import Foundation
import Network
import Combine

public final class NetworkMonitorService: ObservableObject, @unchecked Sendable {
    public static let shared = NetworkMonitorService()

    @Published public private(set) var isConnected: Bool = true
    @Published public private(set) var isWiFiConnected: Bool = true
    @Published public private(set) var isCellular: Bool = false
    @Published public private(set) var currentSSID: String = "Rede Wi-Fi Conectada"

    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.linka.assist.networkmonitor")

    public init() {
        self.monitor = NWPathMonitor()
        startMonitoring()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConnected = (path.status == .satisfied)
                self.isWiFiConnected = path.usesInterfaceType(.wifi)
                self.isCellular = path.usesInterfaceType(.cellular)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }

    /// Verificação síncrona thread-safe do estado atual do path
    public nonisolated func checkCurrentStatus() -> (isWiFi: Bool, isConnected: Bool) {
        let path = monitor.currentPath
        let satisfied = (path.status == .satisfied)
        let wifi = path.usesInterfaceType(.wifi)
        return (wifi, satisfied)
    }

    /// Fluxo assíncrono de mudanças na conectividade Wi-Fi
    public nonisolated func wiFiStatusStream() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let pathMonitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.linka.assist.stream.\(UUID().uuidString)")
            pathMonitor.pathUpdateHandler = { path in
                let isWiFi = path.status == .satisfied && path.usesInterfaceType(.wifi)
                continuation.yield(isWiFi)
            }
            continuation.onTermination = { @Sendable _ in
                pathMonitor.cancel()
            }
            pathMonitor.start(queue: queue)
        }
    }

    #if DEBUG
    /// Permite simulação programática de queda ou reconexão Wi-Fi para testes automatizados
    public func simulateWiFiStatusChange(isWiFi: Bool) {
        self.isWiFiConnected = isWiFi
        if !isWiFi {
            self.isConnected = false
        }
    }
    #endif
}
