import Foundation
import NetworkCore

// MARK: - Status de Entrega do Plano Residencial

/// Classificação do cumprimento da velocidade nominal contratada.
public enum DeliveryStatus: String, Codable, CaseIterable, Sendable {
    /// Entrega acima do contratado (>= 105% por padrão)
    case exceeding
    /// Cumpre a meta do plano (80% ..< 105% por padrão)
    case meetingPlan
    /// Cumpre parcialmente o plano (50% ..< 80% por padrão)
    case partiallyMeeting
    /// Entrega crítica abaixo do plano (< 50% por padrão)
    case belowPlan
}

// MARK: - Avaliação de Métrica Individual do Plano

/// Estado de avaliação para uma direção de velocidade (download ou upload).
public enum PlanMetricEvaluation: Codable, Equatable, Sendable {
    /// Velocidade avaliada com sucesso contra o plano nominal.
    case evaluated(PlanSpeedDelivery)
    /// Sem dados elegíveis disponíveis para esta direção.
    case noData
    /// Direção não configurada no plano contratado (ex.: plano sem upload declarado).
    case notConfigured

    public var delivery: PlanSpeedDelivery? {
        if case .evaluated(let delivery) = self { return delivery }
        return nil
    }

    public var isEvaluated: Bool {
        if case .evaluated = self { return true }
        return false
    }

    public var isNoData: Bool { self == .noData }
    public var isNotConfigured: Bool { self == .notConfigured }

    private enum CodingKeys: String, CodingKey {
        case kind
        case delivery
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "evaluated":
            let delivery = try container.decode(PlanSpeedDelivery.self, forKey: .delivery)
            self = .evaluated(delivery)
        case "noData":
            self = .noData
        case "notConfigured":
            self = .notConfigured
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Tipo desconhecido de PlanMetricEvaluation: \(kind)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .evaluated(let delivery):
            try container.encode("evaluated", forKey: .kind)
            try container.encode(delivery, forKey: .delivery)
        case .noData:
            try container.encode("noData", forKey: .kind)
        case .notConfigured:
            try container.encode("notConfigured", forKey: .kind)
        }
    }
}

// MARK: - Entrega Pontual de Velocidade

/// Detalhe da entrega de velocidade comparada à nominal em uma única medição ou agregado.
public struct PlanSpeedDelivery: Codable, Equatable, Sendable {
    public let nominalMbps: Double
    public let measuredMbps: Double
    public let deliveredRatio: Double
    public let deliveredPercent: Double
    public let deltaMbps: Double
    public let status: DeliveryStatus

    public init(
        nominalMbps: Double,
        measuredMbps: Double,
        configuration: ResidentialPlanEvaluationConfiguration = .default
    ) {
        self.nominalMbps = nominalMbps
        self.measuredMbps = measuredMbps
        let ratio = nominalMbps > 0 ? (measuredMbps / nominalMbps) : 0
        self.deliveredRatio = ratio
        self.deliveredPercent = ratio * 100.0
        self.deltaMbps = measuredMbps - nominalMbps
        self.status = configuration.status(forDeliveredPercent: ratio * 100.0)
    }

    public init(
        nominalMbps: Double,
        measuredMbps: Double,
        deliveredRatio: Double,
        deliveredPercent: Double,
        deltaMbps: Double,
        status: DeliveryStatus
    ) {
        self.nominalMbps = nominalMbps
        self.measuredMbps = measuredMbps
        self.deliveredRatio = deliveredRatio
        self.deliveredPercent = deliveredPercent
        self.deltaMbps = deltaMbps
        self.status = status
    }
}

// MARK: - Agregado Estatístico de Entrega do Plano

