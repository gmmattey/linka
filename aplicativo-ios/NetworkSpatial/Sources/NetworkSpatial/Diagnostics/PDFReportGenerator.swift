import CoreGraphics
import CoreText
import Foundation

/// Estrutura de dados contendo todas as informações para geração do Relatório Técnico em PDF.
public struct TechnicalAuditReportData: Sendable {
    public let houseName: String
    public let generatedDate: Date
    public let ssid: String
    public let gatewayIP: String
    public let accessPoints: [AccessPointNode]
    public let rooms: [Room]
    public let totalCoveragePercent: Int
    public let executiveSummary: String
    public let ispTechnicalNotice: String

    public init(
        houseName: String,
        generatedDate: Date = Date(),
        ssid: String,
        gatewayIP: String,
        accessPoints: [AccessPointNode] = [],
        rooms: [Room] = [],
        totalCoveragePercent: Int,
        executiveSummary: String,
        ispTechnicalNotice: String
    ) {
        self.houseName = houseName
        self.generatedDate = generatedDate
        self.ssid = ssid
        self.gatewayIP = gatewayIP
        self.accessPoints = accessPoints
        self.rooms = rooms
        self.totalCoveragePercent = totalCoveragePercent
        self.executiveSummary = executiveSummary
        self.ispTechnicalNotice = ispTechnicalNotice
    }
}

/// Erros possíveis na geração do relatório em PDF.
public enum PDFReportError: LocalizedError, Sendable {
    case contextCreationFailed
    case documentEmpty
    case fileSystemError(String)

    public var errorDescription: String? {
        switch self {
        case .contextCreationFailed:
            return "Não foi possível inicializar o contexto gráfico de PDF."
        case .documentEmpty:
            return "Os dados da auditoria estão vazios."
        case .fileSystemError(let details):
            return "Falha ao gravar arquivo PDF no disco: \(details)"
        }
    }
}

/// Motor determinístico de renderização do Relatório Técnico Profissional em PDF no padrão A4.
///
/// Desenvolvido em CoreGraphics / CoreText puro para garantir compilação e execução
/// universal tanto em iOS quanto no macOS (testes de linha de comando `swift test`),
/// sem qualquer dependência de `UIGraphicsPDFRenderer` ou `UIKit`.
public enum PDFReportGenerator {
    private static let pageWidth: CGFloat = 595.2 // A4 (pontos)
    private static let pageHeight: CGFloat = 841.8
    private static let marginHorizontal: CGFloat = 40.0
    private static let contentWidth: CGFloat = pageWidth - (marginHorizontal * 2) // 515.2

    /// Gera o arquivo PDF da auditoria técnica e retorna a URL no sistema de arquivos temporário
    public static func generateAuditReportPDF(data: TechnicalAuditReportData) throws -> URL {
        let fileName = "relatorio-wificasa-\(UUID().uuidString).pdf"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let consumer = CGDataConsumer(url: outputURL as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PDFReportError.contextCreationFailed
        }

        // Calculamos distribuição de cômodos por página para paginação automática
        let rooms = data.rooms
        let maxRoomsFirstPage = 7
        let roomsFirstPage = Array(rooms.prefix(maxRoomsFirstPage))
        let remainingRooms = rooms.count > maxRoomsFirstPage ? Array(rooms.suffix(from: maxRoomsFirstPage)) : []

        let totalPages = remainingRooms.isEmpty ? 1 : 1 + Int(ceil(Double(remainingRooms.count) / 18.0))

        // PÁGINA 1
        context.beginPDFPage(nil)
        renderPage1(data: data, roomsOnPage: roomsFirstPage, hasMorePages: !remainingRooms.isEmpty, page: 1, totalPages: totalPages, in: context)
        context.endPDFPage()

        // PÁGINAS ADICIONAIS (se houver muitos cômodos)
        if !remainingRooms.isEmpty {
            let roomsPerPage = 18
            var pageIndex = 2
            var offset = 0
            while offset < remainingRooms.count {
                let chunkEnd = min(offset + roomsPerPage, remainingRooms.count)
                let pageChunk = Array(remainingRooms[offset..<chunkEnd])

                context.beginPDFPage(nil)
                renderContinuationPage(
                    data: data,
                    roomsOnPage: pageChunk,
                    isLastPage: chunkEnd >= remainingRooms.count,
                    page: pageIndex,
                    totalPages: totalPages,
                    in: context
                )
                context.endPDFPage()

                offset += roomsPerPage
                pageIndex += 1
            }
        }

        context.closePDF()
        return outputURL
    }

