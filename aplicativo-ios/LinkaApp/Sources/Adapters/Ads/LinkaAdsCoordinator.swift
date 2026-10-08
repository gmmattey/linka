import Foundation
#if os(iOS)
import UIKit
import GoogleMobileAds
import UserMessagingPlatform
#endif

enum LinkaAdPlacement: Equatable {
    case home
    case history
}

/// Uma única tentativa nativa por sessão, escolhida pelo primeiro placement
/// elegível. Isso impede request duplicado e que o mesmo anúncio apareça em
/// duas telas quando a pessoa navega durante a sessão.
struct LinkaAdSessionGate {
    private(set) var didAttempt = false
    private(set) var placement: LinkaAdPlacement?

    mutating func beginIfEligible(
        placement: LinkaAdPlacement,
        isEnabled: Bool,
        isEligibleForAds: Bool
    ) -> Bool {
        guard isEnabled,
              isEligibleForAds,
              !didAttempt else { return false }
        didAttempt = true
        self.placement = placement
        return true
    }
}

/// Vincula cada fluxo assíncrono de consentimento/anúncio a uma geração. O
/// início de uma medição invalida a geração atual para que uma resposta tardia
/// da UMP nunca possa abrir uma superfície ou carregar publicidade sobre ela.
struct LinkaAdRequestGate {
    private var generation = 0

    mutating func beginRequest() -> Int {
        generation &+= 1
        return generation
    }

    mutating func invalidateForMeasurement() {
        generation &+= 1
    }

    func canContinue(requestGeneration: Int) -> Bool {
        requestGeneration == generation
    }
}

/// Permissão revogável entregue à etapa que pode abrir uma superfície UMP.
/// A implementação consulta esta permissão imediatamente antes de apresentar;
/// assim, uma medição iniciada enquanto a preparação estava suspensa cancela a
/// apresentação, em vez de só impedir o carregamento do anúncio depois dela.
struct LinkaAdPresentationPermit {
    private let canPresent: @MainActor () -> Bool

    init(canPresent: @escaping @MainActor () -> Bool) {
        self.canPresent = canPresent
    }

    @MainActor
    func allowsPresentation() -> Bool {
        canPresent()
    }
}

enum LinkaAdConsentSurface {
    case initialConsent
    case privacyOptions
}

#if os(iOS)
/// Dependências pequenas e observáveis para o único ponto que pode apresentar
/// UMP. Além de manter o SDK fora dos testes, o permit torna a apresentação
/// revogável quando a medição começa no meio do fluxo assíncrono.
struct LinkaAdsCoordinatorDependencies {
    var isEnabled: () -> Bool
    var isApplicationActive: @MainActor () -> Bool
    var updateConsentInformation: @MainActor () async -> Bool
    var presentConsentSurface: @MainActor (LinkaAdConsentSurface, LinkaAdPresentationPermit) async throws -> Void
    var canRequestAds: () -> Bool
    var privacyOptionsRequired: () -> Bool
    var nativeAdLoadWillStart: @MainActor () -> Void
    var adFlowDidFinish: @MainActor () -> Void

