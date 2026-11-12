import Foundation

public enum SlowConnectionLocation: String, Codable, Sendable {
    case home, room, device, unknown
}

public enum SlowConnectionUsage: String, Codable, Sendable {
    case all, service, unknown
}

public enum SlowConnectionTiming: String, Codable, Sendable {
    case continuous, certainTimes, intermittent, unknown
}

public enum SlowConnectionAccess: String, Codable, Sendable {
    case wifi, cable, other, unknown
}

public struct SlowConnectionAnswers: Equatable, Sendable {
    public let location: SlowConnectionLocation?
    public let usage: SlowConnectionUsage?
    public let timing: SlowConnectionTiming?
    public let access: SlowConnectionAccess?

    public init(
        location: SlowConnectionLocation? = nil,
        usage: SlowConnectionUsage? = nil,
        timing: SlowConnectionTiming? = nil,
        access: SlowConnectionAccess? = nil
    ) {
        self.location = location
        self.usage = usage
        self.timing = timing
        self.access = access
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
        guard location != .unknown else {
            return .result(.insufficient, limitations: ["Falta saber onde o problema ocorre para sugerir uma comparação útil."])
        }
        guard usage != .unknown else {
            return .result(.insufficient, limitations: ["Falta saber se a lentidão afeta a conexão inteira ou só um serviço para propor um teste útil."])
        }
        guard let timing = answers.timing else {
            return .question(question(
                "question-slow-timing",
                "Quando a lentidão acontece mais?",
                ["O tempo todo", "Em certos horários", "Vai e volta", "Não sei"]
            ))
        }
        guard let access = answers.access else {
            return .question(question(
                "question-slow-access",
                "Como este aparelho está conectado agora?",
                ["Wi-Fi", "Cabo de rede", "Dados móveis ou outra conexão", "Não sei"]
            ))
        }
        if access == .other {
            return .result(.insufficient, limitations: ["Esta comparação local é voltada à rede doméstica por Wi-Fi ou cabo. A conexão atual não permite separar a rede local de outra conexão."])
        }
        if usage == .service {
            return .result(.insufficient, limitations: ["Mesmo com este contexto, um teste geral não comprova o comportamento de um serviço específico."])
        }
        if access == .unknown {
            return .result(.insufficient, limitations: ["Falta saber se o aparelho está no Wi-Fi ou no cabo para escolher uma comparação controlada."])
        }

        var conditions = [
            timingCondition(timing),
            "Use o mesmo aparelho e o mesmo serviço quando possível.",
            "Esse passo não separa LAN, Internet, DNS ou operadora sem resultados de testes elegíveis."
        ]
        switch (location, access) {
        case (.room, .wifi):
            conditions.insert("No Wi-Fi, compare o mesmo aparelho no cômodo afetado e perto do roteador.", at: 0)
        case (.room, .cable):
            conditions.insert("No cabo, compare o mesmo aparelho e cabo em um ponto conhecido da casa.", at: 0)
        case (.device, .wifi):
            conditions.insert("No Wi-Fi, compare outro aparelho no mesmo local antes de atribuir a causa ao aparelho ou à rede.", at: 0)
        case (.device, .cable):
            conditions.insert("No cabo, compare outro cabo ou aparelho conhecido no mesmo ponto antes de atribuir a causa.", at: 0)
        case (.home, .wifi):
            conditions.insert("No Wi-Fi, compare dois aparelhos em locais próximos ao roteador antes de concluir que o problema é mais amplo.", at: 0)
        case (.home, .cable):
            conditions.insert("No cabo, compare um segundo aparelho ou cabo conhecido antes de concluir que o problema é mais amplo.", at: 0)
        default:
            return .result(.insufficient, limitations: ["Falta contexto suficiente para propor uma comparação controlada."])
        }
        return .proposedComparison(
            objective: "Registrar uma comparação controlada antes de atribuir uma causa à lentidão.",
            conditions: conditions
        )
    }

    private static func timingCondition(_ timing: SlowConnectionTiming) -> String {
        switch timing {
        case .continuous:
            return "Faça a comparação agora e registre que a lentidão foi declarada como contínua."
        case .certainTimes:
            return "Repita a comparação no horário em que a lentidão costuma aparecer e registre o horário."
        case .intermittent:
            return "Repita a comparação quando a lentidão reaparecer e registre o horário."
        case .unknown:
            return "Registre o horário da comparação; sem esse dado não há padrão temporal confirmado."
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
            return SlowConnectionAnswers(location: location, usage: answers.usage, timing: answers.timing, access: answers.access)
        }
        if answers.usage == nil {
            let usage: SlowConnectionUsage
            switch option.text {
            case "Em tudo": usage = .all
            case "Só em um app ou serviço": usage = .service
            case "Não sei": usage = .unknown
            default: throw ContractError.invalid("Opção não pertence à triagem de uso da conexão.")
            }
            return SlowConnectionAnswers(location: answers.location, usage: usage, timing: answers.timing, access: answers.access)
        }
        if answers.location == .unknown || answers.usage == .unknown {
            throw ContractError.invalid("A triagem local de lentidão já atingiu seu limite de evidência.")
        }
        if answers.timing == nil {
            let timing: SlowConnectionTiming
            switch option.text {
            case "O tempo todo": timing = .continuous
            case "Em certos horários": timing = .certainTimes
            case "Vai e volta": timing = .intermittent
            case "Não sei": timing = .unknown
            default: throw ContractError.invalid("Opção não pertence à triagem de horário da conexão.")
            }
            return SlowConnectionAnswers(location: answers.location, usage: answers.usage, timing: timing, access: answers.access)
        }
        if answers.access == nil {
            let access: SlowConnectionAccess
            switch option.text {
            case "Wi-Fi": access = .wifi
            case "Cabo de rede": access = .cable
            case "Dados móveis ou outra conexão": access = .other
            case "Não sei": access = .unknown
            default: throw ContractError.invalid("Opção não pertence à triagem de conexão atual.")
            }
            return SlowConnectionAnswers(location: answers.location, usage: answers.usage, timing: answers.timing, access: access)
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
