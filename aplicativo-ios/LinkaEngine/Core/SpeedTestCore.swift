// Justificativa de Arquitetura (validarModularidade):
// Este arquivo ultrapassa 400 linhas porque centraliza toda a máquina de estados e os invariantes do motor de medição.
// A separação forçada poderia vazar os estados da medição e enfraquecer o isolamento entre tarefas.
import Foundation
import Network

/// Contador thread-safe de bytes trafegados por fase. Isolamento via actor
/// (mais confiável que NSLock + delegate custom em iOS 26+).
actor ByteCounter {
    private var value: Int64 = 0
    private var completions: [(date: Date, bytes: Int64)] = []
    func add(_ n: Int64, at date: Date = Date()) {
        value += n
        completions.append((date, n))
    }
    func total() -> Int64 { value }
    func total(completedAfter date: Date) -> Int64 {
        completions.lazy.filter { $0.date >= date }.map(\.bytes).reduce(0, +)
    }
}

/// Coletor thread-safe de amostras double por fase (issue #52). Usado para
/// juntar as sondagens de latência sob carga coletadas em paralelo à
/// transferência real, sem acoplar a task de amostragem ao estado do ator.
actor LatencyProbeCollector {
    private var values: [Double] = []
    private var timeoutCount = 0
    func record(_ value: Double?) {
        if let value, value.isFinite, value > 0 {
            values.append(value)
        } else {
            timeoutCount += 1
        }
    }
    func snapshot() -> (values: [Double], timeoutCount: Int) { (values, timeoutCount) }
}

/// Contador thread-safe de falhas fatais de transporte consecutivas por fase
/// (issue #66) — mesmo padrão ator de `ByteCounter`. Compartilhado entre os
/// `streams` concorrentes de uma fase: cada falha classificada como fatal
/// por `SpeedTestCore.isFatalTransportError` incrementa; qualquer sucesso de
/// qualquer stream zera, porque um sucesso concorrente já prova que a
/// conexão de transporte não está de fato perdida.
actor FatalErrorTracker {
    private var consecutiveCount: Int = 0
    func recordFailure() -> Int {
        consecutiveCount += 1
        return consecutiveCount
    }
    func recordSuccess() {
        consecutiveCount = 0
    }
    func currentCount() -> Int { consecutiveCount }
}

/// Abstrai a origem do dado bruto de provedor (hoje ipinfo.io) para permitir
/// injeção em teste, sem acoplar `SpeedTestCore` a `URLSession` diretamente.
public protocol ProviderOrgLookup: Sendable {
    /// Retorna o campo `org` bruto (ex.: "AS27699 TELEFÔNICA BRASIL S.A")
    /// ou `nil` se a resposta não trouxer o dado. Lança em erro de rede.
    func fetchOrg() async throws -> String?
}

/// Implementação real: consulta https://ipinfo.io/json.
public struct IPInfoOrgLookup: ProviderOrgLookup {
    public init() {}

    public func fetchOrg() async throws -> String? {
        guard let url = URL(string: "https://ipinfo.io/json") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["org"] as? String
    }
}

/// Abstrai a checagem de conectividade de rede (issue #66) para permitir
/// injeção em teste, no mesmo padrão de `ProviderOrgLookup`/`IPInfoOrgLookup`
/// — sem essa abstração, testar o caminho "offline" exigiria desligar a
/// rede de verdade durante o teste.
public protocol PathStatusProvider: Sendable {
    /// `true` quando há conectividade de rede no momento da checagem.
    func hasConnectivity() async -> Bool
}

/// Guarda thread-safe de resumo único (issue #66): `NWPathMonitor` pode
/// disparar `pathUpdateHandler` mais de uma vez antes de `cancel()` surtir
/// efeito — sem isso, a segunda chamada resumiria a continuation duas vezes
/// e provocaria crash em runtime.
private final class ResumeOnceGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    /// `true` na primeira chamada; `false` em qualquer chamada seguinte.
    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        return true
    }
}

/// Implementação real: consulta o `NWPathMonitor` do sistema.
public struct NWPathStatusProvider: PathStatusProvider {
    public init() {}

    public func hasConnectivity() async -> Bool {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "PathStatusProvider")
        let resumeGuard = ResumeOnceGuard()
        return await withCheckedContinuation { continuation in
            monitor.pathUpdateHandler = { path in
                guard resumeGuard.tryResume() else { return }
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: queue)
        }
    }
}

/// Relógio da medição. Produção mantém a janela de 2s + 10s; a variante
/// interna injetável existe apenas para executar o mesmo ciclo de fases em
/// testes determinísticos, sem transformar a suíte em um teste de 30s.
struct SpeedTestTiming: Sendable {
    let phaseMinDuration: TimeInterval
    let phaseMaxDuration: TimeInterval
    let loadWarmupDuration: TimeInterval
    let minimumUsefulLoadDuration: TimeInterval
    let sampleInterval: TimeInterval
    let latencyProbeInterval: TimeInterval
    let phaseTransitionDelay: TimeInterval
    let baselineRemediationDrainDelay: TimeInterval

    static let production = SpeedTestTiming(
        phaseMinDuration: 12,
        phaseMaxDuration: 18,
        loadWarmupDuration: 2,
        minimumUsefulLoadDuration: 10,
        sampleInterval: 0.3,
        latencyProbeInterval: 1,
        phaseTransitionDelay: 0.5,
        baselineRemediationDrainDelay: 0.5
    )
}

