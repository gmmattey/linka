import SwiftUI
import NetworkCore
import NetworkOptimization

/// Superfície secundária: a medição continua protagonista e a Otimização só
/// traduz fatos já medidos em uma próxima ação explícita da pessoa.
struct OptimizationView: View {
    let baseline: NetworkMeasurement
    let history: [NetworkMeasurement]
    let isPlusActive: Bool
    let onRequestPurchase: () -> Void
    let onRetest: () -> Void
    let onManageIdentification: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var profileCoordinator = OptimizationProfileCoordinator()
    @State private var isPresentingEnvironmentCreation = false

    private var plan: OptimizationPlan {
        OptimizationPlanBuilder().build(baseline: baseline, history: history)
    }

    var body: some View {
        #if os(macOS)
        macOSContent
        #else
        iOSContent
        #endif
    }

    private var iOSContent: some View {
        NavigationStack {
            List {
                Section {
                    Text(LinkaCopy.value("optimization.intro"))
                        .foregroundStyle(.secondary)
                }

                if plan.opportunities.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(LinkaCopy.value("optimization.none.title"))
                                .font(.body.weight(.semibold))
                            Text(LinkaCopy.value("optimization.none.message"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } else {
                    Section(LinkaCopy.value("optimization.opportunities")) {
                        ForEach(plan.opportunities) { opportunity in
                            opportunityRow(opportunity)
                        }
                    }
                }

                NetworkProfilesSection(
                    coordinator: profileCoordinator,
                    isPlusActive: isPlusActive,
                    onRequestPurchase: onRequestPurchase,
                    onManageIdentification: onManageIdentification,
                    isPresentingCreation: $isPresentingEnvironmentCreation
                )

                Section {
                    if isPlusActive {
                        NavigationLink("Comparar resposta de DNS") {
                            DNSBenchmarkView {
                                dismiss()
                                onRetest()
                            }
                        }
                    } else {
                        Button("Comparar resposta de DNS") {
                            onRequestPurchase()
                        }
                    }
                } header: {
                    Text("DNS")
                } footer: {
                    Text(isPlusActive
                         ? "Compare respostas DNS medidas nesta conexão."
                         : "Disponível no Linka Plus.")
                }

                Section {
                    if isPlusActive {
                        Button(LinkaCopy.value("optimization.retest")) {
                            dismiss()
                            onRetest()
                        }
                    } else {
                        Button(LinkaCopy.value("optimization.preview.cta"), action: onRequestPurchase)
                    }
                } footer: {
                    Text(isPlusActive
                         ? LinkaCopy.value("optimization.retest.hint")
                         : LinkaCopy.value("optimization.preview.hint"))
                }
            }
            .linkaGradientScreenBackground()
            .navigationTitle(LinkaCopy.value("optimization.title"))
            .task(id: baseline.id) {
                await profileCoordinator.refresh(
                    currentMeasurement: baseline,
                    history: history
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LinkaCopy.value("common.close")) { dismiss() }
                }
            }
        }
        .sheet(isPresented: $isPresentingEnvironmentCreation) {
            NetworkProfileNameEditor(
                title: LinkaCopy.value("environments.create.title"),
                name: "",
                saveTitle: LinkaCopy.value("environments.create.save")
            ) { name in
                Task {
                    if await profileCoordinator.createAndAssignCurrentMeasurement(named: name) {
                        isPresentingEnvironmentCreation = false
                    }
                }
            }
        }
    }

