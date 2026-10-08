// Justificativa de Arquitetura (validarModularidade):
// Este arquivo gerencia o ciclo de vida e a coordenação entre o motor (LinkaEngine) e a UI de medição.
// Fica coeso manter as conversões de publish em um só lugar para garantir transições atômicas de UI.
import Foundation
import Combine
import Network
import SwiftUI
import WidgetKit
import CryptoKit
import LinkaEngine
import MeasurementHistory
import NetworkCore
import NetworkInsights
import LinkaEntitlements
import LinkaModules
import LinkaWidgetShared


public enum SpeedTestUIPhase {
    case idle
    case connecting
    case downloading
    case uploading
    case done
    /// A rota deixou de ser a mesma durante a medição. Não há resultado
    /// parcial para mostrar ou persistir; o próximo teste depende de um novo
    /// gesto explícito da pessoa.
    case connectionChanged
    /// Falha fatal do motor (issue #66) — motor parou e cancelou sozinho.
    /// Copy e ação de "Tentar novamente" vivem só na UI (`MainView`); aqui é
    /// só o estado.
    case error
}

@MainActor
public class SpeedTestViewModel: ObservableObject {
    @Published public var isTesting: Bool = false
    @Published public var progress: Double = 0.0
    @Published public var downloadSpeed: Double = 0.0
    @Published public var uploadSpeed: Double = 0.0
    @Published public var ping: Int = 0
    @Published public var jitter: Double = 0.0
    @Published public var provider: String = ""
    @Published public var networkType: String = ""
    @Published public var testDuration: String = ""
    @Published public var packetLossPercent: Double? = nil
    @Published public private(set) var hasMeasuredUpload = false
    @Published public private(set) var hasMeasuredPing = false
    @Published public var uiPhase: SpeedTestUIPhase = .idle
    /// Fato tipado da falha fatal (issue #66) — não-`nil` só quando
    /// `uiPhase == .error`. Mapeamento pra mensagem amigável vive só na UI.
    @Published public var failureReason: EngineFailureReason? = nil

    /// Tipo real de interface de rede usado no teste (issue #51) — Wi-Fi,
    /// rede móvel, Ethernet ou outra. Amostrado de forma independente do
    /// motor (`NWPathMonitor` próprio, fora de `SpeedTestCore`) no início e
    /// no fim do teste; se a interface mudar no meio do caminho, fica
    /// `nil` em vez de afirmar um tipo que não valeu para o teste inteiro.
    /// Fonte única para `MainView` e para o que é salvo no histórico —
    /// evita a divergência que existia entre os dois lugares que derivavam
    /// isso de `networkType` (string legada de exibição, não removida).
    @Published public var connectionKind: NetworkConnectionKind? = nil

    /// Banda Wi-Fi confirmada pelo sistema em GHz (issue #51) — só
    /// preenchida quando `connectionKind == .wifi` e a plataforma
    /// realmente informa (CoreWLAN no Mac). `nil` é estado normal no
    /// iPhone e sempre que a rede mudou durante o teste.
    @Published public var wifiBandGHz: Double? = nil

    /// Contexto Wi-Fi da medição, amostrado junto com a interface no começo e
    /// no fim. Não substitui `provider`, que é o provedor do teste.
    @Published public var wifiContext: WiFiNetworkContext? = nil

    /// Monitor de caminho de rede ao vivo para refletir o status real de conexão na tela inicial (Home/Idle).
    private var livePathMonitor: NWPathMonitor?
    private let livePathQueue = DispatchQueue(label: "com.linka.speedtest.viewmodel.live-path")

    /// Conexão de rede ativa no aparelho em tempo real (independente de testes anteriores).
    @Published public var liveConnectionKind: NetworkConnectionKind? = nil

    /// Contexto Wi-Fi ativo no aparelho em tempo real.
    @Published public var liveWiFiContext: WiFiNetworkContext? = nil

    /// Rótulo descritivo da conexão ativa ao vivo (ex: "MinhaCasa · 5 GHz", "5G", "Wi-Fi", "Rede móvel").
    @Published public var liveNetworkLabel: String = ""

    /// Fatos avançados importados explicitamente pelo app Atalhos. São
    /// secundários ao resultado e só existem quando a janela de associação
    /// temporal da issue #134 é satisfeita.
    @Published public private(set) var advancedWiFiDiagnostics: AdvancedWiFiDiagnostics?

    @Published public private(set) var liveDnsLatencyMs: Double?
    @Published public private(set) var livePacketLossPercent: Double?
    @Published public private(set) var liveWifiRSSI: Double?

    /// Relatório de adequação de casos de uso calculado em tempo real.
    @Published public private(set) var liveUsageReport: LiveUsageSuitabilityReport?

    let liveTelemetryCollector = LiveTelemetryCollector()
    private let liveUsageEvaluator = LiveUsageSuitabilityEvaluator()
    var currentThroughputBaseline: ThroughputBaseline?
    /// SSID ao qual a janela e a baseline efêmera pertencem. `nil` não é
    /// uma identidade substituível por provedor, interface ou rede celular.
    private(set) var liveUsageWiFiSSID: String?

    /// Latência sob carga (issue #52). Não é `@Published` de propósito: não
    /// deve disparar re-render nenhum, para não competir com o resultado
    /// (AGENTS.md §6). Leitura pública (issue #53) para que `MainView` possa
    /// ler o valor já calculado no momento em que monta `DetailsDisclosure`
    /// (teste já concluído, `uiPhase == .done`) — escrita continua só interna
    /// a esta classe.
    public private(set) var loadedLatencyMs: Double? = nil
    /// Evidência formal de estabilidade; não é publicada durante a medição.
    public private(set) var packetProbeEvidence: PacketProbeEvidence? = nil
    public private(set) var regionalGameReference: RegionalGameReference? = nil

    /// Latência sob carga durante upload (issue #128, paridade com
    /// `loadedLatencyMs`) — mesmo motivo de não ser `@Published`.
    public private(set) var loadedLatencyUploadMs: Double? = nil

    /// Envelope v1 de evidência. Não é publicado durante o teste: só o
    /// resultado final pode expor uma integridade conclusiva ou parcial.
    public private(set) var loadResponsiveness: LoadResponsivenessEvidence? = nil

    /// Tempo de resolução DNS (ms) do host usado no teste — Expert Mode.
    /// Mesmo motivo de não ser `@Published` que `loadedLatencyMs`: não deve
    /// competir com o resultado por re-render.
    public private(set) var dnsResolutionMs: Double? = nil

    /// Duração bruta do teste em segundos (issue #50), do jeito que o motor
    /// entrega em `MeasurementState.duration` — mesmo padrão de
    /// `loadedLatencyMs`: não-`@Published` para não competir com o
    /// resultado por re-render. `testDuration` (string formatada) já existe
    /// só para exibição ao vivo; este valor bruto é o que alimenta
    /// `NetworkMeasurement.durationMs` no registro salvo, convertido para
    /// milissegundos só no momento da construção final.
    private var rawTestDuration: Double? = nil

    /// Histórico recente real disponível para superfícies secundárias como
    /// o Assist. O limite coincide com `NetworkAssistConfiguration` e evita
    /// carregar uma coleção maior do que o contrato aceita.
    @Published public private(set) var recentMeasurements: [NetworkMeasurement] = []

    // UI states
    @Published public var showPurchase: Bool = false

    private let engine = SpeedTestCore()
    private var testTask: Task<Void, Never>?

