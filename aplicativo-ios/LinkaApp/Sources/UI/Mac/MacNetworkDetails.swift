#if os(macOS)
import Foundation
import SystemConfiguration
#if canImport(CoreWLAN)
import CoreWLAN
#endif

/// Leitura local e pontual do que o macOS informa sobre a rede atual.
/// Não faz requisição externa. O BSSID não é lido: identifica o ponto de acesso.
struct MacNetworkDetails: Equatable {
    var interfaceName: String?
    var ssid: String?
    var bandGHz: Double?
    var channel: Int?
    var channelWidthMHz: Int?
    var phyMode: String?
    var security: String?
    var rssiDbm: Int?
    var noiseDbm: Int?
    var txRateMbps: Double?
    var countryCode: String?
    var localIPv4: String?
    var gatewayIP: String?
    var dnsServers: [String] = []

    var snrDb: Int? {
        guard let rssiDbm, let noiseDbm else { return nil }
        return rssiDbm - noiseDbm
    }

    var isWiFi: Bool { rssiDbm != nil || ssid != nil || phyMode != nil }

    static func capture() -> MacNetworkDetails {
        var details = MacNetworkDetails()
        #if canImport(CoreWLAN)
        if let iface = CWWiFiClient.shared().interface() {
            details.interfaceName = iface.interfaceName
            details.ssid = iface.ssid()
            let rssi = iface.rssiValue()
            details.rssiDbm = rssi == 0 ? nil : rssi
            let noise = iface.noiseMeasurement()
            details.noiseDbm = noise == 0 ? nil : noise
            let rate = iface.transmitRate()
            details.txRateMbps = rate > 0 ? rate : nil
            details.countryCode = iface.countryCode()
            if let channel = iface.wlanChannel() {
                details.channel = channel.channelNumber
                switch channel.channelBand {
                case .band2GHz: details.bandGHz = 2.4
                case .band5GHz: details.bandGHz = 5
                case .band6GHz: details.bandGHz = 6
                default: break
                }
                switch channel.channelWidth {
                case .width20MHz: details.channelWidthMHz = 20
                case .width40MHz: details.channelWidthMHz = 40
                case .width80MHz: details.channelWidthMHz = 80
                case .width160MHz: details.channelWidthMHz = 160
                default: break
                }
            }
            switch iface.activePHYMode() {
            case .mode11a: details.phyMode = "802.11a"
            case .mode11b: details.phyMode = "802.11b"
            case .mode11g: details.phyMode = "802.11g"
            case .mode11n: details.phyMode = "Wi-Fi 4 (802.11n)"
            case .mode11ac: details.phyMode = "Wi-Fi 5 (802.11ac)"
            case .mode11ax: details.phyMode = "Wi-Fi 6 (802.11ax)"
            default: break
            }
            switch iface.security() {
            case .none: details.security = "Aberta"
            case .WEP, .dynamicWEP: details.security = "WEP"
            case .wpaPersonal, .wpaPersonalMixed: details.security = "WPA"
            case .wpa2Personal, .personal: details.security = "WPA2"
            case .wpa3Personal, .wpa3Transition: details.security = "WPA3"
            case .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise, .enterprise, .wpa3Enterprise:
                details.security = "Corporativa"
            default: break
            }
        }
        #endif
        if let store = SCDynamicStoreCreate(nil, "linka" as CFString, nil, nil) {
            let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
            details.gatewayIP = global?["Router"] as? String
            let primary = global?["PrimaryInterface"] as? String
            if details.interfaceName == nil || !details.isWiFi { details.interfaceName = primary ?? details.interfaceName }
            if let primary,
               let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(primary)/IPv4" as CFString) as? [String: Any],
               let addresses = ipv4["Addresses"] as? [String] {
                details.localIPv4 = addresses.first
            }
            if let dns = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
               let servers = dns["ServerAddresses"] as? [String] {
                details.dnsServers = servers
            }
        }
        return details
    }
}
#endif