    #if os(macOS)
    private var macOSContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LinkaCopy.value("optimization.title"))
                        .font(.title.weight(.bold))
                    Text(LinkaCopy.value("optimization.intro"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                macVerdict

                Button(isPlusActive ? LinkaCopy.value("optimization.retest") : LinkaCopy.value("optimization.preview.cta")) {
                    if isPlusActive {
                        dismiss()
                        onRetest()
                    } else {
                        onRequestPurchase()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandAccentWarm)
                .accessibilityHint(isPlusActive ? LinkaCopy.value("optimization.retest.hint") : LinkaCopy.value("optimization.preview.hint"))

                macSection(title: "Nesta medição") {
                    NetworkProfilesSection(
                        coordinator: profileCoordinator,
                        isPlusActive: isPlusActive,
                        onRequestPurchase: onRequestPurchase,
                        onManageIdentification: onManageIdentification,
                        isPresentingCreation: $isPresentingEnvironmentCreation
                    )

                    Divider()
                    if isPlusActive {
                        NavigationLink {
                            DNSBenchmarkView {
                                dismiss()
                                onRetest()
                            }
                        } label: {
                            macSecondaryAction(
                                title: "Comparar resposta de DNS",
                                detail: "Mede respostas DNS nesta conexão."
                            )
                        }
                    } else {
                        Button(action: onRequestPurchase) {
                            macSecondaryAction(
                                title: "Comparar resposta de DNS",
                                detail: "Disponível no Linka Plus."
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(40)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle(LinkaCopy.value("optimization.title"))
        .sheet(isPresented: $isPresentingEnvironmentCreation) {
            NetworkProfileNameEditor(
                title: LinkaCopy.value("environments.create.title"),
                name: "",
                saveTitle: LinkaCopy.value("environments.create.save")
            ) { name in
                Task {
                    if await profileCoordinator.createAndAssignCurrentMeasurement(named: name) {
                        isPresentingEnvironmentCreation = false
                    }
                }
            }
            .frame(minWidth: 420, minHeight: 220)
        }
        .task(id: baseline.id) {
            await profileCoordinator.refresh(currentMeasurement: baseline, history: history)
        }
    }

    @ViewBuilder private var macVerdict: some View {
        if plan.opportunities.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(LinkaCopy.value("optimization.none.title"), systemImage: "checkmark.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.statusGood)
                Text(LinkaCopy.value("optimization.none.message"))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
        } else {
            macSection(title: LinkaCopy.value("optimization.opportunities")) {
                ForEach(plan.opportunities) { opportunity in
                    opportunityRow(opportunity)
                    if opportunity.id != plan.opportunities.last?.id { Divider() }
                }
            }
        }
    }

    private func macSecondaryAction(title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func macSection<Content: View>(title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12, content: content)
                .padding(18)
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
    #endif

    @ViewBuilder
    private func opportunityRow(_ opportunity: OptimizationOpportunity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title(for: opportunity.kind), systemImage: icon(for: opportunity.kind))
                .font(.body.weight(.semibold))
            Text(detail(for: opportunity.kind))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(action(for: opportunity.action))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.brandAccentWarm)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func title(for kind: OptimizationOpportunityKind) -> String {
        switch kind {
        case .responsivenessUnderLoad: LinkaCopy.value("optimization.load.title")
        case .unstableConnection: LinkaCopy.value("optimization.stability.title")
        case .belowUsualQuality: LinkaCopy.value("optimization.history.title")
        }
    }

    private func detail(for kind: OptimizationOpportunityKind) -> String {
        switch kind {
        case .responsivenessUnderLoad: LinkaCopy.value("optimization.load.message")
        case .unstableConnection: LinkaCopy.value("optimization.stability.message")
        case .belowUsualQuality: LinkaCopy.value("optimization.history.message")
        }
    }

    private func action(for action: OptimizationGuidedAction) -> String {
        switch action {
        case .reduceConcurrentUse: LinkaCopy.value("optimization.action.concurrent")
        case .moveCloserToRouter: LinkaCopy.value("optimization.action.proximity")
        case .restartRouter: LinkaCopy.value("optimization.action.restart")
        }
    }

    private func icon(for kind: OptimizationOpportunityKind) -> String {
        switch kind {
        case .responsivenessUnderLoad: "arrow.triangle.2.circlepath"
        case .unstableConnection: "wifi.exclamationmark"
        case .belowUsualQuality: "clock.arrow.circlepath"
        }
    }
}

struct OptimizationRetestResultView: View {
    let result: OptimizationRetestComparison
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: symbol).font(.largeTitle).foregroundStyle(.tint)
                Text(title).font(.title3.weight(.semibold))
                Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            .padding(32)
            .linkaStaticScreenBackground()
            .navigationTitle(LinkaCopy.value("optimization.title"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(LinkaCopy.value("common.close")) { dismiss() } } }
        }
    }
    private var symbol: String { if case .improved = result { return "checkmark.circle" }; return "equal.circle" }
    private var title: String { if case .improved = result { return LinkaCopy.value("optimization.result.improved.title") }; if case .noSignificantGain = result { return LinkaCopy.value("optimization.result.stable.title") }; return LinkaCopy.value("optimization.result.incomparable.title") }
    private var message: String { if case .improved = result { return LinkaCopy.value("optimization.result.improved.message") }; if case .noSignificantGain = result { return LinkaCopy.value("optimization.result.stable.message") }; return LinkaCopy.value("optimization.result.incomparable.message") }
}
