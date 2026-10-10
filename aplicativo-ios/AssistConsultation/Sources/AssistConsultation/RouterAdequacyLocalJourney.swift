import Foundation

public enum RouterAssessmentGoal: String, Codable, Sendable {
    case coverage, speed, stability, unknown
}

public enum RouterEvidenceStatus: String, Codable, Sendable {
    case verified, unverified, unavailable
}

public enum RouterNetworkRole: String, Codable, Sendable {
    case mainRouter = "main_router"
    case accessPoint = "access_point"
    case repeater, unknown
}

public struct RouterAdequacyAnswers: Equatable, Sendable {
    public let equipmentSelected: Bool
    public let evidenceStatus: RouterEvidenceStatus?
    public let role: RouterNetworkRole?
    public let goal: RouterAssessmentGoal?

    public init(
        equipmentSelected: Bool = false,
        evidenceStatus: RouterEvidenceStatus? = nil,
        role: RouterNetworkRole? = nil,
        goal: RouterAssessmentGoal? = nil
    ) {
        self.equipmentSelected = equipmentSelected
        self.evidenceStatus = evidenceStatus
        self.role = role
        self.goal = goal
    }
}

public enum RouterAdequacyStep: Equatable, Sendable {
    case question(ConsultationQuestion)
    case requiresVerifiedEvidence(limitations: [String])
    case result(ConsultationConclusion, limitations: [String])
}

/// Triagem local para evitar que um modelo ou uma ficha incompleta tratem um
/// equipamento como adequado ou obsoleto sem identidade, fonte e uso na rede.
public enum RouterAdequacyLocalJourney {
    public static func next(after answers: RouterAdequacyAnswers) -> RouterAdequacyStep {
        guard answers.equipmentSelected else {
            return .question(question(
                "question-router-selection",
                "Qual equipamento você quer avaliar?",
                ["Selecionar um equipamento", "Ainda não sei"]
            ))
        }
        guard let evidenceStatus = answers.evidenceStatus, evidenceStatus == .verified else {
            return .requiresVerifiedEvidence(limitations: [
                "A identidade, a revisão e a fonte do equipamento precisam ser confirmadas antes de avaliar capacidade."
            ])
        }
        guard let role = answers.role, role != .unknown else {
            return .question(question(
                "question-router-role",
                "Qual é o papel desse equipamento na rede?",
                ["Roteador principal", "Ponto de acesso", "Repetidor", "Não sei"]
            ))
        }
        guard let goal = answers.goal, goal != .unknown else {
            return .question(question(
                "question-router-goal",
                "O que você quer melhorar?",
                ["Cobertura", "Velocidade", "Estabilidade", "Não sei"]
            ))
        }

        return .result(.insufficient, limitations: [
            "Ainda faltam medições e condições de uso para concluir se o equipamento atende ao objetivo.",
            "O papel \(role.rawValue) e o objetivo \(goal.rawValue) não comprovam desempenho, throughput ou necessidade de upgrade."
        ])
    }

    private static func question(_ id: String, _ text: String, _ labels: [String]) -> ConsultationQuestion {
        ConsultationQuestion(
            id: try! PseudonymousReference(id),
            text: text,
            options: labels.enumerated().map {
                QuestionOption(
                    id: try! PseudonymousReference("option-\($0.offset)-\(id)"),
                    text: $0.element,
                    kind: $0.element == "Não sei" ? .unknown : .option
                )
            },
            allowUnknown: true,
            rationale: "Coletar apenas a condição necessária para uma avaliação que não invente capacidade."
        )
    }
}