    /// Instância própria (não compartilhada com `MainView`/`SettingsSheet`,
    /// que recebem a delas via `@EnvironmentObject`) só para decidir se a
    /// sincronização CloudKit do histórico está liberada (capability
    /// `.history`, issue #71). `SpeedTestViewModel` não tem acesso direto
    /// ao `StoreKitEntitlementProvider` do ambiente SwiftUI — não é uma
    /// `View` — e mudar isso exigiria tocar `MainView.swift`, fora do
    /// escopo desta issue. O snapshot de entitlement é derivado da mesma
    /// fonte (StoreKit/`UserDefaults`) então converge para o mesmo estado;
    /// o custo é uma segunda instância de observador de transações em
    /// memória, não uma decisão de acesso divergente.
    private let historySyncEntitlements = StoreKitEntitlementProvider()

    /// Geração monotônica da task de teste atual (issue #47, rodada 3 —
    /// achado de Marcelo). `Task<Void, Never>` não é `Equatable`, então não
    /// dá pra comparar identidade de task diretamente; um contador simples
    /// resolve o mesmo problema. Incrementado sincronamente no início de
    /// `startTest()`, antes da nova `Task` ser criada — cada execução
    /// captura o valor da geração que lhe pertence (`myGeneration`) e só
    /// aplica seu próprio cleanup (`isTesting = false`, etc.) se a geração
    /// ainda for a corrente quando ela terminar. Cobre a corrida: T1 é
    /// cancelada por `skipOrCancel()`, que (sem snapshot pra restaurar)
    /// chama `startTest()` de novo sincronamente — isso já criou T2 e
    /// avançado a geração antes de T1 perceber o cancelamento no próprio
    /// loop. Sem esta guarda, o `catch` de T1 fazia `self.isTesting = false`
    /// incondicionalmente, sobrescrevendo o `true` que T2 acabou de setar;
    /// se o usuário navegasse Histórico→voltar nesse instante, `.onAppear`
    /// via `isTesting == false` e chamava `startTest()` de novo, criando T3
    /// e cancelando T2 sem pedido do usuário.
    private var testGeneration: Int = 0
    private var measurementStartedAt: Date?
    /// Snapshot da interface que autorizou o teste atual. O monitor ao vivo é
    /// a fonte para interromper imediatamente quando esse fato deixa de valer.
    private var measurementConnectionKind: NetworkConnectionKind?
    @Published public private(set) var latestFinishedMeasurement: NetworkMeasurement?

    /// Snapshot do último resultado `.done` alcançado nesta sessão do view
    /// model (issue #47) — capturado em `startTest()` no instante em que um
    /// teste chega a `.done`, antes que um `startTest()` seguinte zere os
    /// campos `@Published` no próprio início. É a fonte usada por
    /// `skipOrCancel()` pra restaurar a tela de resultado integralmente
    /// (todos os campos, não só a velocidade de download) sem round-trip ao
    /// histórico em disco.
    /// Acesso `internal` (não `private`) de propósito (issue #65): permite
    /// que `@testable import LinkaApp` semeie um snapshot em teste sem
    /// depender de uma medição de rede real completa — não é API pública do
    /// módulo, só visível dentro do target do app e de quem importa com
    /// `@testable`.
    struct ResultSnapshot {
        let downloadSpeed: Double
        let uploadSpeed: Double
        let ping: Int
        let hasMeasuredUpload: Bool
        let hasMeasuredPing: Bool
        let jitter: Double
        let provider: String
        let networkType: String
        let testDuration: String
        let packetLossPercent: Double?
        let connectionKind: NetworkConnectionKind?
        let wifiBandGHz: Double?
        let wifiContext: WiFiNetworkContext?
        let advancedWiFiDiagnostics: AdvancedWiFiDiagnostics?

        init(
            downloadSpeed: Double,
            uploadSpeed: Double,
            ping: Int,
            hasMeasuredUpload: Bool? = nil,
            hasMeasuredPing: Bool? = nil,
            jitter: Double,
            provider: String,
            networkType: String,
            testDuration: String,
            packetLossPercent: Double?,
            connectionKind: NetworkConnectionKind?,
            wifiBandGHz: Double?,
            wifiContext: WiFiNetworkContext? = nil,
            advancedWiFiDiagnostics: AdvancedWiFiDiagnostics? = nil
        ) {
            self.downloadSpeed = downloadSpeed
            self.uploadSpeed = uploadSpeed
            self.ping = ping
            self.hasMeasuredUpload = hasMeasuredUpload ?? (uploadSpeed > 0)
            self.hasMeasuredPing = hasMeasuredPing ?? (ping > 0)
            self.jitter = jitter
            self.provider = provider
            self.networkType = networkType
            self.testDuration = testDuration
            self.packetLossPercent = packetLossPercent
            self.connectionKind = connectionKind
            self.wifiBandGHz = wifiBandGHz
            self.wifiContext = wifiContext
            self.advancedWiFiDiagnostics = advancedWiFiDiagnostics
        }
    }

    /// Mesmo racional de acesso `internal` de `ResultSnapshot` acima
    /// (issue #65) — testável via `@testable import` sem expor API pública.
    var lastValidResultSnapshot: ResultSnapshot?

    /// Mantido para consumidores que precisam saber se a sessão já concluiu
    /// uma medição. Cancelar não restaura mais esse resultado: a pessoa
    /// volta sempre para a Home.
    public var hasValidResult: Bool {
        lastValidResultSnapshot != nil
    }

    public init() {
        startLiveNetworkMonitoring()
        loadLastTest()
        // O polling ao vivo precisa começar aqui, não só em
        // `handleScenePhaseChange(.active)`: no macOS, `MacMainView` nunca
        // observa `scenePhase` (não tem `.onChange(of: scenePhase)`), então
        // esse gatilho nunca disparava e "Sua Rede Agora" ficava sempre em
        // "—". No iOS, `.onChange` também não dispara para o valor inicial
        // de `scenePhase` na primeira aparição da view — só em transições
        // subsequentes — então o cold start tinha o mesmo problema.
        startLivePolling()
    }

    deinit {
        livePathMonitor?.cancel()
        livePollingTask?.cancel()
    }

    public func loadLastTest() {
        Task { @MainActor in
            let repository = LinkaMeasurementHistory.makeRepository(entitlements: historySyncEntitlements)
            if let count = try? await repository.totalCount(), count > 0 {
                let query = MeasurementQuery(limit: 20, sortOrder: .newestFirst)
                let results = (try? await repository.measurements(matching: query)) ?? []
                self.recentMeasurements = results
                if let last = results.first {
                    // Hidrata snapshot em memória a partir da última medição
                    // persistida — Pular passa a restaurar o último resultado
                    // (mesmo de sessão anterior), não só quando o usuário mede
                    // dentro desta sessão. Sem isto, o usuário perde a
                    // referência do último teste entre relançamentos do app.
                    if self.lastValidResultSnapshot == nil && self.uiPhase == .idle {
                        self.loadHistoricalResult(last)
                    }
                }
            } else {
                self.recentMeasurements = []
            }
        }
    }

    /// Consulta somente as três medições completas mais antigas. A tela usa
    /// isso para decidir um convite de avaliação sem guardar um segundo
    /// contador e sem considerar resultados parciais ou não persistidos.
    func appStoreReviewHistory() async -> (completedCount: Int, firstCompletedAt: Date)? {
        let repository = LinkaMeasurementHistory.makeRepository(entitlements: historySyncEntitlements)
        let query = MeasurementQuery(
            outcomes: [.complete],
            limit: AppStoreReviewPolicy.minimumCompletedMeasurements,
            sortOrder: .oldestFirst
        )
        guard let measurements = try? await repository.measurements(matching: query),
              let first = measurements.first else {
            return nil
        }
        return (measurements.count, first.measuredAt)
    }

