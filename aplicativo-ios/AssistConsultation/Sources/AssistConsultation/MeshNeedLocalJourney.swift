import Foundation

public enum MeshAffectedArea: String, Codable, Sendable {
    case one, many, all, unknown
}

public enum CablingAvailability: String, Codable, Sendable {
    case available, unavailable, unknown
}

public enum MeshAlternative: String, Codable, Sendable {
    case reposition, wiredAccessPoint = "wired_access_point", mesh, repeater
}

public struct MeshNeedAnswers: Equatable, Sendable {
    public let affectedArea: MeshAffectedArea?
    public let hasVerifiedCoverageEvidence: Bool?
    public let cabling: CablingAvailability?

    public init(
        affectedArea: MeshAffectedArea? = nil,
        hasVerifiedCoverageEvidence: Bool? = nil,
        cabling: CablingAvailability? = nil
    ) {
        self.affectedArea = affectedArea
        self.hasVerifiedCoverageEvidence = hasVerifiedCoverageEvidence
        self.cabling = cabling
    }
}

public enum MeshNeedStep: Equatable, Sendable {
    case question(ConsultationQuestion)
    case requiresCoverageEvidence(limitations: [String])
    case candidateAlternatives([MeshAlternative], limitations: [String])
    case result(ConsultationConclusion, limitations: [String])
}

/// Esta jornada só organiza alternativas condicionais. Ela não mede sinal,
/// não estima alcance e não transforma o tipo de equipamento em diagnóstico.
public enum MeshNeedLocalJourney {
    public static func next(after answers: MeshNeedAnswers) -> MeshNeedStep {
        guard let affectedArea = answers.affectedArea else {
            return .question(question(
                "question-mesh-area",
                "Onde a conexão falha?",
                ["Em um ambiente", "Em vários ambientes", "Na casa toda", "Não sei"]
            ))
        }
        guard affectedArea != .unknown else {
            return .result(.insufficient, limitations: [
                "Falta saber onde a cobertura falha antes de comparar alternativas."
            ])
        }
        guard answers.hasVerifiedCoverageEvidence == true else {
            return .requiresCoverageEvidence(limitations: [
                "Sem evidência de cobertura, não é possível concluir se reposicionamento, ponto de acesso, repetidor ou Mesh ajudará."
            ])
        }
        guard let cabling = answers.cabling else {
            return .question(question(
                "question-mesh-cabling",
                "Há possibilidade de passar cabo até a área afetada?",
                ["Sim", "Não", "Não sei"]
            ))
        }

        switch cabling {
        case .available:
            return .candidateAlternatives(
                [.reposition, .wiredAccessPoint],
                limitations: ["São alternativas para avaliar; a evidência atual não prova alcance ou resultado."]
            )
        case .unavailable:
            return .candidateAlternatives(
                [.reposition, .mesh, .repeater],
                limitations: ["São alternativas para avaliar; não há promessa de cobertura sem teste no ambiente."]
            )
        case .unknown:
            return .result(.insufficient, limitations: [
                "A possibilidade de cabo ainda é desconhecida, então não há base para priorizar uma alternativa."
            ])
        }
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
            rationale: "Coletar somente o contexto que muda as alternativas seguras."
        )
    }
}
