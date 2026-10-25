import Foundation
import NetworkDNSBenchmark
import Network
import Security

struct DNSSystemHealth: Equatable {
    let milliseconds: Double?
}

@MainActor
final class DNSBenchmarkCoordinator: ObservableObject {
    enum State: Equatable {
        case idle
        case running
        case completed(DNSBenchmarkResult)
        case cancelled
        case failed
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var systemHealth = DNSSystemHealth(milliseconds: nil)

    private var task: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var pathIdentity: String?
    private var sessionID: UUID?
    private let pathGate = DNSPathSessionGate()

    deinit { task?.cancel() }

    func start() {
        guard task == nil else { return }
        let id = UUID()
        sessionID = id
        systemHealth = DNSSystemHealth(milliseconds: nil)
        state = .running
        LinkaAnalytics.shared.track(.diagnosticStarted(diagnosticType: "dns_benchmark"))
        observePathForSession()
        let healthTask = DNSSystemResolverProbe.start()
        Task { @MainActor [weak self] in
            let health = await healthTask.value
            guard self?.sessionID == id else { return }
            self?.systemHealth = health
        }
        task = Task { [weak self] in
            guard let self else { return }
            let result = await DoHBenchmarkExecutor().run()
            // Uma sessão antiga não pode tocar no estado de uma sessão nova.
            guard self.sessionID == id else { return }
            guard !Task.isCancelled else {
                self.state = .cancelled
                self.task = nil
                self.sessionID = nil
                LinkaAnalytics.shared.track(.diagnosticCompleted(diagnosticType: "dns_benchmark", outcome: "cancelled"))
                return
            }
            let newState = DNSBenchmarkCoordinator.state(for: result)
            self.state = newState
            self.task = nil
            self.sessionID = nil
            self.stopPathObservation()
            let outcome: String
            switch newState {
            case .completed: outcome = "success"
            case .failed: outcome = "failed"
            default: outcome = "other"
            }
            LinkaAnalytics.shared.track(.diagnosticCompleted(diagnosticType: "dns_benchmark", outcome: outcome))
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        sessionID = nil
        state = .cancelled
        stopPathObservation()
        LinkaAnalytics.shared.track(.diagnosticCompleted(diagnosticType: "dns_benchmark", outcome: "cancelled"))
    }

    /// Uma troca de conexão invalida a sessão efêmera em vez de misturar
    /// amostras de redes diferentes.
    func connectionDidChange() { cancel() }

    private func observePathForSession() {
        let monitor = NWPathMonitor(); pathMonitor = monitor; pathIdentity = nil; pathGate.reset()
        monitor.pathUpdateHandler = { [weak self] path in
            let identity = "\(String(describing: path.status)):\(path.usesInterfaceType(.wifi)):\(path.usesInterfaceType(.cellular)):\(path.usesInterfaceType(.wiredEthernet))"
            Task { @MainActor in
                guard let self else { return }
                self.pathGate.receiveUpdate { self.connectionDidChange() }
                self.pathIdentity = identity
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }
    private func stopPathObservation() { pathMonitor?.cancel(); pathMonitor = nil; pathIdentity = nil }

    private static func state(for result: DNSBenchmarkResult) -> State {
        result.candidates.contains { !$0.isInconclusive } ? .completed(result) : .failed
    }
}

private enum DNSSystemResolverProbe {
    static func start() -> Task<DNSSystemHealth, Never> {
        return Task.detached(priority: .utility) {
            let started = ContinuousClock.now
            var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
            var result: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo("example.com", nil, &hints, &result)
            if let result { freeaddrinfo(result) }
            guard status == 0 else { return DNSSystemHealth(milliseconds: nil) }
            let duration = started.duration(to: .now)
            return DNSSystemHealth(milliseconds: Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1_000)
        }
    }
}

private struct DoHBenchmarkExecutor: Sendable {
    func run() async -> DNSBenchmarkResult {
        var outcomes = Dictionary(uniqueKeysWithValues: DNSProviderCatalog.all.map { ($0.id, [DNSProbeOutcome]()) })
        for round in 0..<DNSBenchmarkPlan.rounds {
            let nonce = String(UUID().uuidString.prefix(12)).replacingOccurrences(of: "-", with: "")
            let name = DNSBenchmarkPlan.syntheticQueryName(round: round, nonce: nonce)
            let transactionID = UInt16.random(in: .min ... .max)
            let payload = DNSWireQuery.makeAQuery(name: name, transactionID: transactionID)
            for provider in DNSBenchmarkPlan.providers(forRound: round) {
                guard !Task.isCancelled else {
                    outcomes[provider.id, default: []].append(.cancelled)
                    continue
                }
                outcomes[provider.id, default: []].append(await probe(provider: provider, payload: payload))
            }
        }
        return DNSBenchmarkResult(candidates: DNSProviderCatalog.all.map { DNSBenchmarkCandidate(provider: $0, samples: outcomes[$0.id] ?? []) })
    }

    private func probe(provider: DNSProvider, payload: Data) async -> DNSProbeOutcome {
        let started = ContinuousClock.now
        do {
            let data = try await DoHBootstrapTransport.request(provider: provider, payload: payload, timeout: .seconds(2))
            try Task.checkCancellation()
            guard DNSWireResponse.isValid(data, for: payload) else { return .failed }
            let duration = started.duration(to: .now)
            return .response(milliseconds: Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1_000)
        } catch is CancellationError {
            return .cancelled
        } catch let error as URLError where error.code == .timedOut {
            return .timedOut
        } catch {
            return .failed
        }
    }
}

/// Transporte HTTP/1.1 sobre TLS com o socket conectado diretamente a um IP
/// bootstrap. SNI e Host continuam sendo o hostname certificado do provedor;
/// assim a resolução do sistema não participa da transação comparada.
private enum DoHBootstrapTransport {
    static func request(provider: DNSProvider, payload: Data, timeout: Duration) async throws -> Data {
        guard let host = provider.dohURL.host,
              let bootstrap = provider.bootstrapIPs.first else { throw URLError(.badURL) }
        let port = provider.dohURL.port ?? 443
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, host)
        sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let connection = NWConnection(host: NWEndpoint.Host(bootstrap), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: parameters)
        return try await DNSRequestDeadline.run(timeout: timeout, onStop: {
            connection.cancel()
        }) {
            try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                try await ready(connection)
        let path = provider.dohURL.path.isEmpty ? "/dns-query" : provider.dohURL.path
        let head = "POST \(path) HTTP/1.1\r\nHost: \(host)\r\nAccept: application/dns-message\r\nContent-Type: application/dns-message\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        try await send(Data(head.utf8) + payload, over: connection)
                let response = try await receive(over: connection, parser: HTTPResponseParser())
                    connection.cancel(); return response
                }
                return try await group.next()!
            }
        }
    }

