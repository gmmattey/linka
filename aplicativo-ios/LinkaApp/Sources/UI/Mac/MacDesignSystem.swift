#if os(macOS)
import SwiftUI

/// Design System do Linka para Mac — índice.
///
/// Princípio: profundidade em vez de linhas. A página (`Color.macPage`) é a
/// camada mais escura; cartões (`linkaMacCard`, `Color.macCard`) são superfícies
/// elevadas com sombra em camadas; poços (`linkaMacWell`, `Color.macWell`) são
/// superfícies rebaixadas para linhas e ações dentro do cartão.
///
/// Fundamentos
/// - Tipografia: `MacType` (corpo 15, rótulo 14, legenda 13, seção 20, título 26, métricas 34–84).
///   Multiplataforma: `LinkaFont` (iPhone/iPad usam os estilos do sistema).
/// - Paleta de dados: `MacPalette` (download, upload, ping, qualidade, rede).
/// - Cor de destaque do app: asset `AccentColor` (roxo). Sem azul do sistema.
///
/// Componentes (`MacVisuals.swift`, `MacComponents.swift`)
/// - `MacMetricTile`, `MacIconBadge`, `MacStatusTag`, `MacBanner`
/// - `MacGauge`, `MacSparkline`, `MacSignalBars`
/// - `MacNetworkCard` + `MacInfoItem` (detalhes reais da rede, via `MacNetworkDetails`)
/// - `MacCardSection` + `MacCardRow` (leitura), `MacSheetScaffold` (janela modal)
/// - `MacInspectorPanel`, `MacInspectorSection`, `MacInspectorRow`, `MacInspectorAction`
///
/// Páginas
/// - `LinkaPage` / `linkaMacForm()` (`MacPageKit.swift`): lista no iPhone e iPad, formulário agrupado no Mac.
/// - `linkaPanelBackground()` / `linkaPageBackground()`: superfícies que mudam por plataforma.
///
/// Telas do Mac: `MacMainView`, `MacHistoryView`, `MacMyNetworkView`, `MacSettingsView`,
/// menus em `MacCommands`. Tokens e cartões de referência: `documentacao/design/design_system`
/// (`tokens/macos.css`, `guidelines/macos-*.card.html`).
enum MacDesignSystem {}
#endif
