import Foundation
import StoreKit

/// Identificadores de produto do Linka Plus na App Store Connect.
///
/// A validacao de existencia/preco acontece no StoreKit: se o produto nao
/// existir ou nao estiver disponivel, a UI falha fechada e nao libera Plus.
public enum LinkaStoreProductID {
    /// Produto ativo hoje na `PurchaseSheet`: "R$ 19,90/ano".
    public static let plusAnnual = "com.linka.plus.annual"

    /// Reservado para uma futura oferta mensal.
    public static let plusMonthly = "com.linka.plus.monthly"

    public static let all: Set<String> = [plusAnnual, plusMonthly]
}

public enum LinkaPurchaseOutcome: Equatable, Sendable {
    case purchased
    case pending
    case userCancelled
}

public enum LinkaStoreError: Error, Equatable, Sendable {
    case productNotFound(String)
    case verificationFailed
}

/// Provider real de entitlement do Linka Plus, baseado em StoreKit 2.
///
/// Refatorado para lidar exclusivamente com assinaturas auto-renováveis.
/// Ele consulta `Transaction.currentEntitlements` nativamente, e confia
/// no próprio StoreKit para gerenciar a validade (expirationDate), sem
/// necessidade de computar e salvar no UserDefaults a data de validade.
@MainActor
public final class StoreKitEntitlementProvider: ObservableObject, LinkaEntitlementProviding, @unchecked Sendable {
    @Published public private(set) var snapshot: LinkaEntitlementSnapshot = .free

    public enum ProductLoadState: Equatable, Sendable {
        case loading
        case loaded(Product)
        case unavailable
        case error(String)
        
        // Custom Equatable for Product (compares ids since Product itself doesn't conform to Equatable directly in earlier iOS, though it might. We'll implement == just in case or just compare ids)
        public static func == (lhs: ProductLoadState, rhs: ProductLoadState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.unavailable, .unavailable): return true
            case let (.loaded(l), .loaded(r)): return l.id == r.id
            case let (.error(l), .error(r)): return l == r
            default: return false
            }
        }
    }

    @Published public private(set) var productState: ProductLoadState = .loading
    @Published public private(set) var isRefreshingSnapshot = false
    /// Enquanto o StoreKit ainda não respondeu, não carregamos publicidade:
    /// evita mostrar anúncio a uma assinatura paga antes de ela prevalecer
    /// sobre a campanha temporária.
    @Published public private(set) var isEntitlementResolved = false

    private let productID: String
    private let now: @Sendable () -> Date
    private var updatesTask: Task<Void, Never>?
    private var productTask: Task<Void, Never>?

    #if DEBUG
    /// Override restrito a builds de desenvolvimento. Nunca é compilado em
    /// TestFlight/App Store: entitlement de distribuição vem só do StoreKit.
    public static let forcePlusKey = "linkaForcePlus"

    private var isForcePlusEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.forcePlusKey)
    }
    #endif

    public init(
        productID: String = LinkaStoreProductID.plusAnnual,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.productID = productID
        self.now = now

        snapshot = LinkaEntitlementSnapshotResolver.resolve(at: now())

        #if DEBUG
        // Override exclusivamente para testes de desenvolvimento.
        if UserDefaults.standard.bool(forKey: Self.forcePlusKey) {
            snapshot = .plus(status: .active, source: .promotion)
        }
        #endif

        let localProductID = productID
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let transaction = try? Self.checkVerified(update),
                      transaction.productID == localProductID else { continue }
                await transaction.finish()
                await self?.refreshSnapshot()
            }
        }

        productTask = Task { [weak self] in
            await self?.loadProduct()
            await self?.refreshSnapshot()
        }
    }

    deinit {
        updatesTask?.cancel()
        productTask?.cancel()
    }

    // MARK: - LinkaEntitlementProviding

    public func decision(
        for capability: LinkaCapability,
        at date: Date
    ) async -> LinkaAccessDecision {
        LinkaEntitlementPolicy.decision(for: capability, snapshot: snapshot, at: date)
    }

    // MARK: - Compra

    @discardableResult
    public func purchase() async throws -> LinkaPurchaseOutcome {
        let productToPurchase: Product
        if case .loaded(let p) = productState {
            productToPurchase = p
        } else {
            let products = try await Product.products(for: [productID])
            guard let p = products.first else {
                throw LinkaStoreError.productNotFound(productID)
            }
            productToPurchase = p
        }

        let result = try await productToPurchase.purchase()
        return try await handle(result)
    }

    public func loadProduct() async {
        productState = .loading

        do {
            let products = try await Product.products(for: [productID])
            if let firstProduct = products.first {
                productState = .loaded(firstProduct)
            } else {
                productState = .unavailable
            }
        } catch {
            productState = .error(error.localizedDescription)
        }
    }

    @discardableResult
    public func restore() async throws -> Bool {
        try await AppStore.sync()
        await refreshSnapshot()
        return Self.isEntitled(snapshot)
    }

    // MARK: - Estado interno

    /// Recalcula o snapshot a partir de `Transaction.currentEntitlements`.
    /// Como o Linka Plus agora é uma Auto-Renewable Subscription, essa API
    /// do StoreKit 2 é a fonte da verdade sobre se o usuário tem a assinatura
    /// ativa, já lidando com revogações, renovações e carências.
    public func refreshSnapshot() async {
        #if DEBUG
        // Em desenvolvimento, preserva o override explícito do teste.
        guard !isForcePlusEnabled else {
            isEntitlementResolved = true
            return
        }
        #endif
        isRefreshingSnapshot = true
        isEntitlementResolved = false
        defer {
            isRefreshingSnapshot = false
            isEntitlementResolved = true
        }

        var activeTransaction: Transaction?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Self.checkVerified(result),
                  transaction.productID == productID else { continue }
            
            // Com currentEntitlements, a transação que volta aqui
            // representa um entitlement ativo neste exato momento.
            activeTransaction = transaction
        }

        let verifiedPurchase = activeTransaction.map { transaction in
            LinkaEntitlementSnapshot.plus(
                status: .active,
                source: .subscription,
                validUntil: transaction.expirationDate
            )
        }
        snapshot = LinkaEntitlementSnapshotResolver.resolve(verifiedPurchase: verifiedPurchase, at: now())
    }

    func handle(_ result: Product.PurchaseResult) async throws -> LinkaPurchaseOutcome {
        switch result {
        case .success(let verification):
            let transaction = try Self.checkVerified(verification)
            guard transaction.productID == productID else {
                await transaction.finish()
                throw LinkaStoreError.productNotFound(productID)
            }
            await transaction.finish()
            await refreshSnapshot()
            return .purchased
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
    }



    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw LinkaStoreError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    static func isEntitled(_ snapshot: LinkaEntitlementSnapshot) -> Bool {
        snapshot.plan == .plus && snapshot.status == .active
    }

    // MARK: - Override de Plus para testes internos

    #if DEBUG
    public func setForcePlus(_ enabled: Bool) {
        if enabled {
            UserDefaults.standard.set(true, forKey: Self.forcePlusKey)
            snapshot = .plus(status: .active, source: .promotion)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.forcePlusKey)
            snapshot = .free
            Task { await refreshSnapshot() }
        }
    }

    public func debugForcePlus() { setForcePlus(true) }
    public func debugResetToFree() { setForcePlus(false) }
    #endif
}
