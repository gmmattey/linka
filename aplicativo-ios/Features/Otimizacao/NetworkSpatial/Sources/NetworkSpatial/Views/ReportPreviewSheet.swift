import SwiftUI
import PDFKit

#if os(iOS)
import UIKit

public struct PDFKitRepresentedView: UIViewRepresentable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    public func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}
#elseif os(macOS)
import AppKit

public struct PDFKitRepresentedView: NSViewRepresentable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    public func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}
#endif

/// Folha de pré-visualização e compartilhamento do Relatório Técnico em PDF (A4).
@available(iOS 17.0, macOS 14.0, *)
public struct ReportPreviewSheet: View {
    public let house: House
    public let ssid: String
    public let gatewayIP: String

    @Environment(\.dismiss) private var dismiss
    @State private var pdfURL: URL? = nil
    @State private var isGenerating: Bool = true
    @State private var errorMessage: String? = nil

    public init(
        house: House,
        ssid: String = "Wi-Fi Residencial",
        gatewayIP: String = "Não identificado"
    ) {
        self.house = house
        self.ssid = ssid
        self.gatewayIP = gatewayIP
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                WiFiCasaTheme.backgroundBase.ignoresSafeArea()

                if isGenerating {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(WiFiCasaTheme.brandAccent)
                            .scaleEffect(1.3)

                        Text(SpatialCopy.value("spatial.pdf.rendering", defaultValue: "Renderizando Relatório Técnico Vetorial..."))
                            .font(.subheadline)
                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                    }
                } else if let error = errorMessage {
                    ContentUnavailableView(
                        SpatialCopy.value("spatial.pdf.errorTitle", defaultValue: "Falha na Geração do Relatório"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if let pdfURL {
                    PDFKitRepresentedView(url: pdfURL)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle(SpatialCopy.value("spatial.pdf.title", defaultValue: "Relatório Técnico Vetorial"))
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(SpatialCopy.value("spatial.common.close", defaultValue: "Fechar")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if let pdfURL {
                        ShareLink(
                            item: pdfURL,
                            preview: SharePreview("Relatório Técnico WiFi Casa - \(house.name).pdf", image: Image(systemName: "doc.text.fill"))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task {
                generateReport()
            }
        }
    }

    private func generateReport() {
        let currentHouse = house
        let currentSSID = ssid
        let currentGatewayIP = gatewayIP

        Task.detached(priority: .userInitiated) {
            do {
                let accessPoints = currentHouse.rooms.compactMap(\.accessPoint)
                let measuredRooms = currentHouse.rooms.filter { $0.lastMeasurement != nil }
                let coverage = currentHouse.totalCoveragePercent

                let summary = "Relatório técnico residencial com \(measuredRooms.count) cômodo(s) avaliado(s) de um total de \(currentHouse.rooms.count). Qualidade média nos pontos medidos: \(coverage)%. A análise comparou a latência e estabilidade da rede local sem fio (roteador/LAN) com destinos de referência na internet (WAN)."

                let ispNotice = "A análise compara a resposta do segmento sem fio local com destinos de referência na internet. Degradações observadas na conexão externa com resposta normal no roteador sugerem provável instabilidade na rota externa ou no provedor, mas dependem de validação direta com o suporte da operadora."

                let auditData = TechnicalAuditReportData(
                    houseName: currentHouse.name,
                    generatedDate: Date(),
                    ssid: currentSSID,
                    gatewayIP: currentGatewayIP,
                    accessPoints: accessPoints,
                    rooms: currentHouse.rooms,
                    totalCoveragePercent: coverage,
                    executiveSummary: summary,
                    ispTechnicalNotice: ispNotice
                )

                let url = try PDFReportGenerator.generateAuditReportPDF(data: auditData)
                await MainActor.run {
                    self.pdfURL = url
                    self.isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isGenerating = false
                }
            }
        }
    }
}

#Preview {
    if #available(iOS 17.0, macOS 14.0, *) {
        ReportPreviewSheet(
            house: House(
                name: "Apartamento 82",
                rooms: [
                    Room(name: "Sala de Estar", icon: "sofa", hasRouter: true),
                    Room(name: "Quarto", icon: "bed.double", hasRouter: false)
                ]
            )
        )
        .preferredColorScheme(.dark)
    }
}
