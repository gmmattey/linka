import Foundation
#if os(iOS)
import GoogleMobileAds
import UserMessagingPlatform
#endif

/// Garante que o ponto de anúncio não vire uma fonte de tentativas repetidas
/// por mudança de filtro, retorno de sheet ou recomposição de SwiftUI.
struct LinkaHistoryAdSessionGate {
    private(set) var didAttempt = false

    mutating func beginIfEligible(isEnabled: Bool, hasPlus: Bool, hasHistory: Bool) -> Bool {
        guard isEnabled, !hasPlus, hasHistory, !didAttempt else { return false }
        didAttempt = true
        return true
    }
}

/// Coordena publicidade como uma capacidade opcional do app, e não como parte
/// de medição ou do histórico. A configuração é deliberadamente fail-closed:
/// sem flag, consentimento atual ou resposta native, nenhuma requisição/slot
/// chega à interface.
@MainActor
final class LinkaAdsCoordinator: NSObject, ObservableObject {
    #if os(iOS)
    @Published private(set) var nativeAd: NativeAd?
    @Published private(set) var privacyOptionsRequired = false

    private var nativeLoader: AdLoader?
    private var historySessionGate = LinkaHistoryAdSessionGate()
    private var consentInformationWasUpdated = false

    private var isEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "LinkaAdsEnabled") as? String) == "YES"
    }

    func prepareHistoryAd(hasPlus: Bool, hasHistory: Bool) {
        guard historySessionGate.beginIfEligible(
            isEnabled: isEnabled,
            hasPlus: hasPlus,
            hasHistory: hasHistory
        ) else { return }

        Task { [weak self] in
            await self?.requestHistoryConsentThenLoadNativeAd()
        }
    }

    /// Atualiza o estado que a UMP mantém para o aplicativo inteiro. Nunca
    /// mostra uma tela: o formulário só pode aparecer sob demanda no
    /// Histórico elegível.
    func refreshConsentInformation() async {
        guard isEnabled else {
            consentInformationWasUpdated = false
            privacyOptionsRequired = false
            return
        }

        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            consentInformationWasUpdated = true
        } catch {
            consentInformationWasUpdated = false
        }

        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    private func requestHistoryConsentThenLoadNativeAd() async {
        await refreshConsentInformation()
        guard consentInformationWasUpdated else { return }

        do {
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            // Falha fechada: sem formulário válido, não solicitamos anúncio.
            return
        }

        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        guard ConsentInformation.shared.canRequestAds else { return }

        // A configuração vale para todos os requests subsequentes e precisa
        // ser aplicada antes da inicialização do SDK.
        MobileAds.shared.requestConfiguration.setPublisherFirstPartyIDEnabled(false)
        MobileAds.shared.requestConfiguration.publisherPrivacyPersonalizationState = .disabled
        await MobileAds.shared.start()
        let loader = AdLoader(
            adUnitID: LinkaAdsConfiguration.nativeAdUnitID,
            rootViewController: nil,
            adTypes: [.native],
            options: nil
        )
        loader.delegate = self
        nativeLoader = loader // O SDK exige manter o loader durante o request.

        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        loader.load(request)
    }

    func presentPrivacyOptions() async {
        guard privacyOptionsRequired else { return }
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
        } catch {
            // A ação não tem fallback: a UMP é a fonte de verdade da escolha.
        }
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }
    #else
    func refreshConsentInformation() async {}
    func prepareHistoryAd(hasPlus: Bool, hasHistory: Bool) {}
    #endif
}

#if os(iOS)
private enum LinkaAdsConfiguration {
    #if DEBUG
    static let nativeAdUnitID = "ca-app-pub-3940256099942544/3986624511"
    #else
    static let nativeAdUnitID = "ca-app-pub-5542349230926522/9986621449"
    #endif
}

extension LinkaAdsCoordinator: NativeAdLoaderDelegate, AdLoaderDelegate {
    nonisolated func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        Task { @MainActor [weak self] in
            self?.nativeAd = nativeAd
        }
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        // Não há retry automático nem fallback visual; uma sessão recebe no
        // máximo uma tentativa e continua útil sem publicidade.
    }
}
#endif