/// Síntese estatística de entrega de velocidade ao longo de uma amostra de medições elegíveis.
public struct PlanMetricAggregateDelivery: Codable, Equatable, Sendable {
    public let nominalMbps: Double
    public let sampleCount: Int
    public let averageMbps: Double
    public let medianMbps: Double
    public let peakMbps: Double
    public let averageDeliveredPercent: Double
    public let medianDeliveredPercent: Double
    public let peakDeliveredPercent: Double
    public let minimumDeliveredPercent: Double
    public let maximumDeliveredPercent: Double
    public let standardDeviationMbps: Double
    public let status: DeliveryStatus

    public init(
        nominalMbps: Double,
        sampleCount: Int,
        averageMbps: Double,
        medianMbps: Double,
        peakMbps: Double,
        averageDeliveredPercent: Double,
        medianDeliveredPercent: Double,
        peakDeliveredPercent: Double,
        minimumDeliveredPercent: Double,
        maximumDeliveredPercent: Double,
        standardDeviationMbps: Double,
        status: DeliveryStatus
    ) {
        self.nominalMbps = nominalMbps
        self.sampleCount = sampleCount
        self.averageMbps = averageMbps
        self.medianMbps = medianMbps
        self.peakMbps = peakMbps
        self.averageDeliveredPercent = averageDeliveredPercent
        self.medianDeliveredPercent = medianDeliveredPercent
        self.peakDeliveredPercent = peakDeliveredPercent
        self.minimumDeliveredPercent = minimumDeliveredPercent
        self.maximumDeliveredPercent = maximumDeliveredPercent
        self.standardDeviationMbps = standardDeviationMbps
        self.status = status
    }

    public init?(
        nominalMbps: Double,
        samples: [Double],
        configuration: ResidentialPlanEvaluationConfiguration = .default
    ) {
        guard !samples.isEmpty, nominalMbps > 0 else {
            return nil
        }
        self.nominalMbps = nominalMbps
        self.sampleCount = samples.count

        let sorted = samples.sorted()
        let count = sorted.count
        let sum = sorted.reduce(0.0, +)
        let average = sum / Double(count)

        let median: Double
        if count.isMultiple(of: 2) {
            median = (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        } else {
            median = sorted[count / 2]
        }

        let peak = sorted.last ?? 0.0
        let minimum = sorted.first ?? 0.0

        let variance = sorted.reduce(0.0) { partial, value in
            let difference = value - average
            return partial + difference * difference
        } / Double(count)
        let standardDeviation = sqrt(variance)

        let avgDelivered = (average / nominalMbps) * 100.0
        let medDelivered = (median / nominalMbps) * 100.0
        let peakDelivered = (peak / nominalMbps) * 100.0
        let minDelivered = (minimum / nominalMbps) * 100.0

        self.averageMbps = average
        self.medianMbps = median
        self.peakMbps = peak
        self.averageDeliveredPercent = avgDelivered
        self.medianDeliveredPercent = medDelivered
        self.peakDeliveredPercent = peakDelivered
        self.minimumDeliveredPercent = minDelivered
        self.maximumDeliveredPercent = peakDelivered
        self.standardDeviationMbps = standardDeviation
        self.status = configuration.status(forDeliveredPercent: avgDelivered)
    }
}

// MARK: - Avaliação Agregada do Plano Residencial

/// Resultado consolidado da avaliação de um plano residencial sobre um conjunto de medições.
public struct ResidentialPlanAggregateEvaluation: Codable, Equatable, Sendable {
    public let planID: UUID
    public let evaluatedAt: Date
    public let totalMeasurementsProvided: Int
    public let eligibleMeasurementsCount: Int
    public let excludedIneligibleCount: Int
    public let excludedOutOfWindowCount: Int
    public let downloadEvaluation: PlanMetricEvaluation
    public let uploadEvaluation: PlanMetricEvaluation
    public let downloadAggregate: PlanMetricAggregateDelivery?
    public let uploadAggregate: PlanMetricAggregateDelivery?
    public let isSampleSufficient: Bool

