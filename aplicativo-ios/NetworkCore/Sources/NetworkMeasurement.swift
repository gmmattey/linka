import Foundation

/// Integridade da evidência de responsividade sob carga. `valid` é a única
/// condição que autoriza consumidores a produzir um veredito geral; os
/// demais casos preservam fatos parciais sem promover confiança indevida.
public enum LoadResponsivenessIntegrity: String, Codable, Equatable, Hashable, Sendable {
    case valid
    case baselineInconclusive
    case downloadInconclusive
    case uploadInconclusive
}

public enum LoadSaturationState: String, Codable, Equatable, Hashable, Sendable {
    case sustained
    case insufficient
}

public struct LatencyEvidenceSummary: Codable, Equatable, Hashable, Sendable {
    public let medianMs: Double
    public let p95Ms: Double
    public let maximumMs: Double
    public let sampleCount: Int
    public let timeoutCount: Int
    public let warmupDurationMs: Int

    public init(medianMs: Double, p95Ms: Double, maximumMs: Double, sampleCount: Int, timeoutCount: Int, warmupDurationMs: Int) {
        self.medianMs = medianMs
        self.p95Ms = p95Ms
        self.maximumMs = maximumMs
        self.sampleCount = sampleCount
        self.timeoutCount = timeoutCount
        self.warmupDurationMs = warmupDurationMs
    }
}

public struct LoadPhaseEvidence: Codable, Equatable, Hashable, Sendable {
    public let latency: LatencyEvidenceSummary?
    public let usefulDurationMs: Int
    public let bytesTransferred: Int64
    public let averageMbps: Double?
    public let saturation: LoadSaturationState

    public init(latency: LatencyEvidenceSummary?, usefulDurationMs: Int, bytesTransferred: Int64, averageMbps: Double?, saturation: LoadSaturationState) {
        self.latency = latency
        self.usefulDurationMs = usefulDurationMs
        self.bytesTransferred = bytesTransferred
        self.averageMbps = averageMbps
        self.saturation = saturation
    }
}

/// Envelope aditivo e versionado da metodologia de responsividade. Os
/// escalares legados seguem como projeção das medianas para compatibilidade.
public struct LoadResponsivenessEvidence: Codable, Equatable, Hashable, Sendable {
    public static let currentMethodologyVersion = 1

    public let methodologyVersion: Int
    public let environmentIdentifier: String
    public let integrity: LoadResponsivenessIntegrity
    public let baseline: LatencyEvidenceSummary?
    public let download: LoadPhaseEvidence?
    public let upload: LoadPhaseEvidence?

    public init(
        methodologyVersion: Int = Self.currentMethodologyVersion,
        environmentIdentifier: String,
        integrity: LoadResponsivenessIntegrity,
        baseline: LatencyEvidenceSummary?,
        download: LoadPhaseEvidence?,
        upload: LoadPhaseEvidence?
    ) {
        self.methodologyVersion = methodologyVersion
        self.environmentIdentifier = environmentIdentifier
        self.integrity = integrity
        self.baseline = baseline
        self.download = download
        self.upload = upload
    }
}

/// Resumo verificável das sondagens de estabilidade da medição formal.
/// Não guarda amostras individuais, host ou qualquer identificador de rede.
public struct PacketProbeEvidence: Codable, Equatable, Hashable, Sendable {
    public static let currentMethodologyVersion = 1

    public let methodologyVersion: Int
    public let environmentIdentifier: String
    public let attemptCount: Int
    public let successCount: Int
    public let failureCount: Int
    public let timeoutCount: Int
    public let longestFailureStreak: Int
    public let expandedAfterInitialWindow: Bool
    public let completed: Bool

