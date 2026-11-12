import CryptoKit
import Foundation

/// Fronteira criptográfica exclusiva da consulta Assist V4.
///
/// A API é intencionalmente separada do transporte HTTP: challenges e proofs
/// entram e saem por protocolos injetados e este arquivo nunca cria uma
/// `URLSession`, não conhece o legacy `/v2/assist` e não possui fallback para
/// outra plataforma. A chave privada permanece dentro do Secure Enclave gerido
/// pelo App Attest; somente o identificador opaco da chave é mantido no
/// Keychain.
public enum AssistConsultationAttestationProtocol {
    public static let version = "linka.assist.consultation.app-attest/1"
    public static let consultationMethod = "POST"
    public static let consultationPath = "/v1/assist/consultations"
}

public struct AssistConsultationRegistrationChallenge: Codable, Equatable, Sendable {
    public let protocolVersion: String
    public let purpose: String
    public let nonce: String
    public let expiresAt: Int64

    public init(protocolVersion: String, purpose: String, nonce: String, expiresAt: Int64) {
        self.protocolVersion = protocolVersion
        self.purpose = purpose
        self.nonce = nonce
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol"
        case purpose
        case nonce
        case expiresAt
    }
}

public struct AssistConsultationRegistrationProof: Codable, Equatable, Sendable {
    public let keyID: String
    public let attestation: String
    public let nonce: String
    public let timestampUnixMilliseconds: String

    public init(keyID: String, attestation: String, nonce: String, timestampUnixMilliseconds: String) {
        self.keyID = keyID
        self.attestation = attestation
        self.nonce = nonce
        self.timestampUnixMilliseconds = timestampUnixMilliseconds
    }

    enum CodingKeys: String, CodingKey {
        case keyID
        case attestation
        case nonce
        case timestampUnixMilliseconds
    }
}

/// O servidor recebe este binding antes de emitir o challenge de assertion.
/// SHA-256 é base64url sem padding, exatamente como no worker V4.
public struct AssistConsultationAssertionBinding: Codable, Equatable, Sendable {
    public let purpose: String
    public let method: String
    public let path: String
    public let requestSHA256: String

    public init(exactBody: Data) {
        purpose = "consultation_assertion"
        method = AssistConsultationAttestationProtocol.consultationMethod
        path = AssistConsultationAttestationProtocol.consultationPath
        requestSHA256 = Data(SHA256.hash(data: exactBody)).base64URLEncodedString()
    }
}

public struct AssistConsultationAssertionChallenge: Codable, Equatable, Sendable {
    public let protocolVersion: String
    public let purpose: String
    public let binding: AssistConsultationAssertionBinding
    public let nonce: String
    public let timestampUnixMilliseconds: String
    public let expiresAt: Int64

    public init(
        protocolVersion: String,
        purpose: String,
        binding: AssistConsultationAssertionBinding,
        nonce: String,
        timestampUnixMilliseconds: String,
        expiresAt: Int64
    ) {
        self.protocolVersion = protocolVersion
        self.purpose = purpose
        self.binding = binding
        self.nonce = nonce
        self.timestampUnixMilliseconds = timestampUnixMilliseconds
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol"
        case purpose
        case binding
        case nonce
        case timestampUnixMilliseconds
        case expiresAt
    }
}

/// A proof pronta para acompanhar um único POST V4. A composição HTTP futura
/// deve mapear estes valores para os headers definidos pela rota, sem alterar
/// assertion, nonce, timestamp ou o corpo que foi assinado.
public struct AssistConsultationRequestAttestation: Equatable, Sendable {
    public let keyID: String
    public let assertion: String
    public let nonce: String
    public let timestampUnixMilliseconds: String
    public let requestSHA256: String

    public init(
        keyID: String,
        assertion: String,
        nonce: String,
        timestampUnixMilliseconds: String,
        requestSHA256: String
    ) {
        self.keyID = keyID
        self.assertion = assertion
        self.nonce = nonce
        self.timestampUnixMilliseconds = timestampUnixMilliseconds
        self.requestSHA256 = requestSHA256
    }
}

