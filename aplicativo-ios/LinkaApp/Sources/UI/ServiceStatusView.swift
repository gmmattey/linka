import SwiftUI

struct ServiceStatusView: View {
    @EnvironmentObject private var store: ServiceStatusStore
    @State private var query = ""
    @State private var expandedIncidentIDs: Set<String> = []

    private var visibleServices: [LinkaService] {
        guard !query.isEmpty else { return store.services }
        return store.services.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var groupedServices: [(category: String, services: [LinkaService])] {
        let grouped = Dictionary(grouping: visibleServices, by: \.category)
        let sortedKeys = grouped.keys.sorted { categoryPriority($0) < categoryPriority($1) }
        return sortedKeys.map { ($0, grouped[$0] ?? []) }
    }

    private func categoryPriority(_ category: String) -> (Int, String) {
        let order: [String: Int] = [
            "Mensagens": 0,
            "Redes Sociais": 1,
            "Jogos": 2,
            "Produtividade": 3,
            "IA": 4,
            "Infraestrutura": 5,
        ]
        return (order[category] ?? 99, category)
    }

    var body: some View {
        #if os(macOS)
        macOSContent
        #else
        iOSContent
        #endif
    }

    private var iOSContent: some View {
        List {
            if let error = store.lastError {
                Text(error).foregroundStyle(.secondary)
            }
            if visibleServices.isEmpty && !store.isLoading {
                emptyState
            } else {
                ForEach(groupedServices, id: \.category) { group in
                    Section(header: Text(LinkaCopy.value(group.category))) {
                        ForEach(group.services) { service in
                            iOSServiceRow(service)
                        }
                    }
                }
            }
        }
        .linkaGradientScreenBackground()
        .searchable(text: $query, prompt: LinkaCopy.value("serviceStatus.search"))
        .navigationTitle(LinkaCopy.value("serviceStatus.title"))
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right").font(.title2).foregroundStyle(.secondary)
            Text(LinkaCopy.value("serviceStatus.empty.title")).font(.headline)
            Text(LinkaCopy.value("serviceStatus.empty.detail")).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private func iOSServiceRow(_ service: LinkaService) -> some View {
        let incident = store.incident(for: service)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: service.sfSymbolName)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(service.name)
                    Text(statusText(for: service)).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(serviceFormat("serviceStatus.notifications", service.name), isOn: Binding(
                    get: { store.isFollowing(service) },
                    set: { enabled in Task { await store.setFollowing(service, enabled: enabled) } }
                ))
                .labelsHidden()
                .tint(.brandAccentWarm)
                .disabled(!service.notificationEligible || !service.monitoringEnabled)
            }
            .accessibilityElement(children: .combine)

            if let incident {
                DisclosureGroup(LinkaCopy.value("serviceStatus.incident"), isExpanded: incidentExpansion(for: incident.id)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(incident.title).font(.footnote.weight(.medium))
                        Text(incident.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    #if os(macOS)
    private var macOSContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LinkaCopy.value("serviceStatus.title"))
                        .font(.title.weight(.bold))
                    Text(LinkaCopy.value("serviceStatus.subtitle"))
                        .foregroundStyle(.secondary)
                }

                if let error = store.lastError {
                    macCard {
                        Text(error)
                            .foregroundStyle(.secondary)
                    }
                }

                if visibleServices.isEmpty && !store.isLoading {
                    macCard {
                        emptyState
                    }
                } else {
                    ForEach(groupedServices, id: \.category) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(LinkaCopy.value(group.category))
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)

                            macCard {
                                ForEach(group.services) { service in
                                    macServiceRow(service)
                                    if service.id != group.services.last?.id { Divider() }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(40)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .searchable(text: $query, prompt: LinkaCopy.value("serviceStatus.search"))
        .navigationTitle(LinkaCopy.value("serviceStatus.title"))
        .task { await store.refresh() }
    }

    private func macCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
    }

    private func macServiceRow(_ service: LinkaService) -> some View {
        let incident = store.incident(for: service)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: service.sfSymbolName)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(service.name)
                        .font(.body.weight(.medium))
                    Text(macStatusSummary(for: service))
                        .font(.footnote)
                        .foregroundStyle(service.monitoringEnabled && incident == nil ? Color.statusGood : .secondary)
                }
                Spacer()
                Toggle(serviceFormat("serviceStatus.notifications", service.name), isOn: Binding(
                    get: { store.isFollowing(service) },
                    set: { enabled in Task { await store.setFollowing(service, enabled: enabled) } }
                ))
                .labelsHidden()
                .tint(.brandAccentWarm)
                .disabled(!service.notificationEligible || !service.monitoringEnabled)
            }
            .accessibilityElement(children: .combine)

            if let incident {
                DisclosureGroup(LinkaCopy.value("serviceStatus.incident"), isExpanded: incidentExpansion(for: incident.id)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(incident.title)
                            .font(.footnote.weight(.medium))
                        Text(incident.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func macStatusSummary(for service: LinkaService) -> String {
        guard service.monitoringEnabled else { return LinkaCopy.value("serviceStatus.monitoringUnavailable") }
        guard let incident = store.incident(for: service) else { return LinkaCopy.value("serviceStatus.operatingNormally") }
        switch incident.severity.lowercased() {
        case "critical", "major", "high": return LinkaCopy.value("serviceStatus.instability")
        default: return LinkaCopy.value("serviceStatus.update")
        }
    }
    #endif

    private func incidentExpansion(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedIncidentIDs.contains(id) },
            set: { isExpanded in
                if isExpanded { expandedIncidentIDs.insert(id) }
                else { expandedIncidentIDs.remove(id) }
            }
        )
    }

    private func statusText(for service: LinkaService) -> String {
        guard service.monitoringEnabled else { return LinkaCopy.value("serviceStatus.monitoringUnavailable") }
        guard let incident = store.incident(for: service) else { return LinkaCopy.value("serviceStatus.operatingNormally") }
        switch incident.confidence {
        case "high": return incident.summary
        default: return serviceFormat("serviceStatus.instability.detail", incident.summary)
        }
    }

    private func serviceFormat(_ key: String, _ value: String) -> String {
        String(format: LinkaCopy.value(key), locale: LinkaLanguagePreference.currentLocale, value)
    }
}
