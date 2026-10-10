import Foundation

public enum SlowConnectionLocation: String, Codable, Sendable {
    case home, room, device, unknown
}

public enum SlowConnectionUsage: String, Codable, Sendable {
    case all, service, unknown
}

public struct SlowConnectionAnswers: Equatable, Sendable {
    public let location: SlowConnectionLocation?
    public let usage: SlowConnectionUsage?

    public init(location: SlowConnectionLocation? = nil, usage: SlowConnectionUsage? = nil) {
        self.location = location
        self.usage = usage
    }
}

public enum SlowConnectionStep: Equatable, Sendable {
    case question(ConsultationQuestion)
    case proposedComparison(objective: String, conditions: [String])
    case result(ConsultationConclusion, limitations: [String])
}

public enum SlowConnectionLocalJourney {
    public static func next(after answers: SlowConnectionAnswers) -> SlowConnectionStep {
        guard let location = answers.location else {
            return .question(question(
                "question-slow-location",
                "Onde a conexão está lenta?",
                ["Na casa inteira", "Em um cômodo", "Em um aparelho", "Não sei"]
            ))
        }
        guard let usage = answers.usage else {
            return .question(question(
                "question-slow-usage",
                "Acontece em tudo ou só em um app ou serviço?",
                ["Em tudo", "Só em um app ou serviço", "Não sei"]
            ))
        }
        if usage == .service {
            return .result(.insufficient, limitations: ["Um teste geral não comprova o comportamento de um serviço específico."])
        }
        switch location {
        case .room:
            return .proposedComparison(
                objective: "Comparar o local afetado com um ponto próximo ao roteador.",
                conditions: ["Use o mesmo aparelho quando possível.", "Registre o local de cada teste."]
            )
        case .device:
            return .proposedComparison(
                objective: "Comparar outro aparelho no mesmo local e cenário.",
                conditions: ["Não atribua resultado ao segundo aparelho sem medição ou relato explícito."]
            )
        case .home:
            return .proposedComparison(
                objective: "Medir o cenário de forma controlada antes de atribuir uma causa.",
                conditions: ["Registre se a condição ocorre em vários aparelhos."]
            )
        case .unknown:
            return .result(.insufficient, limitations: ["Falta saber onde o problema ocorre para sugerir uma comparação útil."])
        }
    }

    /// Converte somente a opção da pergunta local corrente. Nenhuma resposta
    /// é inferida a partir do rótulo; opções fora da etapa ativa são rejeitadas.
    public static func applying(_ option: QuestionOption, to answers: SlowConnectionAnswers) throws -> SlowConnectionAnswers {
        if answers.location == nil {
            let location: SlowConnectionLocation
            switch option.text {
            case "Na casa inteira": location = .home
            case "Em um cômodo": location = .room
            case "Em um aparelho": location = .device
            case "Não sei": location = .unknown
            default: throw ContractError.invalid("Opção não pertence à triagem de local da conexão.")
            }
            return SlowConnectionAnswers(location: location, usage: answers.usage)
        }
        if answers.usage == nil {
            let usage: SlowConnectionUsage
            switch option.text {
            case "Em tudo": usage = .all
            case "Só em um app ou serviço": usage = .service
            case "Não sei": usage = .unknown
            default: throw ContractError.invalid("Opção não pertence à triagem de uso da conexão.")
            }
            return SlowConnectionAnswers(location: answers.location, usage: usage)
        }
        throw ContractError.invalid("A triagem local de lentidão já foi concluída.")
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
            rationale: "Coletar somente a lacuna necessária."
        )
    }
}
