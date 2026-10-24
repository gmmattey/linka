import SwiftUI
import NetworkCore
import NetworkAssist

/// Conversa efêmera: envia apenas a pergunta, poucas mensagens desta tela e métricas sem identificadores.
public struct AssistView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AssistConversationViewModel

    public let currentMeasurement: NetworkMeasurement?
    public let recentMeasurements: [NetworkMeasurement]
    public let isCollectingMeasurement: Bool
    public let usageContext: String?
    public let failureSignal: NetworkAssistFailureSignal?
    public let onRetry: (() -> Void)?
    public let onRetest: (() -> Void)?
    public let onShowDetails: (() -> Void)?
    public let onCloseSheet: (() -> Void)?

    public init(
        currentMeasurement: NetworkMeasurement?, recentMeasurements: [NetworkMeasurement] = [], isCollectingMeasurement: Bool = false,
        usageContext: String? = nil, failureSignal: NetworkAssistFailureSignal? = nil, objective: String? = nil,
        subcategory: String? = nil, reportedProblem: String? = nil, onRetry: (() -> Void)? = nil,
        onRetest: (() -> Void)? = nil, onShowDetails: (() -> Void)? = nil, entitlements: Any? = nil,
        assistProvider: Any? = nil, assistIsRemote: Bool = true, onCloseSheet: (() -> Void)? = nil
    ) {
        self.currentMeasurement = currentMeasurement; self.recentMeasurements = recentMeasurements; self.isCollectingMeasurement = isCollectingMeasurement
        self.usageContext = usageContext; self.failureSignal = failureSignal; self.onRetry = onRetry; self.onRetest = onRetest
        self.onShowDetails = onShowDetails; self.onCloseSheet = onCloseSheet
        _viewModel = StateObject(wrappedValue: AssistConversationViewModel())
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(LinkaCopy.value("assist.direct.intro"))
                                .font(.bodyRegular)
                                .foregroundStyle(.secondary)
                            measurementContext
                            if viewModel.messages.isEmpty {
                                Text(LinkaCopy.value("assist.direct.privacy"))
                                    .font(.captionSmall)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                            }
                            ForEach(viewModel.messages) { message in messageView(message).id(message.id) }
                            if viewModel.isSending, viewModel.messages.last?.role != .assistant { typingIndicator }
                            if let errorMessage = viewModel.errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        if let last = viewModel.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                Divider()
                composer
            }
            .linkaSheetToolbar(title: LinkaCopy.value("assist.direct.title"), onDismiss: closeSheet)
        }
        .onDisappear { viewModel.cancel() }
    }

    @ViewBuilder private var measurementContext: some View {
        if let measurement = currentMeasurement {
            HStack(spacing: 12) {
                metric(LinkaCopy.value("detail.download"), measurement.downloadMbps.map { String(format: "%.0f Mbps", $0) })
                metric(LinkaCopy.value("detail.upload"), measurement.uploadMbps.map { String(format: "%.0f Mbps", $0) })
                metric(LinkaCopy.value("assist.latency"), measurement.latencyMs.map { String(format: "%.0f ms", $0) })
            }
            .padding(12).background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func metric(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value ?? LinkaCopy.value("common.unavailable")).font(.subheadline.weight(.semibold))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composer: some View {
        let canSend = !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isSending

        return HStack(alignment: .bottom, spacing: 8) {
            TextField(LinkaCopy.value("assist.direct.placeholder"), text: $viewModel.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.bodyRegular)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 48)

            Button { viewModel.send(measurement: currentMeasurement) } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.brandOnSurface)
                    .frame(width: 44, height: 44)
                    .background(canSend ? Color.brandSurface : Color.textSecondary.opacity(0.35), in: Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel(LinkaCopy.value("assist.direct.send"))
        }
        .padding(6)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.5), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func messageView(_ message: AssistConversationMessage) -> some View {
        HStack {
            if message.role == .assistant {
                Text(message.content)
                    .font(.bodyRegular)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(14)
                    .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
                Spacer(minLength: 44)
            } else {
                Spacer(minLength: 44)
                Text(message.content)
                    .font(.bodyRegular)
                    .foregroundStyle(Color.brandOnSurface)
                    .padding(14)
                    .background(Color.brandSurface, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
            }
        }
    }

    private var typingIndicator: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(0.25 + 0.75 * max(0, sin(phase * 4 - Double(index))))
                }
            }
            .padding(12)
            .background(Color.surfaceCard, in: Capsule())
        }
    }

    private func closeSheet() {
        viewModel.cancel()
        if let onCloseSheet { onCloseSheet() } else { dismiss() }
    }
}
