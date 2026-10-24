import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
public struct MeasurementDetailSheet: View {
    public let room: Room
    public let measurement: MeasurementResult?
    public let nextRoomName: String?
    public let onNextRoom: (() -> Void)?
    public let onReMeasure: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var didTapNextRoom: Bool = false

    public init(
        room: Room,
        measurement: MeasurementResult?,
        nextRoomName: String? = nil,
        onNextRoom: (() -> Void)? = nil,
        onReMeasure: @escaping () -> Void
    ) {
        self.room = room
        self.measurement = measurement ?? room.lastMeasurement
        self.nextRoomName = nextRoomName
        self.onNextRoom = onNextRoom
        self.onReMeasure = onReMeasure
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let m = measurement {
                    List {
                        // Seção de Status e Score Geral
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Image(systemName: m.rating.systemImage)
                                        .font(.title)
                                        .foregroundStyle(Color.ratingColor(for: m.rating))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.rating.label)
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(Color.ratingColor(for: m.rating))

                                        Text("Score de Qualidade: \(m.score) / 100")
                                            .font(.subheadline)
                                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                                            .monospacedDigit()
                                    }

                                    Spacer()

                                    if room.hasRouter {
                                        Image(systemName: "wifi.router")
                                            .font(.title2)
                                            .foregroundStyle(WiFiCasaTheme.brandAccent)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        // Seção de Diagnóstico: Wi-Fi vs. Operadora
                        Section(header: Text("DIAGNÓSTICO ACIONÁVEL")) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: m.cause.systemImage)
                                        .foregroundStyle(Color.ratingColor(for: m.rating))
                                    Text(m.cause.rawValue)
                                        .font(.headline)
                                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                                }

                                Text(m.explanation)
                                    .font(.subheadline)
                                    .foregroundStyle(WiFiCasaTheme.textPrimary)

