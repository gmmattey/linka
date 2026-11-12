import Foundation

public enum OpportunityHandoffKind: String, Codable, CaseIterable, Sendable {
    case responsivenessUnderLoad = "responsiveness_under_load"
    case unstableConnection = "unstable_connection"
    case belowUsualQuality = "below_usual_quality"
}

public enum OpportunitySuggestedAction: String, Codable, CaseIterable, Sendable {
    case reduceConcurrentUse = "reduce_concurrent_use"
    case moveCloserToRouter = "move_closer_to_router"
    case restartRouter = "restart_router"
}

/// Projeção pseudonimizada e local de uma oportunidade determinística.
/// Ela não recria regras, não carrega medições e não inicia sessão, transporte
/// ou ação. A camada de integração deve validar as referências antes do uso.
public struct OpportunityHandoff: Codable, Equatable, Sendable {
    public let opportunityID: PseudonymousReference
    public let kind: OpportunityHandoffKind
    public let ruleVersion: String
    public let baselineMeasurementRef: PseudonymousReference
    public let evidenceMeasurementRefs: [PseudonymousReference]
    public let suggestedAction: OpportunitySuggestedAction
    public let createdAt: Date

    public init(
        opportunityID: PseudonymousReference,
        kind: OpportunityHandoffKind,
        ruleVersion: String,
        baselineMeasurementRef: PseudonymousReference,
        evidenceMeasurementRefs: [PseudonymousReference],
        suggestedAction: OpportunitySuggestedAction,
        createdAt: Date
    ) {
        self.opportunityID = opportunityID
        self.kind = kind
        self.ruleVersion = ruleVersion
        self.baselineMeasurementRef = baselineMeasurementRef
        self.evidenceMeasurementRefs = evidenceMeasurementRefs
        self.suggestedAction = suggestedAction
        self.createdAt = createdAt
    }
}

public enum OpportunityHandoffDisposition: Equatable, Sendable {
    case eligible
    case unavailable(limitations: [String])
}

public enum OpportunityHandoffValidator {
    public static func validateShape(_ handoff: OpportunityHandoff, at now: Date) throws {
        guard !handoff.ruleVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              handoff.ruleVersion.unicodeScalars.count <= 120,
              !handoff.evidenceMeasurementRefs.isEmpty,
              Set(handoff.evidenceMeasurementRefs).count == handoff.evidenceMeasurementRefs.count,
              handoff.evidenceMeasurementRefs.contains(handoff.baselineMeasurementRef),
              handoff.createdAt <= now else {
            throw ContractError.invalid("Handoff de oportunidade inválido.")
        }
    }

    /// Revalidação pura no destino. A integração fornece apenas referências
    /// já elegíveis na sessão atual; nenhuma medição é lida nem enviada aqui.
    public static func revalidate(
        _ handoff: OpportunityHandoff,
        availableMeasurementRefs: Set<PseudonymousReference>,
        eligibleMeasurementRefs: Set<PseudonymousReference>,
        contextMatches: Bool,
        acceptedRuleVersions: Set<String>,
        maximumAge: TimeInterval,
        at now: Date
    ) -> OpportunityHandoffDisposition {
        var limitations: [String] = []
        if handoff.createdAt > now || now.timeIntervalSince(handoff.createdAt) > maximumAge {
            limitations.append("A oportunidade está antiga e precisa ser reavaliada.")
        }
        if !acceptedRuleVersions.contains(handoff.ruleVersion) {
            limitations.append("A versão da regra não é aceita neste contexto.")
        }
        if !availableMeasurementRefs.isSuperset(of: Set(handoff.evidenceMeasurementRefs)) {
            limitations.append("Uma medição usada pela oportunidade não está mais disponível.")
        }
        if !eligibleMeasurementRefs.isSuperset(of: Set(handoff.evidenceMeasurementRefs)) {
            limitations.append("Uma medição usada pela oportunidade não é elegível para esta investigação.")
        }
        if !contextMatches {
            limitations.append("O contexto da rede mudou desde a oportunidade.")
        }
        return limitations.isEmpty ? .eligible : .unavailable(limitations: limitations)
    }
}
