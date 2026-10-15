import SwiftUI
import NetworkDNSBenchmark

/// Uma sessão secundária e descartável. Não recebe nem escreve Histórico,
/// perfis ou qualquer identificador da conexão.
struct DNSBenchmarkView: View {
    @StateObject private var benchmark = DNSBenchmarkCoordinator()
    @StateObject private var configuration = DNSConfigurationCoordinator()
    @State private var selectedProvider: DNSProvider?
    @State private var showConsent = false
    @State private var isMethodologyExpanded = false
    @Environment(\.openURL) private var openURL

    let onRetest: () -> Void

    var body: some View {
        #if os(macOS)
        macOSContent
        #else
        iOSContent
        #endif
    }

    private var iOSContent: some View {
        List {
            Section {
                Text("Compara a resposta DNS nesta conexão. Isso não aumenta sua velocidade contratada, ping ou Wi-Fi.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if let milliseconds = benchmark.systemHealth.milliseconds {
                    LabeledContent("Resposta", value: Self.milliseconds(milliseconds))
                        .accessibilityLabel("DNS atual do sistema, resposta \(Self.milliseconds(milliseconds))")
                } else {
                    Text("Não disponível nesta tentativa")
                        .foregroundStyle(.secondary)
                }
                Text("O sistema não expôs o IP do resolvedor nesta conexão.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("DNS atual do sistema")
            } footer: {
                Text("É uma resolução pelo sistema. Ela não entra no ranking porque pode usar cache, gateway, VPN ou perfil corporativo.")
            }

            content
            configurationSection
        }
        .linkaGradientScreenBackground()
        .navigationTitle("Resposta de DNS")
        .toolbar {
            if case .running = benchmark.state {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar", action: benchmark.cancel) }
            }
        }
        .task { await configuration.refresh() }
        .confirmationDialog("Criar configuração de DNS?", isPresented: $showConsent, titleVisibility: .visible) {
            if let provider = selectedProvider {
                Link("Política de privacidade de \(provider.name)", destination: provider.privacyURL)
                Button("Criar configuração") { Task { await configuration.create(provider: provider) } }
            }
            Button("Cancelar", role: .cancel) { selectedProvider = nil }
        } message: {
            if let provider = selectedProvider {
                Text("O DNS de todo o dispositivo usará \(provider.name) via DNS sobre HTTPS enquanto a configuração estiver ativa. As consultas de nomes serão enviadas a esse provedor. Você pode remover a configuração no Linka depois.")
            }
        }
    }

    #if os(macOS)
    @State private var showDNSGuideModal = false

    private var macOSContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Pagehead
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(LinkaCopy.value("dns.title"))
                            .font(.largeTitle.weight(.bold))
                        Text(LinkaCopy.value("dns.mac.intro"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Ferramenta")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.surfaceCard, in: Capsule())
                        .foregroundColor(.textSecondary)
                }

                // Network ribbon
                macNetworkRibbon

                // Benchmark Section (Idle / Running / Completed)
                macBenchmarkSection

                if configuration.status != .none {
                    macConfigurationSection
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(36)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle(LinkaCopy.value("dns.title"))
        .sheet(isPresented: $showDNSGuideModal) {
            dnsGuideModalSheet
        }
        .toolbar {
            if case .running = benchmark.state {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LinkaCopy.value("common.cancel"), action: benchmark.cancel)
                }
            }
        }
        .task { await configuration.refresh() }
        .confirmationDialog(LinkaCopy.value("dns.configuration.create.title"), isPresented: $showConsent, titleVisibility: .visible) {
            if let provider = selectedProvider {
                Link(dnsFormat("dns.privacy.provider", provider.name), destination: provider.privacyURL)
                Button(LinkaCopy.value("dns.configuration.create")) { Task { await configuration.create(provider: provider) } }
            }
            Button(LinkaCopy.value("common.cancel"), role: .cancel) { selectedProvider = nil }
        } message: {
            if let provider = selectedProvider {
                Text(dnsFormat("dns.configuration.create.detail", provider.name))
            }
        }
    }

