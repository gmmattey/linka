#if os(iOS)
import Foundation
import AssistConsultation

/// Histórico local, opt-in por ação explícita de salvar. Não participa do
/// transporte nem é usado pelo relay; o conteúdo nunca é escrito em logs.
@MainActor
final class AssistV4ConsultationHistory {
    struct Entry: Codable, Identifiable {
        let id: UUID
        let question: String
        let response: ConsultationTurnResponse
        let savedAt: Date
    }

    static let shared = AssistV4ConsultationHistory()

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent("Linka/AssistV4", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("consultation-history.json")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(question: String, response: ConsultationTurnResponse) throws {
        var entries = try load()
        entries.insert(.init(id: UUID(), question: question, response: response, savedAt: Date()), at: 0)
        // Histórico não é um arquivo de telemetria. Mantemos um limite local
        // pequeno para não transformar uma ação de salvar em retenção infinita.
        let data = try encoder.encode(Array(entries.prefix(50)))
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func load() throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([Entry].self, from: Data(contentsOf: fileURL))
    }
}
#endif
