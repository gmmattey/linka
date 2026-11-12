import AssistConsultation
import AssistConsultationTransport
import CryptoKit
import XCTest

final class AssistConsultationTransportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_547_200)

    func testConfigurationStartsDisabledAtTheFixedHTTPSConsultationEndpoint() throws {
        let configuration = try AssistConsultationTransportConfiguration()

        XCTAssertFalse(configuration.isEnabled)
        XCTAssertEqual(configuration.endpoint, AssistConsultationTransportConfiguration.fixedEndpoint)
        XCTAssertEqual(configuration.endpoint.scheme, "https")
        XCTAssertEqual(configuration.endpoint.path, "/v1/assist/consultations")
        XCTAssertNil(configuration.endpoint.query)
        XCTAssertNil(configuration.endpoint.fragment)
    }

    func testConfigurationRejectsAnyEndpointOtherThanTheFixedV4Route() throws {
        XCTAssertThrowsError(try AssistConsultationTransportConfiguration(
            endpoint: try XCTUnwrap(URL(string: "https://linka-assist-relay.buildealabs.workers.dev/v2/assist"))
        ))
        XCTAssertThrowsError(try AssistConsultationTransportConfiguration(
            endpoint: try XCTUnwrap(URL(string: "http://linka-assist-relay.buildealabs.workers.dev/v1/assist/consultations"))
        ))
    }

    func testInfoConfigurationDefaultsToDisabledAndRejectsDifferentDeclaredEndpoint() throws {
        let configuration = try AssistConsultationTransportConfiguration(infoDictionary: [:])
        XCTAssertFalse(configuration.isEnabled)

        XCTAssertThrowsError(try AssistConsultationTransportConfiguration(infoDictionary: [
            "LinkaAssistConsultationEnabled": "YES",
            "LinkaAssistConsultationEndpoint": "https://linka-assist-relay.buildealabs.workers.dev/v2/assist"
        ]))
        XCTAssertThrowsError(try AssistConsultationTransportConfiguration(infoDictionary: [
            "LinkaAssistConsultationEnabled": "YES"
        ]))
    }

    func testDisabledClientDoesNotCallInjectedTransport() async throws {
        let transport = RecordingTransport(response: nil)
        let client = AssistConsultationTransportClient(
            configuration: try AssistConsultationTransportConfiguration(),
            transport: transport
        )

        let outcome = await client.send(payload(), now: now)
        XCTAssertEqual(outcome, .unavailable(.disabled))
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 0)
    }

    func testClientSendsTheExactContractBytesToFixedRouteAndValidatesResponse() async throws {
        let requestPayload = payload()
        let responsePayload = validResponse(for: requestPayload)
        let responseData = try AssistConsultationContract.encodeResponse(responsePayload, for: requestPayload, now: now)
        let transport = RecordingTransport(response: AssistConsultationHTTPResponse(
            statusCode: 200,
            body: responseData,
            finalURL: AssistConsultationTransportConfiguration.fixedEndpoint
        ))
        let client = AssistConsultationTransportClient(
            configuration: try AssistConsultationTransportConfiguration(isEnabled: true),
            transport: transport
        )

        let outcome = await client.send(requestPayload, now: now)
        XCTAssertEqual(outcome, .response(responsePayload))

        let lastRequest = await transport.lastRequest()
        let sent = try XCTUnwrap(lastRequest)
        XCTAssertEqual(sent.url, AssistConsultationTransportConfiguration.fixedEndpoint)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.headers["Idempotency-Key"], requestPayload.requestID.value)
        XCTAssertEqual(sent.body, try AssistConsultationContract.encode(requestPayload, now: now))
    }

    func testClientRejectsRedirectAndAnUncorrelatedResponse() async throws {
        let requestPayload = payload()
        let valid = validResponse(for: requestPayload)
        let responseData = try AssistConsultationContract.encodeResponse(valid, for: requestPayload, now: now)
        let redirected = RecordingTransport(response: AssistConsultationHTTPResponse(
            statusCode: 200,
            body: responseData,
            finalURL: try XCTUnwrap(URL(string: "https://example.invalid/v1/assist/consultations"))
        ))
        let client = AssistConsultationTransportClient(
            configuration: try AssistConsultationTransportConfiguration(isEnabled: true),
            transport: redirected
        )
        let redirectOutcome = await client.send(requestPayload, now: now)
        XCTAssertEqual(redirectOutcome, .unavailable(.redirected))

        let unrelatedResponse = ConsultationResponse(
            requestID: ref("request-other"),
            transportSessionID: requestPayload.transportSessionID,
            turnID: requestPayload.turnID,
            revision: requestPayload.expectedRevision,
            outcome: valid.outcome
        )
        let unrelatedData = try JSONEncoder().encode(unrelatedResponse)
        let invalid = RecordingTransport(response: AssistConsultationHTTPResponse(
            statusCode: 200,
            body: unrelatedData,
            finalURL: AssistConsultationTransportConfiguration.fixedEndpoint
        ))
        let invalidClient = AssistConsultationTransportClient(
            configuration: try AssistConsultationTransportConfiguration(isEnabled: true),
            transport: invalid
        )
        let invalidOutcome = await invalidClient.send(requestPayload, now: now)
        XCTAssertEqual(invalidOutcome, .unavailable(.invalidResponse))
    }

    func testAppAttestRegistersOnceAndBindsAssertionToTheExactV4Bytes() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_791_547_200)
        let keyStore = RecordingKeyIDStore()
        let appAttest = RecordingAppAttest()
        let exchange = RecordingAttestationExchange(now: timestamp)
        let authorizer = AssistConsultationAppAttestAuthorizer(
            appAttest: appAttest,
            keyIDStore: keyStore,
            exchange: exchange
        )
        let body = Data(#"{"requestID":"request-001"}"#.utf8)

        let outcome = await authorizer.authorize(exactBody: body, now: timestamp)

        guard case let .authorized(proof) = outcome else { return XCTFail("Expected a V4 App Attest proof") }
        XCTAssertEqual(proof.keyID, "device-key-001")
        XCTAssertEqual(proof.nonce, "assertion_nonce-001")
        XCTAssertEqual(proof.timestampUnixMilliseconds, "1791547200000")
        XCTAssertEqual(proof.requestSHA256, Data(SHA256.hash(data: body)).base64URL)
        XCTAssertEqual(proof.assertion, Data("assertion".utf8).base64URL)

        let savedKeyID = try await keyStore.loadKeyID()
        XCTAssertEqual(savedKeyID, "device-key-001")
        let registrationProof = try await exchange.registrationProof()
        XCTAssertEqual(registrationProof?.keyID, "device-key-001")
        XCTAssertEqual(registrationProof?.nonce, "registration_nonce-001")
        XCTAssertEqual(registrationProof?.timestampUnixMilliseconds, "1791547200000")
        let registrationHash = try await appAttest.attestationHash()
        XCTAssertEqual(registrationHash, Data(SHA256.hash(data: Data("registration_nonce-001".utf8))))

        let binding = try await exchange.lastBinding()
        XCTAssertEqual(binding?.method, "POST")
        XCTAssertEqual(binding?.path, "/v1/assist/consultations")
        XCTAssertEqual(binding?.requestSHA256, Data(SHA256.hash(data: body)).base64URL)
        let assertionHash = try await appAttest.assertionHash()
        XCTAssertEqual(assertionHash, expectedAssertionHash(body: body, nonce: "assertion_nonce-001", timestamp: "1791547200000"))
    }

    func testAppAttestReusesStoredKeyWithoutASecondRegistration() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_791_547_200)
        let keyStore = RecordingKeyIDStore(keyID: "existing-key-001")
        let appAttest = RecordingAppAttest()
        let exchange = RecordingAttestationExchange(now: timestamp)
        let authorizer = AssistConsultationAppAttestAuthorizer(appAttest: appAttest, keyIDStore: keyStore, exchange: exchange)

        guard case .authorized = await authorizer.authorize(exactBody: Data("{}".utf8), now: timestamp) else {
            return XCTFail("Expected an assertion with the stored key")
        }
        let registrationProof = try await exchange.registrationProof()
        let generatedKeyCount = await appAttest.generatedKeyCount()
        let attestationCount = await appAttest.attestationCount()
        let assertionCount = await appAttest.assertionCount()
        XCTAssertNil(registrationProof)
        XCTAssertEqual(generatedKeyCount, 0)
        XCTAssertEqual(attestationCount, 0)
        XCTAssertEqual(assertionCount, 1)
    }

    func testAppAttestRejectsAChallengeThatDoesNotEchoExactV4BindingBeforeAssertion() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_791_547_200)
        let keyStore = RecordingKeyIDStore(keyID: "existing-key-001")
        let appAttest = RecordingAppAttest()
        let exchange = RecordingAttestationExchange(now: timestamp, mutatesAssertionBinding: true)
        let authorizer = AssistConsultationAppAttestAuthorizer(appAttest: appAttest, keyIDStore: keyStore, exchange: exchange)

        let outcome = await authorizer.authorize(exactBody: Data("{\"a\":1}".utf8), now: timestamp)
        let assertionCount = await appAttest.assertionCount()
        XCTAssertEqual(outcome, .unavailable)
        XCTAssertEqual(assertionCount, 0)
    }

    func testUnavailableAppAttestDoesNotTouchKeychainOrExchange() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_791_547_200)
        let keyStore = RecordingKeyIDStore()
        let appAttest = RecordingAppAttest(isSupported: false)
        let exchange = RecordingAttestationExchange(now: timestamp)
        let authorizer = AssistConsultationAppAttestAuthorizer(appAttest: appAttest, keyIDStore: keyStore, exchange: exchange)

        let outcome = await authorizer.authorize(exactBody: Data("{}".utf8), now: timestamp)
        let keyStoreLoadCount = await keyStore.loadCount()
        let registrationChallengeCount = await exchange.registrationChallengeCount()
        let assertionChallengeCount = await exchange.assertionChallengeCount()
        XCTAssertEqual(outcome, .unavailable)
        XCTAssertEqual(keyStoreLoadCount, 0)
        XCTAssertEqual(registrationChallengeCount, 0)
        XCTAssertEqual(assertionChallengeCount, 0)
    }

    /// Não tenta falar com o relay: esta é a prova de que uma instalação
    /// assinada, em hardware Apple real, consegue obter a atestação genuína.
    /// Simulador e macOS não implementam o serviço e devem continuar verdes
    /// por meio de skip explícito, nunca por uma atestação falsa.
    func testSystemAppAttestCreatesGenuineAttestationOnPhysicaliPhone() async throws {
        #if os(iOS)
        #if targetEnvironment(simulator)
        throw XCTSkip("App Attest só é comprovado em dispositivo físico.")
        #else
        let provider = AssistConsultationSystemAppAttestProvider()
        let supported = await provider.isSupported()
        try XCTSkipUnless(supported, "Este dispositivo não oferece App Attest.")

        let keyID = try await provider.generateKey()
        XCTAssertFalse(keyID.isEmpty)

        let challenge = Data(SHA256.hash(data: Data("linka-assist-v4-physical-attestation".utf8)))
        let attestation = try await provider.attestKey(keyID, clientDataHash: challenge)
        XCTAssertFalse(attestation.isEmpty)
        #endif
        #else
        throw XCTSkip("App Attest é um serviço exclusivo de iOS.")
        #endif
    }

    private func expectedAssertionHash(body: Data, nonce: String, timestamp: String) -> Data {
        let fields = [
            Data("linka.assist.consultation.app-attest/1".utf8),
            Data("consultation_assertion".utf8),
            Data("POST".utf8),
            Data("/v1/assist/consultations".utf8),
            body,
            Data(nonce.utf8),
            Data(timestamp.utf8)
        ]
        var frame = Data()
        for field in fields {
            var length = UInt64(field.count).bigEndian
            withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
            frame.append(field)
        }
        return Data(SHA256.hash(data: frame))
    }

    private func ref(_ value: String) -> PseudonymousReference { try! PseudonymousReference(value) }

    private func payload() -> ConsultationPayload {
        let consent = ConsentReceipt(ref: ref("consent-001"), state: .granted, scope: .question, recordedAt: now)
        let snapshot = ContextSnapshot(
            snapshotID: ref("snapshot-001"),
            revision: 1,
            intent: .openQuestion,
            consent: consent,
            createdAt: now
        )
        return ConsultationPayload(
            requestID: ref("request-001"),
            transportSessionID: ref("session-001"),
            turnID: ref("turn-001"),
            expectedRevision: 1,
            locale: "pt-BR",
            input: .userMessage("Como posso verificar a cobertura?"),
            contextSnapshot: snapshot,
            consentReceiptRef: consent.ref
        )
    }

    private func validResponse(for payload: ConsultationPayload) -> ConsultationResponse {
        ConsultationResponse(
            requestID: payload.requestID,
            transportSessionID: payload.transportSessionID,
            turnID: payload.turnID,
            revision: payload.expectedRevision,
            outcome: .error(ConsultationErrorPayload(
                code: .unavailable,
                message: "A consulta está indisponível agora.",
                recoverable: true,
                fallback: .retry
            ))
        )
    }
}