    // MARK: - Renderização da Página 1

    private static func renderPage1(
        data: TechnicalAuditReportData,
        roomsOnPage: [Room],
        hasMorePages: Bool,
        page: Int,
        totalPages: Int,
        in context: CGContext
    ) {
        // 1. Cabeçalho Principal (Y top: 40)
        var cursorY: CGFloat = 40.0

        // Barra decorativa da marca WiFi Casa
        let brandBar = CGRect(x: marginHorizontal, y: toCGY(cursorY + 4), width: 4.0, height: 28.0)
        drawFilledRect(brandBar, color: CGColor(red: 124 / 255, green: 58 / 255, blue: 237 / 255, alpha: 1.0), in: context)

        drawText(
            "WiFi Casa — Relatório Técnico de Qualidade Wi-Fi",
            x: marginHorizontal + 12,
            topY: cursorY + 4,
            font: CTFontCreateWithName("Helvetica-Bold" as CFString, 15.0, nil),
            color: CGColor(gray: 0.12, alpha: 1.0),
            in: context
        )

        drawText(
            "Diagnóstico de Qualidade Wi-Fi Residencial & Análise LAN vs. WAN",
            x: marginHorizontal + 12,
            topY: cursorY + 22,
            font: CTFontCreateWithName("Helvetica" as CFString, 8.5, nil),
            color: CGColor(gray: 0.50, alpha: 1.0),
            in: context
        )

        cursorY += 40.0
        drawHorizontalDivider(topY: cursorY, in: context)
        cursorY += 12.0

        // 2. Quadro de Metadados da Auditoria
        let metaBoxHeight: CGFloat = 52.0
        let metaBoxRect = CGRect(x: marginHorizontal, y: toCGY(cursorY + metaBoxHeight), width: contentWidth, height: metaBoxHeight)
        drawCard(rect: metaBoxRect, fillColor: CGColor(gray: 0.97, alpha: 1.0), strokeColor: CGColor(gray: 0.88, alpha: 1.0), cornerRadius: 6, in: context)

        let col1X = marginHorizontal + 12.0
        let col2X = marginHorizontal + 185.0
        let col3X = marginHorizontal + 360.0

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy HH:mm"
        let dateStr = dateFormatter.string(from: data.generatedDate)

        drawKeyValue(key: "Residência:", value: data.houseName, x: col1X, topY: cursorY + 12, in: context)
        drawKeyValue(key: "Rede (SSID):", value: data.ssid, x: col1X, topY: cursorY + 30, in: context)

        drawKeyValue(key: "Gateway Local:", value: data.gatewayIP, x: col2X, topY: cursorY + 12, in: context)
        drawKeyValue(key: "Data da Emissão:", value: dateStr, x: col2X, topY: cursorY + 30, in: context)

        let covStr = "\(data.totalCoveragePercent)%"
        drawKeyValue(key: "Qualidade Média:", value: covStr, x: col3X, topY: cursorY + 12, valueColor: coverageColor(data.totalCoveragePercent), in: context)
        let apsCount = data.accessPoints.count
        let apsStr = apsCount > 0 ? "\(apsCount) \(apsCount == 1 ? "nó ativo" : "nós ativos")" : "1 roteador principal"
        drawKeyValue(key: "Topologia:", value: apsStr, x: col3X, topY: cursorY + 30, in: context)

        cursorY += metaBoxHeight + 14.0

        // 3. Seção 1: Resumo Executivo
        drawSectionTitle("1. RESUMO EXECUTIVO", topY: cursorY, in: context)
        cursorY += 16.0

        let summaryHeight: CGFloat = 36.0
        let summaryRect = CGRect(x: marginHorizontal, y: toCGY(cursorY + summaryHeight), width: contentWidth, height: summaryHeight)
        drawParagraph(data.executiveSummary, in: summaryRect, fontSize: 8.5, color: CGColor(gray: 0.20, alpha: 1.0), in: context)
        cursorY += summaryHeight + 12.0

        // 4. Seção 2: Topologia Esquemática & Mapa Térmico
        drawSectionTitle("2. TOPOLOGIA ESQUEMÁTICA E QUALIDADE RELATIVA", topY: cursorY, in: context)
        cursorY += 16.0

        let heatmapHeight: CGFloat = 85.0
        let heatmapRect = CGRect(x: marginHorizontal, y: toCGY(cursorY + heatmapHeight), width: contentWidth, height: heatmapHeight)
        PDFHeatmapVectorRenderer.renderHeatmap(rooms: data.rooms, in: context, rect: heatmapRect)
        cursorY += heatmapHeight + 14.0

        // 5. Seção 3: Tabela Detalhada por Cômodo
        drawSectionTitle("3. DIAGNÓSTICO DETALHADO POR CÔMODO (LAN vs. WAN)", topY: cursorY, in: context)
        cursorY += 16.0

        cursorY = renderRoomsTable(rooms: roomsOnPage, startTopY: cursorY, in: context)
        cursorY += 12.0

        // 6. Seção 4: Análise Comparativa Externa
        if !hasMorePages {
            drawSectionTitle("4. ANÁLISE COMPARATIVA COM A CONEXÃO EXTERNA (WAN)", topY: cursorY, in: context)
            cursorY += 16.0

            let noticeBoxHeight: CGFloat = 65.0
            let noticeRect = CGRect(x: marginHorizontal, y: toCGY(cursorY + noticeBoxHeight), width: contentWidth, height: noticeBoxHeight)
            drawNoticeCard(data.ispTechnicalNotice, in: noticeRect, context: context)
        }

        // 7. Rodapé de Privacidade
        renderFooter(page: page, totalPages: totalPages, in: context)
    }

