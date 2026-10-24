import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
public struct HistoryView: View {
    public let dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var comparisons: [BeforeAfterComparison] = []

    public init(dataStore: DataStore) {
        self.dataStore = dataStore
    }

    public var body: some View {
        NavigationStack {
            Group {
                if comparisons.isEmpty {
                    ContentUnavailableView(
                        "Nenhuma Comparação Salva",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Realize medições e gere comparativos Antes × Depois para registrar a evolução da sua rede Wi-Fi.")
                    )
                } else {
                    List {
                        ForEach(comparisons) { comp in
                            Section(header: Text(comp.date.formatted(date: .abbreviated, time: .shortened))) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(comp.title)
                                            .font(.headline)
                                            .foregroundStyle(WiFiCasaTheme.textPrimary)
                                        Spacer()
                                        Text("\(comp.deltaCoveragePercent >= 0 ? "+" : "")\(comp.deltaCoveragePercent)%")
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundStyle(comp.deltaCoveragePercent >= 0 ? WiFiCasaTheme.scoreExcellent : WiFiCasaTheme.scorePoor)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(comp.deltaCoveragePercent >= 0 ? WiFiCasaTheme.scoreExcellentSubtle : WiFiCasaTheme.scorePoorSubtle)
                                            .clipShape(Capsule())
                                    }

                                    HStack(spacing: 12) {
                                        Label("\(comp.baselineCoveragePercent)% antes", systemImage: "circle")
                                            .font(.caption)
                                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                                        Label("\(comp.afterCoveragePercent)% depois", systemImage: "checkmark.circle")
                                            .font(.caption)
                                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                                    }

                                    Divider()
                                        .overlay(WiFiCasaTheme.textSecondary.opacity(0.15))
                                        .padding(.vertical, 2)

                                    ForEach(comp.roomComparisons) { r in
                                        HStack {
                                            Label(r.roomName, systemImage: r.roomIcon)
                                                .font(.caption)
                                                .foregroundStyle(WiFiCasaTheme.textPrimary)
                                            Spacer()
                                            Text("\(r.beforeRating.label) → \(r.afterRating.label)")
                                                .font(.caption2)
                                                .foregroundStyle(WiFiCasaTheme.textSecondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .appListStyle()
                }
            }
            .navigationTitle("Histórico de Otimizações")
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                self.comparisons = dataStore.fetchComparisons()
            }
        }
    }
}
