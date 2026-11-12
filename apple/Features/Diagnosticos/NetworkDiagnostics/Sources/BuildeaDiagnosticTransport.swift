import Foundation
import NetworkAssist
import NetworkCore

public struct BuildeaDiagnosticTransport: NetworkAssistTransport {
    public let api: BuildeaDiagnosticAPI
    private let coordinator = DiagnosticCopyCoordinator()

    public init(api: BuildeaDiagnosticAPI) {
        self.api = api
    }

    public func answer(_ request: NetworkAssistRequest) async throws -> NetworkAssistResponse {
        // Fluxo guiado (`AssistProblemSelectionView`) tem prioridade sobre o
        // resumo de uso sintetizado (`usageContext`): quando o usuário
        // passou pela seleção, `objective`/`subcategory` são as chaves
        // fechadas do contrato v2, não um texto livre derivado da medição.
        // Sem seleção guiada, o comportamento observacional de hoje
        // continua idêntico — só `objective` (texto de `usageContext`),
        // sem `subcategory`. "Outro problema" (texto livre) chega em
        // `request.reportedProblem` sem `objective`/`subcategory` — vai só
        // como `reported_problem`, que o NDS usa como contexto adicional
        // para a IA na explicação, NUNCA para priorizar regras (isso
        // continua vindo só de objective/subcategory/métricas). Toda
        // requisição vai sempre para o endpoint v2 (`BuildeaDiagnosticAPI`
        // não tem mais fallback v1).
        let diagnosticContext: NDSRequest.DiagnosticContext?
        if let objective = request.objective {
            diagnosticContext = NDSRequest.DiagnosticContext(
                reportedProblem: request.reportedProblem,
                objective: objective,
                subcategory: request.subcategory
            )
        } else if let reportedProblem = request.reportedProblem {
            diagnosticContext = NDSRequest.DiagnosticContext(reportedProblem: reportedProblem)
        } else if let usageContext = request.usageContext {
            diagnosticContext = NDSRequest.DiagnosticContext(objective: usageContext)
        } else {
            diagnosticContext = nil
        }
        let ndsResponse = try await api.evaluate(
            request.currentMeasurement,
            requestAI: true,
            locale: request.locale,
            diagnosticContext: diagnosticContext
        )
        
        // `effectiveResults`/`effectiveRecommendation` leem do bloco `raw`
        // quando a resposta é v2 (`raw.results`/`raw.recommendation`) e do
        // nível raiz quando é v1 — mesmo achado, mesma dimensão de
        // scoring, independente de qual contrato respondeu.
        let results = ndsResponse.effectiveResults
        let scoringModule = results?.first(where: { $0.module == "scoring" })?.result
        let score = scoringModule?.score
        let veredicto = scoringModule?.veredicto
        let findings = results?.compactMap { $0.cards }.flatMap { $0 } ?? []

        let copy: DiagnosticCopy
        let aiAttribution: String?
        if let v2Explanation = ndsResponse.explanation {
            // Contrato v2: texto já tratado pelo servidor
            // (`explanation.titulo`/`descricao`/`dados`/`acao_usuario`),
            // sem passar pelo coordenador de copy v1 (esse texto não é
            // "AI" nem "determinístico" no sentido do v1 — já chega
            // pronto). `sem_causa_identificada == true` é tratado à parte
            // (AGENTS.md §9 — nunca inventar causa sem lastro).
            copy = Self.copy(fromV2Explanation: v2Explanation, locale: request.locale)
            aiAttribution = Self.formatProvenance(v2Explanation.provenance)
        } else {
            let aiResult = results?.first(where: { $0.module == "ai" })?.result
            let aiExplanation = aiResult?.explanation

            let input = DiagnosticCopyInput(
                recommendationTitle: ndsResponse.effectiveRecommendation?.title,
                recommendationDescription: ndsResponse.effectiveRecommendation?.description,
                score: score,
                findings: findings,
                aiTitle: aiExplanation?.tituloAmigavel,
                aiSummary: aiExplanation?.resumoTecnicoTraduzido,
                veredicto: veredicto,
                aiSourceFindingIds: aiResult?.sourceFindingIds,
                locale: request.locale
            )
            copy = await coordinator.resolveCopy(for: input)
            if copy.source == .ai {
                aiAttribution = Self.formatProvenance(NDSExplanationProvenance(source: "ai", modelLabel: aiResult?.aiModelUsed))
            } else {
                aiAttribution = nil
            }
        }

        let evidenceIDs = [NetworkAssistRequest.currentMeasurementEvidenceID(request.currentMeasurement.id)]
        
        // headerStatus não pode olhar só o veredicto: um veredicto "bom"
        // com achados de atenção/crítico (ex.: latência oscilando) ainda
        // é "tudo certo" no header enquanto a IA descreve o problema no
        // resumo — a tela contradizia a si mesma. Mesmo critério do
        // fallback determinístico (`isHealthyScore && !hasProblemCards`).
        let hasProblemCards = findings.contains { $0.status == "attention" || $0.status == "critical" }
        let isHealthyVerdict = veredicto == "bom" || veredicto == "excelente" || (veredicto == nil && !hasProblemCards)
        let isSemCausa = ndsResponse.explanation?.semCausaIdentificada == true
        let headerStatus = Self.headerStatus(
            isHealthy: isSemCausa || (!hasProblemCards && isHealthyVerdict),
            locale: request.locale
        )
        
        var parsedRecommendation: NetworkAssistRecommendation? = nil
        if let v2Explanation = ndsResponse.explanation {
            // `acao_usuario` é a ação; `dados` é a evidência que sustenta
            // essa ação, mostrada em "Por que recomendamos isso?" na
            // `AssistView` — mesmo papel que `description` já cumpre para
            // uma recomendação v1. `sem_causa_identificada == true` não
            // tem ação a recomendar: nenhuma regra disparou.
            if v2Explanation.semCausaIdentificada != true, let acao = v2Explanation.acaoUsuario {
                let evidenceCards = findings.filter { card in v2Explanation.dados?.contains(card.id) == true }
                // Os findings determinísticos ainda podem chegar no idioma
                // canônico do serviço. Eles não podem ser encaixados numa
                // explicação em inglês/espanhol, pois isso mistura idiomas
                // dentro do mesmo cartão. As dimensões abaixo continuam
                // expondo a evidência com rótulos locais; a descrição bruta
                // só é segura para a localidade canônica pt-BR.
                let isPortuguese = (request.locale ?? "pt-BR").lowercased().hasPrefix("pt")
                let evidenceDesc: String
                if !isPortuguese {
                    evidenceDesc = ""
                } else if evidenceCards.isEmpty {
                    evidenceDesc = v2Explanation.dados?.joined(separator: ", ") ?? ""
                } else {
                    evidenceDesc = evidenceCards
                        .map { $0.mensagemUsuario.isEmpty ? $0.titulo : $0.mensagemUsuario }
                        .joined(separator: " • ")
                }

                parsedRecommendation = NetworkAssistRecommendation(
                    title: acao,
                    description: evidenceDesc,
                    steps: []
                )
            }
        } else if let rec = ndsResponse.effectiveRecommendation {
            parsedRecommendation = NetworkAssistRecommendation(
                title: rec.title,
                description: rec.description,
                steps: rec.steps
            )
        }
        
        var mappedDimensions: [NetworkAssistDimension]? = nil
        if let dimensoes = scoringModule?.dimensoes, !dimensoes.isEmpty {
            mappedDimensions = dimensoes.map { NetworkAssistDimension(name: $0.nome, status: $0.status) }
        }
        
        return NetworkAssistResponse(
            text: copy.title,
            longText: copy.summary,
            disposition: .answered,
            evidenceIDs: evidenceIDs,
            suggestions: nil,
            headerStatus: headerStatus,
            title: copy.title,
            summary: copy.summary,
            recommendation: parsedRecommendation,
            dimensions: mappedDimensions,
            aiAttribution: aiAttribution
        )
    }