                                Divider()
                                    .overlay(WiFiCasaTheme.textSecondary.opacity(0.15))
                                    .padding(.vertical, 2)

                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.caption)
                                        .foregroundStyle(WiFiCasaTheme.scoreFair)
                                    Text(m.actionableRecommendation)
                                        .font(.caption)
                                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                                }


                            }
                            .padding(.vertical, 4)
                        }

                        // Seção Rede Wi-Fi & Ponto de Acesso
                        if m.metrics.ssid != nil || m.metrics.bssid != nil {
                            Section(header: Text("REDE WI-FI & PONTO DE ACESSO")) {
                                if let ssid = m.metrics.ssid {
                                    LabeledContent("Rede Conectada (SSID)") {
                                        Text(ssid)
                                            .fontWeight(.medium)
                                            .foregroundStyle(WiFiCasaTheme.textPrimary)
                                    }
                                }

                                if let bssid = m.metrics.bssid,
                                   let apLabel = AccessPointTracker.shared.label(for: bssid) {
                                    LabeledContent("Ponto de Acesso") {
                                        HStack(spacing: 6) {
                                            Image(systemName: "wifi.router")
                                                .foregroundStyle(WiFiCasaTheme.brandAccent)
                                            Text(apLabel)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(WiFiCasaTheme.textPrimary)
                                        }
                                    }
                                }

                                if let handoff = AccessPointTracker.shared.lastHandoffEvent,
                                   handoff.toBSSID == m.metrics.bssid {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "arrow.triangle.swap")
                                            .foregroundStyle(WiFiCasaTheme.brandAccent)
                                            .padding(.top, 2)
                                        Text("Mudança de ponto de acesso detectada (\(handoff.fromAPName) → \(handoff.toAPName)). Seu iPhone alternou de rádio durante a caminhada.")
                                            .font(.footnote)
                                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                                    }
                                    .padding(.vertical, 2)
                                    .accessibilityLabel("Mudança de ponto de acesso detectada de \(handoff.fromAPName) para \(handoff.toAPName)")
                                }

                                if let bssid = m.metrics.bssid {
                                    DisclosureGroup {
                                        LabeledContent("Identificador (BSSID)") {
                                            Text(bssid)
                                                .font(.caption)
                                                .monospaced()
                                                .foregroundStyle(WiFiCasaTheme.textSecondary)
                                                .accessibilityLabel("Endereço físico BSSID \(bssid)")
                                        }
                                    } label: {
                                        Text("Detalhes Técnicos do AP")
                                            .font(.caption)
                                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                                    }
                                }
                            }
                        }

                        // Seção Segmento Wi-Fi Local (LAN)
                        Section(header: Text("SEGMENTO WI-FI LOCAL (LAN)")) {
                            LabeledContent("Gateway / Roteador") {
                                Text(m.metrics.gatewayIP)
                                    .monospaced()
                                    .foregroundStyle(WiFiCasaTheme.textPrimary)
                            }

                            LabeledContent("Latência no Roteador (Mediana)") {
                                Text("\(String(format: "%.1f", m.metrics.gatewayMedianMs ?? m.metrics.gatewayLatencyMs)) ms")
                                    .monospacedDigit()
                                    .fontWeight(.medium)
                                    .foregroundStyle(WiFiCasaTheme.textPrimary)
                            }

                            if let p95 = m.metrics.gatewayP95Ms {
                                LabeledContent("Pico de Latência (p95)") {
                                    Text("\(String(format: "%.1f", p95)) ms")
                                        .monospacedDigit()
                                        .foregroundStyle(p95 > 40 ? WiFiCasaTheme.scoreFair : WiFiCasaTheme.textPrimary)
                                }
                            }

                            LabeledContent("Jitter Local (RFC 3550)") {
                                Text("\(String(format: "%.1f", m.metrics.gatewayJitterMs)) ms")
                                    .monospacedDigit()
                                    .foregroundStyle(WiFiCasaTheme.textPrimary)
                            }

                            if let interpretation = m.metrics.gatewayLossInterpretation {
                                LabeledContent("Estabilidade de Pacotes") {
                                    HStack(spacing: 6) {
                                        Text(interpretation.badgeText)
                                            .fontWeight(.medium)
                                            .foregroundStyle(interpretation.isDegraded ? WiFiCasaTheme.scorePoor : (interpretation == .isolatedEvent ? WiFiCasaTheme.scoreFair : WiFiCasaTheme.scoreExcellent))

                                        if let lost = m.metrics.gatewayLossEvents, let total = m.metrics.gatewayTotalProbes {
                                            Text("(\(lost)/\(total))")
                                                .font(.caption)
                                                .monospacedDigit()
                                                .foregroundStyle(WiFiCasaTheme.textSecondary)
                                        }
                                    }
                                }
                            } else {
                                LabeledContent("Perda de Pacotes Local") {
                                    Text("\(String(format: "%.1f", m.metrics.gatewayPacketLossPercent))%")
                                        .monospacedDigit()
                                        .foregroundStyle(m.metrics.gatewayPacketLossPercent > 0 ? WiFiCasaTheme.scorePoor : WiFiCasaTheme.textPrimary)
                                }
                            }
                        }

                        // Seção Segmento Internet (WAN)
                        Section(header: Text("SEGMENTO INTERNET (WAN)")) {
                            LabeledContent("Latência Externa (Mediana)") {
                                Text("\(String(format: "%.1f", m.metrics.wanMedianMs ?? m.metrics.wanLatencyMs)) ms")
                                    .monospacedDigit()
                                    .foregroundStyle(WiFiCasaTheme.textPrimary)
                            }

                            if let wanP95 = m.metrics.wanP95Ms {
                                LabeledContent("Pico Externo (p95)") {
                                    Text("\(String(format: "%.1f", wanP95)) ms")
                                        .monospacedDigit()
                                        .foregroundStyle(wanP95 > 120 ? WiFiCasaTheme.scoreFair : WiFiCasaTheme.textPrimary)
                                }
                            }

                            if let wanJitter = m.metrics.wanJitterMs, wanJitter > 0 {
                                LabeledContent("Jitter Externo") {
                                    Text("\(String(format: "%.1f", wanJitter)) ms")
                                        .monospacedDigit()
                                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                                }
                            }

                            LabeledContent("Perda Externa") {
                                Text("\(String(format: "%.1f", m.metrics.wanPacketLossPercent))%")
                                    .monospacedDigit()
                                    .foregroundStyle(m.metrics.wanPacketLossPercent > 0 ? WiFiCasaTheme.scorePoor : WiFiCasaTheme.textPrimary)
                            }

                            LabeledContent("Vazão (Micro-Download 2 MB)") {
                                if let throughput = m.metrics.downloadThroughputMbps, throughput > 0 {
                                    Text("\(String(format: "%.1f", throughput)) Mbps")
                                        .monospacedDigit()
                                        .fontWeight(.medium)
                                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                                } else {
                                    Text("Teste indisponível")
                                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                                }
                            }
                        }

                        // Ações de Continuidade da Caminhada Guiada
                        Section {
                            if let nextRoomName, let onNextRoom {
                                Button(action: {
                                    didTapNextRoom.toggle()
                                    dismiss()
                                    onNextRoom()
                                }) {
                                    HStack {
                                        Spacer()
                                        Label("Ir para o Próximo: \(nextRoomName)", systemImage: "figure.walk")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(WiFiCasaTheme.brandAccent)
                                        Spacer()
                                    }
                                }
                                .sensoryFeedback(.selection, trigger: didTapNextRoom)
                            }

                            Button(action: {
                                dismiss()
                                onReMeasure()
                            }) {
                                HStack {
                                    Spacer()
                                    Label("Medir Novamente", systemImage: "arrow.clockwise")
                                        .font(nextRoomName != nil ? .subheadline : .headline)
                                        .foregroundStyle(nextRoomName != nil ? WiFiCasaTheme.textSecondary : WiFiCasaTheme.textPrimary)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .appListStyle()
                } else {
                    ContentUnavailableView(
                        "Cômodo Não Medido",
                        systemImage: "wifi.slash",
                        description: Text("Realize um teste ativo neste cômodo para visualizar a latência até o roteador e diagnosticar sua conexão.")
                    )
                }
            }
            .navigationTitle(room.name)
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
        }
    }
}
