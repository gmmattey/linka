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
                        NavigationLink {
                            DNSBenchmarkView {
                                dismiss()
                                onRetest()
                            }
                        } label: {
                            Text("Comparar resposta de DNS")
                                .foregroundColor(.textPrimary)
                        }
                    } else {
                        Button("Comparar resposta de DNS") {
                            onRequestPurchase()
                        }
                        .foregroundColor(.brandAccentWarmInk)
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
                        .foregroundColor(.brandAccentWarmInk)
                    } else {
                        Button(LinkaCopy.value("optimization.preview.cta"), action: onRequestPurchase)
                            .foregroundColor(.brandAccentWarmInk)
                    }
                } footer: {
                    Text(isPlusActive
                         ? LinkaCopy.value("optimization.retest.hint")
                         : LinkaCopy.value("optimization.preview.hint"))
                }
            }
            .tint(.brandAccentWarm)
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
            VStack(alignment: .leading, spacing: 24) {
                MacBanner(
                    systemImage: plan.opportunities.isEmpty ? "checkmark.seal.fill" : "slider.horizontal.3",
                    tint: plan.opportunities.isEmpty ? .statusGood : MacPalette.download,
                    title: plan.opportunities.isEmpty ? LinkaCopy.value("optimization.none.title") : LinkaCopy.value("optimization.title"),
                    message: plan.opportunities.isEmpty ? LinkaCopy.value("optimization.none.message") : LinkaCopy.value("optimization.intro")
                )

                if !plan.opportunities.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(LinkaCopy.value("optimization.opportunities")).font(MacType.section)
                        VStack(spacing: 16) {
                            ForEach(plan.opportunities) { opportunity in
                                HStack(alignment: .top, spacing: 16) {
                                    MacIconBadge(systemImage: icon(for: opportunity.kind), tint: MacPalette.quality, size: 50)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(title(for: opportunity.kind)).font(MacType.headline)
                                        Text(detail(for: opportunity.kind)).font(MacType.label).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Label(action(for: opportunity.action), systemImage: "lightbulb.fill")
                                            .font(MacType.labelStrong)
                                            .foregroundStyle(Color.brandAccentWarmInk)
                                            .padding(.top, 4)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .linkaMacCard()
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }

                Button(isPlusActive ? LinkaCopy.value("optimization.retest") : LinkaCopy.value("optimization.preview.cta")) {
                    if isPlusActive {
                        dismiss()
                        onRetest()
                    } else {
                        onRequestPurchase()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.brandAccentWarm)
                .accessibilityHint(isPlusActive ? LinkaCopy.value("optimization.retest.hint") : LinkaCopy.value("optimization.preview.hint"))

                VStack(alignment: .leading, spacing: 12) {
                    Text(LinkaCopy.value("Nesta medição")).font(MacType.section)
                    NetworkProfilesSection(
                        coordinator: profileCoordinator,
                        isPlusActive: isPlusActive,
                        onRequestPurchase: onRequestPurchase,
                        onManageIdentification: onManageIdentification,
                        isPresentingCreation: $isPresentingEnvironmentCreation
                    )
                    if isPlusActive {
                        NavigationLink {
                            DNSBenchmarkView {
                                dismiss()
                                onRetest()
                            }
                        } label: {
                            macToolCard(title: LinkaCopy.value("Comparar resposta de DNS"), detail: LinkaCopy.value("Mede respostas DNS nesta conexão."))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: onRequestPurchase) {
                            macToolCard(title: LinkaCopy.value("Comparar resposta de DNS"), detail: LinkaCopy.value("Disponível no Linka Plus."))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.macPage)
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

    private func macToolCard(title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            MacIconBadge(systemImage: "server.rack", tint: MacPalette.upload, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(MacType.headline)
                Text(detail).font(MacType.label).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .linkaMacCard()
        .contentShape(Rectangle())
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
        #if os(macOS)
        MacSheetScaffold(
            title: LinkaCopy.value("optimization.title"),
            systemImage: symbol,
            tint: symbolColor,
            closeTitle: LinkaCopy.value("common.close"),
            onClose: { dismiss() }
        ) {
            MacBanner(systemImage: symbol, tint: symbolColor, title: title, message: message)
        }
        #else
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: symbol).font(.largeTitle).foregroundStyle(symbolColor)
                Text(title).font(.title3.weight(.semibold))
                Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            .padding(32)
            .linkaStaticScreenBackground()
            .navigationTitle(LinkaCopy.value("optimization.title"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(LinkaCopy.value("common.close")) { dismiss() } } }
        }
        #endif
    }
    private var symbolColor: Color {
        if case .improved = result { return .statusGood }
        return .brandAccentWarmInk
    }
    private var symbol: String { if case .improved = result { return "checkmark.circle" }; return "equal.circle" }
    private var title: String { if case .improved = result { return LinkaCopy.value("optimization.result.improved.title") }; if case .noSignificantGain = result { return LinkaCopy.value("optimization.result.stable.title") }; return LinkaCopy.value("optimization.result.incomparable.title") }
    private var message: String { if case .improved = result { return LinkaCopy.value("optimization.result.improved.message") }; if case .noSignificantGain = result { return LinkaCopy.value("optimization.result.stable.message") }; return LinkaCopy.value("optimization.result.incomparable.message") }
}
