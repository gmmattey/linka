#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NetworkCore
import MeasurementHistory

/// Peças compartilhadas pelas telas do Mac: linha do inspetor, seção, tag de
/// estado, gráfico de linha e formatação das medições.

struct MacInspectorRow: View {
    let label: String
    let value: String
    var systemImage: String? = nil
    var tint: Color = MacPalette.download

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                icon
                Text(label).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                Text(value).monospacedDigit().lineLimit(1)
            }
            HStack(alignment: .top, spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).foregroundStyle(.secondary).font(MacType.label)
                    Text(value).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .font(MacType.body)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var icon: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
                .accessibilityHidden(true)
        }
    }
}

/// Seção do inspetor: título e um poço com as linhas.
struct MacInspectorSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(MacType.captionStrong)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .linkaMacWell(padding: 14, radius: 18)
        }
    }
}

/// Painel de detalhes à direita (inspetor): um cartão flutuante, afastado das
/// bordas da janela, como a barra lateral da esquerda.
struct MacInspectorPanel<Content: View>: View {
    @ViewBuilder let content: Content

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) { content }
            .padding(16)
            .frame(width: 300, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.macCard)
                    .shadow(color: .black.opacity(0.22), radius: 22, x: 0, y: 12)
                    .shadow(color: .black.opacity(0.14), radius: 3, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0)], startPoint: .top, endPoint: .center),
                        lineWidth: 1)
            )
    }

    var body: some View {
        // O cartão tem a altura do conteúdo; só rola se não couber na janela.
        VStack(spacing: 0) {
            ViewThatFits(in: .vertical) {
                card
                ScrollView(showsIndicators: false) { card.padding(.vertical, 2) }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.bottom, 14)
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .frame(width: 320)
    }
}

struct MacStatusTag: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(MacType.captionStrong)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// Linha de ação do inspetor (link ou comando), com destaque na cor de ação.
struct MacInspectorAction: View {
    let title: String
    var role: ButtonRole? = nil
    var shortcut: String? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).font(MacType.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color.statusCritical : Color.brandAccentWarmInk)
        .font(MacType.body)
    }
}

/// Gráfico de linha simples para a velocidade ao vivo.
struct MacSparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [Color.brandAccentWarm.opacity(0.28), Color.brandAccentWarm.opacity(0)],
                        startPoint: .top, endPoint: .bottom))
                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(Color.brandAccentWarm, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let maxValue = values.max(), maxValue > 0 else { return [] }
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step,
                    y: size.height - (CGFloat(value / maxValue) * (size.height - 6)) - 3)
        }
    }
}

enum MacMeasurementFormat {
    static func networkName(_ m: NetworkMeasurement) -> String {
        switch m.connectionKind {
        case .wifi: return m.wifiContext?.ssid ?? "Wi-Fi"
        case .cellular: return LinkaCopy.value("network.cellular")
        case .ethernet: return LinkaCopy.value("network.ethernet")
        default: return LinkaCopy.value("Rede")
        }
    }

    static func mbps(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    static func ms(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(round(value))) ms"
    }

    /// Qualidade geral a partir de ping, jitter e perda — a mesma leitura do app.
    static func quality(_ m: NetworkMeasurement) -> (label: String, color: Color)? {
        guard let ping = m.latencyMs, let jitter = m.jitterMs else { return nil }
        let loss = m.packetLossPercent ?? 0
        if ping <= 30 && jitter <= 5 && loss < 0.5 { return (LinkaCopy.value("Excelente"), .statusGood) }
        if ping <= 60 && jitter <= 15 && loss < 2 { return (LinkaCopy.value("Boa"), .statusGood) }
        if ping <= 120 && loss < 5 { return (LinkaCopy.value("Regular"), .statusAttention) }
        return (LinkaCopy.value("Instável"), .statusCritical)
    }

    static func exportCSV(_ measurements: [NetworkMeasurement]) {
        guard !measurements.isEmpty else { return }
        let data = MeasurementCSVExporter.generateCSVData(from: measurements)
        let panel = NSSavePanel()
        panel.title = LinkaCopy.value("Exportar histórico em CSV")
        panel.nameFieldStringValue = "linka-historico.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = LinkaCopy.value("Não foi possível salvar o arquivo")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
#endif
