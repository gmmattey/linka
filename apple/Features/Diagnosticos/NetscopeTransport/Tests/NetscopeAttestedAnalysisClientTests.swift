import Foundation
import NetscopeEvidence
@testable import NetscopeTransport
import XCTest

final class NetscopeAttestedAnalysisClientTests: XCTestCase {
    func testServiceConfigurationAcceptsOnlyHTTPSOriginWithoutPrefix() throws {
        XCTAssertNoThrow(try NetscopeServiceConfiguration(baseURL: URL(string: "https://configured.example")!))
        XCTAssertNoThrow(try NetscopeServiceConfiguration(baseURL: URL(string: "https://configured.example:8443/")!))

        for value in [
            "http://configured.example",
            "https://configured.example/prefix",
            "https://configured.example/v1/",
            "https://configured.example?query=value",
            "https://configured.example#fragment",
            "https://user:password@configured.example"
        ] {
            XCTAssertThrowsError(try NetscopeServiceConfiguration(baseURL: try XCTUnwrap(URL(string: value)))) {
                XCTAssertEqual($0 as? NetscopeServiceConfigurationError, .invalidBaseURL)
            }
        }
    }

    #if os(macOS)
    func testSystemAvailabilityDoesNotOfferMacOSFallback() {
        XCTAssertFalse(NetscopeSystemAppAttestAvailability.isSupported)
    }
    #endif

    func testUnsupportedPlatformsFailBeforeChallengeOrHTTP() async throws {
        for platform in [NetscopeClientPlatform.simulator, .macOS, .unsupported] {
            let attestation = RecordingAttestation()
            let transport = RecordingTransport(response: unavailableHTTPResponse)
            let outcome = await client(platform: platform, attestation: attestation, transport: transport).analyze(
                input: input,
                locale: "pt-BR",
                app: app,
                configuration: configuration
            )

            XCTAssertEqual(outcome, .unavailable)
            let calls = await attestation.calls()
            let requestCount = await transport.requestCount()
            XCTAssertEqual(calls, [])
            XCTAssertEqual(requestCount, 0)
        }
    }

    func testPhysicalIOSAndIPadRunChallengeRegisterAssertionAndOneRequestInOrder() async throws {
        for platform in [NetscopeClientPlatform.iPhonePhysical, .iPadPhysical] {
            let attestation = RecordingAttestation()
            let transport = RecordingTransport(response: completedHTTPResponse)

            let outcome = await client(platform: platform, attestation: attestation, transport: transport).analyze(
                input: input,
                locale: "pt-BR",
                app: app,
                configuration: configuration
            )

            guard case .response = outcome else {
                return XCTFail("Expected a validated response")
            }
            let calls = await attestation.calls()
            let requestCount = await transport.requestCount()
            let lastRequest = await transport.lastRequest()
            let lastBinding = await attestation.lastBinding()
            let lastAssertionChallenge = await attestation.lastAssertionChallenge()
            XCTAssertEqual(calls, [.registrationChallenge, .register, .analysisChallenge, .assertion])
            XCTAssertEqual(requestCount, 1)
            let request = try XCTUnwrap(lastRequest)
            let binding = try XCTUnwrap(lastBinding)
            let assertionChallenge = try XCTUnwrap(lastAssertionChallenge)
            XCTAssertEqual(request.method, "POST")
            XCTAssertEqual(request.url, URL(string: "https://configured.example/v1/linka/analysis"))
            XCTAssertEqual(request.nonce, "single-use-nonce")
            XCTAssertEqual(request.timestampUnixMilliseconds, 1_700_000_000_000)
            XCTAssertTrue(request.signedRequestSHA256.isEmpty == false)
            XCTAssertEqual(binding.method, "POST")
            XCTAssertEqual(binding.path, "/v1/linka/analysis")
            XCTAssertTrue(binding.binds(exactBody: request.body))
            XCTAssertEqual(assertionChallenge.nonce, request.nonce)
            XCTAssertEqual(assertionChallenge.timestampUnixMilliseconds, request.timestampUnixMilliseconds)
        }
    }

