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
        app.buttons["inventory.saveWithoutResearch"].tap()
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
    func testInitialJourneyHasOneIdentificationFieldAndNoTechnicalForm() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch(); openInventory(app)
        app.buttons["inventory.toolbar.add"].tap()
        XCTAssertTrue(app.textFields["inventory.model"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields.count, 1)
        XCTAssertTrue(app.buttons["inventory.research"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Cloudflare")).firstMatch.exists)
        attachment("inventory-identify")
    }

    func testLiveNokiaResearchKeepsIdentificationAndShowsInlineOutcome() throws {
        try liveResearch(query: "Nokia G-1425-B", expectsAvailable: false)
    }

    func testLargeTextDraftSurvivesBackgrounding() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR",
                                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); openInventory(app)
        app.buttons["inventory.toolbar.add"].tap()
        let field = app.textFields["inventory.model"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        if !field.isHittable { app.swipeUp() }
        field.tap(); field.typeText("Nokia G-1425-B")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(field.value as? String, "Nokia G-1425-B")
        field.tap() // Wait for foreground transition and keyboard to settle before the visual record.
        attachment("inventory-large-text-preserved-draft")
    }

    func testLiveDocumentedNokiaCanSaveAndReopenResearchedInformation() throws {
        try liveResearch(query: "Nokia G-1425G-B", expectsAvailable: true)
    }

    private func liveResearch(query: String, expectsAvailable: Bool) throws {
        guard ProcessInfo.processInfo.environment["LINKA_RUN_LIVE_LOOKUP_TESTS"] == "1" else {
            throw XCTSkip("Real lookup is opt-in; this test consumes the authorized internal pilot service.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launchEnvironment["LINKA_DEVICE_SPEC_ENDPOINT"] = "https://linka-device-spec-lookup.buildealabs.workers.dev/v2/device-specs/lookup"
        app.launch(); openInventory(app)
        app.buttons["inventory.toolbar.add"].tap()
        let field = app.textFields["inventory.model"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(query)
        let search = app.buttons["inventory.research"]
        XCTAssertTrue(search.isHittable); search.tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let outcome = app.descendants(matching: .any)["inventory.research.result"].firstMatch
        let message = app.descendants(matching: .any)["inventory.research.message"].firstMatch
        let completed = NSPredicate { _, _ in outcome.exists || message.exists }
        let wait = expectation(for: completed, evaluatedWith: app)
        waitForExpectations(timeout: 105)
        _ = wait
        XCTAssertEqual(field.value as? String, query)
        XCTAssertTrue(outcome.isHittable || message.isHittable, "Outcome must be visible without searching the form")
        attachment("inventory-live-" + query.replacingOccurrences(of: " ", with: "-"))
        if expectsAvailable {
            XCTAssertTrue(outcome.exists, "Known documented model must produce a usable card")
            let save = app.buttons["inventory.save"]
            if !save.isHittable { app.swipeUp() }
            XCTAssertTrue(save.isHittable); save.tap()
            XCTAssertTrue(app.staticTexts[query].waitForExistence(timeout: 5))
            app.terminate(); app.launch(); openInventory(app)
            XCTAssertTrue(app.staticTexts[query].waitForExistence(timeout: 5))
            app.staticTexts[query].firstMatch.tap()
            XCTAssertTrue(app.buttons["inventory.completeDetails"].waitForExistence(timeout: 5))
            attachment("inventory-live-reopened")
        }
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
