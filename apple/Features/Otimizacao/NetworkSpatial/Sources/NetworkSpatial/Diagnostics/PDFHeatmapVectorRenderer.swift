import CoreGraphics
import CoreText
import Foundation

/// Renderizador vetorial de topologia esquemática e mapa térmico de cômodos para relatórios em PDF.
/// Totalmente compatível com macOS e iOS através de CoreGraphics puro sem UIKit/AppKit.
public enum PDFHeatmapVectorRenderer {

    /// Desenha o mapa vetorial esquemático dos cômodos da residência dentro do retângulo delimitador especificado
    public static func renderHeatmap(
        rooms: [Room],
        in context: CGContext,
        rect: CGRect
    ) {
        context.saveGState()

        // 1. Fundo do container da planta esquemática
        let containerPath = CGPath(
            roundedRect: rect,
            cornerWidth: 8,
            cornerHeight: 8,
            transform: nil
        )
        context.setFillColor(CGColor(gray: 0.97, alpha: 1.0))
        context.addPath(containerPath)
        context.fillPath()

        context.setStrokeColor(CGColor(gray: 0.88, alpha: 1.0))
        context.setLineWidth(1.0)
        context.addPath(containerPath)
        context.strokePath()

        guard !rooms.isEmpty else {
            drawCenteredText(
                "Nenhum cômodo medido para exibição esquemática.",
                in: rect,
                fontSize: 9,
                color: CGColor(gray: 0.55, alpha: 1.0),
                context: context
            )
            context.restoreGState()
            return
        }

        // 2. Determinação da grade (Grid auto-adaptativo ou coordenadas espaciais)
        let count = rooms.count
        let cols: Int
        let rows: Int

        if count <= 3 {
            cols = count
            rows = 1
        } else if count <= 6 {
            cols = 3
            rows = 2
        } else if count <= 8 {
            cols = 4
            rows = 2
        } else {
            cols = 4
            rows = Int(ceil(Double(count) / 4.0))
        }

        let padding: CGFloat = 8.0
        let cellWidth = max(20.0, (rect.width - padding * CGFloat(cols + 1)) / CGFloat(cols))
        let cellHeight = max(20.0, (rect.height - padding * CGFloat(rows + 1)) / CGFloat(rows))

        for (index, room) in rooms.prefix(cols * rows).enumerated() {
            let col = index % cols
            let row = index / cols

            // Em CoreGraphics no PDF (unflipped), o topo está em rect.maxY
            let cellX = rect.minX + padding + CGFloat(col) * (cellWidth + padding)
            let cellY = rect.maxY - padding - CGFloat(row + 1) * cellHeight

            let cellRect = CGRect(x: cellX, y: cellY, width: cellWidth, height: cellHeight)
            drawRoomCard(room: room, in: cellRect, context: context)
        }

        context.restoreGState()
    }

