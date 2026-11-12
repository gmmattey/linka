import Foundation
import NetworkCore

/// Sinais que a camada de plataforma pode preencher para enriquecer o snapshot
/// de diagnóstico. O `NetworkDiagnostics` não conhece `CoreWLAN` nem
/// `CoreTelephony` — o app injeta uma implementação concreta.
///
/// - No macOS, um provider pode preencher `wifi` via `CoreWLAN`.
/// - No iOS, `mobile` pode ser preenchido via `CoreTelephony`.
/// - No iOS, `wifi` é preenchido somente quando `fetchCurrent()` recebe a
///   autorização/capability pública exigida pela Apple.
public struct PlatformHints: Equatable, Sendable {
    public var wifi: Wifi?
    public var mobile: Mobile?

    public init(wifi: Wifi? = nil, mobile: Mobile? = nil) {
        self.wifi = wifi
        self.mobile = mobile
    }

    public static let empty = PlatformHints()

    public struct Wifi: Equatable, Sendable {
        public var ssid: String?
        public var bssid: String?
        public var rssiDbm: Double?
        public var band: String?
        public var linkSpeedMbps: Double?
        public var securityType: WiFiSecurityType?
        public var gateway: GatewayInfo?

        public init(
            ssid: String? = nil,
            bssid: String? = nil,
            rssiDbm: Double? = nil,
            band: String? = nil,
            linkSpeedMbps: Double? = nil,
            securityType: WiFiSecurityType? = nil,
            gateway: GatewayInfo? = nil
        ) {
            self.ssid = ssid
            self.bssid = bssid
            self.rssiDbm = rssiDbm
            self.band = band
            self.linkSpeedMbps = linkSpeedMbps
            self.securityType = securityType
            self.gateway = gateway
        }
    }

    public struct Mobile: Equatable, Sendable {
        public var technology: String?
        public var operatorName: String?

        public init(technology: String? = nil, operatorName: String? = nil) {
            self.technology = technology
            self.operatorName = operatorName
        }
    }
}

public protocol PlatformSignalProviding: Sendable {
    func currentHints() async -> PlatformHints
}

public struct NoopPlatformSignalProvider: PlatformSignalProviding {
    public init() {}
    public func currentHints() async -> PlatformHints { .empty }
}
