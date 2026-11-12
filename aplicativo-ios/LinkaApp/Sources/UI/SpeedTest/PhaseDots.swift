import SwiftUI

struct PhaseDots: View {
    var phases: [(key: String, label: String)]
    var activeKey: String
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activePhaseLabel: String {
        phases.first(where: { $0.key == activeKey })?.label ?? activeKey
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(phases, id: \.key) { phase in
                let isActive = phase.key == activeKey
                HStack(spacing: 6) {
                    Circle()
                        .fill(isActive ? Color.brandSurface : Color.borderDefault)
                        .frame(width: 7, height: 7)
                    
                    Text(phase.label)
                        .font(.caption2.weight(isActive ? .semibold : .medium))
                        .foregroundColor(isActive ? .textPrimary : .textSecondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(activePhaseLabel))
    }
}
