import Foundation

public enum PlanValuePriority: String, Codable, Sendable {
    case economy, stability, speed, offers, unknown
}

public enum PlanSatisfaction: String, Codable, Sendable {
    case satisfied, dissatisfied, unknown
}

public struct PlanValueAnswers: Equatable, Sendable {
    public let hasDeclaredPlan: Bool
    public let hasDeclaredPrice: Bool
    public let priority: PlanValuePriority?
    public let satisfaction: PlanSatisfaction?
    public let hasComparableMeasurements: Bool?

    public init(
        hasDeclaredPlan: Bool = false,
        hasDeclaredPrice: Bool = false,
        priority: PlanValuePriority? = nil,
        satisfaction: PlanSatisfaction? = nil,
        hasComparableMeasurements: Bool? = nil
    ) {
        self.hasDeclaredPlan = hasDeclaredPlan
        self.hasDeclaredPrice = hasDeclaredPrice
        self.priority = priority
        self.satisfaction = satisfaction
        self.hasComparableMeasurements = hasComparableMeasurements
    }
}

public enum PlanValueStep: Equatable, Sendable {
    case question(ConsultationQuestion)
    case requiresDeclaredPlanData(limitations: [String])
    case requiresComparableMeasurements(limitations: [String])
    case result(ConsultationConclusion, limitations: [String])
}

/// Triagem local de valor do plano. Não consulta catálogos, cobertura ou
/// ofertas e não infere preço/disponibilidade a partir de localização alguma.
public enum PlanValueLocalJourney {
    public static func next(after answers: PlanValueAnswers) -> PlanValueStep {
        guard answers.hasDeclaredPlan, answers.hasDeclaredPrice else {
            return .requiresDeclaredPlanData(limitations: [
                "O plano e o preço atuais precisam ser declarados antes de avaliar valor."
            ])
        }
        guard let priority = answers.priority, priority != .unknown else {
            return .question(question(
                "question-plan-priority",
                "O que mais importa para você?",
                ["Economia", "Estabilidade", "Velocidade", "Entender ofertas", "Não sei"]
            ))
        }
        if priority == .offers {
            return .result(.commercialDataMissing, limitations: [
                "Comparação externa exige fonte, data, cobertura e termos; nenhuma oferta é consultada nesta jornada local."
            ])
        }
        guard let satisfaction = answers.satisfaction, satisfaction != .unknown else {
            return .question(question(
                "question-plan-satisfaction",
                "O plano atual atende ao que você precisa?",
                ["Sim", "Não", "Não sei"]
            ))
        }
        guard answers.hasComparableMeasurements == true else {
            return .requiresComparableMeasurements(limitations: [
                "Faltam medições comparáveis para relacionar o uso percebido ao plano declarado."
            ])
        }

        return .result(.insufficient, limitations: [
            "Mesmo com satisfação \(satisfaction.rawValue) e prioridade \(priority.rawValue), a jornada local não confirma custo-benefício ou alternativa comercial.",
            "Nenhuma disponibilidade, cobertura ou oferta foi consultada."
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
            rationale: "Coletar somente contexto declarado e necessário, sem inferir dados comerciais."
        )
    }
}
