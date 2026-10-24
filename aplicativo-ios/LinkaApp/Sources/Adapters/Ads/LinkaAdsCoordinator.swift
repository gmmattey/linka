import Foundation
#if os(iOS)
import UIKit
import GoogleMobileAds
import UserMessagingPlatform
#endif

enum LinkaAdPlacement: Hashable {
    case home
    case history(Int)
    case result(Int)
    case myNetwork
    case router(Int)
    case services
}

struct LinkaAdSessionGate {
    private(set) var attemptedPlacements: Set<LinkaAdPlacement> = []
    private(set) var placement: LinkaAdPlacement?
    var didAttempt: Bool { !attemptedPlacements.isEmpty }

    mutating func beginIfEligible(placement: LinkaAdPlacement, isEnabled: Bool, isEligibleForAds: Bool) -> Bool {
        guard isEnabled, isEligibleForAds, !attemptedPlacements.contains(placement) else { return false }
        attemptedPlacements.insert(placement)
        self.placement = placement
        return true
    }
}

struct LinkaAdRequestGate {
    private var generation = 0
    mutating func beginRequest() -> Int { generation &+= 1; return generation }
    mutating func invalidateForMeasurement() { generation &+= 1 }
    func canContinue(requestGeneration: Int) -> Bool { requestGeneration == generation }
}

struct LinkaAdPresentationPermit {
    private let canPresent: @MainActor () -> Bool
    init(canPresent: @escaping @MainActor () -> Bool) { self.canPresent = canPresent }
    @MainActor func allowsPresentation() -> Bool { canPresent() }
}

enum LinkaAdConsentSurface { case initialConsent, privacyOptions }

#if os(iOS)
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
        isEnabled: { (Bundle.main.object(forInfoDictionaryKey: "LinkaAdsEnabled") as? String) == "YES" },
        isApplicationActive: { UIApplication.shared.applicationState == .active },
        updateConsentInformation: {
            do { try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()); return true }
            catch { return false }
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
        privacyOptionsRequired: { ConsentInformation.shared.privacyOptionsRequirementStatus == .required },
        nativeAdLoadWillStart: {}, adFlowDidFinish: {}
    )
}
#endif

/// Coordena slots nativos de forma opcional. Sem consentimento ou no-fill,
/// a tela segue apenas com conteúdo do Linka.
@MainActor
final class LinkaAdsCoordinator: NSObject, ObservableObject {
    #if os(iOS)
    @Published private(set) var nativeAds: [LinkaAdPlacement: NativeAd] = [:]
    @Published private(set) var privacyOptionsRequired = false
    private let dependencies: LinkaAdsCoordinatorDependencies
    private var nativeLoaders: [ObjectIdentifier: AdLoader] = [:]
    private var loaderContexts: [ObjectIdentifier: (placement: LinkaAdPlacement, generation: Int)] = [:]
    private var sessionGate = LinkaAdSessionGate()
    private var requestGate = LinkaAdRequestGate()
    private var preparationTask: Task<Void, Never>?
    private var pendingPlacements: Set<LinkaAdPlacement> = []
    private var adsSuppressedForMeasurement = false
    private var consentInformationWasUpdated = false
    private var isEligibleForAds = false
    private var isEntitlementResolved = false
    private var adsSDKReady = false
    /// A alteração em Opções de privacidade não reinicia o SDK, mas invalida
    /// a permissão anterior para novos requests.
    private var needsConsentRefresh = true
    private var selectedResultPlacement: LinkaAdPlacement?
    private var resultIndex = 0

    private var canLoadAds: Bool {
        dependencies.isEnabled() && isEntitlementResolved && isEligibleForAds && !adsSuppressedForMeasurement
    }

    init(dependencies: LinkaAdsCoordinatorDependencies = .live) {
        self.dependencies = dependencies
        super.init()
    }

    func updateEligibility(isEligibleForAds: Bool, isEntitlementResolved: Bool) {
        self.isEligibleForAds = isEligibleForAds
        self.isEntitlementResolved = isEntitlementResolved
        if !canLoadAds { invalidatePendingAds() }
    }

    func prepareHomeAd(isEligibleForAds: Bool, isEntitlementResolved: Bool) {
        prepareNativeAds([.home], isEligibleForAds: isEligibleForAds, isEntitlementResolved: isEntitlementResolved)
    }

    func prepareHistoryAds(slotCount: Int, isEligibleForAds: Bool, isEntitlementResolved: Bool) {
        guard slotCount > 0 else { return }
        prepareNativeAds((0..<slotCount).map(LinkaAdPlacement.history), isEligibleForAds: isEligibleForAds, isEntitlementResolved: isEntitlementResolved)
    }

