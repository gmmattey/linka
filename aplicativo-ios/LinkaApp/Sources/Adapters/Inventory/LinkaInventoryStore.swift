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
        InventoryBuildConfiguration.isEnabled
    }
}

@MainActor
final class LinkaInventoryStore: ObservableObject {
    @Published private(set) var devices: [RegisteredNetworkDevice] = []
    @Published private(set) var environments: [NetworkEnvironment] = []
    @Published private(set) var homeProfile: HomeNetworkProfile?
    @Published private(set) var activePlan: NetworkServicePlan?
    @Published private(set) var plans: [NetworkServicePlan] = []
    @Published private(set) var connections: [DeviceConnection] = []
    @Published var error: String?
    @Published private(set) var loading = false

    private let repository: HouseholdRepository

    init(repository: HouseholdRepository = LinkaHousehold.repository) {
        self.repository = repository
    }

    func reload() async {
        loading = true
        defer { loading = false }
        do {
            devices = try await repository.devices()
            environments = try await repository.environments()
            homeProfile = try await repository.homeProfile()
            plans = try await repository.plans()
            connections = try await repository.connections()
            if let activePlanID = homeProfile?.activePlanID {
                activePlan = plans.first(where: { $0.id == activePlanID })
            } else {
                activePlan = nil
            }
            error = nil
        } catch {
            self.error = Self.message(error)
        }
    }

    func save(_ draft: RegisteredNetworkDevice) async -> Bool {
        do {
            _ = try await repository.saveDevice(draft, expectedRevision: draft.revision == 0 ? nil : draft.revision)
            NotificationCenter.default.post(name: LinkaHousehold.didChange, object: nil)
            await reload()
            return true
        } catch {
            self.error = Self.message(error)
            return false
        }
    }

    func delete(_ device: RegisteredNetworkDevice) async {
        do {
            try await repository.removeDevice(id: device.id, expectedRevision: device.revision)
            NotificationCenter.default.post(name: LinkaHousehold.didChange, object: nil)
            await reload()
        } catch {
            self.error = Self.message(error)
        }
    }

    // MARK: - Plans

    func savePlan(_ plan: NetworkServicePlan, makeActive: Bool = true) async -> Bool {
        do {
            let saved = try await repository.savePlan(plan)
            if makeActive {
                var profile = (try await repository.homeProfile()) ?? HomeNetworkProfile(displayName: "Minha Rede")
                profile.activePlanID = saved.id
                _ = try await repository.saveHomeProfile(profile)
            }
            NotificationCenter.default.post(name: LinkaHousehold.didChange, object: nil)
            await reload()
            return true
        } catch {
            self.error = Self.message(error)
            return false
        }
    }

    func replacePlan(current: NetworkServicePlan, with newPlan: NetworkServicePlan, effectiveDate: Date = Date()) async -> Bool {
        do {
            var updatedCurrent = current
            updatedCurrent.effectiveTo = effectiveDate
            updatedCurrent.updatedAt = Date()
            _ = try await repository.savePlan(updatedCurrent)

            var next = newPlan
            if next.effectiveFrom == nil {
                next.effectiveFrom = effectiveDate
            }
            let savedNext = try await repository.savePlan(next)

            var profile = (try await repository.homeProfile()) ?? HomeNetworkProfile(displayName: "Minha Rede")
            profile.activePlanID = savedNext.id
            _ = try await repository.saveHomeProfile(profile)

            NotificationCenter.default.post(name: LinkaHousehold.didChange, object: nil)
            await reload()
            return true
        } catch {
            self.error = Self.message(error)
            return false
        }
    }

    func deletePlan(id: UUID) async -> Bool {
        do {
            try await repository.removePlan(id: id)
            NotificationCenter.default.post(name: LinkaHousehold.didChange, object: nil)
            await reload()
            return true
        } catch {
            self.error = Self.message(error)
            return false
        }
    }

    // MARK: - Connections

    func saveConnection(_ connection: DeviceConnection) async -> Bool {
        do {
            _ = try await repository.saveConnection(connection)
            NotificationCenter.default.post(name: LinkaHousehold.didChange, object: nil)
            await reload()
            return true
        } catch {
            self.error = Self.message(error)
            return false
        }
    }

    func deleteConnection(id: UUID) async -> Bool {
        do {
            try await repository.removeConnection(id: id)
            NotificationCenter.default.post(name: LinkaHousehold.didChange, object: nil)
            await reload()
            return true
        } catch {
            self.error = Self.message(error)
            return false
        }
    }

    func connections(for deviceID: UUID) -> [DeviceConnection] {
        connections.filter { $0.endpointADeviceID == deviceID || $0.endpointBDeviceID == deviceID }
    }

    static func message(_ error: Error) -> String {
        if let error = error as? NetworkInventoryError {
            switch error {
            case .conflict:
                return LinkaCopy.value("inventory.error.conflict")
            case .duplicateConnection:
                return LinkaCopy.value("inventory.connection.duplicateError")
            case .invalidConnection:
                return LinkaCopy.value("inventory.connection.invalidError")
            case .invalidPlan:
                return LinkaCopy.value("inventory.plan.invalidError")
            case .invalidProfile:
                return LinkaCopy.value("inventory.profile.invalidError")
            default:
                return LinkaCopy.value("inventory.error.storage")
            }
        }
        return LinkaCopy.value("inventory.error.storage")
    }
}

extension RegisteredNetworkDevice {
    var inventoryTitle: String {
        if let nickname, !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nickname
        }
        let fullName = [identity.brand, identity.model].filter { !$0.isEmpty }.joined(separator: " ")
        return fullName.isEmpty ? LinkaCopy.value("inventory.unknown") : fullName
    }
}
