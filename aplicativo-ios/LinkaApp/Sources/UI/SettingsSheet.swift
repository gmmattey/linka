import SwiftUI
import StoreKit
import LinkaEntitlements
import LinkaModules
import NetworkDiagnostics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct SettingsView: View {
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider
    @EnvironmentObject private var ads: LinkaAdsCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var purchaseEntryPoint: PurchaseEntryPoint = .settings
    @State private var showPurchase = false
    @State private var showPromotionStatus = false
    @State private var showSubscriptionManagement = false
    @AppStorage("appAppearance") private var appAppearance = "system"
    @AppStorage(LinkaLanguagePreference.storageKey) private var languagePreference = LinkaLanguagePreference.system.rawValue
    private let onPurchaseRequest: ((PurchaseEntryPoint) -> Void)?
    private let onSubscriptionManagementRequest: (() -> Void)?

    init(
        onPurchaseRequest: ((PurchaseEntryPoint) -> Void)? = nil,
        onSubscriptionManagementRequest: (() -> Void)? = nil
    ) {
        self.onPurchaseRequest = onPurchaseRequest
        self.onSubscriptionManagementRequest = onSubscriptionManagementRequest
    }

    var body: some View {
        Group {
        #if os(macOS)
        macOSContent
        #else
        Form {
            Section {
                Button(action: openSubscription) {
                    HStack {
                        LinkaPlusWordmarkView(height: 20)
                        Spacer()
                        Text(subscriptionStatusText)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.textSecondary.opacity(0.6))
                    }
                }
            }

            Section(LinkaCopy.value("settings.section.preferences")) {
                Picker(LinkaCopy.value("settings.appearance.title"), selection: $appAppearance) {
                    Text(LinkaCopy.value("settings.appearance.system")).tag("system")
                    Text(LinkaCopy.value("settings.appearance.light")).tag("light")
                    Text(LinkaCopy.value("settings.appearance.dark")).tag("dark")
                }

                Picker(LinkaCopy.value("settings.language.title"), selection: $languagePreference) {
                    ForEach(LinkaLanguagePreference.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
                .accessibilityHint(LinkaCopy.value("settings.language.hint"))
            }

            Section(LinkaCopy.value("settings.section.serviceStatus")) {
                NavigationLink(destination: ServiceStatusView()) {
                    Label {
                        Text(LinkaCopy.value("settings.serviceStatus"))
                            .foregroundColor(.textPrimary)
                    } icon: {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundColor(.brandAccentWarmInk)
                    }
                }
            }

            #if os(iOS)
            if ads.privacyOptionsRequired {
                Section(LinkaCopy.value("settings.section.privacy")) {
                    Button {
                        Task { await ads.presentPrivacyOptions() }
                    } label: {
                        Label {
                            Text(LinkaCopy.value("settings.adPrivacyOptions"))
                                .foregroundColor(.textPrimary)
                        } icon: {
                            Image(systemName: "hand.raised")
                                .foregroundColor(.brandAccentWarmInk)
                        }
                    }
                }
            }
            #endif

            Section(LinkaCopy.value("settings.section.about")) {
                Link(destination: LinkaExternalLinks.about) {
                    settingsAboutRow(title: LinkaCopy.value("settings.about"), systemImage: "info.circle")
                }
                Link(destination: LinkaExternalLinks.howWeMeasure) {
                    settingsAboutRow(title: LinkaCopy.value("settings.howWeMeasure"), systemImage: "speedometer")
                }
                Link(destination: LinkaExternalLinks.privacy) {
                    settingsAboutRow(title: LinkaCopy.value("settings.privacy"), systemImage: "hand.raised")
                }
                Link(destination: LinkaExternalLinks.terms) {
                    settingsAboutRow(title: LinkaCopy.value("settings.terms"), systemImage: "doc.text")
                }
                Link(destination: LinkaExternalLinks.support) {
                    settingsAboutRow(title: LinkaCopy.value("settings.support"), systemImage: "questionmark.circle")
                }
                Button {
                    requestReview()
                } label: {
                    settingsAboutRow(title: LinkaCopy.value("settings.rate"), systemImage: "star")
                }
                Link(destination: LinkaExternalLinks.support) {
                    settingsAboutRow(title: LinkaCopy.value("settings.feedback"), systemImage: "text.bubble")
                }
            }

            #if DEBUG
            Section {
                Toggle(isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: StoreKitEntitlementProvider.forcePlusKey) },
                    set: { entitlements.setForcePlus($0) }
                )) {
                    Label(LinkaCopy.value("settings.debug.plus"), systemImage: "flask")
                }
                .tint(.brandAccentWarm)

                #if os(iOS)
                Toggle(isOn: Binding(
                    get: { LinkaAnalytics.shared.preference.isOwnerExcluded },
                    set: { excluded in
                        LinkaAnalytics.shared.preference.setOwnerExcluded(excluded)
                        LinkaAnalytics.shared.setCollectionEnabled(LinkaAnalytics.shared.preference.isCollectionEnabled)
                    }
                )) {
                    Label("Excluir telemetria nesta instalação", systemImage: "eye.slash")
                }
                .tint(.brandAccentWarm)
                #endif
            } header: {
                Text(LinkaCopy.value("settings.debug.title")).foregroundColor(.brandAccentWarmInk)
            } footer: {
                Text(LinkaCopy.value("settings.debug.footer"))
            }
            #endif

            Section {
                Text(LinkaCopy.format("settings.version", appVersion))
                    .font(.footnote)
                    .foregroundColor(.textSecondary)
            }
        }
        .tint(.brandAccentWarm)
        .linkaGradientScreenBackground()
        #endif
        }
        .navigationTitle(LinkaCopy.value("settings.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(horizontalSizeClass == .regular ? .inline : .large)
        #endif
        #if os(macOS)
        .toolbar {
            if onPurchaseRequest == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        #endif
        .sheet(isPresented: $showPurchase) { 
            PurchaseSheet(entryPoint: purchaseEntryPoint) {
                if purchaseEntryPoint == .settings {
                    showSubscriptionManagement = true
                }
            }
        }
        .sheet(isPresented: $showPromotionStatus) {
            LinkaPlusPromotionStatusSheet(endDate: promotionEndDate)
        }
        .sheet(isPresented: $showSubscriptionManagement) { SubscriptionManagementSheet() }
        .task {
            await entitlements.refreshSnapshot()
            await entitlements.loadProduct()
        }
    }

    #if os(macOS)
    private var macOSContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Ajustes")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .padding(.bottom, 4)

                macSection {
                    Button(action: openSubscription) {
                        HStack(spacing: 12) {
                            LinkaPlusWordmarkView(height: 20)
                            Spacer()
                            Text(subscriptionStatusText)
                                .font(.bodySmall)
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.trailing)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.textSecondary)
                        }
                        .frame(minHeight: 38)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Linka Plus, \(subscriptionStatusText)")
                }

                macSection(title: LinkaCopy.value("Preferências")) {
                    VStack(spacing: 12) {
                        HStack {
                            Label("Aparência", systemImage: "circle.lefthalf.filled")
                            Spacer()
                            Picker("Aparência", selection: $appAppearance) {
                                Text("Sistema").tag("system")
                                Text("Claro").tag("light")
                                Text("Escuro").tag("dark")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }

                        Divider()

                        HStack {
                            Label(LinkaCopy.value("settings.language.title"), systemImage: "globe")
                            Spacer()
                            Picker(LinkaCopy.value("settings.language.title"), selection: $languagePreference) {
                                ForEach(LinkaLanguagePreference.allCases) { language in
                                    Text(language.displayName).tag(language.rawValue)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)
                        }
                        .accessibilityHint(LinkaCopy.value("settings.language.hint"))
                    }
                }

                macSection(title: LinkaCopy.value("Status de serviços")) {
                    NavigationLink(destination: ServiceStatusView()) {
                        macRow(LinkaCopy.value("Acompanhar serviços"), systemImage: "dot.radiowaves.left.and.right", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }

                macSection(title: LinkaCopy.value("Ajuda")) {
                    VStack(alignment: .leading, spacing: 10) {
                        macLinkRow(LinkaCopy.value("Como medimos"), systemImage: "speedometer", destination: LinkaExternalLinks.howWeMeasure)
                        macLinkRow(LinkaCopy.value("Suporte"), systemImage: "questionmark.circle", destination: LinkaExternalLinks.support)
                        macLinkRow(LinkaCopy.value("Enviar feedback"), systemImage: "text.bubble", destination: LinkaExternalLinks.support)
                        Button { requestReview() } label: {
                            macRow(LinkaCopy.value("Avaliar o Linka"), systemImage: "star", showsChevron: false)
                        }
                        .buttonStyle(.plain)
                    }
                }

                macSection(title: LinkaCopy.value("Sobre e legal")) {
                    VStack(alignment: .leading, spacing: 10) {
                        macLinkRow(LinkaCopy.value("Privacidade"), systemImage: "hand.raised", destination: LinkaExternalLinks.privacy)
                        macLinkRow(LinkaCopy.value("Termos de Uso"), systemImage: "doc.text", destination: LinkaExternalLinks.terms)
                        macLinkRow(LinkaCopy.value("Sobre o Linka"), systemImage: "info.circle", destination: LinkaExternalLinks.about)
                        Text("Versão \(appVersion)")
                            .font(.captionMedium)
                            .foregroundColor(.textSecondary)
                            .padding(.top, 4)
                    }
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color.surfacePage)
    }

    private func macSection<Content: View>(title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundColor(.textSecondary)
                    .tracking(0.6)
            }
            VStack(alignment: .leading, spacing: 12, content: content)
                .padding(16)
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                        .stroke(Color.borderDefault.opacity(0.3), lineWidth: 0.5)
                )
        }
    }

    private func macLinkRow(_ title: String, systemImage: String, destination: URL) -> some View {
        Link(destination: destination) {
            macRow(title, systemImage: systemImage, showsChevron: true)
        }
        .buttonStyle(.plain)
    }

    private func macRow(_ title: String, systemImage: String, showsChevron: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundColor(.brandAccentWarmInk)
                .frame(width: 20, alignment: .center)
            Text(title)
                .foregroundColor(.textPrimary)
            Spacer()
            if showsChevron {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textSecondary.opacity(0.6))
            }
        }
        .frame(minHeight: 34)
        .contentShape(Rectangle())
    }

    #endif

    private func settingsAboutRow(title: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundColor(.brandAccentWarmInk)
                .frame(width: 24, alignment: .center)
            Text(title)
                .foregroundColor(.textPrimary)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textSecondary.opacity(0.6))
        }
    }

    private var appVersion: String {
        LinkaAppVersion.displayString()
    }

    private var subscriptionStatusText: String {
        if LinkaTemporaryFreeOffer.isActive() {
            return LinkaCopy.format("settings.subscription.temporaryFree", promotionEndDate)
        }
        if entitlements.isRefreshingSnapshot { return LinkaCopy.value("settings.subscription.checking") }
        switch entitlements.snapshot.plan {
        case .free:
            return LinkaCopy.value("settings.subscription.learnPlus")
        case .plus:
            return entitlements.snapshot.status == .active ? LinkaCopy.value("settings.subscription.active") : LinkaCopy.value("settings.subscription.inactive")
        }
    }

    private var promotionEndDate: String {
        let formatter = DateFormatter()
        formatter.locale = LinkaLanguagePreference.fromStoredValue(languagePreference).locale
        formatter.timeZone = TimeZone(identifier: "America/Sao_Paulo")
        formatter.setLocalizedDateFormatFromTemplate("dMMMM y")
        return formatter.string(from: LinkaTemporaryFreeOffer.endsAt)
    }

    private func openSubscription() {
        if LinkaTemporaryFreeOffer.isActive() {
            showPromotionStatus = true
            return
        }
        if entitlements.snapshot.plan == .plus, entitlements.snapshot.status == .active {
            if let onSubscriptionManagementRequest {
                onSubscriptionManagementRequest()
            } else {
                showSubscriptionManagement = true
            }
        } else if let onPurchaseRequest {
            onPurchaseRequest(.settings)
        } else {
            purchaseEntryPoint = .settings
            showPurchase = true
        }
    }

}

