import Foundation
import Combine

/// Gerenciador de pontos de acesso observados e detecção determinística de roaming/handoff
@MainActor
public final class AccessPointTracker: ObservableObject {
    public static let shared = AccessPointTracker()

    @Published public private(set) var detectedAccessPoints: [DetectedAccessPoint] = []
    @Published public private(set) var lastHandoffEvent: AccessPointHandoffEvent?

    private var bssidToAPMap: [String: DetectedAccessPoint] = [:]
    private var lastSeenBSSID: String?
    private var lastSeenSSID: String?

    public init() {}

    /// Rótulo amigável estável ("AP 1", "AP 2") para um determinado BSSID
    public func label(for bssid: String?) -> String? {
        guard let bssid = WiFiBSSIDNormalizer.normalize(bssid) else { return nil }
        return bssidToAPMap[bssid]?.label
    }

    /// Registra uma nova medição, atualiza a malha e detecta eventual handoff
    @discardableResult
    public func registerMeasurement(
        result: MeasurementResult,
        roomName: String? = nil
    ) -> (ap: DetectedAccessPoint?, handoff: AccessPointHandoffEvent?) {
        guard let rawBSSID = result.metrics.bssid,
              let normalizedBSSID = WiFiBSSIDNormalizer.normalize(rawBSSID) else {
            // Se a medição não possui BSSID, não altera o estado de APs nem dispara handoff
            return (nil, nil)
        }

        let currentSSID = result.metrics.ssid

        // 1. Resolve ou cria o DetectedAccessPoint mantendo estabilidade
        let ap: DetectedAccessPoint
        if var existing = bssidToAPMap[normalizedBSSID] {
            existing.observedCount += 1
            bssidToAPMap[normalizedBSSID] = existing
            if let index = detectedAccessPoints.firstIndex(where: { $0.id == normalizedBSSID }) {
                detectedAccessPoints[index] = existing
            }
            ap = existing
        } else {
            let nextIndex = detectedAccessPoints.count + 1
            let newLabel = "AP \(nextIndex)"
            let newAP = DetectedAccessPoint(
                id: normalizedBSSID,
                bssid: normalizedBSSID,
                ssid: currentSSID,
                label: newLabel,
                firstSeenRoomName: roomName,
                observedCount: 1
            )
            bssidToAPMap[normalizedBSSID] = newAP
            detectedAccessPoints.append(newAP)
            ap = newAP
        }

        // 2. Avaliação de Handoff (Mesmo SSID, BSSID diferente)
        var detectedHandoff: AccessPointHandoffEvent? = nil
        if let prevBSSID = lastSeenBSSID,
           let prevSSID = lastSeenSSID,
           let curSSID = currentSSID,
           prevSSID == curSSID,
           prevBSSID != normalizedBSSID {
            let fromName = bssidToAPMap[prevBSSID]?.label ?? "AP Anterior"
            let toName = ap.label
            let event = AccessPointHandoffEvent(
                fromBSSID: prevBSSID,
                toBSSID: normalizedBSSID,
                ssid: curSSID,
                fromAPName: fromName,
                toAPName: toName,
                timestamp: result.timestamp
            )
            self.lastHandoffEvent = event
            detectedHandoff = event
        }

        // 3. Atualiza os ponteiros da caminhada
        self.lastSeenBSSID = normalizedBSSID
        self.lastSeenSSID = currentSSID

        return (ap, detectedHandoff)
    }

    /// Sincroniza o rastreador com as medições já existentes na residência
    public func syncWithHouse(_ house: House) {
        var observedInOrder: [(bssid: String, ssid: String?, roomName: String, timestamp: Date)] = []

        for room in house.rooms {
            if let m = room.lastMeasurement,
               let rawBSSID = m.metrics.bssid,
               let normalized = WiFiBSSIDNormalizer.normalize(rawBSSID) {
                observedInOrder.append((bssid: normalized, ssid: m.metrics.ssid, roomName: room.name, timestamp: m.timestamp))
            }
        }

        observedInOrder.sort(by: { $0.timestamp < $1.timestamp })

        for item in observedInOrder {
            if var existing = bssidToAPMap[item.bssid] {
                existing.observedCount += 1
                bssidToAPMap[item.bssid] = existing
                if let idx = detectedAccessPoints.firstIndex(where: { $0.id == item.bssid }) {
                    detectedAccessPoints[idx] = existing
                }
            } else {
                let nextIdx = detectedAccessPoints.count + 1
                let ap = DetectedAccessPoint(
                    id: item.bssid,
                    bssid: item.bssid,
                    ssid: item.ssid,
                    label: "AP \(nextIdx)",
                    firstSeenRoomName: item.roomName,
                    observedCount: 1
                )
                bssidToAPMap[item.bssid] = ap
                detectedAccessPoints.append(ap)
            }
        }
    }

    /// Limpa o estado da sessão
    public func reset() {
        self.detectedAccessPoints = []
        self.bssidToAPMap = [:]
        self.lastSeenBSSID = nil
        self.lastSeenSSID = nil
        self.lastHandoffEvent = nil
    }
}

