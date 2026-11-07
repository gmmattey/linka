#if os(macOS)
import SwiftUI

/// Peças visuais do Linka no Mac: cartões, medidor, indicadores e grade de
/// informações da rede.

extension Color {
    /// Fundo da janela: mais escuro que os cartões, para dar profundidade.
    static let macPage = Color(NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.075, green: 0.075, blue: 0.095, alpha: 1)
            : NSColor(red: 0.925, green: 0.925, blue: 0.948, alpha: 1)
    })
    /// Superfície elevada dos cartões.
    static let macCard = Color(NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.165, green: 0.165, blue: 0.200, alpha: 1)
            : NSColor.white
    })
    /// Superfície rebaixada (poços) dentro de cartões.
    static let macWell = Color(NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.115, green: 0.115, blue: 0.145, alpha: 1)
            : NSColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
    })
}

extension View {
    /// Cartão com profundidade: superfície elevada, brilho na borda superior e
    /// sombras em camadas. Sem linhas de contorno.
    func linkaMacCard(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.macCard)
                    .shadow(color: .black.opacity(0.22), radius: 22, x: 0, y: 12)
                    .shadow(color: .black.opacity(0.14), radius: 3, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.0)],
                                       startPoint: .top, endPoint: .center),
                        lineWidth: 1)
            )
    }

    /// Poço: área rebaixada dentro de um cartão ou do inspetor.
    func linkaMacWell(padding: CGFloat = 12, radius: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(Color.macWell, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Escala tipográfica do Mac. No macOS os estilos do sistema são pequenos
/// (corpo 13 pt, legenda 10 pt); o Linka usa tamanhos maiores para leitura
/// confortável a distância de mesa.
enum MacType {
    static let caption = Font.system(size: 13)
    static let captionStrong = Font.system(size: 13, weight: .semibold)
    static let label = Font.system(size: 14)
    static let labelStrong = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 15)
    static let bodyStrong = Font.system(size: 15, weight: .semibold)
    static let headline = Font.system(size: 16, weight: .semibold)
    static let section = Font.system(size: 20, weight: .bold)
    static let title = Font.system(size: 26, weight: .bold)
    static func metric(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
}

enum MacPalette {
    static let download = Color.brandAccentWarm
    static let upload = Color(red: 0.55, green: 0.40, blue: 0.96)
    static let ping = Color(red: 0.10, green: 0.72, blue: 0.62)
    static let quality = Color(red: 0.96, green: 0.62, blue: 0.10)
    static let network = Color(red: 0.86, green: 0.28, blue: 0.62)
}

/// Ícone dentro de um círculo colorido.
struct MacIconBadge: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.16))
            Image(systemName: systemImage)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct MacMetricTile: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let tint: Color
    var valueSize: CGFloat = 38
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                MacIconBadge(systemImage: systemImage, tint: tint)
                Text(title)
                    .font(MacType.headline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(MacType.metric(valueSize))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(MacType.headline)
                    .foregroundStyle(.secondary)
            }
            if let caption {
                Text(caption)
                    .font(MacType.label)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .linkaMacCard()
        .accessibilityElement(children: .combine)
    }
}

/// Medidor circular de 270°. `progress` vai de 0 a 1.
struct MacGauge<Center: View>: View {
    let progress: Double
    var diameter: CGFloat = 280
    var lineWidth: CGFloat = 22
    @ViewBuilder let center: Center

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * max(clamped, 0.001))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [Color(red: 0.65, green: 0.55, blue: 0.98), Color.brandAccentWarm, Color(red: 0.36, green: 0.13, blue: 0.71)]),
                        center: .center, startAngle: .degrees(0), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
                .shadow(color: Color.brandAccentWarm.opacity(clamped > 0 ? 0.35 : 0), radius: 12)
                .animation(.easeOut(duration: 0.3), value: clamped)
            center
        }
        .frame(width: diameter, height: diameter)
    }

    /// Escala "redonda" para o fim do medidor, a partir da velocidade atual.
    static func scale(for value: Double) -> Double {
        guard value > 0 else { return 100 }
        let magnitude = pow(10, floor(log10(value)))
        for factor in [1.0, 2.0, 5.0, 10.0] where value <= factor * magnitude { return factor * magnitude }
        return 10 * magnitude
    }
}

/// Barras de sinal Wi-Fi a partir do RSSI.
struct MacSignalBars: View {
    let rssi: Int?

    private var level: Int {
        guard let rssi else { return 0 }
        if rssi >= -55 { return 4 }
        if rssi >= -65 { return 3 }
        if rssi >= -75 { return 2 }
        return 1
    }

    private var color: Color {
        switch level {
        case 4, 3: return .statusGood
        case 2: return .statusAttention
        default: return .statusCritical
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(1...4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index <= level ? color : Color.primary.opacity(0.15))
                    .frame(width: 5, height: CGFloat(5 + index * 4))
            }
        }
        .frame(height: 21)
        .accessibilityHidden(true)
    }
}

