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
        #if os(macOS)
        macBody
        #else
        iOSBody
        #endif
    }

    #if os(macOS)
    private var macBody: some View {
        VStack(spacing: 0) {
            if onCloseSheet != nil {
                HStack(spacing: 14) {
                    MacIconBadge(systemImage: "sparkles", tint: MacPalette.download, size: 44)
                    Text(LinkaCopy.value("assist.direct.title")).font(MacType.section)
                    Spacer()
                    Button(LinkaCopy.value("common.close"), action: closeSheet)
                        .keyboardShortcut(.defaultAction)
                        .controlSize(.large)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Rectangle().fill(Color.macCard).shadow(color: .black.opacity(0.18), radius: 10, y: 4))
                .zIndex(1)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        MacBanner(
                            systemImage: "sparkles", tint: MacPalette.download,
                            title: LinkaCopy.value("assist.direct.intro"),
                            message: viewModel.messages.isEmpty ? LinkaCopy.value("assist.direct.privacy") : nil
                        )
                        if let measurement = currentMeasurement {
                            HStack(spacing: 14) {
                                MacMetricTile(title: LinkaCopy.value("detail.download"), value: MacMeasurementFormat.mbps(measurement.downloadMbps), unit: "Mbps",
                                              systemImage: "arrow.down.circle.fill", tint: MacPalette.download, valueSize: 30)
                                MacMetricTile(title: LinkaCopy.value("detail.upload"), value: MacMeasurementFormat.mbps(measurement.uploadMbps), unit: "Mbps",
                                              systemImage: "arrow.up.circle.fill", tint: MacPalette.upload, valueSize: 30)
                                MacMetricTile(title: LinkaCopy.value("assist.latency"), value: measurement.latencyMs.map { String(Int(round($0))) } ?? "—", unit: "ms",
                                              systemImage: "timer", tint: MacPalette.ping, valueSize: 30)
                            }
                        }
                        ForEach(viewModel.messages) { message in macMessage(message).id(message.id) }
                        if viewModel.isSending, viewModel.messages.last?.role != .assistant { typingIndicator }
                        if let errorMessage = viewModel.errorMessage {
                            MacBanner(systemImage: "exclamationmark.triangle.fill", tint: .statusAttention, title: errorMessage)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 780)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let last = viewModel.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            macComposer
        }
        .background(Color.macPage)
        .onDisappear { viewModel.cancel() }
    }

    private var macComposer: some View {
        let canSend = !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isSending
        return HStack(alignment: .bottom, spacing: 10) {
            TextField(LinkaCopy.value("assist.direct.placeholder"), text: $viewModel.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(MacType.body)
                .lineLimit(1...5)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .onSubmit { if canSend { viewModel.send(measurement: currentMeasurement) } }
            Button { viewModel.send(measurement: currentMeasurement) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(canSend ? Color.brandAccentWarm : Color.secondary.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(LinkaCopy.value("assist.direct.send"))
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.macCard)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        )
        .frame(maxWidth: 780)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }

    private func macMessage(_ message: AssistConversationMessage) -> some View {
        HStack {
            if message.role == .assistant {
                Text(message.content)
                    .font(MacType.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.macCard)
                            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                    )
                Spacer(minLength: 60)
            } else {
                Spacer(minLength: 60)
                Text(message.content)
                    .font(MacType.body)
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.brandAccentWarm)
                            .shadow(color: Color.brandAccentWarm.opacity(0.35), radius: 12, y: 6)
                    )
            }
        }
    }
    #endif

    private var iOSBody: some View {
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
