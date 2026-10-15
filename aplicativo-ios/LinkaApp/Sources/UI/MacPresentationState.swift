#if os(macOS)
import Foundation
import CoreGraphics

/// Destinos da casca macOS. Mantidos com as regras de apresentação para que
/// possam ser testados sem inicializar o aplicativo, rede ou StoreKit.
enum MacDestination: Hashable, CaseIterable {
    case speedTest
    case history
    case assist
    case dns
    case optimization
    case myNetwork
    case settings
}

/// Regras puras da casca macOS. Elas mantêm a navegação e o resize testáveis
/// sem transferir estado de apresentação para o motor de medição.
enum MacNavigationPolicy {
    static let measurementDestination: MacDestination = .speedTest

    static func isSidebarDestination(_ destination: MacDestination) -> Bool {
        switch destination {
        case .speedTest, .history, .assist, .dns, .optimization, .myNetwork:
            return true
        case .settings:
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
        case .speedTest, .history, .assist, .dns, .optimization, .settings:
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

enum MacHistoryComparisonPolicy {
    static let maxSelectionCount = 2

    static func toggleSelection(id: UUID, currentSelection: Set<UUID>) -> (newSelection: Set<UUID>, wasCapped: Bool) {
        if currentSelection.contains(id) {
            var updated = currentSelection
            updated.remove(id)
            return (updated, false)
        }
        if currentSelection.count >= maxSelectionCount {
            return (currentSelection, true)
        }
        var updated = currentSelection
        updated.insert(id)
        return (updated, false)
    }

    static func calculateDeltaMbps(a: Double?, b: Double?) -> Double? {
        guard let a = a, let b = b else { return nil }
        return abs(b - a)
    }

    static func isComparisonReady(selectionCount: Int) -> Bool {
        selectionCount == maxSelectionCount
    }
}

enum MacOptimizationPolicy {
    static let requiredStepCount = 3

    static func isReadyForRetest(checkedSteps: [Bool]) -> Bool {
        guard checkedSteps.count >= requiredStepCount else { return false }
        return checkedSteps.prefix(requiredStepCount).allSatisfy { $0 }
    }

    static func progressText(completedCount: Int) -> String {
        "\(min(completedCount, requiredStepCount)) de \(requiredStepCount)"
    }
}

enum MacDNSBenchmarkPolicy {
    static func relativeBarWidth(medianMs: Double, maxLatencyMs: Double) -> Double {
        guard maxLatencyMs > 0 else { return 0.05 }
        let ratio = medianMs / maxLatencyMs
        return max(0.05, min(1.0, ratio))
    }
}

enum MacAssistContextPolicy {
    static func shouldIncludeMeasurement(toggle: Bool, hasMeasurement: Bool) -> Bool {
        toggle && hasMeasurement
    }
}
#endif
