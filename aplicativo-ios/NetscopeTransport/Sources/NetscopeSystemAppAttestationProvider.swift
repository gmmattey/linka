import CryptoKit
import Foundation

#if canImport(DeviceCheck) && os(iOS)
@preconcurrency import DeviceCheck
import Security
#endif

/// Falhas locais da ponte Apple. Elas nunca carregam desafio, assertion ou
/// identificador de chave para a camada de apresentação.
public enum NetscopeSystemAppAttestationError: Error, Equatable, Sendable {
    case unavailable
    case invalidChallenge
    case invalidKeyReference
    case storageFailure
    case malformedAppleResponse
}

/// O resultado opaco de registrar uma chave com a Apple. A composição futura
/// poderá enviá-lo ao endpoint de registro, mas este pacote não faz I/O.
public struct NetscopeRegistrationProof: Equatable, Sendable {
    public let keyID: String
    public let attestation: Data

    public init(keyID: String, attestation: Data) {
        self.keyID = keyID
        self.attestation = attestation
    }
}

/// Armazena somente a referência da chave gerada pela Apple. A chave privada
/// nunca sai do hardware e desafios, assertions e dados de medição não são
/// persistidos aqui.
public protocol NetscopeAppAttestKeyIDStoring: Sendable {
    func readKeyID() throws -> String?
    func writeKeyID(_ keyID: String) throws
}

/// Porta pequena para testar a integração sem exigir um aparelho físico.
/// `clientDataHash` já deve ter 32 bytes; esta camada não inventa nem altera
/// o material assinado.
public protocol NetscopeAppleAppAttestServicing: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

/// Ponte de App Attest sem rede. Esta camada por si só só sabe falar com o
/// framework da Apple, disponível em iPhone e iPad reais; simulador, Mac e
/// qualquer erro ficam indisponíveis. Netscope é iPhone-only por decisão de
/// produto — quem decide isso é `NetscopeClientPlatform`/`NetscopeSystemAppAttestAvailability`
/// na composição, não esta ponte. A criação/atestado de chave e a assertion seguem separados
/// para que cada um receba o challenge próprio do contrato V2.
public actor NetscopeSystemAppAttestationProvider {
    private let service: any NetscopeAppleAppAttestServicing
    private let keyStore: any NetscopeAppAttestKeyIDStoring

    public init(
        service: any NetscopeAppleAppAttestServicing,
        keyStore: any NetscopeAppAttestKeyIDStoring
    ) {
        self.service = service
        self.keyStore = keyStore
    }

    /// Obtém ou cria a referência local e produz o objeto de atestação para o
    /// challenge exclusivo de registro. O contrato V2 entrega os 32 bytes
    /// aleatórios do nonce; a API Apple exige o SHA-256 desses bytes como
    /// clientDataHash. Nunca trate o nonce como se ele já fosse o hash.
    public func makeRegistrationProof(
        for challenge: NetscopeRegistrationChallenge
    ) async throws -> NetscopeRegistrationProof {
        guard service.isSupported else { throw NetscopeSystemAppAttestationError.unavailable }
        guard challenge.value.count == 32 else { throw NetscopeSystemAppAttestationError.invalidChallenge }

        let keyID = try await existingOrNewKeyID()
        let clientDataHash = Data(SHA256.hash(data: challenge.value))
        let attestation = try await service.attestKey(keyID, clientDataHash: clientDataHash)
        guard !attestation.isEmpty else { throw NetscopeSystemAppAttestationError.malformedAppleResponse }
        return .init(keyID: keyID, attestation: attestation)
    }

    /// Produz uma assertion apenas para o frame V2 já validado pelo cliente.
    /// Não cria uma nova chave, não tenta recuperação automática e não faz
    /// retry: qualquer condição inesperada deve permanecer fechada.
    public func makeAssertion(
        for input: NetscopeAttestationAssertionInput,
        using challenge: NetscopeAnalysisAssertionChallenge
    ) async throws -> NetscopeAttestationProof {
        guard service.isSupported else { throw NetscopeSystemAppAttestationError.unavailable }
        guard !challenge.nonce.isEmpty,
              challenge.timestampUnixMilliseconds > 0,
              challenge.timestampUnixMilliseconds <= 9_007_199_254_740_991,
              input.nonce == challenge.nonce,
              input.timestampUnixMilliseconds == challenge.timestampUnixMilliseconds,
              input.signedRequestSHA256.count == 32 else {
            // The client repeats the complete binding check against the exact
            // body before this method is reached. Here we can only reject an
            // incomplete challenge or a malformed digest.
            throw NetscopeSystemAppAttestationError.invalidChallenge
        }
        let keyID: String
        do {
            guard let stored = try keyStore.readKeyID(), Self.isValidKeyID(stored) else {
                throw NetscopeSystemAppAttestationError.invalidKeyReference
            }
            keyID = stored
        } catch let error as NetscopeSystemAppAttestationError {
            throw error
        } catch {
            throw NetscopeSystemAppAttestationError.storageFailure
        }
        let assertion = try await service.generateAssertion(keyID, clientDataHash: input.signedRequestSHA256)
        guard !assertion.isEmpty else { throw NetscopeSystemAppAttestationError.malformedAppleResponse }
        return .init(keyID: keyID, assertion: assertion)
    }

    private func existingOrNewKeyID() async throws -> String {
        do {
            if let stored = try keyStore.readKeyID() {
                guard Self.isValidKeyID(stored) else { throw NetscopeSystemAppAttestationError.invalidKeyReference }
                return stored
            }
        } catch let error as NetscopeSystemAppAttestationError {
            throw error
        } catch {
            throw NetscopeSystemAppAttestationError.storageFailure
        }

        let generated = try await service.generateKey()
        guard Self.isValidKeyID(generated) else { throw NetscopeSystemAppAttestationError.malformedAppleResponse }
        do {
            try keyStore.writeKeyID(generated)
        } catch {
            throw NetscopeSystemAppAttestationError.storageFailure
        }
        return generated
    }

    private static func isValidKeyID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512 && value.unicodeScalars.allSatisfy { !$0.properties.isWhitespace }
    }
}

