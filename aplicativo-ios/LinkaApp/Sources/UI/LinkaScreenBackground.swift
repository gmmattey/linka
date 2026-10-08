import SwiftUI

/// Fundo de tela do Linka inspirado no efeito "Pulse Waves" do LagCheck,
/// adaptado com rigor para o design system do Linka e suporte nativo a
/// Light Mode e Dark Mode (Apple HIG).
public struct LinkaScreenBackground: View {
    public enum Variant: Sendable {
        /// Fundo de tela cheia (para MainView / NavigationStack)
        case fullScreen
        /// Fundo para cards ou áreas de hero (ex.: AssistTeaserCard, MetricRing)
        case heroCard
        /// Variante mínima apenas com gradiente, sem anéis de sinal
        case gradientOnly
    }

    private let variant: Variant
    private let showWaves: Bool
    private let centerUnitPoint: UnitPoint
    private let ringCount: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        variant: Variant = .fullScreen,
        showWaves: Bool = true,
        centerUnitPoint: UnitPoint = UnitPoint(x: 0.5, y: 0.28),
        ringCount: Int = 4
    ) {
        self.variant = variant
        self.showWaves = showWaves
        self.centerUnitPoint = centerUnitPoint
        self.ringCount = ringCount
    }

    public var body: some View {
        ZStack {
            backgroundGradient

            if variant != .gradientOnly {
                signalWaves
                    .opacity(showWaves ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: showWaves)
            }
        }
        .ignoresSafeArea(variant == .fullScreen ? .all : [])
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Gradientes Dinâmicos (Light & Dark)

    @ViewBuilder
    private var backgroundGradient: some View {
        if colorScheme == .dark {
            // Dark Mode: Degradê elegante entre azul petróleo profundo (Linka Midnight Ink)
            // e preto absoluto, garantindo contraste OLED e profundidade cinematográfica.
            LinearGradient(
                stops: [
                    .init(color: Color(red: 12 / 255, green: 20 / 255, blue: 36 / 255), location: 0.0), // Deep Ink
                    .init(color: Color(red: 7 / 255, green: 11 / 255, blue: 20 / 255), location: 0.45),
                    .init(color: Color.black, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            // Light Mode: Suave transição entre o fundo agrupado do iOS e uma tonalidade
            // límpida, mantendo compatibilidade total com cards em secondarySystemGroupedBackground.
            LinearGradient(
                stops: [
                    .init(color: Color.surfacePage.opacity(0.85), location: 0.0),
                    .init(color: Color.surfacePage, location: 0.6),
                    .init(color: Color.surfacePage, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Ondas Concêntricas de Sinal (LagCheck Style)

    private var signalWaves: some View {
        GeometryReader { proxy in
            let center = CGPoint(
                x: proxy.size.width * centerUnitPoint.x,
                y: proxy.size.height * centerUnitPoint.y
            )

            // Base de espaçamento das ondas proporcional à tela ou ao card
            let baseRadius: CGFloat = variant == .heroCard ? 90 : 130
            let stepRadius: CGFloat = variant == .heroCard ? 50 : 80

            ForEach(0..<ringCount, id: \.self) { index in
                let diameter = (baseRadius + CGFloat(index) * stepRadius) * 2

                Circle()
                    .stroke(
                        waveStrokeGradient(index: index),
                        lineWidth: 1.0
                    )
                    .frame(width: diameter, height: diameter)
                    .position(center)
            }
        }
        .clipped()
    }

    private func waveStrokeGradient(index: Int) -> LinearGradient {
        let isDark = colorScheme == .dark

        // Decaimento de opacidade à medida que as ondas se distanciam do centro
        let primaryAlpha: Double = isDark
            ? max(0.02, 0.15 - Double(index) * 0.032)
            : max(0.015, 0.08 - Double(index) * 0.018)

        let secondaryAlpha: Double = isDark
            ? max(0.01, 0.07 - Double(index) * 0.016)
            : max(0.01, 0.04 - Double(index) * 0.01)

        return LinearGradient(
            colors: [
                Color.brandAccentWarm.opacity(primaryAlpha),
                Color.brandSurface.opacity(secondaryAlpha),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension View {
    /// Mantém o mesmo fundo estático do Linka nos destinos secundários sem
    /// introduzir as ondas reservadas ao estado de medição da Home.
    func linkaStaticScreenBackground() -> some View {
        background {
            LinkaScreenBackground(variant: .gradientOnly, showWaves: false)
                .ignoresSafeArea()
        }
    }

    /// List e Form usam um fundo de scroll opaco por padrão. Torná-lo
    /// transparente revela o gradiente sem alterar as células nativas.
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
