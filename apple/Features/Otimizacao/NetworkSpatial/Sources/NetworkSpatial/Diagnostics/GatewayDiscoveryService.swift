import Foundation
import Darwin

/// Estrutura binária compatível com a mensagem rt_msghdr do kernel BSD/Darwin
private struct DarwinRoutingMessageHeader {
    var rtm_msglen: UInt16
    var rtm_version: UInt8
    var rtm_type: UInt8
    var rtm_index: UInt16
    var rtm_flags: Int32
    var rtm_addrs: Int32
    var rtm_pid: pid_t
    var rtm_seq: Int32
    var rtm_errno: Int32
    var rtm_use: Int32
    var rtm_inits: UInt32
    var rmx_locks: UInt32
    var rmx_mtu: UInt32
    var rmx_hopcount: UInt32
    var rmx_expire: Int32
    var rmx_recvpipe: UInt32
    var rmx_sendpipe: UInt32
    var rmx_ssthresh: UInt32
    var rmx_rtt: UInt32
    var rmx_rttvar: UInt32
    var rmx_pksent: UInt32
    var rmx_state: UInt32
    var rmx_filler: (UInt32, UInt32, UInt32)
}

public final class GatewayDiscoveryService: Sendable {
    public static let shared = GatewayDiscoveryService()

    public init() {}

    /// Retorna o endereço IPv4 do Gateway local (roteador Wi-Fi) ou nil se não identificado
    public func discoverGatewayIP() -> String? {
        // 1. Tenta obter o Gateway real da tabela de roteamento do kernel (Darwin)
        if let routingGateway = getGatewayFromRoutingTable() {
            return routingGateway
        }

        // 2. Fallback heurístico baseado na sub-rede local de en0 (.1)
        if let localIP = getLocalWiFiIPAddress() {
            let components = localIP.split(separator: ".")
            if components.count == 4 {
                return "\(components[0]).\(components[1]).\(components[2]).1"
            }
        }

        // 3. Não identificado: nunca assumir arbitrariamente 192.168.1.1
        return nil
    }

    /// Retorna o IP do gateway ou 'Não identificado' para apresentação amigável
    public func discoverGatewayIPDisplayString() -> String {
        discoverGatewayIP() ?? "Não identificado"
    }

    /// Alinhamento binário obrigatório pelo kernel Darwin para estruturas sockaddr em tabelas de rota
    private static func roundup(_ a: Int) -> Int {
        let alignment = MemoryLayout<UInt32>.stride
        return a > 0 ? (1 + (((a - 1) | (alignment - 1)))) : alignment
    }

    /// Obtém o Gateway IPv4 padrão inspecionando a tabela de rotas do kernel BSD/Darwin (compatível com iOS e macOS)
    public func getGatewayFromRoutingTable() -> String? {
        let kCTL_NET: Int32 = 4
        let kPF_ROUTE: Int32 = 17
        let kNET_RT_DUMP: Int32 = 1
        let kRTA_DST: Int32 = 0x1
        let kRTA_GATEWAY: Int32 = 0x2

        var mib: [Int32] = [kCTL_NET, kPF_ROUTE, 0, AF_INET, kNET_RT_DUMP, 0]
        var len: size_t = 0
        guard sysctl(&mib, u_int(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, u_int(mib.count), &buffer, &len, nil, 0) == 0 else { return nil }

        var offset = 0
        while offset < len {
            let rtm = buffer.withUnsafeBytes { ptr -> DarwinRoutingMessageHeader in
                ptr.load(fromByteOffset: offset, as: DarwinRoutingMessageHeader.self)
            }
            let msgLen = Int(rtm.rtm_msglen)
            if msgLen == 0 { break }

            let addrs = rtm.rtm_addrs
            if (addrs & kRTA_DST) != 0 && (addrs & kRTA_GATEWAY) != 0 {
                var saOffset = offset + MemoryLayout<DarwinRoutingMessageHeader>.stride

                let dstSa = buffer.withUnsafeBytes { $0.load(fromByteOffset: saOffset, as: sockaddr.self) }
                let dstLen = Self.roundup(Int(dstSa.sa_len))

                var isDefault = false
                if dstSa.sa_family == UInt8(AF_INET) {
                    let sin = buffer.withUnsafeBytes { $0.load(fromByteOffset: saOffset, as: sockaddr_in.self) }
                    if sin.sin_addr.s_addr == 0 {
                        isDefault = true
                    }
                }

                saOffset += dstLen

                if isDefault {
                    let gwSa = buffer.withUnsafeBytes { $0.load(fromByteOffset: saOffset, as: sockaddr.self) }
                    if gwSa.sa_family == UInt8(AF_INET) {
                        let gwSin = buffer.withUnsafeBytes { $0.load(fromByteOffset: saOffset, as: sockaddr_in.self) }
                        var addr = gwSin.sin_addr
                        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        if let cStr = inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) {
                            return String(cString: cStr)
                        }
                    }
                }
            }
            offset += msgLen
        }
        return nil
    }

    /// Obtém o endereço IPv4 local na interface Wi-Fi (en0)
    public func getLocalWiFiIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING)
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp && !isLoopback, let addr = current.pointee.ifa_addr {
                let name = String(cString: current.pointee.ifa_name)
                // en0 é a interface Wi-Fi padrão em dispositivos iOS
                if name == "en0", addr.pointee.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        address = String(cString: hostname)
                        break
                    }
                }
            }
            ptr = current.pointee.ifa_next
        }

        return address
    }
}
