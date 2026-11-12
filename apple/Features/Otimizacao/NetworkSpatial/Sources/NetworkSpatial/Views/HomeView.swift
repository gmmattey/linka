import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
public struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    @ObservedObject private var networkMonitor: NetworkMonitorService

    @State private var showReportPreviewSheet: Bool = false
    @State private var showScanIntroSheet: Bool = false
    @State private var showScanReviewSheet: Bool = false
    @State private var capturedRoomsForReview: [CapturedRoomData] = []

    private let wrapInNavigationStack: Bool
    private let title: String

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    public init(dataStore: DataStore? = nil, wrapInNavigationStack: Bool = true, title: String = "Cobertura Residencial") {
        let vm = HomeViewModel(dataStore: dataStore)
        self._viewModel = StateObject(wrappedValue: vm)
        self.networkMonitor = vm.networkMonitor
        self.wrapInNavigationStack = wrapInNavigationStack
        self.title = title
    }

    @ViewBuilder
    public var body: some View {
        if wrapInNavigationStack {
            NavigationStack {
                contentView
            }
        } else {
            contentView
        }
    }

    private var contentView: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Estado quando o Wi-Fi está desconectado
                    if !networkMonitor.isWiFiConnected {
                        ContentUnavailableView(
                            SpatialCopy.value("spatial.wifi.disconnected", defaultValue: "Wi-Fi Desconectado"),
                            systemImage: "wifi.slash",
                            description: Text(SpatialCopy.value("spatial.wifi.disconnected.desc", defaultValue: "Conecte seu dispositivo à rede Wi-Fi da sua residência para realizar o mapeamento e testes de qualidade."))
                        )
                        .padding(.vertical, 16)
                    }

                    // Banner de Sessão Ativa de Comparativo Antes × Depois (Profundidade em backgroundRaised, sem bordas)
                    if viewModel.activeComparisonBaseline != nil {
                        Button {
                            viewModel.showBeforeAfterSheet = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.triangle.swap")
                                    .font(.title3)
                                    .foregroundStyle(WiFiCasaTheme.brandAccent)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(SpatialCopy.value("spatial.comparative.active.title", defaultValue: "Modo Comparativo Ativo"))
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundStyle(WiFiCasaTheme.textPrimary)

                                    Text(SpatialCopy.value("spatial.comparative.active.desc", defaultValue: "Baseline 'Antes' fixado. Realize medições com o roteador na nova posição e toque aqui para ver o ganho."))
                                        .font(.caption)
                                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(WiFiCasaTheme.textSecondary)
                            }
                            .padding(14)
                            .background(WiFiCasaTheme.backgroundRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    // Guia de Primeiro Acesso (FTUE em 3 passos - dispensável, profundidade sem bordas)
                    if !viewModel.isOnboardingDismissed && viewModel.house.rooms.allSatisfy({ $0.lastMeasurement == nil }) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "figure.walk.motion")
                                .font(.title2)
                                .foregroundStyle(WiFiCasaTheme.brandAccent)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(SpatialCopy.value("spatial.ftue.title", defaultValue: "Mapeamento em 3 Passos"))
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                                    Spacer()
                                    Button {
                                        viewModel.dismissOnboarding()
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption2)
                                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                                            .padding(6)
                                    }
                                    .frame(width: 44, height: 44) // A11y Touch Target
                                    .accessibilityLabel(SpatialCopy.value("spatial.ftue.dismiss", defaultValue: "Dispensar guia inicial"))
                                }

                                Text(SpatialCopy.value("spatial.ftue.desc", defaultValue: "1. Verifique seus cômodos abaixo.\n2. Caminhe até cada cômodo e meça a conexão.\n3. Identifique pontos fracos e otimize sua rede."))
                                    .font(.caption)
                                    .foregroundStyle(WiFiCasaTheme.textSecondary)
                            }
                        }
                        .padding(14)
                        .background(WiFiCasaTheme.backgroundRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // Nova Seção B2C: Diagnóstico Orientado a Problemas
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(SpatialCopy.value("spatial.problems.header", defaultValue: "Como podemos melhorar sua internet?"))
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(WiFiCasaTheme.textPrimary)

                            Text(SpatialCopy.value("spatial.problems.subtitle", defaultValue: "Escolha o problema e descubra o que fazer."))
                                .font(.subheadline)
                                .foregroundStyle(WiFiCasaTheme.textSecondary)
                        }

                        VStack(spacing: 10) {
                            ForEach(HomeProblemCase.allCases) { problem in
                                ProblemCardView(
                                    problem: problem,
                                    isEnabled: networkMonitor.isWiFiConnected
                                ) {
                                    viewModel.startProblemDiagnosis(problem)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)

                    // Cabeçalho de Cobertura Residencial
                    CoverageHeaderView(
                        house: viewModel.house,
                        isWiFiActive: networkMonitor.isWiFiConnected,
                        currentSSID: networkMonitor.currentSSID,
                        onHelpTap: { viewModel.showHelpSheet = true }
                    )

                    // Título da Seção do Mapa de Cômodos
                    HStack {
                        Text(SpatialCopy.value("spatial.header.sectionRooms", defaultValue: "CÔMODOS DA CASA"))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(WiFiCasaTheme.textSecondary)

                        Spacer()

                        Button {
                            viewModel.showRoomEditorSheet = true
                        } label: {
                            Label(SpatialCopy.value("spatial.header.edit", defaultValue: "Editar"), systemImage: "pencil")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .tint(WiFiCasaTheme.brandAccent)
                    }
                    .padding(.top, 6)

                    // Grid 2D com Heatmap
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(viewModel.house.rooms) { room in
                            RoomCardView(
                                room: room,
                                isSelected: viewModel.selectedRoom?.id == room.id,
                                onMeasureTap: {
                                    viewModel.startMeasurement(for: room)
                                },
                                onDetailTap: {
                                    viewModel.selectedRoom = room
                                    viewModel.showDetailSheet = true
                                }
                            )
                        }
                    }

                    // Smart Contextual CTA Bar (Caminhada Guiada & Otimização Integrada)
                    smartJourneyCTA
                        .padding(.top, 10)

                    // Banner de Múltiplos Pontos de Acesso Detectados (Exibido apenas com >= 2 APs)
                    if viewModel.hasMultipleAccessPoints {
                        HStack(spacing: 12) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.title3)
                                .foregroundStyle(WiFiCasaTheme.brandAccent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(SpatialCopy.value("spatial.ap.multiple.title", defaultValue: "Múltiplos Pontos de Acesso"))
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(WiFiCasaTheme.textPrimary)

                                Text(SpatialCopy.format("spatial.ap.multiple.desc", viewModel.detectedAccessPoints.count))
                                    .font(.caption)
                                    .foregroundStyle(WiFiCasaTheme.textSecondary)
                            }

                            Spacer()

                            Button(SpatialCopy.value("spatial.ap.multiple.view", defaultValue: "Ver")) {
                                viewModel.showAccessPointsSheet = true
                            }
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(WiFiCasaTheme.backgroundOverlay)
                            .foregroundStyle(WiFiCasaTheme.brandAccent)
                            .clipShape(Capsule())
                            .accessibilityLabel(SpatialCopy.format("spatial.ap.multiple.desc", viewModel.detectedAccessPoints.count))
                        }
                        .padding(12)
                        .background(WiFiCasaTheme.backgroundRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(WiFiCasaTheme.backgroundBase.ignoresSafeArea())
            .tint(WiFiCasaTheme.brandAccent)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: toolbarLeadingPlacement) {
                    Menu {
                        Button {
                            showScanIntroSheet = true
                        } label: {
                            Label("Escanear com LiDAR", systemImage: "viewfinder")
                        }

                        Button {
                            viewModel.showHistorySheet = true
                        } label: {
                            Label("Histórico", systemImage: "clock.arrow.circlepath")
                        }

                        #if DEBUG
                        Divider()
                        Menu("Simulação Rápida (Dev)") {
                            ForEach(viewModel.house.rooms) { r in
                                Button("Simular Ótimo em \(r.name)") {
                                    viewModel.runSimulatedMeasurement(for: r, rating: .excellent)
                                }
                                Button("Simular Ruim em \(r.name)") {
                                    viewModel.runSimulatedMeasurement(for: r, rating: .poor)
                                }
                            }
                        }
                        #endif
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

                ToolbarItem(placement: toolbarTrailingPlacement) {
                    Button {
                        showReportPreviewSheet = true
                    } label: {
                        Image(systemName: "doc.text")
                    }
                    .accessibilityLabel("Exportar Relatório Técnico em PDF")
                }
            }
            .modifier(HomeCoreSheetsModifier(viewModel: viewModel))
            .modifier(HomeProSheetsModifier(
                viewModel: viewModel,
                networkMonitor: networkMonitor,
                showReportPreviewSheet: $showReportPreviewSheet,
                showScanIntroSheet: $showScanIntroSheet,
                showScanReviewSheet: $showScanReviewSheet,
                capturedRoomsForReview: $capturedRoomsForReview
            ))
            #if os(iOS)
            .fullScreenCover(isPresented: $viewModel.showWalkSessionSheet) {
                WalkSessionView(viewModel: viewModel.createWalkSessionViewModel())
            }
            #else
            .sheet(isPresented: $viewModel.showWalkSessionSheet) {
                WalkSessionView(viewModel: viewModel.createWalkSessionViewModel())
            }
            #endif
            .sheet(isPresented: $viewModel.showHelpSheet) {
                NavigationStack {
                    List {
                        Section(header: Text("COMO FUNCIONA O WIFI CASA")) {
                            Text("O app avalia ativamente a qualidade da conexão em cada cômodo da casa separando dois caminhos fundamentais:\n\n1. Segmento Local (LAN): Latência até o roteador.\n2. Segmento Externo (WAN): Latência até a internet.\n\nIsso permite descobrir com precisão se a lentidão decorre de barreiras locais no sinal ou de instabilidade externa da sua conexão.")
                                .font(.subheadline)
                        }
                        Section(header: Text("DICAS DE POSICIONAMENTO")) {
                            Text("• Mantenha o roteador em altura média (1 a 1,5m do chão);\n• Evite deixá-lo atrás de televisores ou dentro de nichos fechados;\n• Roteadores em locais centrais cobrem melhor quartos opostos.")
                                .font(.subheadline)
                        }
                    }
                    .navigationTitle("Guia de Qualidade Wi-Fi")
                    .inlineTitleDisplayMode()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Entendi") {
                                viewModel.showHelpSheet = false
                            }
                        }
                    }
                }
            }
            .sensoryFeedback(
                (viewModel.lastFinishedResult?.rating == .poor || viewModel.lastFinishedResult?.rating == .fair) ? .warning : .success,
                trigger: viewModel.lastFinishedResult?.id
            )
            .alert(
                viewModel.isPermissionDeniedError ? "Permissão de Rede Local" : "Aviso de Conexão",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil; viewModel.lastDiagnosticError = nil } }
                )
            ) {
                #if os(iOS)
                if viewModel.isPermissionDeniedError {
                    Button("Abrir Ajustes") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                        viewModel.errorMessage = nil
                        viewModel.lastDiagnosticError = nil
                    }
                }
                #endif
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                    viewModel.lastDiagnosticError = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .onAppear {
                viewModel.reloadData()
            }
    }

    private var toolbarLeadingPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarLeading
        #else
        return .navigation
        #endif
    }

    private var toolbarTrailingPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #else
        return .primaryAction
        #endif
    }

    @ViewBuilder
    private var smartJourneyCTA: some View {
        switch viewModel.journeyState {
        case .notStarted(let firstRoom):
            Button {
                viewModel.startWalkSession(mode: .regular)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "figure.walk.motion")
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(SpatialCopy.value("spatial.journey.startWalk", defaultValue: "Iniciar Caminhada pela Casa"))
                            .font(.headline)
                            .fontWeight(.bold)
                        Text(SpatialCopy.format("spatial.journey.startWalk.step", viewModel.house.rooms.count, firstRoom.name))
                            .font(.caption)
                            .opacity(0.85)
                    }

                    Spacer()

                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(WiFiCasaTheme.brandAccent)
            .accessibilityLabel("Iniciar Caminhada Guiada no cômodo \(firstRoom.name), ponto 1 de \(viewModel.house.rooms.count)")

        case .inProgress(let nextRoom, let measuredCount, let totalRooms):
            Button {
                viewModel.startWalkSession(mode: .regular)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "figure.walk.motion")
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(SpatialCopy.format("spatial.journey.continueWalk", nextRoom.name))
                            .font(.headline)
                            .fontWeight(.bold)
                        Text(SpatialCopy.format("spatial.journey.continueWalk.step", measuredCount + 1, totalRooms))
                            .font(.caption)
                            .opacity(0.85)
                    }

                    Spacer()

                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(WiFiCasaTheme.brandAccent)
            .accessibilityLabel("Continuar caminhada no cômodo \(nextRoom.name), passo \(measuredCount + 1) de \(totalRooms)")

        case .needsOptimization(let roomsNeedingFix):
            VStack(spacing: 10) {
                if let firstRec = viewModel.recommendations().first {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(WiFiCasaTheme.scoreFair)
                            .font(.subheadline)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(SpatialCopy.value("spatial.journey.recommendation", defaultValue: "Recomendação de Posicionamento"))
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(WiFiCasaTheme.textSecondary)

                            Text(firstRec)
                                .font(.caption)
                                .foregroundStyle(WiFiCasaTheme.textPrimary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(WiFiCasaTheme.backgroundRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button {
                    viewModel.startWalkSession(mode: .comparison)
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.swap")
                        let weakDesc = roomsNeedingFix.count == 1 ? SpatialCopy.value("spatial.journey.weakPoint.single", defaultValue: "ponto fraco") : SpatialCopy.value("spatial.journey.weakPoint.multiple", defaultValue: "pontos fracos")
                        Text(SpatialCopy.format("spatial.journey.newComparison", roomsNeedingFix.count, weakDesc))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(WiFiCasaTheme.brandAccent)
                .accessibilityLabel("Otimizar Wi-Fi com Comparativo Antes × Depois. \(roomsNeedingFix.count) cômodos com instabilidade.")
            }

        case .fullyOptimized:
            Button {
                viewModel.showBeforeAfterSheet = true
            } label: {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(WiFiCasaTheme.scoreExcellent)
                    Text(SpatialCopy.value("spatial.journey.stable", defaultValue: "Rede Estável — Ver Comparativo"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(WiFiCasaTheme.brandAccent)
            .accessibilityLabel("Rede estável e com boa qualidade. Ver comparativo e histórico.")
        }
    }
}

// MARK: - Modifiers Modulares para Sheets da HomeView

@available(iOS 17.0, macOS 14.0, *)
private struct HomeCoreSheetsModifier: ViewModifier {
    @ObservedObject var viewModel: HomeViewModel

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $viewModel.showMeasurementSheet) {
                MeasurementActiveSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showDetailSheet) {
                if let room = viewModel.selectedRoom ?? viewModel.activeMeasuringRoom {
                    let nextRoom = viewModel.nextUnmeasuredRoom(excluding: room.id)
                    MeasurementDetailSheet(
                        room: room,
                        measurement: room.lastMeasurement ?? viewModel.lastFinishedResult,
                        nextRoomName: nextRoom?.name,
                        onNextRoom: nextRoom != nil ? {
                            viewModel.proceedToNextRoom(after: room)
                        } : nil,
                        onReMeasure: {
                            viewModel.startMeasurement(for: room)
                        }
                    )
                }
            }
            .sheet(isPresented: $viewModel.showRoomEditorSheet) {
                RoomEditorSheet(
                    rooms: Binding(
                        get: { viewModel.house.rooms },
                        set: { viewModel.updateRooms($0) }
                    )
                ) { updatedRooms in
                    viewModel.updateRooms(updatedRooms)
                }
            }
            .sheet(isPresented: $viewModel.showBeforeAfterSheet) {
                BeforeAfterComparisonView(
                    currentHouse: viewModel.house,
                    dataStore: viewModel.dataStore
                )
            }
            .sheet(isPresented: $viewModel.showHistorySheet) {
                HistoryView(dataStore: viewModel.dataStore)
            }
            .sheet(isPresented: $viewModel.showAccessPointsSheet) {
                DetectedAccessPointsSheet(accessPoints: viewModel.detectedAccessPoints)
            }
            .sheet(item: $viewModel.activeProblemCase) { problem in
                ProblemDiagnosticSheet(
                    problem: problem,
                    house: viewModel.house,
                    diagnosticEngine: viewModel.diagnosticEngine,
                    dataStore: viewModel.dataStore,
                    apTracker: viewModel.apTracker,
                    onFinish: {
                        viewModel.reloadData()
                    }
                )
            }
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct HomeProSheetsModifier: ViewModifier {
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var networkMonitor: NetworkMonitorService

    @Binding var showReportPreviewSheet: Bool
    @Binding var showScanIntroSheet: Bool
    @Binding var showScanReviewSheet: Bool
    @Binding var capturedRoomsForReview: [CapturedRoomData]

    @State private var showActiveScanSheet: Bool = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showReportPreviewSheet) {
                ReportPreviewSheet(
                    house: viewModel.house,
                    ssid: networkMonitor.currentSSID,
                    gatewayIP: GatewayDiscoveryService.shared.discoverGatewayIPDisplayString()
                )
            }
            .sheet(isPresented: $showScanIntroSheet) {
                RoomScanIntroSheet(
                    onStartScanning: {
                        showActiveScanSheet = true
                    },
                    onOpenManualEditor: {
                        viewModel.showRoomEditorSheet = true
                    }
                )
            }
            .sheet(isPresented: $showActiveScanSheet) {
                RoomScanActiveSheet(
                    onScanCompleted: { scannedRooms in
                        showActiveScanSheet = false
                        capturedRoomsForReview = scannedRooms
                        showScanReviewSheet = true
                    },
                    onScanCancelled: {
                        showActiveScanSheet = false
                    }
                )
            }
            .sheet(isPresented: $showScanReviewSheet) {
                RoomScanReviewView(capturedRooms: capturedRoomsForReview) { consolidatedRooms in
                    viewModel.updateRooms(consolidatedRooms)
                }
            }
    }
}
