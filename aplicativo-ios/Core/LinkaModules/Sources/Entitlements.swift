import Foundation
import LinkaEntitlements
import NetworkAssist
import NetworkInsights

/// Contrato legado preservado apenas para a fundação inicial de `LinkaModules`.
/// Código novo deve depender de `LinkaEntitlementProviding`.
public protocol EntitlementProviding: Sendable {
    func hasAccess(to capability: LinkaCapability) async -> Bool
}

/// Compatibilidade com a API inicial free/plus.
/// A política canônica vive em `LinkaEntitlementPolicy`.
public enum LinkaAccessPolicy {
    public static func capabilities(for tier: LinkaTier) -> Set<LinkaCapability> {
        LinkaEntitlementPolicy.capabilities(for: tier)
    }

    public static func hasAccess(
        to capability: LinkaCapability,
        on tier: LinkaTier
    ) -> Bool {
        capabilities(for: tier).contains(capability)
    }
}

/// Provider legado que traduz tier para um snapshot estático.
/// Não representa StoreKit nem estado real de assinatura.
///
/// A fonte real de produção é `LinkaEntitlements.StoreKitEntitlementProvider`
/// (issue #60). Este tipo permanece apenas como utilitário legado/base para
/// atalhos `#if DEBUG` — nunca use para representar uma compra real.
public struct StaticEntitlementProvider: EntitlementProviding {
    private let provider: StaticLinkaEntitlementProvider

    public init(tier: LinkaTier) {
        let snapshot: LinkaEntitlementSnapshot
        switch tier {
        case .free:
            snapshot = .free
        case .plus:
            snapshot = .plus(status: .active, source: .subscription)
        }
        self.provider = StaticLinkaEntitlementProvider(snapshot: snapshot)
    }

    public func hasAccess(to capability: LinkaCapability) async -> Bool {
        await provider.hasAccess(to: capability)
    }
}

// MARK: - Gates de entitlement para consumidores de interpretação

/// Envolve um `NetworkInsightsAnalyzing` para que Insights (comparações,
/// estatísticas, tendências) consulte a mesma política de entitlement usada
/// em todo o app antes de calcular qualquer coisa. `NetworkInsights` em si
/// permanece um pacote de cálculo puro, sem dependência de entitlement —
/// o gate vive aqui, na camada de agregação (`LinkaModules`), para não
/// acoplar o motor de análise à política de acesso.
///
/// `snapshot` é capturado como valor (não como closure/provider) porque
/// `NetworkInsightsAnalyzing` é síncrono — o chamador lê o snapshot atual
/// (ex.: `StoreKitEntitlementProvider.snapshot`, já publicado sem round-trip
/// de rede) e passa o valor no momento da chamada.
public struct EntitlementGatedNetworkInsightsAnalyzer: NetworkInsightsAnalyzing {
    private let analyzer: any NetworkInsightsAnalyzing
    private let snapshot: LinkaEntitlementSnapshot

    public init(
        wrapping analyzer: any NetworkInsightsAnalyzing,
        snapshot: LinkaEntitlementSnapshot
    ) {
        self.analyzer = analyzer
        self.snapshot = snapshot
    }

    public func compare(
        current: NetworkMeasurement,
        against baseline: NetworkMeasurement
    ) throws -> NetworkMeasurementComparison {
        try requireInsightsAccess()
        return try analyzer.compare(current: current, against: baseline)
    }

    public func summarize(_ measurements: [NetworkMeasurement]) throws -> NetworkInsightsSummary {
        try requireInsightsAccess()
        return try analyzer.summarize(measurements)
    }

    public func comparePeriods(
        current: [NetworkMeasurement],
        baseline: [NetworkMeasurement]
    ) throws -> NetworkPeriodComparison {
        try requireInsightsAccess()
        return try analyzer.comparePeriods(current: current, baseline: baseline)
    }

    private func requireInsightsAccess() throws {
        let decision = LinkaEntitlementPolicy.decision(for: .insights, snapshot: snapshot)
        guard decision.isGranted else {
            throw NetworkInsightsError.notEntitled
        }
    }
}

/// Envolve um `NetworkAssistProviding` para que o Assist consulte a mesma
/// política de entitlement antes de responder. Este gate é ortogonal ao
/// feature flag `AssistContainer.isRemoteAssistEnabled()`: um controla se o
/// transport remoto está configurado neste build; o outro controla se o
/// usuário tem direito a usar o Assist. Os dois nunca devem se confundir —
/// o gate de entitlement roda primeiro e não interfere na resposta
/// "Assist não configurado" quando o transport remoto está desligado.
///
/// `snapshot` é uma closure `async` (e não um valor capturado) porque este
/// provider costuma ser construído uma vez e reutilizado em várias chamadas
/// — cada resposta precisa reavaliar o plano *atual* do usuário, não o
/// plano no momento em que o provider foi montado. `async` também permite
/// ler com segurança uma propriedade isolada em `@MainActor`
/// (`StoreKitEntitlementProvider.snapshot`) a partir de um contexto que não
/// é necessariamente o MainActor.
public struct EntitlementGatedNetworkAssistProvider: NetworkAssistProviding {
    private let provider: any NetworkAssistProviding
    private let snapshot: @Sendable () async -> LinkaEntitlementSnapshot

    public init(
        wrapping provider: any NetworkAssistProviding,
        snapshot: @escaping @Sendable () async -> LinkaEntitlementSnapshot
    ) {
        self.provider = provider
        self.snapshot = snapshot
    }

    public func answer(_ context: NetworkAssistContext) async throws -> NetworkAssistResponse {
        try await requireAccess()
        return try await provider.answer(context)
    }

    /// Caminho de streaming (issue #69) — o gate de entitlement roda uma
    /// única vez, antes de qualquer evento (`.progress`/`.textDelta`/
    /// `.completed`) ser observado pelo chamador, nunca no meio do stream.
    /// Repassa para `provider.streamAnswer` (e não para o bridge default do
    /// protocolo) para preservar streaming real quando o provider envolvido
    /// sabe streamar de verdade — usar o bridge aqui perderia esse
    /// comportamento mesmo quando o provider por baixo transmite eventos
    /// progressivos de verdade.
    public func streamAnswer(_ context: NetworkAssistContext) -> AsyncThrowingStream<NetworkAssistStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await requireAccess()
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                do {
                    for try await event in provider.streamAnswer(context) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func requireAccess() async throws {
        let decision = LinkaEntitlementPolicy.decision(for: .assist, snapshot: await snapshot())
        guard decision.isGranted else {
            throw NetworkAssistError.notEntitled
        }
    }
}
