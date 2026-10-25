import SwiftUI

/// Folha para adição, renomeação, remoção e configuração de pontos de acesso Wi-Fi (Roteador, Mesh e Repetidores) por cômodo.
public struct RoomEditorSheet: View {
    @Binding var rooms: [Room]
    public let onSave: ([Room]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var editingRooms: [Room] = []
    @State private var showingAddRoomAlert: Bool = false
    @State private var newRoomName: String = ""

    public struct RoomIconOption: Identifiable, Hashable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    private let availableIcons: [RoomIconOption] = [
        RoomIconOption(id: "sofa", name: "Sala de Estar"),
        RoomIconOption(id: "bed.double", name: "Quarto"),
        RoomIconOption(id: "laptopcomputer", name: "Escritório"),
        RoomIconOption(id: "fork.knife", name: "Cozinha / Jantar"),
        RoomIconOption(id: "tv", name: "Sala de TV"),
        RoomIconOption(id: "bathtub", name: "Banheiro"),
        RoomIconOption(id: "car", name: "Garagem"),
        RoomIconOption(id: "door.left.hand.open", name: "Entrada / Hall"),
        RoomIconOption(id: "sun.max", name: "Varanda / Jardim"),
        RoomIconOption(id: "house", name: "Área Externa / Geral")
    ]

    public init(
        rooms: Binding<[Room]>,
        onSave: @escaping ([Room]) -> Void
    ) {
        self._rooms = rooms
        self.onSave = onSave
        self._editingRooms = State(initialValue: rooms.wrappedValue)
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($editingRooms) { $room in
                        VStack(alignment: .leading, spacing: 10) {
                            // Linha 1: Ícone + Nome do Cômodo
                            HStack(spacing: 12) {
                                Menu {
                                    ForEach(availableIcons) { iconOption in
                                        Button {
                                            room.icon = iconOption.id
                                        } label: {
                                            Label(iconOption.name, systemImage: iconOption.id)
                                        }
                                    }
                                } label: {
                                    Image(systemName: room.icon)
                                        .font(.title3)
                                        .foregroundStyle(WiFiCasaTheme.brandAccent)
                                        .frame(width: 36, height: 36)
                                        .background(WiFiCasaTheme.backgroundOverlay)
                                        .clipShape(Circle())
                                }
                                .accessibilityLabel("Ícone do cômodo: \(room.icon)")
                                .accessibilityHint("Toque duas vezes para escolher outro ícone para este cômodo.")

                                TextField(SpatialCopy.value("spatial.editor.roomName", defaultValue: "Nome do Cômodo"), text: $room.name)
                                    .font(.headline)
                                    .foregroundStyle(WiFiCasaTheme.textPrimary)
                                    .accessibilityLabel("Nome do cômodo: \(room.name)")
                            }

                            // Linha 2: Configuração do Ponto de Acesso
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(SpatialCopy.value("spatial.editor.apHeader", defaultValue: "Ponto de Acesso Wi-Fi"))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(WiFiCasaTheme.textSecondary)

                                    Spacer()

                                    Picker(SpatialCopy.value("spatial.editor.apType", defaultValue: "Tipo de Ponto"), selection: Binding(
                                        get: { currentAccessPointType(for: room) },
                                        set: { newType in
                                            handleAccessPointTypeChange(newType, for: room.id)
                                        }
                                    )) {
                                        Text(AccessPointType.none.label).tag(AccessPointType.none)
                                        Text(AccessPointType.mainRouter.label).tag(AccessPointType.mainRouter)
                                        Text(AccessPointType.meshSatellite.label).tag(AccessPointType.meshSatellite)
                                        Text(AccessPointType.repeater.label).tag(AccessPointType.repeater)
                                    }
                                    .pickerStyle(.menu)
                                    .tint(WiFiCasaTheme.brandAccent)
                                    .accessibilityLabel("Ponto de acesso Wi-Fi configurado em \(room.name)")
                                    .accessibilityValue(currentAccessPointType(for: room).label)
                                    .accessibilityHint("Toque duas vezes para alterar entre Nenhum, Roteador Principal, Nó Mesh ou Repetidor.")
                                }

                                // Se for Satélite Mesh ou Repetidor, seleciona Backhaul
                                let apType = currentAccessPointType(for: room)
                                if apType == .meshSatellite || apType == .repeater {
                                    HStack {
                                        Text(SpatialCopy.value("spatial.editor.backhaul", defaultValue: "Conexão (Backhaul)"))
                                            .font(.caption2)
                                            .foregroundStyle(WiFiCasaTheme.textSecondary)

                                        Spacer()

                                        Picker(SpatialCopy.value("spatial.editor.backhaul", defaultValue: "Backhaul"), selection: Binding(
                                            get: { room.accessPoint?.backhaulType ?? .wifi },
                                            set: { newBackhaul in
                                                updateBackhaul(newBackhaul, for: room.id)
                                            }
                                        )) {
                                            Text(BackhaulType.wifi.label).tag(BackhaulType.wifi)
                                            Text(BackhaulType.ethernet.label).tag(BackhaulType.ethernet)
                                        }
                                        .pickerStyle(.segmented)
                                        .frame(maxWidth: 220)
                                        .accessibilityLabel("Tipo de conexão de volta até o gateway para \(room.name)")
                                        .accessibilityHint("Selecione Sem Fio para enlace Wi-Fi ou Cabo para conexão direta Ethernet.")
                                    }
                                    .padding(.top, 2)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 6)
                    }
                    .onDelete(perform: deleteRoom)
                    .onMove(perform: moveRoom)
                } header: {
                    Text(SpatialCopy.value("spatial.editor.sectionRooms", defaultValue: "CÔMODOS DA RESIDÊNCIA"))
                } footer: {
                    Text(SpatialCopy.value("spatial.editor.footerAP", defaultValue: "Aponte o Roteador Principal e configure seus Nós Mesh ou Repetidores para diagnósticos acionáveis de cobertura e backhaul."))
                }

                Section {
                    Button {
                        showingAddRoomAlert = true
                    } label: {
                        Label(SpatialCopy.value("spatial.editor.addRoom", defaultValue: "Adicionar Novo Cômodo"), systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundStyle(WiFiCasaTheme.brandAccent)
                    }
                    .frame(minHeight: 44) // A11y
                    .accessibilityLabel("Adicionar novo cômodo")
                    .accessibilityHint("Toque duas vezes para criar um novo cômodo na casa.")
                }
            }
            .appListStyle()
            .tint(WiFiCasaTheme.brandAccent)
            .navigationTitle(SpatialCopy.value("spatial.editor.title", defaultValue: "Gerenciar Cômodos"))
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(SpatialCopy.value("spatial.common.cancel", defaultValue: "Cancelar")) {
                        dismiss()
                    }
                    .accessibilityLabel("Cancelar alterações e fechar")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(SpatialCopy.value("spatial.common.save", defaultValue: "Salvar")) {
                        onSave(editingRooms)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityLabel("Salvar alterações dos cômodos")
                }
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
                #endif
            }
            .alert(SpatialCopy.value("spatial.editor.newRoom", defaultValue: "Novo Cômodo"), isPresented: $showingAddRoomAlert) {
                TextField(SpatialCopy.value("spatial.editor.newRoomPlaceholder", defaultValue: "Ex: Varanda, Corredor"), text: $newRoomName)
                Button(SpatialCopy.value("spatial.editor.add", defaultValue: "Adicionar")) {
                    let trimmed = newRoomName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        let newRoom = Room(
                            name: trimmed,
                            icon: "door.left.hand.open",
                            gridX: editingRooms.count % 2,
                            gridY: editingRooms.count / 2,
                            hasRouter: false
                        )
                        editingRooms.append(newRoom)
                        newRoomName = ""
                    }
                }
                Button(SpatialCopy.value("spatial.common.cancel", defaultValue: "Cancelar"), role: .cancel) {
                    newRoomName = ""
                }
            }
        }
    }

    private func currentAccessPointType(for room: Room) -> AccessPointType {
        if let ap = room.accessPoint {
            return ap.type
        }
        return room.hasRouter ? .mainRouter : .none
    }

    private func handleAccessPointTypeChange(_ newType: AccessPointType, for roomId: UUID) {
        guard let index = editingRooms.firstIndex(where: { $0.id == roomId }) else { return }

        switch newType {
        case .none:
            editingRooms[index].hasRouter = false
            editingRooms[index].accessPoint = nil

        case .mainRouter:
            // Regra inegociável: Apenas 1 Roteador Principal na casa
            for i in editingRooms.indices {
                if editingRooms[i].id != roomId && (editingRooms[i].hasRouter || editingRooms[i].accessPoint?.type == .mainRouter) {
                    editingRooms[i].hasRouter = false
                    editingRooms[i].accessPoint = nil
                }
            }
            editingRooms[index].hasRouter = true
            editingRooms[index].accessPoint = AccessPointNode(
                name: "Roteador Principal",
                type: .mainRouter,
                backhaulType: .ethernet,
                roomId: roomId
            )

        case .meshSatellite:
            editingRooms[index].hasRouter = false
            let existingBackhaul = editingRooms[index].accessPoint?.backhaulType ?? .wifi
            let name = editingRooms[index].accessPoint?.name ?? "Nó Mesh \(editingRooms[index].name)"
            editingRooms[index].accessPoint = AccessPointNode(
                name: name,
                type: .meshSatellite,
                backhaulType: existingBackhaul,
                roomId: roomId
            )

        case .repeater:
            editingRooms[index].hasRouter = false
            let existingBackhaul = editingRooms[index].accessPoint?.backhaulType ?? .wifi
            let name = editingRooms[index].accessPoint?.name ?? "Repetidor \(editingRooms[index].name)"
            editingRooms[index].accessPoint = AccessPointNode(
                name: name,
                type: .repeater,
                backhaulType: existingBackhaul,
                roomId: roomId
            )
        }
    }

    private func updateBackhaul(_ newBackhaul: BackhaulType, for roomId: UUID) {
        guard let index = editingRooms.firstIndex(where: { $0.id == roomId }),
              let existing = editingRooms[index].accessPoint else { return }

        editingRooms[index].accessPoint = AccessPointNode(
            id: existing.id,
            name: existing.name,
            type: existing.type,
            backhaulType: newBackhaul,
            roomId: roomId,
            bssid: existing.bssid
        )
    }

    private func deleteRoom(at offsets: IndexSet) {
        editingRooms.remove(atOffsets: offsets)
    }

    private func moveRoom(from source: IndexSet, to destination: Int) {
        editingRooms.move(fromOffsets: source, toOffset: destination)
    }
}

#Preview {
    RoomEditorSheet(
        rooms: .constant([
            Room(name: "Sala de Estar", icon: "sofa", hasRouter: true),
            Room(name: "Quarto Principal", icon: "bed.double", hasRouter: false)
        ]),
        onSave: { _ in }
    )
    .preferredColorScheme(.dark)
}
