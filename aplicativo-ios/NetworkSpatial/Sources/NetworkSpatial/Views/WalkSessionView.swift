import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
public struct WalkSessionView: View {
    @ObservedObject var viewModel: WalkSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var didTapLocation: Bool = false

    public init(viewModel: WalkSessionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                WiFiCasaTheme.backgroundBase.ignoresSafeArea()

                switch viewModel.state {
                case .intro(let totalRooms):
                    introView(totalRooms: totalRooms)
                case .guidingToRoom(let room, let stepIndex, let totalSteps):
                    guidingView(room: room, stepIndex: stepIndex, totalSteps: totalSteps)
                case .measuring(let room, let stepIndex, let totalSteps, let step, let progress):
                    measuringView(room: room, stepIndex: stepIndex, totalSteps: totalSteps, step: step, progress: progress)
                case .roomCompleted(let room, let stepIndex, let totalSteps, let result, let nextRoom):
                    roomCompletedView(room: room, stepIndex: stepIndex, totalSteps: totalSteps, result: result, nextRoom: nextRoom)
                case .sessionSummary(let summary):
                    sessionSummaryView(summary: summary)
                }
            }
            .navigationTitle("")
            .inlineTitleDisplayMode()
            .toolbar {
                toolbarItems()
            }
        }
    }

    // MARK: - 1. Tela de Introdução e Preparação

    private func introView(totalRooms: Int) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(WiFiCasaTheme.brandAccentSubtle)
                    .frame(width: 130, height: 130)

                Image(systemName: "figure.walk.motion")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(WiFiCasaTheme.brandAccent)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(viewModel.session.mode.actionTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(WiFiCasaTheme.textPrimary)

                Text("Vamos caminhar por \(totalRooms) cômodos na ordem mais eficiente pela sua casa.")
                    .font(.subheadline)
                    .foregroundStyle(WiFiCasaTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(WiFiCasaTheme.brandAccent)
                        .frame(width: 24)
                    Text("1 toque por cômodo quando estiver no local")
                        .font(.footnote)
                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                    Spacer()
                }

                HStack(spacing: 12) {
                    Image(systemName: "timer")
                        .foregroundStyle(WiFiCasaTheme.brandAccent)
                        .frame(width: 24)
                    Text("Duração estimada: cerca de 2 minutos")
                        .font(.footnote)
                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                    Spacer()
                }

                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(WiFiCasaTheme.brandAccent)
                        .frame(width: 24)
                    Text("Detecção inteligente de pontos de acesso Wi-Fi")
                        .font(.footnote)
                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                    Spacer()
                }
            }
            .padding(16)
            .background(WiFiCasaTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24)

            Spacer()

            Button {
                viewModel.startWalk()
            } label: {
                HStack(spacing: 8) {
                    Text("Começar Caminhada")
                    Image(systemName: "arrow.right")
                }
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(WiFiCasaTheme.brandAccent)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - 2. Tela de Deslocamento ("Vá até o cômodo")

    private func guidingView(room: Room, stepIndex: Int, totalSteps: Int) -> some View {
        VStack(spacing: 20) {
            // Barra de progresso da caminhada
            VStack(spacing: 6) {
                HStack {
                    Text("\(stepIndex) de \(totalSteps) · \(room.name)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(WiFiCasaTheme.brandAccent)
                    Spacer()
                    Text("Passo a passo")
                        .font(.caption2)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                }
                ProgressView(value: Double(stepIndex - 1), total: Double(totalSteps))
                    .progressViewStyle(.linear)
                    .tint(WiFiCasaTheme.brandAccent)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            Spacer()

            // Ícone do cômodo em destaque
            ZStack {
                Circle()
                    .fill(WiFiCasaTheme.backgroundRaised)
                    .frame(width: 140, height: 140)

                Image(systemName: room.icon)
                    .font(.system(size: 64))
                    .foregroundStyle(WiFiCasaTheme.brandAccent)
            }
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text(room.name)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(WiFiCasaTheme.textPrimary)

                if room.hasRouter {
                    Label("Roteador Principal instalado aqui", systemImage: "router.fill")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(WiFiCasaTheme.brandAccent)
                }

                Text(room.hasRouter ? "Vá até a \(room.name), próximo ao roteador." : "Caminhe até a \(room.name).")
                    .font(.subheadline)
                    .foregroundStyle(WiFiCasaTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let error = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(WiFiCasaTheme.scoreFair)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                }
                .padding(.horizontal, 24)
            }

            Spacer()

            VStack(spacing: 12) {
                Text("📍 Quando estiver no local:")
                    .font(.footnote)
                    .foregroundStyle(WiFiCasaTheme.textSecondary)

                Button {
                    didTapLocation.toggle()
                    viewModel.confirmAtLocation()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Estou aqui")
                    }
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(WiFiCasaTheme.brandAccent)
                .sensoryFeedback(.impact, trigger: didTapLocation)

                Button {
                    viewModel.skipCurrentRoom()
                } label: {
                    Text("Pular este cômodo")
                        .font(.subheadline)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    // MARK: - 3. Tela de Medição Ativa no Cômodo

    private func measuringView(
        room: Room,
        stepIndex: Int,
        totalSteps: Int,
        step: DiagnosticStep,
        progress: Double
    ) -> some View {
        VStack(spacing: 24) {
            // Progresso superior
            VStack(spacing: 6) {
                HStack {
                    Text("\(stepIndex) de \(totalSteps) · Medindo \(room.name)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(WiFiCasaTheme.brandAccent)
                    Spacer()
                }
                ProgressView(value: Double(stepIndex - 1) + progress, total: Double(totalSteps))
                    .progressViewStyle(.linear)
                    .tint(WiFiCasaTheme.brandAccent)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            Spacer()

            // Pulso Wi-Fi
            ZStack {
                Circle()
                    .fill(WiFiCasaTheme.brandAccentSubtle)
                    .frame(width: 140, height: 140)

                Circle()
                    .stroke(WiFiCasaTheme.brandAccent.opacity(0.3), lineWidth: 2)
                    .frame(width: 110, height: 110)

                Image(systemName: "wifi")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(WiFiCasaTheme.brandAccent)
            }
            .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Medindo \(room.name)…")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(WiFiCasaTheme.textPrimary)

                Text(step.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(WiFiCasaTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Checklist visual de micro-etapas (Roteador, Estabilidade, Internet)
            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Image(systemName: progress >= 0.45 ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(progress >= 0.45 ? WiFiCasaTheme.scoreExcellent : WiFiCasaTheme.textSecondary)
                    Text("Roteador")
                        .font(.caption)
                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                }

                HStack(spacing: 6) {
                    Image(systemName: progress >= 0.70 ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(progress >= 0.70 ? WiFiCasaTheme.scoreExcellent : WiFiCasaTheme.textSecondary)
                    Text("Estabilidade")
                        .font(.caption)
                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                }

                HStack(spacing: 6) {
                    Image(systemName: progress >= 0.95 ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(progress >= 0.95 ? WiFiCasaTheme.scoreExcellent : WiFiCasaTheme.textSecondary)
                    Text("Internet")
                        .font(.caption)
                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(WiFiCasaTheme.backgroundRaised)
            .clipShape(Capsule())

            Spacer()

            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(WiFiCasaTheme.brandAccent)
                .padding(.horizontal, 40)
                .padding(.bottom, 24)
        }
    }

    // MARK: - 4. Conclusão Rápida do Cômodo (Sem Card Soup!)

    private func roomCompletedView(
        room: Room,
        stepIndex: Int,
        totalSteps: Int,
        result: MeasurementResult,
        nextRoom: Room?
    ) -> some View {
        VStack(spacing: 24) {
            // Progresso superior
            VStack(spacing: 6) {
                HStack {
                    Text("\(stepIndex) de \(totalSteps) Concluído")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.ratingColor(for: result.rating))
                    Spacer()
                }
                ProgressView(value: Double(stepIndex), total: Double(totalSteps))
                    .progressViewStyle(.linear)
                    .tint(WiFiCasaTheme.brandAccent)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            Spacer()

            // Card Conciso de Conclusão (Sem Bordas, Profundidade Tonal)
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: result.rating.systemImage)
                        .font(.system(size: 40))
                        .foregroundStyle(Color.ratingColor(for: result.rating))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(room.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(WiFiCasaTheme.textPrimary)

                        Text("\(result.rating.label) · \(result.score) pts")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.ratingColor(for: result.rating))
                    }

                    Spacer()
                }

                Divider()
                    .overlay(WiFiCasaTheme.textSecondary.opacity(0.15))

                HStack {
                    Label(result.diagnosisTag.rawValue, systemImage: result.diagnosisTag.systemImage)
                        .font(.subheadline)
                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                    Spacer()
                    Text("Latência: \(String(format: "%.1f", result.metrics.gatewayMedianMs ?? result.metrics.gatewayLatencyMs)) ms")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                }
            }
            .padding(20)
            .background(WiFiCasaTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 24)

            // Prévia do próximo cômodo
            if let next = nextRoom {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(WiFiCasaTheme.brandAccent)
                    Text("Próximo cômodo: \(next.name)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(WiFiCasaTheme.brandAccent)
                    Text("Todos os cômodos foram visitados!")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                }
            }

            Spacer()

            Button {
                viewModel.continueWalk()
            } label: {
                HStack(spacing: 8) {
                    Text(nextRoom != nil ? "Continuar caminhada" : "Ver resultado final")
                    Image(systemName: "arrow.right")
                }
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(WiFiCasaTheme.brandAccent)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .sensoryFeedback(.success, trigger: stepIndex)
    }

    // MARK: - 5. Resumo Consolidado da Casa

    private func sessionSummaryView(summary: WalkSessionSummary) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(WiFiCasaTheme.brandAccentSubtle)
                    .frame(width: 120, height: 120)

                Image(systemName: "house.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(WiFiCasaTheme.brandAccent)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Mapeamento Concluído")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(WiFiCasaTheme.textPrimary)

                Text("Qualidade Média nos Pontos Medidos")
                    .font(.subheadline)
                    .foregroundStyle(WiFiCasaTheme.textSecondary)

                Text("\(summary.houseCoverageScore) / 100")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WiFiCasaTheme.textPrimary)
            }

            // Comparativo Antes × Depois (se ativo)
            if let baseline = summary.baselineCoverageScore, let delta = summary.deltaScore {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.swap")
                        .foregroundStyle(delta >= 0 ? WiFiCasaTheme.scoreExcellent : WiFiCasaTheme.scorePoor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Evolução da Qualidade")
                            .font(.caption)
                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                        Text("Antes \(baseline)% → Depois \(summary.houseCoverageScore)% (\(delta >= 0 ? "+" : "")\(delta)%)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(delta >= 0 ? WiFiCasaTheme.scoreExcellent : WiFiCasaTheme.scorePoor)
                    }
                    Spacer()
                }
                .padding(14)
                .background(WiFiCasaTheme.backgroundRaised)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 24)
            }

            // Detalhamento dos cômodos
            VStack(spacing: 10) {
                if summary.excellentCount > 0 {
                    HStack {
                        Label("\(summary.excellentCount) cômodo(s) com conexão ótima", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(WiFiCasaTheme.scoreExcellent)
                        Spacer()
                    }
                    .font(.footnote)
                }

                if summary.goodCount > 0 {
                    HStack {
                        Label("\(summary.goodCount) cômodo(s) com conexão boa", systemImage: "checkmark.circle")
                            .foregroundStyle(WiFiCasaTheme.scoreGood)
                        Spacer()
                    }
                    .font(.footnote)
                }

                if summary.fairCount > 0 {
                    HStack {
                        Label("\(summary.fairCount) cômodo(s) com conexão regular", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(WiFiCasaTheme.scoreFair)
                        Spacer()
                    }
                    .font(.footnote)
                }

                if summary.poorCount > 0 {
                    HStack {
                        Label("\(summary.poorCount) ponto(s) crítico(s)", systemImage: "xmark.octagon.fill")
                            .foregroundStyle(WiFiCasaTheme.scorePoor)
                        Spacer()
                    }
                    .font(.footnote)
                }

                if summary.detectedAccessPointsCount > 0 {
                    Divider()
                        .overlay(WiFiCasaTheme.textSecondary.opacity(0.15))
                    HStack {
                        Label("\(summary.detectedAccessPointsCount) ponto(s) de acesso detectado(s)", systemImage: "router.fill")
                            .foregroundStyle(WiFiCasaTheme.brandAccent)
                        Spacer()
                    }
                    .font(.footnote)
                }
            }
            .padding(16)
            .background(WiFiCasaTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24)

            Spacer()

            Button {
                viewModel.cancelSession()
                dismiss()
            } label: {
                Text("Ver resultado no mapa")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(WiFiCasaTheme.brandAccent)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbarItems() -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            switch viewModel.state {
            case .intro:
                Button("Fechar") {
                    viewModel.cancelSession()
                    dismiss()
                }
            case .sessionSummary:
                EmptyView()
            default:
                Button("Encerrar por agora") {
                    viewModel.finishEarly()
                }
                .font(.footnote)
                .foregroundStyle(WiFiCasaTheme.textSecondary)
            }
        }
    }
}

