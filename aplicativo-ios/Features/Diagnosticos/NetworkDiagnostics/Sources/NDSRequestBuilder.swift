import Foundation
import NetworkCore

public struct NDSRequestBuilder: Sendable {
    public init() {}

    public func buildRequest(
        current: NetworkMeasurement,
        platformHints: PlatformHints,
        appVersion: String?,
        platformIdentifier: String,
        requestAI: Bool,
        locale: String? = nil,
        diagnosticContext: NDSRequest.DiagnosticContext? = nil,
        historical: NDSRequest.Historical? = nil
    ) -> NDSRequest {
        let hasInternet: Bool? = (current.latencyMs != nil || current.downloadMbps != nil) ? true : nil
        let bandStr: String? = current.wifiBandGHz.map { String($0) }
        let connection = mapConnection(current.connectionKind, hasInternet: hasInternet)
        let wifi = mapWifi(
            platformHints.wifi,
            context: current.wifiContext,
            advanced: current.advancedWiFiDiagnostics,
            kind: current.connectionKind,
            band: bandStr
        )
        let speed = mapSpeed(downloadMbps: current.downloadMbps, uploadMbps: current.uploadMbps)
        let trustedLoadedLatencies = current.trustedLoadedLatencies
        let quality = mapQuality(
            latencyMs: current.latencyMs,
            loadedLatencyMs: trustedLoadedLatencies.downloadMs,
            loadedLatencyUploadMs: trustedLoadedLatencies.uploadMs,
            dnsResolutionMs: current.dnsResolutionMs,
            jitterMs: current.jitterMs,
            packetLossPercent: current.packetLossPercent
        )

        var capabilities: [String] = []
        if connection != nil {
            capabilities.append("connection")
        }
        if wifi != nil {
            capabilities.append("wifi")
        }
        if speed != nil {
            capabilities.append("speed")
        }
        if quality != nil {
            capabilities.append("quality")
        }
        if historical != nil {
            capabilities.append("historical")
        }

        return NDSRequest(
            schemaVersion: "1.0",
            request_id: UUID().uuidString,
            sessionId: current.id.uuidString,
            platform: platformIdentifier,
            // The presentation language is selected by Linka, not inferred
            // from the device here. This keeps a manual override consistent
            // all the way to the relay. Existing API callers retain pt-BR.
            locale: locale ?? "pt-BR",
            app: NDSRequest.AppInfo(id: "linka", version: appVersion ?? "1.0.0"),
            capabilities: capabilities,
            requestedOutputs: requestAI ? ["scoring", "ai"] : ["scoring"],
            context: diagnosticContext,
            connection: connection,
            wifi: wifi,
            speed: speed,
            quality: quality,
            historical: historical
        )
    }

    private func mapSpeed(downloadMbps: Double?, uploadMbps: Double?) -> NDSRequest.Speed? {
        let validDownload = downloadMbps.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let validUpload = uploadMbps.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }

        guard validDownload != nil || validUpload != nil else { return nil }
        return NDSRequest.Speed(downloadMbps: validDownload, uploadMbps: validUpload)
    }

    private func mapQuality(
        latencyMs: Double?,
        loadedLatencyMs: Double?,
        loadedLatencyUploadMs: Double?,
        dnsResolutionMs: Double?,
        jitterMs: Double?,
        packetLossPercent: Double?
    ) -> NDSRequest.Quality? {
        let validLatency = latencyMs.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let validLoaded = loadedLatencyMs.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let validLoadedUpload = loadedLatencyUploadMs.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let validDns = dnsResolutionMs.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let validJitter = jitterMs.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let validLoss = packetLossPercent.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }

        guard validLatency != nil || validLoaded != nil || validLoadedUpload != nil || validDns != nil || validJitter != nil || validLoss != nil else {
            return nil
        }
        return NDSRequest.Quality(
            latencyMs: validLatency,
            loadedLatencyMs: validLoaded,
            loadedLatencyUploadMs: validLoadedUpload,
            dnsResolutionMs: validDns,
            jitterMs: validJitter,
            packetLossPercent: validLoss
        )
    }

    private func mapConnection(_ kind: NetworkConnectionKind?, hasInternet: Bool?) -> NDSRequest.Connection? {
        guard let kind = kind else { return nil }
        let typeStr: String
        switch kind {
        case .wifi: typeStr = "wifi"
        case .cellular: typeStr = "cellular"
        case .ethernet: typeStr = "ethernet"
        case .other: typeStr = "other"
        }
        return NDSRequest.Connection(type: typeStr, hasInternet: hasInternet)
    }

    private func mapWifi(_ hint: PlatformHints.Wifi?, context: WiFiNetworkContext?, advanced: AdvancedWiFiDiagnostics?, kind: NetworkConnectionKind?, band: String?) -> NDSRequest.Wifi? {
        guard kind == .wifi else { return nil }
        let rssi = advanced?.rssiDbm ?? context?.rssiDbm ?? hint?.rssiDbm
        let linkSpeed = advanced?.txRateMbps ?? advanced?.rxRateMbps ?? context?.linkSpeedMbps ?? hint?.linkSpeedMbps
        
        let validBand = band ?? context?.bandGHz.map { String($0) } ?? advanced?.bandGHz.map { String($0) }
        let securityType = context?.securityType?.rawValue
        let rxRate = advanced?.rxRateMbps
        let txRate = advanced?.txRateMbps
        let noise = advanced?.noiseDbm
        let snr = advanced?.snrDb
        let channel = advanced?.channelNumber
        // Endereços e URLs locais não são necessários para a avaliação
        // remota. Permanecem no aparelho para a tela de detalhes, mas nunca
        // entram no payload do relay.
        let gwIP: String? = nil
        let gwVendor: String? = nil
        let gwAdminURL: String? = nil
        
        guard rssi != nil || linkSpeed != nil || validBand != nil || securityType != nil || rxRate != nil || txRate != nil || noise != nil || snr != nil || channel != nil || gwIP != nil || gwVendor != nil || gwAdminURL != nil else { return nil }
        
        return NDSRequest.Wifi(
            rssiDbm: rssi,
            linkSpeedMbps: linkSpeed,
            band: validBand,
            securityType: securityType,
            rxRateMbps: rxRate,
            txRateMbps: txRate,
            noiseDbm: noise,
            snrDb: snr,
            channelNumber: channel,
            gatewayIP: gwIP,
            gatewayVendor: gwVendor,
            gatewayAdminURL: gwAdminURL
        )
    }
}
