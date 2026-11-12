import Foundation
import NetworkDiagnostics
import NetworkCore
import LinkaEntitlements
import CryptoKit

#if canImport(CoreTelephony) && os(iOS)
import CoreTelephony
#endif

#if canImport(CoreWLAN) && os(macOS)
import CoreWLAN
#endif

#if canImport(NetworkExtension) && os(iOS)
import NetworkExtension
#endif

/// Preenche `PlatformHints` com o que Apple público expõe sem entitlement
/// extra:
/// - iOS: portadora e tecnologia via `CoreTelephony`, SSID/BSSID/tipo de
///   segurança via `NEHotspotNetwork.fetchCurrent()` somente após a
///   capability e a autorização explícita. **Sem** RSSI móvel ou Wi-Fi,
///   banda e link speed (não expostos por esse caminho).
/// - macOS: SSID, BSSID, RSSI e banda via `CoreWLAN`.
struct ApplePlatformSignalProvider: PlatformSignalProviding {
    func currentHints() async -> PlatformHints {
        PlatformHints(
            wifi: await currentWifi(),
            mobile: currentMobile()
        )
    }

    private func currentWifi() async -> PlatformHints.Wifi? {
        // Identificação desligada significa não coletar contexto Wi-Fi para
        // envio ao diagnóstico remoto. Descoberta/probe do roteador é uma
        // ação separada e explícita no painel correspondente: nunca pode
        // atrasar a publicação de uma medição.
        guard LinkaWiFiPreferences.isIdentificationEnabled else { return nil }

        #if canImport(CoreWLAN) && os(macOS)
        guard let iface = CWWiFiClient.shared().interface() else {
            return nil
        }
        let ssid = iface.ssid()
        let bssid = iface.bssid()
        let rssi: Double? = {
            let v = iface.rssiValue()
            return v == 0 ? nil : Double(v)
        }()
        let linkSpeed: Double? = {
            let v = iface.transmitRate()
            return v == 0 ? nil : v
        }()
        let band: String? = {
            let channel = iface.wlanChannel()
            guard let band = channel?.channelBand else { return nil }
            return Self.bandLabel(forGHz: Self.mapCWChannelBand(band))
        }()

        let wifi = PlatformHints.Wifi(
            ssid: ssid,
            bssid: bssid,
            rssiDbm: rssi,
            band: band,
            linkSpeedMbps: linkSpeed,
            securityType: nil
        )
        let anySet = wifi.ssid != nil || wifi.bssid != nil || wifi.rssiDbm != nil
            || wifi.band != nil || wifi.linkSpeedMbps != nil
        return anySet ? wifi : nil
        #elseif canImport(NetworkExtension) && os(iOS)
        if #available(iOS 14.0, *), let network = await NEHotspotNetwork.fetchCurrent() {
            return PlatformHints.Wifi(
                ssid: network.ssid.nilIfEmpty,
                bssid: network.bssid.nilIfEmpty,
                securityType: Self.mapSecurityType(network.securityType)
            )
        }
        return nil
        #else
        return nil
        #endif
    }

    #if canImport(NetworkExtension) && os(iOS)
    private static func mapSecurityType(_ securityType: NEHotspotNetworkSecurityType) -> WiFiSecurityType {
        switch securityType {
        case .open: return .open
        case .WEP: return .wep
        case .personal: return .personal
        case .enterprise: return .enterprise
        case .unknown: return .unknown
        @unknown default: return .unknown
        }
    }
    #endif

    private func currentMobile() -> PlatformHints.Mobile? {
        #if canImport(CoreTelephony) && os(iOS)
        let info = CTTelephonyNetworkInfo()
        let carriers = info.serviceSubscriberCellularProviders ?? [:]
        let technologies = info.serviceCurrentRadioAccessTechnology ?? [:]

        var operatorName: String? = nil
        if let dataID = info.dataServiceIdentifier,
           let name = carriers[dataID]?.carrierName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            operatorName = name
        } else {
            operatorName = carriers.values
                .compactMap { $0.carrierName?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
        }

        var technology: String? = nil
        if let dataID = info.dataServiceIdentifier,
           let tech = technologies[dataID] {
            technology = mapTechnology(tech)
        } else {
            technology = technologies.values.first.flatMap(mapTechnology(_:))
        }

        guard operatorName != nil || technology != nil else { return nil }
        return PlatformHints.Mobile(technology: technology, operatorName: operatorName)
        #else
        return nil
        #endif
    }

    /// Banda Wi-Fi confirmada pelo sistema, em GHz — issue #51. Reaproveita
    /// a mesma leitura de `CWChannel.channelBand` que já alimenta
    /// `PlatformHints.Wifi.band` (via `mapCWChannelBand(_:)`), mas devolve
    /// `Double` (2.4/5) em vez de `String`, para
    /// `NetworkMeasurement.wifiBandGHz`.
    ///
    /// Só macOS: no iPhone não há fonte pública de banda sem
    /// `NEHotspotHelper` (entitlement) nem sem localização — `nil` é o
    /// estado normal ali, não erro. Nunca infere banda por SSID/BSSID.
    static func currentWifiBandGHz() -> Double? {
        #if canImport(CoreWLAN) && os(macOS)
        guard let iface = CWWiFiClient.shared().interface(),
              let band = iface.wlanChannel()?.channelBand else {
            return nil
        }
        return mapCWChannelBand(band)
        #else
        return nil
        #endif
    }

    /// RSSI Wi-Fi ao vivo, em dBm, direto do `CoreWLAN` — só macOS. Fonte
    /// para o polling contínuo de "Sua Rede Agora": diferente de
    /// `AdvancedWiFiDiagnostics` (que só existe quando importado
    /// manualmente via Atalhos), esta leitura é síncrona e sempre
    /// disponível quando há interface Wi-Fi conectada, sem depender de
    /// nenhuma ação explícita da pessoa.
    static func currentWifiRSSIDbm() -> Double? {
        #if canImport(CoreWLAN) && os(macOS)
        guard let iface = CWWiFiClient.shared().interface() else { return nil }
        let value = iface.rssiValue()
        return value == 0 ? nil : Double(value)
        #else
        return nil
        #endif
    }

    #if canImport(CoreWLAN) && os(macOS)
    /// Única tradução de `CWChannelBand` do arquivo — issue #89. Antes,
    /// `currentWifi()` (produzindo `String?`) e `currentWifiBandGHz()`
    /// (produzindo `Double?`) reimplementavam este switch de forma
    /// independente, correndo o risco de divergir silenciosamente se um
    /// novo case fosse tratado diferente nos dois lugares. Agora os dois
    /// call sites delegam pra cá; a tradução `Double -> String` em
    /// `bandLabel(forGHz:)` é conversão de formato, não uma segunda fonte
    /// de verdade sobre o significado de cada `CWChannelBand` case.
    static func mapCWChannelBand(_ band: CWChannelBand) -> Double? {
        switch band {
        case .band2GHz: return 2.4
        case .band5GHz: return 5.0
        case .band6GHz: return 6.0
        case .bandUnknown: return nil
        @unknown default: return nil
        }
    }

    /// Rótulo textual da banda a partir do `Double?` já mapeado por
    /// `mapCWChannelBand(_:)` — não reabre o switch sobre `CWChannelBand`.
    static func bandLabel(forGHz ghz: Double?) -> String? {
        guard let ghz else { return nil }
        if ghz == 2.4 { return "2.4GHz" }
        if ghz == 5.0 { return "5GHz" }
        if ghz == 6.0 { return "6GHz" }
        return nil
    }
    #endif

    #if canImport(CoreTelephony) && os(iOS)
    private func mapTechnology(_ raw: String) -> String? {
        switch raw {
        case CTRadioAccessTechnologyLTE: return "4G"
        case CTRadioAccessTechnologyNRNSA, CTRadioAccessTechnologyNR: return "5G"
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA,
             CTRadioAccessTechnologyHSUPA, CTRadioAccessTechnologyCDMA1x,
             CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB, CTRadioAccessTechnologyeHRPD:
            return "3G"
        case CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyGPRS:
            return "2G"
        default:
            return nil
        }
    }
    #endif
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

#if os(macOS) && canImport(CoreWLAN)
/// Captura local e pontual dos dados que o CoreWLAN informou ao Mac.
/// BSSID só atravessa esta fronteira para virar um identificador com hash
/// local; nunca entra cru no resultado, histórico ou cartão compartilhado.
struct MacAdvancedWiFiDiagnosticsProvider {
    func capture(entitlement: LinkaEntitlementSnapshot) -> AdvancedWiFiDiagnostics? {
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        let channel = interface.wlanChannel()?.channelNumber
        let rssi = interface.rssiValue()
        let txRate = interface.transmitRate()
        guard rssi != 0 || txRate > 0 || channel != nil else { return nil }

        return AdvancedWiFiDiagnosticsInbox.makeNativeDiagnostics(
            entitlement: entitlement,
            ssid: interface.ssid(),
            bssid: interface.bssid(),
            txRateMbps: txRate > 0 ? txRate : nil,
            rssiDbm: rssi == 0 ? nil : Double(rssi),
            channelNumber: channel
        )
    }
}
#endif
