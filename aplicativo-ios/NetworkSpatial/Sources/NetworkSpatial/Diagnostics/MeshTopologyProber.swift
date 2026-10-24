import Foundation

/// Diagnóstico estruturado da integridade e saúde de enlace de um nó de rede (AP / Mesh).
public struct MeshLinkDiagnostic: Sendable, Equatable {
    public let nodeName: String
    public let nodeType: AccessPointType
    public let backhaulType: BackhaulType
    public let nodeLatencyMs: Double?
    public let gatewayLatencyMs: Double
    public let linkQuality: QualityRating
    public let recommendation: String?

    public init(
        nodeName: String,
        nodeType: AccessPointType,
        backhaulType: BackhaulType,
        nodeLatencyMs: Double? = nil,
        gatewayLatencyMs: Double,
        linkQuality: QualityRating,
        recommendation: String?
    ) {
        self.nodeName = nodeName
        self.nodeType = nodeType
        self.backhaulType = backhaulType
        self.nodeLatencyMs = nodeLatencyMs
        self.gatewayLatencyMs = gatewayLatencyMs
        self.linkQuality = linkQuality
        self.recommendation = recommendation
    }
}

/// Motor determinístico de aferição e diagnóstico de saúde de enlace do backhaul Mesh / Multi-AP.
///
/// Avalia se nós satélites ou repetidores estão posicionados adequadamente em relação ao gateway,
/// detectando perdas de pacotes e latência induzida por saltos sem fio fracos.
public actor MeshTopologyProber {
    public typealias LatencyProbeHandler = @Sendable (String) async -> LatencyProbeResult

    private let latencyProber: GatewayLatencyProber
    private let customProbeHandler: LatencyProbeHandler?

    public init(customProbeHandler: LatencyProbeHandler? = nil) {
        self.latencyProber = GatewayLatencyProber()
        self.customProbeHandler = customProbeHandler
    }

    /// Mede e avalia deterministicamente a qualidade de backhaul de um nó em relação ao gateway da rede
    public func probeBackhaulQuality(
        node: AccessPointNode,
        gatewayIP: String
    ) async -> MeshLinkDiagnostic {
        // Executa probe determinístico até o Gateway (ou usa handler injetado para testes)
        let probeResult: LatencyProbeResult
        if let customProbeHandler {
            probeResult = await customProbeHandler(gatewayIP)
        } else {
            probeResult = await latencyProber.probe(gatewayIP: gatewayIP)
        }

        let gatewayLatency = probeResult.meanLatencyMs
        let packetLoss = probeResult.packetLossPercent

        // Enlaces cabeados (Ethernet) possuem perfil de alta estabilidade
        if node.backhaulType == .ethernet {
            let quality: QualityRating = (packetLoss > 2.0 || gatewayLatency > 40.0) ? .fair : .excellent
            return MeshLinkDiagnostic(
                nodeName: node.name,
                nodeType: node.type,
                backhaulType: .ethernet,
                nodeLatencyMs: nil, // O iOS não possui API para mensurar o enlace isolado entre nós
                gatewayLatencyMs: gatewayLatency,
                linkQuality: quality,
                recommendation: nil
            )
        }

        // Para roteador principal cabeado à WAN
        if node.type == .mainRouter {
            let quality: QualityRating
            let recommendation: String?

            if packetLoss > 2.0 || gatewayLatency > 80.0 {
                quality = .poor
                recommendation = "Reinicie o roteador principal ou reposicione para local desobstruído."
            } else if gatewayLatency > 35.0 || packetLoss > 0.0 {
                quality = .fair
                recommendation = "O roteador principal apresenta leve oscilação de resposta local."
            } else if gatewayLatency > 10.0 {
                quality = .good
                recommendation = nil
            } else {
                quality = .excellent
                recommendation = nil
            }

            return MeshLinkDiagnostic(
                nodeName: node.name,
                nodeType: node.type,
                backhaulType: node.backhaulType,
                nodeLatencyMs: nil,
                gatewayLatencyMs: gatewayLatency,
                linkQuality: quality,
                recommendation: recommendation
            )
        }

        // Para Satélites Mesh ou Repetidores Wi-Fi
        // Aferição direta até o gateway. Não inventamos salto fracionário (ex: * 0.35)
        // pois o sandbox do iOS não expõe telemetria interna entre APs.
        let (linkQuality, recommendation) = evaluateMeshBackhaul(
            latencyMs: gatewayLatency,
            lossPercent: packetLoss,
            nodeType: node.type
        )

        return MeshLinkDiagnostic(
            nodeName: node.name,
            nodeType: node.type,
            backhaulType: node.backhaulType,
            nodeLatencyMs: nil,
            gatewayLatencyMs: gatewayLatency,
            linkQuality: linkQuality,
            recommendation: recommendation
        )
    }

    /// Regras canônicas de qualidade de backhaul sem fio Mesh / Repetidor
    private func evaluateMeshBackhaul(
        latencyMs: Double,
        lossPercent: Double,
        nodeType: AccessPointType
    ) -> (QualityRating, String?) {
        let isRepeater = (nodeType == .repeater)

        // Condição crítica (Poor): Perda > 5% ou latência nó-gateway > 60ms
        if lossPercent > 5.0 || latencyMs > 60.0 {
            let message = isRepeater
                ? "Aproxime o repetidor Wi-Fi do roteador principal para reduzir perdas e quedas."
                : "Aproxime o satélite mesh 1 cômodo em direção ao roteador principal."
            return (.poor, message)
        }

        // Condição de alerta (Fair): Perda > 2% ou latência > 30ms
        if lossPercent > 2.0 || latencyMs > 30.0 {
            let message = isRepeater
                ? "Aproxime o repetidor Wi-Fi do roteador principal para melhorar a estabilidade do enlace."
                : "Aproxime o satélite mesh 1 cômodo em direção ao roteador principal."
            return (.fair, message)
        }

        // Condição boa (Good): Latência entre 15ms e 30ms sem perda crítica
        if latencyMs > 15.0 {
            return (.good, nil)
        }

        // Enlace sem fio ideal (Excellent): Latência <= 15ms e perda desprezível
        return (.excellent, nil)
    }
}
