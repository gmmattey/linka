#if os(macOS)
import SwiftUI
import AppKit

/// Destinos de navegação de topo do Linka no Mac.
enum MacDestination: String, Hashable {
    case speedTest, history, myNetwork, assist, optimization
}

/// Ponte entre a barra de menus e a janela. Os itens de menu só pedem a ação;
/// quem sabe executá-la (a janela principal ou o Histórico) observa e responde.
@MainActor
final class MacCommandCenter: ObservableObject {
    static let shared = MacCommandCenter()
    private init() {}

    @Published var navigationRequest: MacDestination?
    @Published var exportHistoryRequest = false
    @Published var shareRequest = false
    @Published var deleteRequest = false
    @Published var latestResultRequest = false

    /// Estado que habilita ou desabilita itens de menu.
    @Published var isMeasuring = false
    @Published var canShare = false
    @Published var canDelete = false
    @Published var showsAssist = false
    @Published var showsOptimization = false
}

/// Chaves de preferência de janela.
enum MacWindowPreferences {
    static let inspectorKey = "linka.mac.inspector.visible"
}

/// Menus do app: Arquivo, Visualizar, Medição e Ir. Todo comando da tela tem
/// item de menu e atalho.
struct LinkaMacCommands: Commands {
    @ObservedObject private var center = MacCommandCenter.shared
    @ObservedObject private var coordinator = AppIntentCoordinator.shared
    @AppStorage(MacWindowPreferences.inspectorKey) private var inspectorVisible = true

    var body: some Commands {
        // A barra lateral usa o comando padrão do sistema (⌥⌘S).
        SidebarCommands()

        CommandGroup(replacing: .newItem) {
            Button(LinkaCopy.value("Exportar histórico…")) { center.exportHistoryRequest = true }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button(LinkaCopy.value("Compartilhar medição…")) { center.shareRequest = true }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!center.canShare)
        }

        CommandGroup(after: .sidebar) {
            Button(LinkaCopy.value(inspectorVisible ? "Ocultar inspetor" : "Mostrar inspetor")) {
                inspectorVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }

        CommandMenu(LinkaCopy.value("Medição")) {
            if center.isMeasuring {
                Button(LinkaCopy.value("Cancelar teste")) { coordinator.requestCancelMeasurement() }
                    .keyboardShortcut(".", modifiers: .command)
            } else {
                Button(LinkaCopy.value("Iniciar teste")) { coordinator.requestStartSpeedTest() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            Divider()
            Button(LinkaCopy.value("Excluir medição…")) { center.deleteRequest = true }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!center.canDelete)
        }

        CommandMenu(LinkaCopy.value("Ir")) {
            Button(LinkaCopy.value("Velocímetro")) { center.navigationRequest = .speedTest }
                .keyboardShortcut("1", modifiers: .command)
            Button(LinkaCopy.value("Histórico")) { center.navigationRequest = .history }
                .keyboardShortcut("2", modifiers: .command)
            if MinhaRedeAvailability.isEnabled {
                Button(LinkaCopy.value("inventory.title")) { center.navigationRequest = .myNetwork }
                    .keyboardShortcut("3", modifiers: .command)
            }
            if center.showsAssist || center.showsOptimization {
                Divider()
                if center.showsAssist {
                    Button("Assist") { center.navigationRequest = .assist }
                        .keyboardShortcut("4", modifiers: .command)
                }
                if center.showsOptimization {
                    Button(LinkaCopy.value("optimization.title")) { center.navigationRequest = .optimization }
                        .keyboardShortcut("5", modifiers: .command)
                }
            }
            Divider()
            Button(LinkaCopy.value("Último resultado")) { center.latestResultRequest = true }
                .keyboardShortcut("l", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Link(LinkaCopy.value("Como medimos"), destination: LinkaExternalLinks.howWeMeasure)
            Link(LinkaCopy.value("Suporte do Linka"), destination: LinkaExternalLinks.support)
            Link(LinkaCopy.value("Privacidade"), destination: LinkaExternalLinks.privacy)
            Link(LinkaCopy.value("Termos de Uso"), destination: LinkaExternalLinks.terms)
        }
    }
}
#endif
