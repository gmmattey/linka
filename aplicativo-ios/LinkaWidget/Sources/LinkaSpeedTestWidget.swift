import WidgetKit
import SwiftUI
import AppIntents
import LinkaAppIntents
import LinkaWidgetShared

/// Símbolo vetorial estilizado da marca Linka para o Widget
struct LinkaBrandMark: View {
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.brandAccentWarm.opacity(0.3), lineWidth: size * 0.18)
            Circle()
                .trim(from: 0.0, to: 0.72)
                .stroke(Color.brandAccentWarm, style: StrokeStyle(lineWidth: size * 0.18, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(Color.brandAccentWarm)
                .frame(width: size * 0.28, height: size * 0.28)
        }
        .frame(width: size, height: size)
    }
}

struct LinkaSpeedTestWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LinkaWidgetEntry

    private var locale: Locale {
        LinkaWidgetShared.effectiveLocale(
            preference: LinkaWidgetShared.languagePreference()
        )
    }

    var body: some View {
        widgetBody
            .environment(\.locale, locale)
            .containerBackground(for: .widget) {
                switch family {
                case .accessoryCircular, .accessoryRectangular, .accessoryInline:
                    Color.clear
                default:
                    Color.surfacePage
                }
            }
    }

    @ViewBuilder
    private var widgetBody: some View {
        switch family {
        case .systemMedium:
            mediumBody
        case .accessoryCircular:
            accessoryCircularBody
        case .accessoryRectangular:
            accessoryRectangularBody
        case .accessoryInline:
            accessoryInlineBody
        default:
            smallBody
        }
    }

    // MARK: - System Small

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                LinkaBrandMark(size: 15)
                Text(localized("Linka"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Spacer(minLength: 0)
                if let summary = entry.summary {
                    Text(relativeLabel(for: summary.measuredAt))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
            }
            .padding(.bottom, 8)

            Spacer(minLength: 0)

            // Center Ring / Metric or Empty
            if let summary = entry.summary {
                HStack {
                    Spacer(minLength: 0)
                    ZStack {
                        Circle()
                            .stroke(Color.borderDefault.opacity(0.4), lineWidth: 3.5)
                        Circle()
                            .trim(from: 0, to: ringProgress(summary.downloadMbps))
                            .stroke(Color.brandAccentWarm, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(formattedMbps(summary.downloadMbps))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(localized("Mbps"))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.textSecondary)
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(width: 68, height: 68)
                    Spacer(minLength: 0)
                }
            } else {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .stroke(Color.brandAccentWarm.opacity(0.35), style: StrokeStyle(lineWidth: 2.5, dash: [4, 3]))
                            .frame(width: 48, height: 48)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.brandAccentWarm)
                    }
                    Text(localized("Pronto para testar"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)

            // Button
            testButton(label: localized("Testar"))
        }
    }

    // MARK: - System Medium

    private var mediumBody: some View {
        HStack(spacing: 16) {
            if let summary = entry.summary {
                // Left: Velocímetro / Download
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        LinkaBrandMark(size: 14)
                        Text(localized("Linka"))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.textPrimary)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(Color.borderDefault.opacity(0.4), lineWidth: 4)
                            Circle()
                                .trim(from: 0, to: ringProgress(summary.downloadMbps))
                                .stroke(Color.brandAccentWarm, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Text(formattedMbps(summary.downloadMbps))
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text(localized("Mbps"))
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.textSecondary)
                            }
                            .padding(.horizontal, 4)
                        }
                        .frame(width: 66, height: 66)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("Download"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textSecondary)
                            Text(formattedMbps(summary.downloadMbps))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.textPrimary)
                            Text(relativeLabel(for: summary.measuredAt))
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(.textSecondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Divider sutil
                Rectangle()
                    .fill(Color.borderDefault.opacity(0.35))
                    .frame(width: 1, height: 74)

                // Right: Grid 2 colunas com Upload, Ping e botão Testar
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("Upload"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textSecondary)
                            if let upload = summary.uploadMbps {
                                Text(formattedMbps(upload))
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(.textPrimary)
                            } else {
                                Text("—")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.textSecondary)
                            }
                            Text(localized("Mbps"))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("Ping"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textSecondary)
                            if let ping = summary.latencyMs {
                                Text("\(Int(ping.rounded()))")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(.textPrimary)
                            } else {
                                Text("—")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.textSecondary)
                            }
                            Text(localized("ms"))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    testButton(label: localized("Testar"), compact: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            } else {
                // Empty state systemMedium
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            LinkaBrandMark(size: 14)
                            Text(localized("Linka"))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.textPrimary)
                        }
                        Spacer(minLength: 0)
                        ZStack {
                            Circle()
                                .stroke(Color.brandAccentWarm.opacity(0.35), style: StrokeStyle(lineWidth: 2.5, dash: [4, 3]))
                                .frame(width: 58, height: 58)
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.brandAccentWarm)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: 80)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(localized("Pronto para testar"))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.textPrimary)
                        Text(localized("Testar velocidade e ver o último resultado."))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.textSecondary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        testButton(label: localized("Testar agora"), compact: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Lock Screen & StandBy Accessories

    private var accessoryCircularBody: some View {
        Group {
            if let summary = entry.summary {
                ZStack {
                    AccessoryWidgetBackground()
                    Circle()
                        .stroke(Color.primary.opacity(0.2), lineWidth: 3.5)
                    Circle()
                        .trim(from: 0, to: ringProgress(summary.downloadMbps))
                        .stroke(Color.primary, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(shortMbps(summary.downloadMbps))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(localized("Mbps"))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 2) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(localized("Linka"))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                }
            }
        }
    }

    private var accessoryRectangularBody: some View {
        Group {
            if let summary = entry.summary {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10, weight: .bold))
                            Text(formattedMbps(summary.downloadMbps))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text(localized("Mbps"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text(relativeLabel(for: summary.measuredAt))
                            .font(.system(size: 9, weight: .regular))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 10) {
                        if let upload = summary.uploadMbps {
                            HStack(spacing: 2) {
                                Text("Up:")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text(formattedMbps(upload))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            }
                        }
                        if let ping = summary.latencyMs {
                            HStack(spacing: 2) {
                                Text("Ping:")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("\(Int(ping.rounded()))ms")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        LinkaBrandMark(size: 10)
                        Text(localized("Linka"))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    Text(localized("Pronto para testar"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(localized("Toque para testar"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var accessoryInlineBody: some View {
        Group {
            if let summary = entry.summary {
                Text("Linka • \(formattedMbps(summary.downloadMbps)) Mbps")
            } else {
                Text("Linka • \(localized("Testar"))")
            }
        }
    }

    // MARK: - Action Button

    @ViewBuilder
    private func testButton(label: String, compact: Bool = false) -> some View {
        Button(intent: StartSpeedTestIntent()) {
            HStack(spacing: 5) {
                Image(systemName: "play.fill")
                    .font(.system(size: compact ? 10 : 11, weight: .bold))
                Text(label)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: compact ? nil : .infinity)
            .padding(.horizontal, compact ? 14 : 0)
            .padding(.vertical, compact ? 7 : 8)
            .background(
                Capsule()
                    .fill(Color.brandAccentWarm)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Formatters & Helpers

    private func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: .main, locale: locale)
    }

    private func ringProgress(_ mbps: Double) -> CGFloat {
        let clamped = max(0.06, min(mbps / 500.0, 1.0))
        return CGFloat(clamped)
    }

    private func shortMbps(_ value: Double) -> String {
        if value >= 100 {
            return "\(Int(value.rounded()))"
        } else {
            return value.formatted(.number.precision(.fractionLength(1)).locale(locale))
        }
    }

    private func formattedMbps(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    private func relativeLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return String(
                format: String(localized: "Hoje, %@", defaultValue: "Today, %@", locale: locale),
                locale: locale,
                date.formatted(.dateTime.hour().minute().locale(locale))
            )
        }
        return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).locale(locale))
    }
}

struct LinkaSpeedTestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: LinkaWidgetShared.widgetKind,
            provider: LinkaWidgetTimelineProvider()
        ) { entry in
            LinkaSpeedTestWidgetView(entry: entry)
        }
        .configurationDisplayName("Linka")
        .description("Testar velocidade e ver o último resultado.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}