    func prepareResultAd(isEligibleForAds: Bool, isEntitlementResolved: Bool) {
        if selectedResultPlacement == nil {
            selectedResultPlacement = .result(resultIndex)
            resultIndex += 1
        }
        if let selectedResultPlacement {
            prepareNativeAds([selectedResultPlacement], isEligibleForAds: isEligibleForAds, isEntitlementResolved: isEntitlementResolved)
        }
    }

    func currentResultPlacement() -> LinkaAdPlacement { selectedResultPlacement ?? .result(resultIndex) }

    func prepareMyNetworkAd(isEligibleForAds: Bool, isEntitlementResolved: Bool) {
        prepareNativeAds([.myNetwork], isEligibleForAds: isEligibleForAds, isEntitlementResolved: isEntitlementResolved)
    }

    func prepareRouterAd(index: Int, isEligibleForAds: Bool, isEntitlementResolved: Bool) {
        prepareNativeAds([.router(index)], isEligibleForAds: isEligibleForAds, isEntitlementResolved: isEntitlementResolved)
    }

    func prepareServicesAd(isEligibleForAds: Bool, isEntitlementResolved: Bool) {
        prepareNativeAds([.services], isEligibleForAds: isEligibleForAds, isEntitlementResolved: isEntitlementResolved)
    }

    func measurementDidStart() {
        adsSuppressedForMeasurement = true
        selectedResultPlacement = nil
        invalidatePendingAds()
        sessionGate = LinkaAdSessionGate()
    }

    func measurementDidEnd() { adsSuppressedForMeasurement = false }

    func refreshConsentInformation() async {
        guard dependencies.isEnabled() else { consentInformationWasUpdated = false; privacyOptionsRequired = false; return }
        consentInformationWasUpdated = await dependencies.updateConsentInformation()
        privacyOptionsRequired = dependencies.privacyOptionsRequired()
    }

    func presentPrivacyOptions() async {
        guard !adsSuppressedForMeasurement, privacyOptionsRequired else { return }
        invalidatePendingAds()
        needsConsentRefresh = true
        let generation = requestGate.beginRequest()
        do { try await dependencies.presentConsentSurface(.privacyOptions, presentationPermit(for: generation)) } catch {}
        guard requestGate.canContinue(requestGeneration: generation) else { return }
        privacyOptionsRequired = dependencies.privacyOptionsRequired()
    }

    func nativeAd(for placement: LinkaAdPlacement) -> NativeAd? { canLoadAds ? nativeAds[placement] : nil }

    private func prepareNativeAds(_ placements: [LinkaAdPlacement], isEligibleForAds: Bool, isEntitlementResolved: Bool) {
        updateEligibility(isEligibleForAds: isEligibleForAds, isEntitlementResolved: isEntitlementResolved)
        guard canLoadAds else { return }
        let loadingPlacements = Set(loaderContexts.values.map(\.placement))
        pendingPlacements.formUnion(placements.filter {
            nativeAds[$0] == nil && !loadingPlacements.contains($0)
        })
        guard !pendingPlacements.isEmpty, preparationTask == nil else { return }
        // Um novo slot não pode invalidar callbacks de loaders que já estão
        // em voo. A geração só muda quando a medição/entitlement cancela tudo.
        let generation = loaderContexts.values.first?.generation ?? requestGate.beginRequest()
        preparationTask = Task { [weak self] in await self?.prepareConsentAndLoadAds(requestGeneration: generation) }
    }

    private func prepareConsentAndLoadAds(requestGeneration: Int) async {
        defer {
            if requestGate.canContinue(requestGeneration: requestGeneration) { preparationTask = nil }
            dependencies.adFlowDidFinish()
        }
        guard canLoadAds, requestGate.canContinue(requestGeneration: requestGeneration), dependencies.isApplicationActive() else { return }
        if needsConsentRefresh {
            await refreshConsentInformation()
            guard canLoadAds, requestGate.canContinue(requestGeneration: requestGeneration), consentInformationWasUpdated else { return }
            do { try await dependencies.presentConsentSurface(.initialConsent, presentationPermit(for: requestGeneration)) } catch { return }
            privacyOptionsRequired = dependencies.privacyOptionsRequired()
            guard canLoadAds, requestGate.canContinue(requestGeneration: requestGeneration), dependencies.canRequestAds() else { return }
            needsConsentRefresh = false
        }
        if !adsSDKReady {
            MobileAds.shared.requestConfiguration.setPublisherFirstPartyIDEnabled(false)
            MobileAds.shared.requestConfiguration.publisherPrivacyPersonalizationState = .disabled
            await MobileAds.shared.start()
            adsSDKReady = true
        }
        guard canLoadAds, requestGate.canContinue(requestGeneration: requestGeneration) else { return }
        let placements = pendingPlacements
        pendingPlacements.removeAll()
        for placement in placements { loadNativeAd(for: placement, generation: requestGeneration) }
    }

