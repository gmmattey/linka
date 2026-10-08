import SwiftUI
import NetworkConnectivityTriage

/// Recuperação curta após uma falha de medição. Mostra fatos do aparelho no
/// instante em que a pessoa pede ajuda; não substitui a medição nem o Assist.
struct ConnectivityTriageView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var report: ConnectivityTriageReport?
    @State private var isLoading = true
    let onRetry: () -> Void
    private let service: NetworkConnectivityTriageService

    init(
        onRetry: @escaping () -> Void,
        service: NetworkConnectivityTriageService = NetworkConnectivityTriageService()
    ) {
        self.onRetry = onRetry
        self.service = service
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("triage.checking")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("triage.checking.accessibility")
                } else if let report {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(eyebrow(for: report))
                            .font(.monoEyebrow)
                            .foregroundColor(.textSecondary)
                        Text(title(for: report))
                            .font(.title3.weight(.bold))
                            .foregroundColor(.textPrimary)
                        Text(message(for: report))
                            .font(.body)
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            dismiss()
                            onRetry()
                        } label: {
                            Text("common.retry")
                        }
                        .buttonStyle(.linkaPrimary)
                        .accessibilityHint("triage.retry.hint")

                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityElement(children: .contain)
                } else {
                    LinkaUnavailableState(
                        title: "triage.unavailable.title",
                        message: "triage.unavailable.message",
                        systemImage: "wifi.exclamationmark"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .linkaStaticScreenBackground()
            .linkaSheetToolbar(title: LinkaCopy.value("triage.title")) { dismiss() }
            .task {
                do {
                    let result = try await service.run()
                    guard !Task.isCancelled else { return }
                    report = result
                    isLoading = false
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    report = ConnectivityTriageReport(
                        outcome: .inconclusive,
                        path: ConnectivityPathSnapshot(status: .requiresConnection)
                    )
                    isLoading = false
                }
            }
        }
    }

    private func eyebrow(for report: ConnectivityTriageReport) -> String {
        switch report.outcome {
        case .noNetworkPath: return LinkaCopy.value("triage.eyebrow.noPath")
        case .internetReachable: return LinkaCopy.value("triage.eyebrow.reachable")
        case .dnsResolutionUnavailable: return LinkaCopy.value("triage.eyebrow.dns")
        case .captivePortalSuspected: return LinkaCopy.value("triage.eyebrow.portal")
        case .inconclusive: return LinkaCopy.value("triage.eyebrow.inconclusive")
        }
    }

    private func title(for report: ConnectivityTriageReport) -> String {
        switch report.outcome {
        case .noNetworkPath: return LinkaCopy.value("triage.outcome.noPath")
        case .internetReachable: return LinkaCopy.value("triage.outcome.reachable")
        case .dnsResolutionUnavailable: return LinkaCopy.value("triage.outcome.dns")
        case .captivePortalSuspected: return LinkaCopy.value("triage.outcome.portal")
        case .inconclusive: return LinkaCopy.value("triage.outcome.inconclusive")
        }
    }

    private func message(for report: ConnectivityTriageReport) -> String {
        switch report.outcome {
        case .noNetworkPath:
            return LinkaCopy.value("triage.message.noPath")
        case .internetReachable:
            return LinkaCopy.value("triage.message.reachable")
        case .dnsResolutionUnavailable:
            return LinkaCopy.value("triage.message.dns")
        case .captivePortalSuspected:
            return LinkaCopy.value("triage.message.portal")
        case .inconclusive:
            return LinkaCopy.value("triage.message.inconclusive")
        }
    }
}
