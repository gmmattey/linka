import WidgetKit
import SwiftUI

/// Ponto de entrada da extensão de Widget do Linka (issue #55).
///
/// Um único widget por enquanto — ver não-objetivo do `plano.md` da
/// issue #55: "coleção de vários widgets/tamanhos exóticos antes do
/// primeiro ser validado".
@main
struct LinkaWidgetBundle: WidgetBundle {
    var body: some Widget {
        LinkaSpeedTestWidget()
    }
}
