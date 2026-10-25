import SwiftUI

/// Folha apresentada quando o dispositivo não suporta o sensor LiDAR / Apple RoomPlan.
/// Oferece fallback gracioso para o Editor 2D manual sem frustração do usuário.
@available(iOS 17.0, macOS 14.0, *)
public struct LiDARUnavailableSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let onOpenManualEditor: () -> Void

    public init(onOpenManualEditor: @escaping () -> Void = {}) {
        self.onOpenManualEditor = onOpenManualEditor
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                ContentUnavailableView(
                    SpatialCopy.value("spatial.lidar.unavailableTitle", defaultValue: "Sensor LiDAR Não Disponível"),
                    systemImage: "viewfinder.trianglebadge.exclamationmark",
                    description: Text(SpatialCopy.value("spatial.lidar.unavailableDesc", defaultValue: "Este dispositivo não possui o sensor de escaneamento 3D exclusivo dos modelos iPhone e iPad Pro.\n\nVocê pode criar, organizar e dimensionar todos os cômodos da sua residência com nosso Editor 2D manual!"))
                )
                .foregroundStyle(WiFiCasaTheme.textPrimary)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        dismiss()
                        onOpenManualEditor()
                    } label: {
                        HStack {
                            Spacer()
                            Label(SpatialCopy.value("spatial.scan.manualEditor", defaultValue: "Usar Editor 2D Manual"), systemImage: "pencil.and.ruler.fill")
                                .font(.headline)
                                .fontWeight(.bold)
                            Spacer()
                        }
                        .frame(minHeight: 44) // A11y Touch Target
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(WiFiCasaTheme.brandAccent)

                    Button(SpatialCopy.value("spatial.common.close", defaultValue: "Fechar")) {
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundStyle(WiFiCasaTheme.textSecondary)
                    .frame(minHeight: 44)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .background(WiFiCasaTheme.backgroundBase.ignoresSafeArea())
            .navigationTitle(SpatialCopy.value("spatial.lidar.navTitle", defaultValue: "Escaneamento Espacial"))
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(SpatialCopy.value("spatial.common.close", defaultValue: "Fechar")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    if #available(iOS 17.0, macOS 14.0, *) {
        LiDARUnavailableSheet()
            .preferredColorScheme(.dark)
    }
}
