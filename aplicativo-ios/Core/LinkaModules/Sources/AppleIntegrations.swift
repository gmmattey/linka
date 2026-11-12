import Foundation

@available(
    *,
    deprecated,
    message: "Integrações Apple agora vivem em módulos dedicados. Use LinkaAppIntents para App Intents; Widgets e iCloud terão módulos próprios."
)
public enum AppleIntegration: String, Codable, CaseIterable, Hashable, Sendable {
    case widgets
    case appIntents
    case siriShortcuts
    case sharedHistory
}

@available(
    *,
    deprecated,
    message: "Integrações Apple agora vivem em módulos dedicados."
)
public protocol AppleIntegrationProviding: Sendable {
    func isAvailable(_ integration: AppleIntegration) async -> Bool
}

@available(
    *,
    deprecated,
    message: "Integrações Apple agora vivem em módulos dedicados."
)
public struct StaticAppleIntegrationProvider: AppleIntegrationProviding {
    private let supported: Set<AppleIntegration>

    public init(supported: Set<AppleIntegration> = []) {
        self.supported = supported
    }

    public func isAvailable(_ integration: AppleIntegration) async -> Bool {
        supported.contains(integration)
    }
}
