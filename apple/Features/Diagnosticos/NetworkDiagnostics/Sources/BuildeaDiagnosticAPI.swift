import Foundation
import NetworkCore

public struct BuildeaDiagnosticAPI: Sendable {
    public let configuration: NetworkDiagnosticsConfiguration
    public let httpClient: DiagnosticHTTPClient
    public let platformProvider: PlatformSignalProviding
    private let builder = NDSRequestBuilder()

    public init(
        configuration: NetworkDiagnosticsConfiguration,
        httpClient: DiagnosticHTTPClient = URLSessionDiagnosticHTTPClient(),
        platformProvider: PlatformSignalProviding = NoopPlatformSignalProvider()
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.platformProvider = platformProvider
    }

    public func evaluate(
        _ measurement: NetworkMeasurement,
        requestAI: Bool,
        locale: String? = nil,
        diagnosticContext: NDSRequest.DiagnosticContext? = nil,
        historical: NDSRequest.Historical? = nil
    ) async throws -> NDSResponse {
        guard configuration.transportAuth == .relay || configuration.bearerToken?.isEmpty == false else {
            throw NetworkDiagnosticsError.notConfigured
        }

        let hints = await platformProvider.currentHints()
        let payload = builder.buildRequest(
            current: measurement,
            platformHints: hints,
            appVersion: configuration.appVersion,
            platformIdentifier: configuration.platformIdentifier,
            requestAI: requestAI,
            locale: locale,
            diagnosticContext: diagnosticContext,
            historical: historical
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(payload)

        let endpoint = configuration.v2RulesEndpoint

        let (data, status) = try await httpClient.postJSON(
            url: endpoint,
            body: body,
            timeout: configuration.requestTimeout,
            bearerToken: configuration.transportAuth == .bearer ? configuration.bearerToken : nil
        )
        guard (200..<300).contains(status) else {
            if let errorEnvelope = try? JSONDecoder().decode(NDSErrorEnvelope.self, from: data) {
                throw NetworkDiagnosticsError.nds(
                    code: errorEnvelope.error.code,
                    message: errorEnvelope.error.message,
                    retryable: errorEnvelope.error.retryable,
                    requestID: errorEnvelope.requestID
                )
            }
            throw NetworkDiagnosticsError.httpStatus(status)
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(NDSResponse.self, from: data)
        } catch {
            throw NetworkDiagnosticsError.decoding(String(describing: error))
        }
    }
}