    /// `explanation.sem_causa_identificada == true` quer dizer que nenhuma
    /// regra de problema do NDS disparou para esta medição+subcategoria —
    /// o mesmo caso em que `headerStatus` já mostra "✓ TUDO CERTO" (ver
    /// `answer(_:)` acima). O resumo precisa soar como o resultado positivo
    /// que ele é, não como um diagnóstico inconclusivo: ainda assim nunca
    /// inventa uma causa que os dados não sustentam (AGENTS.md §9), só
    /// afirma a ausência de problema, que é exatamente o que os dados
    /// mostram.
    /// Fallback para quando o NDS retorna `explanation` sem
    /// `sem_causa_identificada` mas também sem `titulo`/`descricao` (rollout
    /// parcial do contrato v2). Diferente do caso acima, aqui não há
    /// garantia de que a conexão está saudável — só que o servidor não
    /// mandou texto pronto — então mantém o tom transparente de
    /// indisponibilidade em vez do texto positivo.
    /// Constrói o `DiagnosticCopy` a partir do bloco `explanation` do
    /// contrato v2. `titulo`/`descricao` podem faltar mesmo sem
    /// `sem_causa_identificada` (o NDS ainda está em implementação em
    /// paralelo) — nesse caso caímos no texto de fallback em vez de
    /// apresentar título/resumo vazios.
    static func copy(fromV2Explanation explanation: NDSV2Explanation, locale: String?) -> DiagnosticCopy {
        if explanation.semCausaIdentificada == true {
            let fallback = localFallback(.noProblemFound, locale: locale)
            return DiagnosticCopy(
                title: fallback.title,
                summary: fallback.summary,
                source: .deterministic
            )
        }
        guard let titulo = explanation.titulo, let descricao = explanation.descricao else {
            let fallback = localFallback(.missingExplanation, locale: locale)
            return DiagnosticCopy(
                title: fallback.title,
                summary: fallback.summary,
                source: .deterministic
            )
        }
        return DiagnosticCopy(title: titulo, summary: descricao, source: .deterministic)
    }

