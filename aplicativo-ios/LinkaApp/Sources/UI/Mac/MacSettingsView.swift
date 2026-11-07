#if os(macOS)
import SwiftUI
import AppKit
import LinkaEntitlements
import LinkaModules
import MeasurementHistory

/// Chaves de preferências do Mac.
enum MacSettingsKeys {
    static let confirmDelete = "linka.mac.confirmDelete"
}

/// Abre a janela de Ajustes (⌘,). Aciona o item "Ajustes…" que a cena Settings
/// cria no menu do app, o que funciona em qualquer versão do macOS.
enum MacSettingsOpener {
    @MainActor
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        if let item = settingsMenuItem(), let action = item.action {
            NSApp.sendAction(action, to: item.target, from: item)
            return
        }
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @MainActor
    private static func settingsMenuItem() -> NSMenuItem? {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return nil }
        return appMenu.items.first { $0.keyEquivalent == "," && $0.action != nil }
    }
}

/// Janela de Ajustes do Mac (⌘,): Geral, Wi-Fi e rede, Privacidade, Dados e Sobre.
struct MacSettingsView: View {
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider

    var body: some View {
        TabView {
            MacSettingsGeneralTab()
                .macScreen(MacScreenName.settings("General"))
                .tabItem { Label(LinkaCopy.value("Geral"), systemImage: "gearshape") }
            MacSettingsNetworkTab()
                .macScreen(MacScreenName.settings("Network"))
                .tabItem { Label(LinkaCopy.value("Wi-Fi e rede"), systemImage: "wifi") }
            MacSettingsPrivacyTab()
                .macScreen(MacScreenName.settings("Privacy"))
                .tabItem { Label(LinkaCopy.value("Privacidade"), systemImage: "hand.raised") }
            MacSettingsDataTab()
                .environmentObject(entitlements)
                .macScreen(MacScreenName.settings("Data"))
                .tabItem { Label(LinkaCopy.value("Dados"), systemImage: "internaldrive") }
            MacSettingsAboutTab()
                .environmentObject(entitlements)
                .macScreen(MacScreenName.settings("About"))
                .tabItem { Label(LinkaCopy.value("Sobre"), systemImage: "info.circle") }
        }
        .font(.system(size: 14))
        .frame(width: 640, height: 480)
        .onAppear { MacAnalytics.shared.track(.settingsOpened) }
    }
}

// MARK: - Geral

