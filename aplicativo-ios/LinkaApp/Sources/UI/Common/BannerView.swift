import SwiftUI
import LinkaEntitlements

/// Ponto de inserção de um anúncio nativo. Não há placeholder: se o
/// consentimento ou o carregamento falhar, a lista mantém apenas conteúdo do
/// usuário.
struct BannerView: View {
    @EnvironmentObject private var ads: LinkaAdsCoordinator
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider
    let placement: LinkaAdPlacement

    var body: some View {
        #if os(iOS)
        if entitlements.isEntitlementResolved,
           LinkaEntitlementPolicy.shouldShowAds(for: entitlements.snapshot),
           let nativeAd = ads.nativeAd(for: placement) {
            NativeAdCard(nativeAd: nativeAd)
                .accessibilityElement(children: .contain)
        }
        #else
        EmptyView()
        #endif
    }
}
