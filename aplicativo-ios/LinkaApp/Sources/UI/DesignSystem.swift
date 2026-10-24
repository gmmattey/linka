import SwiftUI
import LinkaWidgetShared

#if canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
private typealias PlatformColor = NSColor
#endif

public extension Color {
    private static func dynamicColor(light: PlatformColor, dark: PlatformColor) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? dark : light
        })
        #elseif canImport(AppKit)
        // Fallback trivial pro macOS nativo (issue #75): sem trait
        // collection de UIKit, usa o provider dinâmico equivalente do
        // AppKit — mesma lógica de claro/escuro, sem nova UX no Mac.
        return Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
        #endif
    }

    private static func hex(_ hexString: String) -> PlatformColor {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        return PlatformColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    // Paleta compartilhada com o LagCheck. Superfícies e tipografia seguem
    // semântica nativa Apple; ação, seleção, gráficos e estados usam estes
    // mesmos tokens para os dois produtos falarem a mesma língua.
    private static let gamerPurpleDeep = hex("#5B21B6")
    private static let gamerPurple = hex("#7C3AED")
    private static let gamerPurpleLight = hex("#A78BFA")
    private static let coralSolar = hex("#FF5A36")
    private static let semanticGood = hex("#22C55E")
    private static let semanticWarning = hex("#F59E0B")
    private static let semanticNeutral = hex("#8A93A0")

    // UI Polish v2 (2026-08-29): surfacePage/surfaceCard/textPrimary/
    // textSecondary/borderDefault deixaram de ser hex custom e passaram a
    // apoiar nas cores dinâmicas nativas do sistema — ganho automático de
    // contraste correto em Light/Dark/Aumentar Contraste e de "parecer
    // nativo" sem redesenhar o UIKit/AppKit inteiro (decisão de produto,
    // análise de UI Polish v2). A identidade Linka permanece só em
    // brandSurface/brandOnSurface/brandAccentWarm/borderStrong. Esses tokens
    // agora espelham a paleta oficial do LagCheck.
    #if canImport(UIKit)
    static let surfacePage = Color(UIColor.systemGroupedBackground)
    static let surfaceCard = Color(UIColor.secondarySystemGroupedBackground)
    static let textPrimary = Color(UIColor.label)
    static let textSecondary = Color(UIColor.secondaryLabel)
    static let borderDefault = Color(UIColor.separator)
    #elseif canImport(AppKit)
    static let surfacePage = Color(NSColor.windowBackgroundColor)
    static let surfaceCard = Color(NSColor.controlBackgroundColor)
    static let textPrimary = Color(NSColor.labelColor)
    static let textSecondary = Color(NSColor.secondaryLabelColor)
    static let borderDefault = Color(NSColor.separatorColor)
    #endif

    static let borderStrong = dynamicColor(light: gamerPurpleDeep, dark: gamerPurpleLight)
    static let brandSurface = Color(gamerPurple)
    static let brandOnSurface = Color.white
    /// Alias histórico: agora é o Roxo Gamer oficial, não um tom quente.
    static let brandAccentWarm = Color(gamerPurple)
    /// Variante de contraste para texto e ícones sobre superfícies claras/escuras.
    static let brandAccentWarmInk = dynamicColor(light: gamerPurpleDeep, dark: gamerPurpleLight)
    /// Séries de medição do histórico, ambas da família Roxo Gamer.
    static let chartDownloadSeries = dynamicColor(light: gamerPurpleDeep, dark: gamerPurpleLight)
    static let chartUploadSeries = Color(gamerPurple)
    static let statusGood = Color(semanticGood)
    static let statusAttention = Color(semanticWarning)
    static let statusCritical = Color(coralSolar)
    static let statusNeutral = Color(semanticNeutral)
    /// Cor de ação primária semântica, compartilhada com o LagCheck.
    static let actionPrimary = brandAccentWarm
}

