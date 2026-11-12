import SwiftUI

/// Base de páginas do Linka. No iPhone e iPad é a lista de sempre. No Mac é o
/// formulário agrupado nativo, em tamanho de leitura confortável, sobre o fundo
/// da janela. Telas de formulário e de detalhe usam esta base; telas de
/// leitura rica usam os cartões do Design System do Mac.
struct LinkaPage<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        #if os(macOS)
        Form { content }
            .linkaMacForm()
        #else
        List { content }
        #endif
    }
}

extension View {
    /// Aparência de formulário do Mac: agrupado, controles e texto maiores,
    /// fundo da janela. No iPhone e iPad não altera nada.
    @ViewBuilder
    func linkaMacForm() -> some View {
        #if os(macOS)
        self
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.macPage)
            .font(.system(size: 15))
            .controlSize(.large)
        #else
        self
        #endif
    }
}

/// Fontes que respeitam a plataforma: no iPhone e iPad são os estilos do
/// sistema; no Mac usam a escala maior do Design System do Mac.
enum LinkaFont {
    static var title: Font {
        #if os(macOS)
        .system(size: 26, weight: .bold)
        #else
        .title2.bold()
        #endif
    }
    static var section: Font {
        #if os(macOS)
        .system(size: 20, weight: .bold)
        #else
        .title3.bold()
        #endif
    }
    static var headline: Font {
        #if os(macOS)
        .system(size: 16, weight: .semibold)
        #else
        .headline
        #endif
    }
    static var body: Font {
        #if os(macOS)
        .system(size: 15)
        #else
        .body
        #endif
    }
    static var label: Font {
        #if os(macOS)
        .system(size: 14)
        #else
        .subheadline
        #endif
    }
    static var labelStrong: Font {
        #if os(macOS)
        .system(size: 14, weight: .semibold)
        #else
        .subheadline.weight(.semibold)
        #endif
    }
    static var caption: Font {
        #if os(macOS)
        .system(size: 13)
        #else
        .caption
        #endif
    }
}

extension View {
    /// Superfície de painel: no Mac é o cartão com profundidade; no iPhone e iPad,
    /// a superfície de cartão de sempre.
    @ViewBuilder
    func linkaPanelBackground(radius: CGFloat = LinkaRadius.lg) -> some View {
        #if os(macOS)
        self.background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.macCard)
                .shadow(color: .black.opacity(0.22), radius: 22, x: 0, y: 12)
                .shadow(color: .black.opacity(0.14), radius: 3, x: 0, y: 1)
        )
        #else
        self.background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: radius))
        #endif
    }

    /// Fundo de página: janela com profundidade no Mac; fundo de página no iPhone e iPad.
    @ViewBuilder
    func linkaPageBackground() -> some View {
        #if os(macOS)
        self.background(Color.macPage)
        #else
        self.background(Color.surfacePage)
        #endif
    }
}