    private func loadNativeAd(for placement: LinkaAdPlacement, generation: Int) {
        guard canLoadAds,
              requestGate.canContinue(requestGeneration: generation),
              sessionGate.beginIfEligible(placement: placement, isEnabled: dependencies.isEnabled(), isEligibleForAds: isEligibleForAds)
        else { return }
        let loader = AdLoader(adUnitID: LinkaAdsConfiguration.nativeAdUnitID(for: placement), rootViewController: nil, adTypes: [.native], options: nil)
        let identifier = ObjectIdentifier(loader)
        loader.delegate = self
        nativeLoaders[identifier] = loader
        loaderContexts[identifier] = (placement, generation)
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        dependencies.nativeAdLoadWillStart()
        loader.load(request)
    }

    private func invalidatePendingAds() {
        requestGate.invalidateForMeasurement()
        preparationTask?.cancel()
        preparationTask = nil
        pendingPlacements.removeAll()
        nativeLoaders.values.forEach { $0.delegate = nil }
        nativeLoaders.removeAll()
        loaderContexts.removeAll()
        nativeAds.removeAll()
    }

    private func presentationPermit(for generation: Int) -> LinkaAdPresentationPermit {
        LinkaAdPresentationPermit { [weak self] in
            guard let self else { return false }
            return !self.adsSuppressedForMeasurement && self.requestGate.canContinue(requestGeneration: generation)
        }
    }
    #else
    func refreshConsentInformation() async {}
    func prepareHomeAd(isEligibleForAds: Bool, isEntitlementResolved: Bool) {}
    func prepareHistoryAds(slotCount: Int, isEligibleForAds: Bool, isEntitlementResolved: Bool) {}
    func prepareResultAd(isEligibleForAds: Bool, isEntitlementResolved: Bool) {}
    func currentResultPlacement() -> LinkaAdPlacement { .result(0) }
    func prepareMyNetworkAd(isEligibleForAds: Bool, isEntitlementResolved: Bool) {}
    func prepareRouterAd(index: Int, isEligibleForAds: Bool, isEntitlementResolved: Bool) {}
    func prepareServicesAd(isEligibleForAds: Bool, isEntitlementResolved: Bool) {}
    func measurementDidStart() {}
    func measurementDidEnd() {}
    func updateEligibility(isEligibleForAds: Bool, isEntitlementResolved: Bool) {}
    #endif
}

#if os(iOS)
private enum LinkaAdsConfiguration {
    #if DEBUG
    static let testNativeAdUnitID = "ca-app-pub-3940256099942544/3986624511"
    #else
    static let homeNativeAdUnitID = "ca-app-pub-5542349230926522/9310217028"
    static let historyNativeAdUnitIDs = ["ca-app-pub-5542349230926522/9986621449", "ca-app-pub-5542349230926522/6664839985", "ca-app-pub-5542349230926522/8110532028"]
    static let resultNativeAdUnitIDs = ["ca-app-pub-5542349230926522/6190819389", "ca-app-pub-5542349230926522/8553385151"]
    static let myNetworkNativeAdUnitID = "ca-app-pub-5542349230926522/5731073822"
    static let routerNativeAdUnitIDs = ["ca-app-pub-5542349230926522/3508815720", "ca-app-pub-5542349230926522/5187139184"]
    static let servicesNativeAdUnitID = "ca-app-pub-5542349230926522/8254874393"
    #endif

    static func nativeAdUnitID(for placement: LinkaAdPlacement) -> String {
        #if DEBUG
        return testNativeAdUnitID
        #else
        switch placement {
        case .home: return homeNativeAdUnitID
        case .history(let index): return historyNativeAdUnitIDs[index % historyNativeAdUnitIDs.count]
        case .result(let index): return resultNativeAdUnitIDs[index % resultNativeAdUnitIDs.count]
        case .myNetwork: return myNetworkNativeAdUnitID
        case .router(let index): return routerNativeAdUnitIDs[index % routerNativeAdUnitIDs.count]
        case .services: return servicesNativeAdUnitID
        }
        #endif
    }
}

extension LinkaAdsCoordinator: NativeAdLoaderDelegate, AdLoaderDelegate {
    nonisolated func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        let identifier = ObjectIdentifier(adLoader)
        Task { @MainActor [weak self] in
            guard let self, let context = self.loaderContexts[identifier], self.canLoadAds,
                  self.requestGate.canContinue(requestGeneration: context.generation) else { return }
            self.nativeAds[context.placement] = nativeAd
            self.nativeLoaders.removeValue(forKey: identifier)
            self.loaderContexts.removeValue(forKey: identifier)
        }
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        let identifier = ObjectIdentifier(adLoader)
        Task { @MainActor [weak self] in
            self?.nativeLoaders.removeValue(forKey: identifier)
            self?.loaderContexts.removeValue(forKey: identifier)
        }
    }
}
#endif