    public init(
        methodologyVersion: Int = Self.currentMethodologyVersion,
        environmentIdentifier: String,
        attemptCount: Int,
        successCount: Int,
        failureCount: Int,
        timeoutCount: Int,
        longestFailureStreak: Int,
        expandedAfterInitialWindow: Bool,
        completed: Bool
    ) {
        self.methodologyVersion = methodologyVersion
        self.environmentIdentifier = environmentIdentifier
        self.attemptCount = attemptCount
        self.successCount = successCount
        self.failureCount = failureCount
        self.timeoutCount = timeoutCount
        self.longestFailureStreak = longestFailureStreak
        self.expandedAfterInitialWindow = expandedAfterInitialWindow
        self.completed = completed
    }

    public var packetLossPercent: Double? {
        guard completed, attemptCount > 0, failureCount >= 0 else { return nil }
        return Double(failureCount) / Double(attemptCount) * 100
    }
}

/// Referência regional de caminho para jogos. É uma referência de internet,
/// não o ping de um jogo nem a localização da pessoa.
public struct RegionalGameReference: Codable, Equatable, Hashable, Sendable {
    public static let currentMethodologyVersion = 1

    public enum Status: String, Codable, Equatable, Hashable, Sendable {
        case measured
        case inconclusive
    }

    public let methodologyVersion: Int
    public let selectionRuleVersion: Int
    public let catalogVersion: String
    public let regionIdentifier: String?
    public let p50LatencyMs: Double?
    public let jitterMs: Double?
    public let attemptCount: Int
    public let validResponseCount: Int
    public let timeoutCount: Int
    public let packetLossPercent: Double?
    public let status: Status

    public init(
        methodologyVersion: Int = Self.currentMethodologyVersion,
        selectionRuleVersion: Int = 1,
        catalogVersion: String,
        regionIdentifier: String? = nil,
        p50LatencyMs: Double? = nil,
        jitterMs: Double? = nil,
        attemptCount: Int,
        validResponseCount: Int,
        timeoutCount: Int,
        packetLossPercent: Double? = nil,
        status: Status
    ) {
        self.methodologyVersion = methodologyVersion
        self.selectionRuleVersion = selectionRuleVersion
        self.catalogVersion = catalogVersion
        self.regionIdentifier = regionIdentifier
        self.p50LatencyMs = p50LatencyMs
        self.jitterMs = jitterMs
        self.attemptCount = attemptCount
        self.validResponseCount = validResponseCount
        self.timeoutCount = timeoutCount
        self.packetLossPercent = packetLossPercent
        self.status = status
    }
}

public extension NetworkMeasurement {
    /// Única porta de consumo dos escalares de latência sob carga. Registros
    /// anteriores ao envelope continuam usando os fatos legados; quando o
    /// envelope existe, porém, só a integridade `valid` autoriza expor suas
    /// medianas a diagnóstico, Assist, tendência ou otimização.
    var trustedLoadedLatencies: (downloadMs: Double?, uploadMs: Double?) {
        guard let loadResponsiveness else {
            return (loadedLatencyMs, loadedLatencyUploadMs)
        }
        guard loadResponsiveness.integrity == .valid else {
            return (nil, nil)
        }
        return (
            loadResponsiveness.download?.latency?.medianMs,
            loadResponsiveness.upload?.latency?.medianMs
        )
    }
}