    public func loadHistoricalResult(_ measurement: NetworkMeasurement) {
        latestFinishedMeasurement = measurement
        if let kind = measurement.connectionKind {
            switch kind {
            case .cellular: self.networkType = LinkaCopy.value("network.cellular")
            case .wifi: self.networkType = LinkaCopy.value("network.wifi")
            case .ethernet: self.networkType = LinkaCopy.value("network.ethernet")
            case .other: self.networkType = LinkaCopy.value("network.other")
            }
        } else {
            self.networkType = ""
        }
        
        self.downloadSpeed = measurement.downloadMbps ?? 0.0
        self.uploadSpeed = measurement.uploadMbps ?? 0.0
        self.ping = Int((measurement.latencyMs ?? 0).rounded())
        self.hasMeasuredUpload = measurement.uploadMbps != nil
        self.hasMeasuredPing = measurement.latencyMs != nil
        self.jitter = measurement.jitterMs ?? 0.0
        self.provider = measurement.networkIdentifier ?? ""
        if let dur = measurement.durationMs {
            self.rawTestDuration = Double(dur) / 1000.0
            self.testDuration = Self.formattedDuration(self.rawTestDuration!)
        } else {
            self.rawTestDuration = nil
            self.testDuration = ""
        }
        self.packetLossPercent = measurement.packetLossPercent
        self.packetProbeEvidence = measurement.packetProbeEvidence
        self.regionalGameReference = measurement.regionalGameReference
        self.loadedLatencyMs = measurement.loadedLatencyMs
        self.loadedLatencyUploadMs = measurement.loadedLatencyUploadMs
        self.loadResponsiveness = measurement.loadResponsiveness
        self.dnsResolutionMs = measurement.dnsResolutionMs
        self.connectionKind = measurement.connectionKind
        self.wifiBandGHz = measurement.wifiBandGHz
        self.wifiContext = measurement.wifiContext
        self.advancedWiFiDiagnostics = measurement.advancedWiFiDiagnostics
        
        self.lastValidResultSnapshot = ResultSnapshot(
            downloadSpeed: self.downloadSpeed,
            uploadSpeed: self.uploadSpeed,
            ping: self.ping,
            hasMeasuredUpload: self.hasMeasuredUpload,
            hasMeasuredPing: self.hasMeasuredPing,
            jitter: self.jitter,
            provider: self.provider,
            networkType: self.networkType,
            testDuration: self.testDuration,
            packetLossPercent: self.packetLossPercent,
            connectionKind: self.connectionKind,
            wifiBandGHz: self.wifiBandGHz,
            wifiContext: self.wifiContext,
            advancedWiFiDiagnostics: self.advancedWiFiDiagnostics
        )
        
        self.progress = 1.0
        self.uiPhase = .idle
        self.isTesting = false
    }

    
    public func startTest(advancedWiFiDiagnostics: AdvancedWiFiDiagnostics? = nil) {
        guard !isTesting else { return }
        stopLivePolling()
        liveTelemetryCollector.suspend()
        isTesting = true
        progress = 0.0
        downloadSpeed = 0.0
        uploadSpeed = 0.0
        ping = 0
        jitter = 0.0
        provider = ""
        networkType = ""
        testDuration = ""
        loadedLatencyMs = nil
        packetProbeEvidence = nil
        regionalGameReference = nil
        loadedLatencyUploadMs = nil
        loadResponsiveness = nil
        dnsResolutionMs = nil
        rawTestDuration = nil
        failureReason = nil
        connectionKind = nil
        wifiBandGHz = nil
        wifiContext = nil
        self.advancedWiFiDiagnostics = nil
        measurementStartedAt = Date()
        measurementConnectionKind = liveConnectionKind
        uiPhase = .connecting

        testTask?.cancel()
        testGeneration += 1
        let myGeneration = testGeneration
        testTask = Task {
            // Amostra o tipo de interface no início do teste, em paralelo à
            // subida do motor (não soma latência) — independente do
            // `NWPathMonitor` interno de `SpeedTestCore` (issue #51).
            async let startingKindTask = Self.sampleConnectionKind()
            async let startingWiFiContextTask = Self.sampleWiFiContext()

            do {
                var lastUpdateTime = Date()

                for try await state in await engine.runTest() {
                    // Checa cancelamento a cada yield (issue #47, rodada 2):
                    // sem isto, uma `skipOrCancel()` que chegue entre dois
                    // yields do motor só é percebida no próximo `state`, em
                    // vez de interromper o consumo imediatamente — agora que
                    // `SpeedTestCore.runTest()` cancela o próprio Task
                    // interno via `continuation.onTermination`, este loop
                    // também precisa parar de consumir assim que percebe.
                    try Task.checkCancellation()

                    let now = Date()
                    // Throttle updates to ~30fps
                    if now.timeIntervalSince(lastUpdateTime) >= 0.033 || state.progress >= 1.0 || state.progress == 0.0 {
                        if state.phase == .result {
                            // Fase terminal (sempre o último valor yield do
                            // motor, sempre com progress = 1.0, então nunca
                            // é pulado pelo throttle acima — ver
                            // SpeedTestCore.swift linhas ~308-313). Resolve
                            // connectionKind/wifiBandGHz finais ANTES de
                            // publicar `uiPhase = .done` (issue #88): antes,
                            // essa amostragem só acontecia DEPOIS que o loop
                            // terminava, ou seja, depois de `.done` já ter
                            // sido publicado num frame anterior — abrindo uma
                            // janela de ~100-200ms em que a UI via `.done`
                            // com os campos ainda `nil`. Se a interface mudou
                            // no meio do teste (ex.: Wi-Fi → rede móvel), o
                            // teste não rodou inteiro numa única rede — não
                            // afirma nenhum tipo específico nesse caso (nil
                            // continua sendo o estado neutro).
                            let startingKind = await startingKindTask
                            let endingKind = await Self.sampleConnectionKind()
                            let startingWiFiContext = await startingWiFiContextTask
                            let endingWiFiContext = await Self.sampleWiFiContext()
                            guard startingKind == endingKind else {
                                self.cancelForConnectionChange()
                                return
                            }
                            self.processResultState(
                                state,
                                startingKind: startingKind,
                                endingKind: endingKind,
                                startingWiFiContext: startingWiFiContext,
                                endingWiFiContext: endingWiFiContext,
                                advancedWiFiDiagnostics: advancedWiFiDiagnostics,
                                generation: myGeneration
                            )
                        } else {
                            self.update(with: state)
                        }
                        lastUpdateTime = now
                    }
                }

                // Guarda por geração (issue #47, rodada 3): se outra
                // `startTest()` já avançou `testGeneration` — via
                // `skipOrCancel()` reiniciando o loop sem snapshot pra
                // restaurar —, esta execução (T1) não é mais a corrente e
                // não deve tocar nenhum `@Published` nem salvar no
                // histórico por baixo de T2.
                guard self.testGeneration == myGeneration else { return }

                // `!Task.isCancelled` além do `uiPhase == .done` (issue #47):
                // `skipOrCancel()` chama `testTask?.cancel()` antes de
                // qualquer outra coisa, então essa checagem cobre até a
                // corrida rara em que o resultado final chegou bem no
                // instante do cancelamento — um teste interrompido nunca
                // vira snapshot válido nem entra no histórico.
                if self.uiPhase == .done && !Task.isCancelled {
                    let m: NetworkMeasurement
                    if let existing = self.latestFinishedMeasurement {
                        m = existing
                    } else {
                        self.lastValidResultSnapshot = ResultSnapshot(
                            downloadSpeed: self.downloadSpeed,
                            uploadSpeed: self.uploadSpeed,
                            ping: self.ping,
                            hasMeasuredUpload: self.hasMeasuredUpload,
                            hasMeasuredPing: self.hasMeasuredPing,
                            jitter: self.jitter,
                            provider: self.provider,
                            networkType: self.networkType,
                            testDuration: self.testDuration,
                            packetLossPercent: self.packetLossPercent,
                            connectionKind: self.connectionKind,
                            wifiBandGHz: self.wifiBandGHz,
                            wifiContext: self.wifiContext,
                            advancedWiFiDiagnostics: self.advancedWiFiDiagnostics
                        )

                        m = NetworkMeasurement(
                            outcome: .complete,
                            downloadMbps: self.downloadSpeed,
                            uploadMbps: self.hasMeasuredUpload ? self.uploadSpeed : nil,
                            latencyMs: self.hasMeasuredPing ? Double(self.ping) : nil,
                            jitterMs: self.jitter,
                            packetLossPercent: self.packetLossPercent,
                            packetProbeEvidence: self.packetProbeEvidence,
                            regionalGameReference: self.regionalGameReference,
                            loadedLatencyMs: self.loadedLatencyMs,
                            loadedLatencyUploadMs: self.loadedLatencyUploadMs,
                            loadResponsiveness: self.loadResponsiveness,
                            dnsResolutionMs: self.dnsResolutionMs,
                            durationMs: self.rawTestDuration.map { Int(($0 * 1000).rounded()) },
                            connectionKind: self.connectionKind,
                            wifiBandGHz: self.wifiBandGHz,
                            wifiContext: self.wifiContext,
                            advancedWiFiDiagnostics: self.advancedWiFiDiagnostics,
                            networkIdentifier: self.provider
                        )
                        self.latestFinishedMeasurement = m
                    }
                    self.publishThroughputBaselineIfEligible(from: m)
                    await self.refreshLiveUsageSuitability()
                    let repo = LinkaMeasurementHistory.makeRepository(entitlements: historySyncEntitlements)
                    do {
                        try await repo.save(m)
                    } catch {
                        // Falha ao salvar no histórico não derruba o fluxo de medição.
                    }
                    self.loadLastTest()
                    
                    let summary = LinkaWidgetShared.LatestMeasurementSummary(
                        downloadMbps: self.downloadSpeed,
                        uploadMbps: self.uploadSpeed > 0 ? self.uploadSpeed : nil,
                        latencyMs: self.ping > 0 ? Double(self.ping) : nil,
                        measuredAt: m.measuredAt
                    )
                    LinkaWidgetShared.writeLatestSummary(summary)
                    WidgetCenter.shared.reloadTimelines(ofKind: LinkaWidgetShared.widgetKind)
                }
                
                self.isTesting = false
                self.liveTelemetryCollector.resume()
                self.startLivePolling()
            } catch {
                // Mesma guarda por geração do caminho de sucesso acima: uma
                // T1 cancelada que só percebe isso aqui (via
                // `Task.checkCancellation()` dentro do loop) não pode
                // sobrescrever `isTesting`/`uiPhase` de uma T2 que já está
                // rodando (issue #47, rodada 3 — achado de Marcelo).
                guard self.testGeneration == myGeneration else { return }
                self.isTesting = false
                self.liveTelemetryCollector.resume()
                self.startLivePolling()
            }
        }
    }
    