public extension Font {
    // UI Polish v2 (2026-08-29): `.rounded` fica reservado a números de
    // métrica de verdade (MetricRing, preço do paywall) — `displayTitle`/
    // `displayMedium` são usados como títulos de conteúdo/prosa (ex.:
    // AssistView, UsageDiagnosticsView, PurchaseSheet), onde o design
    // padrão do sistema lê mais como um app nativo, não uma métrica.
    static let displayHuge = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let displayLarge = Font.system(.title, design: .rounded, weight: .bold)
    static let displayTitle = Font.system(.title2, design: .default, weight: .bold)
    static let displayMedium = Font.system(.title3, design: .default, weight: .bold)
    static let buttonLabel = Font.system(.headline, design: .default, weight: .semibold)
    static var metricHero: Font { scaledSystemFont(size: 34, weight: .bold, design: .rounded, relativeTo: .largeTitle) }
    static var metricSecondary: Font { scaledSystemFont(size: 20, weight: .bold, design: .default, relativeTo: .title2) }

    // Revisão da escala tipográfica (2026-08-29): o Linka usava tamanhos
    // pequenos demais como padrão secundário (Subheadline/Footnote/
    // Caption2 — 15/13/11pt) em texto funcional real (ping, jitter, rede,
    // histórico, Ajustes), não só em decoração. Regra adotada:
    //   texto funcional nunca abaixo de 13pt (Footnote);
    //   informação importante nunca abaixo de 15pt (Subheadline);
    //   corpo principal em 17pt (Body).
    // Caption2 (11pt) fica reservado a conteúdo realmente descartável
    // (ex.: versão do app) — a maioria dos usos antigos de `captionSmall`/
    // `captionSmallStrong`/`monoCaption` subiu para Footnote (13pt).
    static let bodyRegular = Font.system(.body, design: .default, weight: .regular)
    static let bodyRegularStrong = Font.system(.body, design: .default, weight: .semibold)
    static let bodySmall = Font.system(.body, design: .default, weight: .regular)
    static let bodySmallStrong = Font.system(.body, design: .default, weight: .semibold)
    static let bodySmallMedium = Font.system(.body, design: .default, weight: .medium)
    static let captionStrong = Font.system(.subheadline, design: .default, weight: .bold)
    static let captionMedium = Font.system(.footnote, design: .default, weight: .medium)
    static let captionSmall = Font.system(.footnote, design: .default, weight: .regular)
    static let captionSmallStrong = Font.system(.footnote, design: .default, weight: .bold)
    static let monoEyebrow = Font.system(.subheadline, design: .monospaced, weight: .regular)
    static let monoCaption = Font.system(.footnote, design: .monospaced, weight: .regular)

    // Hierarquia hero da tela de resultado (issue "Hero do resultado",
    // 2026-08-29): a conclusão do diagnóstico abre a tela, o número de
    // download continua sendo o maior elemento, Upload/Ping ganham mais
    // presença. Tamanhos literais porque a composição pede uma escala
    // própria entre os níveis. `Font.system(size:weight:design:)` sozinho
    // NÃO escala com Dynamic Type — por isso passam por
    // `scaledSystemFont(relativeTo:)`, que ancora o tamanho customizado a
    // um text style de referência via `UIFontMetrics` (mesma técnica que
    // `Font.custom(_:size:relativeTo:)` usa para fontes nomeadas).
    static var heroConclusion: Font { scaledSystemFont(size: 25, weight: .semibold, design: .default, relativeTo: .title) }
    static var heroValueHuge: Font { scaledSystemFont(size: 58, weight: .bold, design: .rounded, relativeTo: .largeTitle) }
    static var heroValueLarge: Font { scaledSystemFont(size: 25, weight: .semibold, design: .rounded, relativeTo: .title) }
    static var heroText17: Font { scaledSystemFont(size: 17, weight: .regular, design: .default, relativeTo: .body) }
    static var heroText17Semibold: Font { scaledSystemFont(size: 17, weight: .semibold, design: .default, relativeTo: .body) }
    static var heroText15: Font { scaledSystemFont(size: 15, weight: .regular, design: .default, relativeTo: .subheadline) }

