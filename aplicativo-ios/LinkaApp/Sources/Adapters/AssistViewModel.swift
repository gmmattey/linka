import Foundation
import NetworkAssist
import NetworkCore
import NetworkInsights

@MainActor
final class AssistViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case success(DiagnosticData)
        case error(String)
    }

    struct DiagnosticData: Equatable {
        let headerStatus: String
        let title: String
        let summary: String
        let recommendation: NetworkAssistRecommendation?
        let dimensions: [NetworkAssistDimension]
        let fallbackText: String?
        let aiAttribution: String?
    }

    @Published private(set) var state: State = .idle
    private let assistProvider: any NetworkAssistProviding
    private let languageTag: String

    init(
        assistProvider: any NetworkAssistProviding,
        languageTag: String = LinkaLanguagePreference.currentLanguageTag
    ) {
        self.assistProvider = assistProvider
        self.languageTag = languageTag
    }

    func load(
        currentMeasurement: NetworkMeasurement?,
        recentMeasurements: [NetworkMeasurement] = [],
        usageContext: String? = nil,
        failureSignal: NetworkAssistFailureSignal?,
        objective: String? = nil,
        subcategory: String? = nil,
        reportedProblem: String? = nil
    ) async {
        guard case .idle = state else { return }

        guard let current = currentMeasurement else {
            state = .error(LinkaCopy.value("assist.noMeasurement"))
            return
        }

        state = .loading

        let context = Self.makeContext(
            currentMeasurement: current,
            recentMeasurements: recentMeasurements,
            usageContext: usageContext,
            objective: objective,
            subcategory: subcategory,
            reportedProblem: reportedProblem,
            locale: languageTag
        )

        do {
            var finalResponse: NetworkAssistResponse?
            
            for try await event in assistProvider.streamAnswer(context) {
                if case .completed(let response) = event {
                    finalResponse = response
                }
            }
            
            if let response = finalResponse {
                guard response.disposition == .answered else {
                    state = .error(Self.message(for: response.disposition))
                    return
                }

                if let title = response.title, let summary = response.summary {
                    let data = DiagnosticData(
                        headerStatus: response.headerStatus ?? LinkaCopy.value("assist.completed"),
                        title: title,
                        summary: summary,
                        recommendation: response.recommendation,
                        dimensions: response.dimensions ?? [],
                        fallbackText: nil,
                        aiAttribution: response.aiAttribution
                    )
                    state = .success(data)
                } else {
                    let data = DiagnosticData(
                        headerStatus: "Assist",
                        title: LinkaCopy.value("assist.conclusion"),
                        summary: response.text,
                        recommendation: response.recommendation,
                        dimensions: response.dimensions ?? [],
                        fallbackText: response.longText,
                        aiAttribution: response.aiAttribution
                    )
                    state = .success(data)
                }
            } else {
                state = .error(LinkaCopy.value("assist.empty"))
            }
        } catch {
            let errorText: String
            switch error {
            case NetworkAssistError.notConfigured:
                errorText = LinkaCopy.value("assist.notConfigured")
            case NetworkAssistError.notEntitled:
                errorText = LinkaCopy.value("assist.notEntitled")
            default:
                #if DEBUG
                errorText = "Erro (\(error)): \(error.localizedDescription)"
                #else
                errorText = LinkaCopy.value("assist.error")
                #endif
            }
            state = .error(errorText)
        }
    }

    func retry(
        currentMeasurement: NetworkMeasurement?,
        recentMeasurements: [NetworkMeasurement] = [],
        usageContext: String? = nil,
        failureSignal: NetworkAssistFailureSignal?,
        objective: String? = nil,
        subcategory: String? = nil,
        reportedProblem: String? = nil
    ) async {
        guard case .error = state else { return }
        state = .idle
        await load(
            currentMeasurement: currentMeasurement,
            recentMeasurements: recentMeasurements,
            usageContext: usageContext,
            failureSignal: failureSignal,
            objective: objective,
            subcategory: subcategory,
            reportedProblem: reportedProblem
        )
    }

    /// Monta somente o contexto que a tela realmente possui. Histórico é
    /// limitado ao contrato do Assist, e uma finalidade de uso só passa se
    /// tiver sido informada por uma superfície que a coletou.
    static func makeContext(
        currentMeasurement: NetworkMeasurement,
        recentMeasurements: [NetworkMeasurement],
        usageContext: String? = nil,
        objective: String? = nil,
        subcategory: String? = nil,
        reportedProblem: String? = nil,
        locale: String = LinkaLanguagePreference.currentLanguageTag
    ) -> NetworkAssistContext {
        // O Assist é uma leitura do que está acontecendo agora. Histórico é
        // uma superfície própria do produto e não entra como evidência nem
        // como contexto silencioso desta jornada.
        let recent: [NetworkMeasurement] = []

        let currentEvidence = NetworkAssistEvidence(
            id: NetworkAssistRequest.currentMeasurementEvidenceID(currentMeasurement.id),
            kind: .metric,
            metricKey: "measurement",
            sourceMeasurementIDs: [currentMeasurement.id]
        )
        let recentEvidence = recent.map { measurement in
            NetworkAssistEvidence(
                id: NetworkAssistRequest.recentMeasurementEvidenceID(measurement.id),
                kind: .metric,
                metricKey: "measurement",
                sourceMeasurementIDs: [measurement.id]
            )
        }

        var allEvidence = [currentEvidence] + recentEvidence
        
        let responsivenessResult = LoadResponsivenessEvaluator.evaluateForConsumer(currentMeasurement)
        if responsivenessResult.category != .notAssessed {
            allEvidence.append(NetworkAssistEvidence(
                id: "responsiveness:\(currentMeasurement.id.uuidString.lowercased())",
                kind: .statistic,
                metricKey: "loadResponsivenessCategory",
                direction: responsivenessResult.category.rawValue,
                sourceMeasurementIDs: [currentMeasurement.id]
            ))
            if let downloadDelta = responsivenessResult.downloadComparison.absoluteDelta {
                allEvidence.append(NetworkAssistEvidence(
                    id: "responsiveness-dl-delta:\(currentMeasurement.id.uuidString.lowercased())",
                    kind: .comparison,
                    metricKey: "loadedLatencyMsDelta",
                    value: downloadDelta,
                    unit: "ms",
                    sourceMeasurementIDs: [currentMeasurement.id]
                ))
            }
            if let uploadDelta = responsivenessResult.uploadComparison.absoluteDelta {
                allEvidence.append(NetworkAssistEvidence(
                    id: "responsiveness-ul-delta:\(currentMeasurement.id.uuidString.lowercased())",
                    kind: .comparison,
                    metricKey: "loadedLatencyUploadMsDelta",
                    value: uploadDelta,
                    unit: "ms",
                    sourceMeasurementIDs: [currentMeasurement.id]
                ))
            }
        }

        // Evidência local aditiva: o transporte NDS continua recebendo só a
        // medição canônica até que o Worker aceite um contrato versionado.
        if let probes = currentMeasurement.packetProbeEvidence {
            allEvidence.append(NetworkAssistEvidence(
                id: "stability-loss:\(currentMeasurement.id.uuidString.lowercased())",
                kind: .statistic,
                metricKey: "packetProbeLossPercent",
                value: probes.packetLossPercent,
                unit: "%",
                direction: probes.expandedAfterInitialWindow ? "expanded" : "initial",
                sourceMeasurementIDs: [currentMeasurement.id]
            ))
        }
        if let reference = currentMeasurement.regionalGameReference {
            allEvidence.append(NetworkAssistEvidence(
                id: "regional-game-reference:\(currentMeasurement.id.uuidString.lowercased())",
                kind: .statistic,
                metricKey: "regionalGameReferenceP50Ms",
                value: reference.p50LatencyMs,
                unit: "ms",
                direction: reference.status.rawValue,
                sourceMeasurementIDs: [currentMeasurement.id]
            ))
        }

        return NetworkAssistContext(
            question: LinkaCopy.value("assist.defaultQuestion"),
            currentMeasurement: currentMeasurement,
            recentMeasurements: Array(recent),
            evidence: allEvidence,
            usageContext: usageContext?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            locale: locale,
            objective: objective,
            subcategory: subcategory,
            reportedProblem: reportedProblem?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    private static func message(for disposition: NetworkAssistDisposition) -> String {
        switch disposition {
        case .insufficientEvidence:
            return LinkaCopy.value("assist.insufficient")
        case .requiresDiagnosis:
            return LinkaCopy.value("assist.requiresDiagnosis")
        case .unsupported:
            return LinkaCopy.value("assist.unsupported")
        case .answered:
            return ""
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
