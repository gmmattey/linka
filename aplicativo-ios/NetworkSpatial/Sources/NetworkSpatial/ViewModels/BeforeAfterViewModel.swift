import Foundation
import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class BeforeAfterViewModel: ObservableObject {
    @Published public var baselineRooms: [Room] = []
    @Published public var afterRooms: [Room] = []
    @Published public var comparisonResult: BeforeAfterComparison?
    @Published public var currentStep: FlowStep = .selectBaseline
    @Published public var isSaved: Bool = false

    public enum FlowStep {
        case selectBaseline
        case repositionPrompt
        case measureAfter
        case comparisonReady
    }

    private let dataStore: DataStore

    public init(dataStore: DataStore, initialRooms: [Room] = []) {
        self.dataStore = dataStore

        // Recupera baseline ativo se já tiver sido gravado anteriormente
        if CommandLine.arguments.contains("--screen-beforeafter") {
            let baseRooms = initialRooms
            var improved = initialRooms
            if let qIdx = improved.firstIndex(where: { $0.name.contains("Quarto") }) {
                var qRoom = improved[qIdx]
                let mImproved = MeasurementResult(
                    id: UUID(),
                    roomId: qRoom.id,
                    timestamp: Date(),
                    rating: .good,
                    score: 82,
                    cause: .allGood,
                    metrics: NetworkMetrics(
                        gatewayIP: "192.168.1.1",
                        gatewayLatencyMs: 14.2,
                        gatewayJitterMs: 2.8,
                        gatewayPacketLossPercent: 0.0,
                        wanLatencyMs: 26.5,
                        wanPacketLossPercent: 0.0,
                        downloadThroughputMbps: 185.0
                    ),
                    explanation: "Sinal forte e sem perda de pacotes após reposicionamento.",
                    actionableRecommendation: "Posição ideal do roteador mantida."
                )
                qRoom.lastMeasurement = mImproved
                improved[qIdx] = qRoom
            }
            self.baselineRooms = baseRooms
            self.afterRooms = improved
            self.comparisonResult = SpatialLayoutEngine.generateComparison(
                title: "Reposicionamento do Roteador",
                baselineRooms: baseRooms,
                afterRooms: improved
            )
            self.currentStep = .comparisonReady
        } else if let activeBaseline = dataStore.fetchActiveComparisonBaseline(), !activeBaseline.isEmpty {
            self.baselineRooms = activeBaseline
            self.afterRooms = initialRooms
            self.currentStep = .measureAfter
        } else {
            self.baselineRooms = initialRooms
            self.afterRooms = initialRooms
            self.currentStep = .selectBaseline
        }
    }

    public func setBaselineFromCurrentHouse(_ house: House) {
        self.baselineRooms = house.rooms
        dataStore.saveActiveComparisonBaseline(house.rooms)
        self.currentStep = .repositionPrompt
    }

    public func proceedToMeasureAfter() {
        self.currentStep = .measureAfter
    }

    public func cancelOrResetBaseline() {
        dataStore.clearActiveComparisonBaseline()
        self.baselineRooms = []
        self.comparisonResult = nil
        self.currentStep = .selectBaseline
    }

    public func finalizeComparison(with currentRooms: [Room]) {
        self.afterRooms = currentRooms
        let comparison = SpatialLayoutEngine.generateComparison(
            title: "Otimização de Posicionamento",
            baselineRooms: baselineRooms,
            afterRooms: currentRooms
        )
        self.comparisonResult = comparison
        self.currentStep = .comparisonReady
        dataStore.clearActiveComparisonBaseline()
    }

    public func saveComparisonToHistory() {
        guard let comparison = comparisonResult else { return }
        dataStore.saveComparison(comparison)
        self.isSaved = true
    }
}
