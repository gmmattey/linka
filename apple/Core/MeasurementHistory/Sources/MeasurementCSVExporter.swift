import Foundation
import NetworkCore

public enum MeasurementCSVExporter {
    /// Gera o conteúdo CSV padrão RFC 4180 com cabeçalho e codificação compatível (com BOM UTF-8).
    public static func generateCSV(from measurements: [NetworkMeasurement], locale: Locale = Locale(identifier: "pt_BR")) -> String {
        let displayDateFormatter = DateFormatter()
        displayDateFormatter.locale = locale
        displayDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var rows: [String] = []
        // Cabeçalho canônico
        rows.append("ID,Data/Hora,Tipo de Conexao,Download (Mbps),Upload (Mbps),Ping (ms),Jitter (ms),Perda de Pacotes (%),DNS (ms),Banda Wi-Fi,Servidor,Plataforma")

        for m in measurements {
            let id = m.id.uuidString
            let date = displayDateFormatter.string(from: m.measuredAt)
            let conn: String = {
                switch m.connectionKind {
                case .wifi: return "Wi-Fi"
                case .cellular: return "Celular"
                case .ethernet: return "Ethernet"
                default: return "Outro"
                }
            }()
            let down = m.downloadMbps.map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
            let up = m.uploadMbps.map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
            let ping = m.latencyMs.map { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
            let jitter = m.jitterMs.map { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
            let loss = m.packetLossPercent.map { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
            let dns = m.dnsResolutionMs.map { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
            let band = m.wifiBandGHz.map { "\($0) GHz" } ?? ""
            let server = escapeCSV(m.networkIdentifier ?? "")
            let platform = escapeCSV(m.devicePlatform ?? "")

            let line = [id, date, conn, down, up, ping, jitter, loss, dns, band, server, platform].joined(separator: ",")
            rows.append(line)
        }

        // Prefixo UTF-8 BOM para garantir exibição correta de caracteres especiais no Microsoft Excel
        return "\u{FEFF}" + rows.joined(separator: "\r\n")
    }

    /// Retorna os dados em bytes UTF-8 prontos para exportação/gravação em arquivo.
    public static func generateCSVData(from measurements: [NetworkMeasurement], locale: Locale = Locale(identifier: "pt_BR")) -> Data {
        generateCSV(from: measurements, locale: locale).data(using: .utf8) ?? Data()
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}