    func testBodyNonceOrTimestampMutationInvalidatesAssertionBinding() {
        let challenge = NetscopeAnalysisAssertionChallenge(nonce: "nonce", timestampUnixMilliseconds: 1_700_000_000_000)
        let body = Data("{\"a\":1}".utf8)
        let binding = NetscopeAnalysisAssertionBinding(exactBody: body)
        let original = NetscopeAttestationAssertionInput(binding: binding, exactBody: body, challenge: challenge)
        let mutatedBody = NetscopeAttestationAssertionInput(binding: binding, exactBody: Data("{\"a\":2}".utf8), challenge: challenge)
        let mutatedNonce = NetscopeAttestationAssertionInput(
            binding: binding, exactBody: body,
            challenge: .init(nonce: "other-nonce", timestampUnixMilliseconds: challenge.timestampUnixMilliseconds)
        )
        let mutatedTimestamp = NetscopeAttestationAssertionInput(
            binding: binding, exactBody: body,
            challenge: .init(nonce: challenge.nonce, timestampUnixMilliseconds: challenge.timestampUnixMilliseconds + 1)
        )

        XCTAssertNotEqual(original.signedRequestSHA256, mutatedBody.signedRequestSHA256)
        XCTAssertNotEqual(original.signedRequestSHA256, mutatedNonce.signedRequestSHA256)
        XCTAssertNotEqual(original.signedRequestSHA256, mutatedTimestamp.signedRequestSHA256)
        XCTAssertEqual(original.binding.method, "POST")
        XCTAssertEqual(original.binding.path, "/v1/linka/analysis")
        XCTAssertTrue(original.binds(
            method: "POST", path: "/v1/linka/analysis", exactBody: body,
            nonce: challenge.nonce, timestampUnixMilliseconds: challenge.timestampUnixMilliseconds
        ))
        XCTAssertFalse(original.binds(
            method: "POST", path: "/v1/linka/analysis", exactBody: Data("{\"a\":2}".utf8),
            nonce: challenge.nonce, timestampUnixMilliseconds: challenge.timestampUnixMilliseconds
        ))
        XCTAssertFalse(original.binds(
            method: "POST", path: "/v1/linka/analysis", exactBody: body,
            nonce: "other-nonce", timestampUnixMilliseconds: challenge.timestampUnixMilliseconds
        ))
        XCTAssertFalse(original.binds(
            method: "POST", path: "/v1/linka/analysis", exactBody: body,
            nonce: challenge.nonce, timestampUnixMilliseconds: challenge.timestampUnixMilliseconds + 1
        ))
    }

