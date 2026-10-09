import SwiftUI
import NetworkInventory

struct ServicePlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: LinkaInventoryStore

    let plan: NetworkServicePlan?

    @State private var ispName: String
    @State private var planName: String
    @State private var technology: AccessTechnology
    @State private var downloadSpeedText: String
    @State private var uploadSpeedText: String
    @State private var monthlyCostText: String
    @State private var notes: String

    @State private var saving = false
    @State private var confirmDiscard = false
    @State private var confirmReplace = false
    @State private var confirmDelete = false
    @State private var validationError: String?

    init(plan: NetworkServicePlan?, store: LinkaInventoryStore) {
        self.plan = plan
        self.store = store

        _ispName = State(initialValue: plan?.ispName ?? "")
        _planName = State(initialValue: plan?.planName ?? "")
        _technology = State(initialValue: plan?.technology ?? .fiber)
        _downloadSpeedText = State(initialValue: plan?.nominalDownloadMbps.map { Self.formatSpeed($0) } ?? "")
        _uploadSpeedText = State(initialValue: plan?.nominalUploadMbps.map { Self.formatSpeed($0) } ?? "")
        _monthlyCostText = State(initialValue: plan?.monthlyCostCents.map { Self.formatCost($0) } ?? "")
        _notes = State(initialValue: plan?.notes ?? "")
    }

    private var isNewPlan: Bool {
        plan == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                cellularNoticeSection

                providerSection

                speedsSection

                costAndDetailsSection

                if let error = validationError ?? store.error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                actionsSection
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle(LinkaCopy.value(isNewPlan ? "inventory.plan.add" : "inventory.plan.edit"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LinkaCopy.value("common.cancel")) {
                        if hasUnsavedChanges {
                            confirmDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(saving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(LinkaCopy.value(isNewPlan ? "inventory.plan.save" : "inventory.plan.saveCorrections")) {
                        savePlanInPlace()
                    }
                    .disabled(!canSave || saving)
                    .accessibilityIdentifier("inventory.plan.saveButton")
                }
            }
            .interactiveDismissDisabled(saving || hasUnsavedChanges)
            .alert(LinkaCopy.value("inventory.discard.title"), isPresented: $confirmDiscard) {
                Button(LinkaCopy.value("inventory.discard"), role: .destructive) { dismiss() }
                Button(LinkaCopy.value("inventory.keepEditing"), role: .cancel) {}
            } message: {
                Text(LinkaCopy.value("inventory.discard.message"))
            }
            .alert(LinkaCopy.value("inventory.plan.replace.title"), isPresented: $confirmReplace) {
                Button(LinkaCopy.value("inventory.plan.replace.confirm")) {
                    replacePlanWithNew()
                }
                Button(LinkaCopy.value("common.cancel"), role: .cancel) {}
            } message: {
                Text(LinkaCopy.value("inventory.plan.replace.message"))
            }
            .alert(LinkaCopy.value("inventory.plan.delete.title"), isPresented: $confirmDelete) {
                Button(LinkaCopy.value("inventory.delete"), role: .destructive) {
                    deletePlan()
                }
                Button(LinkaCopy.value("common.cancel"), role: .cancel) {}
            } message: {
                Text(LinkaCopy.value("inventory.plan.delete.message"))
            }
        }
    }

    // MARK: - Sections

    private var cellularNoticeSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.body)
                    .foregroundStyle(.tint)
                    .padding(.top, 2)
                Text(LinkaCopy.value("inventory.plan.notice"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    private var providerSection: some View {
        Section(LinkaCopy.value("inventory.plan.isp")) {
            TextField(LinkaCopy.value("inventory.plan.isp.placeholder"), text: $ispName)
                .accessibilityIdentifier("inventory.plan.ispInput")

            TextField(LinkaCopy.value("inventory.plan.name.placeholder"), text: $planName)
                .accessibilityIdentifier("inventory.plan.nameInput")

            Picker(LinkaCopy.value("inventory.plan.technology"), selection: $technology) {
                ForEach(AccessTechnology.allCases, id: \.self) { tech in
                    Text(technologyLabel(tech)).tag(tech)
                }
            }
            .accessibilityIdentifier("inventory.plan.technologyPicker")
        }
    }

    private var speedsSection: some View {
        Section(LinkaCopy.value("inventory.plan.speeds")) {
            HStack {
                Text(LinkaCopy.value("inventory.plan.download"))
                    .font(.subheadline)
                Spacer()
                TextField(LinkaCopy.value("inventory.plan.download.placeholder"), text: $downloadSpeedText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                    .accessibilityIdentifier("inventory.plan.downloadInput")
            }

            HStack {
                Text(LinkaCopy.value("inventory.plan.upload"))
                    .font(.subheadline)
                Spacer()
                TextField(LinkaCopy.value("inventory.plan.upload.placeholder"), text: $uploadSpeedText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                    .accessibilityIdentifier("inventory.plan.uploadInput")
            }
        }
    }

    private var costAndDetailsSection: some View {
        Section {
            HStack {
                Text(LinkaCopy.value("inventory.plan.cost"))
                    .font(.subheadline)
                Spacer()
                TextField(LinkaCopy.value("inventory.plan.cost.placeholder"), text: $monthlyCostText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                    .accessibilityIdentifier("inventory.plan.costInput")
            }

            TextField(LinkaCopy.value("inventory.plan.notes.placeholder"), text: $notes)
                .accessibilityIdentifier("inventory.plan.notesInput")
        }
    }

    private var actionsSection: some View {
        Section {
            if !isNewPlan {
                Button(LinkaCopy.value("inventory.plan.replace")) {
                    confirmReplace = true
                }
                .disabled(!canSave || saving)
                .accessibilityIdentifier("inventory.plan.replaceButton")

                Button(LinkaCopy.value("inventory.plan.delete"), role: .destructive) {
                    confirmDelete = true
                }
                .accessibilityIdentifier("inventory.plan.deleteButton")
            }
        }
    }

    // MARK: - Validation & Helpers

    private var cleanIsp: String {
        ispName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedDownload: Double? {
        parseSpeed(downloadSpeedText)
    }

    private var parsedUpload: Double? {
        parseSpeed(uploadSpeedText)
    }

    private var parsedCostCents: Int? {
        parseCost(monthlyCostText)
    }

    private var canSave: Bool {
        guard !cleanIsp.isEmpty, cleanIsp.count <= 120 else { return false }
        if !downloadSpeedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let dl = parsedDownload, dl > 0 else { return false }
        }
        if !uploadSpeedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let ul = parsedUpload, ul > 0 else { return false }
        }
        if !monthlyCostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let cost = parsedCostCents, cost >= 0 else { return false }
        }
        return true
    }

    private var hasUnsavedChanges: Bool {
        if let original = plan {
            let originalDl = original.nominalDownloadMbps.map { Self.formatSpeed($0) } ?? ""
            let originalUl = original.nominalUploadMbps.map { Self.formatSpeed($0) } ?? ""
            let originalCost = original.monthlyCostCents.map { Self.formatCost($0) } ?? ""
            return cleanIsp != original.ispName ||
                planName != (original.planName ?? "") ||
                technology != original.technology ||
                downloadSpeedText != originalDl ||
                uploadSpeedText != originalUl ||
                monthlyCostText != originalCost ||
                notes != (original.notes ?? "")
        } else {
            return !cleanIsp.isEmpty ||
                !planName.isEmpty ||
                !downloadSpeedText.isEmpty ||
                !uploadSpeedText.isEmpty ||
                !monthlyCostText.isEmpty ||
                !notes.isEmpty
        }
    }

    private func technologyLabel(_ tech: AccessTechnology) -> String {
        LinkaCopy.value("inventory.technology.\(tech.rawValue)")
    }

    private static func formatSpeed(_ speed: Double) -> String {
        if speed.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", speed)
        }
        return String(format: "%.1f", speed)
    }

    private static func formatCost(_ cents: Int) -> String {
        let value = Double(cents) / 100.0
        return String(format: "%.2f", value)
    }

    private func parseSpeed(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    private func parseCost(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        guard let doubleVal = Double(cleaned), doubleVal >= 0 else { return nil }
        return Int((doubleVal * 100.0).rounded())
    }

    private var currentCurrencyCode: String {
        #if os(macOS)
        return Locale.current.currency?.identifier ?? "BRL"
        #else
        return Locale.current.currency?.identifier ?? "BRL"
        #endif
    }

    private func buildPlanDraft(id: UUID = UUID(), createdAt: Date = Date(), effectiveFrom: Date? = nil, effectiveTo: Date? = nil) -> NetworkServicePlan {
        let cleanPlan = planName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        return NetworkServicePlan(
            id: id,
            ispName: cleanIsp,
            planName: cleanPlan.isEmpty ? nil : cleanPlan,
            nominalDownloadMbps: parsedDownload,
            nominalUploadMbps: parsedUpload,
            technology: technology,
            monthlyCostCents: parsedCostCents,
            currencyCode: parsedCostCents != nil ? currentCurrencyCode : nil,
            notes: cleanNotes.isEmpty ? nil : cleanNotes,
            effectiveFrom: effectiveFrom,
            effectiveTo: effectiveTo,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }

    // MARK: - Actions

    private func savePlanInPlace() {
        guard canSave, !saving else { return }
        saving = true
        validationError = nil

        let targetPlan: NetworkServicePlan
        if let existing = plan {
            targetPlan = buildPlanDraft(
                id: existing.id,
                createdAt: existing.createdAt,
                effectiveFrom: existing.effectiveFrom,
                effectiveTo: existing.effectiveTo
            )
        } else {
            targetPlan = buildPlanDraft(effectiveFrom: Date())
        }

        guard targetPlan.isValid else {
            validationError = LinkaCopy.value("inventory.plan.invalidError")
            saving = false
            return
        }

        Task {
            let success = await store.savePlan(targetPlan, makeActive: true)
            saving = false
            if success {
                dismiss()
            }
        }
    }

    private func replacePlanWithNew() {
        guard let existing = plan, canSave, !saving else { return }
        saving = true
        validationError = nil

        let newPlan = buildPlanDraft(effectiveFrom: Date())
        guard newPlan.isValid else {
            validationError = LinkaCopy.value("inventory.plan.invalidError")
            saving = false
            return
        }

        Task {
            let success = await store.replacePlan(current: existing, with: newPlan, effectiveDate: Date())
            saving = false
            if success {
                dismiss()
            }
        }
    }

    private func deletePlan() {
        guard let existing = plan, !saving else { return }
        saving = true
        Task {
            let success = await store.deletePlan(id: existing.id)
            saving = false
            if success {
                dismiss()
            }
        }
    }
}
