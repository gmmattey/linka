import XCTest
@testable import NetworkSpatial

final class LocalNetworkPermissionResilienceTests: XCTestCase {

    func testLocalNetworkPermissionServiceDefaultBehavior() {
        let userDefaults = UserDefaults(suiteName: "TestLocalNetworkDefaults_\(UUID().uuidString)")!
        let service = LocalNetworkPermissionService(userDefaults: userDefaults)

        XCTAssertFalse(service.hasPreviouslyGrantedPermission)
        // Em ambiente de teste unitário o estado do app pode ser inativo ou ativo
        _ = service.isAppActive

        service.hasPreviouslyGrantedPermission = true
        XCTAssertTrue(service.hasPreviouslyGrantedPermission)
    }

    func testDiagnosticErrorsDescriptions() {
        let denied = DiagnosticError.localNetworkPermissionDenied
        XCTAssertTrue(denied.localizedDescription.contains("Rede Local"))
        XCTAssertTrue(denied.localizedDescription.contains("Ajustes"))

        let interrupted = DiagnosticError.measurementInterruptedByBackground
        XCTAssertTrue(interrupted.localizedDescription.contains("perdeu o foco"))
    }

    func testDiagnosticStepsIncludePermissionHandling() {
        let step1 = DiagnosticStep.checkingLocalNetwork
        XCTAssertTrue(step1.rawValue.contains("permissão") || step1.rawValue.contains("rede local"))

        let step2 = DiagnosticStep.waitingForPermission
        XCTAssertTrue(step2.rawValue.contains("Aguardando"))
    }

    @MainActor
    func testHomeViewModelPermissionDeniedErrorDetection() {
        let viewModel = HomeViewModel()

        viewModel.errorMessage = "Erro qualquer de rede."
        viewModel.lastDiagnosticError = nil
        XCTAssertFalse(viewModel.isPermissionDeniedError)

        viewModel.errorMessage = DiagnosticError.localNetworkPermissionDenied.localizedDescription
        viewModel.lastDiagnosticError = .localNetworkPermissionDenied
        XCTAssertTrue(viewModel.isPermissionDeniedError)

        // Teste de cancelMeasurement com erro de permissão
        viewModel.cancelMeasurement(reason: DiagnosticError.localNetworkPermissionDenied.localizedDescription)
        XCTAssertTrue(viewModel.isPermissionDeniedError)
        XCTAssertEqual(viewModel.lastDiagnosticError, .localNetworkPermissionDenied)
    }
}