    // MARK: - Renderização de Páginas de Continuação

    private static func renderContinuationPage(
        data: TechnicalAuditReportData,
        roomsOnPage: [Room],
        isLastPage: Bool,
        page: Int,
        totalPages: Int,
        in context: CGContext
    ) {
        var cursorY: CGFloat = 40.0

        drawText(
            "WiFi Casa — Relatório Técnico de Qualidade Wi-Fi (Continuação)",
            x: marginHorizontal,
            topY: cursorY + 4,
            font: CTFontCreateWithName("Helvetica-Bold" as CFString, 12.0, nil),
            color: CGColor(gray: 0.12, alpha: 1.0),
            in: context
        )
        cursorY += 24.0
        drawHorizontalDivider(topY: cursorY, in: context)
        cursorY += 16.0

        drawSectionTitle("3. DIAGNÓSTICO DETALHADO POR CÔMODO (CONTINUAÇÃO)", topY: cursorY, in: context)
        cursorY += 16.0

        cursorY = renderRoomsTable(rooms: roomsOnPage, startTopY: cursorY, in: context)
        cursorY += 16.0

        if isLastPage {
            drawSectionTitle("4. ANÁLISE COMPARATIVA COM A CONEXÃO EXTERNA (WAN)", topY: cursorY, in: context)
            cursorY += 16.0

            let noticeBoxHeight: CGFloat = 75.0
            let noticeRect = CGRect(x: marginHorizontal, y: toCGY(cursorY + noticeBoxHeight), width: contentWidth, height: noticeBoxHeight)
            drawNoticeCard(data.ispTechnicalNotice, in: noticeRect, context: context)
        }

        renderFooter(page: page, totalPages: totalPages, in: context)
    }

    // MARK: - Tabela de Cômodos (LAN vs WAN)