private struct LinkaPlusPromotionStatusSheet: View {
    @Environment(\.dismiss) private var dismiss
    let endDate: String

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                LinkaPlusWordmarkView(height: 28)

                VStack(alignment: .leading, spacing: 8) {
                    Text(LinkaCopy.value("settings.subscription.promotion.title"))
                        .font(.title2.weight(.bold))
                    Text(LinkaCopy.format("settings.subscription.promotion.message", endDate))
                        .foregroundColor(.textSecondary)
                }

                Spacer(minLength: 0)

                Button(LinkaCopy.value("common.continue")) {
                    dismiss()
                }
                .buttonStyle(.linkaPrimary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle("Linka Plus")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LinkaCopy.value("common.close")) {
                        dismiss()
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }
}

typealias SettingsSheet = SettingsView

#if os(macOS)
private enum MacRouterPanelState: Equatable {
    case idle
    case locating
    case found(GatewayInfo)
    /// O roteador foi identificado na tabela de rotas, mas o painel não respondeu.
    /// A causa mais provável é a permissão de Rede Local negada para o Linka nos
    /// Ajustes do Sistema (macOS não distingue "negado" de "inacessível" na API
    /// pública, então o Linka comunica a causa mais provável em vez de inventar
    /// um estado de permissão que a plataforma não expõe).
    case unreachable(gatewayIP: String)
    case unavailable
}