    /// The server remains authoritative whenever it supplies an explanation.
    /// These are only semantic, client-local fallbacks for incomplete V2
    /// responses, selected with the same BCP-47 tag sent to the relay.
    private enum LocalFallback {
        case noProblemFound
        case missingExplanation
    }

    private static func localFallback(_ fallback: LocalFallback, locale: String?) -> (title: String, summary: String) {
        switch (locale ?? "pt-BR").lowercased() {
        case let tag where tag.hasPrefix("es"):
            switch fallback {
            case .noProblemFound:
                return ("Todo funciona normalmente", "No identificamos problemas en tu conexión. Todo parece normal.")
            case .missingExplanation:
                return ("No se identificó una causa específica", "No encontramos una causa específica. Inténtalo de nuevo más tarde.")
            }
        case let tag where tag.hasPrefix("en"):
            switch fallback {
            case .noProblemFound:
                return ("Everything is working normally", "We found no problems with your connection. Everything looks normal.")
            case .missingExplanation:
                return ("No specific cause identified", "We couldn't identify a specific cause. Please try again later.")
            }
        default:
            switch fallback {
            case .noProblemFound:
                return ("Tudo funcionando normalmente", "Não há problemas identificados na sua conexão. Tudo parece normal.")
            case .missingExplanation:
                return ("Sem causa específica identificada", "Não foi possível identificar uma causa específica. Tente novamente mais tarde.")
            }
        }
    }

    private static func headerStatus(isHealthy: Bool, locale: String?) -> String {
        switch (locale ?? "pt-BR").lowercased() {
        case let tag where tag.hasPrefix("es"):
            return isHealthy ? "✓ TODO BIEN" : "⚠ REQUIERE ATENCIÓN"
        case let tag where tag.hasPrefix("en"):
            return isHealthy ? "✓ ALL GOOD" : "⚠ NEEDS ATTENTION"
        default:
            return isHealthy ? "✓ TUDO CERTO" : "⚠ PRECISA DE ATENÇÃO"
        }
    }

    public static func formatProvenance(_ provenance: NDSExplanationProvenance?) -> String? {
        guard let provenance, provenance.source == "ai" || provenance.source == "copy_catalog" else {
            return nil
        }
        guard let modelLabel = provenance.modelLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !modelLabel.isEmpty else {
            return "ChatGPT – Luna"
        }
        let lower = modelLabel.lowercased()
        if lower.contains("luna") {
            return "ChatGPT – Luna"
        } else if lower.hasPrefix("gpt-") {
            return "ChatGPT (\(modelLabel))"
        } else if lower.hasPrefix("gemini") {
            return "Gemini (\(modelLabel))"
        } else if lower.contains("claude") {
            return "Claude (\(modelLabel))"
        } else if lower.hasPrefix("@cf/") {
            return "Workers AI"
        } else {
            return modelLabel
        }
    }

}
