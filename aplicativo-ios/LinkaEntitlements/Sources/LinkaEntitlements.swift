import Foundation

public enum LinkaPlan: String, Codable, CaseIterable, Sendable {
    case free
    case plus
}

public enum LinkaCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case speedTest
    case history
    case insights
    case assist
    case appleIntegrations
    /// Importação opt-in de telemetria Wi-Fi pelo app Atalhos (issue #134).
    case advancedWiFiDiagnostics
    /// Exibição de jitter, perda de pacotes e resolução DNS ("Modo Expert").
    /// Gate de renderização de UI, não de cálculo — o motor sempre mede
    /// essas métricas independentemente da capability.
    case expertMode
    /// Tela dedicada de diagnóstico de adequação por caso de uso (um
    /// veredito por `UsageCase`, incluindo `workUpload`), além do resumo
    /// estruturado enviado como evidência ao Assist.
    case usageDiagnostics
    /// Sessão pós-medição que encontra oportunidades determinísticas e pede
    /// um reteste comparável. A prévia permanece disponível para o plano
    /// gratuito; aplicar a jornada completa exige Plus.
    case optimization
}

public enum LinkaEntitlementStatus: String, Codable, Sendable {
    case unknown
    case inactive
    case active
    case expired
}

public enum LinkaEntitlementSource: String, Codable, Sendable {
    case free
    case subscription
    case trial
    case promotion
    case lifetime
}

public enum LinkaAccessReason: String, Codable, Sendable {
    case includedInFree
    case activeEntitlement
    case planDoesNotIncludeCapability
    case unknownEntitlement
    case inactiveEntitlement
    case expiredEntitlement
    case invalidSnapshot
}

/// Acesso aos recursos Plus e ausência de anúncios são regras diferentes.
/// A campanha libera recursos, mas não converte a pessoa em assinante pago.
public enum LinkaAdEligibility: Equatable, Sendable {
    case eligibleFree
    case paidPlus
    case unresolvedEntitlement
}

/// Campanha de lançamento: todos os recursos ficam disponíveis sem compra
/// até o fim de 31/10/2026 no horário de São Paulo.
///
/// A data é centralizada para que UI, Atalhos e provedores de dados usem o
/// mesmo limite. Depois dela, a política normal de entitlement volta a valer.
public enum LinkaTemporaryFreeOffer {
    public static let endsAt = Date(timeIntervalSince1970: 1_793_501_999)

    public static func isWithinOfferPeriod(at date: Date) -> Bool {
        date <= endsAt
    }

    public static func isActive(at date: Date = Date()) -> Bool {
        #if os(iOS)
        return isWithinOfferPeriod(at: date)
        #else
        return false
        #endif
    }
}

public struct LinkaEntitlementSnapshot: Codable, Equatable, Sendable {
    public let plan: LinkaPlan
    public let status: LinkaEntitlementStatus
    public let source: LinkaEntitlementSource
    public let validUntil: Date?

    public init(
        plan: LinkaPlan,
        status: LinkaEntitlementStatus,
        source: LinkaEntitlementSource,
        validUntil: Date? = nil
    ) {
        self.plan = plan
        self.status = status
        self.source = source
        self.validUntil = validUntil
    }

    public static let free = LinkaEntitlementSnapshot(
        plan: .free,
        status: .active,
        source: .free
    )

    public static func plus(
        status: LinkaEntitlementStatus,
        source: LinkaEntitlementSource,
        validUntil: Date? = nil
    ) -> LinkaEntitlementSnapshot {
        LinkaEntitlementSnapshot(
            plan: .plus,
            status: status,
            source: source,
            validUntil: validUntil
        )
    }
}

public struct LinkaAccessDecision: Codable, Equatable, Sendable {
    public let capability: LinkaCapability
    public let isGranted: Bool
    public let reason: LinkaAccessReason

    public init(
        capability: LinkaCapability,
        isGranted: Bool,
        reason: LinkaAccessReason
    ) {
        self.capability = capability
        self.isGranted = isGranted
        self.reason = reason
    }
}

public enum LinkaEntitlementPolicy {
    public static func capabilities(for plan: LinkaPlan) -> Set<LinkaCapability> {
        switch plan {
        case .free:
            // MVP: SpeedTest e Histórico inclusos
            return [.speedTest, .history]
        case .plus:
            return Set(LinkaCapability.allCases)
        }
    }

