import Foundation

/// Configuração do serviço Gemini no Google AI.
public struct LinkaGeniusConfiguration: Equatable, Sendable {
    public static let defaultModel = "gemini-3.8-flash"
    public static let defaultTimeout: TimeInterval = 30.0

    public let model: String
    public let timeout: TimeInterval

    public init(
        model: String = Self.defaultModel,
        timeout: TimeInterval = Self.defaultTimeout
    ) {
        self.model = model
        self.timeout = timeout
    }

    public func endpointURL(apiKey: String) -> URL? {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey)
        ]
        return components?.url
    }
}

// MARK: - DTOs da API Gemini Google AI

public struct GeminiGenerateContentRequest: Codable, Sendable {
    public let contents: [GeminiContent]
    public let systemInstruction: GeminiContent?
    public let generationConfig: GeminiGenerationConfig?

    enum CodingKeys: String, CodingKey {
        case contents
        case systemInstruction
        case generationConfig
    }

    public init(
        contents: [GeminiContent],
        systemInstruction: GeminiContent? = nil,
        generationConfig: GeminiGenerationConfig? = nil
    ) {
        self.contents = contents
        self.systemInstruction = systemInstruction
        self.generationConfig = generationConfig
    }
}

public struct GeminiContent: Codable, Sendable {
    public let role: String?
    public let parts: [GeminiPart]

    public init(role: String? = nil, parts: [GeminiPart]) {
        self.role = role
        self.parts = parts
    }

    public init(text: String, role: String? = nil) {
        self.role = role
        self.parts = [GeminiPart(text: text)]
    }
}

public struct GeminiPart: Codable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct GeminiGenerationConfig: Codable, Sendable {
    public let responseMimeType: String?
    public let responseSchema: GeminiResponseSchema?
    public let temperature: Double?

    enum CodingKeys: String, CodingKey {
        case responseMimeType = "response_mime_type"
        case responseSchema = "response_schema"
        case temperature
    }

    public init(
        responseMimeType: String? = nil,
        responseSchema: GeminiResponseSchema? = nil,
        temperature: Double? = nil
    ) {
        self.responseMimeType = responseMimeType
        self.responseSchema = responseSchema
        self.temperature = temperature
    }
}

public struct GeminiResponseSchema: Codable, Sendable {
    public let type: String
    public let properties: [String: GeminiSchemaProperty]?
    public let required: [String]?
    public let items: GeminiSchemaItems?

    public init(
        type: String,
        properties: [String: GeminiSchemaProperty]? = nil,
        required: [String]? = nil,
        items: GeminiSchemaItems? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
        self.items = items
    }
}

public struct GeminiSchemaProperty: Codable, Sendable {
    public let type: String
    public let description: String?
    public let items: GeminiSchemaItems?

    public init(type: String, description: String? = nil, items: GeminiSchemaItems? = nil) {
        self.type = type
        self.description = description
        self.items = items
    }
}

public struct GeminiSchemaItems: Codable, Sendable {
    public let type: String

    public init(type: String) {
        self.type = type
    }
}

// MARK: - Gemini Response DTOs

public struct GeminiGenerateContentResponse: Codable, Sendable {
    public struct Candidate: Codable, Sendable {
        public struct Content: Codable, Sendable {
            public let parts: [GeminiPart]?
        }
        public let content: Content?
        public let finishReason: String?
    }
    public struct PromptFeedback: Codable, Sendable {
        public let blockReason: String?
    }
    public struct ErrorPayload: Codable, Sendable {
        public let code: Int?
        let message: String?
        let status: String?
    }

    public let candidates: [Candidate]?
    public let promptFeedback: PromptFeedback?
    public let error: ErrorPayload?

    public var firstOutputText: String? {
        candidates?.first?.content?.parts?.first?.text
    }
}
