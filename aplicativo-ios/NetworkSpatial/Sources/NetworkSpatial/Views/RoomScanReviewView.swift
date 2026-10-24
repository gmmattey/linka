import SwiftUI

/// Tela de revisão pós-captura tridimensional com RoomPlan.
/// Permite renomear os cômodos identificados, verificar suas áreas em m²,
/// definir a localização do roteador principal e consolidar os dados no WiFi Casa.
@available(iOS 17.0, macOS 14.0, *)
public struct RoomScanReviewView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var roomsData: [CapturedRoomData]
    @State private var routerRoomIndex: Int = 0
    @State private var editingIndex: Int? = nil
    @State private var editNameText: String = ""
    @State private var showingEditAlert: Bool = false
    @State private var didConsolidate: Bool = false

    public let onConsolidate: ([Room]) -> Void

    public init(
        capturedRooms: [CapturedRoomData],
        onConsolidate: @escaping ([Room]) -> Void
    ) {
        self._roomsData = State(initialValue: capturedRooms)
        self.onConsolidate = onConsolidate
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Preview Resumido das Dimensões Capturadas
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PLANTA CAPTURADA COM LIDAR")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(WiFiCasaTheme.textSecondary)

                        let totalArea = roomsData.reduce(0.0) { $0 + $1.areaSqMeters }

                        HStack(spacing: 16) {
                            statPill(title: "Cômodos", value: "\(roomsData.count)", icon: "square.split.2x2")
                            statPill(title: "Área Total", value: String(format: "%.1f m²", totalArea), icon: "ruler")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Seletor do Roteador Principal
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LOCALIZAÇÃO DO ROTEADOR")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(WiFiCasaTheme.textSecondary)

                        HStack(spacing: 12) {
                            Image(systemName: "wifi.router.fill")
                                .font(.title3)
                                .foregroundStyle(WiFiCasaTheme.brandAccent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Onde fica o Roteador Principal?")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(WiFiCasaTheme.textPrimary)

                                Text("Ponto de entrada do link de internet da operadora.")
                                    .font(.caption2)
                                    .foregroundStyle(WiFiCasaTheme.textSecondary)
                            }

                            Spacer()

                            Picker("Roteador", selection: $routerRoomIndex) {
                                ForEach(roomsData.indices, id: \.self) { idx in
                                    Text(roomsData[idx].suggestedName).tag(idx)
                                }
                            }
                            .tint(WiFiCasaTheme.brandAccent)
                            .pickerStyle(.menu)
                        }
                        .padding(14)
                        .background(WiFiCasaTheme.backgroundRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 16)

                    // Lista de Cômodos Identificados (Toque para editar o nome)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CÔMODOS IDENTIFICADOS (Toque para renomear)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(WiFiCasaTheme.textSecondary)

                        VStack(spacing: 10) {
                            ForEach(roomsData.indices, id: \.self) { index in
                                let item = roomsData[index]
                                let isRouter = (index == routerRoomIndex)

                                Button {
                                    editingIndex = index
                                    editNameText = item.suggestedName
                                    showingEditAlert = true
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(WiFiCasaTheme.backgroundOverlay)
                                                .frame(width: 36, height: 36)

                                            Image(systemName: RoomPlanParser.iconForRoomName(item.suggestedName))
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(isRouter ? WiFiCasaTheme.brandAccent : WiFiCasaTheme.textPrimary)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.suggestedName)
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                                .foregroundStyle(WiFiCasaTheme.textPrimary)

                                            Text("\(String(format: "%.1f m²", item.areaSqMeters)) • \(String(format: "%.1f m", item.boundingWidthMeters)) × \(String(format: "%.1f m", item.boundingLengthMeters))")
                                                .font(.caption2)
                                                .foregroundStyle(WiFiCasaTheme.textSecondary)
                                                .monospacedDigit()
                                        }

                                        Spacer()

                                        if isRouter {
                                            HStack(spacing: 4) {
                                                Image(systemName: "wifi.router.fill")
                                                    .font(.caption2)
                                                Text("Roteador")
                                                    .font(.caption2)
                                                    .fontWeight(.bold)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(WiFiCasaTheme.backgroundOverlay)
                                            .foregroundStyle(WiFiCasaTheme.brandAccent)
                                            .clipShape(Capsule())
                                        }

                                        Image(systemName: "pencil")
                                            .font(.caption)
                                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                                    }
                                    .padding(14)
                                    .background(WiFiCasaTheme.backgroundRaised)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .frame(minHeight: 44) // A11y
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // CTA Consolidar Planta
                    VStack(spacing: 12) {
                        Button {
                            consolidateAndDismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.headline)
                                Text("Consolidar Planta Baixa")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                Spacer()
                            }
                            .frame(minHeight: 44) // A11y Touch Target
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(WiFiCasaTheme.brandAccent)
                        .disabled(roomsData.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .background(WiFiCasaTheme.backgroundBase.ignoresSafeArea())
            .navigationTitle("Revisão da Planta")
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Descartar") {
                        dismiss()
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
            .alert("Renomear Cômodo", isPresented: $showingEditAlert) {
                TextField("Nome do cômodo", text: $editNameText)
                Button("Salvar") {
                    if let idx = editingIndex {
                        let trimmed = editNameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            let old = roomsData[idx]
                            roomsData[idx] = CapturedRoomData(
                                id: old.id,
                                suggestedName: trimmed,
                                areaSqMeters: old.areaSqMeters,
                                boundingWidthMeters: old.boundingWidthMeters,
                                boundingLengthMeters: old.boundingLengthMeters
                            )
                        }
                    }
                }
                Button("Cancelar", role: .cancel) { }
            }
            .sensoryFeedback(.success, trigger: didConsolidate)
        }
    }

    private func consolidateAndDismiss() {
        let rooms = RoomPlanParser.convertCapturedRoomsToHouseRooms(
            capturedRooms: roomsData,
            defaultRouterRoomIndex: routerRoomIndex
        )
        didConsolidate.toggle()
        onConsolidate(rooms)
        dismiss()
    }

    private func statPill(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(WiFiCasaTheme.brandAccent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(WiFiCasaTheme.textSecondary)

                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(WiFiCasaTheme.textPrimary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WiFiCasaTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    if #available(iOS 17.0, macOS 14.0, *) {
        RoomScanReviewView(
            capturedRooms: [
                CapturedRoomData(suggestedName: "Sala de Estar", areaSqMeters: 24.5, boundingWidthMeters: 5.0, boundingLengthMeters: 4.9),
                CapturedRoomData(suggestedName: "Cozinha", areaSqMeters: 14.0, boundingWidthMeters: 4.0, boundingLengthMeters: 3.5),
                CapturedRoomData(suggestedName: "Quarto Principal", areaSqMeters: 16.0, boundingWidthMeters: 4.0, boundingLengthMeters: 4.0),
                CapturedRoomData(suggestedName: "Banheiro", areaSqMeters: 4.8, boundingWidthMeters: 2.4, boundingLengthMeters: 2.0)
            ],
            onConsolidate: { _ in }
        )
        .preferredColorScheme(.dark)
    }
}
