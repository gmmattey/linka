import SwiftUI
import NetworkCore

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// Cartão compartilhável de uma única medição (issue #54).
///
/// Renderiza uma imagem própria do Linka — nunca screenshot bruto — a
/// partir de um `NetworkMeasurement` já produzido pelo `LinkaEngine`
/// (resultado atual) ou já salvo pelo `MeasurementHistory` (item do
/// Histórico). Não recalcula nada: consome só o que já chegou no contrato
/// canônico (AGENTS.md §8 — sem duplicar lógica de medição na UI).
///
/// Fora do cartão por design (AGENTS.md §10): `networkIdentifier`
/// (provedor/SSID cru) e qualquer equivalente a IP/BSSID — não são lidos
/// aqui, nem existe toggle de opt-in nesta entrega.
struct ShareCardView: View {
    let measurement: NetworkMeasurement
    @AppStorage(LinkaLanguagePreference.storageKey) private var languagePreference = LinkaLanguagePreference.system.rawValue

    /// Tamanho fixo em pontos do cartão exportado. Proporção vertical
    /// (retrato) funciona bem tanto anexado a uma mensagem quanto como
    /// imagem de story em qualquer app de destino — o share sheet nativo
    /// decide o resto.
    static let cardSize = CGSize(width: 360, height: 480)

    var body: some View {
        VStack(spacing: 0) {
            Text(copy("share.title", "LINKA SPEEDTEST"))
                .font(.monoEyebrow)
                .foregroundColor(.textSecondary)
                .padding(.top, 40)

            MetricRing(
                connecting: false,
                progress: 1.0,
                value: formattedDownload,
                unit: "Mbps",
                size: 188
            )
            .padding(.top, 24)

            Text(copy("metric.download", "DOWNLOAD"))
                .font(.monoEyebrow)
                .foregroundColor(.textSecondary)
                .padding(.top, 20)
                .padding(.bottom, 10)

            HStack(spacing: 6) {
                statFragment(value: formattedUpload, unit: copy("share.unit.upload", "Mbps upload"))

                if let formattedPing {
                    dot
                    statFragment(value: formattedPing, unit: copy("share.unit.ping", "ms ping"))
                }
            }

            if let connectionLine {
                Text(connectionLine)
                    .font(.bodySmall)
                    .foregroundColor(.textSecondary)
                    .padding(.top, 14)
            }

            Spacer(minLength: 24)

            HStack(alignment: .bottom) {
                // Marca oficial (issue #54) — mesmo asset `wordmark` já
                // usado em `SplashView`, importado sem redesenho
                // (AGENTS.md §7). Pequena de propósito: nunca compete com
                // o resultado (requisito de aceite #6 da issue).
                Image("wordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                Spacer()

                Text(formattedDate)
                    .font(.monoCaption)
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .background(Color.surfaceCard)
    }

    private var dot: some View {
        Text("·")
            .font(.bodySmall)
            .foregroundColor(.textSecondary)
    }

    @ViewBuilder
    private func statFragment(value: String, unit: String) -> some View {
        HStack(spacing: 6) {
            Text(value)
                .font(.metricSecondary)
                .foregroundColor(.textPrimary)
            Text(unit)
                .font(.bodySmall)
                .foregroundColor(.textSecondary)
        }
    }

    private var formattedDownload: String {
        formattedSpeed(measurement.downloadMbps)
    }

    private var formattedUpload: String {
        formattedSpeed(measurement.uploadMbps)
    }

    private func formattedSpeed(_ value: Double?) -> String {
        guard let value else { return "--" }
        return value.formatted(.number.precision(.fractionLength(1)).locale(LinkaLanguagePreference.currentLocale))
    }

    private var formattedPing: String? {
        guard let latencyMs = measurement.latencyMs else { return nil }
        return "\(Int(latencyMs.rounded()))"
    }

    /// Linha discreta de contexto de rede — só tipo de conexão e, quando
    /// aplicável, banda Wi-Fi confirmada pelo sistema (issue #51). Nunca
    /// inclui `networkIdentifier` (provedor/SSID) nem qualquer coisa
    /// equivalente a IP/BSSID (requisito de aceite #4 da issue #54).
    private var connectionLine: String? {
        guard let kind = measurement.connectionKind else { return nil }

        let kindLabel: String
        switch kind {
        case .wifi: kindLabel = copy("network.wifi", "Wi-Fi")
        case .cellular: kindLabel = copy("network.cellular", "Mobile network")
        case .ethernet: kindLabel = "Ethernet"
        case .other: kindLabel = copy("network.other", "Other network")
        }

        guard kind == .wifi, let wifiBandGHz = measurement.wifiBandGHz else {
            return kindLabel
        }

        let fractionLength = wifiBandGHz.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1
        let band = wifiBandGHz.formatted(
            .number
                .precision(.fractionLength(fractionLength))
                .locale(LinkaLanguagePreference.fromStoredValue(languagePreference).locale)
        )
        return "\(kindLabel) · \(band)GHz"
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = LinkaLanguagePreference.fromStoredValue(languagePreference).locale
        return formatter.string(from: measurement.measuredAt)
    }

    private func copy(_ key: String, _ fallback: String) -> String {
        LinkaCopy.value(key, defaultValue: fallback)
    }
}

// MARK: - Renderização sob demanda

/// Rasteriza `ShareCardView` em `Data` PNG pronta pro share sheet nativo
/// (issue #54). Usa `ImageRenderer` (disponível a partir do iOS 16, já o
/// deployment target confirmado do app) em vez de captura de tela — o
/// cartão nunca reflete o que está desenhado na hora, só os dados da
/// medição recebida.
@MainActor
enum ShareCardRenderer {
    /// ~3x o tamanho em pontos do cartão, equivalente a uma tela @3x —
    /// nítido em qualquer app de destino sem gerar um arquivo
    /// desproporcional ao conteúdo.
    private static let exportScale: CGFloat = 3

    static func renderPNGData(for measurement: NetworkMeasurement, colorScheme: ColorScheme) -> Data? {
        #if canImport(UIKit)
        let card = ShareCardView(measurement: measurement)
            .environment(\.colorScheme, colorScheme)

        let renderer = ImageRenderer(content: card)
        renderer.scale = exportScale
        renderer.isOpaque = true

        guard let uiImage = renderer.uiImage else { return nil }
        return uiImage.pngData()
        #elseif canImport(AppKit)
        let card = ShareCardView(measurement: measurement)
            .environment(\.colorScheme, colorScheme)

        let renderer = ImageRenderer(content: card)
        renderer.scale = exportScale
        renderer.isOpaque = true

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
        #else
        return nil
        #endif
    }
}

// MARK: - Gatilho reutilizável (resultado atual + item do Histórico)

#if canImport(UIKit)
/// Gera o cartão sob demanda e apresenta o `UIActivityViewController`
/// nativo (issue #54). Um único lugar para a sequência "renderizar →
/// apresentar", reutilizado tanto pelo resultado atual (`MainView`) quanto
/// por cada item do Histórico (`HistoryRow`) — sem duplicar a lógica em
/// cada superfície.
private struct ShareMeasurementPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let measurement: NetworkMeasurement?
    @Environment(\.colorScheme) private var colorScheme
    @State private var shareImage: UIImage?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { presenting in
                guard presenting else {
                    shareImage = nil
                    return
                }
                guard let measurement,
                      let data = ShareCardRenderer.renderPNGData(for: measurement, colorScheme: colorScheme),
                      let image = UIImage(data: data) else {
                    isPresented = false
                    return
                }
                shareImage = image
            }
            .sheet(isPresented: $isPresented) {
                if let shareImage {
                    ShareSheet(activityItems: [shareImage])
                }
            }
    }
}

extension View {
    /// Liga um `Binding<Bool>` de apresentação ao fluxo completo de
    /// compartilhamento de uma única medição (issue #54): gera o cartão e
    /// abre o share sheet nativo quando `isPresented` vira `true`.
    func shareMeasurementSheet(isPresented: Binding<Bool>, measurement: NetworkMeasurement?) -> some View {
        modifier(ShareMeasurementPresenter(isPresented: isPresented, measurement: measurement))
    }
}
#endif

#if canImport(AppKit)
/// Apresenta o seletor de compartilhamento nativo do macOS a partir do
/// cartão já renderizado. O picker recebe só a imagem, nunca a janela nem
/// metadados de rede do usuário.
private struct MacShareMeasurementPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    let measurement: NetworkMeasurement?
    let colorScheme: ColorScheme

