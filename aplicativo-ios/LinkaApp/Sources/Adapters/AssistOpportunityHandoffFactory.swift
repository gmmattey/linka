#if os(iOS)
import Foundation
import AssistConsultation
import NetworkOptimization

/// Ponte local entre uma oportunidade determinística e o contrato V4.
/// Não lê medições, não abre uma sessão e não decide que o Assist está
/// disponível; esses passos continuam pertencendo ao ponto de integração
/// autorizado. A confiança numérica da oportunidade não atravessa a ponte.
enum AssistOpportunityHandoffFactory {
    static func make(
        opportunity: OptimizationOpportunity,
        baselineMeasurementID: UUID,
        createdAt: Date,
        validatedAt: Date = Date()
    ) throws -> OpportunityHandoff {
        let baseline = try measurementReference(baselineMeasurementID)
        let evidence = try opportunity.evidenceMeasurementIDs.map(measurementReference)
        guard evidence.contains(baseline) else {
            throw ContractError.invalid("A oportunidade precisa incluir a medição de referência.")
        }

        let handoff = OpportunityHandoff(
            opportunityID: try PseudonymousReference(opportunity.id),
            kind: handoffKind(for: opportunity.kind),
            ruleVersion: "optimization/\(opportunity.ruleVersion)",
            baselineMeasurementRef: baseline,
            evidenceMeasurementRefs: evidence,
            suggestedAction: suggestedAction(for: opportunity.action),
            createdAt: createdAt
        )
        try OpportunityHandoffValidator.validateShape(handoff, at: validatedAt)
        return handoff
    }

    private static func measurementReference(_ id: UUID) throws -> PseudonymousReference {
        try PseudonymousReference("measurement-\(id.uuidString.lowercased())")
    }

    private static func handoffKind(for kind: OptimizationOpportunityKind) -> OpportunityHandoffKind {
        switch kind {
        case .responsivenessUnderLoad: .responsivenessUnderLoad
        case .unstableConnection: .unstableConnection
        case .belowUsualQuality: .belowUsualQuality
        }
    }

    private static func suggestedAction(for action: OptimizationGuidedAction) -> OpportunitySuggestedAction {
        switch action {
        case .reduceConcurrentUse: .reduceConcurrentUse
        case .moveCloserToRouter: .moveCloserToRouter
        case .restartRouter: .restartRouter
        }
    }
}
#endif
