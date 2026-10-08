import Foundation

public enum DeviceKind: String, Codable, CaseIterable, Sendable { case modem, router, modemRouter, ont, meshNode, extender, other }
public enum InstalledRole: String, Codable, CaseIterable, Sendable { case mainRouter, accessPoint, repeater, meshSatellite, fiberTermination, bridge, other, unknown }
public enum OwnershipSource: String, Codable, CaseIterable, Sendable { case userOwned, ispProvided, thirdParty, unknown }
public enum DeclaredAnswer: String, Codable, CaseIterable, Sendable { case yes, no, unknown }
public struct DeviceIdentity: Codable, Equatable, Sendable {
    public var brand: String
    public var model: String
    public var hardwareRevision: String?
    public var marketRegion: String?
    public init(brand: String = "", model: String, hardwareRevision: String? = nil, marketRegion: String? = nil) {
        self.brand = brand; self.model = model; self.hardwareRevision = hardwareRevision; self.marketRegion = marketRegion
    }
    public var isValid: Bool {
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && [brand, model, hardwareRevision ?? "", marketRegion ?? ""].allSatisfy { $0.count <= 120 && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }
    }
    public var normalizedForResearch: Self {
        func clean(_ value: String?) -> String? { let v = value?.trimmingCharacters(in: .whitespacesAndNewlines); return v?.isEmpty == false ? v : nil }
        return .init(brand: clean(brand) ?? "", model: clean(model) ?? "", hardwareRevision: clean(hardwareRevision), marketRegion: clean(marketRegion)?.uppercased())
    }
    public var isResearchable: Bool {
        let value = normalizedForResearch
        return value.isValid && !value.brand.isEmpty && value.brand.count <= 80 && (value.hardwareRevision?.count ?? 0) <= 40 && (value.marketRegion == nil || value.marketRegion!.range(of: #"^[A-Z]{2}$"#, options: .regularExpression) != nil)
    }
    public func matches(_ other: Self) -> Bool {
        func norm(_ value: String?) -> String { (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return norm(brand) == norm(other.brand) && norm(model) == norm(other.model) && norm(hardwareRevision) == norm(other.hardwareRevision) && norm(marketRegion) == norm(other.marketRegion)
    }
}
public struct DeviceInstallation: Codable, Equatable, Sendable {
    public var role: InstalledRole
    public var mainRouterAnswer: DeclaredAnswer
    public var ownership: OwnershipSource
    public var fiberDirectConnected: DeclaredAnswer
    public var environmentID: UUID?
    /// User label or last known environment name, retained when its association is removed.
    public var locationLabel: String?
    public init(role: InstalledRole = .unknown, mainRouterAnswer: DeclaredAnswer = .unknown, ownership: OwnershipSource = .unknown, fiberDirectConnected: DeclaredAnswer = .unknown, environmentID: UUID? = nil, locationLabel: String? = nil) {
        self.role = role; self.mainRouterAnswer = role == .mainRouter ? .yes : mainRouterAnswer; self.ownership = ownership; self.fiberDirectConnected = fiberDirectConnected; self.environmentID = environmentID; self.locationLabel = locationLabel
    }
    private enum CodingKeys: String, CodingKey { case role, mainRouterAnswer, ownership, fiberDirectConnected, environmentID, locationLabel }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decode(InstalledRole.self, forKey: .role)
        mainRouterAnswer = try c.decodeIfPresent(DeclaredAnswer.self, forKey: .mainRouterAnswer) ?? (role == .mainRouter ? .yes : .unknown)
        ownership = try c.decode(OwnershipSource.self, forKey: .ownership)
        fiberDirectConnected = try c.decode(DeclaredAnswer.self, forKey: .fiberDirectConnected)
        environmentID = try c.decodeIfPresent(UUID.self, forKey: .environmentID)
        locationLabel = try c.decodeIfPresent(String.self, forKey: .locationLabel)
    }
}
public enum EnrichmentStatus: String, Codable, Sendable { case complete, partial, notFound, unavailable }
public struct SpecificationAttribute: Codable, Equatable, Sendable {
    public var key: String
    public var value: String
    public var unit: String?
    public var evidenceIDs: [String]
    public init(key: String, value: String, unit: String? = nil, evidenceIDs: [String]) { self.key = key; self.value = value; self.unit = unit; self.evidenceIDs = evidenceIDs }
}
public struct SpecificationSource: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var url: URL
    public var title: String
    public var retrievedAt: Date
    public var matchedIdentity: DeviceIdentity
    public init(id: String, url: URL, title: String, retrievedAt: Date = Date(), matchedIdentity: DeviceIdentity) { self.id = id; self.url = url; self.title = title; self.retrievedAt = retrievedAt; self.matchedIdentity = matchedIdentity }
}
public struct DeviceSpecificationSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var identity: DeviceIdentity
    public var status: EnrichmentStatus
    public var attributes: [SpecificationAttribute]
    public var sources: [SpecificationSource]
    public var checkedAt: Date
    public init(schemaVersion: Int = 1, identity: DeviceIdentity, status: EnrichmentStatus, attributes: [SpecificationAttribute] = [], sources: [SpecificationSource] = [], checkedAt: Date = Date()) { self.schemaVersion = schemaVersion; self.identity = identity; self.status = status; self.attributes = attributes; self.sources = sources; self.checkedAt = checkedAt }
}
public struct RegisteredNetworkDevice: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: DeviceKind
    public var identity: DeviceIdentity
    public var nickname: String?
    public var installation: DeviceInstallation
    public var specifications: DeviceSpecificationSnapshot?
    public var revision: Int
    public var createdAt: Date
    public var updatedAt: Date
    public init(id: UUID = UUID(), kind: DeviceKind = .router, identity: DeviceIdentity, nickname: String? = nil, installation: DeviceInstallation = .init(), specifications: DeviceSpecificationSnapshot? = nil, revision: Int = 0, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.kind = kind; self.identity = identity; self.nickname = nickname; self.installation = installation; self.specifications = specifications; self.revision = revision; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}