/// Contrato canônico de uma medição concluída ou parcialmente aproveitável.
///
/// Contém somente fatos medidos e metadados técnicos mínimos. Diagnóstico,
/// assinatura, UI, perguntas do usuário e regras de produto ficam fora daqui.
public struct NetworkMeasurement: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public let measuredAt: Date
    public let outcome: MeasurementOutcome
    public let downloadMbps: Double?
    public let uploadMbps: Double?
    public let latencyMs: Double?
    public let jitterMs: Double?
    public let packetLossPercent: Double?
    /// Evidência da janela formal de estabilidade. Ausente em medições
    /// legadas e em resultados parciais/cancelados.
    public let packetProbeEvidence: PacketProbeEvidence?
    /// Referência regional para Jogos, executada após as fases do teste.
    public let regionalGameReference: RegionalGameReference?
    public let loadedLatencyMs: Double?
    /// Latência sob carga (ms) durante a fase de upload — issue #128,
    /// paridade com `loadedLatencyMs` (que hoje só cobre download). Campo
    /// aditivo: opcional, `nil` por padrão, não muda `schemaVersion`. Uma
    /// medição antiga (persistida antes desta issue) simplesmente não tem
    /// esta chave no JSON e decodifica com `nil` — mesmo padrão já usado
    /// por `wifiBandGHz` (issue #51) e `durationMs` (issue #50), cobertos
    /// pelos testes `testDecodesLegacyJSONWithout*Field` em
    /// `NetworkCoreTests`. Não reaproveita `loadedLatencyMs` para as duas
    /// fases porque download e upload sob carga são fatos independentes: um
    /// pode existir sem o outro (ex.: sondagem de upload falhou mas a de
    /// download não), e a comparação parada-vs-carga por fase
    /// (`NetworkInsights.LoadResponsivenessEvaluator`) precisa dos dois
    /// valores separadamente, não de um único campo ambíguo.
    public let loadedLatencyUploadMs: Double?
    /// Evidência v1 de responsividade sob carga. Ausente em medições
    /// anteriores; consumidores não podem reinterpretar esse legado como
    /// uma medição de alta confiança.
    public let loadResponsiveness: LoadResponsivenessEvidence?
    /// Tempo de resolução DNS (ms) do host usado no teste — issue Expert
    /// Mode. Campo aditivo: opcional, `nil` por padrão, não muda
    /// `schemaVersion`. Uma medição antiga decodifica com `nil`, mesmo
    /// padrão de `loadedLatencyUploadMs`/`wifiBandGHz`/`durationMs`. `nil`
    /// representa falha ou timeout de resolução — nunca é normalizado para
    /// `0` (AGENTS.md §8: ausência não é zero).
    public let dnsResolutionMs: Double?
    public let durationMs: Int?
    public let connectionKind: NetworkConnectionKind?
    /// Banda Wi-Fi confirmada pelo sistema, em GHz (ex.: `2.4`, `5`) —
    /// issue #51. Só é preenchida quando a plataforma realmente informa a
    /// banda (hoje, `CoreWLAN` no Mac); nunca inferida por SSID/BSSID. `nil`
    /// é o estado normal quando a plataforma não expõe essa informação
    /// (sempre o caso no iPhone) ou quando `connectionKind` não é `.wifi`.
    public let wifiBandGHz: Double?
    /// Contexto factual da rede Wi-Fi usado nesta medição. É opcional para
    /// preservar registros antigos e medições sem autorização da plataforma.
    /// Não contém BSSID cru: `accessPointIdentifier`, quando existir, é um
    /// identificador local derivado (issue #133).
    public let wifiContext: WiFiNetworkContext?
    /// Telemetria Wi-Fi avançada importada conscientemente pelo app Atalhos.
    /// É separada de `wifiContext`, que é a leitura nativa da plataforma.
    /// Nunca contém BSSID ou MAC crus (issue #134).
    public let advancedWiFiDiagnostics: AdvancedWiFiDiagnostics?
    public let networkIdentifier: String?
    public let serverIdentifier: String?
    public let engineVersion: String?
    public let location: MeasurementLocation?
    /// Origem do dispositivo que efetuou a medição (ex.: "macOS", "iOS").
    /// Campo aditivo: opcional, `nil` por padrão, não muda `schemaVersion`.
    public let devicePlatform: String?

    public init(
        schemaVersion: Int = NetworkMeasurementContract.currentSchemaVersion,
        id: UUID = UUID(),
        measuredAt: Date = Date(),
        outcome: MeasurementOutcome = .partial,
        downloadMbps: Double? = nil,
        uploadMbps: Double? = nil,
        latencyMs: Double? = nil,
        jitterMs: Double? = nil,
        packetLossPercent: Double? = nil,
        packetProbeEvidence: PacketProbeEvidence? = nil,
        regionalGameReference: RegionalGameReference? = nil,
        loadedLatencyMs: Double? = nil,
        loadedLatencyUploadMs: Double? = nil,
        loadResponsiveness: LoadResponsivenessEvidence? = nil,
        dnsResolutionMs: Double? = nil,
        durationMs: Int? = nil,
        connectionKind: NetworkConnectionKind? = nil,
        wifiBandGHz: Double? = nil,
        wifiContext: WiFiNetworkContext? = nil,
        advancedWiFiDiagnostics: AdvancedWiFiDiagnostics? = nil,
        networkIdentifier: String? = nil,
        serverIdentifier: String? = nil,
        engineVersion: String? = nil,
        location: MeasurementLocation? = nil,
        devicePlatform: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.measuredAt = measuredAt
        self.outcome = outcome
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.latencyMs = latencyMs
        self.jitterMs = jitterMs
        self.packetProbeEvidence = packetProbeEvidence
        self.regionalGameReference = regionalGameReference
        self.packetLossPercent = packetProbeEvidence?.packetLossPercent ?? packetLossPercent
        self.loadedLatencyMs = loadedLatencyMs
        self.loadedLatencyUploadMs = loadedLatencyUploadMs
        self.loadResponsiveness = loadResponsiveness
        self.dnsResolutionMs = dnsResolutionMs
        self.durationMs = durationMs
        self.connectionKind = connectionKind
        self.wifiBandGHz = wifiBandGHz
        self.wifiContext = wifiContext
        self.advancedWiFiDiagnostics = advancedWiFiDiagnostics
        self.networkIdentifier = networkIdentifier
        self.serverIdentifier = serverIdentifier
        self.engineVersion = engineVersion
        self.location = location
        self.devicePlatform = devicePlatform
    }
}

