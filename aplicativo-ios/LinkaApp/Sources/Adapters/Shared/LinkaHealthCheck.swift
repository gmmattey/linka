import Foundation
import Network
import Combine
import LinkaEngine

@MainActor
public final class LinkaHealthCheck: ObservableObject {
    @Published public private(set) var statusText: String = ""
    @Published public private(set) var isOnline: Bool = false
    @Published public private(set) var dnsMs: Double?
    @Published public private(set) var pingMs: Double?
    @Published public private(set) var jitterMs: Double?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.linka.healthcheck")
    private var isRunning = false
    private var healthTask: Task<Void, Never>?

    public init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let online = path.status == .satisfied
                self.isOnline = online
                if online {
                    self.statusText = ""
                    self.runMetrics()
                } else if path.status == .requiresConnection {
                    self.statusText = String(localized: "health.requiresConnection", defaultValue: "Requer conexão")
                    self.clearMetrics()
                } else {
                    self.statusText = String(localized: "health.offline", defaultValue: "Sem internet")
                    self.clearMetrics()
                }
            }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        isRunning = false
        healthTask?.cancel()
        healthTask = nil
        monitor.cancel()
    }
    
    private func clearMetrics() {
        dnsMs = nil
        pingMs = nil
        jitterMs = nil
    }

    private func runMetrics() {
        healthTask?.cancel()
        healthTask = Task {
            // DNS
            let dns = await SpeedTestCore.resolveDNS()

            // Ping and Jitter via idle ping probe
            let pingOutcome = await SpeedTestCore.performPingTest()

            guard !Task.isCancelled else { return }

            self.dnsMs = dns

            if case .measured(let latency, let jitter, _) = pingOutcome {
                self.pingMs = latency
                self.jitterMs = jitter
            }

            self.statusText = String(localized: "health.connected", defaultValue: "Conectado")
        }
    }
}
