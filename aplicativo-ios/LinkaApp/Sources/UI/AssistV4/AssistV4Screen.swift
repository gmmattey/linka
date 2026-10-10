#if os(iOS)
import SwiftUI
import AssistConsultation

struct AssistV4Screen: View {
    @Environment(\.dismiss) private var dismiss
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
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Assist", systemImage: "sparkles")
                .font(.displayTitle)
                .foregroundColor(.textPrimary)
            Text("Consultoria de rede")
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
            VStack(alignment: .leading, spacing: 8) {
                Text("Como posso ajudar?").font(.displayMedium)
                shortcut("Minha internet está lenta", .slowConnection)
                shortcut("Meu roteador é adequado?", .routerAdequacy)
                shortcut("Preciso de uma rede Mesh?", .meshNeed)
                shortcut("Meu plano vale a pena?", .planValue)
            }
        case let .guided(_, question):
            VStack(alignment: .leading, spacing: 12) {
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
            }
        case let .unavailableOpenQuestion(text, canResumeGuidance):
            unavailableOpenQuestion(text, canResumeGuidance: canResumeGuidance)
        case let .limitation(text):
            limitation("Dados insuficientes para continuar", detail: text)
        case let .guidance(title, detail):
            limitation(title, detail: detail)
        }
    }

    private func shortcut(_ title: String, _ intent: ConsultationIntent) -> some View {
        Button { model.start(intent) } label: { HStack { Text(title); Spacer(); Image(systemName: "chevron.right") } }
            .font(.bodyRegularStrong).buttonStyle(.plain).padding(.vertical, 8)
            .accessibilityIdentifier("assist-v4.shortcut.\(intent.rawValue)")
    }

    private func limitation(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.displayMedium)
            Text(detail).font(.bodyRegular).foregroundColor(.textSecondary)
            evidenceBoundary
            Button("Voltar às sugestões") { model.returnHome() }.buttonStyle(.linkaPrimary)
        }
    }

    private func unavailableOpenQuestion(_ text: String, canResumeGuidance: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A pergunta não foi enviada").font(.displayMedium)
            Text("\"\(text)\" continua no rascunho. A consulta livre precisa de um motor V4 autorizado.")
                .font(.bodyRegular)
                .foregroundColor(.textSecondary)
            if canResumeGuidance {
                Text("Sua pergunta guiada e a escolha anterior continuam no aparelho.")
                    .font(.bodyRegular)
                    .foregroundColor(.textSecondary)
                Button("Continuar investigação") { model.resumeGuidance() }
                    .buttonStyle(.linkaPrimary)
            }
            Button("Voltar às sugestões") { model.returnHome() }
                .buttonStyle(.linkaSecondary)
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

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Pergunte sobre sua rede...", text: $model.draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Pergunte sobre sua rede")
                .accessibilityIdentifier("assist-v4.composer")
            Button { model.submitOpenQuestion() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Enviar pergunta")
                .accessibilityIdentifier("assist-v4.send")
        }
        .padding(12)
        .background(.bar)
    }
}
#endif
