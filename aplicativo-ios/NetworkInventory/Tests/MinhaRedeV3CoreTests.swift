import XCTest
@testable import NetworkInventory
import NetworkCore

final class MinhaRedeV3CoreTests: XCTestCase {

    // MARK: - Ajudantes

    private func makePlan(
        id: UUID = UUID(),
        downloadMbps: Double? = 100.0,
        uploadMbps: Double? = 50.0,
        effectiveFrom: Date? = nil,
        effectiveTo: Date? = nil
    ) -> NetworkServicePlan {
        NetworkServicePlan(
            id: id,
            ispName: "Fibra Teste",
            planName: "Super Fibra",
            nominalDownloadMbps: downloadMbps,
            nominalUploadMbps: uploadMbps,
            technology: .fiber,
            effectiveFrom: effectiveFrom,
            effectiveTo: effectiveTo
        )
    }

    private func makeMeasurement(
        connectionKind: NetworkConnectionKind = .wifi,
        downloadMbps: Double? = 95.0,
        uploadMbps: Double? = 45.0,
        measuredAt: Date = Date()
    ) -> NetworkMeasurement {
        NetworkMeasurement(
            measuredAt: measuredAt,
            downloadMbps: downloadMbps,
            uploadMbps: uploadMbps,
            connectionKind: connectionKind
        )
    }

    // MARK: - 1. Isolamento B1 (Guarda B1)

    func testB1IsolationCellularMeasurementIsRejectedInAggregate() {
        let plan = makePlan(downloadMbps: 100.0, uploadMbps: 50.0)
        let cellularMeasurements = [
            makeMeasurement(connectionKind: .cellular, downloadMbps: 120.0, uploadMbps: 60.0),
            makeMeasurement(connectionKind: .cellular, downloadMbps: 150.0, uploadMbps: 80.0)
        ]

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: cellularMeasurements
        )