    public init(
        planID: UUID,
        evaluatedAt: Date = Date(),
        totalMeasurementsProvided: Int,
        eligibleMeasurementsCount: Int,
        excludedIneligibleCount: Int,
        excludedOutOfWindowCount: Int,
        downloadEvaluation: PlanMetricEvaluation,
        uploadEvaluation: PlanMetricEvaluation,
        downloadAggregate: PlanMetricAggregateDelivery?,
        uploadAggregate: PlanMetricAggregateDelivery?,
        isSampleSufficient: Bool
    ) {
        self.planID = planID
        self.evaluatedAt = evaluatedAt
        self.totalMeasurementsProvided = totalMeasurementsProvided
        self.eligibleMeasurementsCount = eligibleMeasurementsCount
        self.excludedIneligibleCount = excludedIneligibleCount
        self.excludedOutOfWindowCount = excludedOutOfWindowCount
        self.downloadEvaluation = downloadEvaluation
        self.uploadEvaluation = uploadEvaluation
        self.downloadAggregate = downloadAggregate
        self.uploadAggregate = uploadAggregate
        self.isSampleSufficient = isSampleSufficient
    }
}

// MARK: - Avaliação Pontual de Medição Única

/// Avaliação pontual de uma única medição contra o plano residencial ativo.
public struct SingleMeasurementPlanEvaluation: Codable, Equatable, Sendable {
    public let planID: UUID
    public let measurementID: UUID
    public let measuredAt: Date
    public let eligibility: ResidentialPlanEligibility
    public let isWithinEffectiveWindow: Bool
    public let download: PlanMetricEvaluation
    public let upload: PlanMetricEvaluation

    public init(
        planID: UUID,
        measurementID: UUID,
        measuredAt: Date,
        eligibility: ResidentialPlanEligibility,
        isWithinEffectiveWindow: Bool,
        download: PlanMetricEvaluation,
        upload: PlanMetricEvaluation
    ) {
        self.planID = planID
        self.measurementID = measurementID
        self.measuredAt = measuredAt
        self.eligibility = eligibility
        self.isWithinEffectiveWindow = isWithinEffectiveWindow
        self.download = download
        self.upload = upload
    }
}

// MARK: - Conformidade Codable de ResidentialPlanEligibility

extension ResidentialPlanEligibility: Codable {
    private enum CodingKeys: String, CodingKey {
        case status
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)
        if status == "eligible" {
            self = .eligible
        } else {
            let reason = try container.decode(Reason.self, forKey: .reason)
            self = .ineligible(reason)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .eligible:
            try container.encode("eligible", forKey: .status)
        case .ineligible(let reason):
            try container.encode("ineligible", forKey: .status)
            try container.encode(reason, forKey: .reason)
        }
    }
}

// MARK: - Configuração de Avaliação do Plano

/// Parâmetros e limiares customizáveis para classificação de entrega de plano.
public struct ResidentialPlanEvaluationConfiguration: Codable, Equatable, Sendable {
    public var meetingThresholdPercent: Double
    public var exceedingThresholdPercent: Double
    public var partiallyMeetingThresholdPercent: Double
    public var minimumSamplesForConfidence: Int

    public init(
        meetingThresholdPercent: Double = 80.0,
        exceedingThresholdPercent: Double = 105.0,
        partiallyMeetingThresholdPercent: Double = 50.0,
        minimumSamplesForConfidence: Int = 3
    ) {
        self.meetingThresholdPercent = meetingThresholdPercent
        self.exceedingThresholdPercent = exceedingThresholdPercent
        self.partiallyMeetingThresholdPercent = partiallyMeetingThresholdPercent
        self.minimumSamplesForConfidence = minimumSamplesForConfidence
    }

    public static let `default` = ResidentialPlanEvaluationConfiguration()

