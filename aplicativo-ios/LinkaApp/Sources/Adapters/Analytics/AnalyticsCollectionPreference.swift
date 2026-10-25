import Foundation

/// Controle local da coleta analítica. A exclusão vale somente nesta instalação
/// e impede tanto os eventos automáticos do SDK quanto os eventos de produto.
public final class AnalyticsCollectionPreference: @unchecked Sendable {
    public static let ownerExcludedDefaultsKey = "linka.analytics.owner_excluded"
    public static let disableLaunchArgument = "-linka-analytics-disabled"
    public static let firebaseDebugLaunchArgument = "-linka-firebase-debug"

    private let userDefaults: UserDefaults
    private let arguments: [String]
    private let environment: [String: String]
    private let defaultCollectionEnabled: Bool

    public init(
        userDefaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultCollectionEnabled: Bool? = nil
    ) {
        self.userDefaults = userDefaults
        self.arguments = arguments
        self.environment = environment
        self.defaultCollectionEnabled = defaultCollectionEnabled ?? Self.computeDefaultCollectionEnabled(arguments: arguments)
    }

    public var isCollectionEnabled: Bool {
        defaultCollectionEnabled
            && !isAutomatedTest
            && !arguments.contains(Self.disableLaunchArgument)
            && !isOwnerExcluded
    }

    public var isOwnerExcluded: Bool {
        userDefaults.bool(forKey: Self.ownerExcludedDefaultsKey)
    }

    public func setOwnerExcluded(_ excluded: Bool) {
        userDefaults.set(excluded, forKey: Self.ownerExcludedDefaultsKey)
    }

    private var isAutomatedTest: Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || arguments.contains(where: { $0.hasPrefix("-ui-fixture") || $0.contains("fixture") })
    }

    private static func computeDefaultCollectionEnabled(arguments: [String]) -> Bool {
        #if DEBUG
        arguments.contains(firebaseDebugLaunchArgument) || arguments.contains("-FIRDebugEnabled")
        #else
        true
        #endif
    }
}