    /// Interrompe uma medição iniciada pela pessoa e retorna à Home. Não é
    /// resultado parcial e não pode restaurar uma medição anterior: isso
    /// faria o cancelamento parecer um teste concluído, inclusive com zeros
    /// ou números que não pertencem à execução recém-cancelada.
    public func skipOrCancel() {
        testTask?.cancel()
        testTask = nil

        failureReason = nil
        isTesting = false
        progress = 0.0
        uiPhase = .idle
        liveTelemetryCollector.resume()
        startLivePolling()
    }

    /// Retorna à tela inicial (Home/Idle) a partir do resultado ou de qualquer outro estado.
    public func resetToIdle() {
        testTask?.cancel()
        testTask = nil
        isTesting = false
        failureReason = nil
        progress = 0.0
        uiPhase = .idle
        liveTelemetryCollector.resume()
        startLivePolling()
    }

    /// O `NWPathMonitor` observou que a rota que iniciou a medição mudou ou
    /// deixou de estar disponível. Não restaura resultado anterior: este é um
    /// estado de segurança da jornada, que pede uma nova intenção explícita.
    func cancelForConnectionChange() {
        guard isTesting else { return }
        testGeneration += 1
        testTask?.cancel()
        testTask = nil
        isTesting = false
        failureReason = nil
        measurementStartedAt = nil
        measurementConnectionKind = nil
        progress = 0
        downloadSpeed = 0
        uploadSpeed = 0
        ping = 0
        jitter = 0
        provider = ""
        networkType = ""
        testDuration = ""
        resetLiveUsageState()
        liveTelemetryCollector.resume()
        startLivePolling()
        packetLossPercent = nil
        hasMeasuredUpload = false
        hasMeasuredPing = false
        loadedLatencyMs = nil
        packetProbeEvidence = nil
        regionalGameReference = nil
        loadedLatencyUploadMs = nil
        loadResponsiveness = nil
        dnsResolutionMs = nil
        rawTestDuration = nil
        connectionKind = nil
        wifiBandGHz = nil
        wifiContext = nil
        advancedWiFiDiagnostics = nil
        uiPhase = .connectionChanged
    }

    /// Reage à mudança de `ScenePhase` da cena (issue #65) — único ponto de
    /// decisão de ciclo de vida do teste; `MainView` só repassa o valor via
    /// `.onChange(of: scenePhase)`, sem lógica própria aqui.
    ///
    /// Reage só à transição para `.background`, nunca a `.inactive`:
    /// `.inactive` também dispara em blips transitórios que não devem
    /// cancelar nada (sheet de compartilhamento, prompt de permissão,
    /// interstitial de anúncio, Control Center) — reagir a `.inactive`
    /// cancelaria testes por engano nesses casos.
    ///
    /// Decisão de produto (issue #65): PAUSAR não é opção real aqui.
    /// `SpeedTestCore.runTest()` usa `URLSessionConfiguration.ephemeral`,
    /// sem `URLSessionConfiguration.background`, `BGTaskScheduler` ou
    /// `UIBackgroundModes` (Info.plist protegido, ver AGENTS.md) —
    /// iOS/iPadOS suspendem essas conexões assim que o processo entra em
    /// background, então não há como retomar de forma confiável um
    /// download/upload em andamento. A única reação correta é cancelar de
    /// forma limpa, nunca prometer conclusão silenciosa em segundo plano.
    ///
    /// No Mac, `ScenePhase.background` pode nunca disparar em uso normal de
    /// janela (perder foco, ocultar com Cmd+H, minimizar não necessariamente
    /// suspendem o processo como no iOS) — comportamento observado
    /// documentado no PR desta issue, não afirmado como testado ao vivo.
    public func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            stopLivePolling()
            resetLiveUsageState()

