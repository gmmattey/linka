import XCTest
@testable import NetworkDiagnostics

/// Cobre a blindagem contra explicação de IA sem evidência (issue #129):
/// o módulo `ai` do NDS pode afirmar um problema sem nenhum achado que o
/// sustente — confirmado testando o serviço real. Um veredito não
/// bom/excelente sem `source_finding_ids` precisa cair no fallback
/// determinístico, nunca repassar a afirmação sem lastro ao usuário.
final class DiagnosticCopyCoordinatorTests: XCTestCase {
    func testAIRendererAcceptsExplanationWhenFindingsSupportIt() async throws {
        let input = DiagnosticCopyInput(
            recommendationTitle: nil,
            recommendationDescription: nil,
            score: 45,
            findings: [],
            aiTitle: "Sua conexão apresenta instabilidade",
            aiSummary: "Notamos perda de pacotes.",
            veredicto: "regular",
            aiSourceFindingIds: ["packet_loss_critical"]
        )

        let copy = try await NDSAIDiagnosticCopyRenderer().render(input: input)

        XCTAssertEqual(copy.source, .ai)
        XCTAssertEqual(copy.title, "Sua conexão apresenta instabilidade")
    }

    /// Caso real reproduzido na issue #129: medição só com velocidade, sem
    /// nenhum achado disparado, e a IA ainda assim afirma instabilidade.
    func testAIRendererRejectsExplanationWithoutFindingsWhenVerdictIsNotHealthy() async {
        let input = DiagnosticCopyInput(
            recommendationTitle: nil,
            recommendationDescription: nil,
            score: 50,
            findings: [],
            aiTitle: "Sua conexão apresenta instabilidade",
            aiSummary: "Pode causar travamentos em chamadas de vídeo.",
            veredicto: "regular",
            aiSourceFindingIds: []
        )

        do {
            _ = try await NDSAIDiagnosticCopyRenderer().render(input: input)
            XCTFail("Deveria lançar quando não há achado que sustente a afirmação de IA")
        } catch {
            // esperado
        }
    }

    func testAIRendererRejectsExplanationWhenSourceFindingIdsIsNil() async {
        let input = DiagnosticCopyInput(
            recommendationTitle: nil,
            recommendationDescription: nil,
            score: 50,
            findings: [],
            aiTitle: "Sua conexão apresenta instabilidade",
            aiSummary: "Texto sem evidência.",
            veredicto: "regular",
            aiSourceFindingIds: nil
        )

        do {
            _ = try await NDSAIDiagnosticCopyRenderer().render(input: input)
            XCTFail("Deveria lançar quando source_finding_ids nem veio na resposta")
        } catch {
            // esperado
        }
    }

    /// Veredito bom/excelente sem achado é o caso normal (nada errado para
    /// citar) — não deve ser bloqueado; é o cenário saudável real observado
    /// no NDS (score 92, sem achados, texto genérico de "tudo certo").
    func testAIRendererAcceptsExplanationWithoutFindingsWhenVerdictIsHealthy() async throws {
        let input = DiagnosticCopyInput(
            recommendationTitle: nil,
            recommendationDescription: nil,
            score: 92,
            findings: [],
            aiTitle: "Sua conexão está funcionando muito bem",
            aiSummary: "Você está com uma ótima estabilidade.",
            veredicto: "excelente",
            aiSourceFindingIds: []
        )

        let copy = try await NDSAIDiagnosticCopyRenderer().render(input: input)

        XCTAssertEqual(copy.source, .ai)
    }

    /// Quando a IA é rejeitada, o coordinator cai no fallback determinístico
    /// em vez de propagar o erro — o usuário sempre vê algo, nunca uma tela
    /// quebrada.
    func testCoordinatorFallsBackToDeterministicWhenAIHasNoSupportingEvidence() async {
        let input = DiagnosticCopyInput(
            recommendationTitle: nil,
            recommendationDescription: nil,
            score: 50,
            findings: [],
            aiTitle: "Sua conexão apresenta instabilidade",
            aiSummary: "Pode causar travamentos.",
            veredicto: "regular",
            aiSourceFindingIds: []
        )

        let copy = await DiagnosticCopyCoordinator().resolveCopy(for: input)

        XCTAssertEqual(copy.source, .deterministic)
        XCTAssertEqual(copy.title, "Diagnóstico inconclusivo")
    }
}
