import Foundation

#if canImport(RoomPlan) && os(iOS)
import RoomPlan
#endif

/// Parser e conversor determinístico de cômodos capturados via sensor LiDAR / RoomPlan
/// para o modelo canônico de cômodos (`Room`) do WiFi Casa.
public enum RoomPlanParser {

    /// Converte a lista de cômodos capturados pelo escaneamento 3D em cômodos no grid residencial.
    ///
    /// - Parameters:
    ///   - capturedRooms: Lista de superfícies capturadas e delimitadas pela malha espacial.
    ///   - defaultRouterRoomIndex: Índice do cômodo onde o roteador principal está localizado (padrão: 0).
    /// - Returns: Vetor de instâncias `Room` com coordenadas sem sobreposição, ícones semânticos e área em m².
    public static func convertCapturedRoomsToHouseRooms(
        capturedRooms: [CapturedRoomData],
        defaultRouterRoomIndex: Int? = 0
    ) -> [Room] {
        var resultRooms: [Room] = []

        for (index, captured) in capturedRooms.enumerated() {
            let roomId = captured.id
            let cleanName = captured.suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
            let roomName = cleanName.isEmpty ? "Cômodo \(index + 1)" : cleanName

            // Sanitização de área entre 1.0 m² e 500.0 m² para prevenir distorções na planta
            let sanitizedArea = max(1.0, min(500.0, captured.areaSqMeters))

            // Distribuição de grid 2D sem sobreposição (2 colunas)
            let gridX = index % 2
            let gridY = index / 2

            let isRouterRoom = (defaultRouterRoomIndex != nil && index == defaultRouterRoomIndex)

            let apNode: AccessPointNode? = isRouterRoom
                ? AccessPointNode(
                    name: "Roteador Principal",
                    type: .mainRouter,
                    backhaulType: .ethernet,
                    roomId: roomId
                )
                : nil

            let icon = iconForRoomName(roomName)

            let room = Room(
                id: roomId,
                name: roomName,
                icon: icon,
                gridX: gridX,
                gridY: gridY,
                hasRouter: isRouterRoom,
                lastMeasurement: nil,
                accessPoint: apNode,
                floorAreaSqMeters: sanitizedArea,
                isLiDARCaptured: true
            )

            resultRooms.append(room)
        }

        return resultRooms
    }

    /// Mapeia o nome do cômodo para um ícone semântico do SF Symbols.
    public static func iconForRoomName(_ name: String) -> String {
        let lower = name.lowercased()

        if lower.contains("quarto") || lower.contains("suíte") || lower.contains("suite") || lower.contains("dormitório") || lower.contains("dormitorio") {
            return "bed.double"
        } else if lower.contains("sala") || lower.contains("living") || lower.contains("estar") {
            return "sofa"
        } else if lower.contains("cozinha") || lower.contains("jantar") || lower.contains("copa") {
            return "fork.knife"
        } else if lower.contains("banheiro") || lower.contains("lavabo") || lower.contains("bwc") {
            return "bathtub"
        } else if lower.contains("escritório") || lower.contains("escritorio") || lower.contains("office") || lower.contains("estudo") {
            return "laptopcomputer"
        } else if lower.contains("tv") || lower.contains("cinema") || lower.contains("home theater") {
            return "tv"
        } else if lower.contains("garagem") || lower.contains("auto") {
            return "car"
        } else if lower.contains("varanda") || lower.contains("sacada") || lower.contains("jardim") || lower.contains("quintal") {
            return "sun.max"
        } else if lower.contains("hall") || lower.contains("corredor") || lower.contains("entrada") {
            return "door.left.hand.open"
        } else {
            return "house"
        }
    }
}

/// Alias para conformidade com a assinatura de `RoomPlanModelConverter` descrita na arquitetura.
public typealias RoomPlanModelConverter = RoomPlanParser