private actor RecordingTransport: AssistConsultationHTTPTransporting {
    private var requests: [AssistConsultationHTTPRequest] = []
    private let response: AssistConsultationHTTPResponse?

    init(response: AssistConsultationHTTPResponse?) {
        self.response = response
    }

    func perform(_ request: AssistConsultationHTTPRequest) async throws -> AssistConsultationHTTPResponse {
        requests.append(request)
        guard let response else { throw RecordingTransportError.unavailable }
        return response
    }

    func callCount() -> Int { requests.count }
    func lastRequest() -> AssistConsultationHTTPRequest? { requests.last }
}

private enum RecordingTransportError: Error { case unavailable }

private actor RecordingKeyIDStore: AssistConsultationAppAttestKeyIDStoring {
    private var storedKeyID: String?
    private var reads = 0

    init(keyID: String? = nil) {
        storedKeyID = keyID
    }

    func loadKeyID() -> String? {
        reads += 1
        return storedKeyID
    }

    func saveKeyID(_ keyID: String) {
        storedKeyID = keyID
    }

    func loadCount() -> Int { reads }
}

private actor RecordingAppAttest: AssistConsultationAppAttestProviding {
    private let supported: Bool
    private var generatedKeys = 0
    private var attestations: [Data] = []
    private var assertions: [Data] = []

    init(isSupported: Bool = true) {
        supported = isSupported
    }

    func isSupported() -> Bool { supported }

    func generateKey() -> String {
        generatedKeys += 1
        return "device-key-001"
    }

    func attestKey(_ keyID: String, clientDataHash: Data) -> Data {
        XCTAssertEqual(keyID, "device-key-001")
        attestations.append(clientDataHash)
        return Data("attestation".utf8)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) -> Data {
        XCTAssertFalse(keyID.isEmpty)
        assertions.append(clientDataHash)
        return Data("assertion".utf8)
    }

    func generatedKeyCount() -> Int { generatedKeys }
    func attestationCount() -> Int { attestations.count }
    func assertionCount() -> Int { assertions.count }
    func attestationHash() -> Data? { attestations.last }
    func assertionHash() -> Data? { assertions.last }
}

