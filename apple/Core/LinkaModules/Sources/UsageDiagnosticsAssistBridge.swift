import NetworkInsights

/// Ponte entre o classificador puro de adequação por uso (`NetworkInsights`)
/// e o Assist (`NetworkAssist`) — issue Expert Mode/diagnóstico de uso.
///
/// `NetworkInsights` não conhece Assist nem copy de produto (AGENTS.md
/// §8/§9); esta ponte vive na camada de agregação (`LinkaModules`), mesmo
/// lugar dos gates de entitlement em `Entitlements.swift`. Produz texto
/// estritamente factual, fundamentado nos veredictos já calculados — nunca
/// cita marca, jogo, app ou serviço específico, mesma restrição de
/// `UsageSuitabilityCopy` na UI (`LinkaApp/Sources/UI/DetailsDisclosure.swift`).
public enum UsageDiagnosticsAssistBridge {
    private static let caseLabelsByLocale: [String: [UsageCase: String]] = [
        "pt": [
            .videoCall: "Chamada em vídeo",
            .streamingHD: "Streaming em HD",
            .streaming4K: "Streaming em 4K",
            .onlineGaming: "Jogo online",
            .workUpload: "Envio de arquivos e trabalho"
        ],
        "en": [
            .videoCall: "Video call",
            .streamingHD: "HD streaming",
            .streaming4K: "4K streaming",
            .onlineGaming: "Online gaming",
            .workUpload: "File upload and work"
        ],
        "es": [
            .videoCall: "Videollamada",
            .streamingHD: "Streaming en HD",
            .streaming4K: "Streaming en 4K",
            .onlineGaming: "Juego en línea",
            .workUpload: "Envío de archivos y trabajo"
        ]
    ]

    private static let levelLabelsByLocale: [String: [SuitabilityLevel: String]] = [
        "pt": [
            .adequate: "adequada",
            .limited: "limitada",
            .notAssessed: "não avaliada (faltam métricas)"
        ],
        "en": [
            .adequate: "adequate",
            .limited: "limited",
            .notAssessed: "not assessed (missing metrics)"
        ],
        "es": [
            .adequate: "adecuada",
            .limited: "limitada",
            .notAssessed: "no evaluada (faltan métricas)"
        ]
    ]

    /// Resumo compacto e factual de um `UsageSuitabilityReport`, adequado
    /// para `NetworkAssistContext.usageContext` — o Assist usa isto como
    /// evidência grounded, nunca como opinião a repetir literalmente.
    /// `locale` é a tag BCP-47 da preferência de idioma do app.
    public static func assistSummary(for report: UsageSuitabilityReport, locale: String? = nil) -> String {
        let key: String
        switch (locale ?? "pt-BR").lowercased() {
        case let tag where tag.hasPrefix("es"): key = "es"
        case let tag where tag.hasPrefix("en"): key = "en"
        default: key = "pt"
        }
        let caseLabels = caseLabelsByLocale[key] ?? [:]
        let levelLabels = levelLabelsByLocale[key] ?? [:]

        return report.verdicts
            .map { verdict in
                let label = caseLabels[verdict.usageCase] ?? verdict.usageCase.rawValue
                let level = levelLabels[verdict.level] ?? verdict.level.rawValue
                return "\(label): \(level)."
            }
            .joined(separator: " ")
    }
}
