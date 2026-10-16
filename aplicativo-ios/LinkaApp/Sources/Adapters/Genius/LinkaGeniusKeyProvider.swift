import Foundation

/// Protocolo para resolução da API key do Gemini.
public protocol LinkaGeniusKeyProviding: Sendable {
    func resolveKey() -> String?
}

/// Provedor padrão de chave com cascata estrita:
/// 1. Variável de ambiente `GEMINI_API_KEY`
/// 2. Arquivo `.env.local` no diretório raiz do projeto ou bundle
/// 3. Arquivo `~/Documents/Gemini API KEY.md`
public struct DefaultLinkaGeniusKeyProvider: LinkaGeniusKeyProviding {
    private let environmentLookup: @Sendable (String) -> String?
    private let fileReader: @Sendable (String) -> String?
    private let projectRootCandidates: [String]
    private let userDocumentsKeyPath: String

    public init(
        environmentLookup: @escaping @Sendable (String) -> String? = { ProcessInfo.processInfo.environment[$0] },
        fileReader: @escaping @Sendable (String) -> String? = { path in
            let expanded = (path as NSString).expandingTildeInPath
            return try? String(contentsOfFile: expanded, encoding: .utf8)
        },
        projectRootCandidates: [String] = [
            FileManager.default.currentDirectoryPath,
            "/Users/giammattey/Projetos/linka"
        ],
        userDocumentsKeyPath: String = "~/Documents/Gemini API KEY.md"
    ) {
        self.environmentLookup = environmentLookup
        self.fileReader = fileReader
        self.projectRootCandidates = projectRootCandidates
        self.userDocumentsKeyPath = userDocumentsKeyPath
    }

    public func resolveKey() -> String? {
        // 1. Variável de ambiente
        if let envKey = environmentLookup("GEMINI_API_KEY")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envKey.isEmpty {
            return envKey
        }

        // 2. Arquivo .env.local
        for root in projectRootCandidates {
            let envPath = (root as NSString).appendingPathComponent(".env.local")
            if let content = fileReader(envPath), let parsed = Self.parseEnvKey(from: content, key: "GEMINI_API_KEY") {
                return parsed
            }
        }

        // 3. Arquivo em ~/Documents/Gemini API KEY.md
        if let docContent = fileReader(userDocumentsKeyPath),
           let parsed = Self.parseMarkdownKey(from: docContent) {
            return parsed
        }

        return nil
    }

    /// Extrai chave no formato KEY=VALOR de um arquivo .env
    public static func parseEnvKey(from content: String, key: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2 {
                let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                if name == key {
                    var val = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                        val = String(val.dropFirst().dropLast())
                    }
                    if !val.isEmpty {
                        return val
                    }
                }
            }
        }
        return nil
    }

    /// Extrai chave do arquivo markdown (linha que começa com AQ. ou após o título)
    public static func parseMarkdownKey(from content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.lowercased().hasPrefix("gemini api key") {
                continue
            }
            if trimmed.count >= 20 {
                return trimmed
            }
        }
        return nil
    }
}
