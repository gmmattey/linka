import XCTest

final class AssistV4FixtureUITests: XCTestCase {
    func testGuidedAndOpenQuestionStayLocalInFixture() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--assist-v4-fixture", "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()

        XCTAssertTrue(app.buttons["assist-v4.shortcut.slow_connection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["assist-v4.composer"].exists)

        app.buttons["assist-v4.shortcut.slow_connection"].tap()
        let room = app.buttons["Em um cômodo"]
        XCTAssertTrue(room.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Investigação local · etapa 1 de 2"].exists)
        room.tap()
        app.buttons["Continuar"].tap()
        let usage = app.buttons["Em tudo"]
        XCTAssertTrue(usage.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Investigação local · etapa 2 de 2"].exists)
        usage.tap()
        app.buttons["Continuar"].tap()
        XCTAssertTrue(app.staticTexts["Próxima etapa sugerida"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Por quê"].exists)
        XCTAssertTrue(app.staticTexts["Próxima ação"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["assist-v4.local-orientation"].exists)
        app.buttons["assist-v4.action.complete"].tap()
        XCTAssertTrue(app.staticTexts["Ação marcada como concluída nesta sessão local."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Não foi executado teste nem salvo histórico."].exists)

        app.buttons["Voltar às sugestões"].tap()
        let composer = app.textFields["assist-v4.composer"]
        composer.tap()
        composer.typeText("Posso usar um roteador antigo como AP?")
        app.buttons["assist-v4.send"].tap()
        XCTAssertTrue(app.staticTexts["A pergunta não foi enviada"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "continua no rascunho")).firstMatch.exists)
    }

    func testOpenQuestionCanReturnToAnUnsentGuidedInvestigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--assist-v4-fixture", "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()

        app.buttons["assist-v4.shortcut.slow_connection"].tap()
        let room = app.buttons["Em um cômodo"]
        XCTAssertTrue(room.waitForExistence(timeout: 3))
        room.tap()

        let composer = app.textFields["assist-v4.composer"]
        composer.tap()
        composer.typeText("E em videochamadas?")
        app.buttons["assist-v4.send"].tap()
        XCTAssertTrue(app.buttons["Continuar investigação"].waitForExistence(timeout: 3))

        app.buttons["Continuar investigação"].tap()
        XCTAssertTrue(app.buttons["Em um cômodo"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Continuar"].isEnabled)
    }

    func testResultCanRevisitTheLastGuidedChoiceWithoutSendingData() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--assist-v4-fixture", "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()

        app.buttons["assist-v4.shortcut.slow_connection"].tap()
        app.buttons["Em um cômodo"].tap()
        app.buttons["Continuar"].tap()
        app.buttons["Em tudo"].tap()
        app.buttons["Continuar"].tap()
        XCTAssertTrue(app.buttons["assist-v4.action.revise-answers"].waitForExistence(timeout: 3))

        app.buttons["assist-v4.action.revise-answers"].tap()
        XCTAssertTrue(app.staticTexts["Acontece em tudo ou só em um app ou serviço?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Continuar"].isEnabled)
        app.buttons["Só em um app ou serviço"].tap()
        app.buttons["Continuar"].tap()
        XCTAssertTrue(app.staticTexts["Dados insuficientes para continuar"].waitForExistence(timeout: 3))
    }

    func testGuidedBackPreservesThePreviousLocalChoice() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--assist-v4-fixture", "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()

        app.buttons["assist-v4.shortcut.slow_connection"].tap()
        app.buttons["Em um cômodo"].tap()
        app.buttons["Continuar"].tap()
        XCTAssertTrue(app.buttons["assist-v4.guided.back"].waitForExistence(timeout: 3))
        app.buttons["assist-v4.guided.back"].tap()
        XCTAssertTrue(app.staticTexts["Onde a conexão está lenta?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Continuar"].isEnabled)
        app.buttons["Continuar"].tap()
        XCTAssertTrue(app.staticTexts["Acontece em tudo ou só em um app ou serviço?"].waitForExistence(timeout: 3))
    }

    func testPlanDeclarationStaysLocalAndDoesNotConsultOffers() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--assist-v4-fixture", "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()

        app.buttons["assist-v4.shortcut.plan_value"].tap()
        let name = app.textFields["assist-v4.plan.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Fibra 500")
        let price = app.textFields["assist-v4.plan.price"]
        price.tap()
        price.typeText("99,90")
        app.buttons["Continuar"].tap()
        XCTAssertTrue(app.buttons["Entender ofertas"].waitForExistence(timeout: 3))
        app.buttons["Entender ofertas"].tap()
        app.buttons["Continuar"].tap()
        XCTAssertTrue(app.staticTexts["Dados insuficientes para continuar"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "nenhuma oferta é consultada")).firstMatch.exists)
    }

    func testFixtureKeepsTheLocalBoundariesOnExpandedTextIpad() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--assist-v4-fixture",
            "-AppleLanguages", "(pt-BR)",
            "-AppleLocale", "pt_BR",
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategory", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["assist-v4.network-context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["assist-v4.shortcut.router_adequacy"].exists)
        XCTAssertTrue(app.textFields["assist-v4.composer"].exists)

        app.buttons["assist-v4.shortcut.router_adequacy"].tap()
        XCTAssertTrue(app.buttons["Selecionar um equipamento"].waitForExistence(timeout: 3))
        app.buttons["Selecionar um equipamento"].tap()
        app.buttons["Continuar"].tap()
        XCTAssertTrue(app.staticTexts["Dados insuficientes para continuar"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["assist-v4.evidence-boundary"].exists)
    }
}
