import Foundation

public enum LocalActionStatus: String, Codable, CaseIterable, Sendable {
    case pending, completed, ignored, unavailable
}

/// Estado efêmero de uma ação apresentada na sessão atual. Persistir, exportar
/// ou enviar esse registro é responsabilidade de uma etapa com autorização própria.
public struct LocalActionProgress: Equatable, Sendable {
    public let actionID: PseudonymousReference
    public let status: LocalActionStatus
    public let confirmedAt: Date?
    public let evidenceRef: PseudonymousReference?

    public init(
        actionID: PseudonymousReference,
        status: LocalActionStatus,
        confirmedAt: Date? = nil,
        evidenceRef: PseudonymousReference? = nil
    ) {
        self.actionID = actionID
        self.status = status
        self.confirmedAt = confirmedAt
        self.evidenceRef = evidenceRef
    }
}

public struct RetestComparisonConditions: Equatable, Sendable {
    public let baselineMeasurementRef: PseudonymousReference
    public let retestMeasurementRef: PseudonymousReference
    public let sameInterface: Bool
    public let sameEnvironment: Bool
    public let sameMethod: Bool
    public let sameDevice: Bool
    public let comparablePeriod: Bool

    public init(
        baselineMeasurementRef: PseudonymousReference,
        retestMeasurementRef: PseudonymousReference,
        sameInterface: Bool,
        sameEnvironment: Bool,
        sameMethod: Bool,
        sameDevice: Bool,
        comparablePeriod: Bool
    ) {
        self.baselineMeasurementRef = baselineMeasurementRef
        self.retestMeasurementRef = retestMeasurementRef
        self.sameInterface = sameInterface
        self.sameEnvironment = sameEnvironment
        self.sameMethod = sameMethod
        self.sameDevice = sameDevice
        self.comparablePeriod = comparablePeriod
    }
}

public enum RetestComparisonDisposition: Equatable, Sendable {
    case comparable
    case inconclusive(limitations: [String])
}

/// Valida o acompanhamento dentro da memória da sessão, sem executar teste ou
/// reter dados. Um reteste só pode ser comparado quando as condições declaradas
/// são compatíveis; do contrário, permanece inconclusivo.
public enum ActionRetestLocalPolicy {
    public static func validate(_ progress: LocalActionProgress, at now: Date) throws {
        switch progress.status {
        case .pending:
            guard progress.confirmedAt == nil, progress.evidenceRef == nil else {
                throw ContractError.invalid("Ação pendente não pode registrar confirmação ou evidência.")
            }
        case .completed, .ignored, .unavailable:
            guard let confirmedAt = progress.confirmedAt, confirmedAt <= now else {
                throw ContractError.invalid("Ação finalizada requer confirmação explícita com data válida.")
            }
        }
    }

    public static func evaluate(_ conditions: RetestComparisonConditions) -> RetestComparisonDisposition {
        var limitations: [String] = []
        if conditions.baselineMeasurementRef == conditions.retestMeasurementRef {
            limitations.append("O reteste precisa referenciar uma medição diferente da linha de base.")
        }
        if !conditions.sameInterface { limitations.append("A interface de rede mudou.") }
        if !conditions.sameEnvironment { limitations.append("O ambiente mudou.") }
        if !conditions.sameMethod { limitations.append("O método de medição mudou.") }
        if !conditions.sameDevice { limitations.append("O aparelho mudou.") }
        if !conditions.comparablePeriod { limitations.append("O período não é comparável.") }
        return limitations.isEmpty ? .comparable : .inconclusive(limitations: limitations)
    }
}
