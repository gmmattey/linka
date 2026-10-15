#if os(macOS)
import SwiftUI
import NetworkCore

struct MacHistoryComparisonSheet: View {
    let first: NetworkMeasurement
    let second: NetworkMeasurement
    let onUnderstandWithAssist: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(first: NetworkMeasurement, second: NetworkMeasurement, onUnderstandWithAssist: (() -> Void)? = nil) {
        self.first = first
        self.second = second
        self.onUnderstandWithAssist = onUnderstandWithAssist
    }

    init(measurements: [NetworkMeasurement], onUnderstandWithAssist: (() -> Void)? = nil) {
        let fallback = NetworkMeasurement(id: UUID(), measuredAt: Date(), connectionKind: .wifi)
        self.first = measurements.first ?? fallback
        self.second = measurements.count > 1 ? measurements[1] : (measurements.first ?? fallback)
        self.onUnderstandWithAssist = onUnderstandWithAssist
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        measurementCard(for: first)
                        measurementCard(for: second)
                    }

                    deltaInsightCard
                }
                .padding(24)
            }
            Divider()
            footerActions
        }
        .frame(minWidth: 680, minHeight: 460)
        .background(Color.surfacePage)
    }

    private var header: some View {
        HStack {
            Text(LinkaCopy.value("mac.history.compare.title"))
                .font(.headline)
                .foregroundColor(.textPrimary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LinkaCopy.value("common.close"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.surfaceCard)
    }

    private func measurementCard(for m: NetworkMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(m.wifiContext?.bandDisplay ?? (m.connectionKind == .wifi ? "Wi-Fi" : "Cabo"))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.brandAccentWarm.opacity(0.12), in: Capsule())
                    .foregroundColor(.brandAccentWarm)
                Spacer()
            }

            Text(Self.dateFormatter.string(from: m.measuredAt))
                .font(.caption)
                .foregroundColor(.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(m.downloadMbps.map { localizedNumber($0, fractionDigits: 1) } ?? "—")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text(LinkaCopy.value("detail.download") + " (Mbps)")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            Divider()

            VStack(spacing: 8) {
                metricRow(
                    label: LinkaCopy.value("detail.upload"),
                    value: m.uploadMbps.map { localizedNumber($0, fractionDigits: 1) + " Mbps" } ?? "—"
                )
                metricRow(
                    label: LinkaCopy.value("assist.latency"),
                    value: m.latencyMs.map { "\(Int(round($0))) ms" } ?? "—"
                )
                metricRow(
                    label: LinkaCopy.value("detail.jitter"),
                    value: m.jitterMs.map { localizedNumber($0, fractionDigits: 1) + " ms" } ?? "—"
                )
                metricRow(
                    label: LinkaCopy.value("detail.packetLoss"),
                    value: m.packetLossPercent.map { localizedNumber($0, fractionDigits: 1) + "%" } ?? "—"
                )
            }

            if let note = m.networkIdentifier, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
        )
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(.textPrimary)
        }
    }

    private var deltaInsightCard: some View {
        let down1 = first.downloadMbps ?? 0
        let down2 = second.downloadMbps ?? 0
        let delta = abs(down2 - down1)
        let formattedDelta = "\(localizedNumber(delta, fractionDigits: 1)) Mbps"

        return HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.brandAccentWarm.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.brandAccentWarm)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: LinkaCopy.value("mac.history.compare.delta"), formattedDelta))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.textPrimary)
                Text(LinkaCopy.value("mac.history.compare.explanation"))
                    .font(.footnote)
                    .foregroundColor(.textSecondary)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
        )
    }

    private var footerActions: some View {
        HStack {
            Spacer()
            Button(LinkaCopy.value("common.close")) {
                dismiss()
            }
            .buttonStyle(.bordered)

            if let onUnderstandWithAssist {
                Button {
                    dismiss()
                    onUnderstandWithAssist()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text(LinkaCopy.value("mac.history.compare.assistAction"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandAccentWarm)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.surfaceCard)
    }

    private static var dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = LinkaLanguagePreference.currentLocale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func localizedNumber(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(fractionDigits))
                .locale(LinkaLanguagePreference.currentLocale)
        )
    }
}
#endif
