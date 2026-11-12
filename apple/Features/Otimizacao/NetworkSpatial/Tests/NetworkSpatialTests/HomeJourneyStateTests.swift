import XCTest
@testable import NetworkSpatial

@MainActor
final class HomeJourneyStateTests: XCTestCase {

    func testDiagnosisTagMapping() {
        let healthyResult = MeasurementResult(
            roomId: UUID(),
            rating: .excellent,
            score: 95,
            cause: .allGood,
            metrics: NetworkMetrics(),
            explanation: "Tudo ótimo",
            actionableRecommendation: "Manter roteador"
        )
        XCTAssertEqual(healthyResult.diagnosisTag, .healthy)
        XCTAssertFalse(healthyResult.diagnosisTag.isIssue)

        let weakWiFiResult = MeasurementResult(
            roomId: UUID(),
            rating: .poor,
            score: 30,
            cause: .localWiFiDegraded,
            metrics: NetworkMetrics(),
            explanation: "Sinal fraco",
            actionableRecommendation: "Aproximar"
        )
        XCTAssertEqual(weakWiFiResult.diagnosisTag, .weakWiFi)
        XCTAssertTrue(weakWiFiResult.diagnosisTag.isIssue)

        let slowProviderResult = MeasurementResult(
            roomId: UUID(),
            rating: .good,
            score: 80,
            cause: .ispDegraded,
            metrics: NetworkMetrics(),
            explanation: "Operadora lenta",
            actionableRecommendation: "Contatar provedor"
        )
        XCTAssertEqual(slowProviderResult.diagnosisTag, .slowProvider)
        XCTAssertTrue(slowProviderResult.diagnosisTag.isIssue)

        let unmeasuredRoom = Room(name: "Varanda")
        XCTAssertEqual(unmeasuredRoom.diagnosisTag, .unmeasured)
    }

    private func makeIsolatedViewModel() -> (HomeViewModel, DataStore, UserDefaults) {
        let store = DataStore(inMemory: true)
        let suiteName = "HomeJourneyStateTests_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let vm = HomeViewModel(dataStore: store, userDefaults: defaults)
        return (vm, store, defaults)
    }

    func testJourneyStateTransitions() {
        let (vm, store, _) = makeIsolatedViewModel()

        // Estado Inicial: 0 medições feitas -> .notStarted
        var state = vm.journeyState
        switch state {
        case .notStarted(let firstRoom):
            XCTAssertEqual(firstRoom.id, vm.house.routerRoom?.id ?? vm.house.rooms.first?.id)
        default:
            XCTFail("Esperado .notStarted, obtido \(state)")
        }

        // Simula 1 medição no primeiro cômodo -> .inProgress
        guard let first = vm.house.rooms.first else {
            XCTFail("Casa sem cômodos")
            return
        }
        vm.runSimulatedMeasurement(for: first, rating: .excellent)

        state = vm.journeyState
        switch state {
        case .inProgress(let nextRoom, let measuredCount, let totalRooms):
            XCTAssertEqual(measuredCount, 1)
            XCTAssertEqual(totalRooms, vm.house.rooms.count)
            XCTAssertNotEqual(nextRoom.id, first.id)
        default:
            XCTFail("Esperado .inProgress, obtido \(state)")
        }

        // Simula medição em todos os outros cômodos com 1 fraco -> .needsOptimization
        let remainingRooms = vm.house.rooms.filter { $0.id != first.id }
        for (index, room) in remainingRooms.enumerated() {
            vm.runSimulatedMeasurement(for: room, rating: index == 0 ? .poor : .excellent)
        }

        state = vm.journeyState
        switch state {
        case .needsOptimization(let roomsNeedingFix):
            XCTAssertFalse(roomsNeedingFix.isEmpty)
        default:
            XCTFail("Esperado .needsOptimization, obtido \(state)")
        }

        // Se todos forem excelentes -> .fullyOptimized
        for room in vm.house.rooms {
            let excellentResult = MeasurementResult(
                roomId: room.id,
                rating: .excellent,
                score: 95,
                cause: .allGood,
                metrics: NetworkMetrics(),
                explanation: "Perfeito",
                actionableRecommendation: ""
            )
            store.saveMeasurement(excellentResult, for: room.id)
        }
        vm.reloadData()

        state = vm.journeyState
        XCTAssertEqual(state, .fullyOptimized)
    }

    func testNextUnmeasuredRoomHelper() {
        let (vm, _, _) = makeIsolatedViewModel()

        let initialNext = vm.nextUnmeasuredRoom()
        XCTAssertNotNil(initialNext)
        XCTAssertEqual(initialNext?.id, vm.house.rooms.first?.id)

        // Excluindo o primeiro cômodo
        if let firstId = vm.house.rooms.first?.id {
            let nextExcludingFirst = vm.nextUnmeasuredRoom(excluding: firstId)
            XCTAssertNotNil(nextExcludingFirst)
            XCTAssertNotEqual(nextExcludingFirst?.id, firstId)
        }
    }

    func testProceedToNextRoomCancellation() {
        let (vm, _, _) = makeIsolatedViewModel()
        guard let first = vm.house.rooms.first else { return }

        // Dispara proceedToNextRoom
        vm.proceedToNextRoom(after: first)

        // Se o usuário cancelar ou iniciar outra medição antes de 500ms, a transição anterior é cancelada
        vm.cancelMeasurement()
        XCTAssertFalse(vm.isMeasuring)
    }
}