struct MacInfoItem: View {
    let systemImage: String
    let label: String
    let value: String
    var tint: Color = MacPalette.network

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MacIconBadge(systemImage: systemImage, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(MacType.label).foregroundStyle(.secondary)
                Text(value)
                    .font(MacType.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Grade com os detalhes da rede atual.
struct MacNetworkCard: View {
    let details: MacNetworkDetails
    let fallbackName: String

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 18, alignment: .leading)]

    private func dash(_ value: String?) -> String { value ?? "—" }

    private var bandText: String {
        var parts: [String] = []
        if let band = details.bandGHz { parts.append(String(format: "%g GHz", band)) }
        if let channel = details.channel { parts.append("canal \(channel)") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(LinkaCopy.value("Sua rede agora"))
                    .font(MacType.section)
                Spacer()
                if details.isWiFi {
                    HStack(spacing: 8) {
                        MacSignalBars(rssi: details.rssiDbm)
                        Text(details.rssiDbm.map { "\($0) dBm" } ?? "—")
                            .font(MacType.headline).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                MacInfoItem(systemImage: details.isWiFi ? "wifi" : "cable.connector",
                            label: LinkaCopy.value("Rede"),
                            value: details.ssid ?? (fallbackName.isEmpty ? "—" : fallbackName))
                if details.isWiFi {
                    MacInfoItem(systemImage: "dot.radiowaves.left.and.right", label: LinkaCopy.value("Banda e canal"), value: bandText)
                    MacInfoItem(systemImage: "arrow.left.and.right", label: LinkaCopy.value("Largura do canal"),
                                value: details.channelWidthMHz.map { "\($0) MHz" } ?? "—", tint: MacPalette.upload)
                    MacInfoItem(systemImage: "cpu", label: LinkaCopy.value("Padrão Wi-Fi"), value: dash(details.phyMode), tint: MacPalette.upload)
                    MacInfoItem(systemImage: "lock.shield", label: LinkaCopy.value("Segurança"), value: dash(details.security), tint: MacPalette.ping)
                    MacInfoItem(systemImage: "speedometer", label: LinkaCopy.value("Velocidade do link"),
                                value: details.txRateMbps.map { "\(Int($0)) Mbps" } ?? "—", tint: MacPalette.download)
                    MacInfoItem(systemImage: "waveform", label: LinkaCopy.value("Ruído e SNR"),
                                value: details.noiseDbm.map { noise in
                                    details.snrDb.map { "\(noise) dBm · SNR \($0) dB" } ?? "\(noise) dBm"
                                } ?? "—", tint: MacPalette.quality)
                }
                MacInfoItem(systemImage: "number", label: LinkaCopy.value("IP deste Mac"), value: dash(details.localIPv4), tint: MacPalette.ping)
                MacInfoItem(systemImage: "wifi.router", label: LinkaCopy.value("Roteador (gateway)"), value: dash(details.gatewayIP), tint: MacPalette.download)
                MacInfoItem(systemImage: "server.rack", label: "DNS",
                            value: details.dnsServers.isEmpty ? "—" : details.dnsServers.prefix(2).joined(separator: ", "), tint: MacPalette.upload)
            }
        }
        .linkaMacCard(padding: 22)
    }
}

/// Janela modal padrão do Mac: cabeçalho com ícone, título e "Concluído",
/// conteúdo rolável sobre o fundo da janela e rodapé opcional de ações.
struct MacSheetScaffold<Content: View, Footer: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var tint: Color = MacPalette.download
    var closeTitle: String = LinkaCopy.value("common.done")
    let onClose: () -> Void
    let content: Content
    let footer: Footer

    init(title: String, subtitle: String? = nil, systemImage: String? = nil, tint: Color = MacPalette.download,
         closeTitle: String = LinkaCopy.value("common.done"), onClose: @escaping () -> Void,
         @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title; self.subtitle = subtitle; self.systemImage = systemImage; self.tint = tint
        self.closeTitle = closeTitle; self.onClose = onClose
        self.content = content(); self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let systemImage {
                    MacIconBadge(systemImage: systemImage, tint: tint, size: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(MacType.section)
                    if let subtitle {
                        Text(subtitle).font(MacType.label).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(closeTitle, action: onClose)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
                        .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Rectangle().fill(Color.macCard).shadow(color: .black.opacity(0.18), radius: 10, y: 4))
            .zIndex(1)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) { content }
                    .padding(24)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            footer
        }
        .background(Color.macPage)
    }
}

extension MacSheetScaffold where Footer == EmptyView {
    init(title: String, subtitle: String? = nil, systemImage: String? = nil, tint: Color = MacPalette.download,
         closeTitle: String = LinkaCopy.value("common.done"), onClose: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint, closeTitle: closeTitle,
                  onClose: onClose, content: content, footer: { EmptyView() })
    }
}

/// Faixa de destaque com ícone e mensagem (veredito, aviso, estado).
struct MacBanner: View {
    let systemImage: String
    let tint: Color
    let title: String
    var message: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MacIconBadge(systemImage: systemImage, tint: tint, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(MacType.headline).fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message).font(MacType.label).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Seção com título e conteúdo em cartão, para telas de leitura.
struct MacCardSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).font(MacType.section) }
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .linkaMacCard(padding: 18)
        }
    }
}

/// Linha de rótulo e valor dentro de um cartão, com divisor.
struct MacCardRow: View {
    let label: String
    let value: String
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(MacType.body).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(value).font(MacType.bodyStrong).monospacedDigit().multilineTextAlignment(.trailing)
            }
            .linkaMacWell(padding: 12, radius: 12)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
#endif
