import SwiftUI

/// Explica a direção da fase em curso sem competir com o valor medido.
/// O marcador nunca representa pacote, volume ou tempo exatos: ele apenas
/// traduz visualmente o sentido da sondagem ou do tráfego já em execução.
enum MeasurementNetworkFlowPhase: String, Equatable {
    case ping
    case download
    case upload

    var accessibilityLabel: String {
        switch self {
        case .ping: return LinkaCopy.value("measurement.phase.ping")
        case .download: return LinkaCopy.value("measurement.phase.download")
        case .upload: return LinkaCopy.value("measurement.phase.upload")
        }
    }
}

struct MeasurementNetworkFlowView: View {
    let phase: MeasurementNetworkFlowPhase
    let pingMilliseconds: Int?
    let width: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var markerProgress: CGFloat = 0

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let endpointInset: CGFloat = 34
                let start = endpointInset
                let end = max(start, proxy.size.width - endpointInset)
                let markerX = reduceMotion
                    ? (start + end) / 2
                    : start + (end - start) * markerProgress

                ZStack {
                    Capsule()
                        .fill(Color.borderDefault)
                        .frame(height: 2)
                        .padding(.horizontal, endpointInset)

                    endpoint(symbol: "iphone", alignment: .leading)
                    endpoint(symbol: "server.rack", alignment: .trailing)

                    Circle()
                        .fill(Color.brandAccentWarm)
                        .frame(width: 10, height: 10)
                        .shadow(color: Color.brandAccentWarm.opacity(0.28), radius: 4, y: 1)
                        .position(x: markerX, y: proxy.size.height / 2)
                }
            }
            .frame(width: width, height: 44)

            if phase == .ping {
                HStack(spacing: 4) {
                    Text(pingMilliseconds.map(String.init) ?? "—")
                        .font(.bodyRegularStrong.monospacedDigit())
                        .contentTransition(.numericText())
                    Text("ms")
                        .font(.monoCaption)
                }
                .foregroundStyle(Color.textPrimary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase.accessibilityLabel)
        .accessibilityValue(phase == .ping ? "\(pingMilliseconds.map(String.init) ?? "—") ms" : "")
        .task(id: "\(phase.rawValue)-\(reduceMotion)") {
            await animateMarker()
        }
    }

    private func endpoint(symbol: String, alignment: Alignment) -> some View {
        HStack {
            if alignment == .trailing { Spacer(minLength: 0) }
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 28, height: 28)
                .background(Color.surfaceCard, in: Circle())
            if alignment == .leading { Spacer(minLength: 0) }
        }
    }

    @MainActor
    private func animateMarker() async {
        guard !reduceMotion else {
            markerProgress = 0.5
            return
        }

        switch phase {
        case .ping:
            markerProgress = 0
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.38)) { markerProgress = 1 }
                try? await Task.sleep(nanoseconds: 390_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.38)) { markerProgress = 0 }
                try? await Task.sleep(nanoseconds: 390_000_000)
            }
        case .download:
            markerProgress = 1
            while !Task.isCancelled {
                withAnimation(.linear(duration: 0.68)) { markerProgress = 0 }
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                markerProgress = 1
            }
        case .upload:
            markerProgress = 0
            while !Task.isCancelled {
                withAnimation(.linear(duration: 0.68)) { markerProgress = 1 }
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                markerProgress = 0
            }
        }
    }
}
