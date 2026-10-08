import XCTest

final class MyNetworkUITests: XCTestCase {
    func testManualInventoryPersistsAndDeletionIsExplicit() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
        openInventory(app)
        app.buttons["inventory.toolbar.add"].tap()
        let model = "QA-local-" + UUID().uuidString.prefix(8)
        let field = app.textFields["inventory.model"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(model)
        app.buttons["inventory.save"].tap()
        XCTAssertTrue(app.staticTexts[model].waitForExistence(timeout: 5))
        attachment("inventory-created")
        app.terminate(); app.launch()
        openInventory(app)
        XCTAssertTrue(app.staticTexts[model].waitForExistence(timeout: 5))
        app.staticTexts[model].tap()
        for _ in 0..<4 where !app.buttons["Excluir equipamento"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["Excluir equipamento"].waitForExistence(timeout: 5))
        app.buttons["Excluir equipamento"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Cancelar"].tap()
        XCTAssertTrue(app.staticTexts[model].exists)
        app.buttons["Excluir equipamento"].tap()
        app.alerts.buttons["Excluir equipamento"].tap()
        XCTAssertTrue(app.staticTexts["Este equipamento foi excluído."].waitForExistence(timeout: 5))
    }
    func testChangedDraftAsksBeforeDiscarding() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch(); openInventory(app)
        app.buttons["inventory.toolbar.add"].tap()
        let field = app.textFields["inventory.model"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("QA-unsaved")
        app.buttons["Cancelar"].tap()
        XCTAssertTrue(app.alerts["Descartar alterações?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Continuar editando"].tap()
        XCTAssertEqual(field.value as? String, "QA-unsaved")
        app.buttons["Cancelar"].tap(); app.alerts.buttons["Descartar"].tap()
        XCTAssertTrue(app.buttons["inventory.toolbar.add"].waitForExistence(timeout: 5))
    }
    private func openInventory(_ app: XCUIApplication) {
        if app.buttons["Entendi"].waitForExistence(timeout: 2) { app.buttons["Entendi"].tap() }
        let entry = app.buttons["inventory.open"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        XCTAssertTrue(app.buttons["inventory.toolbar.add"].waitForExistence(timeout: 5))
    }
    private func attachment(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
