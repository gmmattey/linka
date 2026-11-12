import AppIntents

public struct LinkaAppShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSpeedTestIntent(),
            phrases: [
                "Analisar conexão com \(.applicationName)",
                "Testar internet com \(.applicationName)",
                "Testar Wi-Fi com \(.applicationName)",
                "Medir velocidade no \(.applicationName)"
            ],
            shortTitle: "Analisar conexão",
            systemImageName: "network"
        )
        
        AppShortcut(
            intent: GetLatestResultIntent(),
            phrases: [
                "Último resultado do \(.applicationName)",
                "Ver resultado do \(.applicationName)",
                "Qual foi a última medição no \(.applicationName)"
            ],
            shortTitle: "Último resultado",
            systemImageName: "clock"
        )

        AppShortcut(
            intent: OpenHistoryIntent(),
            phrases: [
                "Abrir histórico do \(.applicationName)",
                "Ver medições no \(.applicationName)"
            ],
            shortTitle: "Abrir histórico",
            systemImageName: "clock.arrow.circlepath"
        )

        AppShortcut(
            intent: OpenLatestMeasurementIntent(),
            phrases: [
                "Abrir última medição do \(.applicationName)",
                "Ver última medição no \(.applicationName)"
            ],
            shortTitle: "Abrir última medição",
            systemImageName: "chart.bar"
        )

        AppShortcut(
            intent: OpenPurchaseIntent(),
            phrases: [
                "Conhecer Linka Plus no \(.applicationName)",
                "Abrir Linka Plus no \(.applicationName)"
            ],
            shortTitle: "Linka Plus",
            systemImageName: "sparkles"
        )
    }
}
