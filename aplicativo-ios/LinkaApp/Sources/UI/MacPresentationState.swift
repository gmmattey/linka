#if os(macOS)
import CoreGraphics

/// Destinos da casca macOS. Mantidos com as regras de apresentação para que
/// possam ser testados sem inicializar o aplicativo, rede ou StoreKit.
enum MacDestination: Hashable {
    case speedTest
    case history
    case myNetwork
    case assist
    case optimization
    case settings

}

/// Regras puras da casca macOS. Elas mantêm a navegação e o resize testáveis
/// sem transferir estado de apresentação para o motor de medição.
enum MacNavigationPolicy {
    static let measurementDestination: MacDestination = .speedTest

    static func isSidebarDestination(_ destination: MacDestination) -> Bool {
        switch destination {
        case .speedTest, .history, .myNetwork:
            return true
        case .assist, .optimization, .settings:
            return false
        }
    }

    static func isAvailable(
        _ destination: MacDestination,
        isMeasuring: Bool,
        hasMeasurement: Bool,
        minhaRedeEnabled: Bool
    ) -> Bool {
        guard !isMeasuring || destination == .speedTest else { return false }

        switch destination {
        case .myNetwork:
            return minhaRedeEnabled
        case .optimization:
            return hasMeasurement
        case .speedTest, .history, .assist, .settings:
            return true
        }
    }
}

enum MacHomeLayout {
    static let inspectorMinimumContentWidth: CGFloat = 1_180

    static func showsInspector(contentWidth: CGFloat, hasMeasurement: Bool) -> Bool {
        hasMeasurement && contentWidth >= inspectorMinimumContentWidth
    }
}
#endif
