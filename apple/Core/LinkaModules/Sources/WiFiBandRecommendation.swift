import Foundation
import NetworkCore
import NetworkInsights

public enum WiFiBandRecommendationTarget: Double, Codable, Equatable, Sendable {
    case band5GHz = 5.0
    case band6GHz = 6.0
}

public enum WiFiBandRecommendationAction: Equatable, Sendable {
    case switchBand(target: WiFiBandRecommendationTarget)
}

public enum WiFiBandRecommendationReason: String, Codable, Equatable, Sendable {
    case historicallyBetterOn5GHz
    case historicallyBetterOn6GHz
}

public struct WiFiBandRecommendation: Equatable, Sendable {
    public let currentBand: Double?
    public let action: WiFiBandRecommendationAction?
    public let reason: WiFiBandRecommendationReason?
    public let isEvidenceSufficient: Bool
    
    public init(
        currentBand: Double?,
        action: WiFiBandRecommendationAction?,
        reason: WiFiBandRecommendationReason?,
        isEvidenceSufficient: Bool
    ) {
        self.currentBand = currentBand
        self.action = action
        self.reason = reason
        self.isEvidenceSufficient = isEvidenceSufficient
    }
}

public struct WiFiBandRecommendationEvaluator {
    public let minimumGoodSignalDbm: Double
    public let minimumSamplesRequired: Int

    public init(minimumGoodSignalDbm: Double = -70, minimumSamplesRequired: Int = 2) {
        self.minimumGoodSignalDbm = minimumGoodSignalDbm
        self.minimumSamplesRequired = minimumSamplesRequired
    }

    public func evaluate(
        measurement: NetworkMeasurement,
        historicalMeasurements: [NetworkMeasurement] = []
    ) -> WiFiBandRecommendation {
        guard measurement.connectionKind == .wifi else {
            return WiFiBandRecommendation(currentBand: nil, action: nil, reason: nil, isEvidenceSufficient: false)
        }

        let currentBand = measurement.wifiBandGHz ?? measurement.advancedWiFiDiagnostics?.bandGHz ?? measurement.wifiContext?.bandGHz
        let rssi = measurement.advancedWiFiDiagnostics?.rssiDbm ?? measurement.wifiContext?.rssiDbm
        let download = measurement.downloadMbps
        
        guard let currentBand, let rssi, let download else {
            return WiFiBandRecommendation(currentBand: currentBand, action: nil, reason: nil, isEvidenceSufficient: false)
        }
        
        guard let currentSSID = measurement.wifiContext?.ssid, !currentSSID.isEmpty else {
            return WiFiBandRecommendation(currentBand: currentBand, action: nil, reason: nil, isEvidenceSufficient: false)
        }
        
        // Filter history by same SSID
        let sameNetworkHistory = historicalMeasurements.filter { hist in
            hist.connectionKind == .wifi && hist.wifiContext?.ssid == currentSSID
        }
        
        func medianDownload(for band: Double) -> Double? {
            let values = sameNetworkHistory.compactMap { hist -> Double? in
                let histBand = hist.wifiBandGHz ?? hist.advancedWiFiDiagnostics?.bandGHz ?? hist.wifiContext?.bandGHz
                if histBand == band, let speed = hist.downloadMbps, speed > 0 {
                    return speed
                }
                return nil
            }.sorted()
            
            guard values.count >= minimumSamplesRequired else { return nil }
            let count = values.count
            if count % 2 == 0 {
                return (values[count/2 - 1] + values[count/2]) / 2.0
            } else {
                return values[count/2]
            }
        }
        
        let median5GHz = medianDownload(for: 5.0)
        let median6GHz = medianDownload(for: 6.0)
        
        switch currentBand {
        case 2.4:
            if rssi > minimumGoodSignalDbm {
                let m5IsBetter = median5GHz.map { $0 > download * 1.2 } ?? false
                let m6IsBetter = median6GHz.map { $0 > download * 1.2 } ?? false
                
                if m5IsBetter && m6IsBetter {
                    let m5 = median5GHz!
                    let m6 = median6GHz!
                    if m6 > m5 * 1.2 {
                        return WiFiBandRecommendation(
                            currentBand: currentBand,
                            action: .switchBand(target: .band6GHz),
                            reason: .historicallyBetterOn6GHz,
                            isEvidenceSufficient: true
                        )
                    } else {
                        return WiFiBandRecommendation(
                            currentBand: currentBand,
                            action: .switchBand(target: .band5GHz),
                            reason: .historicallyBetterOn5GHz,
                            isEvidenceSufficient: true
                        )
                    }
                } else if m6IsBetter {
                    return WiFiBandRecommendation(
                        currentBand: currentBand,
                        action: .switchBand(target: .band6GHz),
                        reason: .historicallyBetterOn6GHz,
                        isEvidenceSufficient: true
                    )
                } else if m5IsBetter {
                    return WiFiBandRecommendation(
                        currentBand: currentBand,
                        action: .switchBand(target: .band5GHz),
                        reason: .historicallyBetterOn5GHz,
                        isEvidenceSufficient: true
                    )
                }
            }
            return WiFiBandRecommendation(currentBand: currentBand, action: nil, reason: nil, isEvidenceSufficient: true)
            
        case 5.0:
            if let m6 = median6GHz, m6 > download * 1.2 {
                return WiFiBandRecommendation(
                    currentBand: currentBand,
                    action: .switchBand(target: .band6GHz),
                    reason: .historicallyBetterOn6GHz,
                    isEvidenceSufficient: true
                )
            }
            return WiFiBandRecommendation(currentBand: currentBand, action: nil, reason: nil, isEvidenceSufficient: true)
            
        default:
            return WiFiBandRecommendation(currentBand: currentBand, action: nil, reason: nil, isEvidenceSufficient: true)
        }
    }
}
