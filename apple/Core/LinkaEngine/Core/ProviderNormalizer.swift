import Foundation

public struct ProviderInfo: Equatable, Sendable {
    public let commercialName: String
    public let country: String?

    public init(commercialName: String, country: String? = nil) {
        self.commercialName = commercialName
        self.country = country
    }
}

/// Normalizes ISP/mobile carrier org strings returned by IP-info services
/// (e.g. "AS27699 TELEFÔNICA BRASIL S.A") to their commercial brand
/// ("Vivo"). Zero network I/O — all data is bundled.
public struct ProviderNormalizer: Sendable {

    private struct Dataset: Decodable {
        struct ASNEntry: Decodable {
            let name: String
            let country: String?
        }
        struct SubstringEntry: Decodable {
            let match: String
            let name: String
            let country: String?
        }
        let asnMappings: [String: ASNEntry]
        let substringPatterns: [SubstringEntry]
        let legalSuffixes: [String]
    }

    private let dataset: Dataset?

    public static let shared = ProviderNormalizer()

    public init() {
        self.dataset = Self.loadDataset(from: .module)
    }

    /// For tests that want to inject a custom bundle.
    internal init(bundle: Bundle) {
        self.dataset = Self.loadDataset(from: bundle)
    }

    private static func loadDataset(from bundle: Bundle) -> Dataset? {
        guard let url = bundle.url(forResource: "providers", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(Dataset.self, from: data)
    }

    /// Normalize a raw `org` string as returned by ipinfo.io.
    /// Accepts the full string including the "AS<n>" prefix.
    public func normalize(org: String) -> ProviderInfo? {
        let trimmed = org.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let (asn, remainder) = splitASN(trimmed)
        let dataset = self.dataset

        if let asn, let dataset, let entry = dataset.asnMappings[String(asn)] {
            return ProviderInfo(commercialName: entry.name, country: entry.country)
        }

        let candidate = remainder.isEmpty ? trimmed : remainder
        let normalized = candidate
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()

        if let dataset {
            for pattern in dataset.substringPatterns {
                if normalized.contains(pattern.match.uppercased()) {
                    return ProviderInfo(commercialName: pattern.name, country: pattern.country)
                }
            }
        }

        let cleaned = heuristicClean(candidate, suffixes: dataset?.legalSuffixes ?? [])
        return ProviderInfo(commercialName: cleaned, country: nil)
    }

    /// Convenience: returns just the display name, falling back to `raw` (minus AS prefix) if lookup fails.
    public func displayName(for org: String) -> String? {
        normalize(org: org)?.commercialName
    }

    // MARK: - Internals

    /// Splits "AS27699 Telefônica…" into (27699, "Telefônica…").
    /// If no ASN prefix, returns (nil, original).
    internal func splitASN(_ raw: String) -> (asn: Int?, remainder: String) {
        let scanner = Scanner(string: raw)
        scanner.charactersToBeSkipped = .whitespaces

        guard scanner.scanString("AS") != nil else {
            return (nil, raw)
        }
        var value: Int = 0
        guard scanner.scanInt(&value) else {
            return (nil, raw)
        }
        let remainder = String(raw[scanner.currentIndex...])
            .trimmingCharacters(in: .whitespaces)
        return (value, remainder)
    }

    /// Removes legal suffixes (case- and diacritic-insensitive) and normalizes whitespace/casing.
    internal func heuristicClean(_ raw: String, suffixes: [String]) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripChars = CharacterSet(charactersIn: ",;.").union(.whitespacesAndNewlines)

        // Iteratively strip legal suffixes; some names carry two ("Foo Telecom LTDA").
        var changed = true
        while changed {
            changed = false
            let folded = s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
                          .uppercased()
            for suffix in suffixes {
                let needle = suffix.uppercased()
                if folded.hasSuffix(needle), s.count > suffix.count {
                    s = String(s.dropLast(suffix.count))
                        .trimmingCharacters(in: stripChars)
                    changed = true
                    break
                }
            }
        }

        let collapsed = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return titleCased(collapsed)
    }

    private func titleCased(_ input: String) -> String {
        let smallWords: Set<String> = ["de", "do", "da", "dos", "das", "e", "of", "and", "the", "y"]
        let words = input.split(separator: " ")
        return words.enumerated().map { idx, word in
            let lower = word.lowercased()
            if idx > 0, smallWords.contains(lower) {
                return lower
            }
            // Preserve acronyms already uppercased (TIM, AT&T, BT, MEO, NOS)
            if word.count <= 4, word.allSatisfy({ $0.isUppercase || !$0.isLetter }) {
                return String(word)
            }
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }.joined(separator: " ")
    }
}