/// Localiza somente o gateway da rota ativa. A descoberta canônica vive em
/// `NetworkDiagnostics`: não faz inventário Bonjour, não deduz fabricante e
/// não guarda credenciais.
struct MacRouterPanelView: View {
    @Environment(\.openURL) private var openURL
    @State private var state: MacRouterPanelState = .idle
    @State private var showOpenConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Painel do roteador")
                .font(.title2.weight(.semibold))

            Group {
                switch state {
                case .idle, .locating:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Procurando o roteador nesta rede…")
                    }
                    .foregroundColor(.textSecondary)
                case .found(let gateway):
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Painel encontrado", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.statusGood)
                        Text(gateway.ip)
                            .font(.bodySmallStrong)
                            .foregroundColor(.textPrimary)
                        if gateway.adminURL?.scheme?.lowercased() == "http" {
                            Text("Esta página não usa conexão segura.")
                                .font(.bodySmall)
                                .foregroundColor(.textSecondary)
                        }
                        Button("Abrir painel no navegador") { showOpenConfirmation = true }
                            .buttonStyle(.linkaPrimary)
                    }
                case .unreachable(let gatewayIP):
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Roteador encontrado, painel bloqueado", systemImage: "exclamationmark.shield")
                            .foregroundColor(.statusAttention)
                        Text(gatewayIP)
                            .font(.bodySmallStrong)
                            .foregroundColor(.textPrimary)
                        Text("O Linka identificou o roteador desta rede, mas não conseguiu confirmar o painel. O motivo mais comum é a permissão de Rede Local negada para o Linka nos Ajustes do Sistema.")
                            .font(.bodySmall)
                            .foregroundColor(.textSecondary)
                        Button("Abrir Ajustes do Sistema") { openSystemLocalNetworkSettings() }
                            .buttonStyle(.linkaSecondary)
                    }
                case .unavailable:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Não foi possível localizar um painel nesta rede.")
                            .foregroundColor(.textPrimary)
                        Text("O Linka confirma o painel antes de oferecer a abertura.")
                            .font(.bodySmall)
                            .foregroundColor(.textSecondary)
                    }
                }
            }

            Spacer()
            Button(state == .locating ? "Procurando…" : "Localizar painel") {
                Task { await locatePanel() }
            }
            .buttonStyle(.linkaSecondary)
            .disabled(state == .locating)
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 360, alignment: .topLeading)
        .navigationTitle("Painel do roteador")
        .task { await locatePanel() }
        .confirmationDialog("Abrir o painel do roteador?", isPresented: $showOpenConfirmation, titleVisibility: .visible) {
            if case .found(let gateway) = state, let url = gateway.adminURL {
                Button("Abrir no navegador") { openURL(url) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            if case .found(let gateway) = state {
                Text(String(format: LinkaCopy.value("router.panel.confirmation.message"), locale: LinkaLanguagePreference.currentLocale, gateway.ip))
            }
        }
    }

    @MainActor
    private func locatePanel() async {
        state = .locating
        guard let gatewayIP = await ActiveGatewayDiscovery().discoverGateway() else {
            state = .unavailable
            return
        }
        let gateway = await GatewayProber().probe(gatewayIP: gatewayIP)
        if gateway.isAccessible, gateway.adminURL != nil {
            state = .found(gateway)
        } else {
            // O gateway foi identificado (temos o IP real da rota ativa), mas o
            // painel não respondeu: diferente de não termos achado gateway algum.
            state = .unreachable(gatewayIP: gatewayIP)
        }
    }

    private func openSystemLocalNetworkSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") else { return }
        openURL(url)
    }
}
#endif