        XCTAssertEqual(aggregate.totalMeasurementsProvided, 2)
        XCTAssertEqual(aggregate.eligibleMeasurementsCount, 0)
        XCTAssertEqual(aggregate.excludedIneligibleCount, 2)
        XCTAssertEqual(aggregate.excludedOutOfWindowCount, 0)
        XCTAssertEqual(aggregate.downloadEvaluation, .noData)
        XCTAssertEqual(aggregate.uploadEvaluation, .noData)
        XCTAssertNil(aggregate.downloadAggregate)
        XCTAssertNil(aggregate.uploadAggregate)
        XCTAssertFalse(aggregate.isSampleSufficient)
    }

    func testB1IsolationPersonalHotspotMeasurementIsRejected() {
        let plan = makePlan()
        let wifiMeasurement = makeMeasurement(connectionKind: .wifi)

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: [wifiMeasurement],
            eligibilityResolver: { m in
                ResidentialPlanEligibility.evaluate(measurement: m, isPersonalHotspot: true)
            }
        )

        XCTAssertEqual(aggregate.totalMeasurementsProvided, 1)
        XCTAssertEqual(aggregate.eligibleMeasurementsCount, 0)
        XCTAssertEqual(aggregate.excludedIneligibleCount, 1)
        XCTAssertEqual(aggregate.downloadEvaluation, .noData)
    }

    func testB1IsolationExpensiveNetworkIsRejected() {
        let plan = makePlan()
        let wifiMeasurement = makeMeasurement(connectionKind: .wifi)

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: [wifiMeasurement],
            eligibilityResolver: { m in
                ResidentialPlanEligibility.evaluate(measurement: m, isExpensive: true)
            }
        )

        XCTAssertEqual(aggregate.totalMeasurementsProvided, 1)
        XCTAssertEqual(aggregate.eligibleMeasurementsCount, 0)
        XCTAssertEqual(aggregate.excludedIneligibleCount, 1)
        XCTAssertEqual(aggregate.downloadEvaluation, .noData)
    }

    func testB1IsolationSingleMeasurementCellularEvaluation() {
        let plan = makePlan(downloadMbps: 100.0, uploadMbps: 50.0)
        let measurement = makeMeasurement(
            connectionKind: .cellular,
            downloadMbps: 150.0,
            uploadMbps: 70.0
        )

        let single = ResidentialPlanEvaluator.evaluateSingle(
            plan: plan,
            measurement: measurement
        )

        XCTAssertEqual(single.planID, plan.id)
        XCTAssertEqual(single.measurementID, measurement.id)
        XCTAssertFalse(single.eligibility.isEligible)
        XCTAssertEqual(single.eligibility.reason, .cellularConnection)
        XCTAssertTrue(single.isWithinEffectiveWindow)
        XCTAssertEqual(single.download, .noData)
        XCTAssertEqual(single.upload, .noData)
    }

    func testB1IsolationSingleMeasurementHotspotEvaluation() {
        let plan = makePlan()
        let measurement = makeMeasurement(connectionKind: .wifi)

        let single = ResidentialPlanEvaluator.evaluateSingle(
            plan: plan,
            measurement: measurement,
            isPersonalHotspot: true
        )

        XCTAssertFalse(single.eligibility.isEligible)
        XCTAssertEqual(single.eligibility.reason, .personalHotspot)
        XCTAssertEqual(single.download, .noData)
    }

    func testB1IsolationSingleMeasurementExpensiveEvaluation() {
        let plan = makePlan()
        let measurement = makeMeasurement(connectionKind: .wifi)

        let single = ResidentialPlanEvaluator.evaluateSingle(
            plan: plan,
            measurement: measurement,
            isExpensive: true
        )

        XCTAssertFalse(single.eligibility.isEligible)
        XCTAssertEqual(single.eligibility.reason, .expensiveNetwork)
        XCTAssertEqual(single.download, .noData)
    }

    func testB1IsolationWifiAndEthernetAreAccepted() {
        let plan = makePlan(downloadMbps: 100.0, uploadMbps: 50.0)
        let wifi = makeMeasurement(connectionKind: .wifi, downloadMbps: 100.0, uploadMbps: 50.0)
        let ethernet = makeMeasurement(connectionKind: .ethernet, downloadMbps: 100.0, uploadMbps: 50.0)

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: [wifi, ethernet]
        )

        XCTAssertEqual(aggregate.totalMeasurementsProvided, 2)
        XCTAssertEqual(aggregate.eligibleMeasurementsCount, 2)
        XCTAssertEqual(aggregate.excludedIneligibleCount, 0)
        XCTAssertTrue(aggregate.downloadEvaluation.isEvaluated)
        XCTAssertTrue(aggregate.uploadEvaluation.isEvaluated)
    }

    // MARK: - 2. Respeito à Janela Temporal

    func testTemporalWindowBeforeEffectiveFromIsRejected() {
        let now = Date()
        let effectiveFrom = now.addingTimeInterval(1000)
        let plan = makePlan(effectiveFrom: effectiveFrom)

        let measurement = makeMeasurement(measuredAt: now)

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: [measurement]
        )

        XCTAssertEqual(aggregate.totalMeasurementsProvided, 1)
        XCTAssertEqual(aggregate.eligibleMeasurementsCount, 0)
        XCTAssertEqual(aggregate.excludedIneligibleCount, 0)
        XCTAssertEqual(aggregate.excludedOutOfWindowCount, 1)
        XCTAssertEqual(aggregate.downloadEvaluation, .noData)
    }

    func testTemporalWindowAfterEffectiveToIsRejected() {
        let now = Date()
        let effectiveTo = now.addingTimeInterval(-1000)
        let plan = makePlan(effectiveTo: effectiveTo)

        let measurement = makeMeasurement(measuredAt: now)

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: [measurement]
        )

        XCTAssertEqual(aggregate.totalMeasurementsProvided, 1)
        XCTAssertEqual(aggregate.eligibleMeasurementsCount, 0)
        XCTAssertEqual(aggregate.excludedOutOfWindowCount, 1)
        XCTAssertEqual(aggregate.downloadEvaluation, .noData)
    }

    func testTemporalWindowInsideWindowIsAccepted() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let t1 = Date(timeIntervalSince1970: 2_000_000)
        let plan = makePlan(effectiveFrom: t0, effectiveTo: t1)

        let mStart = makeMeasurement(measuredAt: t0)
        let mMid = makeMeasurement(measuredAt: Date(timeIntervalSince1970: 1_500_000))
        let mEnd = makeMeasurement(measuredAt: t1)
        let mBefore = makeMeasurement(measuredAt: Date(timeIntervalSince1970: 999_999))
        let mAfter = makeMeasurement(measuredAt: Date(timeIntervalSince1970: 2_000_001))

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: [mBefore, mStart, mMid, mEnd, mAfter]
        )

        XCTAssertEqual(aggregate.totalMeasurementsProvided, 5)
        XCTAssertEqual(aggregate.eligibleMeasurementsCount, 3)
        XCTAssertEqual(aggregate.excludedOutOfWindowCount, 2)
        XCTAssertEqual(aggregate.excludedIneligibleCount, 0)
    }

    func testTemporalWindowSingleMeasurementEvaluation() {
        let t0 = Date(timeIntervalSince1970: 10_000)
        let t1 = Date(timeIntervalSince1970: 20_000)
        let plan = makePlan(effectiveFrom: t0, effectiveTo: t1)

        let outBefore = makeMeasurement(measuredAt: Date(timeIntervalSince1970: 9_999))
        let evalBefore = ResidentialPlanEvaluator.evaluateSingle(plan: plan, measurement: outBefore)
        XCTAssertFalse(evalBefore.isWithinEffectiveWindow)
        XCTAssertEqual(evalBefore.download, .noData)

        let inWindow = makeMeasurement(measuredAt: Date(timeIntervalSince1970: 15_000))
        let evalIn = ResidentialPlanEvaluator.evaluateSingle(plan: plan, measurement: inWindow)
        XCTAssertTrue(evalIn.isWithinEffectiveWindow)
        XCTAssertTrue(evalIn.download.isEvaluated)

        let outAfter = makeMeasurement(measuredAt: Date(timeIntervalSince1970: 20_001))
        let evalAfter = ResidentialPlanEvaluator.evaluateSingle(plan: plan, measurement: outAfter)
        XCTAssertFalse(evalAfter.isWithinEffectiveWindow)
        XCTAssertEqual(evalAfter.download, .noData)
    }

    // MARK: - 3. Ausência de Medições (Ausência != Zero)

    func testEmptyMeasurementsReturnsNoDataAndZeroCounts() {
        let plan = makePlan(downloadMbps: 100.0, uploadMbps: 50.0)

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: []
        )

        XCTAssertEqual(aggregate.totalMeasurementsProvided, 0)
        XCTAssertEqual(aggregate.eligibleMeasurementsCount, 0)
        XCTAssertEqual(aggregate.excludedIneligibleCount, 0)
        XCTAssertEqual(aggregate.excludedOutOfWindowCount, 0)
        XCTAssertEqual(aggregate.downloadEvaluation, .noData)
        XCTAssertEqual(aggregate.uploadEvaluation, .noData)
        XCTAssertNil(aggregate.downloadAggregate)
        XCTAssertNil(aggregate.uploadAggregate)
        XCTAssertFalse(aggregate.isSampleSufficient)
    }

    func testAllMeasurementsExcludedReturnsNoDataWithCorrectCounts() {
        let t0 = Date(timeIntervalSince1970: 100_000)
        let plan = makePlan(effectiveFrom: t0)

        let cellular1 = makeMeasurement(connectionKind: .cellular, measuredAt: t0)
        let cellular2 = makeMeasurement(connectionKind: .cellular, measuredAt: t0)
        let outOfWindow1 = makeMeasurement(connectionKind: .wifi, measuredAt: Date(timeIntervalSince1970: 50_000))
        let outOfWindow2 = makeMeasurement(connectionKind: .wifi, measuredAt: Date(timeIntervalSince1970: 60_000))
        let outOfWindow3 = makeMeasurement(connectionKind: .wifi, measuredAt: Date(timeIntervalSince1970: 70_000))

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: [cellular1, cellular2, outOfWindow1, outOfWindow2, outOfWindow3]
        )

        XCTAssertEqual(aggregate.totalMeasurementsProvided, 5)
        XCTAssertEqual(aggregate.eligibleMeasurementsCount, 0)
        XCTAssertEqual(aggregate.excludedIneligibleCount, 2)
        XCTAssertEqual(aggregate.excludedOutOfWindowCount, 3)
        XCTAssertEqual(aggregate.downloadEvaluation, .noData)
        XCTAssertEqual(aggregate.uploadEvaluation, .noData)
        XCTAssertFalse(aggregate.isSampleSufficient)
    }

    // MARK: - 4. Planos com Apenas Download ou Apenas Upload

    func testPlanWithOnlyDownloadConfigured() {
        let plan = makePlan(downloadMbps: 200.0, uploadMbps: nil)
        let m1 = makeMeasurement(downloadMbps: 180.0, uploadMbps: 100.0)
        let m2 = makeMeasurement(downloadMbps: 190.0, uploadMbps: 100.0)
        let m3 = makeMeasurement(downloadMbps: 200.0, uploadMbps: 100.0)

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: [m1, m2, m3]
        )

        XCTAssertTrue(aggregate.downloadEvaluation.isEvaluated)
        XCTAssertNotNil(aggregate.downloadAggregate)
        XCTAssertEqual(aggregate.uploadEvaluation, .notConfigured)
        XCTAssertNil(aggregate.uploadAggregate)
        XCTAssertTrue(aggregate.isSampleSufficient)

        let single = ResidentialPlanEvaluator.evaluateSingle(plan: plan, measurement: m1)
        XCTAssertTrue(single.download.isEvaluated)
        XCTAssertEqual(single.upload, .notConfigured)
    }

    func testPlanWithOnlyUploadConfigured() {
        let plan = makePlan(downloadMbps: nil, uploadMbps: 100.0)
        let m1 = makeMeasurement(downloadMbps: 300.0, uploadMbps: 90.0)
        let m2 = makeMeasurement(downloadMbps: 300.0, uploadMbps: 95.0)
        let m3 = makeMeasurement(downloadMbps: 300.0, uploadMbps: 100.0)

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: [m1, m2, m3]
        )

        XCTAssertEqual(aggregate.downloadEvaluation, .notConfigured)
        XCTAssertNil(aggregate.downloadAggregate)
        XCTAssertTrue(aggregate.uploadEvaluation.isEvaluated)
        XCTAssertNotNil(aggregate.uploadAggregate)
        XCTAssertTrue(aggregate.isSampleSufficient)

        let single = ResidentialPlanEvaluator.evaluateSingle(plan: plan, measurement: m1)
        XCTAssertEqual(single.download, .notConfigured)
        XCTAssertTrue(single.upload.isEvaluated)
    }

    // MARK: - 5. Medições com Resultado Parcial

    func testPartialMeasurementWithOnlyDownloadAvailable() {
        let plan = makePlan(downloadMbps: 300.0, uploadMbps: 150.0)
        let m1 = makeMeasurement(downloadMbps: 270.0, uploadMbps: nil)
        let m2 = makeMeasurement(downloadMbps: 285.0, uploadMbps: nil)
        let m3 = makeMeasurement(downloadMbps: 300.0, uploadMbps: nil)

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: [m1, m2, m3]
        )

        XCTAssertTrue(aggregate.downloadEvaluation.isEvaluated)
        XCTAssertEqual(aggregate.downloadAggregate?.sampleCount, 3)
        XCTAssertEqual(aggregate.uploadEvaluation, .noData)
        XCTAssertNil(aggregate.uploadAggregate)

        let single = ResidentialPlanEvaluator.evaluateSingle(plan: plan, measurement: m1)
        XCTAssertTrue(single.download.isEvaluated)
        XCTAssertEqual(single.upload, .noData)
    }

    func testPartialMeasurementWithOnlyUploadAvailable() {
        let plan = makePlan(downloadMbps: 300.0, uploadMbps: 150.0)
        let m1 = makeMeasurement(downloadMbps: nil, uploadMbps: 130.0)
        let m2 = makeMeasurement(downloadMbps: nil, uploadMbps: 140.0)
        let m3 = makeMeasurement(downloadMbps: nil, uploadMbps: 150.0)

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: [m1, m2, m3]
        )

        XCTAssertEqual(aggregate.downloadEvaluation, .noData)
        XCTAssertNil(aggregate.downloadAggregate)
        XCTAssertTrue(aggregate.uploadEvaluation.isEvaluated)
        XCTAssertEqual(aggregate.uploadAggregate?.sampleCount, 3)

        let single = ResidentialPlanEvaluator.evaluateSingle(plan: plan, measurement: m1)
        XCTAssertEqual(single.download, .noData)
        XCTAssertTrue(single.upload.isEvaluated)
    }

    // MARK: - 6. Verificação Exata dos Limiares de DeliveryStatus

    func testDeliveryStatusThresholdsSingleMeasurement() {
        let plan = makePlan(downloadMbps: 100.0, uploadMbps: 100.0)

        // >= 105% -> exceeding
        let exceeding1 = ResidentialPlanEvaluator.evaluateSingle(
            plan: plan,
            measurement: makeMeasurement(downloadMbps: 105.0)
        )
        XCTAssertEqual(exceeding1.download.delivery?.status, .exceeding)
        XCTAssertEqual(exceeding1.download.delivery?.deliveredPercent, 105.0)

        let exceeding2 = ResidentialPlanEvaluator.evaluateSingle(
            plan: plan,
            measurement: makeMeasurement(downloadMbps: 150.0)
        )
        XCTAssertEqual(exceeding2.download.delivery?.status, .exceeding)

        // 80% ..< 105% -> meetingPlan
        let meeting1 = ResidentialPlanEvaluator.evaluateSingle(
            plan: plan,
            measurement: makeMeasurement(downloadMbps: 104.9)
        )
        XCTAssertEqual(meeting1.download.delivery?.status, .meetingPlan)

        let meeting2 = ResidentialPlanEvaluator.evaluateSingle(
            plan: plan,
            measurement: makeMeasurement(downloadMbps: 80.0)
        )
        XCTAssertEqual(meeting2.download.delivery?.status, .meetingPlan)

        // 50% ..< 80% -> partiallyMeeting
        let partial1 = ResidentialPlanEvaluator.evaluateSingle(
            plan: plan,
            measurement: makeMeasurement(downloadMbps: 79.9)
        )
        XCTAssertEqual(partial1.download.delivery?.status, .partiallyMeeting)

        let partial2 = ResidentialPlanEvaluator.evaluateSingle(
            plan: plan,
            measurement: makeMeasurement(downloadMbps: 50.0)
        )
        XCTAssertEqual(partial2.download.delivery?.status, .partiallyMeeting)

        // < 50% -> belowPlan
        let below1 = ResidentialPlanEvaluator.evaluateSingle(
            plan: plan,
            measurement: makeMeasurement(downloadMbps: 49.9)
        )
        XCTAssertEqual(below1.download.delivery?.status, .belowPlan)

        let below2 = ResidentialPlanEvaluator.evaluateSingle(
            plan: plan,
            measurement: makeMeasurement(downloadMbps: 10.0)
        )
        XCTAssertEqual(below2.download.delivery?.status, .belowPlan)

        let belowZero = ResidentialPlanEvaluator.evaluateSingle(
            plan: plan,
            measurement: makeMeasurement(downloadMbps: 0.0)
        )
        XCTAssertEqual(belowZero.download.delivery?.status, .belowPlan)
    }

    func testDeliveryStatusCustomConfiguration() {
        let customConfig = ResidentialPlanEvaluationConfiguration(
            meetingThresholdPercent: 90.0,
            exceedingThresholdPercent: 110.0,
            partiallyMeetingThresholdPercent: 60.0,
            minimumSamplesForConfidence: 5
        )

        let plan = makePlan(downloadMbps: 100.0)

        // 109% com config default seria exceeding, mas na custom é meetingPlan (< 110%)
        let eval1 = ResidentialPlanEvaluator.evaluateSingle(
            plan: plan,
            measurement: makeMeasurement(downloadMbps: 109.0),
            configuration: customConfig
        )
        XCTAssertEqual(eval1.download.delivery?.status, .meetingPlan)

        // 110% é exceeding
        let eval2 = ResidentialPlanEvaluator.evaluateSingle(
            plan: plan,
            measurement: makeMeasurement(downloadMbps: 110.0),
            configuration: customConfig
        )
        XCTAssertEqual(eval2.download.delivery?.status, .exceeding)

        // 89% com config default seria meetingPlan, mas na custom é partiallyMeeting (< 90%)
        let eval3 = ResidentialPlanEvaluator.evaluateSingle(
            plan: plan,
            measurement: makeMeasurement(downloadMbps: 89.0),
            configuration: customConfig
        )
        XCTAssertEqual(eval3.download.delivery?.status, .partiallyMeeting)

        // 59% é belowPlan (< 60%)
        let eval4 = ResidentialPlanEvaluator.evaluateSingle(
            plan: plan,
            measurement: makeMeasurement(downloadMbps: 59.0),
            configuration: customConfig
        )
        XCTAssertEqual(eval4.download.delivery?.status, .belowPlan)
    }

    // MARK: - 7. Agregação Estatística

    func testStatisticalAggregationCalculations() {
        let plan = makePlan(downloadMbps: 100.0)
        let measurements = [
            makeMeasurement(downloadMbps: 60.0),
            makeMeasurement(downloadMbps: 80.0),
            makeMeasurement(downloadMbps: 100.0),
            makeMeasurement(downloadMbps: 120.0),
            makeMeasurement(downloadMbps: 140.0)
        ]

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: measurements
        )

        guard let downloadAgg = aggregate.downloadAggregate else {
            return XCTFail("downloadAggregate não deveria ser nil")
        }

        XCTAssertEqual(downloadAgg.sampleCount, 5)
        XCTAssertEqual(downloadAgg.nominalMbps, 100.0)
        XCTAssertEqual(downloadAgg.averageMbps, 100.0, accuracy: 0.001)
        XCTAssertEqual(downloadAgg.medianMbps, 100.0, accuracy: 0.001)
        XCTAssertEqual(downloadAgg.peakMbps, 140.0, accuracy: 0.001)
        XCTAssertEqual(downloadAgg.averageDeliveredPercent, 100.0, accuracy: 0.001)
        XCTAssertEqual(downloadAgg.medianDeliveredPercent, 100.0, accuracy: 0.001)
        XCTAssertEqual(downloadAgg.peakDeliveredPercent, 140.0, accuracy: 0.001)
        XCTAssertEqual(downloadAgg.minimumDeliveredPercent, 60.0, accuracy: 0.001)
        XCTAssertEqual(downloadAgg.maximumDeliveredPercent, 140.0, accuracy: 0.001)

        // Variância = (1600 + 400 + 0 + 400 + 1600) / 5 = 800.0 -> sqrt(800) ≈ 28.28427
        let expectedStdDev = sqrt(800.0)
        XCTAssertEqual(downloadAgg.standardDeviationMbps, expectedStdDev, accuracy: 0.001)
        XCTAssertEqual(downloadAgg.status, .meetingPlan)

        // Verificação do PlanSpeedDelivery sintetizado na downloadEvaluation
        guard let delivery = aggregate.downloadEvaluation.delivery else {
            return XCTFail("delivery não deveria ser nil")
        }
        XCTAssertEqual(delivery.nominalMbps, 100.0)
        XCTAssertEqual(delivery.measuredMbps, 100.0, accuracy: 0.001)
        XCTAssertEqual(delivery.deltaMbps, 0.0, accuracy: 0.001)
        XCTAssertEqual(delivery.deliveredRatio, 1.0, accuracy: 0.001)
        XCTAssertEqual(delivery.deliveredPercent, 100.0, accuracy: 0.001)
        XCTAssertEqual(delivery.status, .meetingPlan)
    }

    func testStatisticalAggregationEvenCountMedian() {
        let plan = makePlan(downloadMbps: 200.0)
        let measurements = [
            makeMeasurement(downloadMbps: 100.0),
            makeMeasurement(downloadMbps: 200.0),
            makeMeasurement(downloadMbps: 300.0),
            makeMeasurement(downloadMbps: 400.0)
        ]

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: measurements
        )

        guard let downloadAgg = aggregate.downloadAggregate else {
            return XCTFail("downloadAggregate não deveria ser nil")
        }

        XCTAssertEqual(downloadAgg.sampleCount, 4)
        XCTAssertEqual(downloadAgg.averageMbps, 250.0, accuracy: 0.001)
        XCTAssertEqual(downloadAgg.medianMbps, 250.0, accuracy: 0.001)
        XCTAssertEqual(downloadAgg.averageDeliveredPercent, 125.0, accuracy: 0.001)
        XCTAssertEqual(downloadAgg.status, .exceeding)
    }

    func testSampleSufficiencyThreshold() {
        let plan = makePlan(downloadMbps: 100.0)
        let m1 = makeMeasurement()
        let m2 = makeMeasurement()
        let m3 = makeMeasurement()

        let agg1 = ResidentialPlanEvaluator.evaluateAggregate(plan: plan, measurements: [m1])
        XCTAssertFalse(agg1.isSampleSufficient)

        let agg2 = ResidentialPlanEvaluator.evaluateAggregate(plan: plan, measurements: [m1, m2])
        XCTAssertFalse(agg2.isSampleSufficient)

        let agg3 = ResidentialPlanEvaluator.evaluateAggregate(plan: plan, measurements: [m1, m2, m3])
        XCTAssertTrue(agg3.isSampleSufficient)

        // Custom config com minimumSamplesForConfidence: 2
        let config = ResidentialPlanEvaluationConfiguration(minimumSamplesForConfidence: 2)
        let aggCustom = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: [m1, m2],
            configuration: config
        )
        XCTAssertTrue(aggCustom.isSampleSufficient)
    }

    // MARK: - 8. DeltaMbps e DeliveredRatio

    func testDeltaAndDeliveredRatioAccuracy() {
        let plan = makePlan(downloadMbps: 250.0, uploadMbps: 100.0)
        let measurement = makeMeasurement(downloadMbps: 275.0, uploadMbps: 80.0)

        let single = ResidentialPlanEvaluator.evaluateSingle(plan: plan, measurement: measurement)

        guard let downloadDelivery = single.download.delivery,
              let uploadDelivery = single.upload.delivery else {
            return XCTFail("Entregas de download e upload deveriam estar presentes")
        }

        // Download: 275 Mbps em plano de 250 Mbps -> ratio 1.1, delta +25
        XCTAssertEqual(downloadDelivery.deliveredRatio, 1.1, accuracy: 0.0001)
        XCTAssertEqual(downloadDelivery.deliveredPercent, 110.0, accuracy: 0.0001)
        XCTAssertEqual(downloadDelivery.deltaMbps, 25.0, accuracy: 0.0001)
        XCTAssertEqual(downloadDelivery.status, .exceeding)

        // Upload: 80 Mbps em plano de 100 Mbps -> ratio 0.8, delta -20
        XCTAssertEqual(uploadDelivery.deliveredRatio, 0.8, accuracy: 0.0001)
        XCTAssertEqual(uploadDelivery.deliveredPercent, 80.0, accuracy: 0.0001)
        XCTAssertEqual(uploadDelivery.deltaMbps, -20.0, accuracy: 0.0001)
        XCTAssertEqual(uploadDelivery.status, .meetingPlan)
    }

    // MARK: - 9. Serialização Codable Roundtrip

    func testCodableRoundtrip() throws {
        let plan = makePlan(downloadMbps: 100.0, uploadMbps: 50.0)
        let measurements = [
            makeMeasurement(downloadMbps: 90.0, uploadMbps: 45.0),
            makeMeasurement(downloadMbps: 100.0, uploadMbps: 50.0),
            makeMeasurement(downloadMbps: 110.0, uploadMbps: 55.0)
        ]

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: measurements
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(aggregate)
        let decoded = try decoder.decode(ResidentialPlanAggregateEvaluation.self, from: data)

        XCTAssertEqual(aggregate, decoded)

        let single = ResidentialPlanEvaluator.evaluateSingle(
            plan: plan,
            measurement: measurements[0]
        )
        let singleData = try encoder.encode(single)
        let decodedSingle = try decoder.decode(SingleMeasurementPlanEvaluation.self, from: singleData)
        XCTAssertEqual(single, decodedSingle)
    }

    // MARK: - 10. Robustez e Casos Extremos (Auditoria)

    func testUploadOnlyMeasurementsAffectOnlyUploadSufficiency() {
        let plan = makePlan(downloadMbps: 100.0, uploadMbps: 50.0)
        // 3 medições com upload mas download nulo
        let uploadOnlyMeasurements = [
            makeMeasurement(downloadMbps: nil, uploadMbps: 45.0),
            makeMeasurement(downloadMbps: nil, uploadMbps: 48.0),
            makeMeasurement(downloadMbps: nil, uploadMbps: 52.0)
        ]

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: uploadOnlyMeasurements
        )

        XCTAssertEqual(aggregate.eligibleMeasurementsCount, 3)
        XCTAssertEqual(aggregate.downloadEvaluation, .noData)
        XCTAssertNil(aggregate.downloadAggregate)
        XCTAssertNotNil(aggregate.uploadAggregate)
        XCTAssertTrue(aggregate.uploadEvaluation.isEvaluated)
        XCTAssertTrue(aggregate.isSampleSufficient)
    }

    func testEvaluateAggregateWithZeroOrNegativeNominalDoesNotProduceNaNOrInf() {
        let planZero = makePlan(downloadMbps: 0.0, uploadMbps: -50.0)
        let measurements = [
            makeMeasurement(downloadMbps: 100.0, uploadMbps: 50.0),
            makeMeasurement(downloadMbps: 80.0, uploadMbps: 40.0)
        ]

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: planZero,
            measurements: measurements
        )

        XCTAssertEqual(aggregate.eligibleMeasurementsCount, 2)
        XCTAssertEqual(aggregate.downloadEvaluation, .noData)
        XCTAssertEqual(aggregate.uploadEvaluation, .noData)
        XCTAssertNil(aggregate.downloadAggregate)
        XCTAssertNil(aggregate.uploadAggregate)
        XCTAssertFalse(aggregate.isSampleSufficient)

        // Também testando PlanSpeedDelivery diretamente com nominal <= 0
        let deliveryZero = PlanSpeedDelivery(nominalMbps: 0.0, measuredMbps: 50.0)
        XCTAssertFalse(deliveryZero.deliveredRatio.isNaN)
        XCTAssertFalse(deliveryZero.deliveredRatio.isInfinite)
        XCTAssertEqual(deliveryZero.deliveredRatio, 0.0)
        XCTAssertEqual(deliveryZero.deliveredPercent, 0.0)

        let deliveryNegative = PlanSpeedDelivery(nominalMbps: -100.0, measuredMbps: 50.0)
        XCTAssertFalse(deliveryNegative.deliveredRatio.isNaN)
        XCTAssertFalse(deliveryNegative.deliveredRatio.isInfinite)
        XCTAssertEqual(deliveryNegative.deliveredRatio, 0.0)
    }

    func testIneligibleConnectionKindOtherAndNil() {
        let plan = makePlan()
        let measurementOther = NetworkMeasurement(
            measuredAt: Date(),
            downloadMbps: 100.0,
            uploadMbps: 50.0,
            connectionKind: .other
        )
        let measurementNil = NetworkMeasurement(
            measuredAt: Date(),
            downloadMbps: 100.0,
            uploadMbps: 50.0,
            connectionKind: nil
        )

        let aggregate = ResidentialPlanEvaluator.evaluateAggregate(
            plan: plan,
            measurements: [measurementOther, measurementNil]
        )

        XCTAssertEqual(aggregate.totalMeasurementsProvided, 2)
        XCTAssertEqual(aggregate.eligibleMeasurementsCount, 0)
        XCTAssertEqual(aggregate.excludedIneligibleCount, 2)
        XCTAssertEqual(aggregate.downloadEvaluation, .noData)
        XCTAssertEqual(aggregate.uploadEvaluation, .noData)

        let singleOther = ResidentialPlanEvaluator.evaluateSingle(plan: plan, measurement: measurementOther)
        XCTAssertFalse(singleOther.eligibility.isEligible)
        XCTAssertEqual(singleOther.eligibility.reason, .unsupportedConnectionKind)

        let singleNil = ResidentialPlanEvaluator.evaluateSingle(plan: plan, measurement: measurementNil)
        XCTAssertFalse(singleNil.eligibility.isEligible)
        XCTAssertEqual(singleNil.eligibility.reason, .missingConnectionKind)
    }

    func testPlanMetricAggregateDeliveryFailableInitRejectsEmptyAndNonPositiveNominal() {
        XCTAssertNil(PlanMetricAggregateDelivery(nominalMbps: 100.0, samples: []))
        XCTAssertNil(PlanMetricAggregateDelivery(nominalMbps: 0.0, samples: [100.0]))
        XCTAssertNil(PlanMetricAggregateDelivery(nominalMbps: -50.0, samples: [100.0]))
        XCTAssertNotNil(PlanMetricAggregateDelivery(nominalMbps: 100.0, samples: [95.0]))
    }
}