    private static func renderRoomsTable(rooms: [Room], startTopY: CGFloat, in context: CGContext) -> CGFloat {
        var cursorY = startTopY
        let headerHeight: CGFloat = 20.0
        let rowHeight: CGFloat = 18.0

        // Cabeçalho da Tabela
        let headerRect = CGRect(x: marginHorizontal, y: toCGY(cursorY + headerHeight), width: contentWidth, height: headerHeight)
        drawCard(rect: headerRect, fillColor: CGColor(gray: 0.92, alpha: 1.0), strokeColor: nil, cornerRadius: 4, in: context)

        // Larguras das Colunas
        let colWidths: [CGFloat] = [105, 75, 48, 48, 52, 48, 52, 87]
        let headers = ["Cômodo", "Nó Conect.", "Ping LAN", "Jitter", "Perda LAN", "Ping WAN", "Perda WAN", "Classificação"]

        var colX = marginHorizontal + 6.0
        for (i, h) in headers.enumerated() {
            drawText(h, x: colX, topY: cursorY + 5, font: CTFontCreateWithName("Helvetica-Bold" as CFString, 7.5, nil), color: CGColor(gray: 0.25, alpha: 1.0), in: context)
            colX += colWidths[i]
        }
        cursorY += headerHeight

        // Linhas de Dados
        for (rowIndex, room) in rooms.enumerated() {
            let rowY = cursorY
            if rowIndex % 2 == 1 {
                let rowBgRect = CGRect(x: marginHorizontal, y: toCGY(rowY + rowHeight), width: contentWidth, height: rowHeight)
                drawCard(rect: rowBgRect, fillColor: CGColor(gray: 0.98, alpha: 1.0), strokeColor: nil, cornerRadius: 2, in: context)
            }

            var cellX = marginHorizontal + 6.0

            // 1. Cômodo
            drawText(room.name, x: cellX, topY: rowY + 5, font: CTFontCreateWithName("Helvetica-Bold" as CFString, 7.5, nil), color: CGColor(gray: 0.15, alpha: 1.0), in: context)
            cellX += colWidths[0]

            // 2. Nó Conectado
            let nodeName = room.lastMeasurement?.metrics.connectedNodeName ?? room.accessPoint?.name ?? (room.hasRouter ? "Roteador" : "—")
            drawText(nodeName, x: cellX, topY: rowY + 5, font: CTFontCreateWithName("Helvetica" as CFString, 7.0, nil), color: CGColor(gray: 0.35, alpha: 1.0), in: context)
            cellX += colWidths[1]

            if let m = room.lastMeasurement {
                // 3. Ping LAN
                drawText("\(String(format: "%.0f", m.metrics.gatewayLatencyMs)) ms", x: cellX, topY: rowY + 5, font: CTFontCreateWithName("Helvetica" as CFString, 7.0, nil), color: CGColor(gray: 0.20, alpha: 1.0), in: context)
                cellX += colWidths[2]

                // 4. Jitter LAN
                drawText("\(String(format: "%.1f", m.metrics.gatewayJitterMs)) ms", x: cellX, topY: rowY + 5, font: CTFontCreateWithName("Helvetica" as CFString, 7.0, nil), color: CGColor(gray: 0.20, alpha: 1.0), in: context)
                cellX += colWidths[3]

                // 5. Perda LAN
                let lanLossColor = m.metrics.gatewayPacketLossPercent > 0 ? CGColor(red: 1.0, green: 90 / 255, blue: 54 / 255, alpha: 1.0) : CGColor(gray: 0.20, alpha: 1.0)
                drawText("\(String(format: "%.1f", m.metrics.gatewayPacketLossPercent))%", x: cellX, topY: rowY + 5, font: CTFontCreateWithName("Helvetica" as CFString, 7.0, nil), color: lanLossColor, in: context)
                cellX += colWidths[4]

                // 6. Ping WAN
                drawText("\(String(format: "%.0f", m.metrics.wanLatencyMs)) ms", x: cellX, topY: rowY + 5, font: CTFontCreateWithName("Helvetica" as CFString, 7.0, nil), color: CGColor(gray: 0.20, alpha: 1.0), in: context)
                cellX += colWidths[5]

                // 7. Perda WAN
                let wanLossColor = m.metrics.wanPacketLossPercent > 0 ? CGColor(red: 1.0, green: 90 / 255, blue: 54 / 255, alpha: 1.0) : CGColor(gray: 0.20, alpha: 1.0)
                drawText("\(String(format: "%.1f", m.metrics.wanPacketLossPercent))%", x: cellX, topY: rowY + 5, font: CTFontCreateWithName("Helvetica" as CFString, 7.0, nil), color: wanLossColor, in: context)
                cellX += colWidths[6]

                // 8. Classificação
                let ratingColor = colorForRating(m.rating)
                drawText(m.rating.label, x: cellX, topY: rowY + 5, font: CTFontCreateWithName("Helvetica-Bold" as CFString, 7.0, nil), color: ratingColor, in: context)
            } else {
                for i in 2..<7 {
                    drawText("—", x: cellX, topY: rowY + 5, font: CTFontCreateWithName("Helvetica" as CFString, 7.0, nil), color: CGColor(gray: 0.50, alpha: 1.0), in: context)
                    cellX += colWidths[i]
                }
                drawText("Não Medido", x: cellX, topY: rowY + 5, font: CTFontCreateWithName("Helvetica" as CFString, 7.0, nil), color: CGColor(gray: 0.50, alpha: 1.0), in: context)
            }

            cursorY += rowHeight
        }

        // Borda inferior da tabela
        drawHorizontalDivider(topY: cursorY + 2, in: context)
        return cursorY + 4
    }