struct SubscriptionManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider
    @State private var isRestoring = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    #if canImport(UIKit)
                    Button(LinkaCopy.value("settings.subscription.manage"), action: manageSubscription)
                    #else
                    Link(LinkaCopy.value("settings.subscription.manage"), destination: LinkaExternalLinks.subscriptionManagement)
                    #endif
                    Button(isRestoring ? LinkaCopy.value("settings.subscription.restoring") : LinkaCopy.value("settings.subscription.restore"), action: restore)
                        .disabled(isRestoring)
                } footer: {
                    Text(LinkaCopy.value("settings.subscription.footer"))
                }
                if let message { Section { Text(message).foregroundColor(.textSecondary) } }
            }
            .linkaGradientScreenBackground()
            .linkaSheetToolbar(title: LinkaCopy.value("linka.plus")) { dismiss() }
        }
    }

    #if canImport(UIKit)
    private func manageSubscription() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        Task { try? await AppStore.showManageSubscriptions(in: scene) }
    }
    #endif

    private func restore() {
        isRestoring = true; message = nil
        Task {
            do {
                let restored = try await entitlements.restore()
                isRestoring = false
                message = restored ? LinkaCopy.value("settings.subscription.restored") : LinkaCopy.value("settings.subscription.noPurchase")
            } catch {
                isRestoring = false; message = LinkaCopy.value("settings.subscription.restoreError")
            }
        }
    }
}
