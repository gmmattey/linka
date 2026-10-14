import SwiftUI
import StoreKit
import AppIntents
import LinkaEntitlements
import LinkaModules
import NetworkDiagnostics
#if canImport(CoreLocation) && os(iOS)
import CoreLocation
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct SettingsView: View {
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider
    @EnvironmentObject private var ads: LinkaAdsCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @State private var purchaseEntryPoint: PurchaseEntryPoint = .settings
    @State private var showPurchase = false
    @State private var showSubscriptionManagement = false
    @State private var showWiFiExplanation = false
    @State private var showAdvancedActions = false
    @State private var showNetworkProfiles = false
    @AppStorage("appAppearance") private var appAppearance = "system"
    @AppStorage(LinkaLanguagePreference.storageKey) private var languagePreference = LinkaLanguagePreference.system.rawValue
    @AppStorage(LinkaWiFiPreferences.identificationEnabledKey) private var networkIdentificationEnabled = true
    @AppStorage(LinkaWiFiPreferences.advancedConfiguredKey) private var advancedWiFiConfigured = false
    @AppStorage(LinkaWiFiPreferences.advancedDiagnosticsEnabledKey) private var advancedWiFiEnabled = true
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

            #if os(iOS)
            Section(LinkaCopy.value("settings.section.network")) {
                Button(action: openNetworkIdentification) {
                    settingsRow(title: LinkaCopy.value("settings.wifiIdentification.title"), value: networkIdentificationStatusText, systemImage: "wifi")
                }
                Button(action: openAdvancedWiFi) {
                    settingsRow(title: LinkaCopy.value("settings.advancedWiFi.title"), value: advancedWiFiStatusText, systemImage: "waveform.path.ecg")
                }
                Button { showNetworkProfiles = true } label: {
                    settingsRow(title: LinkaCopy.value("environments.saved.title"), value: "", systemImage: "mappin.and.ellipse")
                }
                .accessibilityLabel(LinkaCopy.value("environments.saved.title"))
                .accessibilityHint(LinkaCopy.value("environments.settings.accessibilityHint"))
            }

            Section(LinkaCopy.value("settings.section.tools")) {
                NavigationLink(destination: RouterDiscoveryView()) {
                    Label(LinkaCopy.value("settings.routerAccess"), systemImage: "router")
                }
            }
            #endif

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
                    Label(LinkaCopy.value("settings.serviceStatus"), systemImage: "dot.radiowaves.left.and.right")
                }
            }

            #if os(iOS)
            if ads.privacyOptionsRequired {
                Section(LinkaCopy.value("settings.section.privacy")) {
                    Button {
                        Task { await ads.presentPrivacyOptions() }
                    } label: {
                        Label(LinkaCopy.value("settings.adPrivacyOptions"), systemImage: "hand.raised")
                    }
                }
            }
            #endif

            Section(LinkaCopy.value("settings.section.about")) {
                Link(destination: LinkaExternalLinks.about) {
                    Label(LinkaCopy.value("settings.about"), systemImage: "info.circle")
                }
                Link(destination: LinkaExternalLinks.howWeMeasure) {
                    Label(LinkaCopy.value("settings.howWeMeasure"), systemImage: "speedometer")
                }
                Link(destination: LinkaExternalLinks.privacy) {
                    Label(LinkaCopy.value("settings.privacy"), systemImage: "hand.raised")
                }
                Link(destination: LinkaExternalLinks.terms) {
                    Label(LinkaCopy.value("settings.terms"), systemImage: "doc.text")
                }
                Link(destination: LinkaExternalLinks.support) {
                    Label(LinkaCopy.value("settings.support"), systemImage: "questionmark.circle")
                }
                Button {
                    requestReview()
                } label: {
                    Label(LinkaCopy.value("settings.rate"), systemImage: "star")
                }
                Link(destination: LinkaExternalLinks.support) {
                    Label(LinkaCopy.value("settings.feedback"), systemImage: "text.bubble")
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
            } header: {
                Text(LinkaCopy.value("settings.debug.title")).foregroundColor(.brandAccentWarm)
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
        .linkaGradientScreenBackground()
        #endif
        }
        .navigationTitle(LinkaCopy.value("settings.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        #if os(macOS)
        .toolbar {
            if onPurchaseRequest == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LinkaCopy.value("common.close")) { dismiss() }
                }
            }
        }
        #endif
        .sheet(isPresented: $showPurchase) { 
            PurchaseSheet(entryPoint: purchaseEntryPoint) {
                if purchaseEntryPoint == .advancedWiFi {
                    openAdvancedWiFi()
                } else if purchaseEntryPoint == .settings {
                    showSubscriptionManagement = true
                }
            }
        }
        .sheet(isPresented: $showSubscriptionManagement) { SubscriptionManagementSheet() }
        .sheet(isPresented: $showNetworkProfiles) {
            NetworkProfilesManagementView(isPlusActive: LinkaEntitlementPolicy.decision(for: .optimization, snapshot: entitlements.snapshot).isGranted) {
                purchaseEntryPoint = .optimization; showPurchase = true
            }
            #if os(iOS)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .task {
            await entitlements.refreshSnapshot()
            await entitlements.loadProduct()
        }
        .confirmationDialog(LinkaCopy.value("settings.wifiIdentification.title"), isPresented: $showWiFiExplanation, titleVisibility: .visible) {
            switch WiFiNetworkPermission.state(enabled: networkIdentificationEnabled) {
            case .permissionDenied:
                Button(LinkaCopy.value("settings.wifiIdentification.openSystemSettings")) {
                    networkIdentificationEnabled = true
                    WiFiNetworkPermission.openSystemSettings()
                }
            case .active:
                Button(LinkaCopy.value("settings.wifiIdentification.disable"), role: .destructive) {
                    networkIdentificationEnabled = false
                }
            case .disabledByUser, .permissionRequired:
                Button(LinkaCopy.value("settings.wifiIdentification.enable")) {
                    networkIdentificationEnabled = true
                    WiFiNetworkPermission.requestIdentification()
                }
            case .unavailable:
                EmptyView()
            }
            Button(LinkaCopy.value("common.cancel"), role: .cancel) {}
        } message: {
            Text(networkIdentificationMessage)
        }
        .confirmationDialog(LinkaCopy.value("settings.advancedWiFi.title"), isPresented: $showAdvancedActions, titleVisibility: .visible) {
            switch advancedWiFiState {
            case .requiresPlus:
                Button(LinkaCopy.value("settings.advancedWiFi.learnPlus")) {
                    purchaseEntryPoint = .advancedWiFi
                    showPurchase = true
                }
            case .needsConfiguration:
                Button(LinkaCopy.value("settings.advancedWiFi.addShortcut")) {
                    importAdvancedWiFiShortcut()
                    advancedWiFiEnabled = true
                }
            case .active:
                Button(LinkaCopy.value("settings.advancedWiFi.run")) { runAdvancedWiFiShortcut() }
                Button(LinkaCopy.value("settings.advancedWiFi.updateShortcut")) {
                    importAdvancedWiFiShortcut()
                }
                Button(LinkaCopy.value("settings.advancedWiFi.disable"), role: .destructive) { advancedWiFiEnabled = false }
            case .disabled:
                Button(LinkaCopy.value("settings.advancedWiFi.enable")) { advancedWiFiEnabled = true }
                Button(LinkaCopy.value("settings.advancedWiFi.updateShortcut")) {
                    importAdvancedWiFiShortcut()
                }
            }
            Button(LinkaCopy.value("common.cancel"), role: .cancel) {}
        } message: {
            Text(advancedWiFiMessage)
        }
    }

    #if os(macOS)
    private var macOSContent: some View {
        Form {
            Section {
                Button(action: openSubscription) {
                    HStack(spacing: 12) {
                        LinkaPlusWordmarkView(height: 20)
                        Spacer()
                        Text(subscriptionStatusText)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: LinkaCopy.value("settings.mac.plusStatus"), locale: LinkaLanguagePreference.currentLocale, subscriptionStatusText))
            }

            Section(LinkaCopy.value("settings.section.preferences")) {
                Picker(LinkaCopy.value("settings.appearance.title"), selection: $appAppearance) {
                    Text(LinkaCopy.value("settings.appearance.system")).tag("system")
                    Text(LinkaCopy.value("settings.appearance.light")).tag("light")
                    Text(LinkaCopy.value("settings.appearance.dark")).tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section(LinkaCopy.value("settings.section.network")) {
                Toggle(isOn: Binding(
                    get: { advancedWiFiEnabled },
                    set: { enabled in
                        guard macAdvancedWiFiAllowed else {
                            purchaseEntryPoint = .advancedWiFi
                            showPurchase = true
                            return
                        }
                        advancedWiFiEnabled = enabled
                    }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LinkaCopy.value("settings.advancedWiFi.title"))
                        Text(macAdvancedWiFiAllowed ? LinkaCopy.value("settings.mac.advancedWiFi.available") : LinkaCopy.value("settings.mac.advancedWiFi.plus"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.brandAccentWarm)

                NavigationLink(destination: NetworkProfilesManagementView(
                    isPlusActive: LinkaEntitlementPolicy.decision(for: .optimization, snapshot: entitlements.snapshot).isGranted,
                    onRequestPurchase: {
                        purchaseEntryPoint = .optimization
                        showPurchase = true
                    }
                )) {
                    Label(LinkaCopy.value("environments.saved.title"), systemImage: "mappin.and.ellipse")
                }
                .accessibilityHint(LinkaCopy.value("environments.settings.accessibilityHint"))
            }

            Section(LinkaCopy.value("settings.section.tools")) {
                NavigationLink(destination: MacRouterPanelView()) {
                    Label(LinkaCopy.value("settings.routerAccess"), systemImage: "router")
                }
                NavigationLink(destination: ServiceStatusView()) {
                    Label(LinkaCopy.value("settings.serviceStatus"), systemImage: "dot.radiowaves.left.and.right")
                }
            }

            Section(LinkaCopy.value("settings.mac.section.help")) {
                macLinkRow(LinkaCopy.value("settings.howWeMeasure"), systemImage: "speedometer", destination: LinkaExternalLinks.howWeMeasure)
                macLinkRow(LinkaCopy.value("settings.support"), systemImage: "questionmark.circle", destination: LinkaExternalLinks.support)
                macLinkRow(LinkaCopy.value("settings.feedback"), systemImage: "text.bubble", destination: LinkaExternalLinks.support)
                Button { requestReview() } label: {
                    Label(LinkaCopy.value("settings.rate"), systemImage: "star")
                }
            }

            Section(LinkaCopy.value("settings.mac.section.legal")) {
                macLinkRow(LinkaCopy.value("settings.privacy"), systemImage: "hand.raised", destination: LinkaExternalLinks.privacy)
                macLinkRow(LinkaCopy.value("settings.terms"), systemImage: "doc.text", destination: LinkaExternalLinks.terms)
                macLinkRow(LinkaCopy.value("settings.about"), systemImage: "info.circle", destination: LinkaExternalLinks.about)
                Text(LinkaCopy.format("settings.version", appVersion))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func macLinkRow(_ title: String, systemImage: String, destination: URL) -> some View {
        Link(destination: destination) {
            Label(title, systemImage: systemImage)
        }
    }

    private var macAdvancedWiFiAllowed: Bool {
        LinkaEntitlementPolicy.decision(
            for: .advancedWiFiDiagnostics,
            snapshot: entitlements.snapshot
        ).isGranted
    }
    #endif

    private func settingsRow(title: String, value: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundColor(.textPrimary)
            Spacer()
            Text(value)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.textSecondary.opacity(0.6))
        }
    }

    private var appVersion: String {
        LinkaAppVersion.displayString()
    }

    private var subscriptionStatusText: String {
        if LinkaTemporaryFreeOffer.isActive() {
            return LinkaCopy.value("settings.subscription.temporaryFree")
        }
        if entitlements.isRefreshingSnapshot { return LinkaCopy.value("settings.subscription.checking") }
        switch entitlements.snapshot.plan {
        case .free:
            return LinkaCopy.value("settings.subscription.learnPlus")
        case .plus:
            return entitlements.snapshot.status == .active ? LinkaCopy.value("settings.subscription.active") : LinkaCopy.value("settings.subscription.inactive")
        }
    }

    private var advancedWiFiState: LinkaAdvancedWiFiSettingsState {
        let decision = LinkaEntitlementPolicy.decision(for: .advancedWiFiDiagnostics, snapshot: entitlements.snapshot)
        return .state(
            hasEntitlement: decision.isGranted,
            configured: advancedWiFiConfigured,
            enabled: advancedWiFiEnabled
        )
    }

    private var advancedWiFiStatusText: String {
        switch advancedWiFiState {
        case .requiresPlus: return LinkaCopy.value("settings.advancedWiFi.status.requiresPlus")
        case .needsConfiguration: return LinkaCopy.value("settings.advancedWiFi.status.needsConfiguration")
        case .active: return LinkaCopy.value("settings.advancedWiFi.status.active")
        case .disabled: return LinkaCopy.value("settings.advancedWiFi.status.disabled")
        }
    }

    private var networkIdentificationStatusText: String {
        switch WiFiNetworkPermission.state(enabled: networkIdentificationEnabled) {
        case .active: return LinkaCopy.value("wifi.identification.active")
        case .disabledByUser: return LinkaCopy.value("wifi.identification.disabled")
        case .permissionRequired: return LinkaCopy.value("wifi.identification.permissionRequired")
        case .permissionDenied: return LinkaCopy.value("wifi.identification.permissionDenied")
        case .unavailable: return LinkaCopy.value("common.unavailable")
        }
    }

    private var networkIdentificationMessage: String {
        switch WiFiNetworkPermission.state(enabled: networkIdentificationEnabled) {
        case .active:
            return LinkaCopy.value("settings.wifiIdentification.message.active")
        case .disabledByUser, .permissionRequired:
            return LinkaCopy.value("settings.wifiIdentification.message.permissionRequired")
        case .permissionDenied:
            return LinkaCopy.value("settings.wifiIdentification.message.permissionDenied")
        case .unavailable:
            return LinkaCopy.value("settings.wifiIdentification.message.unavailable")
        }
    }

    private var advancedWiFiMessage: String {
        switch advancedWiFiState {
        case .requiresPlus:
            return LinkaCopy.value("settings.advancedWiFi.message.requiresPlus")
        case .needsConfiguration:
            return LinkaCopy.value("settings.advancedWiFi.message.needsConfiguration")
        case .active:
            return LinkaCopy.value("settings.advancedWiFi.message.active")
        case .disabled:
            return LinkaCopy.value("settings.advancedWiFi.message.disabled")
        }
    }

    private func openSubscription() {
        guard !LinkaTemporaryFreeOffer.isActive() else { return }
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

    private func openNetworkIdentification() {
        switch WiFiNetworkPermission.state(enabled: networkIdentificationEnabled) {
        case .active, .disabledByUser, .permissionRequired, .permissionDenied:
            showWiFiExplanation = true
        case .unavailable:
            break
        }
    }

    private func openAdvancedWiFi() {
        let decision = LinkaEntitlementPolicy.decision(for: .advancedWiFiDiagnostics, snapshot: entitlements.snapshot)
        guard decision.isGranted else {
            purchaseEntryPoint = .advancedWiFi; showPurchase = true; return
        }
        if advancedWiFiConfigured && advancedWiFiEnabled {
            showAdvancedActions = true
        } else if advancedWiFiConfigured {
            showAdvancedActions = true
        } else {
            advancedWiFiEnabled = true
            showAdvancedActions = true
        }
    }

    private func runAdvancedWiFiShortcut() {
        openURL(LinkaAdvancedWiFiIntegration.runShortcutURL)
    }

    private func importAdvancedWiFiShortcut() {
        #if canImport(UIKit)
        // O botão vive em um confirmationDialog. Espera o fechamento da
        // folha antes de pedir a troca para o app Atalhos.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            UIApplication.shared.open(LinkaAdvancedWiFiIntegration.importShortcutURL)
        }
        #else
        openURL(LinkaAdvancedWiFiIntegration.importShortcutURL)
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
private struct MacRouterPanelView: View {
    @Environment(\.openURL) private var openURL
    @State private var state: MacRouterPanelState = .idle
    @State private var showOpenConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(LinkaCopy.value("router.mac.title"))
                .font(.title2.weight(.semibold))

            Group {
                switch state {
                case .idle, .locating:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(LinkaCopy.value("router.mac.locating"))
                    }
                    .foregroundColor(.textSecondary)
                case .found(let gateway):
                    VStack(alignment: .leading, spacing: 8) {
                        Label(LinkaCopy.value("router.mac.found"), systemImage: "checkmark.circle.fill")
                            .foregroundColor(.statusGood)
                        Text(gateway.ip)
                            .font(.bodySmallStrong)
                            .foregroundColor(.textPrimary)
                        if gateway.adminURL?.scheme?.lowercased() == "http" {
                            Text(LinkaCopy.value("router.mac.insecure"))
                                .font(.bodySmall)
                                .foregroundColor(.textSecondary)
                        }
                        Button(LinkaCopy.value("router.mac.open")) { showOpenConfirmation = true }
                            .buttonStyle(.linkaPrimary)
                    }
                case .unreachable(let gatewayIP):
                    VStack(alignment: .leading, spacing: 8) {
                        Label(LinkaCopy.value("router.mac.unreachable.title"), systemImage: "exclamationmark.shield")
                            .foregroundColor(.statusAttention)
                        Text(gatewayIP)
                            .font(.bodySmallStrong)
                            .foregroundColor(.textPrimary)
                        Text(LinkaCopy.value("router.mac.unreachable.detail"))
                            .font(.bodySmall)
                            .foregroundColor(.textSecondary)
                        Button(LinkaCopy.value("router.mac.openSystemSettings")) { openSystemLocalNetworkSettings() }
                            .buttonStyle(.linkaSecondary)
                    }
                case .unavailable:
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LinkaCopy.value("router.mac.unavailable.title"))
                            .foregroundColor(.textPrimary)
                        Text(LinkaCopy.value("router.mac.unavailable.detail"))
                            .font(.bodySmall)
                            .foregroundColor(.textSecondary)
                    }
                }
            }

            Spacer()
            Button(state == .locating ? LinkaCopy.value("router.mac.locating.short") : LinkaCopy.value("router.mac.locate")) {
                Task { await locatePanel() }
            }
            .buttonStyle(.linkaSecondary)
            .disabled(state == .locating)
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 300, alignment: .topLeading)
        .navigationTitle(LinkaCopy.value("router.mac.title"))
        .task { await locatePanel() }
        .confirmationDialog(LinkaCopy.value("router.mac.confirmation.title"), isPresented: $showOpenConfirmation, titleVisibility: .visible) {
            if case .found(let gateway) = state, let url = gateway.adminURL {
                Button(LinkaCopy.value("router.mac.confirmation.open")) { openURL(url) }
            }
            Button(LinkaCopy.value("common.cancel"), role: .cancel) {}
        } message: {
            if case .found(let gateway) = state {
                Text(String(format: LinkaCopy.value("router.mac.confirmation.detail"), locale: LinkaLanguagePreference.currentLocale, gateway.ip))
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
