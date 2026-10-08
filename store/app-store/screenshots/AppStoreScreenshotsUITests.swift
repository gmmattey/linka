import XCTest

class AppStoreScreenshotsUITests: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Adiciona um argumento para o app saber que está rodando via UI Test (caso precise mockar algo)
        app.launchArguments.append("--uitesting")
        app.launch()
    }
    
    func takeScreenshot(name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        // keepAlways garante que a foto ficará salva no Result Bundle (.xcresult)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCaptureScreenshots() throws {
        let app = XCUIApplication()
        
        // Dá um tempo para a Home carregar
        sleep(3)
        
        // 1. Home / Entenda sua conexão
        takeScreenshot(name: "01-entenda-sua-conexao")
        
        // 2. Resultado (Clica em Analisar e aguarda)
        let analisarBtn = app.buttons["Analisar rede"]
        if analisarBtn.exists {
            analisarBtn.tap()
            // Aguarda o tempo do teste de velocidade terminar (aprox 15-20s)
            sleep(20)
            takeScreenshot(name: "02-resultado")
        }
        
        // 3. Assist
        // Tenta abrir o Assist a partir da tela de resultado ou da Home
        let assistBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Assist'")).firstMatch
        if assistBtn.exists {
            assistBtn.tap()
            sleep(2)
            takeScreenshot(name: "03-assist")
        }
    }

    func testSpeedTestCTAStartsMeasurement() throws {
        let app = XCUIApplication()
        let speedTestButton = app.buttons["home.speedTestCTA"]

        XCTAssertTrue(speedTestButton.waitForExistence(timeout: 5))
        XCTAssertTrue(speedTestButton.isHittable)

        speedTestButton.tap()

        XCTAssertTrue(app.otherElements["home.measurementInProgress"].waitForExistence(timeout: 3))
    }
}