/// As quatro chamadas remotas do handshake permanecem injetadas. Isto evita
/// que o pacote abra tráfego fora do composition root iOS e deixa o protocolo
/// testável sem aparelho ou backend.
public protocol AssistConsultationAttestationExchanging: Sendable {
    func requestRegistrationChallenge() async throws -> AssistConsultationRegistrationChallenge
    func register(_ proof: AssistConsultationRegistrationProof) async throws
    func requestAssertionChallenge(
        for binding: AssistConsultationAssertionBinding,
        keyID: String
    ) async throws -> AssistConsultationAssertionChallenge
}

/// Adaptador mínimo sobre `DCAppAttestService`. A implementação concreta só
/// é exposta no iOS e não exporta nenhuma chave privada.
public protocol AssistConsultationAppAttestProviding: Sendable {
    func isSupported() async -> Bool
    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

/// Guarda somente a referência da chave que a Apple mantém fora do processo.
/// A interface assíncrona permite doubles de teste seguros por actor.
public protocol AssistConsultationAppAttestKeyIDStoring: Sendable {
    func loadKeyID() async throws -> String?
    func saveKeyID(_ keyID: String) async throws
}

public enum AssistConsultationAttestationOutcome: Equatable, Sendable {
    case authorized(AssistConsultationRequestAttestation)
    case unavailable
}

/// Orquestra a primeira atestação e as assertions seguintes. Falha fechada:
/// qualquer challenge inconsistente, relógio inválido, Keychain/App Attest
/// indisponível ou erro de I/O devolve apenas `unavailable` e não gera proof
/// parcial que pudesse chegar ao relay.
public struct AssistConsultationAppAttestAuthorizer: Sendable {
    private let appAttest: any AssistConsultationAppAttestProviding
    private let keyIDStore: any AssistConsultationAppAttestKeyIDStoring
    private let exchange: any AssistConsultationAttestationExchanging

    public init(
        appAttest: any AssistConsultationAppAttestProviding,
        keyIDStore: any AssistConsultationAppAttestKeyIDStoring,
        exchange: any AssistConsultationAttestationExchanging
    ) {
        self.appAttest = appAttest
        self.keyIDStore = keyIDStore
        self.exchange = exchange
    }

    public func authorize(
        exactBody: Data,
        now: Date = Date()
    ) async -> AssistConsultationAttestationOutcome {
        guard await appAttest.isSupported() else { return .unavailable }

        do {
            let keyID = try await registeredKeyID(now: now)
            let binding = AssistConsultationAssertionBinding(exactBody: exactBody)
            let challenge = try await exchange.requestAssertionChallenge(for: binding, keyID: keyID)
            guard challenge.isValid(for: binding, now: now) else { return .unavailable }
            guard let clientDataHash = assertionClientDataHash(exactBody: exactBody, challenge: challenge) else {
                return .unavailable
            }
            let assertion = try await appAttest.generateAssertion(keyID, clientDataHash: clientDataHash)
            guard !assertion.isEmpty else { return .unavailable }

            return .authorized(.init(
                keyID: keyID,
                assertion: assertion.base64URLEncodedString(),
                nonce: challenge.nonce,
                timestampUnixMilliseconds: challenge.timestampUnixMilliseconds,
                requestSHA256: binding.requestSHA256
            ))
        } catch {
            return .unavailable
        }
    }