    private var macNetworkRibbon: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.brandAccentWarm.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "globe")
                    .font(.system(size: 18))
                    .foregroundColor(.brandAccentWarm)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("DNS atual: automático da rede")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text("O teste compara consultas. Nenhuma configuração é aplicada automaticamente.")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
        )
    }

    @ViewBuilder private var macBenchmarkSection: some View {
        switch benchmark.state {
        case .idle:
            VStack(spacing: 14) {
                Image(systemName: "globe")
                    .font(.system(size: 36))
                    .foregroundColor(.textSecondary)
                    .padding(.bottom, 2)

                Text("Qual DNS responde melhor nesta rede?")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.textPrimary)

                Text("Veja uma comparação de latência e confira o resultado antes de abrir os ajustes do sistema.")
                    .font(.bodySmall)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                Button {
                    benchmark.start()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gauge.medium")
                        Text(LinkaCopy.value("dns.compare.start"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandAccentWarm)
                .padding(.top, 4)
                .accessibilityHint(LinkaCopy.value("dns.compare.start.hint"))
            }
            .frame(maxWidth: .infinity)
            .padding(32)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                    .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
            )
        case .running:
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .padding(.bottom, 2)

                Text(LinkaCopy.value("dns.compare.running"))
                    .font(.title2.weight(.bold))
                    .foregroundColor(.textPrimary)

                Text(LinkaCopy.value("dns.compare.running.detail"))
                    .font(.bodySmall)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)

                Button(LinkaCopy.value("common.cancel"), action: benchmark.cancel)
                    .buttonStyle(.linkaSecondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(32)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                    .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
            )
        case .completed(let result):
            let maxLat = maxLatency(in: result)
            VStack(spacing: 18) {
                // Table of results
                VStack(spacing: 0) {
                    if let sysMs = benchmark.systemHealth.milliseconds {
                        macSystemDNSRow(sysMs: sysMs, maxLatency: maxLat)
                        Divider()
                    }

                    ForEach(result.orderedCandidates) { candidate in
                        macCandidateRow(candidate, winner: result.winner?.id == candidate.id, maxLatency: maxLat)
                        if candidate.id != result.orderedCandidates.last?.id { Divider() }
                    }
                }
                .padding(14)
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                        .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
                )

                // Insight card
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.brandAccentWarm.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "info.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.brandAccentWarm)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(LinkaCopy.value("mac.dns.insight.title"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(LinkaCopy.value("mac.dns.insight.desc"))
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                            .lineSpacing(2)

                        Button {
                            showDNSGuideModal = true
                        } label: {
                            HStack(spacing: 4) {
                                Text(LinkaCopy.value("mac.dns.insight.action"))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.brandAccentWarm)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                        .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
                )

                // Footer action
                HStack {
                    Button {
                        benchmark.start()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Comparar novamente")
                        }
                    }
                    .buttonStyle(.linkaSecondary)

                    Spacer()

                    Text("Resultados medidos nesta conexão · mesma rede")
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                }
                .padding(.top, 4)
            }
        case .cancelled:
            VStack(alignment: .leading, spacing: 14) {
                Text(LinkaCopy.value("dns.compare.cancelled"))
                    .foregroundStyle(.secondary)
                Button(LinkaCopy.value("common.tryAgain"), action: benchmark.start)
                    .buttonStyle(.bordered)
            }
            .padding(20)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .failed:
            VStack(alignment: .leading, spacing: 14) {
                Text(LinkaCopy.value("dns.compare.failed"))
                    .foregroundStyle(.secondary)
                Button(LinkaCopy.value("common.tryAgain"), action: benchmark.start)
                    .buttonStyle(.bordered)
            }
            .padding(20)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var dnsGuideModalSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.brandAccentWarm.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "globe")
                            .font(.system(size: 18))
                            .foregroundColor(.brandAccentWarm)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LinkaCopy.value("mac.dns.guide.intro"))
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text("Cloudflare · 1.1.1.1 e 1.0.0.1")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }

                Divider()

                Text(LinkaCopy.value("mac.dns.guide.desc"))
                    .font(.bodySmall)
                    .foregroundColor(.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Antes:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.textPrimary)
                    + Text(" registrar a configuração atual.\n")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                    + Text("Depois:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.textPrimary)
                    + Text(" repetir o teste e verificar a navegação.\n")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                    + Text("Para reverter:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.textPrimary)
                    + Text(" restaurar o DNS anterior.")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfacePage, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer()

                HStack {
                    Button(LinkaCopy.value("common.close")) {
                        showDNSGuideModal = false
                    }
                    .buttonStyle(.linkaSecondary)

                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("1.1.1.1\n1.0.0.1", forType: .string)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("Copiar endereços")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandAccentWarm)
                }
            }
            .padding(24)
            .frame(minWidth: 460, minHeight: 320)
        }
    }

    private func maxLatency(in result: DNSBenchmarkResult) -> Double {
        let candidateMax = result.candidates.compactMap(\.medianMilliseconds).max() ?? 50.0
        let systemMs = benchmark.systemHealth.milliseconds ?? 0.0
        return max(candidateMax, systemMs, 25.0)
    }

    private func macSystemDNSRow(sysMs: Double, maxLatency: Double) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DNS atual")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text("Automático da rede")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }
            .frame(width: 140, alignment: .leading)

            GeometryReader { geo in
                let ratio = min(max(sysMs / maxLatency, 0.05), 1.0)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.surfacePage)
                        .frame(height: 7)
                    Capsule()
                        .fill(Color.textSecondary.opacity(0.6))
                        .frame(width: max(geo.size.width * ratio, 8), height: 7)
                }
            }
            .frame(height: 7)

            Text(Self.milliseconds(sysMs))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.textPrimary)
                .frame(width: 70, alignment: .trailing)

            HStack(spacing: 8) {
                Text("Atual")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.textSecondary.opacity(0.12), in: Capsule())
                    .foregroundColor(.textSecondary)
            }
            .frame(width: 150, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private func macCandidateRow(_ candidate: DNSBenchmarkCandidate, winner: Bool, maxLatency: Double) -> some View {
        let ip = candidate.provider.bootstrapIPs.first ?? candidate.provider.dohURL.host ?? ""

        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.provider.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(ip)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textSecondary)
            }
            .frame(width: 140, alignment: .leading)

            if let median = candidate.medianMilliseconds {
                GeometryReader { geo in
                    let ratio = min(max(median / maxLatency, 0.05), 1.0)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.surfacePage)
                            .frame(height: 7)
                        Capsule()
                            .fill(winner ? Color.brandAccentWarm : Color.brandAccentWarm.opacity(0.65))
                            .frame(width: max(geo.size.width * ratio, 8), height: 7)
                    }
                }
                .frame(height: 7)

                Text(Self.milliseconds(median))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .frame(width: 70, alignment: .trailing)
            } else {
                Spacer()
                Text(LinkaCopy.value("dns.inconclusive"))
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .frame(width: 70, alignment: .trailing)
            }

            HStack(spacing: 8) {
                if winner {
                    Text("Menor latência")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.statusGood.opacity(0.12), in: Capsule())
                        .foregroundColor(.statusGood)
                }

                if configuration.status == .none {
                    Button(LinkaCopy.value("dns.choose")) {
                        selectedProvider = candidate.provider
                        showConsent = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(dnsFormat("dns.choose.accessibility", "\(candidate.provider.name), \(candidate.medianMilliseconds.map(Self.milliseconds) ?? "")"))
                }
            }
            .frame(width: 150, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var macConfigurationSection: some View {
        switch configuration.status {
        case .none:
            EmptyView()
        case .awaitingActivation(let name):
            macSection(title: LinkaCopy.value("dns.configuration.title")) {
                Text(dnsFormat("dns.configuration.awaiting", name))
                    .foregroundStyle(.secondary)
                Button(LinkaCopy.value("dns.configuration.refreshAfterActivation")) { Task { await configuration.refresh() } }
                Button(LinkaCopy.value("dns.configuration.remove"), role: .destructive) { Task { await configuration.remove() } }
            }
        case .active(let name):
            macSection(title: LinkaCopy.value("dns.configuration.title")) {
                Label(dnsFormat("dns.configuration.active", name), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.statusGood)
                Button(LinkaCopy.value("common.testAgain"), action: onRetest)
                Button(LinkaCopy.value("dns.configuration.refresh")) { Task { await configuration.refresh() } }
                Button(LinkaCopy.value("dns.configuration.remove"), role: .destructive) { Task { await configuration.remove() } }
            }
        case .failed:
            macSection(title: LinkaCopy.value("dns.configuration.title")) {
                Text(LinkaCopy.value("dns.configuration.failed"))
                    .foregroundStyle(.secondary)
                Button(LinkaCopy.value("common.tryAgain")) { Task { await configuration.refresh() } }
                Button(LinkaCopy.value("dns.configuration.remove"), role: .destructive) { Task { await configuration.remove() } }
            }
        case .unavailable:
            macSection(title: LinkaCopy.value("dns.configuration.title")) {
                Text(LinkaCopy.value("dns.configuration.unavailable"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func macSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
            Divider()
        }
    }
    #endif

    @ViewBuilder private var content: some View {
        switch benchmark.state {
        case .idle:
            Section {
                Button("Iniciar comparação", action: benchmark.start)
                    .accessibilityHint("Envia consultas DNS sintéticas aos provedores comparados")
            } footer: {
                Text("A comparação usa consultas sintéticas; não usa domínios da sua navegação.")
            }
        case .running:
            Section {
                HStack(spacing: 12) { ProgressView(); Text("Comparando respostas de DNS…") }
                    .accessibilityElement(children: .combine)
            } footer: { Text("Três rodadas por provedor, com timeout de 2 segundos.") }
        case .completed(let result):
            Section {
                if let winner = result.winner {
                    Text("Menor mediana nesta comparação: \(winner.provider.name)")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("Sem vencedor matemático nesta comparação")
                        .font(.subheadline.weight(.semibold))
                }
                ForEach(result.orderedCandidates) { candidate in
                    candidateRow(candidate, winner: result.winner?.id == candidate.id)
                }
            } header: {
                Text("Comparação desta sessão")
            } footer: {
                Text("O resultado vale só para esta tentativa. Menor mediana não é promessa de uma conexão melhor em todos os usos.")
            }
        case .cancelled:
            Section { Text("Comparação cancelada").foregroundStyle(.secondary) }
        case .failed:
            Section { Text("Não foi possível concluir a comparação.").foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private func candidateRow(_ candidate: DNSBenchmarkCandidate, winner: Bool) -> some View {
        if let median = candidate.medianMilliseconds {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(candidate.provider.name)
                    Spacer()
                    Text(Self.milliseconds(median)).monospacedDigit()
                }
                if winner { Text("Menor mediana nesta comparação").font(.caption).foregroundStyle(.secondary) }
                if configuration.status == .none {
                    Button("Escolher \(candidate.provider.name)") {
                        selectedProvider = candidate.provider
                        showConsent = true
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Escolher \(candidate.provider.name), \(Self.milliseconds(median))")
                }
                Link("Política de privacidade", destination: candidate.provider.privacyURL)
                    .font(.caption)
            }
            .accessibilityElement(children: .contain)
        } else {
            HStack { Text(candidate.provider.name); Spacer(); Text("Inconclusivo").foregroundStyle(.secondary) }
                .accessibilityLabel("\(candidate.provider.name), inconclusivo")
        }
    }

    @ViewBuilder private var configurationSection: some View {
        switch configuration.status {
        case .none:
            EmptyView()
        case .awaitingActivation(let name):
            Section {
                Text("\(name) via DNS sobre HTTPS foi criada, mas o iPhone ainda não a ativou. Abra Ajustes > Geral > VPN e Gerenciamento de Dispositivo > DNS, ative \(name) e volte aqui para confirmar.")
                Button("Já ativei — atualizar") { Task { await configuration.refresh() } }
                Button("Remover configuração de DNS", role: .destructive) { Task { await configuration.remove() } }
            } header: { Text("Configuração de DNS") }
        case .active(let name):
            Section {
                Label("Ativa: \(name) via DNS sobre HTTPS", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.statusGood)
                Button("Medir de novo", action: onRetest)
                Button("Atualizar estado") { Task { await configuration.refresh() } }
                Button("Remover configuração de DNS", role: .destructive) { Task { await configuration.remove() } }
            } header: { Text("Configuração de DNS") }
        case .failed:
            Section {
                Text("Não foi possível confirmar a configuração. Nenhum outro DNS foi escolhido automaticamente.")
                    .foregroundStyle(.secondary)
                Button("Tentar novamente") { Task { await configuration.refresh() } }
                Button("Remover configuração de DNS", role: .destructive) { Task { await configuration.remove() } }
            } header: { Text("Configuração de DNS") }
        case .unavailable:
            Section {
                Text("Aplicar DNS não está disponível neste dispositivo. A comparação continua disponível.")
                    .foregroundStyle(.secondary)
            } header: { Text("Configuração de DNS") }
        }
    }

    private static func milliseconds(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) ms"
    }

    private func dnsFormat(_ key: String, _ value: String) -> String {
        String(format: LinkaCopy.value(key), locale: LinkaLanguagePreference.currentLocale, value)
    }
}