    private static func ready(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = DNSConnectionCompletionGate()
            func resolve(_ result: Result<Void, Error>) {
                gate.resolveOnce {
                    connection.stateUpdateHandler = nil
                    continuation.resume(with: result)
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: resolve(.success(()))
                case .failed(let error): resolve(.failure(error))
                case .cancelled: resolve(.failure(CancellationError()))
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
        }
    }
    private static func send(_ data: Data, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }
    private static func receive(over connection: NWConnection, parser: HTTPResponseParser) async throws -> Data {
        var parser = parser
        let fragment: Data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, error in
                if let error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: URLError(.badServerResponse)) }
            }
        }
        if let body = try parser.append(fragment) { return body }
        return try await receive(over: connection, parser: parser)
    }
    /*private static func receive(over connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, error in
                if let error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: URLError(.badServerResponse)) }
            }
        }
    }
    private static func body(from response: Data) throws -> Data {
        guard let boundary = response.range(of: Data("\r\n\r\n".utf8)),
              let header = String(data: response[..<boundary.lowerBound], encoding: .utf8),
              header.hasPrefix("HTTP/1.1 200") else { throw URLError(.badServerResponse) }
        return Data(response[boundary.upperBound...])
    }*/
}

/// A fronteira do deadline é isolada para que timeout e cancelamento sejam
/// exercitados sem depender de rede real. O callback sempre encerra o recurso
/// subjacente (no transporte real, o socket) antes de a operação retornar.
enum DNSRequestDeadline {
    static func run<T: Sendable>(
        timeout: Duration,
        onStop: @escaping @Sendable () -> Void,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withTaskCancellationHandler(operation: {
            try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask(operation: operation)
                group.addTask {
                    try await Task.sleep(for: timeout)
                    onStop()
                    throw URLError(.timedOut)
                }
                defer {
                    group.cancelAll()
                    onStop()
                }
                return try await group.next()!
            }
        }, onCancel: onStop)
    }
}