    private func registeredKeyID(now: Date) async throws -> String {
        if let existing = try await keyIDStore.loadKeyID(), !existing.isEmpty {
            return existing
        }

        let challenge = try await exchange.requestRegistrationChallenge()
        guard challenge.isValid(now: now) else { throw AssistConsultationAttestationError.invalidChallenge }
        let keyID = try await appAttest.generateKey()
        guard !keyID.isEmpty else { throw AssistConsultationAttestationError.invalidKeyID }
        let clientDataHash = Data(SHA256.hash(data: Data(challenge.nonce.utf8)))
        let attestation = try await appAttest.attestKey(keyID, clientDataHash: clientDataHash)
        guard !attestation.isEmpty else { throw AssistConsultationAttestationError.emptyProof }
        try await exchange.register(.init(
            keyID: keyID,
            attestation: attestation.base64URLEncodedString(),
            nonce: challenge.nonce,
            timestampUnixMilliseconds: String(Self.unixMilliseconds(now))
        ))
        try await keyIDStore.saveKeyID(keyID)
        return keyID
    }

    private func assertionClientDataHash(
        exactBody: Data,
        challenge: AssistConsultationAssertionChallenge
    ) -> Data? {
        guard let message = assertionMessage(exactBody: exactBody, challenge: challenge) else { return nil }
        return Data(SHA256.hash(data: message))
    }

    /// Replica o frame do worker: para cada campo, UInt64 big-endian do tamanho
    /// seguido dos bytes. Não há JSON intermediário nem serialização implícita.
    private func assertionMessage(
        exactBody: Data,
        challenge: AssistConsultationAssertionChallenge
    ) -> Data? {
        guard challenge.isValid(for: challenge.binding, now: Date.distantPast) else { return nil }
        return Self.lengthPrefixedFrame([
            Data(AssistConsultationAttestationProtocol.version.utf8),
            Data(challenge.purpose.utf8),
            Data(challenge.binding.method.utf8),
            Data(challenge.binding.path.utf8),
            exactBody,
            Data(challenge.nonce.utf8),
            Data(challenge.timestampUnixMilliseconds.utf8)
        ])
    }

    private static func lengthPrefixedFrame(_ fields: [Data]) -> Data {
        var result = Data()
        result.reserveCapacity(fields.reduce(0) { $0 + 8 + $1.count })
        for field in fields {
            var length = UInt64(field.count).bigEndian
            withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
            result.append(field)
        }
        return result
    }

    fileprivate static func unixMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded(.down))
    }
}

public enum AssistConsultationAttestationError: Error, Equatable, Sendable {
    case invalidChallenge
    case invalidKeyID
    case emptyProof
}

private extension AssistConsultationRegistrationChallenge {
    func isValid(now: Date) -> Bool {
        protocolVersion == AssistConsultationAttestationProtocol.version
            && purpose == "registration"
            && nonce.isBase64URL(maximumLength: 256)
            && expiresAt > AssistConsultationAppAttestAuthorizer.unixMilliseconds(now)
    }
}

private extension AssistConsultationAssertionChallenge {
    func isValid(for expectedBinding: AssistConsultationAssertionBinding, now: Date) -> Bool {
        protocolVersion == AssistConsultationAttestationProtocol.version
            && purpose == "consultation_assertion"
            && binding == expectedBinding
            && binding.method == AssistConsultationAttestationProtocol.consultationMethod
            && binding.path == AssistConsultationAttestationProtocol.consultationPath
            && binding.requestSHA256.isBase64URL(exactLength: 43)
            && nonce.isBase64URL(maximumLength: 256)
            && timestampUnixMilliseconds.isPositiveDecimalTimestamp
            && (now == .distantPast || expiresAt > AssistConsultationAppAttestAuthorizer.unixMilliseconds(now))
    }
}

private extension String {
    var isPositiveDecimalTimestamp: Bool {
        guard !isEmpty, allSatisfy(\.isNumber), let value = Int64(self) else { return false }
        return value > 0
    }

    func isBase64URL(maximumLength: Int? = nil, exactLength: Int? = nil) -> Bool {
        guard !isEmpty,
              maximumLength.map({ count <= $0 }) ?? true,
              exactLength.map({ count == $0 }) ?? true else { return false }
        return unicodeScalars.allSatisfy { scalar in
            (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
                || (48...57).contains(scalar.value) || scalar == "-" || scalar == "_"
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
