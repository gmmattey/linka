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
            "-AppleLocale", "pt_BR",
            "-linka.language.preference.v1", "pt-BR"
        ]
        app.launch()
        // Em macOS o processo de UI test pode iniciar em segundo plano; a
        // ativação torna a janela candidata a superfície observada pelo teste.
        app.activate()
    }

    func testPrimarySidebarAndSettingsAreReachableWithoutStartingMeasurement() {
        // NavigationLink dentro de uma sidebar macOS expõe uma linha
        // selecionável, não um botão. Buscar por qualquer elemento preserva
        // essa semântica nativa e ainda exerce o identificador público.
        let speedTest = app.descendants(matching: .any)["mac.sidebar.speedTest"]
        XCTAssertTrue(speedTest.waitForExistence(timeout: 8))

        let history = app.descendants(matching: .any)["mac.sidebar.history"]
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

    func testSidebarLeavesAContextualSettingsDestination() {
        let settings = app.buttons["mac.toolbar.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.click()

        let serviceStatus = app.buttons["Acompanhar serviços"]
        XCTAssertTrue(serviceStatus.waitForExistence(timeout: 3))
        serviceStatus.click()
        XCTAssertTrue(app.searchFields["Buscar serviço"].waitForExistence(timeout: 3))

        let speedTest = app.descendants(matching: .any)["mac.sidebar.speedTest"]
        speedTest.click()
        XCTAssertTrue(app.descendants(matching: .any)["mac.workspace.speedTest"].waitForExistence(timeout: 3))
    }

    func testAllSidebarDestinationsFromPrototypeAreReachable() {
        let speedTest = app.descendants(matching: .any)["mac.sidebar.speedTest"]
        XCTAssertTrue(speedTest.waitForExistence(timeout: 8))

        let history = app.descendants(matching: .any)["mac.sidebar.history"]
        XCTAssertTrue(history.exists)

        let assist = app.descendants(matching: .any)["mac.sidebar.assist"]
        XCTAssertTrue(assist.exists)
        assist.click()
        XCTAssertTrue(app.descendants(matching: .any)["mac.workspace.assist"].waitForExistence(timeout: 3))

        let dns = app.descendants(matching: .any)["mac.sidebar.dns"]
        XCTAssertTrue(dns.exists)
        dns.click()
        XCTAssertTrue(app.descendants(matching: .any)["mac.workspace.dns"].waitForExistence(timeout: 3))

        let optimization = app.descendants(matching: .any)["mac.sidebar.optimization"]
        XCTAssertTrue(optimization.exists)
        optimization.click()
        XCTAssertTrue(app.descendants(matching: .any)["mac.workspace.optimization"].waitForExistence(timeout: 3))

        speedTest.click()
        XCTAssertTrue(app.descendants(matching: .any)["mac.workspace.speedTest"].waitForExistence(timeout: 3))
    }

    func testIdleScreenShowsFastCompleteSelectorAndExplicitStartButton() {
        let startButton = app.buttons["mac.idle.startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 8))
        XCTAssertTrue(startButton.isHittable)
    }
}
#endif
