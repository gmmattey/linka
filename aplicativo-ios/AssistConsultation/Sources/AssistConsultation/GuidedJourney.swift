import Foundation

/// Perguntas iniciais locais das quatro jornadas guiadas. Elas não diagnosticam
/// nem executam nada: apenas coletam o menor contexto necessário para o próximo
/// passo da investigação.
public enum GuidedJourney {
    public static func firstQuestion(for intent: ConsultationIntent) -> ConsultationQuestion? {
        switch intent {
        case .slowConnection:
            return question("question-slow-location", "Onde a conexão está lenta?", [
                option("option-slow-home", "Na casa inteira"),
                option("option-slow-room", "Em um cômodo"),
                option("option-slow-device", "Em um aparelho"),
                unknown()
            ], rationale: "A abrangência separa um problema local de uma hipótese mais ampla.")
        case .routerAdequacy:
            return question("question-router-goal", "O que você quer melhorar?", [
                option("option-router-coverage", "Cobertura"),
                option("option-router-speed", "Velocidade"),
                option("option-router-stability", "Estabilidade"),
                unknown()
            ], rationale: "Um modelo cadastrado não prova que o equipamento é inadequado ao objetivo.")
        case .meshNeed:
            return question("question-mesh-location", "Onde a conexão falha?", [
                option("option-mesh-one", "Em um ambiente"),
                option("option-mesh-many", "Em vários ambientes"),
                option("option-mesh-all", "Na casa toda"),
                unknown()
            ], rationale: "Cobertura precisa de contexto antes de sugerir reposicionamento, cabo ou Mesh.")
        case .planValue:
            return question("question-plan-priority", "O que mais importa para você?", [
                option("option-plan-economy", "Economia"),
                option("option-plan-stability", "Estabilidade"),
                option("option-plan-speed", "Velocidade"),
                option("option-plan-offers", "Entender meu plano"),
                unknown()
            ], rationale: "Preço declarado e medição não comprovam oferta ou cobertura disponível.")
        case .openQuestion:
            return nil
        }
    }

    private static func question(_ id: String, _ text: String, _ options: [QuestionOption], rationale: String) -> ConsultationQuestion {
        ConsultationQuestion(id: reference(id), text: text, options: options, allowUnknown: true, rationale: rationale)
    }

    private static func option(_ id: String, _ text: String) -> QuestionOption {
        QuestionOption(id: reference(id), text: text)
    }

    private static func unknown() -> QuestionOption {
        QuestionOption(id: reference("option-unknown"), text: "Não sei", kind: .unknown)
    }

    private static func reference(_ value: String) -> PseudonymousReference { try! PseudonymousReference(value) }
}
