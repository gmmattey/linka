import SwiftUI
import StoreKit
import LinkaEntitlements

struct PurchaseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider
    let entryPoint: PurchaseEntryPoint
    let onPurchaseCompleted: (() -> Void)?
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var errorMessage: String?
    @State private var hasTrackedOffer = false

    init(entryPoint: PurchaseEntryPoint = .settings, onPurchaseCompleted: (() -> Void)? = nil) {
        self.entryPoint = entryPoint
        self.onPurchaseCompleted = onPurchaseCompleted
    }

    private var plusBenefits: [String] {
        var benefits = [
            copy("purchase.benefit.assist", "Assist explains your result"),
            copy("purchase.benefit.recurring", "Identifies recurring issues"),
            copy("purchase.benefit.history", "Compares your history"),
            copy("purchase.benefit.wifi", "Advanced Wi-Fi diagnostics")
        ]

        switch entryPoint {
        case .assist:
            benefits.removeAll { $0 == copy("purchase.benefit.assist", "Assist explains your result") }
            benefits.insert(copy("purchase.benefit.assist", "Assist explains your result"), at: 0)
        case .historyInsights:
            benefits.removeAll { $0 == copy("purchase.benefit.history", "Compares your history") || $0 == copy("purchase.benefit.recurring", "Identifies recurring issues") }
            benefits.insert(copy("purchase.benefit.recurring", "Identifies recurring issues"), at: 0)
            benefits.insert(copy("purchase.benefit.history", "Compares your history"), at: 1)
        case .advancedWiFi:
            benefits.removeAll { $0 == copy("purchase.benefit.wifi", "Advanced Wi-Fi diagnostics") }
            benefits.insert(copy("purchase.benefit.wifi", "Advanced Wi-Fi diagnostics"), at: 0)
        case .optimization:
            benefits.insert(copy("purchase.benefit.optimization", "Find adjustments that can improve your connection"), at: 0)
        case .shortcut, .appIntent:
            benefits.insert(copy("purchase.benefit.shortcuts", "Siri and Shortcuts automation"), at: 0)
        case .settings:
            break
        }
        
        return benefits
    }

    var body: some View {
        if LinkaDistribution.isDirectDownload {
            DirectDownloadPlusNotice()
        } else {
            #if os(macOS)
            macStoreContent
            #else
            storeContent
            #endif
        }
    }

    #if os(macOS)
    private var macStoreContent: some View {
        MacSheetScaffold(
            title: "Linka Plus",
            subtitle: entryPoint.subtitle,
            systemImage: "sparkles",
            tint: MacPalette.download,
            closeTitle: copy("common.close", "Close"),
            onClose: { dismiss() }
        ) {
            if entryPoint != .settings {
                Text(entryPoint.title).font(MacType.title)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                ForEach(plusBenefits, id: \.self) { benefit in
                    HStack(spacing: 14) {
                        MacIconBadge(systemImage: "checkmark", tint: .statusGood, size: 38)
                        Text(benefit).font(MacType.body).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .linkaMacCard(padding: 16)
                }
            }

            VStack(spacing: 6) {
                switch entitlements.productState {
                case .loaded(let product):
                    Text(product.displayPrice).font(MacType.metric(44))
                    Text(copy("purchase.annual.cancel", "Billed annually · Cancel anytime")).font(MacType.label).foregroundStyle(.secondary)
                case .loading:
                    ProgressView().controlSize(.large).padding(.vertical, 10)
                case .unavailable, .error:
                    Text(copy("purchase.unavailable", "Plan is not available right now")).font(MacType.body).foregroundStyle(.secondary)
                    Button(copy("common.tryAgain", "Try again")) { Task { await entitlements.loadProduct() } }
                        .controlSize(.large)
                }
            }
            .frame(maxWidth: .infinity)
            .linkaMacCard(padding: 24)

            VStack(spacing: 12) {
                if let errorMessage {
                    Text(errorMessage).font(MacType.label).foregroundStyle(Color.statusAttention)
                }
                Button(action: purchase) {
                    if isPurchasing {
                        ProgressView().controlSize(.small)
                    } else {
                        switch entitlements.productState {
                        case .loaded(let product): Text(copy("purchase.subscribe.price", "Subscribe for %@/year", product.displayPrice))
                        case .loading: Text(copy("purchase.loading.price", "Loading price…"))
                        case .unavailable, .error: Text(copy("purchase.subscribe", "Subscribe"))
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.brandAccentWarm)
                .disabled(isPurchasing || isRestoring || !isProductLoaded)

                Button(action: restore) {
                    if isRestoring { ProgressView().controlSize(.small) } else { Text(copy("purchase.restore", "Restore purchase")) }
                }
                .controlSize(.large)
                .disabled(isPurchasing || isRestoring)

                Text(disclaimerText).font(MacType.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack(spacing: 6) {
                    Link(copy("legal.terms", "Terms of Use"), destination: LinkaExternalLinks.terms)
                    Text("·").foregroundStyle(.secondary)
                    Link(copy("legal.privacy", "Privacy"), destination: LinkaExternalLinks.privacy)
                }
                .font(MacType.caption)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            guard !hasTrackedOffer else { return }
            hasTrackedOffer = true
            LinkaAnalytics.shared.track(.plusOfferViewed(entryPoint: entryPoint.analyticsIdentifier))
        }
    }
    #endif

    private var storeContent: some View {
        ZStack {
            LinkaScreenBackground(variant: .gradientOnly, showWaves: false)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(copy("common.close", "Close"), systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .foregroundColor(.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel(copy("common.close", "Close"))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .center, spacing: 0) {
                        LinkaPlusWordmarkView(height: 28)
                            .padding(.top, 16)

                        if entryPoint != .settings {
                            Text(entryPoint.title)
                                .font(.displayTitle)
                                .foregroundColor(.textPrimary)
                                .padding(.top, 16)
                        }

                        Text(entryPoint.subtitle)
                            .font(.bodyRegular)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 6)
                            .padding(.horizontal, 28)

                        // Lista de Benefícios Plus
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(plusBenefits, id: \.self) { benefit in
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.bodyRegularStrong)
                                        .foregroundColor(.brandAccentWarmInk)
                                    Text(benefit)
                                        .font(.bodyRegular)
                                        .foregroundColor(.textPrimary)
                                    Spacer()
                                }
                            }
                        }
                        .padding(.top, 32)
                        .padding(.horizontal, 28)

                        priceState
                            .padding(.top, 28)
                            .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 24)
                }

                VStack(spacing: 0) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.captionMedium)
                            .foregroundColor(.statusAttention)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 10)
                    }

                    Button(action: purchase) {
                        if isPurchasing {
                            ProgressView().tint(Color.brandOnSurface)
                        } else {
                            switch entitlements.productState {
                            case .loaded(let product):
                                Text(copy("purchase.subscribe.price", "Subscribe for %@/year", product.displayPrice))
                            case .loading:
                                Text(copy("purchase.loading.price", "Loading price…"))
                            case .unavailable, .error:
                                Text(copy("purchase.subscribe", "Subscribe"))
                            }
                        }
                    }
                    .buttonStyle(.linkaPrimary)
                    .disabled(isPurchasing || isRestoring || !isProductLoaded)
                    .padding(.horizontal, 24)

                    Button(action: restore) {
                        if isRestoring {
                            ProgressView()
                        } else {
                            Text(copy("purchase.restore", "Restore purchase"))
                        }
                    }
                    .buttonStyle(.linkaSecondary)
                    .disabled(isPurchasing || isRestoring)
                    .padding(.top, 14)

                    Text(disclaimerText)
                        .font(.captionSmall)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                        .padding(.horizontal, 28)

                    HStack(spacing: 4) {
                        Link(copy("legal.terms", "Terms of Use"), destination: LinkaExternalLinks.terms)
                            .underline()
                        Text("·").foregroundColor(.textSecondary)
                        Link(copy("legal.privacy", "Privacy"), destination: LinkaExternalLinks.privacy)
                            .underline()
                    }
                    .font(.captionSmall)
                    .foregroundColor(.brandAccentWarmInk)
                    .padding(.top, 6)
                    .padding(.bottom, 16)
                }
            }
        }
        .onAppear {
            guard !hasTrackedOffer else { return }
            hasTrackedOffer = true
            LinkaAnalytics.shared.track(.plusOfferViewed(entryPoint: entryPoint.analyticsIdentifier))
        }
    }

    @ViewBuilder private var priceState: some View {
        VStack(spacing: 4) {
            switch entitlements.productState {
            case .loaded(let product):
                Text(product.displayPrice)
                    .font(.displayLarge)
                    .foregroundColor(.textPrimary)
                Text(copy("purchase.annual.cancel", "Billed annually · Cancel anytime"))
                    .font(.captionMedium)
                    .foregroundColor(.textSecondary)
            case .loading:
                ProgressView().padding(.vertical, 6)
            case .unavailable:
                Text(copy("purchase.unavailable", "Plan is not available right now"))
                    .font(.bodySmallMedium)
                    .foregroundColor(.textSecondary)
                Button(copy("common.tryAgain", "Try again")) {
                    Task { await entitlements.loadProduct() }
                }
                .font(.bodySmallStrong)
                .foregroundColor(.textPrimary)
            case .error(let message):
                Text(copy("purchase.price.error", "We couldn't load the price right now"))
                    .font(.bodySmallMedium)
                    .foregroundColor(.textSecondary)
                #if DEBUG
                Text(message)
                    .font(.captionSmall)
                    .foregroundColor(.statusAttention)
                #endif
                Button(copy("common.tryAgain", "Try again")) {
                    Task { await entitlements.loadProduct() }
                }
                .font(.bodySmallStrong)
                .foregroundColor(.textPrimary)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private var isProductLoaded: Bool {
        if case .loaded = entitlements.productState { return true }
        return false
    }

    private var disclaimerText: String {
        if case .loaded(let product) = entitlements.productState {
            return copy("purchase.disclaimer.price", "%@ per year, automatically renewed by Apple.", product.displayPrice)
        }
        return copy("purchase.disclaimer", "Annual subscription automatically renewed by Apple.")
    }

    private func purchase() {
        guard !isPurchasing, !isRestoring else { return }
        isPurchasing = true
        errorMessage = nil
        Task {
            do {
                let outcome = try await entitlements.purchase()
                isPurchasing = false
                switch outcome {
                case .purchased:
                    dismiss()
                    onPurchaseCompleted?()
                case .userCancelled:
                    break
                case .pending:
                    errorMessage = copy("purchase.pending", "Your purchase is awaiting approval.")
                }
            } catch {
                isPurchasing = false
                errorMessage = copy("purchase.error", "We couldn't complete your purchase right now. Try again.")
            }
        }
    }

    private func restore() {
        guard !isPurchasing, !isRestoring else { return }
        isRestoring = true
        errorMessage = nil
        Task {
            do {
                let restored = try await entitlements.restore()
                isRestoring = false
                if restored {
                    dismiss()
                    onPurchaseCompleted?()
                } else {
                    errorMessage = copy("purchase.restore.none", "No active purchase was found.")
                }
            } catch {
                isRestoring = false
                errorMessage = copy("purchase.restore.error", "We couldn't restore your purchase right now. Try again.")
            }
        }
    }

    private func copy(_ key: String, _ fallback: String, _ arguments: CVarArg...) -> String {
        let locale = LinkaLanguagePreference.currentLocale
        let bundle = Bundle(path: Bundle.main.path(forResource: locale.identifier, ofType: "lproj") ?? "") ?? .main
        let format = bundle.localizedString(forKey: key, value: fallback, table: nil)
        return arguments.isEmpty ? format : String(format: format, locale: locale, arguments: arguments)
    }
}


/// Aviso exibido no lugar da compra quando o app vem do download direto.
struct DirectDownloadPlusNotice: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        #if os(macOS)
        MacSheetScaffold(
            title: LinkaCopy.value("Linka Plus na App Store"),
            systemImage: "sparkles",
            tint: MacPalette.download,
            closeTitle: LinkaCopy.value("Fechar"),
            onClose: { dismiss() }
        ) {
            MacBanner(
                systemImage: "bag.fill", tint: MacPalette.download,
                title: LinkaCopy.value("Linka Plus na App Store"),
                message: LinkaCopy.value("A assinatura do Linka Plus só funciona na versão do Linka baixada pela App Store. Esta versão do site inclui os recursos gratuitos.")
            )
            Button(LinkaCopy.value("Abrir na App Store")) { openURL(LinkaDistribution.appStoreListing) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.brandAccentWarm)
        }
        .frame(minWidth: 520, minHeight: 320)
        #else
        EmptyView()
        #endif
    }
}
