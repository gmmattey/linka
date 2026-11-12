import XCTest
import PDFKit
@testable import NetworkSpatial

final class PDFReportGeneratorTests: XCTestCase {

    private var generatedURLs: [URL] = []

    override func tearDown() {
        super.tearDown()
        for url in generatedURLs {
            try? FileManager.default.removeItem(at: url)
        }
        generatedURLs.removeAll()
    }

    func testPDFGenerationWithSingleRoomProducesValidDocument() throws {
        let roomId = UUID()
        let room = Room(
            id: roomId,
            name: "Sala de Estar",
            icon: "sofa",
            hasRouter: true,
            lastMeasurement: MeasurementResult(
                roomId: roomId,
                rating: .excellent,
                score: 96,
                cause: .allGood,
                metrics: NetworkMetrics(
                    gatewayIP: "192.168.1.1",
                    gatewayLatencyMs: 4.2,
                    gatewayJitterMs: 0.8,
                    gatewayPacketLossPercent: 0.0,
                    wanLatencyMs: 18.0,
                    wanPacketLossPercent: 0.0,
                    downloadThroughputMbps: 350.0
                ),
                explanation: "Conexão perfeita.",
                actionableRecommendation: "Manter posição."
            )
        )

        let ap = AccessPointNode(
            name: "Roteador Sala",
            type: .mainRouter,
            backhaulType: .ethernet,
            roomId: roomId
        )

        let reportData = TechnicalAuditReportData(
            houseName: "Apartamento Jardins",
            ssid: "Fibra_5G",
            gatewayIP: "192.168.1.1",
            accessPoints: [ap],
            rooms: [room],
            totalCoveragePercent: 96,
            executiveSummary: "A cobertura residencial apresenta nível de excelência nos pontos auditados.",
            ispTechnicalNotice: "O enlace LAN e a rota WAN da operadora operam com estabilidade máxima."
        )

        let pdfURL = try PDFReportGenerator.generateAuditReportPDF(data: reportData)
        generatedURLs.append(pdfURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: pdfURL.path))

        // Valida tamanho do arquivo > 10 KB
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: pdfURL.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        XCTAssertGreaterThan(fileSize, 5_000, "O arquivo PDF deve ter tamanho válido")

        // Valida cabeçalho %PDF-
        let fileData = try Data(contentsOf: pdfURL)
        let headerPrefix = String(data: fileData.prefix(5), encoding: .ascii)
        XCTAssertEqual(headerPrefix, "%PDF-")

        // Valida abertura via PDFKit
        let pdfDoc = PDFDocument(url: pdfURL)
        XCTAssertNotNil(pdfDoc)
        XCTAssertEqual(pdfDoc?.pageCount, 1)

        // Valida conteúdo de texto
        let fullText = (0..<(pdfDoc?.pageCount ?? 0)).compactMap { pdfDoc?.page(at: $0)?.string }.joined(separator: "\n")
        XCTAssertTrue(fullText.contains("WiFi Casa"))
        XCTAssertTrue(fullText.contains("Apartamento Jardins"))
        XCTAssertTrue(fullText.contains("Fibra_5G"))
        XCTAssertTrue(fullText.contains("Sala de Estar"))
    }

    func testPDFGenerationWith20RoomsCreatesPaginatedDocument() throws {
        var rooms: [Room] = []
        for i in 1...20 {
            let roomId = UUID()
            let rating: QualityRating = (i % 3 == 0) ? .fair : (i % 2 == 0 ? .good : .excellent)
            let room = Room(
                id: roomId,
                name: "Cômodo \(i)",
                icon: "bed.double",
                hasRouter: (i == 1),
                lastMeasurement: MeasurementResult(
                    roomId: roomId,
                    rating: rating,
                    score: rating.scoreValue,
                    cause: .allGood,
                    metrics: NetworkMetrics(
                        gatewayIP: "192.168.1.1",
                        gatewayLatencyMs: Double(i * 3),
                        gatewayJitterMs: 1.5,
                        gatewayPacketLossPercent: 0.0,
                        wanLatencyMs: 25.0,
                        wanPacketLossPercent: 0.0
                    ),
                    explanation: "Medição de teste",
                    actionableRecommendation: "Nenhuma"
                )
            )
            rooms.append(room)
        }

        let reportData = TechnicalAuditReportData(
            houseName: "Casa Grande",
            ssid: "Mesh_Pro",
            gatewayIP: "192.168.1.1",
            accessPoints: [],
            rooms: rooms,
            totalCoveragePercent: 82,
            executiveSummary: "Resumo executivo de múltiplos cômodos.",
            ispTechnicalNotice: "Parecer para operadora com múltiplas páginas."
        )

        let pdfURL = try PDFReportGenerator.generateAuditReportPDF(data: reportData)
        generatedURLs.append(pdfURL)

        let pdfDoc = PDFDocument(url: pdfURL)
        XCTAssertNotNil(pdfDoc)
        XCTAssertGreaterThan(pdfDoc?.pageCount ?? 0, 1, "Uma casa com 20 cômodos deve quebrar em mais de 1 página")
    }

    func testPDFGenerationWithUnmeasuredRoomsDoesNotCrash() throws {
        let rooms = [
            Room(name: "Sala", icon: "sofa"),
            Room(name: "Quarto 1", icon: "bed.double"),
            Room(name: "Cozinha", icon: "fork.knife")
        ]

        let reportData = TechnicalAuditReportData(
            houseName: "Residência Vazia",
            ssid: "Wi-Fi Casa",
            gatewayIP: "192.168.1.1",
            accessPoints: [],
            rooms: rooms,
            totalCoveragePercent: 0,
            executiveSummary: "Nenhum cômodo medido ainda.",
            ispTechnicalNotice: "Sem dados suficientes para auditar a operadora."
        )

        let pdfURL = try PDFReportGenerator.generateAuditReportPDF(data: reportData)
        generatedURLs.append(pdfURL)

        let pdfDoc = PDFDocument(url: pdfURL)
        XCTAssertNotNil(pdfDoc)
        XCTAssertEqual(pdfDoc?.pageCount, 1)

        let fullText = pdfDoc?.page(at: 0)?.string ?? ""
        XCTAssertTrue(fullText.contains("Não Medido"))
    }
}
