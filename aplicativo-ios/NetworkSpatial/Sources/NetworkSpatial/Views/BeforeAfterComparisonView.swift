import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
public struct BeforeAfterComparisonView: View {
    public let currentHouse: House
    public let dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: BeforeAfterViewModel
    @State private var showingSavedToast: Bool = false

    public init(currentHouse: House, dataStore: DataStore) {
        self.currentHouse = currentHouse
        self.dataStore = dataStore
        self._viewModel = StateObject(wrappedValue: BeforeAfterViewModel(dataStore: dataStore, initialRooms: currentHouse.rooms))
    }

    public var body: some View {
        NavigationStack {
            List {
                switch viewModel.currentStep {
                case .selectBaseline:
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.swap")
                                    .font(.title2)
                                    .foregroundStyle(WiFiCasaTheme.brandAccent)
                                Text("Comparativo Antes × Depois")
                                    .font(.headline)
                                    .foregroundStyle(WiFiCasaTheme.textPrimary)
                            }

                            Text("Fixe o estado atual da sua casa como ponto de partida (Antes). Em seguida, mude o roteador de lugar ou instale nós mesh para comprovar o ganho real de sinal.")
                                .font(.subheadline)
                                .foregroundStyle(WiFiCasaTheme.textSecondary)

                            Button {
                                viewModel.setBaselineFromCurrentHouse(currentHouse)
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("Definir Leituras Atuais como Baseline (Antes)")
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(WiFiCasaTheme.brandAccent)
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 8)
                    }

                case .repositionPrompt:
                    Section {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Passo 2: Reposicionar e Re-medir", systemImage: "arrow.left.and.right.circle.fill")
                                .font(.headline)
                                .foregroundStyle(WiFiCasaTheme.brandAccent)

                            Text("1. Mova fisicamente o roteador (ex: aproxime do corredor ou eleve a altura) ou ligue o repetidor/mesh.\n2. Aguarde 1 minuto para o sinal se estabilizar.\n3. Vá ao mapa para realizar a nova rodada de testes nos cômodos.")
                                .font(.subheadline)
                                .foregroundStyle(WiFiCasaTheme.textPrimary)

                            VStack(spacing: 10) {
                                Button {
                                    dismiss()
                                } label: {
                                    HStack {
                                        Spacer()
                                        Label("Ir ao Mapa para Medir", systemImage: "map.fill")
                                            .fontWeight(.semibold)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(WiFiCasaTheme.brandAccent)

                                Button("Já Realizei as Medições — Comparar") {
                                    viewModel.finalizeComparison(with: currentHouse.rooms)
                                }
                                .buttonStyle(.bordered)
                                .tint(WiFiCasaTheme.brandAccent)

                                Button("Descartar Baseline", role: .destructive) {
                                    viewModel.cancelOrResetBaseline()
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundStyle(WiFiCasaTheme.scorePoor)
                                .padding(.top, 4)
                            }
                            .padding(.top, 6)
                        }
                        .padding(.vertical, 6)
                    }

                case .measureAfter:
                    Section {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: "clock.badge.checkmark.fill")
                                    .font(.title2)
                                    .foregroundStyle(WiFiCasaTheme.brandAccent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Baseline 'Antes' Ativo")
                                        .font(.headline)
                                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                                    Text("\(viewModel.baselineRooms.count) cômodos registrados no ponto de partida.")
                                        .font(.caption)
                                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                                }
                            }

                            Text("Com o roteador no novo local, caminhe pelos cômodos e realize novas medições na tela inicial. Quando terminar, gere o comparativo.")
                                .font(.subheadline)
                                .foregroundStyle(WiFiCasaTheme.textPrimary)

                            VStack(spacing: 10) {
                                Button {
                                    viewModel.finalizeComparison(with: currentHouse.rooms)
                                } label: {
                                    HStack {
                                        Spacer()
                                        Label("Gerar Comparativo com Leituras Atuais", systemImage: "sparkles")
                                            .fontWeight(.semibold)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .tint(WiFiCasaTheme.brandAccent)

                                Button {
                                    dismiss()
                                } label: {
                                    HStack {
                                        Spacer()
                                        Text("Continuar Medindo no Mapa")
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(WiFiCasaTheme.brandAccent)

                                Button("Descartar e Iniciar Novo Baseline", role: .destructive) {
                                    viewModel.cancelOrResetBaseline()
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundStyle(WiFiCasaTheme.scorePoor)
                                .padding(.top, 4)
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 6)
                    }

                case .comparisonReady:
                    if let result = viewModel.comparisonResult {
                        // Resumo do Ganho Consolidado
                        Section {
                            VStack(spacing: 16) {
                                Text("EVOLUÇÃO DA QUALIDADE MÉDIA")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(WiFiCasaTheme.textSecondary)

                                HStack(spacing: 20) {
                                    VStack {
                                        Text("Antes")
                                            .font(.caption)
                                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                                        Text("\(result.baselineCoveragePercent)%")
                                            .font(.title)
                                            .fontWeight(.bold)
                                            .foregroundStyle(WiFiCasaTheme.textPrimary)
                                            .monospacedDigit()
                                    }

                                    Image(systemName: "arrow.right")
                                        .font(.title3)
                                        .foregroundStyle(WiFiCasaTheme.textSecondary)

                                    VStack {
                                        Text("Depois")
                                            .font(.caption)
                                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                                        Text("\(result.afterCoveragePercent)%")
                                            .font(.title)
                                            .fontWeight(.bold)
                                            .monospacedDigit()
                                            .foregroundStyle(WiFiCasaTheme.scoreExcellent)
                                    }
                                }

                                HStack(spacing: 6) {
                                    Image(systemName: result.deltaCoveragePercent >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                    Text("\(result.deltaCoveragePercent >= 0 ? "+" : "")\(result.deltaCoveragePercent)% na Qualidade Média Medida")
                                        .fontWeight(.semibold)
                                }
                                .font(.subheadline)
                                .foregroundStyle(result.deltaCoveragePercent >= 0 ? WiFiCasaTheme.scoreExcellent : WiFiCasaTheme.scorePoor)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(result.deltaCoveragePercent >= 0 ? WiFiCasaTheme.scoreExcellentSubtle : WiFiCasaTheme.scorePoorSubtle)
                                .clipShape(Capsule())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }

                        // Comparativo Cômodo por Cômodo
                        Section(header: Text("COMPARAÇÃO POR CÔMODO")) {
                            ForEach(result.roomComparisons) { item in
                                HStack {
                                    Image(systemName: item.roomIcon)
                                        .font(.title3)
                                        .foregroundStyle(Color.ratingColor(for: item.afterRating))
                                        .frame(width: 32)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.roomName)
                                            .font(.headline)
                                            .foregroundStyle(WiFiCasaTheme.textPrimary)

                                        HStack(spacing: 4) {
                                            Text(item.beforeRating.label)
                                                .font(.caption)
                                                .foregroundStyle(WiFiCasaTheme.textSecondary)
                                            Image(systemName: "arrow.right")
                                                .font(.caption2)
                                                .foregroundStyle(WiFiCasaTheme.textSecondary)
                                            Text(item.afterRating.label)
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(Color.ratingColor(for: item.afterRating))
                                        }
                                    }

                                    Spacer()

                                    HStack(spacing: 3) {
                                        Text("\(item.beforeScore)")
                                            .font(.subheadline)
                                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                                            .monospacedDigit()
                                        Text("→")
                                            .font(.caption)
                                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                                        Text("\(item.afterScore)")
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .monospacedDigit()
                                            .foregroundStyle(item.deltaScore >= 0 ? WiFiCasaTheme.scoreExcellent : WiFiCasaTheme.scorePoor)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        // Ações de Salvar
                        Section {
                            Button {
                                viewModel.saveComparisonToHistory()
                                showingSavedToast = true
                            } label: {
                                HStack {
                                    Spacer()
                                    Label(viewModel.isSaved ? "Salvo no Histórico" : "Salvar no Histórico", systemImage: viewModel.isSaved ? "checkmark" : "square.and.arrow.down")
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                            }
                            .disabled(viewModel.isSaved)
                            .tint(WiFiCasaTheme.brandAccent)
                        }
                    }
                }
            }
            .appListStyle()
            .navigationTitle("Antes × Depois")
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
        }
    }
}