    /// Tamanho fixo que participa do Dynamic Type de verdade: no iOS/iPadOS
    /// usa `UIFontMetrics(forTextStyle:)` para escalar `size` como se fosse
    /// o `textStyle` de referência. No macOS (AppKit) não há equivalente
    /// público a `UIFontMetrics`, então o tamanho fica fixo — limitação
    /// conhecida, não uma tentativa de contornar a ausência da API.
    private static func scaledSystemFont(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo textStyle: Font.TextStyle) -> Font {
        #if canImport(UIKit)
        let uiWeight: UIFont.Weight
        switch weight {
        case .bold: uiWeight = .bold
        case .semibold: uiWeight = .semibold
        case .medium: uiWeight = .medium
        case .light: uiWeight = .light
        default: uiWeight = .regular
        }

        let uiTextStyle: UIFont.TextStyle
        switch textStyle {
        case .largeTitle: uiTextStyle = .largeTitle
        case .title: uiTextStyle = .title1
        case .title2: uiTextStyle = .title2
        case .title3: uiTextStyle = .title3
        case .headline: uiTextStyle = .headline
        case .callout: uiTextStyle = .callout
        case .subheadline: uiTextStyle = .subheadline
        case .footnote: uiTextStyle = .footnote
        case .caption: uiTextStyle = .caption1
        case .caption2: uiTextStyle = .caption2
        default: uiTextStyle = .body
        }

        var baseFont = UIFont.systemFont(ofSize: size, weight: uiWeight)
        if design == .rounded, let roundedDescriptor = baseFont.fontDescriptor.withDesign(.rounded) {
            baseFont = UIFont(descriptor: roundedDescriptor, size: size)
        }
        let scaledFont = UIFontMetrics(forTextStyle: uiTextStyle).scaledFont(for: baseFont)
        return Font(scaledFont)
        #else
        return Font.system(size: size, weight: weight, design: design)
        #endif
    }
}

public struct LinkaMotion {
    public static let spring = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.35)
    public static let fade = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.25)
    public static let pulse = Animation.spring(response: 0.3, dampingFraction: 0.5)
}

public enum LinkaSpacing {
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 20
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
}

public enum LinkaRadius {
    public static let sm: CGFloat = 10
    public static let md: CGFloat = 14
    public static let lg: CGFloat = 18
}

public struct LinkaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        // Botão de largura livre (linkaAdaptiveContentWidth não trava mais
        // o iPad) — sem isso, em .regular ele ficava muito largo e raso,
        // com o mesmo texto pequeno do iPhone boiando no meio. Sobe um
        // degrau de tipografia (ainda um text style, escalável por Dynamic
        // Type) e de altura em vez de esticar só a largura.
        let isRegular = horizontalSizeClass == .regular
        configuration.label
            .font(isRegular ? .system(.title3, weight: .semibold) : .buttonLabel)
            .foregroundColor(.brandOnSurface)
            .frame(maxWidth: .infinity)
            .frame(minHeight: isRegular ? 64 : 52)
            .padding(.vertical, isRegular ? LinkaSpacing.md : LinkaSpacing.sm)
            .padding(.horizontal, isRegular ? LinkaSpacing.lg : LinkaSpacing.md)
            .background(Color.brandSurface.opacity(isEnabled ? 1 : 0.42), in: RoundedRectangle(cornerRadius: isRegular ? LinkaRadius.lg : LinkaRadius.md, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

public struct LinkaSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let isRegular = horizontalSizeClass == .regular
        configuration.label
            .font(isRegular ? .system(.headline, weight: .semibold) : .bodySmallStrong)
            .foregroundColor(.textPrimary.opacity(isEnabled ? 1 : 0.45))
            .frame(minHeight: isRegular ? 56 : 44)
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

public extension ButtonStyle where Self == LinkaPrimaryButtonStyle {
    static var linkaPrimary: LinkaPrimaryButtonStyle { LinkaPrimaryButtonStyle() }
}

public extension ButtonStyle where Self == LinkaSecondaryButtonStyle {
    static var linkaSecondary: LinkaSecondaryButtonStyle { LinkaSecondaryButtonStyle() }
}

public struct LinkaPlusBadge: View {
    public init() {}

    public var body: some View {
        Text("Plus")
            .font(.captionSmallStrong)
            .foregroundColor(.brandAccentWarm)
            .padding(.horizontal, LinkaSpacing.xs)
            .padding(.vertical, 3)
            .background(Color.brandAccentWarm.opacity(0.12), in: Capsule())
    }
}

public struct LinkaStatusBadge: View {
    let label: String
    let color: Color

    public init(_ label: String, color: Color) {
        self.label = label
        self.color = color
    }

    public var body: some View {
        Text(label)
            .font(.captionSmallStrong)
            .foregroundColor(color)
            .padding(.horizontal, LinkaSpacing.xs)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

public struct LinkaUnavailableState: View {
    let title: String
    let message: String
    let systemImage: String
    let actionTitle: String?
    let action: (() -> Void)?

    public init(
        title: String,
        message: String,
        systemImage: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
            } actions: {
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            VStack(spacing: LinkaSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .foregroundColor(.textSecondary)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .padding(.top, LinkaSpacing.xs)
                }
            }
            .padding(LinkaSpacing.lg)
        }
    }
}

private struct LinkaSheetToolbarModifier: ViewModifier {
    let title: String
    let dismissTitle: String
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(dismissTitle, action: onDismiss)
                }
            }
    }
}

