import SwiftUI

struct StatDisplay: View {
    var label: String
    var value: String
    var unit: String
    var accent: Bool = false
    var animation: Namespace.ID? = nil
    var matchedId: String? = nil
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.monoEyebrow)
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Group {
                    if let id = matchedId, let ns = animation {
                        Text(value)
                            .matchedGeometryEffect(id: id, in: ns)
                    } else {
                        Text(value)
                    }
                }
                .font(.displayTitle)
                .foregroundColor(accent ? .brandAccentWarm : .textPrimary)
                .lineLimit(1)
                
                Text(unit)
                    .font(.monoCaption)
                    .foregroundColor(.textSecondary)
            }
        }
    }
}
