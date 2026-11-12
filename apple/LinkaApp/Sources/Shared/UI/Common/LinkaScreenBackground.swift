import SwiftUI

/// Fundo canônico das telas do Linka.
///
/// A superfície vem diretamente do sistema para respeitar Light/Dark Mode,
/// contraste e a linguagem visual nativa do iPhone, iPad e Mac. Os parâmetros
/// de variante continuam por compatibilidade com os destinos existentes, mas
/// não introduzem tratamento gráfico no fundo.
public struct LinkaScreenBackground: View {
    public enum Variant: Sendable {
        /// Fundo de tela cheia (para MainView / NavigationStack)
        case fullScreen
        /// Fundo para cards ou áreas de hero (ex.: AssistTeaserCard, MetricRing)
        case heroCard
        /// Variante mínima para destinos secundários
        case gradientOnly
    }

    private let variant: Variant
    public init(
        variant: Variant = .fullScreen,
        showWaves: Bool = true,
        centerUnitPoint: UnitPoint = UnitPoint(x: 0.5, y: 0.28),
        ringCount: Int = 4
    ) {
        self.variant = variant
        _ = showWaves
        _ = centerUnitPoint
        _ = ringCount
    }

    public var body: some View {
        Color.surfacePage
            .ignoresSafeArea(variant == .fullScreen ? .all : [])
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Aplica a superfície nativa nas telas secundárias.
    func linkaStaticScreenBackground() -> some View {
        background {
            LinkaScreenBackground(variant: .gradientOnly, showWaves: false)
                .ignoresSafeArea()
        }
    }

    /// List e Form usam um fundo de scroll opaco por padrão. Torná-lo
    /// transparente revela a superfície semântica sem alterar as células nativas.
    func linkaGradientScreenBackground() -> some View {
        scrollContentBackground(.hidden)
            .linkaStaticScreenBackground()
    }
}

// MARK: - Previews

#Preview("LinkaScreenBackground — Dark") {
    ZStack {
        LinkaScreenBackground()

        VStack(spacing: 20) {
            Circle()
                .stroke(Color.brandAccentWarm, lineWidth: 8)
                .frame(width: 140, height: 140)
                .overlay(
                    Text("350")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                )
                .padding(.top, 90)

            Text("Mbps Download")
                .font(.subheadline)
                .foregroundColor(.gray)

            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("LinkaScreenBackground — Light") {
    ZStack {
        LinkaScreenBackground()

        VStack(spacing: 20) {
            Circle()
                .stroke(Color.brandAccentWarm, lineWidth: 8)
                .frame(width: 140, height: 140)
                .overlay(
                    Text("350")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                )
                .padding(.top, 90)

            Text("Mbps Download")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
    .preferredColorScheme(.light)
}
