import Foundation

public enum DiagnosticStep: String, Sendable {
    case verifyingWiFi = "Verificando rede Wi-Fi..."
    case discoveringGateway = "Localizando roteador..."
    case checkingLocalNetwork = "Verificando permissão de rede local..."
    case waitingForPermission = "Aguardando autorização de rede local..."
    case probingLAN = "Medindo sinal até o roteador (LAN)..."
    case confirmingStability = "Avaliando estabilidade da rede..."
    case probingWAN = "Verificando rota para a internet (WAN)..."
    case measuringThroughput = "Validando taxa de vazão..."
    case completing = "Concluindo diagnóstico..."
}

public enum DiagnosticError: LocalizedError, Sendable {
    case notConnectedToWiFi
    case measurementAborted
    case gatewayUnreachable
    case localNetworkPermissionDenied
    case measurementInterruptedByBackground

    public var errorDescription: String? {
        switch self {
        case .notConnectedToWiFi:
            return "O dispositivo não está conectado ao Wi-Fi. Conecte-se à rede Wi-Fi residencial antes de medir."
        case .measurementAborted:
            return "A medição foi interrompida porque a conexão Wi-Fi foi perdida."
        case .gatewayUnreachable:
            return "Não foi possível comunicar com o roteador local."
        case .localNetworkPermissionDenied:
            return "O WiFi Casa precisa de autorização de Rede Local para diagnosticar a conexão com seu roteador. Ative em Ajustes > WiFi Casa > Rede Local."
        case .measurementInterruptedByBackground:
            return "A medição foi pausada porque o app perdeu o foco. Retorne ao WiFi Casa para concluir o teste."
        }
    }
}