public actor SpeedTestCore {

    // ----------------------------------------------------------------
    // Duração adaptativa por fase (issue #62).
    //
    // O preset anterior usava 18s fixos em download e upload, herdados do
    // preset "pesado" do SignallQ — adequado para métodos de diagnóstico
    // mais profundos, desnecessário para o objetivo do Linka (medir rápido
    // e mostrar resultado). Em vez de um teto fixo, cada fase roda até a
    // vazão amostrada convergir (ver `hasConverged`/`shouldStopPhase`),
    // respeitando sempre um piso (`phaseMinDuration`) e um teto
    // (`phaseMaxDuration`) conhecidos:
    //
    //   - `phaseMinDuration` (12s) garante dois segundos de warm-up e dez
    //     segundos úteis de carga antes de sequer considerar encerrar —
    //     evita "convergência" espúria por poucas amostras iniciais.
    //   - `phaseMaxDuration` (18s) preserva o teto de hoje: em conexões
    //     instáveis que nunca convergem, o consumo de dados e o tempo
    //     total no pior caso não pioram em relação ao comportamento atual.
    //
    // Mesmos valores para download e upload — nenhuma evidência coletada
    // (ver PR #62) justifica um piso/teto assimétrico entre as duas fases;
    // ambas usam os mesmos 4 streams e a mesma técnica de amostragem.
    // ----------------------------------------------------------------
    private let providerLookup: ProviderOrgLookup
    private let providerEnrichmentTimeout: TimeInterval
    private let pathStatusProvider: PathStatusProvider
    private let locationTracker: LocationTracker
    private let environment: SpeedTestEnvironment
    private let transport: any SpeedTestTransport
    private let timing: SpeedTestTiming

    /// - Parameters:
    ///   - providerLookup: fonte do dado bruto de provedor. Injetável para testes;
    ///     produção usa `IPInfoOrgLookup()` por padrão.
    ///   - providerEnrichmentTimeout: teto de tempo, em segundos, dedicado exclusivamente
    ///     ao enriquecimento de provedor. Roda em paralelo à medição, nunca soma ao
    ///     tempo de nenhuma fase (ping/download/upload).
    ///   - pathStatusProvider: fonte da checagem de conectividade prévia ao ping
    ///     (issue #66). Injetável para testes; produção usa `NWPathStatusProvider()`
    ///     por padrão.
    public init(
        providerLookup: ProviderOrgLookup = IPInfoOrgLookup(),
        providerEnrichmentTimeout: TimeInterval = 2.0,
        pathStatusProvider: PathStatusProvider = NWPathStatusProvider(),
        environment: SpeedTestEnvironment = .cloudflare,
        transport: any SpeedTestTransport = URLSessionSpeedTestTransport()
    ) {
        self.providerLookup = providerLookup
        self.providerEnrichmentTimeout = providerEnrichmentTimeout
        self.pathStatusProvider = pathStatusProvider
        self.locationTracker = LocationTracker()
        self.environment = environment
        self.transport = transport
        self.timing = .production
    }

    init(
        providerLookup: ProviderOrgLookup,
        providerEnrichmentTimeout: TimeInterval = 2.0,
        pathStatusProvider: PathStatusProvider,
        environment: SpeedTestEnvironment,
        transport: any SpeedTestTransport,
        timing: SpeedTestTiming
    ) {
        self.providerLookup = providerLookup
        self.providerEnrichmentTimeout = providerEnrichmentTimeout
        self.pathStatusProvider = pathStatusProvider
        self.locationTracker = LocationTracker()
        self.environment = environment
        self.transport = transport
        self.timing = timing
    }

    /// Starts the speed test and yields updates via an AsyncThrowingStream
    public func runTest() -> AsyncThrowingStream<MeasurementState, Error> {
        return AsyncThrowingStream { continuation in
            let innerTask = Task {
                do {
                    var state = MeasurementState(progress: 0.0, phase: .ping)
                    
                    if let location = locationTracker.getCurrentLocationIfPermitted() {
                        state.location = location
                    }

                    let testStart = Date()

                    let monitor = NWPathMonitor()
                    let queue = DispatchQueue(label: "NetworkMonitor")
                    monitor.start(queue: queue)

                    // Small delay to allow NWPathMonitor to fetch the initial path
                    try? await Task.sleep(nanoseconds: 100_000_000)

                    if monitor.currentPath.usesInterfaceType(.wifi) {
                        state.networkType = .wifi
                    } else if monitor.currentPath.usesInterfaceType(.cellular) {
                        state.networkType = .cellular
                    } else {
                        state.networkType = .unknown
                    }
                    monitor.cancel()

                    // ----------------------------------------------------
                    // Checagem de conectividade prévia ao ping (issue #66).
                    // Sem rede desde o início não é uma falha transitória
                    // de fase — é um estado explícito: pára aqui, antes de
                    // gastar qualquer request, e devolve o fato tipado
                    // (`.offline`) em vez de deixar ping/download/upload
                    // falharem silenciosamente um a um.
                    // ----------------------------------------------------
                    guard await pathStatusProvider.hasConnectivity() else {
                        let errored = Self.errorState(preserving: state, reason: .offline)
                        continuation.yield(errored)
                        continuation.finish()
                        return
                    }

                    // Descoberta de provedor (ipinfo.io) desacoplada do caminho crítico:
                    // dispara como Task detached em paralelo ao ping/download/upload e
                    // nunca bloqueia nenhum yield nem compete pelo executor do ator com
                    // as fases de medição. Tem timeout próprio, bem menor que qualquer
                    // fase — se falhar ou estourar o prazo, o resultado segue válido sem
                    // provedor (nil), sem inventar "Desconhecido".
                    let providerTask = Task.detached(priority: .utility) { [providerLookup, providerEnrichmentTimeout] in
                        await SpeedTestCore.resolveProviderName(
                            lookup: providerLookup,
                            timeout: providerEnrichmentTimeout
                        )
                    }

                    continuation.yield(state)

                    // Resolução DNS cronometrada (Expert Mode) — dispara em
                    // paralelo ao ping, nunca soma ao tempo da fase: mesma
                    // filosofia do `providerTask` acima (desacoplado do
                    // caminho crítico, timeout próprio menor que a fase).
                    let dnsTask = Task.detached(priority: .utility) {
                        await SpeedTestCore.resolveDNS()
                    }

                    // Measure Ping and Packet Loss
                    let pingOutcome = try await SpeedTestCore.performDetailedPingTest(
                        environment: environment,
                        transport: transport
                    )

                    // `performPingTest()` roda até 10 sondagens sequenciais
                    // sem checar cancelamento internamente — sem este ponto
                    // de corte, um cancelamento chegado durante o ping só
                    // seria percebido depois de entrar na fase de download
                    // (issue #47, rodada 2). `runPhaseTimeBased` já checa
                    // `Task.isCancelled` no próprio loop de amostragem, mas
                    // esta é a única lacuna real anterior a ele.
                    try Task.checkCancellation()

                    let initialBaseline: BaselineMeasurement
                    switch pingOutcome {
                    case .measured(let pingMs, let jitterMs, let lossPercent, let baseline, let probeEvidence):
                        state.ping = pingMs
                        state.jitter = jitterMs
                        state.packetLossPercent = lossPercent
                        state.packetProbeEvidence = probeEvidence
                        initialBaseline = baseline
                    case .fatalFailure(let reason):
                        // Falha fatal já durante o ping (issue #85) — antes
                        // desta correção, uma conexão morta gastava os ~11s
                        // completos de `performPingTest` antes de a fase de
                        // download sequer conseguir detectar a perda de
                        // transporte. Nenhum dado real foi medido ainda
                        // nesta fase, então não há nada além do offline check
                        // anterior para preservar.
                        dnsTask.cancel()
                        let errored = Self.errorState(preserving: state, reason: reason)
                        continuation.yield(errored)
                        continuation.finish()
                        return
                    }

                    // `performPingTest` (~10 sondagens sequenciais, até ~1s
                    // cada) já deve ter dado tempo de sobra ao DNS (timeout
                    // de 2s). Se não, aguardamos o restante aqui — sem
                    // bloquear além do timeout próprio da sondagem.
                    state.dnsResolutionMs = await dnsTask.value

                    state.phase = .download
                    state.progress = 0.1
                    continuation.yield(state)

                    // ----------------------------------------------------
                    // Measure Download
                    // 12s–18s adaptativo (issue #62), 4 streams, 10MB chunk.
                    // Chunks menores + menos streams reduzem drasticamente a
                    // chance de tomar 429 do Cloudflare em uso real (cada
                    // request pesa 60% menos e a rajada por segundo cai pela
                    // metade).
                    // ----------------------------------------------------
                    let downloadOutcome = try await runPhaseTimeBased(
                        phase: .download,
                        minDuration: timing.phaseMinDuration,
                        maxDuration: timing.phaseMaxDuration,
                        streams: 4,
                        bytes: 10_000_000, // 10 MB
                        state: &state,
                        continuation: continuation
                    )

                    let downloadEvidence: EngineLoadedPhaseEvidence?
                    switch downloadOutcome {
                    case .measured(let measurement):
                        state.downloadSpeed = measurement.speed
                        downloadEvidence = measurement.evidence
                    case .fatalFailure(let reason):
                        // Preserva ping/jitter/packetLoss já capturados nesta
                        // fase anterior — só marca o fato tipado, sem
                        // descartar dado real já medido (AGENTS.md §8).
                        let errored = Self.errorState(preserving: state, reason: reason)
                        continuation.yield(errored)
                        continuation.finish()
                        return
                    }

                    state.phase = .upload
                    state.progress = 0.5
                    continuation.yield(state)

                    // Pausa dramática para o respiro visual e percepção de mudança de fase
                    try? await Task.sleep(nanoseconds: UInt64(timing.phaseTransitionDelay * 1_000_000_000))

                    // ----------------------------------------------------
                    // Measure Upload
                    // 12s–18s adaptativo (issue #62), 4 streams, 5MB chunk.
                    // Mesmo motivo do download: agressividade reduzida pra
                    // fugir de 429.
                    // ----------------------------------------------------
                    let uploadOutcome = try await runPhaseTimeBased(
                        phase: .upload,
                        minDuration: timing.phaseMinDuration,
                        maxDuration: timing.phaseMaxDuration,
                        streams: 4,
                        bytes: 5_000_000, // 5 MB
                        state: &state,
                        continuation: continuation
                    )

                    let uploadEvidence: EngineLoadedPhaseEvidence?
                    switch uploadOutcome {
                    case .measured(let measurement):
                        state.uploadSpeed = measurement.speed
                        uploadEvidence = measurement.evidence
                    case .fatalFailure(let reason):
                        // Preserva o download já medido (e ping/jitter) —
                        // mesma regra do aborto na fase de download acima.
                        let errored = Self.errorState(preserving: state, reason: reason)
                        continuation.yield(errored)
                        continuation.finish()
                        return
                    }

                    let finalBaseline = try await Self.remediatedBaselineIfNeeded(
                        initial: initialBaseline,
                        download: downloadEvidence,
                        upload: uploadEvidence,
                        environment: environment,
                        transport: transport,
                        drainDelay: timing.baselineRemediationDrainDelay
                    )
                    try Task.checkCancellation()
                    state.ping = finalBaseline.statistics?.medianMs ?? state.ping
                    state.loadResponsiveness = EngineLoadResponsivenessEvidence(
                        environmentIdentifier: environment.identifier,
                        integrity: Self.loadIntegrity(
                            baseline: finalBaseline.statistics,
                            download: downloadEvidence,
                            upload: uploadEvidence,
                            baselineRemediationFailed: finalBaseline.remediationFailed
                        ),
                        baseline: finalBaseline.statistics,
                        download: downloadEvidence,
                        upload: uploadEvidence
                    )

                    // A referência regional é uma evidência adicional do
                    // resultado formal. Ela nunca roda no monitor vivo e não
                    // altera download/upload; ausência de eco UDP só deixa
                    // Jogos inconclusivo.
                    state.regionalGameReference = await GameLiftRegionalReferenceProbe().measure()
                    try Task.checkCancellation()

                    // Anexa o provedor somente aqui, na virada para o resultado final.
                    // A essa altura download (18s) + upload (18s) já consumiram muito
                    // mais tempo que o timeout de enriquecimento (2s por padrão), então
                    // a Task já terminou (sucesso, timeout ou falha) e este await não
                    // introduz espera real nem atrasa o resultado. Se por algum motivo
                    // ainda estiver pendente, o próprio timeout interno da Task garante
                    // que ela não segura o resultado além do prazo dedicado ao enriquecimento.
                    state.provider = await providerTask.value

                    state.phase = .result
                    state.progress = 1.0
                    state.duration = Date().timeIntervalSince(testStart)
                    continuation.yield(state)

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // Propaga o cancelamento da consumidora até o motor (issue #47,
            // rodada 2 — bug real reportado por Marcelo no PR #91):
            // `AsyncThrowingStream` por padrão não cancela sozinho a Task que
            // produz os valores quando a Task que consome (`for try await`
            // em `SpeedTestViewModel.startTest()`) é cancelada — a stream só
            // recebe `onTermination`, e sem este handler `innerTask`
            // continuava batendo download/upload reais mesmo depois de
            // "Cancelar"/"Pular". `onTermination` dispara tanto quando a
            // consumidora cancela quanto quando a stream termina normalmente
            // (`.finished`) — cancelar `innerTask` numa Task já finalizada é
            // no-op seguro, então não precisa distinguir os dois casos aqui.
            continuation.onTermination = { @Sendable _ in
                innerTask.cancel()
            }
        }
    }

    /// Resultado de uma fase de transferência (issue #66): ou ela produziu
    /// uma vazão medida normalmente, ou abortou por falha fatal de
    /// transporte (`shouldAbortPhase`) antes de conseguir medir nada.
    private struct PhaseMeasurement {
        let speed: Double
        let evidence: EngineLoadedPhaseEvidence
    }

    private enum PhaseOutcome {
        case measured(PhaseMeasurement)
        case fatalFailure(EngineFailureReason)
    }

    /// Resultado da fase de ping (issue #85) — mesmo espírito de
    /// `PhaseOutcome`, mas carregando os três valores que `performPingTest`
    /// produz (latência, jitter, perda de pacote) em vez de uma vazão única.
    public enum PingOutcome {
        case measured(latency: Double, jitter: Double, packetLossPercent: Double)
        case fatalFailure(EngineFailureReason)
    }

    private enum DetailedPingOutcome {
        case measured(latency: Double, jitter: Double, packetLossPercent: Double, baseline: BaselineMeasurement, probeEvidence: EnginePacketProbeEvidence)
        case fatalFailure(EngineFailureReason)
    }

    private struct BaselineMeasurement {
        let statistics: EngineLatencyStatistics?
        let remediationFailed: Bool
    }

    private func runPhaseTimeBased(
        phase: Phase,
        minDuration: TimeInterval,
        maxDuration: TimeInterval,
        streams: Int,
        bytes: Int,
        state: inout MeasurementState,
        continuation: AsyncThrowingStream<MeasurementState, Error>.Continuation
    ) async throws -> PhaseOutcome {

        let phaseStart = Date()
        let sampleInterval = timing.sampleInterval
        let counter = ByteCounter()
        let fatalErrorTracker = FatalErrorTracker()
        let measurementEnvironment = environment
        let measurementTransport = transport
        let phaseTiming = timing

        // Random payload for upload to avoid compression caching at network level.
        let payload = phase == .upload ? generateRandomPayload(size: bytes) : nil

        // ------------------------------------------------------------
        // Latência sob carga (issue #52, paridade de upload na issue #128),
        // nas fases de download e upload.
        //
        // Sonda HEAD leve (0 bytes) contra o mesmo endpoint Cloudflare,
        // concorrente à carga real dos `streams` da fase — é essa
        // concorrência (com download OU upload) que a diferencia da latência
        // ociosa de `performPingTest` (que roda isolada, antes de qualquer
        // carga). A sondagem em si (`performLoadedLatencyProbe`) sempre bate
        // no endpoint de download com HEAD de 0 bytes — o que muda por fase é
        // só a carga concorrente que ela testemunha, não a sondagem; por
        // isso a mesma função nonisolated é reaproveitada literalmente para
        // as duas fases, sem variante nem parâmetro de fase.
        //
        // Fica presa à mesma janela da fase (`phaseStart`/`maxDuration`) e é
        // cancelada assim que o loop principal termina, cedo por convergência
        // ou no teto — nunca estende a duração calibrada por #62. O
        // intervalo de 1s entre sondagens mantém o custo de dados desprezível
        // (HEAD de 0 bytes) e não compete por banda com os streams de carga.
        let latencyCollector: LatencyProbeCollector? = (phase == .download || phase == .upload)
            ? LatencyProbeCollector()
            : nil
        let latencySamplingTask: Task<Void, Never>? = latencyCollector.map { collector in
            Task.detached(priority: .utility) {
                while Date().timeIntervalSince(phaseStart) < maxDuration && !Task.isCancelled {
                    if Date().timeIntervalSince(phaseStart) >= phaseTiming.loadWarmupDuration {
                        let sample = await SpeedTestCore.performLoadedLatencyProbe(
                            environment: measurementEnvironment,
                            transport: measurementTransport
                        )
                        await collector.record(sample)
                    }
                    try? await Task.sleep(nanoseconds: UInt64(phaseTiming.latencyProbeInterval * 1_000_000_000))
                }
            }
        }

        let workersTask = Task {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<streams {
                    group.addTask {
                        // Backoff progressivo quando o servidor devolve 429 —
                        // Cloudflare rate-limita agressivamente esses endpoints
                        // sob rajada. Começa em 100ms e cresce até 2s.
                        var backoffMs: UInt64 = 100
                        while Date().timeIntervalSince(phaseStart) < maxDuration && !Task.isCancelled {
                            do {
                                let bytesGained: Int64
                                let statusCode: Int
                                if phase == .download {
                                    let response = try await measurementTransport.execute(.download(measurementEnvironment.downloadURL(bytes: bytes)))
                                    statusCode = response.statusCode
                                    bytesGained = statusCode == 200 ? Int64(response.byteCount) : 0
                                } else {
                                    guard let payload else { return }
                                    let response = try await measurementTransport.execute(.upload(measurementEnvironment.uploadEndpoint, payload))
                                    statusCode = response.statusCode
                                    bytesGained = statusCode == 200 ? Int64(payload.count) : 0
                                }
                                if bytesGained > 0 {
                                    await counter.add(bytesGained)
                                    backoffMs = 100  // sucesso — reseta backoff
                                    // Sucesso concorrente prova que o transporte não está
                                    // de fato perdido — zera a sequência de falhas fatais
                                    // acumulada por qualquer outro stream (issue #66).
                                    await fatalErrorTracker.recordSuccess()
                                } else if statusCode == 429 || statusCode >= 500 {
                                    // Rate-limit ou erro upstream — recua antes de tentar de novo.
                                    try? await Task.sleep(nanoseconds: backoffMs * 1_000_000)
                                    backoffMs = min(backoffMs * 2, 2_000)
                                }
                            } catch let urlError as URLError where SpeedTestCore.isFatalTransportError(urlError) {
                                // Falha fatal de transporte (issue #66) — distinta de erro
                                // transitório isolado. Conta pra decisão de aborto
                                // (`shouldAbortPhase`, checada no loop principal); uma
                                // pausa curta evita busy-loop batendo num host inacessível.
                                _ = await fatalErrorTracker.recordFailure()
                                try? await Task.sleep(nanoseconds: 200_000_000)
                            } catch {
                                // Erros transientes de rede — segue tentando até a fase terminar.
                            }
                        }
                    }
                }
            }
        }

        var mbpsSamples: [Double] = []
        var usefulMbpsSamples: [Double] = []
        var usefulSampleDates: [Date] = []
        var smoothedMbps: Double = 0.0
        var lastTotal: Int64 = 0

        while Date().timeIntervalSince(phaseStart) < maxDuration {
            try? await Task.sleep(nanoseconds: UInt64(sampleInterval * 1_000_000_000))
            if Task.isCancelled { break }

            let total = await counter.total()
            let deltaBytes = total - lastTotal
            lastTotal = total
            let instantMbps = (Double(deltaBytes) * 8.0) / sampleInterval / 1_000_000.0

            if instantMbps > 0 {
                smoothedMbps = smoothedMbps == 0 ? instantMbps : 0.3 * instantMbps + 0.7 * smoothedMbps
                mbpsSamples.append(instantMbps)
                if Date().timeIntervalSince(phaseStart) >= timing.loadWarmupDuration {
                    usefulMbpsSamples.append(instantMbps)
                    usefulSampleDates.append(Date())
                }

                if phase == .download {
                    state.downloadSpeed = smoothedMbps
                } else {
                    state.uploadSpeed = smoothedMbps
                }
            }

            // Progress interpolation — baseado em maxDuration (teto), não na
            // duração real da fase. Como a fase pode encerrar antes por
            // convergência (ver `shouldStopPhase` abaixo), isso evita que o
            // progresso "estoure" 1.0 sempre que termina cedo e evita um
            // salto visual brusco quando a próxima fase assume seu
            // baseProgress — motion continua só transmitindo estado, sem
            // chamar atenção pra si (AGENTS.md §6).
            let elapsed = Date().timeIntervalSince(phaseStart)
            let phaseProgress = min(elapsed / maxDuration, 1.0)
            let baseProgress = phase == .download ? 0.1 : 0.5
            let totalPhaseRange = phase == .download ? 0.4 : 0.5
            state.progress = baseProgress + (phaseProgress * totalPhaseRange)

            continuation.yield(state)

            // Aborto por falha fatal persistente (issue #66): só quando a
            // fase ainda não entregou nenhum byte real (`total == 0`) — um
            // erro isolado numa fase que já está fluindo throughput nunca
            // aborta, mesmo que a sequência de falhas fatais acumule (ver
            // `shouldAbortPhase`).
            let fatalCount = await fatalErrorTracker.currentCount()
            if Self.shouldAbortPhase(consecutiveFatalErrors: fatalCount, bytesTransferred: total) {
                workersTask.cancel()
                _ = await workersTask.result
                latencySamplingTask?.cancel()
                _ = await latencySamplingTask?.value
                return .fatalFailure(.connectionLost(phase: phase))
            }

            // Encerra a fase cedo quando a vazão amostrada já convergiu e o
            // piso mínimo já foi respeitado (issue #62) — conexões estáveis
            // terminam antes de `maxDuration`, economizando tempo, franquia
            // e bateria. Conexões instáveis seguem até `maxDuration`, igual
            // ao comportamento anterior.
            if Self.shouldStopPhase(
                samples: mbpsSamples,
                elapsed: elapsed,
                minDuration: minDuration,
                maxDuration: maxDuration
            ) {
                break
            }
        }

        workersTask.cancel()
        _ = await workersTask.result

        // Encerra a sondagem de latência sob carga na mesma virada da carga
        // real — nunca sobrevive além da janela da fase. Falha ou ausência
        // total de amostras aqui nunca lança nem afeta `downloadSpeed`/
        // `uploadSpeed` (aceite #4 da #52, preservado na paridade de upload
        // da #128): `aggregateLoadedLatency` simplesmente devolve `nil`, e o
        // resultado principal da fase (`return .measured(...)` abaixo) nunca
        // depende deste bloco.
        latencySamplingTask?.cancel()
        _ = await latencySamplingTask?.value
        let elapsedTotal = Date().timeIntervalSince(phaseStart)
        let usefulBytes = await counter.total(completedAfter: phaseStart.addingTimeInterval(timing.loadWarmupDuration))
        let valid = mbpsSamples.filter { $0 > 0 }
        let usefulDuration = max(0, elapsedTotal - timing.loadWarmupDuration)
        let saturation = Self.loadSaturation(
            usefulDuration: usefulDuration,
            usefulBytes: usefulBytes,
            usefulSampleCount: usefulMbpsSamples.count,
            usefulSampleSpan: Self.sampleSpan(usefulSampleDates),
            minimumUsefulDuration: timing.minimumUsefulLoadDuration
        )
        let phaseAverageMbps = usefulDuration > 0
            ? (Double(usefulBytes) * 8.0) / usefulDuration / 1_000_000.0
            : nil

        let evidence: EngineLoadedPhaseEvidence
        if let latencyCollector {
            let snapshot = await latencyCollector.snapshot()
            let latency = saturation == .sustained
                ? Self.latencyStatistics(
                    samples: snapshot.values,
                    timeoutCount: snapshot.timeoutCount,
                    warmupDuration: timing.loadWarmupDuration
                )
                : nil
            let aggregatedLatency = latency?.medianMs
            if phase == .download {
                state.loadedLatencyMs = aggregatedLatency
            } else {
                state.loadedLatencyUploadMs = aggregatedLatency
            }
            evidence = EngineLoadedPhaseEvidence(
                latency: latency,
                usefulDurationMs: Int((usefulDuration * 1_000).rounded()),
                bytesTransferred: usefulBytes,
                averageMbps: phaseAverageMbps,
                saturation: saturation
            )
        } else {
            evidence = EngineLoadedPhaseEvidence(
                latency: nil,
                usefulDurationMs: Int((usefulDuration * 1_000).rounded()),
                bytesTransferred: usefulBytes,
                averageMbps: phaseAverageMbps,
                saturation: saturation
            )
        }

        // Fallback: se nenhum sample instantâneo pegou nada (rede muito
        // rápida ou requisição única muito lenta), calcula pela média
        // global bytes / duração da fase — nunca retorna 0 se algum byte
        // foi contabilizado.
        let averageMbps = phaseAverageMbps ?? 0.0

        // Janela estável (últimos 65%) — mesma técnica do SignallQ, corta warmup TCP.
        let stableStart = Int(ceil(Double(valid.count) * 0.35))
        let stable = valid.count > stableStart ? Array(valid[stableStart...]) : valid
        let stableAvg = stable.isEmpty ? 0.0 : stable.reduce(0, +) / Double(stable.count)

        // Variação objetiva de vazão (issue #52): desvio relativo dentro da
        // mesma janela estável usada para `stableAvg`, com o mesmo piso de
        // robustez de `hasConverged` (>= window amostras válidas). Fica só
        // em `MeasurementState` — motor-interno nesta primeira entrega, não
        // entra no contrato canônico `NetworkMeasurement` (ver notas do
        // plano da issue #52).
        let variation = Self.throughputVariation(stableSamples: stable)
        if phase == .download {
            state.downloadThroughputVariation = variation
        } else {
            state.uploadThroughputVariation = variation
        }

        return .measured(PhaseMeasurement(speed: stableAvg > 0 ? stableAvg : averageMbps, evidence: evidence))
    }

    /// Critério de convergência de vazão (issue #62): decide se uma janela
    /// recente de amostras de mbps já está "estável o suficiente" para
    /// considerar a medição da fase concluída.
    ///
    /// `nonisolated static` de propósito — igual a `resolveProviderName`:
    /// não toca `Date()` ao vivo, não toca URLSession, não toca o estado do
    /// ator. Recebe só o array de amostras já coletadas, o que a torna
    /// inteiramente exercitável em teste com arrays sintéticos.
    ///
    /// - Parameters:
    ///   - samples: amostras de mbps instantâneo coletadas na fase até agora,
    ///     em ordem cronológica (uma por `sampleInterval`, hoje 300ms).
    ///   - window: quantas das amostras mais recentes considerar. 5 amostras
    ///     a 300ms cobre 1.5s de janela — sensível o bastante para detectar
    ///     estabilização sem reagir a um único pico/vale isolado.
    ///   - tolerance: variação relativa máxima, como fração da média da
    ///     janela, para considerar a vazão estável. 0.08 (8%) tolera o ruído
    ///     normal de uma conexão saudável sem aceitar como "estável" uma
    ///     vazão que ainda está subindo ou caindo de forma clara.
    /// - Returns: `true` quando há amostras válidas suficientes (>= `window`,
    ///   descartando zeros — que indicam ausência de dado na janela, não
    ///   vazão real) e a variação relativa entre elas está dentro de
    ///   `tolerance`. `false` quando não há amostras suficientes ainda ou a
    ///   vazão segue variando além da tolerância.
    nonisolated static func hasConverged(
        samples: [Double],
        window: Int = 5,
        tolerance: Double = 0.08
    ) -> Bool {
        let valid = samples.filter { $0 > 0 }
        guard valid.count >= window else { return false }

        let recent = Array(valid.suffix(window))
        let mean = recent.reduce(0, +) / Double(recent.count)
        guard mean > 0 else { return false }

        let maxRelativeDeviation = recent.map { abs($0 - mean) / mean }.max() ?? .infinity
        return maxRelativeDeviation <= tolerance
    }

    /// Decisão completa de "encerrar a fase agora?" (issue #62): compõe o
    /// critério de convergência (`hasConverged`) com o piso e o teto de
    /// duração da fase. `nonisolated static` pela mesma razão de
    /// `hasConverged` — sem `Date()` ao vivo, `elapsed` é passado pelo
    /// chamador, então é inteiramente testável com valores sintéticos.
    ///
    /// - Returns: `true` se `elapsed` já alcançou `maxDuration` (teto —
    ///   sempre encerra, convergindo ou não, preservando o pior caso de
    ///   tempo/consumo de dados do comportamento anterior); ou se `elapsed`
    ///   já alcançou `minDuration` **e** `hasConverged` é `true` (encerra
    ///   cedo). Caso contrário `false` — a fase continua amostrando.
    nonisolated static func shouldStopPhase(
        samples: [Double],
        elapsed: TimeInterval,
        minDuration: TimeInterval,
        maxDuration: TimeInterval,
        window: Int = 5,
        tolerance: Double = 0.08
    ) -> Bool {
        if elapsed >= maxDuration { return true }
        guard elapsed >= minDuration else { return false }
        return hasConverged(samples: samples, window: window, tolerance: tolerance)
    }

    /// Classifica um `URLError` como falha fatal de transporte ou falha
    /// transitória recuperável (issue #66).
    ///
    /// `nonisolated static` de propósito — puro, exercitável diretamente com
    /// instâncias sintéticas de `URLError`, sem precisar disparar uma
    /// request de verdade.
    ///
    /// - Returns: `true` para códigos que indicam perda de conectividade de
    ///   transporte (`notConnectedToInternet`, `networkConnectionLost`,
    ///   `cannotConnectToHost`, `cannotFindHost`, `dataNotAllowed`) — nenhum
    ///   deles se recupera tentando de novo no mesmo caminho de rede.
    ///   `false` para os demais (ex.: `timedOut`), que o motor já trata como
    ///   recuperáveis (junto com HTTP 429/5xx, tratados à parte por
    ///   status code em `runPhaseTimeBased`).
    nonisolated static func isFatalTransportError(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    /// Decide se uma fase deve abortar por falha fatal de transporte
    /// persistente (issue #66).
    ///
    /// `nonisolated static` de propósito — mesmo padrão de `shouldStopPhase`:
    /// puro, sem tocar o estado do ator, exercitável com valores sintéticos.
    ///
    /// - Parameters:
    ///   - consecutiveFatalErrors: contagem corrente de falhas fatais
    ///     consecutivas (`FatalErrorTracker.currentCount()`), zerada por
    ///     qualquer sucesso concorrente de qualquer stream da fase.
    ///   - bytesTransferred: bytes acumulados na fase até agora (mesmo
    ///     `total` já lido de `ByteCounter` no loop de amostragem).
    ///   - threshold: piso de falhas fatais consecutivas exigido antes de
    ///     sequer considerar abortar — um valor isolado nunca aborta.
    /// - Returns: `true` somente quando **ambas** as condições valem: já
    ///   houve `threshold` falhas fatais seguidas **e** a fase ainda não
    ///   entregou nenhum byte real (`bytesTransferred == 0`). Uma fase que
    ///   já está entregando throughput real nunca aborta por erro isolado,
    ///   mesmo que a sequência de falhas fatais atinja o piso — dado real já
    ///   medido vale mais que uma sondagem de erro (AGENTS.md §8).
    nonisolated static func shouldAbortPhase(
        consecutiveFatalErrors: Int,
        bytesTransferred: Int64,
        threshold: Int = 6
    ) -> Bool {
        consecutiveFatalErrors >= threshold && bytesTransferred == 0
    }

    /// Decide se a fase de ping deve abortar cedo por falha fatal de
    /// transporte persistente (issue #85) — mesma lógica de
    /// `shouldAbortPhase`, adaptada ao laço sequencial de `performPingTest`
    /// (que não tem `ByteCounter`, só a contagem de sondagens que já
    /// obtiveram uma resposta 200).
    ///
    /// `nonisolated static` de propósito — mesmo padrão de `shouldAbortPhase`
    /// e `hasConverged`: puro, sem tocar estado do ator, exercitável com
    /// valores sintéticos em teste.
    ///
    /// - Parameters:
    ///   - consecutiveFatalErrors: contagem corrente de falhas fatais
    ///     (`isFatalTransportError`) consecutivas — zerada por qualquer
    ///     sondagem bem-sucedida (ver `performPingTest`).
    ///   - successCount: quantas sondagens já tiveram sucesso (200) nesta
    ///     fase até agora.
    ///   - threshold: piso de falhas fatais consecutivas exigido antes de
    ///     considerar abortar. 3 é menor que o piso de 6 usado em
    ///     `shouldAbortPhase` — o ping é sequencial (uma sondagem por vez,
    ///     não `streams` concorrentes), então o mesmo sinal de conexão morta
    ///     leva menos sondagens para se acumular.
    /// - Returns: `true` somente quando **ambas** as condições valem: já
    ///   houve `threshold` falhas fatais seguidas **e** nenhuma sondagem
    ///   desta fase teve sucesso ainda. Uma perda isolada intercalada com
    ///   sucesso nunca aborta — sucesso zera o contador antes de chegar ao
    ///   piso (AGENTS.md §8: preserva throughput/latência real já medido).
    nonisolated static func shouldAbortPingTest(
        consecutiveFatalErrors: Int,
        successCount: Int,
        threshold: Int = 3
    ) -> Bool {
        consecutiveFatalErrors >= threshold && successCount == 0
    }

    /// Constrói o `MeasurementState` final de uma falha fatal (issue #66):
    /// preserva integralmente o estado já capturado nas fases anteriores
    /// (ping, jitter, packetLoss, downloadSpeed, provider, networkType…) e
    /// só marca `phase` como `.error` e anota o motivo tipado — nunca perde
    /// dado real já medido por causa de uma falha posterior (AGENTS.md §8).
    ///
    /// `nonisolated static` de propósito — puro, sem tocar o estado do ator,
    /// exercitável diretamente com um `MeasurementState` sintético.
    nonisolated static func errorState(
        preserving state: MeasurementState,
        reason: EngineFailureReason
    ) -> MeasurementState {
        var errored = state
        errored.phase = .error
        errored.failureReason = reason
        return errored
    }

    /// Agregação da latência sob carga (issue #52, reaproveitada para a
    /// paridade de upload na issue #128): reduz as sondagens coletadas por
    /// `performLoadedLatencyProbe` durante a fase de download OU upload a um
    /// único valor representativo. Função única e parametrizada só pela
    /// lista de amostras — não existe variante por fase porque a agregação
    /// (mediana, piso de amostras) não depende de qual fase gerou as
    /// amostras, só do que as amostras dizem.
    ///
    /// `nonisolated static` de propósito — mesmo padrão de `hasConverged`:
    /// não toca `Date()` ao vivo nem estado do ator, então é inteiramente
    /// exercitável com arrays sintéticos em teste.
    ///
    /// Usa a mediana, não a média: sob carga real é comum que uma sondagem
    /// isolada colida com uma rajada de um dos streams de download e saia
    /// bem mais alta que as demais — a mediana absorve esse outlier sem
    /// exigir lógica extra de filtragem.
    ///
    /// - Parameters:
    ///   - samples: latências em ms coletadas durante a fase, em qualquer
    ///     ordem (sondagens já vêm filtradas de falha por
    ///     `performLoadedLatencyProbe`, que só produz valores positivos).
    ///   - minSamples: piso mínimo de amostras válidas para produzir um
    ///     valor — evita reportar "latência sob carga" a partir de uma
    ///     única sondagem que pode não ser representativa.
    /// - Returns: a mediana das amostras válidas (finitas e positivas), ou
    ///   `nil` quando não há amostras suficientes — nunca inventa um valor.
    nonisolated static func aggregateLoadedLatency(
        samples: [Double],
        minSamples: Int = 3
    ) -> Double? {
        let valid = samples.filter { $0.isFinite && $0 > 0 }
        guard valid.count >= minSamples else { return nil }

        let sorted = valid.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }

    /// Resume uma janela de sondagens sem promover uma única resposta a
    /// evidência. O p95 usa nearest-rank, estável para conjuntos pequenos.
    nonisolated static func latencyStatistics(
        samples: [Double],
        timeoutCount: Int,
        warmupDuration: TimeInterval,
        minimumSamples: Int = 5
    ) -> EngineLatencyStatistics? {
        let valid = samples.filter { $0.isFinite && $0 > 0 }.sorted()
        guard valid.count >= minimumSamples else { return nil }
        let middle = valid.count / 2
        let median = valid.count.isMultiple(of: 2)
            ? (valid[middle - 1] + valid[middle]) / 2
            : valid[middle]
        let p95Index = min(valid.count - 1, max(0, Int(ceil(Double(valid.count) * 0.95)) - 1))
        return EngineLatencyStatistics(
            medianMs: median,
            p95Ms: valid[p95Index],
            maximumMs: valid.last!,
            sampleCount: valid.count,
            timeoutCount: max(0, timeoutCount),
            warmupDurationMs: Int((max(0, warmupDuration) * 1_000).rounded())
        )
    }

    nonisolated static func loadIntegrity(
        baseline: EngineLatencyStatistics?,
        download: EngineLoadedPhaseEvidence?,
        upload: EngineLoadedPhaseEvidence?,
        baselineRemediationFailed: Bool
    ) -> EngineLoadResponsivenessIntegrity {
        if baseline == nil || baselineRemediationFailed { return .baselineInconclusive }
        guard let download, download.saturation == .sustained, download.latency != nil else {
            return .downloadInconclusive
        }
        guard let upload, upload.saturation == .sustained, upload.latency != nil else {
            return .uploadInconclusive
        }
        return .valid
    }

    /// A saturação é deliberadamente calculada só com carga concluída após o
    /// warm-up. Bytes/amostras da subida inicial jamais compensam uma janela
    /// útil sem tráfego.
    nonisolated static func loadSaturation(
        usefulDuration: TimeInterval,
        usefulBytes: Int64,
        usefulSampleCount: Int,
        usefulSampleSpan: TimeInterval? = nil,
        minimumUsefulDuration: TimeInterval = 10
    ) -> EngineLoadSaturation {
        guard usefulDuration >= minimumUsefulDuration,
              usefulBytes > 0,
              usefulSampleCount >= 5 else {
            return .insufficient
        }

        // Amostras pós-warm-up concentradas numa rajada curta não comprovam
        // carga sustentada. No caminho real, elas precisam atravessar 60% da
        // janela útil observada (ao menos 6s na janela mínima de 10s).
        // O parâmetro opcional mantém compatibilidade com chamadores puros
        // antigos; `runPhaseTimeBased` sempre informa as datas reais.
        if let usefulSampleSpan {
            let minimumDistributedSpan = max(
                usefulDuration * 0.6,
                minimumUsefulDuration * 0.6
            )
            guard usefulSampleSpan >= minimumDistributedSpan else {
                return .insufficient
            }
        }
        return .sustained
    }

    nonisolated private static func sampleSpan(_ dates: [Date]) -> TimeInterval? {
        guard let first = dates.min(), let last = dates.max() else { return nil }
        return max(0, last.timeIntervalSince(first))
    }

    /// Uma latência sob carga materialmente menor que o repouso normalmente
    /// indica baseline contaminado (cache, rádio acordando, fila anterior),
    /// não uma melhora que o Linka deva vender como fato.
    nonisolated static func isMateriallyInverted(
        baseline: EngineLatencyStatistics?,
        download: EngineLoadedPhaseEvidence?,
        upload: EngineLoadedPhaseEvidence?
    ) -> Bool {
        guard let baseline else { return false }
        let loaded = [download?.latency?.medianMs, upload?.latency?.medianMs].compactMap { $0 }
        return loaded.contains { $0 < baseline.medianMs * 0.8 }
    }

    private static func remediatedBaselineIfNeeded(
        initial: BaselineMeasurement,
        download: EngineLoadedPhaseEvidence?,
        upload: EngineLoadedPhaseEvidence?,
        environment: SpeedTestEnvironment,
        transport: any SpeedTestTransport,
        drainDelay: TimeInterval
    ) async throws -> BaselineMeasurement {
        guard isMateriallyInverted(baseline: initial.statistics, download: download, upload: upload) else {
            return initial
        }
        // Dá à última transferência cancelada uma curta janela para drenar;
        // sem isso a "remedição ociosa" ainda poderia testemunhar a própria
        // cauda da carga que está tentando validar.
        try await Task.sleep(nanoseconds: UInt64(drainDelay * 1_000_000_000))
        try Task.checkCancellation()
        switch try await performDetailedPingTest(environment: environment, transport: transport) {
        case .measured(_, _, _, let retried, _):
            return BaselineMeasurement(
                statistics: retried.statistics,
                remediationFailed: isMateriallyInverted(baseline: retried.statistics, download: download, upload: upload)
            )
        case .fatalFailure:
            return BaselineMeasurement(statistics: initial.statistics, remediationFailed: true)
        }
    }

    /// Medida objetiva de variação de vazão (issue #52): coeficiente de
    /// variação (desvio padrão relativo à média) das amostras de mbps já
    /// coletadas na janela estável da fase (`stable`, a mesma usada para
    /// `stableAvg` — descarta os primeiros 35% para cortar o warmup
    /// TCP/TLS). Não introduz nenhuma amostragem nova: reaproveita
    /// integralmente `mbpsSamples` já coletado no ritmo de `sampleInterval`.
    ///
    /// `nonisolated static` pelo mesmo motivo de `hasConverged`: puro,
    /// sem tocar estado do ator, testável com arrays sintéticos.
    ///
    /// - Parameters:
    ///   - stableSamples: amostras de mbps da janela estável da fase.
    ///   - window: piso mínimo de amostras válidas para produzir um valor —
    ///     mesmo piso de robustez de `hasConverged` (5 amostras).
    /// - Returns: desvio padrão / média das amostras válidas (>0), como
    ///   fração — quanto maior, mais instável a vazão dentro da janela
    ///   estável. `nil` quando não há amostras suficientes ou a média é
    ///   zero — nunca inventa um valor com dado insuficiente.
    nonisolated static func throughputVariation(
        stableSamples: [Double],
        window: Int = 5
    ) -> Double? {
        let valid = stableSamples.filter { $0 > 0 }
        guard valid.count >= window else { return nil }

        let mean = valid.reduce(0, +) / Double(valid.count)
        guard mean > 0 else { return nil }

        let variance = valid.map { pow($0 - mean, 2) }.reduce(0, +) / Double(valid.count)
        let stdDev = variance.squareRoot()
        return stdDev / mean
    }

    private func generateRandomPayload(size: Int) -> Data {
        var data = Data(count: size)
        data.withUnsafeMutableBytes { buffer in
            arc4random_buf(buffer.baseAddress, size)
        }
        return data
    }

    public static func performPingTest() async -> PingOutcome {
        let outcome: DetailedPingOutcome
        do {
            outcome = try await performDetailedPingTest(
                environment: .cloudflare,
                transport: URLSessionSpeedTestTransport()
            )
        } catch {
            return .fatalFailure(.connectionLost(phase: .ping))
        }
        switch outcome {
        case .measured(let latency, let jitter, let loss, _, _):
            return .measured(latency: latency, jitter: jitter, packetLossPercent: loss)
        case .fatalFailure(let reason):
            return .fatalFailure(reason)
        }
    }

    private static func performDetailedPingTest(
        environment: SpeedTestEnvironment,
        transport: any SpeedTestTransport
    ) async throws -> DetailedPingOutcome {
        var latencies: [Double] = []
        var failures = 0
        var timeouts = 0
        var consecutiveFatalErrors = 0
        var longestFailureStreak = 0
        var failureStreak = 0
        let initialWindow = 100
        let expandedWindow = 300
        var targetCount = initialWindow
        var probeIndex = 0

        while probeIndex < targetCount {
            try Task.checkCancellation()
            let start = Date()
            do {
                let response = try await transport.execute(.probe(environment.latencyProbeEndpoint))
                if response.statusCode == 200 {
                    let latency = Date().timeIntervalSince(start) * 1000.0
                    latencies.append(latency)
                    failureStreak = 0
                    // Sondagem bem-sucedida prova que o transporte não está
                    // de fato perdido — zera a sequência de falhas fatais
                    // (issue #85, mesmo padrão de `FatalErrorTracker.recordSuccess`
                    // usado em `runPhaseTimeBased`).
                    consecutiveFatalErrors = 0
                } else {
                    failures += 1
                    failureStreak += 1
                    longestFailureStreak = max(longestFailureStreak, failureStreak)
                }
            } catch let urlError as URLError where SpeedTestCore.isFatalTransportError(urlError) {
                // Falha fatal de transporte (issue #85, extensão do #66 para
                // a fase de ping) — distinta de timeout/erro isolado.
                failures += 1
                if urlError.code == .timedOut { timeouts += 1 }
                failureStreak += 1
                longestFailureStreak = max(longestFailureStreak, failureStreak)
                consecutiveFatalErrors += 1
                if Self.shouldAbortPingTest(
                    consecutiveFatalErrors: consecutiveFatalErrors,
                    successCount: latencies.count
                ) {
                    // Aborta cedo: numa conexão morta, sem isto o laço
                    // gastaria os ~11s completos das 10 sondagens antes de a
                    // fase de download sequer ter chance de detectar a perda
                    // de transporte.
                    return .fatalFailure(.connectionLost(phase: .ping))
                }
            } catch let urlError as URLError {
                failures += 1
                if urlError.code == .timedOut { timeouts += 1 }
                failureStreak += 1
                longestFailureStreak = max(longestFailureStreak, failureStreak)
            } catch {
                // Erro transiente (ex.: timeout isolado) — segue tentando as
                // sondagens restantes, igual ao comportamento anterior.
                failures += 1
                failureStreak += 1
                longestFailureStreak = max(longestFailureStreak, failureStreak)
            }
            probeIndex += 1
            if probeIndex == initialWindow, failures >= 1, failures <= 2 {
                targetCount = expandedWindow
            }
            // A janela é deliberadamente sequencial, mas um intervalo curto
            // evita inflar o teste formal por dezenas de segundos.
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        let evidence = EnginePacketProbeEvidence(
            environmentIdentifier: environment.latencyProbeEndpoint.host ?? "latency-probe",
            attemptCount: probeIndex,
            successCount: latencies.count,
            failureCount: failures,
            timeoutCount: timeouts,
            longestFailureStreak: longestFailureStreak,
            expandedAfterInitialWindow: targetCount == expandedWindow,
            completed: true
        )
        let lossPercent = evidence.packetLossPercent ?? 100

        guard !latencies.isEmpty else {
            return .measured(
                latency: 0.0,
                jitter: 0.0,
                packetLossPercent: lossPercent,
                baseline: BaselineMeasurement(statistics: nil, remediationFailed: false),
                probeEvidence: evidence
            ) // 100% loss
        }

        let baselineSamples = Array(latencies.dropFirst(min(2, latencies.count)))
        let baseline = BaselineMeasurement(
            statistics: latencyStatistics(samples: baselineSamples, timeoutCount: failures, warmupDuration: 0.1),
            remediationFailed: false
        )
        let representativeLatency = baseline.statistics?.medianMs ?? latencies.reduce(0, +) / Double(latencies.count)

        // Calculate Jitter (average of differences between consecutive pings)
        var jitterSum = 0.0
        if latencies.count > 1 {
            for i in 1..<latencies.count {
                jitterSum += abs(latencies[i] - latencies[i-1])
            }
            let avgJitter = jitterSum / Double(latencies.count - 1)
            return .measured(latency: representativeLatency, jitter: avgJitter, packetLossPercent: lossPercent, baseline: baseline, probeEvidence: evidence)
        }

        return .measured(latency: representativeLatency, jitter: 0.0, packetLossPercent: lossPercent, baseline: baseline, probeEvidence: evidence)
    }

    /// Resolução DNS cronometrada do host usado no teste — Expert Mode. Uma
    /// única sondagem (não uma janela como o ping). Roda em `Task.detached`
    /// porque `getaddrinfo` é uma chamada bloqueante do sistema (POSIX); o
    /// custo de uma thread do pool por teste é aceitável para uma sondagem
    /// única. Preferimos isso a `CFHost`, cujo callback assíncrono depende
    /// de agendar num `CFRunLoop` ativo — garantia frágil fora da main
    /// thread e em ambiente de teste headless.
    ///
    /// Cache de DNS do sistema pode deixar medições repetidas
    /// artificialmente otimistas em execuções seguidas contra o mesmo host;
    /// não há API pública confiável para contornar isso.
    ///
    /// Retorna `nil` em falha ou timeout — nunca `0` (ausência não é zero,
    /// AGENTS.md §8/§9). Falha aqui não aborta o teste inteiro: é chamado
    /// em paralelo ao ping, fora do caminho crítico de `performPingTest`.
    nonisolated public static func resolveDNS(
        host: String = "speed.cloudflare.com",
        timeoutMs: Double = 2000
    ) async -> Double? {
        await withTaskGroup(of: Double?.self) { group in
            group.addTask {
                let start = Date()
                var hints = addrinfo(
                    ai_flags: 0,
                    ai_family: AF_UNSPEC,
                    ai_socktype: SOCK_STREAM,
                    ai_protocol: 0,
                    ai_addrlen: 0,
                    ai_canonname: nil,
                    ai_addr: nil,
                    ai_next: nil
                )
                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(host, nil, &hints, &result)
                defer { if let result { freeaddrinfo(result) } }
                guard status == 0, result != nil else { return nil }
                let elapsed = Date().timeIntervalSince(start) * 1000.0
                guard elapsed.isFinite, elapsed >= 0 else { return nil }
                return elapsed
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutMs * 1_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Uma única sondagem de latência sob carga (issue #52): HEAD leve
    /// (0 bytes) contra o mesmo endpoint Cloudflare usado pela fase de
    /// download, disparada em paralelo à carga real dos streams de
    /// transferência — é essa concorrência com carga que a diferencia da
    /// latência ociosa de `performPingTest`, que roda isolada antes de
    /// qualquer transferência.
    ///
    /// `nonisolated static` de propósito, igual a `resolveProviderName`:
    /// não toca estado do ator, então pode ser chamada de dentro de uma
    /// `Task.detached` sem nenhum hop de volta para `SpeedTestCore`.
    ///
    /// - Returns: a latência em milissegundos quando a sondagem responde
    ///   200, ou `nil` em qualquer falha/timeout/status diferente — nunca
    ///   lança, para nunca derrubar a task de amostragem que a chama em
    ///   loop.
    nonisolated static func performLoadedLatencyProbe(
        environment: SpeedTestEnvironment = .cloudflare,
        transport: any SpeedTestTransport = URLSessionSpeedTestTransport()
    ) async -> Double? {
        let start = Date()
        do {
            let response = try await transport.execute(.probe(environment.latencyProbeEndpoint))
            guard response.statusCode == 200 else {
                return nil
            }
            return Date().timeIntervalSince(start) * 1000.0
        } catch {
            return nil
        }
    }

    /// Resolve o nome comercial do provedor com um timeout dedicado, isolado do
    /// orçamento de tempo de qualquer fase de medição. `nonisolated` + `static`
    /// de propósito: não precisa (nem deve) tocar o estado do ator, e assim a
    /// corrida abaixo não faz nenhum hop de volta para `SpeedTestCore`.
    ///
    /// Implementado como corrida entre a consulta real e um timer de timeout —
    /// o primeiro que terminar decide o resultado. Sucesso rápido não espera o
    /// timeout; timeout ou erro nunca produzem "Desconhecido", só `nil`.
    nonisolated static func resolveProviderName(
        lookup: ProviderOrgLookup,
        timeout: TimeInterval
    ) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                do {
                    guard let org = try await lookup.fetchOrg() else { return nil }
                    return ProviderNormalizer.shared.displayName(for: org)
                } catch {
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