    private static func drawRoomCard(
        room: Room,
        in cellRect: CGRect,
        context: CGContext
    ) {
        let rating = room.currentRating
        let (fillColor, strokeColor, badgeTextColor) = colors(for: rating)

        // Cartão do cômodo
        let path = CGPath(
            roundedRect: cellRect,
            cornerWidth: 6,
            cornerHeight: 6,
            transform: nil
        )
        context.setFillColor(fillColor)
        context.addPath(path)
        context.fillPath()

        context.setStrokeColor(strokeColor)
        context.setLineWidth(1.0)
        context.addPath(path)
        context.strokePath()

        // Textos dentro da célula
        let innerPadding: CGFloat = 6.0

        // 1. Nome do Cômodo
        let nameFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 8.5, nil)
        let nameString = NSAttributedString(
            string: room.name,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): nameFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.12, alpha: 1.0)
            ]
        )
        let nameLine = CTLineCreateWithAttributedString(nameString)
        context.textPosition = CGPoint(x: cellRect.minX + innerPadding, y: cellRect.maxY - 14)
        CTLineDraw(nameLine, context)

        // 2. Score / Rating
        let scoreFont = CTFontCreateWithName("Helvetica" as CFString, 7.5, nil)
        let ratingText: String
        if let measurement = room.lastMeasurement {
            ratingText = "\(rating.label) (\(measurement.score) pts)"
        } else {
            ratingText = "Não Medido"
        }

        let scoreString = NSAttributedString(
            string: ratingText,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): scoreFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): badgeTextColor
            ]
        )
        let scoreLine = CTLineCreateWithAttributedString(scoreString)
        context.textPosition = CGPoint(x: cellRect.minX + innerPadding, y: cellRect.maxY - 25)
        CTLineDraw(scoreLine, context)

        // 3. Indicador de Ponto de Acesso / Roteador
        if room.hasRouter || (room.accessPoint != nil && room.accessPoint?.type != AccessPointType.none) {
            let apType = room.accessPoint?.type ?? (room.hasRouter ? .mainRouter : .none)
            let apLabel: String
            switch apType {
            case .mainRouter:
                apLabel = "● Roteador Principal"
            case .meshSatellite:
                apLabel = "● Satélite Mesh"
            case .repeater:
                apLabel = "● Repetidor Wi-Fi"
            case .none:
                apLabel = ""
            }

            if !apLabel.isEmpty {
                let apFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 6.5, nil)
                let apString = NSAttributedString(
                    string: apLabel,
                    attributes: [
                        NSAttributedString.Key(kCTFontAttributeName as String): apFont,
                        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 124 / 255, green: 58 / 255, blue: 237 / 255, alpha: 1.0)
                    ]
                )
                let apLine = CTLineCreateWithAttributedString(apString)
                context.textPosition = CGPoint(x: cellRect.minX + innerPadding, y: max(cellRect.minY + 4, cellRect.maxY - 35))
                CTLineDraw(apLine, context)
            }
        }
    }

    private static func colors(for rating: QualityRating) -> (fill: CGColor, stroke: CGColor, text: CGColor) {
        switch rating {
        case .excellent:
            return (
                CGColor(red: 34 / 255, green: 197 / 255, blue: 94 / 255, alpha: 0.12),
                CGColor(red: 34 / 255, green: 197 / 255, blue: 94 / 255, alpha: 0.8),
                CGColor(red: 34 / 255, green: 197 / 255, blue: 94 / 255, alpha: 1.0)
            )
        case .good:
            return (
                CGColor(red: 124 / 255, green: 58 / 255, blue: 237 / 255, alpha: 0.10),
                CGColor(red: 124 / 255, green: 58 / 255, blue: 237 / 255, alpha: 0.7),
                CGColor(red: 91 / 255, green: 33 / 255, blue: 182 / 255, alpha: 1.0)
            )
        case .fair:
            return (
                CGColor(red: 245 / 255, green: 158 / 255, blue: 11 / 255, alpha: 0.12),
                CGColor(red: 245 / 255, green: 158 / 255, blue: 11 / 255, alpha: 0.8),
                CGColor(red: 245 / 255, green: 158 / 255, blue: 11 / 255, alpha: 1.0)
            )
        case .poor:
            return (
                CGColor(red: 1.0, green: 90 / 255, blue: 54 / 255, alpha: 0.12),
                CGColor(red: 1.0, green: 90 / 255, blue: 54 / 255, alpha: 0.8),
                CGColor(red: 1.0, green: 90 / 255, blue: 54 / 255, alpha: 1.0)
            )
        case .unmeasured:
            return (
                CGColor(gray: 0.94, alpha: 1.0),
                CGColor(gray: 0.78, alpha: 1.0),
                CGColor(gray: 0.50, alpha: 1.0)
            )
        }
    }

    private static func drawCenteredText(
        _ text: String,
        in rect: CGRect,
        fontSize: CGFloat,
        color: CGColor,
        context: CGContext
    ) {
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attr = NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
            ]
        )
        let line = CTLineCreateWithAttributedString(attr)
        let textBounds = CTLineGetBoundsWithOptions(line, [])
        let x = rect.midX - (textBounds.width / 2.0)
        let y = rect.midY - (textBounds.height / 2.0)
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
    }
}
