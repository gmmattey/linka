import SwiftUI
import NetworkDiagnostics

#if os(iOS)
import UIKit

private enum RouterPanelState: Equatable {
    case idle
    case locating
    case found(GatewayInfo)
    /// O roteador foi identificado na rota ativa, mas o painel não respondeu.
    /// A causa mais provável é a permissão de Rede Local negada para o Linka
    /// em Ajustes (o iOS não distingue "negado" de "inacessível" na API
    /// pública, então o Linka comunica a causa mais provável em vez de
    /// inventar um estado de permissão que a plataforma não expõe).
    case unreachable(gatewayIP: String)
    case unavailable
}

/// Acesso ao roteador, não scanner de rede: há no máximo o gateway da rota
/// ativa, confirmado por HTTP/HTTPS antes de ser oferecido ao usuário.
struct RouterDiscoveryView: View {
    @Environment(\.openURL) private var openURL
    @State private var state: RouterPanelState = .idle
    @State private var showOpenConfirmation = false
    @State private var savedPassword = ""
    @State private var hasSavedPassword = false
    private let service = "com.linka.router"

    var body: some View {
        List {
            Section(LinkaCopy.value("router.panel.title")) {
                switch state {
                case .idle:
                    Text(LinkaCopy.value("router.panel.idle"))
                        .foregroundColor(.secondary)
                case .locating:
                    HStack { ProgressView(); Text(LinkaCopy.value("router.panel.locating")) }
                case .found(let gateway):
                    VStack(alignment: .leading, spacing: 8) {
                        Label(LinkaCopy.value("router.panel.found"), systemImage: "checkmark.circle.fill")
                            .foregroundColor(.statusGood)
                        Text(gateway.ip).font(.footnote).foregroundColor(.secondary)
                        Button(LinkaCopy.value("router.panel.open")) { showOpenConfirmation = true }
                    }
                case .unreachable(let gatewayIP):
                    VStack(alignment: .leading, spacing: 8) {
                        Label(LinkaCopy.value("router.panel.unreachable.title"), systemImage: "exclamationmark.shield")
                            .foregroundColor(.orange)
                        Text(gatewayIP).font(.footnote).foregroundColor(.secondary)
                        Text(LinkaCopy.value("router.panel.unreachable.message"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Button(LinkaCopy.value("router.panel.openSettings")) { openSystemSettings() }
                    }
                case .unavailable:
                    Text(LinkaCopy.value("router.panel.unavailable"))
                        .foregroundColor(.secondary)
                }

                Button(state == .locating ? LinkaCopy.value("router.panel.locating") : LinkaCopy.value("router.panel.locate")) {
                    Task { await locatePanel() }
                }
                .disabled(state == .locating)
            }

            Section(header: Text(LinkaCopy.value("router.password.title")), footer: Text(LinkaCopy.value("router.password.footer"))) {
                SecureField(LinkaCopy.value("router.password.field"), text: $savedPassword)
                Button(LinkaCopy.value("common.savePassword")) {
                    if let data = savedPassword.data(using: .utf8) {
                        KeychainHelper.shared.save(data, service: service, account: "router_admin")
                        hasSavedPassword = true
                    }
                }
                if hasSavedPassword {
                    Button(LinkaCopy.value("router.password.remove"), role: .destructive) {
                        KeychainHelper.shared.delete(service: service, account: "router_admin")
                        savedPassword = ""
                        hasSavedPassword = false
                    }
                }
            }
        }
        .linkaGradientScreenBackground()
        .navigationTitle(LinkaCopy.value("router.title"))
        .onAppear {
            if let data = KeychainHelper.shared.read(service: service, account: "router_admin"),
               let password = String(data: data, encoding: .utf8) {
                savedPassword = password
                hasSavedPassword = true
            }
        }
        .confirmationDialog(LinkaCopy.value("router.panel.confirmation.title"), isPresented: $showOpenConfirmation, titleVisibility: .visible) {
            if case .found(let gateway) = state, let url = gateway.adminURL {
                Button(LinkaCopy.value("router.panel.open")) { openURL(url) }
            }
            Button(LinkaCopy.value("common.cancel"), role: .cancel) {}
        } message: {
            if case .found(let gateway) = state {
                Text(String(format: LinkaCopy.value("router.panel.confirmation.message"), locale: LinkaLanguagePreference.currentLocale, gateway.ip))
            }
        }
    }

    @MainActor
    private func locatePanel() async {
        state = .locating
        guard let ip = await ActiveGatewayDiscovery().discoverGateway() else {
            state = .unavailable
            return
        }
        let gateway = await GatewayProber().probe(gatewayIP: ip)
        if gateway.isAccessible, gateway.adminURL != nil {
            state = .found(gateway)
        } else {
            // O gateway foi identificado (temos o IP real da rota ativa), mas o
            // painel não respondeu: diferente de não termos achado gateway algum.
            state = .unreachable(gatewayIP: ip)
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
#endif
