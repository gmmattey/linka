import Foundation

public struct SpatialLayoutEngine: Sendable {

    /// Calcula a distância Manhattan em grid entre dois cômodos
    public static func distance(from roomA: Room, to roomB: Room) -> Int {
        abs(roomA.gridX - roomB.gridX) + abs(roomA.gridY - roomB.gridY)
    }

    /// Constrói uma rota otimizada de caminhada iniciando no roteador e visitando os vizinhos mais próximos (Manhattan TSP)
    public static func buildWalkRoute(rooms: [Room]) -> [Room] {
        guard !rooms.isEmpty else { return [] }
        guard rooms.count > 1 else { return rooms }

        var remaining = rooms
        var route: [Room] = []

        // 1. Início prioritário no cômodo do roteador principal
        let startIndex = remaining.firstIndex(where: { $0.hasRouter || $0.accessPoint?.type == .mainRouter }) ?? 0
        var current = remaining.remove(at: startIndex)
        route.append(current)

        // 2. Algoritmo guloso do vizinho mais próximo em distância Manhattan
        while !remaining.isEmpty {
            let nearestIndex = remaining.indices.min(by: { idx0, idx1 in
                let dist0 = distance(from: current, to: remaining[idx0])
                let dist1 = distance(from: current, to: remaining[idx1])
                if dist0 != dist1 {
                    return dist0 < dist1
                }
                if remaining[idx0].gridY != remaining[idx1].gridY {
                    return remaining[idx0].gridY < remaining[idx1].gridY
                }
                return remaining[idx0].gridX < remaining[idx1].gridX
            }) ?? 0

            current = remaining.remove(at: nearestIndex)
            route.append(current)
        }

        return route
    }

    /// Calcula a cobertura total ponderada da residência (%)
    public static func calculateHouseCoverage(rooms: [Room]) -> Int {
        let measuredRooms = rooms.compactMap(\.lastMeasurement)
        guard !measuredRooms.isEmpty else { return 0 }
        let totalScore = measuredRooms.reduce(0) { $0 + $1.score }
        return Int(round(Double(totalScore) / Double(measuredRooms.count)))
    }

    /// Gera uma comparação Antes × Depois entre o baseline inicial e a rodada atual
    public static func generateComparison(
        title: String = "Comparativo de Qualidade",
        baselineRooms: [Room],
        afterRooms: [Room]
    ) -> BeforeAfterComparison {
        let baselineCoverage = calculateHouseCoverage(rooms: baselineRooms)
        let afterCoverage = calculateHouseCoverage(rooms: afterRooms)

        var roomComparisons: [RoomComparison] = []

        // Mapeia cômodo por nome ou ID
        for afterRoom in afterRooms {
            let beforeRoom = baselineRooms.first(where: { $0.id == afterRoom.id || $0.name == afterRoom.name })
            let beforeRating = beforeRoom?.currentRating ?? .unmeasured
            let beforeScore = beforeRoom?.currentScore ?? 0

            let comparison = RoomComparison(
                roomName: afterRoom.name,
                roomIcon: afterRoom.icon,
                beforeRating: beforeRating,
                beforeScore: beforeScore,
                afterRating: afterRoom.currentRating,
                afterScore: afterRoom.currentScore
            )
            roomComparisons.append(comparison)
        }

        return BeforeAfterComparison(
            title: title,
            date: Date(),
            baselineCoveragePercent: baselineCoverage,
            afterCoveragePercent: afterCoverage,
            roomComparisons: roomComparisons
        )
    }

    /// Gera recomendações inteligentes de posicionamento com base na topologia da casa
    public static func generateRecommendations(rooms: [Room]) -> [String] {
        guard let routerRoom = rooms.first(where: \.hasRouter) else {
            return ["Defina qual cômodo abriga o roteador principal para receber recomendações de posicionamento."]
        }

        var recommendations: [String] = []

        let poorRooms = rooms.filter { $0.currentRating == .poor }
        let fairRooms = rooms.filter { $0.currentRating == .fair }
        let unmeasuredCount = rooms.filter { $0.currentRating == .unmeasured }.count

        if unmeasuredCount > 0 {
            recommendations.append("Avalie todos os cômodos da residência para um mapa de qualidade completo. O índice atual reflete apenas os pontos medidos (\(rooms.count - unmeasuredCount) de \(rooms.count)).")
        }

        if !poorRooms.isEmpty {
            let poorNames = poorRooms.map(\.name).joined(separator: ", ")
            recommendations.append("Área crítica detectada em: \(poorNames). Há indício de instabilidade local ou sinal degradado.")

            // Análise topológica de distância
            let farthestPoor = poorRooms.max(by: { distance(from: routerRoom, to: $0) < distance(from: routerRoom, to: $1) })
            if let farthest = farthestPoor {
                recommendations.append("Mover o roteador para um ponto mais central ou adicionar um nó mesh a meio caminho de '\(farthest.name)' pode eliminar os pontos cegos.")
            }
        } else if !fairRooms.isEmpty {
            let fairNames = fairRooms.map(\.name).joined(separator: ", ")
            recommendations.append("Sinal moderado em: \(fairNames). Elevar o roteador em 1 metro (longe do chão e de móveis metálicos) já pode melhorar a resposta nesses cômodos.")
        } else if rooms.allSatisfy({ $0.currentRating == .excellent || $0.currentRating == .good }) {
            recommendations.append("Excelente resposta nos cômodos medidos! O roteador em '\(routerRoom.name)' atende os pontos testados com alta estabilidade.")
        }

        return recommendations
    }
}
