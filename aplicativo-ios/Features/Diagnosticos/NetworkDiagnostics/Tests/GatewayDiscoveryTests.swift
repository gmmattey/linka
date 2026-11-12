import XCTest
@testable import NetworkDiagnostics

// Mocks para simular retornos de sysctl/getifaddrs
struct MockNetworkSystemAPI: NetworkSystemAPI {
    var interfaces: [(name: String, flags: Int32, isLoopback: Bool, ipv4: String, netmask: String)] = []
    var gateways: [String: String] = [:] // interface -> gateway IP
    
    func getInterfaces() -> [(name: String, flags: Int32, isLoopback: Bool, ipv4: String, netmask: String)] {
        return interfaces
    }
    
    func getGateway(forInterface name: String) -> String? {
        return gateways[name]
    }
}

final class GatewayDiscoveryTests: XCTestCase {

    let upAndRunningFlags: Int32 = 0x1 | 0x40 // Simulate IFF_UP | IFF_RUNNING

    func testIsPrivateIPv4() {
        XCTAssertTrue(LocalGatewayDiscovery.isPrivateIPv4("192.168.1.1"), "Deve aceitar IP 192.168.x.x")
        XCTAssertTrue(LocalGatewayDiscovery.isPrivateIPv4("10.0.0.1"), "Deve aceitar IP 10.x.x.x")
        XCTAssertTrue(LocalGatewayDiscovery.isPrivateIPv4("172.16.0.1"), "Deve aceitar IP 172.16.x.x")
        XCTAssertTrue(LocalGatewayDiscovery.isPrivateIPv4("172.31.255.254"), "Deve aceitar IP 172.31.x.x")
        XCTAssertTrue(LocalGatewayDiscovery.isPrivateIPv4("169.254.0.1"), "Deve aceitar Link-local")
        
        XCTAssertFalse(LocalGatewayDiscovery.isPrivateIPv4("8.8.8.8"), "Não deve aceitar IP público")
        XCTAssertFalse(LocalGatewayDiscovery.isPrivateIPv4("1.1.1.1"), "Não deve aceitar IP público")
        XCTAssertFalse(LocalGatewayDiscovery.isPrivateIPv4("127.0.0.1"), "Loopback não deve ser aceito como roteador")
        XCTAssertFalse(LocalGatewayDiscovery.isPrivateIPv4("invalido"), "Deve rejeitar IP inválido")
    }

    func testActiveDiscoveryChoosesOnlyAPrivateGatewayWithoutGuessingSuffix() {
        XCTAssertEqual(
            ActiveGatewayDiscovery.firstValidGateway(in: ["8.8.8.8", "10.42.0.254", "192.168.1.1"]),
            "10.42.0.254"
        )
        XCTAssertNil(ActiveGatewayDiscovery.firstValidGateway(in: ["1.1.1.1", "127.0.0.1"]))
    }

    func testGatewayInfoDisplayName() {
        let info = GatewayInfo(ip: "192.168.1.1", isAccessible: false)
        XCTAssertEqual(info.displayName, "Roteador")
    }

    func testDiscoveryWithValidWifiAndGateway() {
        var mockAPI = MockNetworkSystemAPI()
        mockAPI.interfaces = [
            (name: "en0", flags: upAndRunningFlags, isLoopback: false, ipv4: "192.168.1.100", netmask: "255.255.255.0")
        ]
        mockAPI.gateways = ["en0": "192.168.1.1"]
        
        let discovery = LocalGatewayDiscovery(systemAPI: mockAPI)
        let info = discovery.discoverPrimaryInterface()
        
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.name, "en0")
        XCTAssertEqual(info?.gatewayCandidate, "192.168.1.1")
    }

    func testDiscoveryWithPublicGatewayIsRejected() {
        var mockAPI = MockNetworkSystemAPI()
        mockAPI.interfaces = [
            (name: "en0", flags: upAndRunningFlags, isLoopback: false, ipv4: "192.168.1.100", netmask: "255.255.255.0")
        ]
        // Gateway público, deve ser rejeitado por segurança
        mockAPI.gateways = ["en0": "8.8.8.8"]
        
        let discovery = LocalGatewayDiscovery(systemAPI: mockAPI)
        let info = discovery.discoverPrimaryInterface()
        
        XCTAssertNotNil(info)
        XCTAssertNil(info?.gatewayCandidate, "O gateway público não deve ser atribuído")
    }

    func testDiscoveryWithVPNIsIgnored() {
        var mockAPI = MockNetworkSystemAPI()
        mockAPI.interfaces = [
            // Interface VPN (utun)
            (name: "utun0", flags: upAndRunningFlags, isLoopback: false, ipv4: "10.1.1.2", netmask: "255.255.255.255")
        ]
        mockAPI.gateways = ["utun0": "10.1.1.1"]
        
        let discovery = LocalGatewayDiscovery(systemAPI: mockAPI)
        let info = discovery.discoverPrimaryInterface()
        
        XCTAssertNil(info, "A interface VPN utun deve ser completamente ignorada")
    }

    func testDiscoveryWithCellularIsIgnored() {
        var mockAPI = MockNetworkSystemAPI()
        mockAPI.interfaces = [
            // Interface celular (pdp_ip)
            (name: "pdp_ip0", flags: upAndRunningFlags, isLoopback: false, ipv4: "100.64.1.2", netmask: "255.255.255.255")
        ]
        mockAPI.gateways = ["pdp_ip0": "100.64.1.1"]
        
        let discovery = LocalGatewayDiscovery(systemAPI: mockAPI)
        let info = discovery.discoverPrimaryInterface()
        
        XCTAssertNil(info, "A rede móvel deve ser completamente ignorada")
    }

    func testDiscoveryWithLoopbackIsIgnored() {
        var mockAPI = MockNetworkSystemAPI()
        mockAPI.interfaces = [
            (name: "lo0", flags: upAndRunningFlags, isLoopback: true, ipv4: "127.0.0.1", netmask: "255.0.0.0")
        ]
        mockAPI.gateways = ["lo0": "127.0.0.1"]
        
        let discovery = LocalGatewayDiscovery(systemAPI: mockAPI)
        let info = discovery.discoverPrimaryInterface()
        
        XCTAssertNil(info, "Interface de loopback deve ser ignorada")
    }
    
    func testDiscoveryWhenGatewayIsMissing() {
        var mockAPI = MockNetworkSystemAPI()
        mockAPI.interfaces = [
            (name: "en0", flags: upAndRunningFlags, isLoopback: false, ipv4: "192.168.1.100", netmask: "255.255.255.0")
        ]
        // Sem gateway configurado
        mockAPI.gateways = [:]
        
        let discovery = LocalGatewayDiscovery(systemAPI: mockAPI)
        let info = discovery.discoverPrimaryInterface()
        
        XCTAssertNotNil(info)
        XCTAssertNil(info?.gatewayCandidate, "Gateway deve ser nulo se não houver rota padrão")
    }

    func testDiscoveryWithDifferentPrivateNetwork() {
        var mockAPI = MockNetworkSystemAPI()
        // Gateway não terminado em .1
        mockAPI.interfaces = [
            (name: "en0", flags: upAndRunningFlags, isLoopback: false, ipv4: "10.0.0.100", netmask: "255.255.255.0")
        ]
        mockAPI.gateways = ["en0": "10.0.0.254"]
        
        let discovery = LocalGatewayDiscovery(systemAPI: mockAPI)
        let info = discovery.discoverPrimaryInterface()
        
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.gatewayCandidate, "10.0.0.254", "Deve detectar o gateway real independentemente do final ser .1")
    }
}
