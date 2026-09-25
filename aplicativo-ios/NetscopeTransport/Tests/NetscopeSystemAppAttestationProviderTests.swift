import CryptoKit
import Foundation
import NetscopeEvidence
@testable import NetscopeTransport
import XCTest

final class NetscopeSystemAppAttestationProviderTests: XCTestCase {
    func testRegistrationCreatesAndPersistsOnlyAppleKeyReference() async throws {
        let service = TestAppAttestService()
        let store = TestKeyStore()
        let provider = NetscopeSystemAppAttestationProvider(service: service, keyStore: store)
        let challenge = NetscopeRegistrationChallenge(value: Data(repeating: 7, count: 32))

        let first = try await provider.makeRegistrationProof(for: challenge)
        let second = try await provider.makeRegistrationProof(for: challenge)

        XCTAssertEqual(first.keyID, "apple-key-reference")
        XCTAssertEqual(second.keyID, first.keyID)
        XCTAssertEqual(first.attestation, Data("apple-attestation".utf8))
        XCTAssertEqual(service.generatedKeyCount, 1)
        XCTAssertEqual(service.attestedKeyIDs, [first.keyID, first.keyID])
        XCTAssertEqual(service.attestationHashes, [challenge.value, challenge.value])
        XCTAssertEqual(try store.readKeyID(), first.keyID)
    }

    func testAssertionUsesStoredReferenceAndExactSignedRequestDigest() async throws {
        let service = TestAppAttestService()
        let store = TestKeyStore(keyID: "apple-key-reference")
        let provider = NetscopeSystemAppAttestationProvider(service: service, keyStore: store)
        let body = Data("{\"measurement\":1}".utf8)
        let challenge = NetscopeAnalysisAssertionChallenge(nonce: "single-use", timestampUnixMilliseconds: 1_700_000_000_000)
        let input = NetscopeAttestationAssertionInput(
            binding: .init(exactBody: body), exactBody: body, challenge: challenge
        )

        let proof = try await provider.makeAssertion(for: input, using: challenge)

        XCTAssertEqual(proof.keyID, "apple-key-reference")
        XCTAssertEqual(proof.assertion, Data("apple-assertion".utf8))
        XCTAssertEqual(service.assertedKeyIDs, [proof.keyID])
        XCTAssertEqual(service.assertionHashes, [input.signedRequestSHA256])
        XCTAssertEqual(service.generatedKeyCount, 0)
    }

    func testUnsupportedAppleServiceFailsClosedWithoutCreatingOrReadingKey() async {
        let service = TestAppAttestService(isSupported: false)
        let store = TestKeyStore()
        let provider = NetscopeSystemAppAttestationProvider(service: service, keyStore: store)

        do {
            _ = try await provider.makeRegistrationProof(
                for: .init(value: Data(repeating: 1, count: 32))
            )
            XCTFail("Expected unavailable")
        } catch let error as NetscopeSystemAppAttestationError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(service.generatedKeyCount, 0)
        XCTAssertEqual(store.readCount, 0)
    }

    func testMalformedRegistrationChallengeFailsBeforeAppleKeyGeneration() async {
        let service = TestAppAttestService()
        let store = TestKeyStore()
        let provider = NetscopeSystemAppAttestationProvider(service: service, keyStore: store)

        do {
            _ = try await provider.makeRegistrationProof(for: .init(value: Data("not-a-hash".utf8)))
            XCTFail("Expected invalid challenge")
        } catch let error as NetscopeSystemAppAttestationError {
            XCTAssertEqual(error, .invalidChallenge)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(service.generatedKeyCount, 0)
        XCTAssertEqual(store.readCount, 0)
    }

    func testMismatchedAssertionChallengeFailsBeforeCallingApple() async {
        let service = TestAppAttestService()
        let store = TestKeyStore(keyID: "apple-key-reference")
        let provider = NetscopeSystemAppAttestationProvider(service: service, keyStore: store)
        let body = Data("{\"measurement\":1}".utf8)
        let boundChallenge = NetscopeAnalysisAssertionChallenge(nonce: "bound", timestampUnixMilliseconds: 1_700_000_000_000)
        let input = NetscopeAttestationAssertionInput(
            binding: .init(exactBody: body), exactBody: body, challenge: boundChallenge
        )
        let swappedChallenge = NetscopeAnalysisAssertionChallenge(nonce: "swapped", timestampUnixMilliseconds: 1_700_000_000_001)

        do {
            _ = try await provider.makeAssertion(for: input, using: swappedChallenge)
            XCTFail("Expected invalid challenge")
        } catch let error as NetscopeSystemAppAttestationError {
            XCTAssertEqual(error, .invalidChallenge)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(service.assertedKeyIDs.isEmpty)
    }
}

private final class TestAppAttestService: NetscopeAppleAppAttestServicing, @unchecked Sendable {
    let isSupported: Bool
    private(set) var generatedKeyCount = 0
    private(set) var attestedKeyIDs: [String] = []
    private(set) var attestationHashes: [Data] = []
    private(set) var assertedKeyIDs: [String] = []
    private(set) var assertionHashes: [Data] = []

    init(isSupported: Bool = true) { self.isSupported = isSupported }

    func generateKey() async throws -> String {
        generatedKeyCount += 1
        return "apple-key-reference"
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        attestedKeyIDs.append(keyID)
        attestationHashes.append(clientDataHash)
        return Data("apple-attestation".utf8)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        assertedKeyIDs.append(keyID)
        assertionHashes.append(clientDataHash)
        return Data("apple-assertion".utf8)
    }
}

private final class TestKeyStore: NetscopeAppAttestKeyIDStoring, @unchecked Sendable {
    private var keyID: String?
    private(set) var readCount = 0

    init(keyID: String? = nil) { self.keyID = keyID }

    func readKeyID() throws -> String? {
        readCount += 1
        return keyID
    }

    func writeKeyID(_ keyID: String) throws { self.keyID = keyID }
}
