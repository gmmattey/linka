import Foundation
import LinkaEntitlements

public enum LinkaSystemAction: String, Codable, CaseIterable, Hashable, Sendable {
    case startSpeedTest
    case openLatestMeasurement
    case openHistory
    case openPurchase
    case getLatestResult
    case measureNetworkSilently
}

public struct LinkaSystemActionResponse: Equatable, Sendable {
    public let action: LinkaSystemAction
    public let value: String?

    public init(
        action: LinkaSystemAction,
        value: String? = nil
    ) {
        self.action = action
        self.value = value
    }
}

public enum LinkaAppIntentExecutionError: Error, Equatable, Sendable {
    case notConfigured
    case mismatchedResponse(expected: LinkaSystemAction, actual: LinkaSystemAction)
    case missingValue(action: LinkaSystemAction)

    /// Usuário sem acesso à capacidade `.appleIntegrations` (Siri/Shortcuts/
    /// App Intents é um recurso Plus — ver `LinkaAppIntentExecutor.entitlementGated`).
    case notEntitled(action: LinkaSystemAction)
}

public struct LinkaAppIntentExecutor: Sendable {
    public typealias Handler = @Sendable (LinkaSystemAction) async throws -> LinkaSystemActionResponse

    private let handler: Handler

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    public func execute(_ action: LinkaSystemAction) async throws -> LinkaSystemActionResponse {
        let response = try await handler(action)

        guard response.action == action else {
            throw LinkaAppIntentExecutionError.mismatchedResponse(
                expected: action,
                actual: response.action
            )
        }

        if action == .getLatestResult {
            let value = response.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else {
                throw LinkaAppIntentExecutionError.missingValue(action: action)
            }
        }

        return response
    }

    public static let unconfigured = LinkaAppIntentExecutor { _ in
        throw LinkaAppIntentExecutionError.notConfigured
    }
}

public extension LinkaAppIntentExecutor {
    /// Envolve um executor real com uma checagem de entitlement, para que
    /// Siri/Shortcuts/App Intents consultem a mesma fonte de acesso
    /// (`LinkaEntitlementPolicy`) usada pelo resto do app, sem duplicar a
    /// regra aqui. Toda a superfície de App Intents é tratada como a
    /// capacidade `.appleIntegrations` — inclusive `startSpeedTest`, já que
    /// medir pelo app continua livre (`LinkaCapability.speedTest`), mas
    /// acioná-lo via Siri/Shortcuts/Widget é parte da integração Apple
    /// ofertada no Linka Plus.
    ///
    /// **Decisão do Luiz (2026-08-15)**: Widget/Siri/App Intents são
    /// exclusivos do Linka Plus, incluindo o disparo de `startSpeedTest`
    /// por essas superfícies. Usuário Free continua medindo pelo app
    /// (grátis por princípio, `AGENTS.md` §6), mas acionar via integração
    /// Apple exige assinatura. Gate uniforme atrás de `.appleIntegrations`.
    ///
    /// `snapshot` é síncrona porque o snapshot de produção
    /// (`StoreKitEntitlementProvider.snapshot`) já é um valor publicado
    /// disponível sem round-trip de rede.
    static func entitlementGated(
        wrapping executor: LinkaAppIntentExecutor,
        snapshot: @escaping @Sendable () -> LinkaEntitlementSnapshot
    ) -> LinkaAppIntentExecutor {
        LinkaAppIntentExecutor { action in
            let decision = LinkaEntitlementPolicy.decision(
                for: .appleIntegrations,
                snapshot: snapshot()
            )
            guard decision.isGranted else {
                throw LinkaAppIntentExecutionError.notEntitled(action: action)
            }
            return try await executor.execute(action)
        }
    }
}