#if canImport(DeviceCheck) && os(iOS)
/// Implementação de produção da API Apple. Esta classe não conhece endpoint,
/// host ou transporte; ela só fala com o serviço local do sistema.
@available(iOS 14.0, *)
public final class NetscopeDeviceCheckAppAttestService: NetscopeAppleAppAttestServicing, @unchecked Sendable {
    private let appAttestService: DCAppAttestService

    public init(appAttestService: DCAppAttestService = .shared) {
        self.appAttestService = appAttestService
    }

    public var isSupported: Bool { appAttestService.isSupported }

    public func generateKey() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            appAttestService.generateKey { keyID, error in
                if let error { continuation.resume(throwing: error); return }
                guard let keyID, !keyID.isEmpty else {
                    continuation.resume(throwing: NetscopeSystemAppAttestationError.malformedAppleResponse)
                    return
                }
                continuation.resume(returning: keyID)
            }
        }
    }

    public func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            appAttestService.attestKey(keyID, clientDataHash: clientDataHash) { attestation, error in
                if let error { continuation.resume(throwing: error); return }
                guard let attestation, !attestation.isEmpty else {
                    continuation.resume(throwing: NetscopeSystemAppAttestationError.malformedAppleResponse)
                    return
                }
                continuation.resume(returning: attestation)
            }
        }
    }

    public func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            appAttestService.generateAssertion(keyID, clientDataHash: clientDataHash) { assertion, error in
                if let error { continuation.resume(throwing: error); return }
                guard let assertion, !assertion.isEmpty else {
                    continuation.resume(throwing: NetscopeSystemAppAttestationError.malformedAppleResponse)
                    return
                }
                continuation.resume(returning: assertion)
            }
        }
    }
}

/// Keychain privado ao aparelho. Guarda somente o identificador devolvido
/// pela Apple, sem backup/restauração para outro dispositivo.
public final class NetscopeKeychainAppAttestKeyIDStore: NetscopeAppAttestKeyIDStoring, @unchecked Sendable {
    private let service: String
    private let account: String

    public init(
        service: String = "com.linka.netscope.app-attest",
        account: String = "key-id-v1"
    ) {
        self.service = service
        self.account = account
    }

    public func readKeyID() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let keyID = String(data: data, encoding: .utf8) else {
            throw NetscopeSystemAppAttestationError.storageFailure
        }
        return keyID
    }

    public func writeKeyID(_ keyID: String) throws {
        guard !keyID.isEmpty else { throw NetscopeSystemAppAttestationError.invalidKeyReference }
        let data = Data(keyID.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw NetscopeSystemAppAttestationError.storageFailure
        }
        var create = query
        attributes.forEach { create[$0.key] = $0.value }
        guard SecItemAdd(create as CFDictionary, nil) == errSecSuccess else {
            throw NetscopeSystemAppAttestationError.storageFailure
        }
    }
}
#endif
