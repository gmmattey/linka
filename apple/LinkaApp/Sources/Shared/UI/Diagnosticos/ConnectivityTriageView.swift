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
        #if os(macOS)
        macBody
        #else
        iOSBody
        #endif
    }

    private var iOSBody: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(LinkaCopy.value("triage.checking"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(LinkaCopy.value("triage.checking.accessibility"))
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
                            Text(LinkaCopy.value("common.retry"))
                        }
                        .buttonStyle(.linkaPrimary)
                        .accessibilityHint(LinkaCopy.value("triage.retry.hint"))

                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityElement(children: .contain)
                } else {
                    LinkaUnavailableState(
                        title: LinkaCopy.value("triage.unavailable.title"),
                        message: LinkaCopy.value("triage.unavailable.message"),
                        systemImage: "wifi.exclamationmark"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .linkaStaticScreenBackground()
            .linkaSheetToolbar(title: LinkaCopy.value("triage.title")) { dismiss() }
            .task { await runTriage() }
        }
    }

#if os(macOS)
    private var macBody: some View {
        MacSheetScaffold(
            title: LinkaCopy.value("triage.title"),
            systemImage: "stethoscope",
            tint: MacPalette.ping,
            closeTitle: LinkaCopy.value("common.close"),
            onClose: { dismiss() }
        ) {
            if isLoading {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text(LinkaCopy.value("triage.checking")).font(MacType.body).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
                .accessibilityLabel(LinkaCopy.value("triage.checking.accessibility"))
            } else if let report {
                let reachable = report.outcome == .internetReachable
                MacBanner(
                    systemImage: reachable ? "checkmark.seal.fill" : "wifi.exclamationmark",
                    tint: reachable ? .statusGood : .statusAttention,
                    title: title(for: report),
                    message: message(for: report)
                )
                Button {
                    dismiss()
                    onRetry()
                } label: {
                    Text(LinkaCopy.value("common.retry"))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandAccentWarm)
                .controlSize(.large)
                .accessibilityHint(LinkaCopy.value("triage.retry.hint"))
            } else {
                MacBanner(
                    systemImage: "wifi.exclamationmark", tint: .statusAttention,
                    title: LinkaCopy.value("triage.unavailable.title"),
                    message: LinkaCopy.value("triage.unavailable.message")
                )
            }
        }
        .task { await runTriage() }
    }
    #endif

    @MainActor
    private func runTriage() async {
        LinkaAnalytics.shared.track(.diagnosticStarted(diagnosticType: "connectivity_triage"))
        do {
            let result = try await service.run()
            guard !Task.isCancelled else { return }
            report = result
            isLoading = false
            LinkaAnalytics.shared.track(.diagnosticCompleted(diagnosticType: "connectivity_triage", outcome: "success"))
        } catch is CancellationError {
            LinkaAnalytics.shared.track(.diagnosticCompleted(diagnosticType: "connectivity_triage", outcome: "cancelled"))
            return
        } catch {
            guard !Task.isCancelled else { return }
            report = ConnectivityTriageReport(
                outcome: .inconclusive,
                path: ConnectivityPathSnapshot(status: .requiresConnection)
            )
            isLoading = false
            LinkaAnalytics.shared.track(.diagnosticCompleted(diagnosticType: "connectivity_triage", outcome: "inconclusive"))
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
