import SwiftUI

/// Folha modal que apresenta os pontos de acesso (APs) detectados durante as medições
@available(iOS 17.0, macOS 14.0, *)
public struct DetectedAccessPointsSheet: View {
    public let accessPoints: [DetectedAccessPoint]
    @Environment(\.dismiss) private var dismiss

    public init(accessPoints: [DetectedAccessPoint]) {
        self.accessPoints = accessPoints
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.title3)
                                .foregroundStyle(WiFiCasaTheme.brandAccent)
                            Text("Topologia de Rádios")
                                .font(.headline)
                                .foregroundStyle(WiFiCasaTheme.textPrimary)
                        }

                        Text("Identificamos \(accessPoints.count) ponto\(accessPoints.count > 1 ? "s" : "") de acesso diferente\(accessPoints.count > 1 ? "s" : "") aos quais seu iPhone se associou durante as medições na residência.")
                            .font(.subheadline)
                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("PONTOS DE ACESSO OBSERVADOS")) {
                    ForEach(accessPoints) { ap in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: "wifi.router")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(WiFiCasaTheme.brandAccent)
                                    Text(ap.label)
                                        .font(.headline)
                                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                                }

                                Spacer()

                                Text("\(ap.observedCount) mediç\(ap.observedCount > 1 ? "ões" : "ão")")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(WiFiCasaTheme.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(WiFiCasaTheme.backgroundOverlay)
                                    .clipShape(Capsule())
                            }

                            if let ssid = ap.ssid {
                                LabeledContent("Rede Wi-Fi (SSID)") {
                                    Text(ssid)
                                        .font(.subheadline)
                                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                                }
                            }

                            if let room = ap.firstSeenRoomName {
                                LabeledContent("Primeira Conexão") {
                                    Text(room)
                                        .font(.subheadline)
                                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                                }
                            }

                            DisclosureGroup {
                                LabeledContent("Identificador (BSSID)") {
                                    Text(ap.bssid)
                                        .font(.caption)
                                        .monospaced()
                                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                                        .accessibilityLabel("Endereço físico BSSID \(ap.bssid)")
                                }
                            } label: {
                                Text("Detalhes Técnicos")
                                    .font(.caption)
                                    .foregroundStyle(WiFiCasaTheme.textSecondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(WiFiCasaTheme.brandAccent)

                        Text("Múltiplos pontos de acesso sob o mesmo nome de rede geralmente indicam nós Mesh, repetidores ou roteadores adicionais. O mesmo equipamento também pode emitir BSSIDs distintos para as frequências de 2.4 GHz e 5 GHz.")
                            .font(.footnote)
                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .appListStyle()
            .navigationTitle("Pontos de Acesso")
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WiFiCasaTheme.brandAccent)
                }
            }
        }
    }
}