    static let live = LinkaAdsCoordinatorDependencies(
        isEnabled: {
            (Bundle.main.object(forInfoDictionaryKey: "LinkaAdsEnabled") as? String) == "YES"
        },
        isApplicationActive: {
            UIApplication.shared.applicationState == .active
        },
        updateConsentInformation: {
            do {
                try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
                return true
            } catch {
                return false
            }
        },
        presentConsentSurface: { surface, permit in
            guard permit.allowsPresentation() else { return }
            switch surface {
            case .initialConsent:
                guard ConsentInformation.shared.consentStatus == .required else { return }
                let form = try await ConsentForm.load()
                guard permit.allowsPresentation() else { return }
                try await form.present(from: nil)
            case .privacyOptions:
                try await ConsentForm.presentPrivacyOptionsForm(from: nil)
            }
        },
        canRequestAds: { ConsentInformation.shared.canRequestAds },
        privacyOptionsRequired: {
            ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        },
        nativeAdLoadWillStart: {},
        adFlowDidFinish: {}
    )
}
#endif

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
    private var sessionGate = LinkaAdSessionGate()
    private var requestGate = LinkaAdRequestGate()
    private var consentLoadTask: Task<Void, Never>?
    private var adsSuppressedForMeasurement = false
    private var consentInformationWasUpdated = false
    private var isEligibleForAds = false
    private var isEntitlementResolved = false
    private var nativeLoaderGeneration: Int?

    private var canLoadAds: Bool {
        dependencies.isEnabled() && isEntitlementResolved && isEligibleForAds
            && !adsSuppressedForMeasurement
    }

    /// Atualizações de compra/restauração revogam publicidade imediatamente.
    func updateEligibility(isEligibleForAds: Bool, isEntitlementResolved: Bool) {
        self.isEligibleForAds = isEligibleForAds
        self.isEntitlementResolved = isEntitlementResolved
        if !canLoadAds { invalidatePendingAds() }
    }

    private func invalidatePendingAds() {
        requestGate.invalidateForMeasurement()
        consentLoadTask?.cancel()
        consentLoadTask = nil
        nativeLoader?.delegate = nil
        nativeLoader = nil
        nativeLoaderGeneration = nil
        nativeAd = nil
    }
    private let dependencies: LinkaAdsCoordinatorDependencies

    init(dependencies: LinkaAdsCoordinatorDependencies = .live) {
        self.dependencies = dependencies
        super.init()
    }

    func prepareHomeAd(
        isEligibleForAds: Bool,
        isEntitlementResolved: Bool
    ) {
        prepareNativeAd(
            for: .home,
            isEligibleForAds: isEligibleForAds,
            isEntitlementResolved: isEntitlementResolved
        )
    }

    func prepareHistoryAd(
        isEligibleForAds: Bool,
        isEntitlementResolved: Bool,
        hasHistory: Bool
    ) {
        guard hasHistory else { return }
        prepareNativeAd(
            for: .history,
            isEligibleForAds: isEligibleForAds,
            isEntitlementResolved: isEntitlementResolved
        )
    }

    private func prepareNativeAd(
        for placement: LinkaAdPlacement,
        isEligibleForAds: Bool,
        isEntitlementResolved: Bool
    ) {
        updateEligibility(isEligibleForAds: isEligibleForAds, isEntitlementResolved: isEntitlementResolved)
        guard canLoadAds, !sessionGate.didAttempt, consentLoadTask == nil else { return }

        let requestGeneration = requestGate.beginRequest()
        consentLoadTask = Task { [weak self] in
            await self?.requestConsentThenLoadNativeAd(
                placement: placement, requestGeneration: requestGeneration
            )
        }
    }

    func measurementDidStart() {
        adsSuppressedForMeasurement = true
        invalidatePendingAds()
    }

    /// Libera superfícies elegíveis e opções de privacidade; não inicia anúncio.
    func measurementDidEnd() {
        adsSuppressedForMeasurement = false
    }

    /// Atualiza o estado que a UMP mantém para o aplicativo inteiro. Nunca
    /// mostra uma tela: o formulário só pode aparecer sob demanda no
    /// Histórico elegível.
    func refreshConsentInformation() async {
        guard dependencies.isEnabled() else {
            consentInformationWasUpdated = false
            privacyOptionsRequired = false
            return
        }

        consentInformationWasUpdated = await dependencies.updateConsentInformation()
        privacyOptionsRequired = dependencies.privacyOptionsRequired()
    }

    private func requestConsentThenLoadNativeAd(placement: LinkaAdPlacement, requestGeneration: Int) async {
        defer {
            if requestGate.canContinue(requestGeneration: requestGeneration) {
                consentLoadTask = nil
            }
            dependencies.adFlowDidFinish()
        }
        guard canLoadAds, requestGate.canContinue(requestGeneration: requestGeneration) else { return }
        guard dependencies.isApplicationActive(), canLoadAds,
              requestGate.canContinue(requestGeneration: requestGeneration) else { return }
        await refreshConsentInformation()
        guard canLoadAds, requestGate.canContinue(requestGeneration: requestGeneration),
              consentInformationWasUpdated else { return }

        do {
            try await dependencies.presentConsentSurface(
                .initialConsent,
                presentationPermit(for: requestGeneration)
            )
        } catch {
            // Falha fechada: sem formulário válido, não solicitamos anúncio.
            return
        }

        privacyOptionsRequired = dependencies.privacyOptionsRequired()
        guard canLoadAds, requestGate.canContinue(requestGeneration: requestGeneration),
              dependencies.canRequestAds() else { return }

        // A configuração vale para todos os requests subsequentes e precisa
        // ser aplicada antes da inicialização do SDK.
        MobileAds.shared.requestConfiguration.setPublisherFirstPartyIDEnabled(false)
        MobileAds.shared.requestConfiguration.publisherPrivacyPersonalizationState = .disabled
        await MobileAds.shared.start()
        guard canLoadAds, requestGate.canContinue(requestGeneration: requestGeneration) else { return }
        let loader = AdLoader(
            adUnitID: LinkaAdsConfiguration.nativeAdUnitID,
            rootViewController: nil,
            adTypes: [.native],
            options: nil
        )
        loader.delegate = self
        nativeLoader = loader // O SDK exige manter o loader durante o request.
        nativeLoaderGeneration = requestGeneration

        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        guard canLoadAds,
              requestGate.canContinue(requestGeneration: requestGeneration),
              sessionGate.beginIfEligible(placement: placement,
                                         isEnabled: dependencies.isEnabled(),
                                         isEligibleForAds: isEligibleForAds) else { return }
        dependencies.nativeAdLoadWillStart()
        loader.load(request)
    }

    func presentPrivacyOptions() async {
        guard !adsSuppressedForMeasurement,
              privacyOptionsRequired else { return }
        invalidatePendingAds()
        let requestGeneration = requestGate.beginRequest()
        do {
            try await dependencies.presentConsentSurface(
                .privacyOptions,
                presentationPermit(for: requestGeneration)
            )
        } catch {
            // A ação não tem fallback: a UMP é a fonte de verdade da escolha.
        }
        guard requestGate.canContinue(requestGeneration: requestGeneration) else { return }
        privacyOptionsRequired = dependencies.privacyOptionsRequired()
    }

    private func presentationPermit(for requestGeneration: Int) -> LinkaAdPresentationPermit {
        LinkaAdPresentationPermit { [weak self] in
            guard let self else { return false }
            return !self.adsSuppressedForMeasurement
                && self.requestGate.canContinue(requestGeneration: requestGeneration)
        }
    }
    #else
    func refreshConsentInformation() async {}
    func prepareHomeAd(isEligibleForAds: Bool, isEntitlementResolved: Bool) {}
    func prepareHistoryAd(isEligibleForAds: Bool, isEntitlementResolved: Bool, hasHistory: Bool) {}
    func measurementDidStart() {}
    func measurementDidEnd() {}
    func updateEligibility(isEligibleForAds: Bool, isEntitlementResolved: Bool) {}
    #endif

    #if os(iOS)
    func nativeAd(for placement: LinkaAdPlacement) -> NativeAd? {
        canLoadAds && sessionGate.placement == placement ? nativeAd : nil
    }
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
            guard let self,
                  self.canLoadAds,
                  self.nativeLoader === adLoader,
                  let generation = self.nativeLoaderGeneration,
                  self.requestGate.canContinue(requestGeneration: generation) else { return }
            self.nativeAd = nativeAd
        }
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        // Não há retry automático nem fallback visual; uma sessão recebe no
        // máximo uma tentativa e continua útil sem publicidade.
    }
}
#endif
