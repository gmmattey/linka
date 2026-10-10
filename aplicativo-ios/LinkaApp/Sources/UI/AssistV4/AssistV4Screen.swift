#if os(iOS)
import SwiftUI
import AssistConsultation

struct AssistV4Screen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AssistV4PresentationModel()

    var body: some View {
        NavigationStack {
            ZStack {
                LinkaScreenBackground(variant: .gradientOnly, showWaves: false).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        networkContext
                        turns
                        content
                    }
                    .padding(20)
                    .linkaAdaptiveContentWidth()
                }
            }
            .navigationTitle("Assist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Fechar") { dismiss() } } }
            .safeAreaInset(edge: .bottom) { composer }
            .onChange(of: scenePhase) { phase in
                guard phase == .background else { return }
                model.pauseForBackground()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Assist", systemImage: "sparkles")
                .font(.displayTitle)
                .foregroundColor(.textPrimary)
            Text("Seu especialista em conexões")
                .font(.bodyRegular)
                .foregroundColor(.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var networkContext: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sua rede")
                .font(.bodyRegularStrong)
            Text("Nenhum plano, equipamento ou medição foi autorizado nesta prova local.")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("assist-v4.network-context")
    }

    @ViewBuilder private var turns: some View {
        ForEach(model.turns) { turn in
            Text(turn.text)
                .font(.bodyRegular)
                .padding(12)
                .background(turn.role == .user ? Color.brandSurface.opacity(0.12) : Color.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: turn.role == .user ? .trailing : .leading)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .home:
            VStack(alignment: .leading, spacing: 12) {
                Text("Como posso ajudar?").font(.displayMedium)
                VStack(spacing: 0) {
                    shortcut("Minha internet está lenta", .slowConnection)
                    shortcut("Meu roteador é adequado?", .routerAdequacy)
                    shortcut("Preciso de uma rede Mesh?", .meshNeed)
                    shortcut("Meu plano vale a pena?", .planValue, showsDivider: false)
                }
            }
        case .planDeclaration:
            planDeclaration
        case let .guided(intent, question):
            VStack(alignment: .leading, spacing: 12) {
                if let progress = guidanceProgress(intent: intent, question: question) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Investigação local · etapa \(progress.current) de \(progress.total)")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        ProgressView(value: Double(progress.current), total: Double(progress.total))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("assist-v4.guidance-progress")
                }
                Text(question.text).font(.displayMedium)
                ForEach(question.options, id: \.id) { option in
                    Button { model.selectedOptionID = option.id } label: {
                        HStack { Image(systemName: model.selectedOptionID == option.id ? "largecircle.fill.circle" : "circle"); Text(option.text); Spacer() }
                    }
                    .buttonStyle(.plain)
                    .font(.bodyRegular)
                    .accessibilityLabel(option.text)
                    .accessibilityValue(model.selectedOptionID == option.id ? "Selecionado" : "Não selecionado")
                }
                Button("Continuar") { model.continueGuided() }
                    .buttonStyle(.linkaPrimary)
                    .disabled(model.selectedOptionID == nil)
                Button("Voltar") { model.goBackFromGuidedQuestion() }
                    .buttonStyle(.linkaSecondary)
                    .accessibilityIdentifier("assist-v4.guided.back")
                Button("Encerrar investigação") { model.cancelLocalInvestigation() }
                    .buttonStyle(.linkaSecondary)
                    .accessibilityIdentifier("assist-v4.cancel")
            }
        case let .awaitingConsent(question):
            openQuestionConsent(question)
        case .submittingOpenQuestion:
            submittingOpenQuestion
        case let .remoteUnavailable(message):
            remoteUnavailable(message)
        case let .remoteRecoverableError(message):
            remoteRecoverableError(message)
        case let .remoteResult(assessment):
            remoteResult(assessment)
        case let .unavailableOpenQuestion(text, canResumeGuidance):
            unavailableOpenQuestion(text, canResumeGuidance: canResumeGuidance)
        case let .limitation(text):
            limitation("Dados insuficientes para continuar", detail: text)
        case let .localOrientation(orientation):
            localOrientation(orientation)
        case .paused:
            pausedInvestigation
        case .cancelled:
            cancelledInvestigation
        }
    }

    private func openQuestionConsent(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Antes de enviar").font(.displayMedium)
            Text("Sua pergunta fica neste aparelho até você escolher continuar.")
                .font(.bodyRegular)
                .foregroundColor(.textSecondary)
            Text("“\(question)”")
                .font(.bodyRegular)
                .padding(12)
                .background(Color.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text("Nesta etapa, seria enviada somente a pergunta.")
                    .font(.bodyRegularStrong)
                Text("Plano, equipamentos, medições, localização, nome da rede, IP e histórico ficam de fora.")
                    .font(.bodyRegular)
                    .foregroundColor(.textSecondary)
            }
            Button("Enviar só a pergunta") { model.sendOpenQuestionOnly() }
                .buttonStyle(.linkaPrimary)
                .accessibilityIdentifier("assist-v4.consent.question-only")
            Button("Não enviar") { model.declineOpenQuestionConsent() }
                .buttonStyle(.linkaSecondary)
                .accessibilityIdentifier("assist-v4.consent.decline")
        }
    }

    private var submittingOpenQuestion: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView()
                .accessibilityLabel("Preparando consulta")
            Text("Preparando sua consulta").font(.displayMedium)
            Text("Validando a consulta autorizada antes de qualquer envio. Você pode manter esta tela aberta.")
                .font(.bodyRegular)
                .foregroundColor(.textSecondary)
        }
        .accessibilityIdentifier("assist-v4.loading")
    }

    private func remoteUnavailable(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Consulta indisponível").font(.displayMedium)
            Text(message).font(.bodyRegular).foregroundColor(.textSecondary)
            Button("Voltar às sugestões") { model.returnHome() }
                .buttonStyle(.linkaPrimary)
        }
        .accessibilityIdentifier("assist-v4.remote-unavailable")
    }

    private func remoteRecoverableError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Não foi possível concluir agora").font(.displayMedium)
            Text(message).font(.bodyRegular).foregroundColor(.textSecondary)
            Button("Tentar novamente") { model.retryOpenQuestion() }
                .buttonStyle(.linkaPrimary)
                .accessibilityIdentifier("assist-v4.remote-retry")
            Button("Voltar às sugestões") { model.returnHome() }
                .buttonStyle(.linkaSecondary)
        }
        .accessibilityIdentifier("assist-v4.remote-recoverable-error")
    }

    private func remoteResult(_ assessment: ConsultationAssessment) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Assist").font(.bodyRegularStrong)
            Text(assessment.summary).font(.displayMedium)
            if !assessment.unknowns.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("O que ainda não sabemos").font(.bodyRegularStrong)
                    ForEach(assessment.unknowns, id: \.id) { unknown in
                        Text(unknown.text).font(.bodyRegular).foregroundColor(.textSecondary)
                    }
                }
            }
            DisclosureGroup("Dados e limites desta resposta") {
                if assessment.evidenceRefs.isEmpty {
                    Text("A resposta não usa medição, plano ou equipamento.")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                } else {
                    Text("As evidências referenciadas permanecem vinculadas à sessão. A apresentação detalhada será liberada com o histórico V4.")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            }
            .font(.bodyRegularStrong)
            Button("Copiar e salvar estarão disponíveis com o histórico da consulta") {}
                .buttonStyle(.linkaSecondary)
                .disabled(true)
        }
        .accessibilityIdentifier("assist-v4.remote-result")
    }

    private func guidanceProgress(intent: ConsultationIntent, question: ConsultationQuestion) -> (current: Int, total: Int)? {
        switch intent {
        case .slowConnection:
            switch question.id.value {
            case "question-slow-location": return (1, 2)
            case "question-slow-usage": return (2, 2)
            default: return nil
            }
        case .planValue:
            switch question.id.value {
            case "question-plan-priority": return (1, 2)
            case "question-plan-satisfaction": return (2, 2)
            default: return nil
            }
        case .routerAdequacy, .meshNeed:
            return (1, 1)
        case .openQuestion:
            return nil
        }
    }

    private var planDeclaration: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Qual é seu plano atual?").font(.displayMedium)
            Text("Esses dados ficam só nesta sessão local e não serão enviados nem salvos.")
                .font(.bodyRegular)
                .foregroundColor(.textSecondary)
            TextField("Nome do plano", text: $model.declaredPlanName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("assist-v4.plan.name")
            TextField("Preço mensal", text: $model.declaredPlanPrice)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("assist-v4.plan.price")
            Button("Continuar") { model.continuePlanDeclaration() }
                .buttonStyle(.linkaPrimary)
                .disabled(model.declaredPlanName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.declaredPlanPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Voltar às sugestões") { model.returnHome() }
                .buttonStyle(.linkaSecondary)
            Button("Encerrar investigação") { model.cancelLocalInvestigation() }
                .buttonStyle(.linkaSecondary)
                .accessibilityIdentifier("assist-v4.cancel")
        }
    }

    private func shortcut(_ title: String, _ intent: ConsultationIntent, showsDivider: Bool = true) -> some View {
        VStack(spacing: 0) {
            Button(action: { model.start(intent) }) {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .contentShape(Rectangle())
            }
                .font(.bodyRegularStrong)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.vertical, 12)
                .accessibilityIdentifier("assist-v4.shortcut.\(intent.rawValue)")
            if showsDivider {
                Divider()
            }
        }
    }

    private func limitation(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.displayMedium)
            Text(detail).font(.bodyRegular).foregroundColor(.textSecondary)
            evidenceBoundary
            Button("Voltar às sugestões") { model.returnHome() }.buttonStyle(.linkaPrimary)
        }
    }

    private func localOrientation(_ orientation: AssistV4PresentationModel.LocalOrientation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(orientation.title)
                .font(.displayMedium)
                .accessibilityIdentifier("assist-v4.local-orientation")
            VStack(alignment: .leading, spacing: 4) {
                Text("Por quê").font(.bodyRegularStrong)
                Text(orientation.reason).font(.bodyRegular).foregroundColor(.textSecondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Próxima ação").font(.bodyRegularStrong)
                Text(orientation.nextAction).font(.bodyRegular).foregroundColor(.textSecondary)
                ForEach(orientation.supportingConditions, id: \.self) { condition in
                    Text(condition).font(.bodyRegular).foregroundColor(.textSecondary)
                }
            }
            orientationEvidence(orientation)
            suggestedActionFeedback(orientation.actionProgress.status)
            Button("Revisar respostas") { model.reviseSlowConnectionAnswers() }
                .buttonStyle(.linkaSecondary)
                .accessibilityIdentifier("assist-v4.action.revise-answers")
            if orientation.actionProgress.status == .pending {
                Button("Voltar às sugestões") { model.returnHome() }.buttonStyle(.linkaSecondary)
            } else {
                Button("Voltar às sugestões") { model.returnHome() }.buttonStyle(.linkaPrimary)
            }
            Button("Encerrar investigação") { model.cancelLocalInvestigation() }
                .buttonStyle(.linkaSecondary)
                .accessibilityIdentifier("assist-v4.cancel")
        }
    }

    private var cancelledInvestigation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Investigação encerrada").font(.displayMedium)
            Text("As informações desta sessão local foram descartadas. Nada foi enviado ou salvo.")
                .font(.bodyRegular)
                .foregroundColor(.textSecondary)
            Button("Voltar às sugestões") { model.returnHome() }
                .buttonStyle(.linkaPrimary)
        }
        .accessibilityIdentifier("assist-v4.cancelled")
    }

    private var pausedInvestigation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Investigação pausada").font(.displayMedium)
            Text("Sua etapa local continua neste aparelho e só será retomada se você escolher continuar. Nada foi enviado ou salvo.")
                .font(.bodyRegular)
                .foregroundColor(.textSecondary)
            Button("Retomar investigação") { model.resumePausedInvestigation() }
                .buttonStyle(.linkaPrimary)
                .accessibilityIdentifier("assist-v4.resume")
            Button("Encerrar investigação") { model.cancelLocalInvestigation() }
                .buttonStyle(.linkaSecondary)
                .accessibilityIdentifier("assist-v4.cancel")
        }
    }

    private func unavailableOpenQuestion(_ text: String, canResumeGuidance: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A pergunta não foi enviada").font(.displayMedium)
            Text("\"\(text)\" continua no rascunho. A consulta livre precisa de um motor V4 autorizado.")
                .font(.bodyRegular)
                .foregroundColor(.textSecondary)
            if canResumeGuidance {
                Text("Sua etapa local continua no aparelho.")
                    .font(.bodyRegular)
                    .foregroundColor(.textSecondary)
                Button("Continuar investigação") { model.resumeGuidance() }
                    .buttonStyle(.linkaPrimary)
            }
            Button("Voltar às sugestões") { model.returnHome() }
                .buttonStyle(.linkaSecondary)
            Button("Encerrar investigação") { model.cancelLocalInvestigation() }
                .buttonStyle(.linkaSecondary)
                .accessibilityIdentifier("assist-v4.cancel")
        }
    }

    private var evidenceBoundary: some View {
        DisclosureGroup("Dados e limites desta orientação") {
            Text("Nenhuma medição, especificação, oferta ou fonte externa foi consultada nesta prova local.")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .font(.bodyRegularStrong)
        .accessibilityIdentifier("assist-v4.evidence-boundary")
    }

    private func orientationEvidence(_ orientation: AssistV4PresentationModel.LocalOrientation) -> some View {
        DisclosureGroup("Dados e limites desta orientação") {
            Text("Respostas declaradas nesta tela")
                .font(.caption)
                .foregroundColor(.textSecondary)
            ForEach(orientation.declaredAnswers, id: \.self) { answer in
                Text(answer)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            Text("Nenhuma medição, especificação, oferta ou fonte externa foi consultada nesta prova local.")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .font(.bodyRegularStrong)
        .accessibilityIdentifier("assist-v4.evidence-boundary")
    }

    @ViewBuilder private func suggestedActionFeedback(_ status: LocalActionStatus) -> some View {
        switch status {
        case .pending:
            VStack(alignment: .leading, spacing: 8) {
                Text("Quando terminar essa ação fora do app, confirme aqui.")
                    .font(.bodyRegular)
                    .foregroundColor(.textSecondary)
                Button("Marcar como concluída") { model.completeSuggestedAction() }
                    .buttonStyle(.linkaPrimary)
                    .accessibilityIdentifier("assist-v4.action.complete")
                Button("Agora não") { model.deferSuggestedAction() }
                    .buttonStyle(.linkaSecondary)
                    .accessibilityIdentifier("assist-v4.action.defer")
            }
        case .completed:
            actionFeedback("Ação marcada como concluída nesta sessão local.")
        case .ignored:
            actionFeedback("Ação adiada nesta sessão local.")
        case .unavailable:
            actionFeedback("Ação indisponível nesta sessão local.")
        }
    }

    private func actionFeedback(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message).font(.bodyRegularStrong)
            Text("Não foi executado teste nem salvo histórico.")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .accessibilityIdentifier("assist-v4.action-feedback")
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Pergunte sobre sua rede...", text: $model.draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Pergunte sobre sua rede")
                .accessibilityIdentifier("assist-v4.composer")
                .disabled(isPaused)
            Button { model.submitOpenQuestion() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                .disabled(isPaused || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Enviar pergunta")
                .accessibilityIdentifier("assist-v4.send")
        }
        .padding(12)
        .background(.bar)
    }

    private var isPaused: Bool {
        if case .paused = model.state { return true }
        return false
    }
}
#endif
