import Foundation
import XCTest
@testable import NetworkProfiles

final class NetworkProfilesTests: XCTestCase {
    func testCRUDAllowsRepeatedNamesAndAtomicAssignment() async throws {
        let url = temporaryFileURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = FileNetworkProfileRepository(fileURL: url)
        let first = try XCTUnwrap(NetworkEnvironment(name: "Sala"))
        let second = try XCTUnwrap(NetworkEnvironment(name: "Sala"))
        try await repository.create(first)
        try await repository.createAndAssign(second, measurementID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, assignedAt: Date(timeIntervalSince1970: 2))
        let environments = try await repository.environments()
        let assignment = try await repository.assignment(for: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        XCTAssertEqual(environments.map(\.name), ["Sala", "Sala"])
        XCTAssertEqual(assignment?.environmentID, second.id)
    }

    func testReassignmentIsUniqueAndRemovalCascades() async throws {
        let url = temporaryFileURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = FileNetworkProfileRepository(fileURL: url)
        let first = try XCTUnwrap(NetworkEnvironment(name: "Sala")); let second = try XCTUnwrap(NetworkEnvironment(name: "Quarto")); let measurement = UUID()
        try await repository.create(first); try await repository.create(second)
        try await repository.assign(measurementID: measurement, to: first.id, assignedAt: Date())
        try await repository.assign(measurementID: measurement, to: second.id, assignedAt: Date())
        let reassigned = try await repository.assignment(for: measurement)
        XCTAssertEqual(reassigned?.environmentID, second.id)
        try await repository.remove(id: second.id)
        let removed = try await repository.assignment(for: measurement)
        XCTAssertNil(removed)
    }

    func testSchemaTwoRoundTripsAcrossRepositoryInstances() async throws {
        let url = temporaryFileURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let environment = try XCTUnwrap(NetworkEnvironment(name: "Escritório"))
        let measurement = UUID()
        let writer = FileNetworkProfileRepository(fileURL: url)
        try await writer.createAndAssign(environment, measurementID: measurement, assignedAt: Date(timeIntervalSince1970: 42))
        let reader = FileNetworkProfileRepository(fileURL: url)
        let restored = try await reader.environment(id: environment.id)
        XCTAssertEqual(restored, environment)
        let assignment = try await reader.assignment(for: measurement)
        XCTAssertEqual(assignment?.environmentID, environment.id)
        XCTAssertEqual(assignment?.assignedAt, Date(timeIntervalSince1970: 42))
    }

    func testSchemaTwoRejectsOrphanAndDuplicateAssignments() async throws {
        let orphanURL = temporaryFileURL(); let duplicateURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: orphanURL.deletingLastPathComponent()); try? FileManager.default.removeItem(at: duplicateURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: orphanURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: duplicateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let orphan = #"{"schemaVersion":2,"environments":[],"assignments":[{"measurementID":"00000000-0000-0000-0000-000000000001","environmentID":"00000000-0000-0000-0000-000000000002","assignedAt":1}]}"#
        let duplicate = #"{"schemaVersion":2,"environments":[{"id":"00000000-0000-0000-0000-000000000002","name":"Sala","createdAt":1,"updatedAt":2}],"assignments":[{"measurementID":"00000000-0000-0000-0000-000000000001","environmentID":"00000000-0000-0000-0000-000000000002","assignedAt":1},{"measurementID":"00000000-0000-0000-0000-000000000001","environmentID":"00000000-0000-0000-0000-000000000002","assignedAt":2}]}"#
        try Data(orphan.utf8).write(to: orphanURL); try Data(duplicate.utf8).write(to: duplicateURL)
        await assertError(.corruptedStore, repository: FileNetworkProfileRepository(fileURL: orphanURL))
        await assertError(.corruptedStore, repository: FileNetworkProfileRepository(fileURL: duplicateURL))
    }

    func testSchemaOneMigrationPersistenceFailurePreservesLegacyFile() async throws {
        let url = temporaryFileURL()
        let parent = url.deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
            try? FileManager.default.removeItem(at: parent)
        }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let legacy = Data(#"{"schemaVersion":1,"profiles":[{"id":"40E6215D-B5C6-4896-987C-F30F3678F608","identity":{"version":1,"fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"name":"Sala","createdAt":1000,"updatedAt":2000}]}"#.utf8)
        try legacy.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: parent.path)
        let repository = FileNetworkProfileRepository(fileURL: url)
        do {
            _ = try await repository.environments()
            XCTFail("Expected migration persistence failure")
        } catch let error as NetworkProfileRepositoryError {
            XCTAssertEqual(error, .persistenceFailed)
        }
        XCTAssertEqual(try Data(contentsOf: url), legacy)
    }

    func testSchemaOneMigrationPreservesNameAndIDWithoutAssignmentsOrIdentity() async throws {
        let url = temporaryFileURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let id = UUID(uuidString: "40E6215D-B5C6-4896-987C-F30F3678F608")!
        let json = #"{"schemaVersion":1,"profiles":[{"id":"40E6215D-B5C6-4896-987C-F30F3678F608","identity":{"version":1,"fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"name":"Sala","createdAt":1000,"updatedAt":2000,"referenceStartedAt":1000}]}"#
        try Data(json.utf8).write(to: url)
        let repository = FileNetworkProfileRepository(fileURL: url)
        let environments = try await repository.environments()
        XCTAssertEqual(environments.first?.id, id); XCTAssertEqual(environments.first?.name, "Sala")
        let assignments = try await repository.assignments(for: id)
        XCTAssertTrue(assignments.isEmpty)
        let persisted = try String(decoding: Data(contentsOf: url), as: UTF8.self)
        XCTAssertTrue(persisted.contains("\"schemaVersion\":2")); XCTAssertFalse(persisted.contains("identity")); XCTAssertFalse(persisted.contains("fingerprint"))
    }

    func testInvalidAndFutureStoresFailClosed() async throws {
        let corrupt = temporaryFileURL(); let future = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: corrupt.deletingLastPathComponent()); try? FileManager.default.removeItem(at: future.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: corrupt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: future.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: corrupt); try Data("{\"schemaVersion\":99}".utf8).write(to: future)
        await assertError(.corruptedStore, repository: FileNetworkProfileRepository(fileURL: corrupt))
        await assertError(.unsupportedStoreVersion(99), repository: FileNetworkProfileRepository(fileURL: future))
    }

    private func assertError(_ expected: NetworkProfileRepositoryError, repository: FileNetworkProfileRepository) async {
        do { _ = try await repository.environments(); XCTFail("Expected error") }
        catch let error as NetworkProfileRepositoryError { XCTAssertEqual(error, expected) }
        catch { XCTFail("Unexpected error: \(error)") }
    }
    private func temporaryFileURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("NetworkProfilesTests-\(UUID().uuidString)").appendingPathComponent("profiles.json") }
}