/// Fatos sobre a rede Wi-Fi expostos publicamente pela plataforma. Campos
/// indisponíveis continuam `nil`; o contrato não infere banda, sinal ou taxa
/// de link a partir do nome da rede.
public struct WiFiNetworkContext: Codable, Equatable, Hashable, Sendable {
    public let ssid: String?
    public let accessPointIdentifier: String?
    public let securityType: WiFiSecurityType?
    public let bandGHz: Double?
    public let rssiDbm: Double?
    public let linkSpeedMbps: Double?
    public let gatewayIP: String?
    public let gatewayVendor: String?
    public let gatewayAdminURL: String?

    public init(
        ssid: String? = nil,
        accessPointIdentifier: String? = nil,
        securityType: WiFiSecurityType? = nil,
        bandGHz: Double? = nil,
        rssiDbm: Double? = nil,
        linkSpeedMbps: Double? = nil,
        gatewayIP: String? = nil,
        gatewayVendor: String? = nil,
        gatewayAdminURL: String? = nil
    ) {
        self.ssid = ssid
        self.accessPointIdentifier = accessPointIdentifier
        self.securityType = securityType
        self.bandGHz = bandGHz
        self.rssiDbm = rssiDbm
        self.linkSpeedMbps = linkSpeedMbps
        self.gatewayIP = gatewayIP
        self.gatewayVendor = gatewayVendor
        self.gatewayAdminURL = gatewayAdminURL
    }

    /// Só associa uma identidade quando o teste começou e terminou no mesmo
    /// SSID. Roaming no mesmo SSID conserva o contexto, mas marca a troca do
    /// ponto de acesso pelo identificador ausente para não escolher um deles.
    public static func resolve(
        start: WiFiNetworkContext?,
        end: WiFiNetworkContext?,
        connectionKind: NetworkConnectionKind?
    ) -> WiFiNetworkContext? {
        guard connectionKind == .wifi,
              let start,
              let end,
              let startSSID = start.ssid,
              let endSSID = end.ssid,
              startSSID == endSSID else {
            return nil
        }

        return WiFiNetworkContext(
            ssid: startSSID,
            accessPointIdentifier: start.accessPointIdentifier == end.accessPointIdentifier
                ? start.accessPointIdentifier
                : nil,
            securityType: start.securityType == end.securityType ? start.securityType : nil,
            bandGHz: start.bandGHz == end.bandGHz ? start.bandGHz : nil,
            rssiDbm: end.rssiDbm,
            linkSpeedMbps: end.linkSpeedMbps,
            gatewayIP: end.gatewayIP ?? start.gatewayIP,
            gatewayVendor: end.gatewayVendor ?? start.gatewayVendor,
            gatewayAdminURL: end.gatewayAdminURL ?? start.gatewayAdminURL
        )
    }
}

