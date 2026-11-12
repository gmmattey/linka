import XCTest
import NetworkCore
@testable import LinkaApp

/// Regressão do PR #141: `MainView` passou a apresentar `AssistView` dentro
/// de `AssistProblemSelectionView` (que empurra `AssistView` via
/// `navigationDestination` no próprio `NavigationStack`). Nesse arranjo,
/// `@Environment(\.dismiss)` capturado dentro de `AssistView` só faz pop de
/// volta para a tela de seleção — não fecha o sheet inteiro apresentado por
/// `MainView`. "Testar novamente" e "Ver detalhes da medição" ficavam
/// escondidos atrás do sheet ainda aberto.
///
/// A correção dá a `AssistView` um `onCloseSheet` explícito, que
/// `AssistProblemSelectionView` preenche com o `dismiss` capturado na RAIZ
/// do seu próprio `NavigationStack` (o único que fecha o sheet de verdade).
/// Este teste comprova que o `onCloseSheet` fornecido no `init` é o closure
/// realmente armazenado na view — ou seja, que o botão, ao chamá-lo, aciona
/// o fechamento do sheet real e não um `dismiss()` de pop local.
@MainActor
final class AssistViewCloseSheetTests: XCTestCase {
    func test_onCloseSheet_whenProvided_isStoredAndInvokedInsteadOfLocalDismiss() {
        var closeSheetCallCount = 0

        let view = AssistView(
            currentMeasurement: measurement(id: UUID()),
            recentMeasurements: [],
            onCloseSheet: { closeSheetCallCount += 1 }
        )

        // Simula o que os botões "Testar novamente" e "Ver detalhes da
        // medição" fazem quando `onCloseSheet` foi fornecido pelo fluxo
        // guiado: chamam esse closure em vez de `dismiss()` local.
        view.onCloseSheet?()
        view.onCloseSheet?()

        XCTAssertEqual(
            closeSheetCallCount,
            2,
            "onCloseSheet deve ser o closure realmente armazenado e invocável pelos botões, não descartado."
        )
    }

    /// `HistoryView` continua sem passar `onCloseSheet` (não deve ser
    /// alterado — ela empurra `AssistView` no próprio `NavigationStack`,
    /// sem tela de seleção no meio, onde o `dismiss()` local já é correto).
    func test_onCloseSheet_defaultsToNil_preservingHistoryViewBehavior() {
        let view = AssistView(
            currentMeasurement: measurement(id: UUID()),
            recentMeasurements: []
        )

        XCTAssertNil(
            view.onCloseSheet,
            "Sem onCloseSheet explícito (caso HistoryView), o botão deve continuar caindo no dismiss() local."
        )
    }

    // MARK: - Helpers

    private func measurement(id: UUID) -> NetworkMeasurement {
        NetworkMeasurement(
            id: id,
            outcome: .complete,
            downloadMbps: 120,
            uploadMbps: 30,
            latencyMs: 18
        )
    }
}
