import Foundation
import Network

/// Fatos locais usados pela recuperação de falha. Não contém SSID, BSSID, IP
/// nem uma conclusão sobre roteador, operadora ou DNS.
public enum ConnectivityPathStatus: String, Equatable, Sendable {
    case satisfied
    case unavailable
    case requiresConnection
}

public enum ConnectivityInterfaceKind: String, Equatable, Sendable {
    case wifi
    case cellular
    case wiredEthernet
    case other
    case unknown
}

public struct ConnectivityPathSnapshot: Equatable, Sendable {
    public let status: ConnectivityPathStatus
    public let interface: ConnectivityInterfaceKind

    public init(status: ConnectivityPathStatus, interface: ConnectivityInterfaceKind = .unknown) {
        self.status = status
        self.interface = interface
    }
}

public protocol ConnectivityPathProviding: Sendable {
    func snapshot() async -> ConnectivityPathSnapshot
}

/// Consulta pontual do caminho do aparelho. Ela não faz sondas HTTP, não envia
/// dados e não permite inferir a causa de uma indisponibilidade.
public struct NWConnectivityPathProvider: ConnectivityPathProviding {
    public init() {}

    public func snapshot() async -> ConnectivityPathSnapshot {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.linka.connectivity-triage.path")
        monitor.start(queue: queue)
        do {
            try await Task.sleep(nanoseconds: 100_000_000)
        } catch {
            monitor.cancel()
            return ConnectivityPathSnapshot(status: .requiresConnection)
        }
        let path = monitor.currentPath
        monitor.cancel()

        let status: ConnectivityPathStatus
        switch path.status {
        case .satisfied: status = .satisfied
        case .requiresConnection: status = .requiresConnection
        case .unsatisfied: status = .unavailable
        @unknown default: status = .unavailable
        }

        let interface: ConnectivityInterfaceKind
        if path.usesInterfaceType(.wifi) {
            interface = .wifi
        } else if path.usesInterfaceType(.cellular) {
            interface = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            interface = .wiredEthernet
        } else if path.status == .satisfied {
            interface = .other
        } else {
            interface = .unknown
        }
        return ConnectivityPathSnapshot(status: status, interface: interface)
    }
}

public enum ConnectivityTriageOutcome: String, Equatable, Sendable {
    /// Não há caminho de rede disponível neste instante.
    case noNetworkPath
    case internetReachable
    case dnsResolutionUnavailable
    case captivePortalSuspected
    /// O sistema ainda precisa estabelecer um caminho. Não é um diagnóstico.
    case inconclusive
}

public struct ConnectivityTriageReport: Equatable, Sendable {
    public let outcome: ConnectivityTriageOutcome
    public let path: ConnectivityPathSnapshot

    public init(outcome: ConnectivityTriageOutcome, path: ConnectivityPathSnapshot) {
        self.outcome = outcome
        self.path = path
    }
}

/// Classificador puro para manter copy e apresentação fora da sondagem.
public enum ConnectivityTriageClassifier {
    public static func classify(
        _ path: ConnectivityPathSnapshot,
        probes: [ConnectivityHTTPProbeOutcome] = []
    ) -> ConnectivityTriageReport {
        let outcome: ConnectivityTriageOutcome
        switch path.status {
        case .unavailable:
            outcome = .noNetworkPath
        case .satisfied:
            if probes.contains(where: { $0 == .success }) {
                outcome = .internetReachable
            } else if !probes.isEmpty && probes.allSatisfy({ $0 == .dnsFailure }) {
                outcome = .dnsResolutionUnavailable
            } else if probes.contains(where: { $0 == .redirected || $0 == .unexpectedResponse }) {
                outcome = .captivePortalSuspected
            } else {
                outcome = .inconclusive
            }
        case .requiresConnection:
            outcome = .inconclusive
        }
        return ConnectivityTriageReport(outcome: outcome, path: path)
    }
}

public enum ConnectivityHTTPProbeOutcome: Equatable, Sendable {
    case success
    case redirected
    case unexpectedResponse
    case dnsFailure
    case timeout
    case transportFailure
}

public protocol ConnectivityHTTPProbing: Sendable {
    func probe(_ endpoint: URL) async throws -> ConnectivityHTTPProbeOutcome
}

public struct URLSessionConnectivityHTTPProbe: ConnectivityHTTPProbing {
    private let configurationFactory: @Sendable () -> URLSessionConfiguration

    public init(configurationFactory: @escaping @Sendable () -> URLSessionConfiguration = { URLSessionConfiguration.ephemeral }) {
        self.configurationFactory = configurationFactory
    }

    public func probe(_ endpoint: URL) async throws -> ConnectivityHTTPProbeOutcome {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let configuration = configurationFactory()
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let redirectDelegate = RedirectBlockingDelegate()
        let session = URLSession(configuration: configuration, delegate: redirectDelegate, delegateQueue: nil)
        do {
            try Task.checkCancellation()
            let (_, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { return .transportFailure }
            if response.url != endpoint { return .redirected }
            return (200..<300).contains(http.statusCode) ? .success : .unexpectedResponse
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if redirectDelegate.didBlockRedirect { return .redirected }
            switch error.code {
            case .cannotFindHost, .dnsLookupFailed: return .dnsFailure
            case .timedOut: return .timeout
            default: return .transportFailure
            }
        } catch {
            return .transportFailure
        }
    }
}

final class RedirectBlockingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var blockedRedirect = false

    var didBlockRedirect: Bool {
        lock.lock()
        defer { lock.unlock() }
        return blockedRedirect
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        lock.lock()
        blockedRedirect = true
        lock.unlock()
        completionHandler(nil)
    }
}

public struct NetworkConnectivityTriageService: Sendable {
    private let pathProvider: any ConnectivityPathProviding
    private let httpProbe: any ConnectivityHTTPProbing
    private let endpoints: [URL]

    public init(
        pathProvider: any ConnectivityPathProviding = NWConnectivityPathProvider(),
        httpProbe: any ConnectivityHTTPProbing = URLSessionConnectivityHTTPProbe(),
        endpoints: [URL] = Self.defaultEndpoints
    ) {
        self.pathProvider = pathProvider
        self.httpProbe = httpProbe
        self.endpoints = endpoints
    }

    public func run() async throws -> ConnectivityTriageReport {
        try Task.checkCancellation()
        let path = await pathProvider.snapshot()
        try Task.checkCancellation()
        guard path.status == .satisfied else {
            return ConnectivityTriageClassifier.classify(path)
        }
        let outcomes = try await withThrowingTaskGroup(of: ConnectivityHTTPProbeOutcome.self) { group in
            for endpoint in endpoints {
                group.addTask { try await httpProbe.probe(endpoint) }
            }
            var collected: [ConnectivityHTTPProbeOutcome] = []
            for try await outcome in group { collected.append(outcome) }
            return collected
        }
        return ConnectivityTriageClassifier.classify(path, probes: outcomes)
    }

    public static let defaultEndpoints = [
        URL(string: "https://network-diagnostics-service.buildealabs.workers.dev/v1/health")!,
        URL(string: "https://network-diagnostics-service.buildealabs.workers.dev/v1/version")!
    ]
}