            // Só age em cima de uma medição em andamento — `.done`/`.error`
            // já são estados terminais e não têm nada pra cancelar; agir
            // ali arriscaria sobrescrever um resultado que já passou por
            // `phase == .result` no motor (requisito de aceite #2).
            guard uiPhase == .connecting || uiPhase == .downloading || uiPhase == .uploading else {
                return
            }

            // Mecanismo de cancelamento já existe e já funciona
            // (`SpeedTestCore.runTest()` propaga cancelamento via
            // `continuation.onTermination`, libera `session
            // .invalidateAndCancel()` e cancela `workersTask`/
            // `latencySamplingTask`) — este handler só aciona o gatilho que
            // faltava, não reimplementa nada do motor (AGENTS.md §8).
            testTask?.cancel()
            testTask = nil
            failureReason = nil
            isTesting = false

            // Não incrementa `testGeneration` nem chama `startTest()` aqui
            // (issue #47, rodada 3 — reintroduziria a mesma classe de
            // corrida que aquela issue já resolveu). Disparar rede
            // enquanto o app está indo para background não tem sentido
            // (seria cancelado de novo no instante seguinte) e contradiz
            // "nenhuma promessa de conclusão em segundo plano". O reinício,
            // quando fizer sentido, só acontece na volta a `.active`.
            if let snapshot = lastValidResultSnapshot {
                restoreLastValidSnapshot(snapshot)
            } else {
                progress = 0.0
                uiPhase = .idle
            }

        case .active:
            // A rota pode ter mudado enquanto o app não estava visível. A
            // janela anterior não é evidência para a nova sessão ativa.
            resetLiveUsageState()
            startLivePolling()

            refreshLiveNetwork()

        case .inactive:
            break