private actor RecordingAttestationExchange: AssistConsultationAttestationExchanging {
    private let now: Date
    private let mutatesAssertionBinding: Bool
    private var registrationChallenges = 0
    private var assertionChallenges = 0
    private var registeredProof: AssistConsultationRegistrationProof?
    private var binding: AssistConsultationAssertionBinding?

    init(now: Date, mutatesAssertionBinding: Bool = false) {
        self.now = now
        self.mutatesAssertionBinding = mutatesAssertionBinding
    }

    func requestRegistrationChallenge() -> AssistConsultationRegistrationChallenge {
        registrationChallenges += 1
        return .init(
            protocolVersion: "linka.assist.consultation.app-attest/1",
            purpose: "registration",
            nonce: "registration_nonce-001",
            expiresAt: Int64(now.timeIntervalSince1970 * 1_000) + 60_000
        )
    }

    func register(_ proof: AssistConsultationRegistrationProof) {
        registeredProof = proof
    }

    func requestAssertionChallenge(
        for binding: AssistConsultationAssertionBinding,
        keyID: String
    ) -> AssistConsultationAssertionChallenge {
        XCTAssertFalse(keyID.isEmpty)
        assertionChallenges += 1
        self.binding = binding
        let acceptedBinding: AssistConsultationAssertionBinding
        if mutatesAssertionBinding {
            acceptedBinding = .init(exactBody: Data("tampered".utf8))
        } else {
            acceptedBinding = binding
        }
        return .init(
            protocolVersion: "linka.assist.consultation.app-attest/1",
            purpose: "consultation_assertion",
            binding: acceptedBinding,
            nonce: "assertion_nonce-001",
            timestampUnixMilliseconds: "1791547200000",
            expiresAt: Int64(now.timeIntervalSince1970 * 1_000) + 60_000
        )
    }

    func registrationProof() -> AssistConsultationRegistrationProof? { registeredProof }
    func lastBinding() -> AssistConsultationAssertionBinding? { binding }
    func registrationChallengeCount() -> Int { registrationChallenges }
    func assertionChallengeCount() -> Int { assertionChallenges }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