    /// Avalia a porcentagem entregue e classifica em `DeliveryStatus`.
    public func status(forDeliveredPercent percent: Double) -> DeliveryStatus {
        if percent >= exceedingThresholdPercent {
            return .exceeding
        } else if percent >= meetingThresholdPercent {
            return .meetingPlan
        } else if percent >= partiallyMeetingThresholdPercent {
            return .partiallyMeeting
        } else {
            return .belowPlan
        }
    }
}

// MARK: - Avaliador de Plano Residencial (Motor V3)

/// Motor de avaliação e correlação entre medições de rede e o plano residencial contratado.
public enum ResidentialPlanEvaluator {

    /// Avalia uma medição pontual contra o plano residencial.
    ///
    /// - Parameters:
    ///   - plan: Plano de serviço residencial contratado.
    ///   - measurement: Medição canônica realizada.
    ///   - configuration: Limiares e parâmetros de avaliação.
    ///   - isExpensive: Sinalização de rede restrita/onerosa (se conhecida fora da medição).
    ///   - isPersonalHotspot: Sinalização de hotspot pessoal (se conhecida fora da medição).
    /// - Returns: Estrutura `SingleMeasurementPlanEvaluation` com elegibilidade, janela e entregas.
    public static func evaluateSingle(
        plan: NetworkServicePlan,
        measurement: NetworkMeasurement,
        configuration: ResidentialPlanEvaluationConfiguration = .default,
        isExpensive: Bool = false,
        isPersonalHotspot: Bool = false
    ) -> SingleMeasurementPlanEvaluation {
        let eligibility = ResidentialPlanEligibility.evaluate(
            measurement: measurement,
            isExpensive: isExpensive,
            isPersonalHotspot: isPersonalHotspot
        )

        var isWithinEffectiveWindow = true
        if let effectiveFrom = plan.effectiveFrom, measurement.measuredAt < effectiveFrom {
            isWithinEffectiveWindow = false
        }
        if let effectiveTo = plan.effectiveTo, measurement.measuredAt > effectiveTo {
            isWithinEffectiveWindow = false
        }

        let isAccepted = eligibility.isEligible && isWithinEffectiveWindow

        let download: PlanMetricEvaluation
        if let nominalDownload = plan.nominalDownloadMbps {
            if isAccepted, let measured = measurement.downloadMbps {
                download = .evaluated(
                    PlanSpeedDelivery(
                        nominalMbps: nominalDownload,
                        measuredMbps: measured,
                        configuration: configuration
                    )
                )
            } else {
                download = .noData
            }
        } else {
            download = .notConfigured
        }

        let upload: PlanMetricEvaluation
        if let nominalUpload = plan.nominalUploadMbps {
            if isAccepted, let measured = measurement.uploadMbps {
                upload = .evaluated(
                    PlanSpeedDelivery(
                        nominalMbps: nominalUpload,
                        measuredMbps: measured,
                        configuration: configuration
                    )
                )
            } else {
                upload = .noData
            }
        } else {
            upload = .notConfigured
        }

        return SingleMeasurementPlanEvaluation(
            planID: plan.id,
            measurementID: measurement.id,
            measuredAt: measurement.measuredAt,
            eligibility: eligibility,
            isWithinEffectiveWindow: isWithinEffectiveWindow,
            download: download,
            upload: upload
        )
    }

