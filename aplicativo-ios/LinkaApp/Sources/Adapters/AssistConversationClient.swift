import Foundation
import NetworkCore

struct AssistConversationMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    let id: UUID
    let role: Role
    let content: String
}

enum AssistConversationError: Error, Equatable { case unavailable, invalidResponse, sensitiveInput }

protocol AssistConversationServing: Sendable {
    func stream(message: String, history: [AssistConversationMessage], measurement: NetworkMeasurement?, locale: String, onDelta: @escaping @MainActor @Sendable (String) -> Void) async throws
}

struct AssistConversationClient: AssistConversationServing {
    private let session: URLSession
    private let endpoint: URL?
    private let enabled: Bool

    init(session: URLSession = .shared, bundle: Bundle = .main) {
        self.session = session
        self.endpoint = bundle.object(forInfoDictionaryKey: "LinkaAssistDirectEndpoint").flatMap { $0 as? String }.flatMap(URL.init(string:))
        self.enabled = (bundle.object(forInfoDictionaryKey: "LinkaAssistDirectEnabled") as? String) == "YES"
    }

    init(session: URLSession = .shared, endpoint: URL?, enabled: Bool) {
        self.session = session
        self.endpoint = endpoint
        self.enabled = enabled
    }

    func stream(message: String, history: [AssistConversationMessage], measurement: NetworkMeasurement?, locale: String, onDelta: @escaping @MainActor @Sendable (String) -> Void) async throws {
        guard enabled, let endpoint else { throw AssistConversationError.unavailable }
        guard !Self.containsSensitiveNetworkData(message), !history.contains(where: { Self.containsSensitiveNetworkData($0.content) }) else { throw AssistConversationError.sensitiveInput }
        let body = Request(
            schemaVersion: "1.0.0", message: message, locale: locale, context: Context(measurement: measurement),
            previousMessages: history.suffix(4).map { .init(role: $0.role.rawValue, content: $0.content) }
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 25
        request.httpBody = try JSONEncoder().encode(body)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AssistConversationError.unavailable }
        guard response.mimeType == "text/event-stream" else { throw AssistConversationError.invalidResponse }
        var charactersReceived = 0
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if data == "[DONE]" { break }
            guard let delta = Self.delta(fromSSEData: data) else { continue }
            charactersReceived += delta.count
            guard charactersReceived <= 2_000 else { throw AssistConversationError.invalidResponse }
            await onDelta(delta)
        }
        guard charactersReceived > 0 else { throw AssistConversationError.invalidResponse }
    }

    private struct Request: Encodable {
        let schemaVersion: String; let message: String; let locale: String; let context: Context?; let previousMessages: [Message]
        enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version"; case message, locale, context; case previousMessages = "previous_messages" }
    }
    private struct Context: Encodable {
        let connectionKind: String?; let downloadMbps: Double?; let uploadMbps: Double?; let latencyMs: Double?; let jitterMs: Double?; let packetLossPercent: Double?; let loadedLatencyDownloadMs: Double?; let loadedLatencyUploadMs: Double?
        init?(measurement: NetworkMeasurement?) {
            guard let measurement else { return nil }
            connectionKind = measurement.connectionKind?.rawValue; downloadMbps = measurement.downloadMbps; uploadMbps = measurement.uploadMbps
            latencyMs = measurement.latencyMs; jitterMs = measurement.jitterMs; packetLossPercent = measurement.packetLossPercent
            loadedLatencyDownloadMs = measurement.loadedLatencyMs; loadedLatencyUploadMs = measurement.loadedLatencyUploadMs
        }
        enum CodingKeys: String, CodingKey { case connectionKind = "connection_kind"; case downloadMbps = "download_mbps"; case uploadMbps = "upload_mbps"; case latencyMs = "latency_ms"; case jitterMs = "jitter_ms"; case packetLossPercent = "packet_loss_percent"; case loadedLatencyDownloadMs = "loaded_latency_download_ms"; case loadedLatencyUploadMs = "loaded_latency_upload_ms" }
    }
    private struct Message: Encodable { let role: String; let content: String }

    private static func delta(fromSSEData data: String) -> String? {
        guard data != "[DONE]", let bytes = data.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return nil }
        if let response = object["response"] as? String { return response }
        if let delta = object["delta"] as? String { return delta }
        if let choices = object["choices"] as? [[String: Any]], let delta = choices.first?["delta"] as? [String: Any], let content = delta["content"] as? String { return content }
        return nil
    }

    static func containsSensitiveNetworkData(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        if ["ssid", "bssid", "senha", "password", "passphrase", "gateway", "endereço ip", "ip address", "mac address"].contains(where: lowercased.contains) { return true }
        let patterns = ["\\b(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})(?:\\.(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})){3}\\b", "\\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\\b"]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }
}

@MainActor
final class AssistConversationViewModel: ObservableObject {
    @Published var draft = ""
    @Published private(set) var messages: [AssistConversationMessage] = []
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?
    private let service: any AssistConversationServing
    private let locale: String
    private var sendTask: Task<Void, Never>?

    init(service: any AssistConversationServing = AssistConversationClient(), locale: String = LinkaLanguagePreference.currentLanguageTag) {
        self.service = service; self.locale = locale
    }

    func send(measurement: NetworkMeasurement?) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        guard !AssistConversationClient.containsSensitiveNetworkData(text) else {
            errorMessage = LinkaCopy.value("assist.direct.sensitiveInput")
            return
        }
        let history = messages
        draft = ""; errorMessage = nil
        messages.append(.init(id: UUID(), role: .user, content: text)); isSending = true
        let assistantID = UUID()
        sendTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isSending = false
                sendTask = nil
            }
            do {
                try await service.stream(message: text, history: history, measurement: measurement, locale: locale) { [weak self] delta in
                    guard let self else { return }
                    if let index = self.messages.firstIndex(where: { $0.id == assistantID }) {
                        let current = self.messages[index]
                        self.messages[index] = .init(id: current.id, role: .assistant, content: current.content + delta)
                    } else {
                        self.messages.append(.init(id: assistantID, role: .assistant, content: delta))
                    }
                }
            } catch AssistConversationError.sensitiveInput {
                errorMessage = LinkaCopy.value("assist.direct.sensitiveInput")
            } catch { errorMessage = LinkaCopy.value("assist.direct.unavailable") }
        }
    }

    func cancel() {
        sendTask?.cancel()
        sendTask = nil
        isSending = false
    }
}