    func testAttestationFailureDoesNotReachHTTP() async throws {
        let attestation = RecordingAttestation(failure: .assertion)
        let transport = RecordingTransport(response: completedHTTPResponse)

        let outcome = await client(attestation: attestation, transport: transport).analyze(
            input: input, locale: "pt-BR", app: app, configuration: configuration
        )

        XCTAssertEqual(outcome, .unavailable)
        let requestCount = await transport.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    func testCancellationAndTimeoutBecomeUnavailableWithoutRetry() async throws {
        for error in [TransportFailure.cancelled, .timedOut] {
            let attestation = RecordingAttestation()
            let transport = RecordingTransport(failure: error)
            let outcome = await client(attestation: attestation, transport: transport).analyze(
                input: input, locale: "pt-BR", app: app, configuration: configuration
            )

            XCTAssertEqual(outcome, .unavailable)
            let requestCount = await transport.requestCount()
            XCTAssertEqual(requestCount, 1)
        }
    }

    func testRedirectHTTPFailureAndMalformedJSONBecomeUnavailable() async throws {
        let redirect = NetscopeHTTPResponse(statusCode: 200, body: completedResponse, finalURL: URL(string: "https://other.example/v1/linka/analysis")!)
        let unauthorized = NetscopeHTTPResponse(statusCode: 401, body: Data(), finalURL: URL(string: "https://configured.example/v1/linka/analysis")!)
        let malformed = NetscopeHTTPResponse(statusCode: 200, body: Data("not-json".utf8), finalURL: URL(string: "https://configured.example/v1/linka/analysis")!)

        for response in [redirect, unauthorized, malformed] {
            let outcome = await client(
                attestation: RecordingAttestation(),
                transport: RecordingTransport(response: response)
            ).analyze(input: input, locale: "pt-BR", app: app, configuration: configuration)
            XCTAssertEqual(outcome, .unavailable)
        }
    }

    private var configuration: NetscopeServiceConfiguration {
        try! NetscopeServiceConfiguration(baseURL: URL(string: "https://configured.example")!)
    }

    private var app: NetscopeV1Codec.AppDescriptor {
        .init(version: "1.0", platform: .ios)
    }

    private var input: NetscopeLocalAnalysisInput {
        .init(
            observedEvidence: .init(
                downloadMbps: 100,
                uploadMbps: 20,
                latencyMs: 12,
                jitterMs: 1,
                packetLossPercent: nil,
                connectionKind: .wifi,
                wifiDetails: nil
            ),
            declaredContext: .init(objective: .gaming)
        )
    }

    private var completedResponse: Data {
        Data("""
        {"schema_version":"1.0.0","request_id":"test","status":"completed","declared_context":{"objective":"gaming"},"assessment":{"title":"Ok","summary":"Ok","confidence":"low"},"evidence_used":[{"metric":"latency_ms","value":12,"source":"system_observed"}],"limitations":["Partial reading"]}
        """.utf8)
    }

    private var completedHTTPResponse: NetscopeHTTPResponse {
        .init(statusCode: 200, body: completedResponse, finalURL: URL(string: "https://configured.example/v1/linka/analysis")!)
    }

    private var unavailableHTTPResponse: NetscopeHTTPResponse {
        .init(statusCode: 503, body: Data(), finalURL: URL(string: "https://configured.example/v1/linka/analysis")!)
    }

    private func client(
        platform: NetscopeClientPlatform = .iPhonePhysical,
        attestation: RecordingAttestation,
        transport: RecordingTransport
    ) -> NetscopeAttestedAnalysisClient {
        .init(platform: platform, attestation: attestation, transport: transport)
    }
}

private actor RecordingAttestation: NetscopeAttestationProviding {
    enum Call: Equatable { case registrationChallenge, register, analysisChallenge, assertion }

    private let failure: FailurePoint?
    private var recordedCalls: [Call] = []
    private var recordedBinding: NetscopeAnalysisAssertionBinding?
    private var recordedAssertionChallenge: NetscopeAnalysisAssertionChallenge?

    init(failure: FailurePoint? = nil) {
        self.failure = failure
    }

    func requestRegistrationChallenge() throws -> NetscopeRegistrationChallenge {
        recordedCalls.append(.registrationChallenge)
        if failure == .registrationChallenge { throw TransportFailure.timedOut }
        return .init(value: Data("registration-challenge".utf8))
    }

    func registerIfNeeded(for challenge: NetscopeRegistrationChallenge) throws {
        recordedCalls.append(.register)
        if failure == .register { throw TransportFailure.timedOut }
    }

    func requestAnalysisAssertionChallenge(for binding: NetscopeAnalysisAssertionBinding) throws -> NetscopeAnalysisAssertionChallenge {
        recordedCalls.append(.analysisChallenge)
        recordedBinding = binding
        if failure == .analysisChallenge { throw TransportFailure.timedOut }
        return .init(nonce: "single-use-nonce", timestampUnixMilliseconds: 1_700_000_000_000)
    }

    func makeAssertion(
        for input: NetscopeAttestationAssertionInput,
        using challenge: NetscopeAnalysisAssertionChallenge
    ) throws -> NetscopeAttestationProof {
        recordedCalls.append(.assertion)
        if failure == .assertion { throw TransportFailure.timedOut }
        recordedAssertionChallenge = challenge
        return .init(keyID: "ephemeral-key-id", assertion: Data("proof".utf8))
    }

    func calls() -> [Call] { recordedCalls }
    func lastBinding() -> NetscopeAnalysisAssertionBinding? { recordedBinding }
    func lastAssertionChallenge() -> NetscopeAnalysisAssertionChallenge? { recordedAssertionChallenge }
}

private actor RecordingTransport: NetscopeHTTPTransporting {
    private let response: NetscopeHTTPResponse?
    private let failure: Error?
    private var requests: [NetscopeAuthenticatedHTTPRequest] = []

    init(response: NetscopeHTTPResponse) {
        self.response = response
        failure = nil
    }

    init(failure: Error) {
        response = nil
        self.failure = failure
    }

    func perform(_ request: NetscopeAuthenticatedHTTPRequest) throws -> NetscopeHTTPResponse {
        requests.append(request)
        if let failure { throw failure }
        return response!
    }

    func requestCount() -> Int { requests.count }
    func lastRequest() -> NetscopeAuthenticatedHTTPRequest? { requests.last }
}

private enum FailurePoint { case registrationChallenge, register, analysisChallenge, assertion }
private enum TransportFailure: Error { case cancelled, timedOut }
