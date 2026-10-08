import Foundation
import Combine
import NetworkInventory
import NetworkProfiles

/// One household store per process; all environment writers use this composition.
enum LinkaHousehold {
    static let repository: HouseholdRepository = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Linka", isDirectory: true)
        return HouseholdRepository(
            profiles: FileNetworkProfileRepository(fileURL: base.appendingPathComponent("network-profiles-v1.json")),
            inventory: FileNetworkInventoryRepository(fileURL: base.appendingPathComponent("network-inventory-v1.json")))
    }()
    static let didChange = Notification.Name("LinkaHouseholdDidChange")
}

enum MinhaRedeAvailability {
    static var isEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

@MainActor
final class LinkaInventoryStore: ObservableObject {
    @Published private(set) var devices: [RegisteredNetworkDevice] = []
    @Published private(set) var environments: [NetworkEnvironment] = []
    @Published var error: String?
    @Published private(set) var loading = false
    private let repository: HouseholdRepository
    init(repository: HouseholdRepository = LinkaHousehold.repository) { self.repository = repository }

    func reload() async {
        loading = true
        defer { loading = false }
        do {
            devices = try await repository.devices()
            environments = try await repository.environments()
            error = nil
        } catch { self.error = Self.message(error) }
    }
    func save(_ draft: RegisteredNetworkDevice) async -> Bool {
        do {
            _ = try await repository.saveDevice(draft, expectedRevision: draft.revision == 0 ? nil : draft.revision)
            NotificationCenter.default.post(name: LinkaHousehold.didChange, object: nil)
            await reload()
            return true
        } catch { self.error = Self.message(error); return false }
    }
    func delete(_ device: RegisteredNetworkDevice) async {
        do {
            try await repository.removeDevice(id: device.id, expectedRevision: device.revision)
            NotificationCenter.default.post(name: LinkaHousehold.didChange, object: nil)
            await reload()
        } catch { self.error = Self.message(error) }
    }
    static func message(_ error: Error) -> String {
        if let error = error as? NetworkInventoryError, error == .conflict {
            return LinkaCopy.value("inventory.error.conflict")
        }
        return LinkaCopy.value("inventory.error.storage")
    }
}