    // MARK: - Cartão de Parecer Técnico para Operadora

    private static func drawNoticeCard(_ text: String, in rect: CGRect, context: CGContext) {
        // Fundo com borda lateral Roxo Gamer.
        drawCard(rect: rect, fillColor: CGColor(red: 0.96, green: 0.94, blue: 1.0, alpha: 1.0), strokeColor: CGColor(red: 167 / 255, green: 139 / 255, blue: 250 / 255, alpha: 1.0), cornerRadius: 6, in: context)

        let highlightBar = CGRect(x: rect.minX, y: rect.minY, width: 4.0, height: rect.height)
        drawFilledRect(highlightBar, color: CGColor(red: 124 / 255, green: 58 / 255, blue: 237 / 255, alpha: 1.0), in: context)

        let textRect = CGRect(x: rect.minX + 12, y: rect.minY + 6, width: rect.width - 20, height: rect.height - 12)
        drawParagraph(text, in: textRect, fontSize: 8.0, color: CGColor(gray: 0.18, alpha: 1.0), in: context)
    }

    // MARK: - Rodapé

    private static func renderFooter(page: Int, totalPages: Int, in context: CGContext) {
        drawHorizontalDivider(topY: 841.8 - 45.0, in: context)

        drawText(
            "Gerado localmente pelo app WiFi Casa. Custo zero, sem servidores externos.",
            x: marginHorizontal,
            topY: 841.8 - 32.0,
            font: CTFontCreateWithName("Helvetica" as CFString, 7.5, nil),
            color: CGColor(gray: 0.55, alpha: 1.0),
            in: context
        )

        let pageText = "Página \(page) de \(totalPages)"
        let pageFont = CTFontCreateWithName("Helvetica" as CFString, 7.5, nil)
        let attr = NSAttributedString(
            string: pageText,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): pageFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.55, alpha: 1.0)
            ]
        )
        let line = CTLineCreateWithAttributedString(attr)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        let x = marginHorizontal + contentWidth - bounds.width
        context.textPosition = CGPoint(x: x, y: toCGY(841.8 - 32.0))
        CTLineDraw(line, context)
    }

    // MARK: - Helpers de Desenho e Tipografia

    private static func toCGY(_ topY: CGFloat) -> CGFloat {
        pageHeight - topY
    }

    private static func drawSectionTitle(_ title: String, topY: CGFloat, in context: CGContext) {
        drawText(
            title,
            x: marginHorizontal,
            topY: topY,
            font: CTFontCreateWithName("Helvetica-Bold" as CFString, 9.5, nil),
            color: CGColor(red: 124 / 255, green: 58 / 255, blue: 237 / 255, alpha: 1.0),
            in: context
        )
    }

    private static func drawKeyValue(
        key: String,
        value: String,
        x: CGFloat,
        topY: CGFloat,
        valueColor: CGColor? = nil,
        in context: CGContext
    ) {
        let keyFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 8.0, nil)
        let valFont = CTFontCreateWithName("Helvetica" as CFString, 8.0, nil)

        let attrKey = NSAttributedString(
            string: "\(key) ",
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): keyFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.40, alpha: 1.0)
            ]
        )
        let keyLine = CTLineCreateWithAttributedString(attrKey)
        let keyBounds = CTLineGetBoundsWithOptions(keyLine, [])

        context.textPosition = CGPoint(x: x, y: toCGY(topY))
        CTLineDraw(keyLine, context)

        let attrVal = NSAttributedString(
            string: value,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): valFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): valueColor ?? CGColor(gray: 0.15, alpha: 1.0)
            ]
        )
        let valLine = CTLineCreateWithAttributedString(attrVal)
        context.textPosition = CGPoint(x: x + keyBounds.width, y: toCGY(topY))
        CTLineDraw(valLine, context)
    }

    private static func drawText(
        _ text: String,
        x: CGFloat,
        topY: CGFloat,
        font: CTFont,
        color: CGColor,
        in context: CGContext
    ) {
        let attr = NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
            ]
        )
        let line = CTLineCreateWithAttributedString(attr)
        context.textPosition = CGPoint(x: x, y: toCGY(topY))
        CTLineDraw(line, context)
    }

    private static func drawParagraph(
        _ text: String,
        in rect: CGRect,
        fontSize: CGFloat,
        color: CGColor,
        in context: CGContext
    ) {
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attr = NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attr.length), path, nil)
        CTFrameDraw(frame, context)
    }

    private static func drawCard(
        rect: CGRect,
        fillColor: CGColor,
        strokeColor: CGColor?,
        cornerRadius: CGFloat,
        in context: CGContext
    ) {
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.setFillColor(fillColor)
        context.addPath(path)
        context.fillPath()

        if let strokeColor {
            context.setStrokeColor(strokeColor)
            context.setLineWidth(1.0)
            context.addPath(path)
            context.strokePath()
        }
    }

    private static func drawFilledRect(_ rect: CGRect, color: CGColor, in context: CGContext) {
        context.setFillColor(color)
        context.fill(rect)
    }

    private static func drawHorizontalDivider(topY: CGFloat, in context: CGContext) {
        context.setStrokeColor(CGColor(gray: 0.88, alpha: 1.0))
        context.setLineWidth(0.8)
        context.beginPath()
        context.move(to: CGPoint(x: marginHorizontal, y: toCGY(topY)))
        context.addLine(to: CGPoint(x: marginHorizontal + contentWidth, y: toCGY(topY)))
        context.strokePath()
    }

    private static func colorForRating(_ rating: QualityRating) -> CGColor {
        switch rating {
        case .excellent:
            return CGColor(red: 34 / 255, green: 197 / 255, blue: 94 / 255, alpha: 1.0)
        case .good:
            return CGColor(red: 124 / 255, green: 58 / 255, blue: 237 / 255, alpha: 1.0)
        case .fair:
            return CGColor(red: 245 / 255, green: 158 / 255, blue: 11 / 255, alpha: 1.0)
        case .poor:
            return CGColor(red: 1.0, green: 90 / 255, blue: 54 / 255, alpha: 1.0)
        case .unmeasured:
            return CGColor(gray: 0.50, alpha: 1.0)
        }
    }

    private static func coverageColor(_ percent: Int) -> CGColor {
        if percent >= 85 {
            return CGColor(red: 34 / 255, green: 197 / 255, blue: 94 / 255, alpha: 1.0)
        } else if percent >= 70 {
            return CGColor(red: 124 / 255, green: 58 / 255, blue: 237 / 255, alpha: 1.0)
        } else if percent >= 50 {
            return CGColor(red: 245 / 255, green: 158 / 255, blue: 11 / 255, alpha: 1.0)
        } else {
            return CGColor(red: 1.0, green: 90 / 255, blue: 54 / 255, alpha: 1.0)
        }
    }
}
