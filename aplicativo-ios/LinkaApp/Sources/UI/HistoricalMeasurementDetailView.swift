import SwiftUI
import NetworkCore
import LinkaEntitlements

/// Tela de detalhe de uma medição histórica em formato de List nativo padrão Apple.
struct HistoricalMeasurementDetailView: View {
    let measurement: NetworkMeasurement
    let onStartNewMeasurement: (() -> Void)?
    let onStartNewMeasurementWithAdvancedWiFi: (() -> Void)?
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider

    init(
        measurement: NetworkMeasurement,
        onStartNewMeasurement: (() -> Void)? = nil,
        onStartNewMeasurementWithAdvancedWiFi: (() -> Void)? = nil
    ) {
        self.measurement = measurement
        self.onStartNewMeasurement = onStartNewMeasurement
        self.onStartNewMeasurementWithAdvancedWiFi = onStartNewMeasurementWithAdvancedWiFi
    }

    var body: some View {
        MeasurementDetailView(
            measurement: measurement,
            duration: nil,
            onStartNewMeasurement: onStartNewMeasurement,
            onStartNewMeasurementWithAdvancedWiFi: onStartNewMeasurementWithAdvancedWiFi
        )
            .environmentObject(entitlements)
            .onAppear {
                LinkaAnalytics.shared.track(.resultViewed(source: "history"))
            }
    }
}
