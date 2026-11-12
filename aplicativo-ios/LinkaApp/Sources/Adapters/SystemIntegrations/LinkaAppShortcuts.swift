import AppIntents
import LinkaAppIntents

/// Atalhos que o sistema registra para o Linka.
///
/// O provedor precisa pertencer ao alvo do aplicativo: assim o processador
/// de metadados do Xcode o inclui em `Metadata.appintents` e o app Atalhos o
/// descobre no dispositivo. Os intents continuam no pacote dedicado, que
/// preserva o contrato independente da interface SwiftUI.
struct LinkaAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSpeedTestIntent(),
            phrases: [
                "Testar internet com \(.applicationName)",
                "Medir minha conexão com \(.applicationName)"
            ],
            shortTitle: "Testar internet",
            systemImageName: "gauge.with.dots.needle.50percent"
        )

        AppShortcut(
            intent: OpenHistoryIntent(),
            phrases: ["Abrir histórico do \(.applicationName)"],
            shortTitle: "Histórico",
            systemImageName: "clock.arrow.circlepath"
        )

        AppShortcut(
            intent: OpenLatestMeasurementIntent(),
            phrases: ["Abrir última medição do \(.applicationName)"],
            shortTitle: "Última medição",
            systemImageName: "chart.bar"
        )

        AppShortcut(
            intent: OpenPurchaseIntent(),
            phrases: ["Conhecer Linka Plus no \(.applicationName)"],
            shortTitle: "Linka Plus",
            systemImageName: "sparkles"
        )

        #if os(iOS)
        AppShortcut(
            intent: RegisterAdvancedWiFiDiagnosticsIntent(),
            phrases: [
                "Registrar diagnóstico Wi-Fi com \(.applicationName)",
                "Importar dados Wi-Fi no \(.applicationName)"
            ],
            shortTitle: "Wi-Fi avançado",
            systemImageName: "wifi"
        )
        #endif
    }
}