private struct MacSettingsGeneralTab: View {
    @AppStorage("appAppearance") private var appAppearance = "system"
    @AppStorage(LinkaLanguagePreference.storageKey) private var languagePreference = LinkaLanguagePreference.system.rawValue
    @AppStorage(MacWindowPreferences.inspectorKey) private var inspectorVisible = true
    @AppStorage(MacSettingsKeys.confirmDelete) private var confirmDelete = true
    @AppStorage(LinkaWiFiPreferences.identificationEnabledKey) private var identificationEnabled = true
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section(LinkaCopy.value("settings.appearance.title")) {
                HStack(spacing: 18) {
                    MacAppearanceChoice(title: LinkaCopy.value("settings.appearance.system"), kind: .system, selection: $appAppearance, tag: "system")
                    MacAppearanceChoice(title: LinkaCopy.value("settings.appearance.light"), kind: .light, selection: $appAppearance, tag: "light")
                    MacAppearanceChoice(title: LinkaCopy.value("settings.appearance.dark"), kind: .dark, selection: $appAppearance, tag: "dark")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            Section {
                Picker(LinkaCopy.value("settings.language.title"), selection: $languagePreference) {
                    ForEach(LinkaLanguagePreference.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
            } footer: {
                Text(LinkaCopy.value("Sistema usa o idioma definido no macOS."))
            }

            Section(LinkaCopy.value("Janela")) {
                Toggle(LinkaCopy.value("Mostrar o painel de detalhes"), isOn: $inspectorVisible)
                Toggle(LinkaCopy.value("Pedir confirmação ao excluir medições"), isOn: $confirmDelete)
            }

            Section {
                Button(LinkaCopy.value("Restaurar ajustes padrão…"), role: .destructive) { confirmReset = true }
            }
        }
        .formStyle(.grouped)
        .onChange(of: appAppearance) { value in
            MacAnalytics.shared.track(.settingChanged(setting: "appearance", value: value))
            MacAnalytics.shared.setUserProperty(value, for: "appearance")
        }
        .onChange(of: languagePreference) { value in
            MacAnalytics.shared.track(.settingChanged(setting: "language", value: value))
            MacAnalytics.shared.setUserProperty(value, for: "app_language")
        }
        .onChange(of: confirmDelete) { MacAnalytics.shared.track(.settingChanged(setting: "confirm_delete", value: $0 ? "on" : "off")) }
        .alert(LinkaCopy.value("Restaurar os ajustes padrão?"), isPresented: $confirmReset) {
            Button(LinkaCopy.value("Restaurar"), role: .destructive) {
                appAppearance = "system"
                languagePreference = LinkaLanguagePreference.system.rawValue
                inspectorVisible = true
                confirmDelete = true
                identificationEnabled = true
            }
            Button(LinkaCopy.value("common.cancel"), role: .cancel) {}
        } message: {
            Text(LinkaCopy.value("Aparência, idioma, janela e Wi-Fi voltam ao padrão. Suas medições não são apagadas."))
        }
    }
}

/// Opção de aparência com miniatura da janela no tema correspondente.
private struct MacAppearanceChoice: View {
    enum Kind { case system, light, dark }

    let title: String
    let kind: Kind
    @Binding var selection: String
    let tag: String

    private var isSelected: Bool { selection == tag }

    var body: some View {
        Button { selection = tag } label: {
            VStack(spacing: 8) {
                preview
                    .frame(width: 116, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color.brandAccentWarm : Color.primary.opacity(0.15), lineWidth: isSelected ? 3 : 1)
                    )
                    .shadow(color: .black.opacity(isSelected ? 0.25 : 0.12), radius: isSelected ? 10 : 5, y: 3)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var preview: some View {
        switch kind {
        case .light: miniWindow(dark: false)
        case .dark: miniWindow(dark: true)
        case .system:
            HStack(spacing: 0) {
                miniWindow(dark: false).frame(width: 58).clipped()
                miniWindow(dark: true).frame(width: 58, alignment: .trailing).clipped()
            }
        }
    }

    private func miniWindow(dark: Bool) -> some View {
        let page = dark ? Color(red: 0.08, green: 0.08, blue: 0.10) : Color(red: 0.92, green: 0.92, blue: 0.95)
        let card = dark ? Color(red: 0.17, green: 0.17, blue: 0.20) : Color.white
        return ZStack(alignment: .topLeading) {
            page
            RoundedRectangle(cornerRadius: 4).fill(card).frame(width: 26, height: 60).offset(x: 6, y: 8)
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 3).fill(Color.brandAccentWarm).frame(width: 40, height: 8)
                RoundedRectangle(cornerRadius: 4).fill(card).frame(width: 66, height: 22)
                RoundedRectangle(cornerRadius: 4).fill(card).frame(width: 66, height: 18)
            }
            .offset(x: 38, y: 10)
        }
        .frame(width: 116, height: 76, alignment: .topLeading)
    }
}

// MARK: - Wi-Fi e rede

private struct MacSettingsNetworkTab: View {
    @AppStorage(LinkaWiFiPreferences.identificationEnabledKey) private var identificationEnabled = true
    @State private var state = WiFiNetworkPermission.state(enabled: true)

    var body: some View {
        Form {
            Section {
                Toggle(LinkaCopy.value("Mostrar o nome da rede Wi-Fi"), isOn: $identificationEnabled)
                    .onChange(of: identificationEnabled) { enabled in
                        MacAnalytics.shared.track(.settingChanged(setting: "wifi_name", value: enabled ? "on" : "off"))
                        if enabled { WiFiNetworkPermission.requestIdentification() }
                        refresh()
                    }
                LabeledContent(LinkaCopy.value("Permissão de localização")) {
                    Text(state.statusText).foregroundStyle(.secondary)
                }
                if WiFiNetworkPermission.canOpenSystemSettings {
                    Button(LinkaCopy.value("Abrir Ajustes do Sistema…")) { WiFiNetworkPermission.openSystemSettings() }
                }
            } header: {
                Text("Wi-Fi")
            } footer: {
                Text(LinkaCopy.value("O macOS só informa o nome da rede com os Serviços de Localização ligados. O Linka não guarda a sua localização."))
            }

            Section {
                Button(LinkaCopy.value("Abrir permissão de Rede Local…")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } header: {
                Text(LinkaCopy.value("Rede local"))
            } footer: {
                Text(LinkaCopy.value("O Linka consulta o roteador da rede local para identificar o equipamento e diagnosticar a qualidade da conexão Wi-Fi."))
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

// MARK: - Privacidade

private struct MacSettingsPrivacyTab: View {
    @AppStorage(AnalyticsCollectionPreference.userOptOutDefaultsKey) private var optedOut = false

    var body: some View {
        Form {
            Section {
                Label(LinkaCopy.value("O teste só acontece quando você inicia."), systemImage: "hand.tap")
                Label(LinkaCopy.value("O histórico e o cadastro da sua rede ficam salvos neste Mac."), systemImage: "internaldrive")
                Label(LinkaCopy.value("O Linka não mostra anúncios no Mac."), systemImage: "nosign")
            } header: {
                Text(LinkaCopy.value("Como o Linka trata seus dados"))
            }

            Section {
                Toggle(LinkaCopy.value("Compartilhar dados de uso"), isOn: Binding(
                    get: { !optedOut },
                    set: { shares in
                        if !shares { MacAnalytics.shared.track(.settingChanged(setting: "analytics", value: "off")) }
                        optedOut = !shares
                        LinkaAnalytics.shared.setCollectionEnabled(LinkaAnalytics.shared.preference.isCollectionEnabled)
                        if shares { MacAnalytics.shared.track(.settingChanged(setting: "analytics", value: "on")) }
                    }))
            } footer: {
                Text(LinkaCopy.value("Ajuda a melhorar o Linka com dados anônimos de uso, como telas abertas e se o teste terminou. Nunca inclui o nome da sua rede, endereços, localização ou o que você digita."))
            }

            Section(LinkaCopy.value("Permissões do sistema")) {
                Button(LinkaCopy.value("Serviços de Localização…")) {
                    open("x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
                }
                Button(LinkaCopy.value("Rede Local…")) {
                    open("x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")
                }
            }

            Section {
                Link(LinkaCopy.value("Política de privacidade"), destination: LinkaExternalLinks.privacy)
                Link(LinkaCopy.value("Termos de Uso"), destination: LinkaExternalLinks.terms)
            }
        }
        .formStyle(.grouped)
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Dados

private struct MacSettingsDataTab: View {
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider
    @State private var confirmDeleteAll = false
    @State private var count: Int?

    var body: some View {
        Form {
            Section {
                LabeledContent(LinkaCopy.value("Medições salvas")) {
                    Text(count.map(String.init) ?? "—").monospacedDigit().foregroundStyle(.secondary)
                }
                Button(LinkaCopy.value("Exportar histórico em CSV…")) {
                    MacCommandCenter.shared.exportHistoryRequest = true
                }
                .disabled((count ?? 0) == 0)
            } header: {
                Text(LinkaCopy.value("Histórico"))
            } footer: {
                Text(LinkaCopy.value("O histórico fica salvo neste Mac."))
            }

            Section {
                Button(LinkaCopy.value("Excluir histórico…"), role: .destructive) { confirmDeleteAll = true }
                    .disabled((count ?? 0) == 0)
            } footer: {
                Text(LinkaCopy.value("history.delete.message"))
            }
        }
        .formStyle(.grouped)
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .linkaHistoryDidChange)) { _ in Task { await reload() } }
        .alert(LinkaCopy.value("Excluir todo o histórico?"), isPresented: $confirmDeleteAll) {
            Button(LinkaCopy.value("common.delete"), role: .destructive) {
                Task { @MainActor in
                    let repo = LinkaMeasurementHistory.makeRepository(entitlements: entitlements)
                    try? await repo.deleteAll()
                    MacAnalytics.shared.track(.measurementDeleted(scope: "all"))
                    NotificationCenter.default.post(name: .linkaHistoryDidChange, object: nil)
                }
            }
            Button(LinkaCopy.value("common.cancel"), role: .cancel) {}
        } message: {
            Text(LinkaCopy.value("history.delete.message"))
        }
    }

    private func reload() async {
        let repo = LinkaMeasurementHistory.makeRepository(entitlements: entitlements)
        let total = try? await repo.totalCount()
        await MainActor.run { count = total }
    }
}

// MARK: - Sobre

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
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Linka").font(.system(size: 20, weight: .bold))
                        Text("\(LinkaCopy.value("Versão")) \(version)").foregroundStyle(.secondary)
                        Text(LinkaDistribution.isDirectDownload ? LinkaCopy.value("Download direto do site") : LinkaCopy.value("Versão da App Store"))
                            .font(.system(size: 12)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            Section {
                Link(LinkaCopy.value("Como medimos"), destination: LinkaExternalLinks.howWeMeasure)
                Link(LinkaCopy.value("Suporte"), destination: LinkaExternalLinks.support)
                Link(LinkaCopy.value("Enviar feedback"), destination: LinkaExternalLinks.support)
                Link(LinkaCopy.value("Sobre o Linka"), destination: LinkaExternalLinks.about)
                if !LinkaDistribution.isDirectDownload {
                    Link(LinkaCopy.value("Avaliar o Linka"), destination: LinkaDistribution.appStoreListing)
                }
            }
            if MacFeatures.plusPurchase && !LinkaDistribution.isDirectDownload {
                Section {
                    Button(LinkaCopy.value("Conhecer o Linka Plus")) { showPurchase = true }
                }
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
