import Foundation
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
public protocol DeviceSpecEnrichmentService: Sendable { func enrich(identity: DeviceIdentity) async throws -> DeviceSpecificationSnapshot }
public struct HTTPDeviceSpecEnrichmentService: DeviceSpecEnrichmentService {
    public let endpoint: URL
    private let session: URLSession
    public init(endpoint: URL, session: URLSession = .shared) { self.endpoint = endpoint; self.session = session }
    public func enrich(identity: DeviceIdentity) async throws -> DeviceSpecificationSnapshot {
        try Task.checkCancellation()
        let identity = identity.normalizedForResearch
        guard identity.isResearchable, endpoint.scheme == "https" else { throw NetworkInventoryError.invalidDevice }
        try Task.checkCancellation()
        struct Request: Encodable { var schemaVersion = 1; var identity: DeviceIdentity }
        var request = URLRequest(url: endpoint); request.httpMethod = "POST"; request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(identity: identity))
        let (bytes, response) = try await session.bytes(for: request, delegate: RejectLookupRedirects())
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == endpoint, response.expectedContentLength <= 256_000 else { bytes.task.cancel(); throw NetworkInventoryError.unavailable }
        var data = Data()
        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 256_000 else { throw NetworkInventoryError.invalidResponse }
                data.append(byte)
            }
        } catch { bytes.task.cancel(); throw error }
        try Task.checkCancellation()
        try Self.validateWireKeys(data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else { throw NetworkInventoryError.invalidResponse }; return date
        }
        let result: DeviceSpecificationSnapshot
        do { result = try decoder.decode(DeviceSpecificationSnapshot.self, from: data) } catch { throw NetworkInventoryError.invalidResponse }
        try result.validate(for: identity); try Task.checkCancellation(); return result
    }
    private static func validateWireKeys(_ data: Data) throws {
        func keys(_ object: [String: Any], _ allowed: Set<String>) -> Bool { Set(object.keys).isSubset(of: allowed) }
        func identity(_ object: Any?) -> Bool { guard let object = object as? [String: Any] else { return false }; return keys(object, ["brand", "model", "hardwareRevision", "marketRegion"]) }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], keys(root, ["schemaVersion", "identity", "status", "attributes", "sources", "checkedAt"]), identity(root["identity"]), let attributes = root["attributes"] as? [[String: Any]], let sources = root["sources"] as? [[String: Any]], attributes.allSatisfy({ keys($0, ["key", "value", "unit", "evidenceIDs"]) }), sources.allSatisfy({ keys($0, ["id", "url", "title", "retrievedAt", "matchedIdentity"]) && identity($0["matchedIdentity"]) }) else { throw NetworkInventoryError.invalidResponse }
    }

}
private final class RejectLookupRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
public extension DeviceSpecificationSnapshot {
    func validate(for expected: DeviceIdentity) throws {
        let allowed: Set<String> = ["wifiStandards", "bandsGHz", "lanPorts", "wanPorts", "wanMedia", "ethernetPortSpeedsMbps", "supportsMesh", "meshTechnology", "supportedModes", "firmwareSupportStatus", "radioCapabilities", "ethernetPorts", "supportedBackhaul", "fiberTermination"]
        guard schemaVersion == 1, identity.isValid, identity.matches(expected), attributes.count <= allowed.count, sources.count <= 30,
              Set(attributes.map(\.key)).count == attributes.count, Set(sources.map(\.id)).count == sources.count else { throw NetworkInventoryError.invalidResponse }
        if status == .notFound || status == .unavailable { guard attributes.isEmpty, sources.isEmpty else { throw NetworkInventoryError.invalidResponse } }
        if status == .complete { guard !attributes.isEmpty else { throw NetworkInventoryError.invalidResponse } }
        for source in sources {
            guard !source.id.isEmpty, source.id.count <= 100, source.url.scheme == "https", let host = source.url.host, host.contains("."), !host.hasSuffix(".local"), !host.hasSuffix(".localhost"), host != "localhost", !host.contains(":"), !host.split(separator: ".").allSatisfy({ Int($0) != nil }), source.url.user == nil, source.url.password == nil, !source.title.isEmpty, source.title.count <= 500, source.matchedIdentity.matches(expected) else { throw NetworkInventoryError.invalidResponse }
        }
        let ids = Set(sources.map(\.id))
        for attribute in attributes {
            guard allowed.contains(attribute.key), Self.validValue(attribute), !attribute.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, attribute.value.count <= 4000, (attribute.unit?.count ?? 0) <= 30, !attribute.evidenceIDs.isEmpty, Set(attribute.evidenceIDs).count == attribute.evidenceIDs.count, attribute.evidenceIDs.allSatisfy({ ids.contains($0) }) else { throw NetworkInventoryError.invalidResponse }
        }
    }
}
public struct DeviceLabelCandidate: Equatable, Sendable {
    public var identity: DeviceIdentity
    public init(identity: DeviceIdentity) { self.identity = identity }
}
public protocol DeviceLabelOCRService: Sendable { func candidates(from imageData: Data) async throws -> [DeviceLabelCandidate] }
/// Only explicitly labelled model/revision fields are considered. Never returns a raw label or passwords.
public enum DeviceLabelParser {
    public static func candidates(from recognizedLines: [String]) -> [DeviceLabelCandidate] {
        var models: [String] = []; var revision: String?; var brand = ""
        let brands = ["TP-Link", "D-Link", "Huawei", "Nokia", "Intelbras", "ASUS", "Netgear", "ZTE", "Tenda", "Ubiquiti"]
        for line in recognizedLines.prefix(100) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            // Reject the entire line, including merged OCR fields. Never truncate around a secret.
            let sensitive = #"(?i)\b(password|passwd|passphrase|senha|ssid|bssid|serial|s\s*/\s*n|mac|wps|pin|key|psk|chave)\b"#
            if lower.range(of: sensitive, options: .regularExpression) != nil { continue }
            if let match = brands.first(where: { lower == $0.lowercased() || lower.hasPrefix($0.lowercased() + " ") }) { brand = match }
            for prefix in ["model:", "modelo:", "model no:", "model no.:"] where lower.hasPrefix(prefix) {
                let value = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty && value.count <= 120 { if !models.contains(value) { models.append(value) } }
            }
            for prefix in ["ver:", "version:", "h/w ver:", "hardware version:"] where lower.hasPrefix(prefix) {
                let value = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty && value.count <= 120 { revision = value }
            }
        }
        return models.map { DeviceIdentity(brand: brand, model: $0, hardwareRevision: models.count == 1 ? revision : nil) }.filter(\.isValid).map { .init(identity: $0) }
    }
}

