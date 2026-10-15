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
    #if os(macOS)
    @State private var selectedProfile: String = "general"
    @State private var checklistChecked: [Bool] = [false, false, false]
    @State private var showBaselineTechnicalDetails = false
    #endif

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
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(LinkaCopy.value("optimization.title"))
                            .font(.largeTitle.weight(.bold))
                        Spacer()
                        Text("Fluxo guiado")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.brandAccentWarm.opacity(0.12), in: Capsule())
                            .foregroundColor(.brandAccentWarm)
                    }
                    Text(LinkaCopy.value("mac.optimize.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                macBaselineRibbon

                macProfileChoices

                macOptimizationChecklist

                macInsightCard

                macFooterAction
                    .padding(.top, 4)

                Divider().padding(.vertical, 8)

                macSection(title: LinkaCopy.value("optimization.mac.measurementContext")) {
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
                                title: LinkaCopy.value("optimization.mac.dns.title"),
                                detail: LinkaCopy.value("optimization.mac.dns.detail")
                            )
                        }
                    } else {
                        Button(action: onRequestPurchase) {
                            macSecondaryAction(
                                title: LinkaCopy.value("optimization.mac.dns.title"),
                                detail: LinkaCopy.value("optimization.mac.dns.plusDetail")
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(36)
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
        .sheet(isPresented: $showBaselineTechnicalDetails) {
            NavigationStack {
                MeasurementDetailView(measurement: baseline, duration: nil)
            }
            .frame(minWidth: 640, minHeight: 520)
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

    private var macBaselineRibbon: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.brandAccentWarm.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "gauge.medium")
                    .font(.system(size: 18))
                    .foregroundColor(.brandAccentWarm)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(LinkaCopy.value("mac.optimize.baseline.title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(baselineSummaryLine)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Button(LinkaCopy.value("assist.technicalDetails")) {
                showBaselineTechnicalDetails = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.brandAccentWarm)
        }
        .padding(14)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
        )
    }

    private var baselineSummaryLine: String {
        let down = baseline.downloadMbps.map { "\(localizedNumber($0, fractionDigits: 1)) Mbps ↓" } ?? ""
        let lat = baseline.latencyMs.map { "\(Int(round($0))) ms" } ?? ""
        let band = baseline.wifiContext?.bandDisplay ?? (baseline.connectionKind == .wifi ? "Wi-Fi" : "Cabo")
        return [down, lat, band].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var macProfileChoices: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LinkaCopy.value("mac.optimize.profile.prompt"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textPrimary)

            HStack(spacing: 10) {
                profileButton(id: "general", label: LinkaCopy.value("mac.optimize.profile.general"), icon: "wifi")
                profileButton(id: "videoCall", label: LinkaCopy.value("mac.optimize.profile.videoCall"), icon: "video")
                profileButton(id: "gaming", label: LinkaCopy.value("mac.optimize.profile.gaming"), icon: "gamecontroller")
                profileButton(id: "transfers", label: LinkaCopy.value("mac.optimize.profile.transfers"), icon: "arrow.down.circle")
            }
        }
    }

    private func profileButton(id: String, label: String, icon: String) -> some View {
        let isSelected = selectedProfile == id
        return Button {
            selectedProfile = id
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .brandAccentWarm : .textSecondary)
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .brandAccentWarm : .textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? Color.brandAccentWarm.opacity(0.12) : Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                    .stroke(isSelected ? Color.brandAccentWarm : Color.borderDefault.opacity(0.35), lineWidth: isSelected ? 1.5 : 0.6)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mac.optimize.profile.\(id)")
    }

    private var macOptimizationChecklist: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(LinkaCopy.value("mac.optimize.checklist.title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(String(format: LinkaCopy.value("mac.optimize.checklist.progress"), checklistChecked.filter { $0 }.count))
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.brandAccentWarm.opacity(0.12), in: Capsule())
                    .foregroundColor(.brandAccentWarm)
            }

            VStack(spacing: 0) {
                checklistRow(
                    index: 0,
                    title: LinkaCopy.value("mac.optimize.checklist.step1.title"),
                    desc: LinkaCopy.value("mac.optimize.checklist.step1.desc")
                )
                Divider().padding(.vertical, 8)
                checklistRow(
                    index: 1,
                    title: LinkaCopy.value("mac.optimize.checklist.step2.title"),
                    desc: dynamicStep2Description
                )
                Divider().padding(.vertical, 8)
                checklistRow(
                    index: 2,
                    title: LinkaCopy.value("mac.optimize.checklist.step3.title"),
                    desc: LinkaCopy.value("mac.optimize.checklist.step3.desc")
                )
            }
        }
        .padding(18)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
        )
    }

    private var dynamicStep2Description: String {
        switch selectedProfile {
        case "videoCall": return LinkaCopy.value("mac.optimize.checklist.step2.desc.videoCall")
        case "gaming": return LinkaCopy.value("mac.optimize.checklist.step2.desc.gaming")
        case "transfers": return LinkaCopy.value("mac.optimize.checklist.step2.desc.transfers")
        default: return LinkaCopy.value("mac.optimize.checklist.step2.desc.general")
        }
    }

    private func checklistRow(index: Int, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                checklistChecked[index].toggle()
            } label: {
                Image(systemName: checklistChecked[index] ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundColor(checklistChecked[index] ? .brandAccentWarm : .textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mac.optimize.checkbox.\(index)")

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            checklistChecked[index].toggle()
        }
    }

    private var macInsightCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.brandAccentWarm.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 16))
                    .foregroundColor(.brandAccentWarm)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(LinkaCopy.value("mac.optimize.insight.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(LinkaCopy.value("mac.optimize.insight.desc"))
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
        )
    }

    private var macFooterAction: some View {
        let isReady = checklistChecked.allSatisfy { $0 }
        return HStack {
            Text(isReady ? LinkaCopy.value("mac.optimize.ready") : LinkaCopy.value("mac.optimize.notReady"))
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)

            Spacer()

            Button {
                dismiss()
                onRetest()
            } label: {
                HStack(spacing: 6) {
                    Text(LinkaCopy.value("mac.optimize.retestAction"))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandAccentWarm)
            .disabled(!isReady)
            .accessibilityIdentifier("mac.optimize.retestButton")
        }
    }

    private func localizedNumber(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(fractionDigits))
                .locale(LinkaLanguagePreference.currentLocale)
        )
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