public extension View {
    func linkaSheetToolbar(
        title: String,
        dismissTitle: String = "Fechar",
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(LinkaSheetToolbarModifier(title: title, dismissTitle: dismissTitle, onDismiss: onDismiss))
    }

    func linkaCard(cornerRadius: CGFloat = LinkaRadius.md) -> some View {
        background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Largura da coluna de conteúdo principal do fluxo de medição (idle,
    /// medindo, resultado): 500pt em compact (iPhone); em regular (iPad),
    /// limitado a 680pt por padrão para eliminar o aspecto esticado mantendo
    /// proporção e alinhamento do conteúdo central.
    func linkaAdaptiveContentWidth(regularMaxWidth: CGFloat = 680, compactMaxWidth: CGFloat = 500) -> some View {
        modifier(LinkaAdaptiveContentWidthModifier(regularMaxWidth: regularMaxWidth, compactMaxWidth: compactMaxWidth))
    }
}

public struct LinkaAdaptiveContentWidthModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var regularMaxWidth: CGFloat = 680
    var compactMaxWidth: CGFloat = 500

    public init(regularMaxWidth: CGFloat = 680, compactMaxWidth: CGFloat = 500) {
        self.regularMaxWidth = regularMaxWidth
        self.compactMaxWidth = compactMaxWidth
    }

    public func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content.frame(maxWidth: regularMaxWidth)
        } else {
            content.frame(maxWidth: compactMaxWidth)
        }
    }
}

/// Resolves copy through the language chosen in Linka's Settings. SwiftUI's
/// environment handles `Text` literals, while copy produced by view models and
/// helpers needs this explicit lookup to follow the same preference.
enum LinkaCopy {
    static func value(_ key: String, defaultValue: String? = nil) -> String {
        let preference = UserDefaults.standard.string(forKey: LinkaWidgetShared.languagePreferenceKey) ?? "system"
        return value(key, locale: preference, defaultValue: defaultValue)
    }

    /// Usa a tag BCP-47 que já acompanha uma operação remota ou preferência do app.
    static func value(_ key: String, locale: String?, defaultValue: String? = nil) -> String {
        let rawPreference = locale
            ?? UserDefaults.standard.string(forKey: LinkaWidgetShared.languagePreferenceKey)
            ?? "system"
        
        let effectiveTag = LinkaWidgetShared.effectiveLanguageTag(preference: rawPreference)

        let bundle: Bundle
        if let path = Bundle.main.path(forResource: effectiveTag, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            bundle = localizedBundle
        } else if let path = Bundle.main.path(forResource: "pt-BR", ofType: "lproj"),
                  let fallbackBundle = Bundle(path: path) {
            bundle = fallbackBundle
        } else {
            bundle = .main
        }

        let notFoundSentinel = "__LINKA_NOT_FOUND__"
        let localized = bundle.localizedString(forKey: key, value: notFoundSentinel, table: "Localizable")
        if localized != notFoundSentinel {
            return localized
        }

        // Se falhou no bundle escolhido, tenta o fallback pt-BR explicitamente
        if let path = Bundle.main.path(forResource: "pt-BR", ofType: "lproj"),
           let ptBundle = Bundle(path: path) {
            let ptLocalized = ptBundle.localizedString(forKey: key, value: notFoundSentinel, table: "Localizable")
            if ptLocalized != notFoundSentinel {
                return ptLocalized
            }
        }

        return defaultValue ?? key
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let preference = UserDefaults.standard.string(forKey: LinkaWidgetShared.languagePreferenceKey) ?? "system"
        return String(
            format: value(key),
            locale: LinkaWidgetShared.effectiveLocale(preference: preference),
            arguments: arguments
        )
    }
}
