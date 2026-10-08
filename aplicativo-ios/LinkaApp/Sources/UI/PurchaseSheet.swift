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
                                        .foregroundColor(.brandAccentWarm)
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
                        Text("·").foregroundColor(.textSecondary)
                        Link(copy("legal.privacy", "Privacy"), destination: LinkaExternalLinks.privacy)
                    }
                    .font(.captionSmall)
                    .foregroundColor(.brandSurface)
                    .padding(.top, 6)
                    .padding(.bottom, 16)
                }
            }
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
