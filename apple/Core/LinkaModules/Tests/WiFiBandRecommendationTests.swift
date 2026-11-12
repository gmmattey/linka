import XCTest
import NetworkCore
@testable import LinkaModules

final class WiFiBandRecommendationTests: XCTestCase {
    
    private func createMeasurement(
        band: Double?,
        rssi: Double?,
        download: Double?,
        ssid: String? = "MyWiFi"
    ) -> NetworkMeasurement {
        return NetworkMeasurement(
            downloadMbps: download,
            connectionKind: .wifi,
            wifiBandGHz: band,
            wifiContext: WiFiNetworkContext(ssid: ssid, rssiDbm: rssi)
        )
    }

    func test2_4GHzWithGoodCoverageLimitationAnd5GHzConfirmedBetter() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -60, download: 50)
        let hist1 = createMeasurement(band: 5.0, rssi: -60, download: 200)
        let hist2 = createMeasurement(band: 5.0, rssi: -60, download: 220)
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [hist1, hist2])
        
        XCTAssertEqual(result.action, .switchBand(target: .band5GHz))
        XCTAssertEqual(result.reason, .historicallyBetterOn5GHz)
        XCTAssertTrue(result.isEvidenceSufficient)
    }

    func test2_4GHzWithWeakSignal() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -80, download: 10)
        let hist1 = createMeasurement(band: 5.0, rssi: -60, download: 200)
        let hist2 = createMeasurement(band: 5.0, rssi: -60, download: 220)
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [hist1, hist2])
        
        XCTAssertNil(result.action)
        XCTAssertTrue(result.isEvidenceSufficient)
    }

    func test0Samples_NotEligible() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -60, download: 50)
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [])
        
        XCTAssertNil(result.action)
    }

    func test1Sample_NotEligible() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -60, download: 50)
        let hist1 = createMeasurement(band: 5.0, rssi: -60, download: 200)
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [hist1])
        
        XCTAssertNil(result.action)
    }

    func test3Samples_Eligible() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -60, download: 50)
        let hist1 = createMeasurement(band: 5.0, rssi: -60, download: 200)
        let hist2 = createMeasurement(band: 5.0, rssi: -60, download: 220)
        let hist3 = createMeasurement(band: 5.0, rssi: -60, download: 190)
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [hist1, hist2, hist3])
        
        XCTAssertEqual(result.action, .switchBand(target: .band5GHz))
    }

    func testBandSeparation_1Sample5GHz_1Sample6GHz_NotEligible() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -60, download: 50)
        let hist1 = createMeasurement(band: 5.0, rssi: -60, download: 200)
        let hist2 = createMeasurement(band: 6.0, rssi: -60, download: 200)
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [hist1, hist2])
        
        XCTAssertNil(result.action)
    }

    func testNetworkSeparation_DifferentSSIDs_NotEligible() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -60, download: 50, ssid: "NetworkA")
        let hist1 = createMeasurement(band: 5.0, rssi: -60, download: 200, ssid: "NetworkA")
        let hist2 = createMeasurement(band: 5.0, rssi: -60, download: 200, ssid: "NetworkB")
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [hist1, hist2])
        
        XCTAssertNil(result.action)
    }

    func testInvalidData_ZeroSpeed_NotEligible() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -60, download: 50)
        let hist1 = createMeasurement(band: 5.0, rssi: -60, download: 200)
        let hist2 = createMeasurement(band: 5.0, rssi: -60, download: 0) // Invalid
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [hist1, hist2])
        
        XCTAssertNil(result.action)
    }
    
    func testInvalidData_NoBand_NotEligible() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -60, download: 50)
        let hist1 = createMeasurement(band: 5.0, rssi: -60, download: 200)
        let hist2 = createMeasurement(band: nil, rssi: -60, download: 200) // Invalid
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [hist1, hist2])
        
        XCTAssertNil(result.action)
    }

    // MARK: - Issue 158 tests
    
    func test2_4GHz_to_6GHz_Directly() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -60, download: 50)
        let hist1 = createMeasurement(band: 6.0, rssi: -60, download: 200)
        let hist2 = createMeasurement(band: 6.0, rssi: -60, download: 220)
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [hist1, hist2])
        
        XCTAssertEqual(result.action, .switchBand(target: .band6GHz))
        XCTAssertEqual(result.reason, .historicallyBetterOn6GHz)
    }
    
    func test2_4GHz_6GHzInsufficientEvidence() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -60, download: 50)
        let hist1 = createMeasurement(band: 6.0, rssi: -60, download: 200)
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [hist1])
        
        XCTAssertNil(result.action)
    }
    
    func test2_4GHz_5GHzEligible_6GHzNoEvidence() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -60, download: 50)
        let hist1 = createMeasurement(band: 5.0, rssi: -60, download: 200)
        let hist2 = createMeasurement(band: 5.0, rssi: -60, download: 220)
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [hist1, hist2])
        
        XCTAssertEqual(result.action, .switchBand(target: .band5GHz))
    }
    
    func test2_4GHz_BothEligible_Deterministic_5GHzWins() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -60, download: 50)
        let hist5_1 = createMeasurement(band: 5.0, rssi: -60, download: 200)
        let hist5_2 = createMeasurement(band: 5.0, rssi: -60, download: 200)
        let hist6_1 = createMeasurement(band: 6.0, rssi: -60, download: 220)
        let hist6_2 = createMeasurement(band: 6.0, rssi: -60, download: 220)
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [hist5_1, hist5_2, hist6_1, hist6_2])
        
        XCTAssertEqual(result.action, .switchBand(target: .band5GHz))
    }
    
    func test2_4GHz_BothEligible_Deterministic_6GHzWins() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -60, download: 50)
        let hist5_1 = createMeasurement(band: 5.0, rssi: -60, download: 100)
        let hist5_2 = createMeasurement(band: 5.0, rssi: -60, download: 100)
        let hist6_1 = createMeasurement(band: 6.0, rssi: -60, download: 200)
        let hist6_2 = createMeasurement(band: 6.0, rssi: -60, download: 200)
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [hist5_1, hist5_2, hist6_1, hist6_2])
        
        XCTAssertEqual(result.action, .switchBand(target: .band6GHz))
    }
    
    func test2_4GHz_5GHzInsufficient_6GHzSufficient() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -60, download: 50)
        let hist5_1 = createMeasurement(band: 5.0, rssi: -60, download: 200)
        let hist6_1 = createMeasurement(band: 6.0, rssi: -60, download: 200)
        let hist6_2 = createMeasurement(band: 6.0, rssi: -60, download: 200)
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [hist5_1, hist6_1, hist6_2])
        
        XCTAssertEqual(result.action, .switchBand(target: .band6GHz))
    }
    
    func test2_4GHz_5GHzSufficient_6GHzInsufficient() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -60, download: 50)
        let hist5_1 = createMeasurement(band: 5.0, rssi: -60, download: 200)
        let hist5_2 = createMeasurement(band: 5.0, rssi: -60, download: 200)
        let hist6_1 = createMeasurement(band: 6.0, rssi: -60, download: 300)
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [hist5_1, hist5_2, hist6_1])
        
        XCTAssertEqual(result.action, .switchBand(target: .band5GHz))
    }
    
    func test2_4GHz_BothInsufficient() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -60, download: 50)
        let hist5_1 = createMeasurement(band: 5.0, rssi: -60, download: 200)
        let hist6_1 = createMeasurement(band: 6.0, rssi: -60, download: 300)
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [hist5_1, hist6_1])
        
        XCTAssertNil(result.action)
    }
    
    func test2_4GHz_WeakSignal_6GHzExcellent() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -85, download: 10)
        let hist6_1 = createMeasurement(band: 6.0, rssi: -60, download: 300)
        let hist6_2 = createMeasurement(band: 6.0, rssi: -60, download: 300)
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [hist6_1, hist6_2])
        
        XCTAssertNil(result.action)
    }
    
    func test2_4GHz_6GHzDifferentNetwork() {
        let evaluator = WiFiBandRecommendationEvaluator()
        let current = createMeasurement(band: 2.4, rssi: -60, download: 50, ssid: "MyWiFi")
        let hist6_1 = createMeasurement(band: 6.0, rssi: -60, download: 300, ssid: "OtherWiFi")
        let hist6_2 = createMeasurement(band: 6.0, rssi: -60, download: 300, ssid: "OtherWiFi")
        
        let result = evaluator.evaluate(measurement: current, historicalMeasurements: [hist6_1, hist6_2])
        
        XCTAssertNil(result.action)
    }
}