public enum WiFiSecurityType: String, Codable, Equatable, Hashable, Sendable {
    case open
    case wep
    case personal
    case enterprise
    case unknown
}

/// Fatos de Wi-Fi que o usuário escolheu importar por um atalho oficial.
/// O contrato não representa capacidade privada: campos que o Atalhos não
/// expõe permanecem ausentes, e nenhuma métrica ausente vira zero.
public struct AdvancedWiFiDiagnostics: Codable, Equatable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static let currentShortcutVersion = 1

    public let schemaVersion: Int
    public let shortcutVersion: Int
    public let captureIdentifier: UUID
    public let capturedAt: Date
    public let ssid: String?
    public let accessPointIdentifier: String?
    public let wifiStandard: String?
    public let rxRateMbps: Double?
    public let txRateMbps: Double?
    public let rssiDbm: Double?
    public let noiseDbm: Double?
    public let channelNumber: Int?
    public let bandGHz: Double?
    public let snrDb: Double?

    public init(
        schemaVersion: Int = AdvancedWiFiDiagnostics.currentSchemaVersion,
        shortcutVersion: Int = AdvancedWiFiDiagnostics.currentShortcutVersion,
        captureIdentifier: UUID = UUID(),
        capturedAt: Date,
        ssid: String? = nil,
        accessPointIdentifier: String? = nil,
        wifiStandard: String? = nil,
        rxRateMbps: Double? = nil,
        txRateMbps: Double? = nil,
        rssiDbm: Double? = nil,
        noiseDbm: Double? = nil,
        channelNumber: Int? = nil,
        bandGHz: Double? = nil,
        snrDb: Double? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.shortcutVersion = shortcutVersion
        self.captureIdentifier = captureIdentifier
        self.capturedAt = capturedAt
        self.ssid = ssid
        self.accessPointIdentifier = accessPointIdentifier
        self.wifiStandard = wifiStandard
        self.rxRateMbps = rxRateMbps
        self.txRateMbps = txRateMbps
        self.rssiDbm = rssiDbm
        self.noiseDbm = noiseDbm
        self.channelNumber = channelNumber
        self.bandGHz = bandGHz
        self.snrDb = snrDb
    }

    /// A faixa é inferida exclusivamente do número de canal IEEE 802.11.
    /// Canais sem mapeamento inequívoco (por exemplo 6 GHz) ficam ausentes;
    /// o Linka nunca usa SSID, RSSI ou taxa para inventar uma banda.
    public static func bandGHz(forChannel channel: Int?) -> Double? {
        guard let channel else { return nil }
        switch channel {
        case 1...14: return 2.4
        case 32...177: return 5
        default: return nil
        }
    }

    public static func snrDb(rssiDbm: Double?, noiseDbm: Double?) -> Double? {
        guard let rssiDbm, let noiseDbm,
              rssiDbm.isFinite, noiseDbm.isFinite else { return nil }
        return rssiDbm - noiseDbm
    }

    /// Janela temporal da issue #134. A captura só pode acompanhar uma
    /// medição quando cai até 30 s antes do começo, durante ela ou até 10 s
    /// depois do fim. O SSID nativo, quando ambos existem, é uma segunda
    /// proteção contra associação cruzada.
    public func isEligible(
        forMeasurementStartedAt startedAt: Date,
        endedAt: Date,
        nativeSSID: String?
    ) -> Bool {
        guard capturedAt >= startedAt.addingTimeInterval(-30),
              capturedAt <= endedAt.addingTimeInterval(10) else {
            return false
        }
        guard let ssid, let nativeSSID else { return true }
        return ssid == nativeSSID
    }
}

public enum MeasurementOutcome: String, Codable, Equatable, Hashable, Sendable {
    case complete
    case partial
}

