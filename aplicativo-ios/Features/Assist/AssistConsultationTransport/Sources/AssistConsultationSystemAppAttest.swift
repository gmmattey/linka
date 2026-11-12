#if os(iOS)
import DeviceCheck
import Foundation
import Security

/// Implementação iOS do App Attest. Não é compilada para macOS e o framework
/// Apple mantém a chave privada fora deste processo.
@available(iOS 16.0, *)
public struct AssistConsultationSystemAppAttestProvider: AssistConsultationAppAttestProviding {
    public init() {}

    public func isSupported() async -> Bool {
        DCAppAttestService.shared.isSupported
    }

    public func generateKey() async throws -> String {
        try await DCAppAttestService.shared.generateKey()
    }

    public func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
    }

    public func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
    }
}

/// Armazena exclusivamente o Key ID público/opaco. A service namespace não é
/// compartilhada com Netscope, Assist legado ou qualquer outra funcionalidade.
public final class AssistConsultationKeychainAppAttestKeyIDStore: AssistConsultationAppAttestKeyIDStoring, @unchecked Sendable {
    private static let service = "com.buildea.linka.assist-consultation-v4.app-attest"
    private static let account = "key-id"

    public init() {}

    public func loadKeyID() async throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let keyID = String(data: data, encoding: .utf8),
              !keyID.isEmpty else {
            throw AssistConsultationKeychainError(status: status)
        }
        return keyID
    }

    public func saveKeyID(_ keyID: String) async throws {
        guard !keyID.isEmpty else { throw AssistConsultationKeychainError(status: errSecParam) }
        let data = Data(keyID.utf8)
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw AssistConsultationKeychainError(status: updateStatus) }

        var insert = lookup
        attributes.forEach { insert[$0.key] = $0.value }
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else { throw AssistConsultationKeychainError(status: insertStatus) }
    }
}

public struct AssistConsultationKeychainError: Error, Equatable, Sendable {
    /// O status é preservado somente para a composição decidir retry local; não
    /// deve ser enviado ao relay ou mostrado como dado de diagnóstico do usuário.
    public let status: OSStatus
}
#endif