    /// Avalia de forma agregada uma amostra de medições contra o plano residencial.
    ///
    /// - Parameters:
    ///   - plan: Plano residencial de referência.
    ///   - measurements: Coleção de medições brutas fornecidas.
    ///   - configuration: Configuração com limiares e requisitos de amostragem.
    ///   - evaluatedAt: Instante do cálculo da avaliação.
    ///   - eligibilityResolver: Resolução opcional de elegibilidade por medição (útil para testes de hotspot/expensive).
    /// - Returns: Síntese agregada `ResidentialPlanAggregateEvaluation`.
    public static func evaluateAggregate(
        plan: NetworkServicePlan,
        measurements: [NetworkMeasurement],
        configuration: ResidentialPlanEvaluationConfiguration = .default,
        evaluatedAt: Date = Date(),
        eligibilityResolver: ((NetworkMeasurement) -> ResidentialPlanEligibility)? = nil
    ) -> ResidentialPlanAggregateEvaluation {
        var eligibleMeasurements: [NetworkMeasurement] = []
        var excludedIneligibleCount = 0
        var excludedOutOfWindowCount = 0

        for measurement in measurements {
            let eligibility = eligibilityResolver?(measurement)
                ?? ResidentialPlanEligibility.evaluate(measurement: measurement)

            guard eligibility.isEligible else {
                excludedIneligibleCount += 1
                continue
            }

            var inWindow = true
            if let effectiveFrom = plan.effectiveFrom, measurement.measuredAt < effectiveFrom {
                inWindow = false
            }
            if let effectiveTo = plan.effectiveTo, measurement.measuredAt > effectiveTo {
                inWindow = false
            }

            guard inWindow else {
                excludedOutOfWindowCount += 1
                continue
            }

            eligibleMeasurements.append(measurement)
        }

        let eligibleCount = eligibleMeasurements.count

        // Download
        let downloadAggregate: PlanMetricAggregateDelivery?
        let downloadEvaluation: PlanMetricEvaluation

        if let nominalDownload = plan.nominalDownloadMbps {
            let downloadSamples = eligibleMeasurements.compactMap { $0.downloadMbps }
            if let agg = PlanMetricAggregateDelivery(
                nominalMbps: nominalDownload,
                samples: downloadSamples,
                configuration: configuration
            ) {
                downloadAggregate = agg
                downloadEvaluation = .evaluated(
                    PlanSpeedDelivery(
                        nominalMbps: nominalDownload,
                        measuredMbps: agg.averageMbps,
                        configuration: configuration
                    )
                )
            } else {
                downloadAggregate = nil
                downloadEvaluation = .noData
            }
        } else {
            downloadAggregate = nil
            downloadEvaluation = .notConfigured
        }

        // Upload
        let uploadAggregate: PlanMetricAggregateDelivery?
        let uploadEvaluation: PlanMetricEvaluation

        if let nominalUpload = plan.nominalUploadMbps {
            let uploadSamples = eligibleMeasurements.compactMap { $0.uploadMbps }
            if let agg = PlanMetricAggregateDelivery(
                nominalMbps: nominalUpload,
                samples: uploadSamples,
                configuration: configuration
            ) {
                uploadAggregate = agg
                uploadEvaluation = .evaluated(
                    PlanSpeedDelivery(
                        nominalMbps: nominalUpload,
                        measuredMbps: agg.averageMbps,
                        configuration: configuration
                    )
                )
            } else {
                uploadAggregate = nil
                uploadEvaluation = .noData
            }
        } else {
            uploadAggregate = nil
            uploadEvaluation = .notConfigured
        }

        let minSamples = configuration.minimumSamplesForConfidence
        let hasDownloadConfidence = downloadAggregate.map { $0.sampleCount >= minSamples } ?? false
        let hasUploadConfidence = uploadAggregate.map { $0.sampleCount >= minSamples } ?? false
        let isSampleSufficient = (hasDownloadConfidence || hasUploadConfidence) && eligibleCount > 0

        return ResidentialPlanAggregateEvaluation(
            planID: plan.id,
            evaluatedAt: evaluatedAt,
            totalMeasurementsProvided: measurements.count,
            eligibleMeasurementsCount: eligibleCount,
            excludedIneligibleCount: excludedIneligibleCount,
            excludedOutOfWindowCount: excludedOutOfWindowCount,
            downloadEvaluation: downloadEvaluation,
            uploadEvaluation: uploadEvaluation,
            downloadAggregate: downloadAggregate,
            uploadAggregate: uploadAggregate,
            isSampleSufficient: isSampleSufficient
        )
    }
}
