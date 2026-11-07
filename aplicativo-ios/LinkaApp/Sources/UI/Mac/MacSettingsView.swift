#if os(macOS)
import SwiftUI
import AppKit
import LinkaEntitlements
import LinkaModules
import MeasurementHistory

/// Janela de Ajustes do Mac (⌘,). Abas Geral, Wi-Fi, Dados e Sobre, no padrão
/// das Configurações de apps nativos.
struct MacSettingsView: View {
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider

    var body: some View {
        TabView {
            MacSettingsGeneralTab()
                .tabItem { Label(LinkaCopy.value("Geral"), systemImage: "gearshape") }
            MacSettingsWiFiTab()
                .tabItem { Label("Wi-Fi", systemImage: "wifi") }
            MacSettingsDataTab()
                .environmentObject(entitlements)
                .tabItem { Label(LinkaCopy.value("Dados"), systemImage: "square.and.arrow.up") }
            MacSettingsAboutTab()
                .environmentObject(entitlements)
                .tabItem { Label(LinkaCopy.value("Sobre"), systemImage: "info.circle") }
        }
        .frame(width: 560, height: 360)
    }
}

private struct MacSettingsGeneralTab: View {
    @AppStorage("appAppearance") private var appAppearance = "system"
    @AppStorage(LinkaLanguagePreference.storageKey) private var languagePreference = LinkaLanguagePreference.system.rawValue

    var body: some View {
        Form {
            Picker(LinkaCopy.value("Aparência"), selection: $appAppearance) {
                Text(LinkaCopy.value("Sistema")).tag("system")
                Text(LinkaCopy.value("Claro")).tag("light")
                Text(LinkaCopy.value("Escuro")).tag("dark")
            }
            .pickerStyle(.segmented)

            Picker(LinkaCopy.value("settings.language.title"), selection: $languagePreference) {
                ForEach(LinkaLanguagePreference.allCases) { language in
                    Text(language.displayName).tag(language.rawValue)
                }
            }
            Text(LinkaCopy.value("Sistema usa o idioma definido no macOS."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct MacSettingsWiFiTab: View {
    @AppStorage(LinkaWiFiPreferences.identificationEnabledKey) private var identificationEnabled = true
    @State private var state = WiFiNetworkPermission.state(enabled: true)

    var body: some View {
        Form {
            Section {
                Toggle(LinkaCopy.value("Mostrar o nome da rede Wi-Fi"), isOn: $identificationEnabled)
                    .onChange(of: identificationEnabled) { enabled in
                        if enabled { WiFiNetworkPermission.requestIdentification() }
                        refresh()
                    }
                LabeledContent(LinkaCopy.value("Permissão de localização")) {
                    Text(state.statusText).foregroundStyle(.secondary)
                }
                if WiFiNetworkPermission.canOpenSystemSettings {
                    Button(LinkaCopy.value("Abrir Ajustes do Sistema…")) {
                        WiFiNetworkPermission.openSystemSettings()
                    }
                }
            } footer: {
                Text(LinkaCopy.value("O macOS só informa o nome da rede com os Serviços de Localização ligados. O Linka não guarda a sua localização."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: .wiFiAuthorizationDidChange)) { _ in refresh() }
    }

    private func refresh() {
        state = WiFiNetworkPermission.state(enabled: identificationEnabled)
    }
}

private struct MacSettingsDataTab: View {
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider
    @State private var confirmDeleteAll = false

    var body: some View {
        Form {
            Section {
                Button(LinkaCopy.value("Exportar histórico em CSV…")) {
                    MacCommandCenter.shared.exportHistoryRequest = true
                }
                Button(LinkaCopy.value("Excluir histórico…"), role: .destructive) {
                    confirmDeleteAll = true
                }
            } footer: {
                Text(LinkaCopy.value("O histórico fica salvo neste Mac."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert(LinkaCopy.value("Excluir todo o histórico?"), isPresented: $confirmDeleteAll) {
            Button(LinkaCopy.value("common.delete"), role: .destructive) {
                Task { @MainActor in
                    let repo = LinkaMeasurementHistory.makeRepository(entitlements: entitlements)
                    try? await repo.deleteAll()
                    NotificationCenter.default.post(name: .linkaHistoryDidChange, object: nil)
                }
            }
            Button(LinkaCopy.value("common.cancel"), role: .cancel) {}
        } message: {
            Text(LinkaCopy.value("history.delete.message"))
        }
    }
}

private struct MacSettingsAboutTab: View {
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider
    @State private var showPurchase = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                Link(LinkaCopy.value("Como medimos"), destination: LinkaExternalLinks.howWeMeasure)
                Link(LinkaCopy.value("Suporte"), destination: LinkaExternalLinks.support)
                Link(LinkaCopy.value("Privacidade"), destination: LinkaExternalLinks.privacy)
                Link(LinkaCopy.value("Termos de Uso"), destination: LinkaExternalLinks.terms)
                Link(LinkaCopy.value("Sobre o Linka"), destination: LinkaExternalLinks.about)
            }
            if !LinkaDistribution.isDirectDownload {
                Section {
                    Button(LinkaCopy.value("Conhecer o Linka Plus")) { showPurchase = true }
                }
            }
            Section {
                LabeledContent(LinkaCopy.value("Versão")) { Text(version).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showPurchase) {
            PurchaseSheet(entryPoint: .settings)
                .environmentObject(entitlements)
                .frame(minWidth: 620, minHeight: 620)
        }
    }
}

extension Notification.Name {
    /// Disparada quando o histórico muda por fora da tela (ex.: excluir tudo nos Ajustes).
    static let linkaHistoryDidChange = Notification.Name("linka.history.didChange")
}
#endif
