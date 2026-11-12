import Foundation

/// Marcos seguros e pequenos que a interface poderá exibir durante a leitura.
/// Eles descrevem somente progresso técnico; não expõem prompt, resposta,
/// raciocínio do modelo, provider, modelo ou payload.
public enum NetscopeProgressMilestone: String, CaseIterable, Equatable, Sendable {
    case accepted
    case analysisStarted = "analysis_started"
    case validatingResult = "validating_result"
}

public struct NetscopeProgressEvent: Equatable, Sendable {
    public let milestone: NetscopeProgressMilestone

    public init(milestone: NetscopeProgressMilestone) {
        self.milestone = milestone
    }
}

public enum NetscopeProgressDecodingError: Error, Equatable, Sendable {
    case malformedEvent
    case unsupportedMilestone
}

/// Decodifica um frame JSON mínimo de SSE (`{"milestone":"accepted"}`).
/// Objetos com campos extras, conteúdo textual ou milestone desconhecido são
/// rejeitados: o consumidor deve exibir `unavailable`, não texto do provider.
public enum NetscopeProgressDecoder {
    public static func decode(_ data: Data) throws -> NetscopeProgressEvent {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["milestone"],
              let rawValue = object["milestone"] as? String else {
            throw NetscopeProgressDecodingError.malformedEvent
        }
        guard let milestone = NetscopeProgressMilestone(rawValue: rawValue) else {
            throw NetscopeProgressDecodingError.unsupportedMilestone
        }
        return NetscopeProgressEvent(milestone: milestone)
    }
}
