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
                            Text(SpatialCopy.value("spatial.aps.title", defaultValue: "Topologia de Rádios"))
                                .font(.headline)
                                .foregroundStyle(WiFiCasaTheme.textPrimary)
                        }

                        let apNoun = accessPoints.count == 1 ? (SpatialCopy.currentLanguageTag == "en" ? "access point" : (SpatialCopy.currentLanguageTag == "es-419" ? "punto de acceso" : "ponto de acesso")) : (SpatialCopy.currentLanguageTag == "en" ? "access points" : (SpatialCopy.currentLanguageTag == "es-419" ? "puntos de acceso" : "pontos de acesso"))
                        Text(SpatialCopy.format("spatial.aps.count", accessPoints.count, apNoun))
                            .font(.subheadline)
                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text(SpatialCopy.value("spatial.aps.observed", defaultValue: "PONTOS DE ACESSO OBSERVADOS"))) {
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

                                let mNoun = ap.observedCount == 1 ? (SpatialCopy.currentLanguageTag == "en" ? "measurement" : (SpatialCopy.currentLanguageTag == "es-419" ? "medición" : "medição")) : (SpatialCopy.currentLanguageTag == "en" ? "measurements" : (SpatialCopy.currentLanguageTag == "es-419" ? "mediciones" : "medições"))
                                Text(SpatialCopy.format("spatial.aps.measurements", ap.observedCount, mNoun))
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
                                Text(SpatialCopy.value("spatial.aps.techDetails", defaultValue: "Detalhes Técnicos"))
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

                        Text(SpatialCopy.value("spatial.aps.explanation", defaultValue: "Múltiplos pontos de acesso sob o mesmo nome de rede geralmente indicam nós Mesh, repetidores ou roteadores adicionais. O mesmo equipamento também pode emitir BSSIDs distintos para as frequências de 2.4 GHz e 5 GHz."))
                            .font(.footnote)
                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .appListStyle()
            .navigationTitle(SpatialCopy.value("spatial.ap.multiple.title", defaultValue: "Pontos de Acesso"))
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(SpatialCopy.value("spatial.common.ok", defaultValue: "OK")) {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WiFiCasaTheme.brandAccent)
                }
            }
        }
    }
}