    public static func decision(
        for capability: LinkaCapability,
        snapshot: LinkaEntitlementSnapshot,
        at date: Date = Date()
    ) -> LinkaAccessDecision {
        // A função principal nunca depende do estado do sistema de assinatura.
        if capability == .speedTest || capability == .history {
            return LinkaAccessDecision(
                capability: capability,
                isGranted: true,
                reason: .includedInFree
            )
        }

        guard isStructurallyValid(snapshot) else {
            return denied(capability, reason: .invalidSnapshot)
        }

        guard capabilities(for: snapshot.plan).contains(capability) else {
            return denied(capability, reason: .planDoesNotIncludeCapability)
        }

        switch snapshot.status {
        case .unknown:
            return denied(capability, reason: .unknownEntitlement)
        case .inactive:
            return denied(capability, reason: .inactiveEntitlement)
        case .expired:
            return denied(capability, reason: .expiredEntitlement)
        case .active:
            if let validUntil = snapshot.validUntil, validUntil <= date {
                return denied(capability, reason: .expiredEntitlement)
            }

            return LinkaAccessDecision(
                capability: capability,
                isGranted: true,
                reason: .activeEntitlement
            )
        }
    }

    public static func hasAccess(
        to capability: LinkaCapability,
        snapshot: LinkaEntitlementSnapshot,
        at date: Date = Date()
    ) -> Bool {
        decision(for: capability, snapshot: snapshot, at: date).isGranted
    }

    /// A campanha temporária continua sendo uma experiência Free para fins de
    /// publicidade. Assinaturas, trials do StoreKit e compras vitalícias são
    /// Plus sem anúncios enquanto estiverem válidos.
    public static func adEligibility(
        for snapshot: LinkaEntitlementSnapshot,
        at date: Date = Date()
    ) -> LinkaAdEligibility {
        guard isStructurallyValid(snapshot) else {
            return .unresolvedEntitlement
        }

        guard snapshot.status != .unknown else { return .unresolvedEntitlement }

        guard snapshot.plan == .plus else {
            return .eligibleFree
        }

        guard snapshot.status == .active,
              snapshot.validUntil.map({ $0 > date }) ?? true else {
            return .eligibleFree
        }

        switch snapshot.source {
        case .promotion:
            return .eligibleFree
        case .subscription, .trial, .lifetime:
            return .paidPlus
        case .free:
            return .unresolvedEntitlement
        }
    }

    public static func shouldShowAds(
        for snapshot: LinkaEntitlementSnapshot,
        at date: Date = Date()
    ) -> Bool {
        adEligibility(for: snapshot, at: date) == .eligibleFree
    }

    private static func isStructurallyValid(_ snapshot: LinkaEntitlementSnapshot) -> Bool {
        switch snapshot.plan {
        case .free:
            return snapshot.source == .free && snapshot.validUntil == nil
        case .plus:
            guard snapshot.source != .free else { return false }
            if snapshot.source == .lifetime && snapshot.validUntil != nil {
                return false
            }
            return true
        }
    }

    private static func denied(
        _ capability: LinkaCapability,
        reason: LinkaAccessReason
    ) -> LinkaAccessDecision {
        LinkaAccessDecision(
            capability: capability,
            isGranted: false,
            reason: reason
        )
    }
}

public protocol LinkaEntitlementProviding: Sendable {
    func decision(
        for capability: LinkaCapability,
        at date: Date
    ) async -> LinkaAccessDecision
}

public extension LinkaEntitlementProviding {
    func hasAccess(
        to capability: LinkaCapability,
        at date: Date = Date()
    ) async -> Bool {
        await decision(for: capability, at: date).isGranted
    }
}

public struct StaticLinkaEntitlementProvider: LinkaEntitlementProviding {
    public let snapshot: LinkaEntitlementSnapshot

    public init(snapshot: LinkaEntitlementSnapshot) {
        self.snapshot = snapshot
    }

    public func decision(
        for capability: LinkaCapability,
        at date: Date
    ) async -> LinkaAccessDecision {
        LinkaEntitlementPolicy.decision(
            for: capability,
            snapshot: snapshot,
            at: date
        )
    }
}