        @unknown default:
            break
        }
    }

    /// Restaura os campos de exibição a partir do último resultado válido
    /// desta sessão (issue #47, extraído em #65 para ser compartilhado
    /// entre `skipOrCancel()` e `handleScenePhaseChange()` sem duplicar os
    /// mesmos ~10 campos nos dois lugares). Não mexe em `isTesting`,
    /// `failureReason` ou `testTask` — quem chama é responsável por esses
    /// campos antes/depois, já que os dois fluxos que usam isto (cancelamento
    /// explícito do usuário vs. backgrounding) tratam esses três campos de
    /// forma ligeiramente diferente.
    private func restoreLastValidSnapshot(_ snapshot: ResultSnapshot) {
        downloadSpeed = snapshot.downloadSpeed
        uploadSpeed = snapshot.uploadSpeed
        ping = snapshot.ping
        hasMeasuredUpload = snapshot.hasMeasuredUpload
        hasMeasuredPing = snapshot.hasMeasuredPing
        jitter = snapshot.jitter
        provider = snapshot.provider
        networkType = snapshot.networkType
        testDuration = snapshot.testDuration
        packetLossPercent = snapshot.packetLossPercent
        connectionKind = snapshot.connectionKind
        wifiBandGHz = snapshot.wifiBandGHz
        wifiContext = snapshot.wifiContext
        advancedWiFiDiagnostics = snapshot.advancedWiFiDiagnostics
        progress = 1.0
        uiPhase = .done
    }

    /// Processa o state terminal do motor (`phase == .result`, issue #88):
    /// resolve `connectionKind`/`wifiBandGHz` finais (só quando `generation`
    /// ainda é a geração corrente — mesma guarda de sempre contra um
    /// `skipOrCancel()`/novo `startTest()` que avance `testGeneration`
    /// durante os ~100ms de amostragem final) e SÓ DEPOIS publica o state
    /// via `update(with:)` — é essa chamada que marca `uiPhase = .done`.
    /// Extraído num método próprio, com acesso `internal` (mesmo padrão de
    /// `ResultSnapshot`/`lastValidResultSnapshot` acima), pra ser testável
    /// via `@testable import` sem depender de uma medição de rede real
    /// completa (`engine` não é injetável).
    ///
    /// `NetworkConnectionKind.resolve(start:end:)` continua a única fonte
    /// que decide `connectionKind` — nenhuma lógica duplicada aqui.
    func processResultState(
        _ state: MeasurementState,
        startingKind: NetworkConnectionKind,
        endingKind: NetworkConnectionKind,
        startingWiFiContext: WiFiNetworkContext? = nil,
        endingWiFiContext: WiFiNetworkContext? = nil,
        advancedWiFiDiagnostics: AdvancedWiFiDiagnostics? = nil,
        generation: Int
    ) {
        if self.testGeneration == generation {
            self.connectionKind = NetworkConnectionKind.resolve(start: startingKind, end: endingKind)
            self.wifiBandGHz = self.connectionKind == .wifi
                ? ApplePlatformSignalProvider.currentWifiBandGHz()
                : nil
            self.wifiContext = WiFiNetworkContext.resolve(
                start: startingWiFiContext,
                end: endingWiFiContext,
                connectionKind: self.connectionKind
            )
            let imported = advancedWiFiDiagnostics ?? AdvancedWiFiDiagnosticsInbox.takePending()
            let startedAt = self.measurementStartedAt ?? Date()
            let endedAt = Date()
            self.advancedWiFiDiagnostics = imported.flatMap { diagnostics in
                guard self.connectionKind == .wifi,
                      diagnostics.isEligible(
                        forMeasurementStartedAt: startedAt,
                        endedAt: endedAt,
                        nativeSSID: self.wifiContext?.ssid
                      ) else { return nil }
                if advancedWiFiDiagnostics != nil {
                    guard let capturedAP = diagnostics.accessPointIdentifier,
                          let measuredAP = self.wifiContext?.accessPointIdentifier,
                          capturedAP == measuredAP else { return nil }
                }
                return diagnostics
            }
        }
        self.update(with: state)
        if self.testGeneration == generation && self.uiPhase == .done {
            self.lastValidResultSnapshot = ResultSnapshot(
                downloadSpeed: self.downloadSpeed,
                uploadSpeed: self.uploadSpeed,
                ping: self.ping,
                hasMeasuredUpload: self.hasMeasuredUpload,
                hasMeasuredPing: self.hasMeasuredPing,
                jitter: self.jitter,
                provider: self.provider,
                networkType: self.networkType,
                testDuration: self.testDuration,
                            packetLossPercent: self.packetLossPercent,
                connectionKind: self.connectionKind,
                wifiBandGHz: self.wifiBandGHz,
                wifiContext: self.wifiContext,
                advancedWiFiDiagnostics: self.advancedWiFiDiagnostics
            )

            let m = NetworkMeasurement(
                outcome: .complete,
                downloadMbps: self.downloadSpeed,
                uploadMbps: self.hasMeasuredUpload ? self.uploadSpeed : nil,
                latencyMs: self.hasMeasuredPing ? Double(self.ping) : nil,
                jitterMs: self.jitter,
                packetLossPercent: self.packetLossPercent,
                packetProbeEvidence: self.packetProbeEvidence,
                regionalGameReference: self.regionalGameReference,
                loadedLatencyMs: self.loadedLatencyMs,
                loadedLatencyUploadMs: self.loadedLatencyUploadMs,
                loadResponsiveness: self.loadResponsiveness,
                dnsResolutionMs: self.dnsResolutionMs,
                durationMs: self.rawTestDuration.map { Int(($0 * 1000).rounded()) },
                connectionKind: self.connectionKind,
                wifiBandGHz: self.wifiBandGHz,
                wifiContext: self.wifiContext,
                advancedWiFiDiagnostics: self.advancedWiFiDiagnostics,
                networkIdentifier: self.provider
            )
            self.latestFinishedMeasurement = m
        }
    }

    /// Processa um callback vindo do App Intent/URL. Se a próxima medição
    /// ainda não começou, o dado volta ao inbox para ser associado a ela;
    /// se já houver medição, só atualiza a última quando a janela temporal
    /// comprovar a associação. Nunca cria uma nova medição por conta própria.
    func consumePendingAdvancedWiFiDiagnostics() {
        guard let diagnostics = AdvancedWiFiDiagnosticsInbox.takePending() else { return }
        if isTesting {
            // Recoloca o dado para a resolução no resultado. A serialização
            // local não contém BSSID/MAC e expira de qualquer forma.
            AdvancedWiFiDiagnosticsInbox.requeue(diagnostics)
            return
        }
        guard connectionKind == .wifi,
              let snapshot = lastValidResultSnapshot,
              let finishedMeasurement = latestFinishedMeasurement else {
            AdvancedWiFiDiagnosticsInbox.requeue(diagnostics)
            return
        }
        let endedAt = finishedMeasurement.measuredAt
        let startedAt = endedAt.addingTimeInterval(-Double(finishedMeasurement.durationMs ?? 0) / 1_000)
        guard diagnostics.isEligible(
            forMeasurementStartedAt: startedAt,
            endedAt: endedAt,
            nativeSSID: wifiContext?.ssid
        ) else { return }
        self.advancedWiFiDiagnostics = diagnostics
        persist(diagnostics, onto: latestFinishedMeasurement)
        self.lastValidResultSnapshot = ResultSnapshot(
            downloadSpeed: snapshot.downloadSpeed,
            uploadSpeed: snapshot.uploadSpeed,
            ping: snapshot.ping,
            hasMeasuredUpload: snapshot.hasMeasuredUpload,
            hasMeasuredPing: snapshot.hasMeasuredPing,
            jitter: snapshot.jitter,
            provider: snapshot.provider,
            networkType: snapshot.networkType,
            testDuration: snapshot.testDuration,
            packetLossPercent: snapshot.packetLossPercent,
            connectionKind: snapshot.connectionKind,
            wifiBandGHz: snapshot.wifiBandGHz,
            wifiContext: snapshot.wifiContext,
            advancedWiFiDiagnostics: diagnostics
        )
    }

    private func persist(_ diagnostics: AdvancedWiFiDiagnostics, onto measurement: NetworkMeasurement?) {
        guard let measurement else { return }
        let updated = NetworkMeasurement(
            schemaVersion: measurement.schemaVersion,
            id: measurement.id,
            measuredAt: measurement.measuredAt,
            outcome: measurement.outcome,
            downloadMbps: measurement.downloadMbps,
            uploadMbps: measurement.uploadMbps,
            latencyMs: measurement.latencyMs,
            jitterMs: measurement.jitterMs,
            packetLossPercent: measurement.packetLossPercent,
            packetProbeEvidence: measurement.packetProbeEvidence,
            regionalGameReference: measurement.regionalGameReference,
            loadedLatencyMs: measurement.loadedLatencyMs,
            loadedLatencyUploadMs: measurement.loadedLatencyUploadMs,
            loadResponsiveness: measurement.loadResponsiveness,
            dnsResolutionMs: measurement.dnsResolutionMs,
            durationMs: measurement.durationMs,
            connectionKind: measurement.connectionKind,
            wifiBandGHz: measurement.wifiBandGHz,
            wifiContext: measurement.wifiContext,
            advancedWiFiDiagnostics: diagnostics,
            networkIdentifier: measurement.networkIdentifier,
            serverIdentifier: measurement.serverIdentifier,
            engineVersion: measurement.engineVersion,
            location: measurement.location
        )
        latestFinishedMeasurement = updated
        recentMeasurements = recentMeasurements.map { $0.id == updated.id ? updated : $0 }
        Task { @MainActor in
            let repository = LinkaMeasurementHistory.makeRepository(entitlements: historySyncEntitlements)
            try? await repository.save(updated)
        }
    }

    private func update(with state: MeasurementState) {
        self.progress = state.progress
        if let p = state.ping {
            self.ping = Int(p)
            self.hasMeasuredPing = true
        }
        if let j = state.jitter { self.jitter = j }
        if let d = state.downloadSpeed { self.downloadSpeed = d }
        if let u = state.uploadSpeed {
            self.uploadSpeed = u
            self.hasMeasuredUpload = true
        }
        if let prov = state.provider { self.provider = prov }
        if let net = state.networkType {
            switch net {
            case .wifi: self.networkType = LinkaCopy.value("network.wifi")
            case .cellular: self.networkType = LinkaCopy.value("network.cellular")
            case .unknown: self.networkType = LinkaCopy.value("network.other")
            }
        }
        if let dur = state.duration {
            self.testDuration = Self.formattedDuration(dur)
            self.rawTestDuration = dur
        }
        if let loss = state.packetLossPercent { self.packetLossPercent = loss }
        if let evidence = state.packetProbeEvidence {
            self.packetProbeEvidence = Self.packetProbeEvidence(from: evidence)
        }
        if let reference = state.regionalGameReference {
            self.regionalGameReference = Self.regionalGameReference(from: reference)
        }
        if let loadedLatency = state.loadedLatencyMs { self.loadedLatencyMs = loadedLatency }
        if let loadedLatencyUpload = state.loadedLatencyUploadMs { self.loadedLatencyUploadMs = loadedLatencyUpload }
        if let responsiveness = state.loadResponsiveness {
            self.loadResponsiveness = Self.loadResponsivenessEvidence(from: responsiveness)
        }
        if let dns = state.dnsResolutionMs { self.dnsResolutionMs = dns }
        if let reason = state.failureReason { self.failureReason = reason }

        switch state.phase {
        case .idle: self.uiPhase = .idle
        case .ping: self.uiPhase = .connecting
        case .download: self.uiPhase = .downloading
        case .upload: self.uiPhase = .uploading
        case .result: self.uiPhase = .done
        case .error: self.uiPhase = .error
        }
    }

    private static func loadResponsivenessEvidence(
        from source: EngineLoadResponsivenessEvidence
    ) -> LoadResponsivenessEvidence {
        func latency(_ value: EngineLatencyStatistics?) -> LatencyEvidenceSummary? {
            guard let value else { return nil }
            return LatencyEvidenceSummary(
                medianMs: value.medianMs,
                p95Ms: value.p95Ms,
                maximumMs: value.maximumMs,
                sampleCount: value.sampleCount,
                timeoutCount: value.timeoutCount,
                warmupDurationMs: value.warmupDurationMs
            )
        }
        func phase(_ value: EngineLoadedPhaseEvidence?) -> LoadPhaseEvidence? {
            guard let value else { return nil }
            let saturation: LoadSaturationState = value.saturation == .sustained ? .sustained : .insufficient
            return LoadPhaseEvidence(
                latency: latency(value.latency),
                usefulDurationMs: value.usefulDurationMs,
                bytesTransferred: value.bytesTransferred,
                averageMbps: value.averageMbps,
                saturation: saturation
            )
        }
        let integrity: LoadResponsivenessIntegrity
        switch source.integrity {
        case .valid: integrity = .valid
        case .baselineInconclusive: integrity = .baselineInconclusive
        case .downloadInconclusive: integrity = .downloadInconclusive
        case .uploadInconclusive: integrity = .uploadInconclusive
        }
        return LoadResponsivenessEvidence(
            methodologyVersion: source.methodologyVersion,
            environmentIdentifier: source.environmentIdentifier,
            integrity: integrity,
            baseline: latency(source.baseline),
            download: phase(source.download),
            upload: phase(source.upload)
        )
    }

    private static func packetProbeEvidence(from source: EnginePacketProbeEvidence) -> PacketProbeEvidence {
        PacketProbeEvidence(
            environmentIdentifier: source.environmentIdentifier,
            attemptCount: source.attemptCount,
            successCount: source.successCount,
            failureCount: source.failureCount,
            timeoutCount: source.timeoutCount,
            longestFailureStreak: source.longestFailureStreak,
            expandedAfterInitialWindow: source.expandedAfterInitialWindow,
            completed: source.completed
        )
    }

    private static func regionalGameReference(from source: EngineRegionalGameReference) -> RegionalGameReference {
        RegionalGameReference(
            catalogVersion: source.catalogVersion,
            regionIdentifier: source.regionIdentifier,
            p50LatencyMs: source.p50LatencyMs,
            jitterMs: source.jitterMs,
            attemptCount: source.attemptCount,
            validResponseCount: source.validResponseCount,
            timeoutCount: source.timeoutCount,
            packetLossPercent: source.packetLossPercent,
            status: source.isMeasured ? .measured : .inconclusive
        )
    }

    private static func formattedDuration(_ seconds: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = LinkaLanguagePreference.currentLocale
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return "\(formatter.string(from: NSNumber(value: seconds)) ?? "\(seconds)")s"
    }

    /// Amostra pontual e independente do tipo de interface de rede ativa
    /// no momento da chamada, via um `NWPathMonitor` próprio deste ponto —
    /// nunca lê estado interno do `NWPathMonitor` de `SpeedTestCore`
    /// (issue #51; motor fica intocado, ver AGENTS.md §8 e issue #66 em
    /// paralelo). Chamada no início e no fim do teste para detectar troca
    /// de rede no meio do caminho.
    private static func sampleConnectionKind() async -> NetworkConnectionKind {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.linka.speedtest.viewmodel.interface-sample")
        monitor.start(queue: queue)

        // Mesma folga que `SpeedTestCore` usa para dar tempo do
        // `NWPathMonitor` buscar o caminho inicial antes da leitura.
        try? await Task.sleep(nanoseconds: 100_000_000)

        let path = monitor.currentPath
        monitor.cancel()

        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else {
            return .other
        }
    }

    /// Lê somente os fatos liberados pela plataforma naquele instante. Em
    /// iPhone/iPad `fetchCurrent()` devolve nil até que o usuário conceda a
    /// capability e a localização precisa; esta chamada não pede permissão.
    private static func sampleWiFiContext() async -> WiFiNetworkContext? {
        guard LinkaWiFiPreferences.isIdentificationEnabled else { return nil }
        let hints = await ApplePlatformSignalProvider().currentHints()
        guard let wifi = hints.wifi else { return nil }
        guard wifi.ssid != nil || wifi.bssid != nil || wifi.gateway != nil else { return nil }

        let vendorStr = wifi.gateway?.displayName

        return WiFiNetworkContext(
            ssid: wifi.ssid,
            accessPointIdentifier: localAccessPointIdentifier(for: wifi.bssid),
            securityType: wifi.securityType,
            bandGHz: wifi.band.flatMap(Double.init),
            rssiDbm: wifi.rssiDbm,
            linkSpeedMbps: wifi.linkSpeedMbps,
            gatewayIP: wifi.gateway?.ip,
            gatewayVendor: vendorStr,
            gatewayAdminURL: wifi.gateway?.adminURL?.absoluteString
        )
    }

    /// BSSID nunca sai do processo: o histórico recebe somente este hash com
    /// salt local não sincronizado, suficiente para reconhecer roaming no
    /// próprio aparelho sem expor o identificador físico do AP.
    private static func localAccessPointIdentifier(for bssid: String?) -> String? {
        guard let bssid, !bssid.isEmpty else { return nil }
        let defaults = UserDefaults.standard
        let key = "linka.wifi.access-point-salt.v1"
        let salt: String
        if let existing = defaults.string(forKey: key) {
            salt = existing
        } else {
            salt = UUID().uuidString
            defaults.set(salt, forKey: key)
        }
        let digest = SHA256.hash(data: Data("\(salt)|\(bssid.lowercased())".utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// `--` e `—` são placeholders que o CoreTelephony pode devolver quando
    /// não expõe a operadora; nunca representam o nome de uma rede.
    static func liveCellularNetworkLabel(operatorName: String?, technology: String?) -> String {
        func displayValue(_ raw: String?) -> String? {
            guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  value != "--",
                  value != "—" else {
                return nil
            }
            return value
        }

        let operatorName = displayValue(operatorName)
        let technology = displayValue(technology)

        switch (operatorName, technology) {
        case let (.some(operatorName), .some(technology)):
            return "\(operatorName) · \(technology)"
        case let (.some(operatorName), nil):
            return operatorName
        case let (nil, .some(technology)):
            return technology
        case (nil, nil):
            return LinkaCopy.value("network.cellular")
        }
    }

    // MARK: - Monitoramento em Tempo Real (Idle / Home)

    private func startLiveNetworkMonitoring() {
        let monitor = NWPathMonitor()
        self.livePathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.updateLiveNetwork(with: path)
            }
        }
        monitor.start(queue: livePathQueue)
    }

    public func refreshLiveNetwork() {
        Task { @MainActor [weak self] in
            guard let self, let monitor = self.livePathMonitor else { return }
            await self.updateLiveNetwork(with: monitor.currentPath)
        }
    }

    private func updateLiveNetwork(with path: NWPath) async {
        let kind: NetworkConnectionKind?
        if path.status != .satisfied {
            kind = nil
        } else if path.usesInterfaceType(.wifi) {
            kind = .wifi
        } else if path.usesInterfaceType(.cellular) {
            kind = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            kind = .ethernet
        } else {
            kind = .other
        }
        self.liveConnectionKind = kind

        // A rota é um requisito de validade da medição, não um detalhe de
        // apresentação. Qualquer troca de interface (inclusive indisponível)
        // interrompe o stream antes que ele publique ou persista um resultado.
        if isTesting {
            if measurementConnectionKind == nil, let kind {
                // O monitor ainda não havia entregado o primeiro caminho no
                // instante do toque. Esse primeiro valor estabelece a rota;
                // os seguintes precisam coincidir.
                measurementConnectionKind = kind
            } else if measurementConnectionKind != kind {
                cancelForConnectionChange()
            }
        }

        if kind == .wifi {
            let wifiCtx = await Self.sampleWiFiContext()
            updateLiveWiFiContext(wifiCtx)
        } else if kind == .cellular {
            self.liveWiFiContext = nil
            let hints = await ApplePlatformSignalProvider().currentHints()
            self.liveNetworkLabel = Self.liveCellularNetworkLabel(
                operatorName: hints.mobile?.operatorName,
                technology: hints.mobile?.technology
            )
        } else if kind == .ethernet {
            self.liveWiFiContext = nil
            self.liveNetworkLabel = LinkaCopy.value("network.ethernet")
        } else if path.status != .satisfied {
            self.liveWiFiContext = nil
            self.liveNetworkLabel = LinkaCopy.value("network.offline")
        } else {
            self.liveWiFiContext = nil
            self.liveNetworkLabel = LinkaCopy.value("network.connection")
        }

        reconcileLiveUsageNetworkIdentity()
    }

    /// O `NWPathMonitor` não dispara ao trocar de SSID sem trocar de
    /// interface. Por isso o polling reamostra o contexto Wi-Fi antes de
    /// registrar uma nova sonda e invalida qualquer evidência da rede antiga.
    private func refreshLiveWiFiContextForPolling() async {
        guard liveConnectionKind == .wifi else { return }
        updateLiveWiFiContext(await Self.sampleWiFiContext())
        reconcileLiveUsageNetworkIdentity()
    }

    private func updateLiveWiFiContext(_ wifiCtx: WiFiNetworkContext?) {
        liveWiFiContext = wifiCtx
        if let ssid = wifiCtx?.ssid {
            let band = wifiCtx?.bandGHz ?? ApplePlatformSignalProvider.currentWifiBandGHz()
            if let band {
                let bandStr = band.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", band)
                    : String(format: "%.1f", band)
                liveNetworkLabel = "\(ssid) · \(bandStr) GHz"
            } else {
                liveNetworkLabel = ssid
            }
        } else {
            liveNetworkLabel = LinkaCopy.value("network.wifi")
        }
    }
    
    private var livePollingTask: Task<Void, Never>?

    /// Sessão dedicada e efêmera para o ping ao vivo — nunca compartilha
    /// cache/cookies com o motor de medição nem com `URLSession.shared`, e
    /// usa timeout curto para não deixar uma rede degradada travar o loop de
    /// polling por até 60s (default de `URLSession.shared`). Uma rede ruim
    /// deve virar "perda de pacotes" rapidamente, não uma UI congelada.
    private lazy var livePingSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 4
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    public func startLivePolling() {
        stopLivePolling()
        livePollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }

                // Só coleta métricas ao vivo se NÃO estiver testando — o
                // polling nunca deve concorrer com a medição ativa.
                if !self.isTesting {
                    await self.refreshLiveWiFiContextForPolling()
                    await self.performLivePing()
                    await self.updateLiveRSSI()
                    await self.refreshLiveUsageSuitability()
                }

                // Polling a cada 3 segundos
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    public func stopLivePolling() {
        livePollingTask?.cancel()
        livePollingTask = nil
    }

    private func performLivePing() async {
        // Um ping HTTP leve para estimar latência
        guard let url = URL(string: "https://www.apple.com/library/test/success.html") else { return }
        let start = Date()
        do {
            let (_, response) = try await livePingSession.data(from: url)
            guard !self.isTesting else { return }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode >= 200 && statusCode < 400 {
                let ms = Date().timeIntervalSince(start) * 1000
                self.liveTelemetryCollector.recordProbe(rttMs: ms)
                self.liveDnsLatencyMs = ms
            } else {
                self.liveTelemetryCollector.recordProbe(rttMs: nil)
            }
        } catch {
            guard !self.isTesting else { return }
            self.liveTelemetryCollector.recordProbe(rttMs: nil)
        }
    }

    /// Atualiza a avaliação de casos de uso em tempo real na tela Início.
    public func refreshLiveUsageSuitability() async {
        guard !isTesting else { return }

        guard let ssid = liveUsageWiFiSSID else {
            liveUsageReport = liveUsageEvaluator.evaluate(
                telemetry: liveTelemetryCollector.snapshot(
                    connectionKind: liveConnectionKind,
                    interfaceLabel: liveNetworkLabel,
                    isExpensive: liveConnectionKind == .cellular,
                    isConstrained: false,
                    wifiRssiDbm: liveWifiRSSI
                ),
                baseline: nil
            )
            return
        }

        if currentThroughputBaseline == nil {
            let repository = LinkaMeasurementHistory.makeRepository(entitlements: historySyncEntitlements)
            let baseline = await LiveTelemetryCollector.fetchThroughputBaseline(
                forWiFiSSID: ssid,
                maxAge: 14400,
                repository: repository
            )
            // A busca é assíncrona: só aceita o resultado se ele ainda
            // pertence ao SSID que originou a consulta.
            guard liveUsageWiFiSSID == ssid else { return }
            currentThroughputBaseline = baseline
        }

        #if os(macOS)
        let linkSpeed = liveWiFiContext?.linkSpeedMbps
        #else
        let linkSpeed: Double? = nil
        #endif

        let snapshot = liveTelemetryCollector.snapshot(
            connectionKind: liveConnectionKind,
            interfaceLabel: liveNetworkLabel,
            isExpensive: liveConnectionKind == .cellular,
            isConstrained: false,
            wifiLinkSpeedMbps: linkSpeed,
            wifiRssiDbm: liveWifiRSSI
        )

        if let latency = snapshot.latencyMs {
            self.liveDnsLatencyMs = latency
        }
        if let loss = snapshot.packetLossPercent {
            self.livePacketLossPercent = loss
        }

        self.liveUsageReport = liveUsageEvaluator.evaluate(
            telemetry: snapshot,
            baseline: currentThroughputBaseline
        )
    }

    /// Invalida fatos derivados que não podem sobreviver a troca de rede ou
    /// retorno do background. A rota e o polling serão amostrados novamente.
    func resetLiveUsageState() {
        liveTelemetryCollector.clearBuffer()
        currentThroughputBaseline = nil
        liveUsageWiFiSSID = nil
        liveUsageReport = nil
        liveDnsLatencyMs = nil
        livePacketLossPercent = nil
    }

    func reconcileLiveUsageNetworkIdentity(for sampledSSID: String? = nil) {
        let currentSSID = sampledSSID ?? (liveConnectionKind == .wifi ? liveWiFiContext?.ssid : nil)
        guard currentSSID != liveUsageWiFiSSID else { return }

        liveTelemetryCollector.clearBuffer()
        currentThroughputBaseline = nil
        liveUsageReport = nil
        liveDnsLatencyMs = nil
        livePacketLossPercent = nil
        liveUsageWiFiSSID = currentSSID
    }

    private func publishThroughputBaselineIfEligible(from measurement: NetworkMeasurement) {
        guard measurement.outcome == .complete,
              let ssid = measurement.wifiContext?.ssid,
              ssid == liveUsageWiFiSSID,
              let download = measurement.downloadMbps, download > 0,
              let upload = measurement.uploadMbps, upload > 0 else {
            return
        }

        currentThroughputBaseline = ThroughputBaseline(
            downloadMbps: download,
            uploadMbps: upload,
            lastMeasuredAt: measurement.measuredAt,
            networkIdentifier: ssid
        )
    }

    /// Sinal Wi-Fi ao vivo, atualizado a cada ciclo de polling independente
    /// de mudança de rota (`NWPathMonitor` só dispara em troca de
    /// interface/SSID, não quando o RSSI varia com a pessoa andando pela
    /// casa). No macOS lê `CoreWLAN` diretamente — nunca depende de
    /// `advancedWiFiDiagnostics`, que só existe quando importado
    /// manualmente via Atalhos e por isso fica `nil` na grande maioria das
    /// sessões, deixando "Sinal Wi-Fi" preso em "—" indefinidamente.
    private func updateLiveRSSI() async {
        guard liveConnectionKind == .wifi else {
            if liveWifiRSSI != nil { liveWifiRSSI = nil }
            return
        }
        #if os(macOS)
        liveWifiRSSI = ApplePlatformSignalProvider.currentWifiRSSIDbm()
        #else
        // iPhone/iPad não expõem RSSI por API pública fora de
        // `NEHotspotHelper` (entitlement dedicado). `liveWiFiContext`, que
        // já é amostrado via `sampleWiFiContext()`, é a única fonte
        // possível aqui.
        liveWifiRSSI = liveWiFiContext?.rssiDbm
        #endif
    }
}
