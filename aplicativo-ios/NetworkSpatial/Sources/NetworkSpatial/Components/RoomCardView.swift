import SwiftUI

public struct RoomCardView: View {
    public let room: Room
    public let isSelected: Bool
    public let onMeasureTap: () -> Void
    public let onDetailTap: () -> Void

    public init(
        room: Room,
        isSelected: Bool = false,
        onMeasureTap: @escaping () -> Void,
        onDetailTap: @escaping () -> Void
    ) {
        self.room = room
        self.isSelected = isSelected
        self.onMeasureTap = onMeasureTap
        self.onDetailTap = onDetailTap
    }

    private var rating: QualityRating {
        room.currentRating
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Cabeçalho do Card: Ícone do cômodo em tile neutro + Badge de Ponto de Acesso
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WiFiCasaTheme.backgroundOverlay)
                        .frame(width: 32, height: 32)

                    Image(systemName: room.icon)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                }
                .accessibilityHidden(true)

                Spacer()

                let nodeType = room.accessPoint?.type ?? (room.hasRouter ? .mainRouter : .none)
                APNodeBadgeView(type: nodeType, isCompact: true)
            }

            // Nome do cômodo
            Text(room.name)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(WiFiCasaTheme.textPrimary)
                .lineLimit(1)

            // Status de Qualidade + Latência com alto contraste
            HStack(spacing: 6) {
                if rating == .unmeasured {
                    Image(systemName: "circle.dashed")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(WiFiCasaTheme.textSecondary)

                    Text("Não Medido")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                } else {
                    Circle()
                        .fill(Color.ratingColor(for: rating))
                        .frame(width: 8, height: 8)

                    Text(rating.label)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.ratingColor(for: rating))
                }

                Spacer()

                if let measurement = room.lastMeasurement {
                    Text("\(String(format: "%.0f", measurement.metrics.gatewayLatencyMs)) ms")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                        .monospacedDigit()
                }
            }

            // Tag discriminada de diagnóstico + Micro-chip de AP detectado
            if let measurement = room.lastMeasurement {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: room.diagnosisTag.systemImage)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(room.diagnosisTag.isIssue ? Color.ratingColor(for: rating) : WiFiCasaTheme.scoreGood)

                        Text(room.diagnosisTag.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(room.diagnosisTag.isIssue ? Color.ratingColor(for: rating).opacity(0.20) : WiFiCasaTheme.backgroundOverlay)
                    .clipShape(Capsule())

                    if let bssid = measurement.metrics.bssid,
                       let apLabel = AccessPointTracker.shared.label(for: bssid) {
                        HStack(spacing: 3) {
                            Image(systemName: "wifi.router")
                                .font(.caption2.weight(.medium))
                            Text(apLabel)
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3.5)
                        .background(WiFiCasaTheme.backgroundOverlay)
                        .clipShape(Capsule())
                        .accessibilityLabel("Conectado ao Ponto de Acesso \(apLabel)")
                    }
                }
            }

            Spacer(minLength: 2)

            Divider()
                .overlay(WiFiCasaTheme.textSecondary.opacity(0.18))

            // Ações: Ver Detalhes ou Medir/Re-medir (Layout anti-quebra com fixedSize e lineLimit)
            HStack {
                Button(action: onDetailTap) {
                    HStack(spacing: 2) {
                        Text(room.lastMeasurement != nil ? "Detalhes" : "Info")
                            .font(.caption.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(WiFiCasaTheme.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(room.lastMeasurement != nil ? "Ver detalhes de \(room.name)" : "Ver informações de \(room.name)")
                .accessibilityHint("Abre o diagnóstico aprofundado deste cômodo")

                Spacer(minLength: 4)

                Button(action: onMeasureTap) {
                    HStack(spacing: 4) {
                        Image(systemName: room.lastMeasurement != nil ? "arrow.clockwise" : "play.fill")
                            .font(.caption2.weight(.bold))
                        Text(room.lastMeasurement != nil ? "Re-medir" : "Medir")
                            .font(.caption.weight(.bold))
                    }
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(WiFiCasaTheme.brandAccent.opacity(0.20))
                    .foregroundStyle(WiFiCasaTheme.brandAccentWarm)
                    .clipShape(Capsule())
                    .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(room.lastMeasurement != nil ? "Re-medir \(room.name)" : "Iniciar medição em \(room.name)")
                .accessibilityHint("Inicia o diagnóstico de latência e sinal Wi-Fi")
            }
        }
        .padding(13)
        .frame(minHeight: 140)
        // Profundidade por camadas pura: Fundo neutro elevado uniforme (idêntico ao Lagcheck), sem bordas e sem fundos lamacentos
        .background(
            ZStack {
                WiFiCasaTheme.backgroundRaised
                if isSelected {
                    WiFiCasaTheme.brandAccent.opacity(0.08)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(room.name)\(room.hasRouter ? ", com roteador" : "")")
        .accessibilityValue(
            room.lastMeasurement != nil
            ? "\(rating.label). \(room.diagnosisTag.rawValue). Latência no roteador de \(String(format: "%.0f", room.lastMeasurement!.metrics.gatewayLatencyMs)) milissegundos."
            : "Cômodo não medido."
        )
        .accessibilityAction(named: room.lastMeasurement != nil ? "Ver detalhes" : "Ver informações", onDetailTap)
        .accessibilityAction(named: room.lastMeasurement != nil ? "Re-medir cômodo" : "Iniciar medição", onMeasureTap)
    }
}
