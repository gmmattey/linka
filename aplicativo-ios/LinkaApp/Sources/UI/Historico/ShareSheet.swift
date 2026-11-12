import SwiftUI

#if canImport(UIKit)
import UIKit

/// Envelope fino sobre `UIActivityViewController` (issue #54) — o share
/// sheet nativo do sistema. Não conhece o cartão nem a medição, só
/// apresenta os itens recebidos; nenhuma integração dedicada a um app
/// específico (WhatsApp, iMessage etc.) — fora de escopo da issue.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
