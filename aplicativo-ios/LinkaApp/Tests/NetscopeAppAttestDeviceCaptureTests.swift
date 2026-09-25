import XCTest
import CryptoKit
import NetscopeTransport

#if canImport(DeviceCheck)
import DeviceCheck
#endif

/// Not a correctness test: a one-time capture of genuine App Attest bytes
/// from the connected physical iPhone, for a17/a18's mandatory input #1
/// ("fixtures Apple verificadas"). It never asserts pass/fail on the
/// captured shape — that is the backend verifier's job against these same
/// bytes. It skips itself everywhere except a real, supported device so it
/// can stay in the test target without affecting CI or simulator runs.
///
/// Captured values are attached to the Xcode result bundle (`XCTAttachment`,
/// base64 text), never printed to a log or committed to the repo — they are
/// a real device's key material and must be handled like the physical
/// evidence they are.
final class NetscopeAppAttestDeviceCaptureTests: XCTestCase {
    func test_captureOneRealRegistrationAndAssertion() async throws {
        #if canImport(DeviceCheck)
        let service = DCAppAttestService.shared
        guard service.isSupported else {
            throw XCTSkip("DCAppAttestService unavailable on this destination (simulator or unsupported host).")
        }

        let keyId = try await service.generateKey()
        attach(name: "key-id", text: keyId)

        let nonce = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        attach(name: "registration-nonce-base64", text: nonce.base64EncodedString())

        let clientDataHash = Data(SHA256.hash(data: nonce))
        let attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash)
        attach(name: "attestation-object-base64", text: attestation.base64EncodedString())

        let message = Data("device-capture-fixture-message-v1".utf8)
        let assertionClientDataHash = Data(SHA256.hash(data: message))
        let assertion = try await service.generateAssertion(keyId, clientDataHash: assertionClientDataHash)
        attach(name: "assertion-message-utf8-base64", text: message.base64EncodedString())
        attach(name: "assertion-object-base64", text: assertion.base64EncodedString())

        XCTAssertFalse(attestation.isEmpty)
        XCTAssertFalse(assertion.isEmpty)
        #else
        throw XCTSkip("DeviceCheck is not available on this platform.")
        #endif
    }

    private func attach(name: String, text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
