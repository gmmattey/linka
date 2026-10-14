#if os(macOS)
import XCTest

/// Exercita a casca nativa sem iniciar uma medição. Os destinos são parte da
/// navegação principal do Mac e precisam continuar alcançáveis numa candidata
/// real, não só nas regras puras de `MacNavigationPolicy`.
final class MacNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.linka.assist")
        app.launchArguments = [
            "-AppleLanguages", "(pt-BR)",
            "-AppleLocale", "pt_BR"
        ]
        app.launch()
    }

    func testPrimarySidebarAndSettingsAreReachableWithoutStartingMeasurement() {
        let speedTest = app.buttons["mac.sidebar.speedTest"]
        XCTAssertTrue(speedTest.waitForExistence(timeout: 8))

        let history = app.buttons["mac.sidebar.history"]
        XCTAssertTrue(history.exists)
        history.click()
        XCTAssertTrue(app.descendants(matching: .any)["mac.workspace.history"].waitForExistence(timeout: 3))

        let settings = app.buttons["mac.toolbar.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.click()
        XCTAssertTrue(app.descendants(matching: .any)["mac.workspace.settings"].waitForExistence(timeout: 3))

        // Voltar ao destino de medição não inicia o teste: a pessoa mantém
        // controle explícito sobre uma ação que consome rede e gera histórico.
        speedTest.click()
        XCTAssertTrue(app.descendants(matching: .any)["mac.workspace.speedTest"].waitForExistence(timeout: 3))
    }
}
#endif
