import Foundation
import NetworkCore
import NetworkInventory

/// Montador do contexto factual da rede para a consulta ao Genius.
public struct LinkaGeniusContextAssembler: Sendable {
    private let householdRepository: HouseholdRepository?

    public init(householdRepository: HouseholdRepository? = nil) {
        self.householdRepository = householdRepository
    }

    /// Monta o contexto consolidando medição e dados residenciais.
    public func assemble(
        question: String,
        measurement: NetworkMeasurement?,
        locale: String = Locale.current.identifier
    ) async -> LinkaGeniusContext {
        let (plan, devices) = await fetchHouseholdData()

        return LinkaGeniusContext(
            question: question,
            measurement: measurement,
            plan: plan,
            devices: devices,
            locale: Self.normalizeLocale(locale)
        )
    }

    private func fetchHouseholdData() async -> (NetworkServicePlan?, [RegisteredNetworkDevice]) {
        guard let household = householdRepository else { return (nil, []) }
        do {
            let plans = try await household.plans()
            let devices = try await household.devices()
            return (plans.first, devices)
        } catch {
            return (nil, [])
        }
    }

    public static func normalizeLocale(_ identifier: String) -> String {
        let lower = identifier.lowercased()
        if lower.starts(with: "es") { return "es-419" }
        if lower.starts(with: "en") { return "en" }
        return "pt-BR"
    }

    /// Gera uma síntese textual descritiva dos fatos conhecidos para ser injetada no prompt.
    public static func buildFactualReport(for context: LinkaGeniusContext) -> String {
        var lines: [String] = []

        lines.append("## Telemetria e Fatos da Rede Observados")

        // 1. Telemetria do teste recente
        if let m = context.measurement {
            lines.append("### Último Teste de Conexão:")
            if let dl = m.downloadMbps {
                lines.append(String(format: "- Download medido: %.2f Mbps", dl))
            } else {
                lines.append("- Download medido: Não mensurado")
            }

            if let ul = m.uploadMbps {
                lines.append(String(format: "- Upload medido: %.2f Mbps", ul))
            } else {
                lines.append("- Upload medido: Não mensurado")
            }

            if let lat = m.latencyMs {
                lines.append(String(format: "- Ping ocioso (RTT): %.1f ms", lat))
            }
            if let jit = m.jitterMs {
                lines.append(String(format: "- Jitter: %.1f ms", jit))
            }

            let loss = m.packetProbeEvidence?.packetLossPercent ?? m.packetLossPercent
            if let loss {
                lines.append(String(format: "- Perda de pacotes: %.1f%%", loss))
            }

            // Bufferbloat / Latência sob carga
            if let loadedDl = m.loadedLatencyMs {
                let delta = m.latencyMs.map { loadedDl - $0 }
                if let delta {
                    lines.append(String(format: "- Latência sob carga (Download): %.1f ms (+%.1f ms sob tráfego)", loadedDl, delta))
                } else {
                    lines.append(String(format: "- Latência sob carga (Download): %.1f ms", loadedDl))
                }
            }
            if let loadedUl = m.loadedLatencyUploadMs {
                let delta = m.latencyMs.map { loadedUl - $0 }
                if let delta {
                    lines.append(String(format: "- Latência sob carga (Upload): %.1f ms (+%.1f ms sob tráfego)", loadedUl, delta))
                } else {
                    lines.append(String(format: "- Latência sob carga (Upload): %.1f ms", loadedUl))
                }
            }

            // Conexão física e Wi-Fi
            if let kind = m.connectionKind {
                lines.append("- Tipo de interface: \(kind.rawValue)")
            }
            if let band = m.wifiBandGHz ?? m.wifiContext?.bandGHz {
                lines.append(String(format: "- Frequência Wi-Fi: %.1f GHz", band))
            }
            if let ssid = m.wifiContext?.ssid {
                lines.append("- Rede Wi-Fi (SSID): \(ssid)")
            }
            if let rssi = m.wifiContext?.rssiDbm {
                lines.append(String(format: "- Sinal Wi-Fi (RSSI): %.0f dBm", rssi))
            }
            if let linkSpeed = m.wifiContext?.linkSpeedMbps {
                lines.append(String(format: "- Taxa de link Wi-Fi: %.0f Mbps", linkSpeed))
            }
            if let gw = m.wifiContext?.gatewayIP {
                lines.append("- Gateway IP do Roteador: \(gw)")
            }
            if let gwVendor = m.wifiContext?.gatewayVendor {
                lines.append("- Fabricante do Gateway: \(gwVendor)")
            }
            if let dns = m.dnsResolutionMs {
                lines.append(String(format: "- Resolução DNS: %.1f ms", dns))
            }
        } else {
            lines.append("- Nenhuma medição de velocidade foi realizada recentemente.")
        }

        // 2. Plano residencial contratado
        lines.append("### Plano Residencial Contratado:")
        if let plan = context.plan {
            lines.append("- Operadora / Provedor: \(plan.ispName)")
            if let pName = plan.planName {
                lines.append("- Nome do Plano: \(pName)")
            }
            if let nomDl = plan.nominalDownloadMbps {
                lines.append(String(format: "- Velocidade contratada de Download: %.0f Mbps", nomDl))
            }
            if let nomUl = plan.nominalUploadMbps {
                lines.append(String(format: "- Velocidade contratada de Upload: %.0f Mbps", nomUl))
            }
            lines.append("- Tecnologia de Acesso: \(plan.technology.rawValue)")
            if let cents = plan.monthlyCostCents {
                lines.append(String(format: "- Mensalidade: R$ %.2f", Double(cents) / 100.0))
            }
        } else {
            lines.append("- Nenhum plano residencial cadastrado no inventário.")
        }

        // 3. Equipamentos cadastrados
        lines.append("### Equipamentos de Rede Registrados:")
        if !context.devices.isEmpty {
            for dev in context.devices {
                let role = dev.installation.role.rawValue
                let ownership = dev.installation.ownership.rawValue
                let brand = dev.identity.brand.isEmpty ? "Genérico" : dev.identity.brand
                let model = dev.identity.model
                lines.append("- Dispositivo: [\(dev.kind.rawValue)] \(brand) \(model) | Função: \(role) | Posse: \(ownership)")
            }
        } else {
            lines.append("- Nenhum equipamento cadastrado.")
        }

        return lines.joined(separator: "\n")
    }
}