public actor WiFiDiagnosticEngine {
    public static let shared = WiFiDiagnosticEngine()

    private let gatewayDiscovery: GatewayDiscoveryService
    private let gatewayProber: GatewayLatencyProber
    private let wanProber: WANProber
    private let throughputProber: ThroughputMicroProber
    private let permissionService: LocalNetworkPermissionService
    private let connectionInfoService: WiFiConnectionInfoServiceProtocol

    public init(
        gatewayDiscovery: GatewayDiscoveryService = .shared,
        gatewayProber: GatewayLatencyProber = GatewayLatencyProber(),
        wanProber: WANProber = WANProber(),
        throughputProber: ThroughputMicroProber = ThroughputMicroProber(),
        permissionService: LocalNetworkPermissionService = .shared,
        connectionInfoService: WiFiConnectionInfoServiceProtocol = WiFiConnectionInfoService.shared
    ) {
        self.gatewayDiscovery = gatewayDiscovery
        self.gatewayProber = gatewayProber
        self.wanProber = wanProber
        self.throughputProber = throughputProber
        self.permissionService = permissionService
        self.connectionInfoService = connectionInfoService
    }

    /// Executa o fluxo de medição ativa no cômodo com cancelamento reativo em tempo real caso o Wi-Fi caia
    public func performMeasurement(
        for roomId: UUID,
        isRouterRoom: Bool,
        progressHandler: (@Sendable (DiagnosticStep, Double) -> Void)? = nil
    ) async throws -> MeasurementResult {
        #if targetEnvironment(simulator)
        let allowSimulatorBypass = true
        #else
        let allowSimulatorBypass = false
        #endif

        let (initialWiFi, initialConnected) = NetworkMonitorService.shared.checkCurrentStatus()
        if (!initialWiFi || !initialConnected) && !allowSimulatorBypass {
            throw DiagnosticError.notConnectedToWiFi
        }

        return try await withThrowingTaskGroup(of: MeasurementResult.self) { group in
            // Watchdog concorrente de queda de Wi-Fi em tempo real
            group.addTask {
                let stream = NetworkMonitorService.shared.wiFiStatusStream()
                for await isWiFi in stream {
                    if !isWiFi && !allowSimulatorBypass {
                        throw DiagnosticError.measurementAborted
                    }
                }
                if Task.isCancelled { throw DiagnosticError.measurementAborted }
                // Se a stream fechar sem erro mas a task for mantida, aguarda cancelamento
                try await Task.sleep(nanoseconds: 30_000_000_000)
                throw DiagnosticError.measurementAborted
            }

            // Worker de execução da sequência de probes
            group.addTask {
                try await self.executeProbingSequence(
                    roomId: roomId,
                    isRouterRoom: isRouterRoom,
                    allowSimulatorBypass: allowSimulatorBypass,
                    progressHandler: progressHandler
                )
            }

            // O primeiro a concluir define o destino do grupo
            guard let firstResult = try await group.next() else {
                throw DiagnosticError.measurementAborted
            }
            group.cancelAll()
            return firstResult
        }
    }

    private func executeProbingSequence(
        roomId: UUID,
        isRouterRoom: Bool,
        allowSimulatorBypass: Bool,
        progressHandler: (@Sendable (DiagnosticStep, Double) -> Void)?
    ) async throws -> MeasurementResult {
        // 1. Verificação inicial do Wi-Fi
        progressHandler?(.verifyingWiFi, 0.1)
        let (isWiFi, _) = NetworkMonitorService.shared.checkCurrentStatus()
        if !isWiFi && !allowSimulatorBypass {
            throw DiagnosticError.notConnectedToWiFi
        }

        // 2. Descoberta do IP do Gateway
        progressHandler?(.discoveringGateway, 0.2)
        if Task.isCancelled { throw DiagnosticError.measurementAborted }
        guard let gatewayIP = gatewayDiscovery.discoverGatewayIP() ?? (allowSimulatorBypass ? "192.168.1.1" : nil) else {
            throw DiagnosticError.gatewayUnreachable
        }

        if Task.isCancelled { throw DiagnosticError.measurementAborted }

        // 2.5. Pre-flight de Permissão de Rede Local (Evita medição incorreta em background durante popup do iOS)
        progressHandler?(.checkingLocalNetwork, 0.3)
        let permissionStatus = await permissionService.prepareLocalNetworkAccess(
            gatewayIP: gatewayIP,
            onWaitingForUserPermission: {
                progressHandler?(.waitingForPermission, 0.3)
            }
        )
        if Task.isCancelled { throw DiagnosticError.measurementAborted }
        if permissionStatus == .denied && !allowSimulatorBypass {
            throw DiagnosticError.localNetworkPermissionDenied
        }

        // 2.6. Consulta das informações do ponto de acesso Wi-Fi conectado (SSID/BSSID)
        await connectionInfoService.requestAuthorizationIfNeeded()
        let connectionInfo = await connectionInfoService.fetchCurrentConnectionInfo()

        // 3. Probing LAN (Roteador: 20 probes base, 500ms timeout, adaptativo +20)
        progressHandler?(.probingLAN, 0.45)
        let lanResult = await gatewayProber.probe(
            gatewayIP: gatewayIP,
            sampleCount: 20,
            timeoutSeconds: 0.5,
            enableAdaptiveProbing: true,
            onAdaptiveConfirmation: {
                progressHandler?(.confirmingStability, 0.55)
            }
        )

        if Task.isCancelled { throw DiagnosticError.measurementAborted }

        // 4. Probing WAN (Internet: 8 probes base, 1.0s timeout, adaptativo +8)
        progressHandler?(.probingWAN, 0.70)
        let wanResult = await wanProber.probe(
            sampleCount: 8,
            timeoutSeconds: 1.0,
            enableAdaptiveProbing: true,
            onAdaptiveConfirmation: {
                progressHandler?(.confirmingStability, 0.80)
            }
        )

        if Task.isCancelled { throw DiagnosticError.measurementAborted }

        // 5. Micro-Throughput (2 MB, timeout 2.5s)
        progressHandler?(.measuringThroughput, 0.9)
        let throughput = await throughputProber.measureThroughputMbps()

        if Task.isCancelled { throw DiagnosticError.measurementAborted }

        progressHandler?(.completing, 1.0)

        // 6. Montagem das métricas
        let metrics = NetworkMetrics(
            gatewayIP: gatewayIP,
            gatewayLatencyMs: lanResult.medianLatencyMs,
            gatewayJitterMs: lanResult.jitterMs,
            gatewayPacketLossPercent: lanResult.packetLossPercent,
            wanLatencyMs: wanResult.wanMedianLatencyMs,
            wanPacketLossPercent: wanResult.wanPacketLossPercent,
            downloadThroughputMbps: throughput,
            connectedNodeName: nil,
            bssid: connectionInfo?.bssid,
            ssid: connectionInfo?.ssid,
            backhaulLatencyMs: nil,
            gatewayMedianMs: lanResult.medianLatencyMs,
            gatewayP95Ms: lanResult.p95LatencyMs,
            gatewayLossEvents: lanResult.lostCount,
            gatewayTotalProbes: lanResult.totalProbes,
            gatewayConsecutiveLoss: lanResult.consecutiveLossCount,
            gatewayLossInterpretation: lanResult.lossInterpretation,
            wanMedianMs: wanResult.wanMedianLatencyMs,
            wanP95Ms: wanResult.wanP95LatencyMs,
            wanJitterMs: wanResult.wanJitterMs,
            wanLossInterpretation: wanResult.wanLossInterpretation
        )

        // 7. Classificação determinística e isolamento LAN vs WAN
        let classification = QualityClassifier.classify(
            metrics: metrics,
            isWiFiActive: isWiFi || allowSimulatorBypass,
            isRouterRoom: isRouterRoom
        )

        return MeasurementResult(
            roomId: roomId,
            timestamp: Date(),
            rating: classification.rating,
            score: classification.score,
            cause: classification.cause,
            metrics: metrics,
            explanation: classification.explanation,
            actionableRecommendation: classification.recommendation
        )
    }

    /// Cria uma medição mock/simulada para uso em testes de UI ou demonstrações
    public nonisolated func createSimulatedMeasurement(
        roomId: UUID,
        rating: QualityRating,
        isRouterRoom: Bool = false,
        bssid: String? = nil,
        ssid: String? = nil
    ) -> MeasurementResult {
        var metrics: NetworkMetrics
        switch rating {
        case .excellent:
            metrics = NetworkMetrics(
                gatewayIP: "192.168.1.1",
                gatewayLatencyMs: 4.2,
                gatewayJitterMs: 1.1,
                gatewayPacketLossPercent: 0.0,
                wanLatencyMs: 18.5,
                wanPacketLossPercent: 0.0,
                downloadThroughputMbps: 220.0,
                gatewayMedianMs: 4.2,
                gatewayP95Ms: 8.5,
                gatewayLossEvents: 0,
                gatewayTotalProbes: 20,
                gatewayConsecutiveLoss: 0,
                gatewayLossInterpretation: .stable,
                wanMedianMs: 18.5,
                wanP95Ms: 24.0,
                wanJitterMs: 3.2,
                wanLossInterpretation: .stable
            )
        case .good:
            metrics = NetworkMetrics(
                gatewayIP: "192.168.1.1",
                gatewayLatencyMs: 15.4,
                gatewayJitterMs: 3.8,
                gatewayPacketLossPercent: 0.0,
                wanLatencyMs: 32.1,
                wanPacketLossPercent: 0.0,
                downloadThroughputMbps: 145.0,
                gatewayMedianMs: 15.4,
                gatewayP95Ms: 28.0,
                gatewayLossEvents: 0,
                gatewayTotalProbes: 20,
                gatewayConsecutiveLoss: 0,
                gatewayLossInterpretation: .stable,
                wanMedianMs: 32.1,
                wanP95Ms: 45.0,
                wanJitterMs: 6.5,
                wanLossInterpretation: .stable
            )
        case .fair:
            metrics = NetworkMetrics(
                gatewayIP: "192.168.1.1",
                gatewayLatencyMs: 32.0,
                gatewayJitterMs: 9.2,
                gatewayPacketLossPercent: 2.5,
                wanLatencyMs: 68.0,
                wanPacketLossPercent: 0.0,
                downloadThroughputMbps: 45.0,
                gatewayMedianMs: 32.0,
                gatewayP95Ms: 65.0,
                gatewayLossEvents: 1,
                gatewayTotalProbes: 40,
                gatewayConsecutiveLoss: 1,
                gatewayLossInterpretation: .isolatedEvent,
                wanMedianMs: 68.0,
                wanP95Ms: 95.0,
                wanJitterMs: 14.0,
                wanLossInterpretation: .stable
            )
        case .poor:
            metrics = NetworkMetrics(
                gatewayIP: "192.168.1.1",
                gatewayLatencyMs: 85.0,
                gatewayJitterMs: 24.0,
                gatewayPacketLossPercent: 7.5,
                wanLatencyMs: 155.0,
                wanPacketLossPercent: 5.0,
                downloadThroughputMbps: 8.5,
                gatewayMedianMs: 85.0,
                gatewayP95Ms: 140.0,
                gatewayLossEvents: 3,
                gatewayTotalProbes: 40,
                gatewayConsecutiveLoss: 2,
                gatewayLossInterpretation: .confirmedLoss,
                wanMedianMs: 155.0,
                wanP95Ms: 220.0,
                wanJitterMs: 35.0,
                wanLossInterpretation: .confirmedLoss
            )
        case .unmeasured:
            metrics = NetworkMetrics()
        }

        metrics.bssid = bssid
        metrics.ssid = ssid

        let classification = QualityClassifier.classify(
            metrics: metrics,
            isWiFiActive: rating != .unmeasured,
            isRouterRoom: isRouterRoom
        )

        return MeasurementResult(
            roomId: roomId,
            timestamp: Date(),
            rating: classification.rating,
            score: classification.score,
            cause: classification.cause,
            metrics: metrics,
            explanation: classification.explanation,
            actionableRecommendation: classification.recommendation
        )
    }
}