public enum NetworkConnectionKind: String, Codable, Equatable, Hashable, Sendable {
    case wifi
    case cellular
    case ethernet
    case other
}

public struct MeasurementLocation: Codable, Equatable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public extension NetworkConnectionKind {
    /// Reconcilia amostras de início e fim de uma medição.
    ///
    /// Retorna o tipo comum quando início e fim concordam; `nil` quando
    /// divergem ou quando qualquer uma das amostras está ausente — trocar
    /// de rede (ou não conseguir amostrar) no meio do teste torna o
    /// metadado de interface enganoso, então o estado neutro é preferível
    /// a afirmar um tipo que não valeu para o teste inteiro (issue #51).
    static func resolve(start: NetworkConnectionKind?, end: NetworkConnectionKind?) -> NetworkConnectionKind? {
        guard let start, let end else { return nil }
        return start == end ? start : nil
    }
}

public enum NetworkMeasurementContract {
    public static let currentSchemaVersion = 1

    public static func isValid(_ measurement: NetworkMeasurement) -> Bool {
        violations(for: measurement).isEmpty
    }

    public static func violations(for measurement: NetworkMeasurement) -> [String] {
        var result: [String] = []

        if measurement.schemaVersion != currentSchemaVersion {
            result.append("schemaVersion")
        }

        let metrics: [(String, Double?)] = [
            ("downloadMbps", measurement.downloadMbps),
            ("uploadMbps", measurement.uploadMbps),
            ("latencyMs", measurement.latencyMs),
            ("jitterMs", measurement.jitterMs),
            ("packetLossPercent", measurement.packetLossPercent),
            ("loadedLatencyMs", measurement.loadedLatencyMs),
            ("loadedLatencyUploadMs", measurement.loadedLatencyUploadMs),
            ("dnsResolutionMs", measurement.dnsResolutionMs)
        ]

        for (name, value) in metrics {
            if let value, (!value.isFinite || value < 0) {
                result.append(name)
            }
        }

        if let packetLossPercent = measurement.packetLossPercent,
           packetLossPercent > 100 {
            result.append("packetLossPercent")
        }

        if let probes = measurement.packetProbeEvidence {
            let countsAreConsistent = probes.attemptCount > 0
                && probes.successCount >= 0
                && probes.failureCount >= 0
                && probes.successCount + probes.failureCount == probes.attemptCount
                && probes.timeoutCount >= 0
                && probes.timeoutCount <= probes.failureCount
                && probes.longestFailureStreak >= 0
                && probes.longestFailureStreak <= probes.failureCount
            if probes.methodologyVersion != PacketProbeEvidence.currentMethodologyVersion
                || probes.environmentIdentifier.isEmpty
                || !countsAreConsistent
                || !probes.completed
                || measurement.packetLossPercent != probes.packetLossPercent {
                result.append("packetProbeEvidence")
            }
        }

        if let reference = measurement.regionalGameReference {
            let countsAreConsistent = reference.attemptCount >= 0
                && reference.validResponseCount >= 0
                && reference.validResponseCount <= reference.attemptCount
                && reference.timeoutCount >= 0
                && reference.timeoutCount <= reference.attemptCount
            let valuesAreValid = [reference.p50LatencyMs, reference.jitterMs, reference.packetLossPercent]
                .compactMap { $0 }
                .allSatisfy { $0.isFinite && $0 >= 0 }
            let measuredIsComplete = reference.status != .measured || (
                reference.regionIdentifier != nil && reference.p50LatencyMs != nil && reference.validResponseCount >= 2
            )
            if reference.methodologyVersion != RegionalGameReference.currentMethodologyVersion
                || reference.catalogVersion.isEmpty
                || !countsAreConsistent
                || !valuesAreValid
                || !measuredIsComplete {
                result.append("regionalGameReference")
            }
        }

        if let durationMs = measurement.durationMs, durationMs < 0 {
            result.append("durationMs")
        }

        if let responsiveness = measurement.loadResponsiveness {
            if responsiveness.methodologyVersion != LoadResponsivenessEvidence.currentMethodologyVersion || responsiveness.environmentIdentifier.isEmpty {
                result.append("loadResponsiveness")
            }

            func validLatency(_ summary: LatencyEvidenceSummary?) -> Bool {
                guard let summary else { return true }
                return [summary.medianMs, summary.p95Ms, summary.maximumMs].allSatisfy { $0.isFinite && $0 >= 0 }
                    && summary.medianMs <= summary.p95Ms
                    && summary.p95Ms <= summary.maximumMs
                    && summary.sampleCount > 0
                    && summary.timeoutCount >= 0
                    && summary.warmupDurationMs >= 0
            }
            func validPhase(_ phase: LoadPhaseEvidence?) -> Bool {
                guard let phase else { return true }
                return validLatency(phase.latency)
                    && phase.usefulDurationMs >= 0
                    && phase.bytesTransferred >= 0
                    && (phase.averageMbps.map { $0.isFinite && $0 >= 0 } ?? true)
            }

            if !validLatency(responsiveness.baseline) || !validPhase(responsiveness.download) || !validPhase(responsiveness.upload) {
                result.append("loadResponsiveness")
            }
            if let downloadMedian = responsiveness.download?.latency?.medianMs,
               measurement.loadedLatencyMs != downloadMedian {
                result.append("loadedLatencyMs")
            }
            if let uploadMedian = responsiveness.upload?.latency?.medianMs,
               measurement.loadedLatencyUploadMs != uploadMedian {
                result.append("loadedLatencyUploadMs")
            }
            if responsiveness.integrity == .valid,
               (responsiveness.baseline == nil || responsiveness.download?.latency == nil || responsiveness.upload?.latency == nil || responsiveness.download?.saturation != .sustained || responsiveness.upload?.saturation != .sustained) {
                result.append("loadResponsiveness")
            }
        }

        if let wifiBandGHz = measurement.wifiBandGHz {
            if !wifiBandGHz.isFinite || wifiBandGHz <= 0 {
                result.append("wifiBandGHz")
            }
            // Banda Wi-Fi só faz sentido junto de `connectionKind == .wifi` —
            // caso contrário seria um metadado enganoso (issue #51).
            if measurement.connectionKind != .wifi {
                result.append("wifiBandGHz")
            }
        }

        if measurement.wifiContext != nil, measurement.connectionKind != .wifi {
            result.append("wifiContext")
        }

        if let advanced = measurement.advancedWiFiDiagnostics {
            if measurement.connectionKind != .wifi {
                result.append("advancedWiFiDiagnostics")
            }
            if advanced.schemaVersion != AdvancedWiFiDiagnostics.currentSchemaVersion {
                result.append("advancedWiFiDiagnostics")
            }
            if advanced.shortcutVersion > AdvancedWiFiDiagnostics.currentShortcutVersion || advanced.shortcutVersion < 1 {
                result.append("advancedWiFiDiagnostics")
            }
            for value in [advanced.rxRateMbps, advanced.txRateMbps, advanced.rssiDbm, advanced.noiseDbm, advanced.bandGHz, advanced.snrDb] {
                if let value, !value.isFinite {
                    result.append("advancedWiFiDiagnostics")
                }
            }
            if let rxRate = advanced.rxRateMbps, rxRate < 0 { result.append("advancedWiFiDiagnostics") }
            if let txRate = advanced.txRateMbps, txRate < 0 { result.append("advancedWiFiDiagnostics") }
            if let channel = advanced.channelNumber, channel <= 0 { result.append("advancedWiFiDiagnostics") }
        }

        switch measurement.outcome {
        case .complete:
            if measurement.downloadMbps == nil { result.append("downloadMbps") }
            if measurement.uploadMbps == nil { result.append("uploadMbps") }
            if measurement.latencyMs == nil { result.append("latencyMs") }
        case .partial:
            let hasMeasuredMetric = metrics.contains { $0.1 != nil }
            if !hasMeasuredMetric { result.append("metrics") }
        }

        return Array(Set(result)).sorted()
    }
}