private extension DeviceSpecificationSnapshot {
    static func validValue(_ attribute: SpecificationAttribute) -> Bool {
        let parts = attribute.value.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        func members(_ allowed: Set<String>) -> Bool { !parts.isEmpty && Set(parts).count == parts.count && parts.allSatisfy { allowed.contains($0) } }
        switch attribute.key {
        case "lanPorts", "wanPorts": return attribute.unit == nil && Int(attribute.value).map { (0...128).contains($0) } == true
        case "supportsMesh": return attribute.unit == nil && ["true", "false"].contains(attribute.value)
        case "bandsGHz": return attribute.unit == "GHz" && members(["2.4", "5", "6"])
        case "ethernetPortSpeedsMbps": return attribute.unit == "Mbps" && !parts.isEmpty && parts.allSatisfy { Double($0).map { $0.isFinite && $0 > 0 && $0 <= 1_000_000 } == true }
        case "wifiStandards": return attribute.unit == nil && members(["802.11a", "802.11b", "802.11g", "802.11n", "802.11ac", "802.11ax", "802.11be"])
        case "wanMedia": return attribute.unit == nil && ["ethernet", "fiber", "mixed", "unknown"].contains(attribute.value)
        case "supportedModes": return attribute.unit == nil && members(["router", "accessPoint", "repeater", "meshSatellite", "bridge", "fiberTermination"])
        case "supportedBackhaul": return attribute.unit == nil && members(["ethernet", "wifi"])
        case "fiberTermination": return attribute.unit == nil && ["none", "gpon", "xgsPon", "sfp", "unknown"].contains(attribute.value)
        case "radioCapabilities", "ethernetPorts": return attribute.unit == nil && validStructured(attribute)
        case "meshTechnology": return attribute.unit == nil && ["unknown", "easyMesh", "oneMesh", "aiMesh", "orbi", "deco", "eero", "velop", "other"].contains(attribute.value)
        case "firmwareSupportStatus": return attribute.unit == nil && ["supported", "unsupported", "unknown"].contains(attribute.value)
        default: return false
        }
    }
}

private extension DeviceSpecificationSnapshot {
    static func validStructured(_ attribute: SpecificationAttribute) -> Bool {
        guard let data = attribute.value.data(using: .utf8), let objects = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]], !objects.isEmpty else { return false }
        func number(_ object: [String: Any], _ key: String) -> Double? {
            guard let value = object[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }; return value.doubleValue
        }
        if attribute.key == "radioCapabilities" {
            guard objects.count <= 3 else { return false }
            var bands: Set<Double> = []
            for object in objects {
                guard Set(object.keys).isSubset(of: ["bandGHz", "maxChannelWidthMHz", "maxPhyRateMbps", "spatialStreams"]), let band = number(object, "bandGHz"), [2.4, 5, 6].contains(band), bands.insert(band).inserted else { return false }
                var known = false
                for key in ["maxChannelWidthMHz", "maxPhyRateMbps", "spatialStreams"] {
                    guard let raw = object[key], !(raw is NSNull) else { continue }
                    guard let value = number(object, key), value.isFinite else { return false }
                    if key == "maxChannelWidthMHz", ![20, 40, 80, 160, 320].contains(value) { return false }
                    if key == "maxPhyRateMbps", !(value > 0 && value <= 1_000_000) { return false }
                    if key == "spatialStreams", !(value >= 1 && value <= 32 && value.rounded() == value) { return false }
                    known = true
                }
                if !known { return false }
            }
            return true
        }
        guard objects.count <= 32 else { return false }
        return objects.allSatisfy { object in
            guard Set(object.keys) == ["role", "portCount", "speedMbps"], let role = object["role"] as? String, ["lan", "wan", "lanWan"].contains(role), let count = number(object, "portCount"), let speed = number(object, "speedMbps") else { return false }
            return count >= 1 && count <= 128 && count.rounded() == count && speed.isFinite && speed > 0 && speed <= 1_000_000
        }
    }
}