    final class Coordinator {
        var isPresenting = false
        var picker: NSSharingServicePicker?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard isPresented, !context.coordinator.isPresenting else { return }
        context.coordinator.isPresenting = true

        DispatchQueue.main.async {
            defer {
                isPresented = false
                context.coordinator.isPresenting = false
            }
            guard let measurement,
                  let data = ShareCardRenderer.renderPNGData(for: measurement, colorScheme: colorScheme),
                  let image = NSImage(data: data) else {
                return
            }

            let picker = NSSharingServicePicker(items: [image])
            context.coordinator.picker = picker
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }
}

private struct MacShareMeasurementModifier: ViewModifier {
    @Binding var isPresented: Bool
    let measurement: NetworkMeasurement?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background(
            MacShareMeasurementPresenter(
                isPresented: $isPresented,
                measurement: measurement,
                colorScheme: colorScheme
            )
            .frame(width: 1, height: 1)
        )
    }
}

extension View {
    func shareMeasurementSheet(isPresented: Binding<Bool>, measurement: NetworkMeasurement?) -> some View {
        modifier(MacShareMeasurementModifier(isPresented: isPresented, measurement: measurement))
    }
}
#elseif !canImport(UIKit)
extension View {
    /// Sem interface nativa de compartilhamento nesta plataforma.
    func shareMeasurementSheet(isPresented: Binding<Bool>, measurement: NetworkMeasurement?) -> some View {
        self
    }
}
#endif
