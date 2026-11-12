import Foundation

#if os(iOS) && !targetEnvironment(macCatalyst)
import CoreLocation
import NetworkExtension
#endif

// MARK: - DTO de Conexão Wi-Fi

public struct WiFiConnectionInfo: Sendable, Equatable, Codable {
    public let ssid: String?
    public let bssid: String?
    public let timestamp: Date

    public init(ssid: String? = nil, bssid: String? = nil, timestamp: Date = Date()) {
        self.ssid = ssid
        self.bssid = WiFiBSSIDNormalizer.normalize(bssid)
        self.timestamp = timestamp
    }
}

// MARK: - Protocolo do Serviço

public protocol WiFiConnectionInfoServiceProtocol: Sendable {
    func fetchCurrentConnectionInfo() async -> WiFiConnectionInfo?
    func requestAuthorizationIfNeeded() async
}

// MARK: - Autorizador Contextual de Localização (Exclusivo para leitura de SSID/BSSID)

#if os(iOS) && !targetEnvironment(macCatalyst)
@MainActor
final class WiFiLocationAuthorizer: NSObject, CLLocationManagerDelegate {
    static let shared = WiFiLocationAuthorizer()
    private var locationManager: CLLocationManager?

    override private init() {
        super.init()
    }

    func requestWhenInUseAuthorizationIfNeeded() {
        if locationManager == nil {
            let manager = CLLocationManager()
            manager.delegate = self
            self.locationManager = manager
        }

        guard let manager = locationManager else { return }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }
}
#endif

// MARK: - Implementação Nativa do Serviço

public final class WiFiConnectionInfoService: WiFiConnectionInfoServiceProtocol, @unchecked Sendable {
    public static let shared = WiFiConnectionInfoService()

    private let timeoutNanoseconds: UInt64

    public init(timeoutSeconds: Double = 2.0) {
        self.timeoutNanoseconds = UInt64(timeoutSeconds * 1_000_000_000)
    }

    public func requestAuthorizationIfNeeded() async {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        await MainActor.run {
            WiFiLocationAuthorizer.shared.requestWhenInUseAuthorizationIfNeeded()
        }
        #endif
    }

    public func fetchCurrentConnectionInfo() async -> WiFiConnectionInfo? {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        // Wrapper com timeout determinístico defensivo de até 2s (recomendação Gael)
        return await withTaskGroup(of: WiFiConnectionInfo?.self) { group in
            // Worker de consulta assíncrona ao NEHotspotNetwork
            group.addTask {
                await withCheckedContinuation { continuation in
                    NEHotspotNetwork.fetchCurrent { network in
                        guard let network else {
                            continuation.resume(returning: nil)
                            return
                        }

                        let rawSSID = network.ssid
                        let rawBSSID = network.bssid
                        let normalizedBSSID = WiFiBSSIDNormalizer.normalize(rawBSSID)

                        guard rawSSID != nil || normalizedBSSID != nil else {
                            continuation.resume(returning: nil)
                            return
                        }

                        let info = WiFiConnectionInfo(
                            ssid: rawSSID,
                            bssid: normalizedBSSID,
                            timestamp: Date()
                        )
                        continuation.resume(returning: info)
                    }
                }
            }

            // Watchdog de timeout para evitar travamento caso o subsistema não responda
            group.addTask { [timeoutNanoseconds] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }

            // O primeiro a retornar define o resultado
            let firstResult = await group.next() ?? nil
            group.cancelAll()
            return firstResult
        }
        #else
        // Fallback em ambientes macOS / CLI para compilação segura e swift test
        return nil
        #endif
    }
}

// MARK: - Mock para Testes Automatizados e Previews

public final class MockWiFiConnectionInfoService: WiFiConnectionInfoServiceProtocol, @unchecked Sendable {
    public var mockSSID: String?
    public var mockBSSID: String?
    public var shouldReturnNil: Bool
    public var simulateDelayNanoseconds: UInt64
    public private(set) var authorizationRequested: Bool = false

    public init(
        mockSSID: String? = "MinhaCasa",
        mockBSSID: String? = "AA:BB:CC:10:01:01",
        shouldReturnNil: Bool = false,
        simulateDelayNanoseconds: UInt64 = 0
    ) {
        self.mockSSID = mockSSID
        self.mockBSSID = mockBSSID
        self.shouldReturnNil = shouldReturnNil
        self.simulateDelayNanoseconds = simulateDelayNanoseconds
    }

    public func requestAuthorizationIfNeeded() async {
        self.authorizationRequested = true
    }

    public func fetchCurrentConnectionInfo() async -> WiFiConnectionInfo? {
        if simulateDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: simulateDelayNanoseconds)
        }

        if shouldReturnNil {
            return nil
        }

        guard mockSSID != nil || mockBSSID != nil else {
            return nil
        }

        return WiFiConnectionInfo(
            ssid: mockSSID,
            bssid: mockBSSID,
            timestamp: Date()
        )
    }
}

