import SwiftUI

/// Folha de introdução com orientações preparatórias para escaneamento 3D via Apple RoomPlan / LiDAR.
@available(iOS 17.0, macOS 14.0, *)
public struct RoomScanIntroSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showingLiDARUnavailable: Bool = false

    public let onStartScanning: () -> Void
    public let onOpenManualEditor: () -> Void

    public init(
        onStartScanning: @escaping () -> Void,
        onOpenManualEditor: @escaping () -> Void = {}
    ) {
        self.onStartScanning = onStartScanning
        self.onOpenManualEditor = onOpenManualEditor
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Hero
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(WiFiCasaTheme.backgroundRaised)
                                .frame(width: 80, height: 80)

                            Image(systemName: "viewfinder")
                                .font(.largeTitle.weight(.semibold))
                                .foregroundStyle(WiFiCasaTheme.brandAccent)
                        }
                        .padding(.top, 8)

                        Text(SpatialCopy.value("spatial.scan.introTitle", defaultValue: "Como escanear sua casa"))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(WiFiCasaTheme.textPrimary)

                        Text(SpatialCopy.value("spatial.scan.introSubtitle", defaultValue: "Gere uma planta tridimensional precisa em menos de 2 minutos utilizando os sensores do iPhone Pro."))
                            .font(.subheadline)
                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Card com 3 Dicas de Ouro (Camada 1 #1C1C1E, sem bordas)
                    VStack(alignment: .leading, spacing: 18) {
                        instructionRow(
                            number: "1",
                            icon: "lightbulb.fill",
                            title: SpatialCopy.value("spatial.scan.tip1Title", defaultValue: "Boa Iluminação"),
                            description: SpatialCopy.value("spatial.scan.tip1Desc", defaultValue: "Acenda as luzes dos cômodos para ajudar os sensores ópticos e de profundidade a mapear os cantos.")
                        )

                        instructionRow(
                            number: "2",
                            icon: "door.left.hand.open",
                            title: SpatialCopy.value("spatial.scan.tip2Title", defaultValue: "Abra as Portas"),
                            description: SpatialCopy.value("spatial.scan.tip2Desc", defaultValue: "Mantenha as portas internas abertas para que o sistema identifique a transição e limites entre os cômodos.")
                        )

                        instructionRow(
                            number: "3",
                            icon: "figure.walk",
                            title: SpatialCopy.value("spatial.scan.tip3Title", defaultValue: "Caminhada Calma"),
                            description: SpatialCopy.value("spatial.scan.tip3Desc", defaultValue: "Caminhe suavemente pelo perímetro de cada cômodo, apontando a câmera para paredes, quinas e chão.")
                        )
                    }
                    .padding(18)
                    .background(WiFiCasaTheme.backgroundRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 16)

                    Spacer(minLength: 16)

                    // CTA Primário
                    VStack(spacing: 12) {
                        Button {
                            handleStartScanTap()
                        } label: {
                            HStack(spacing: 8) {
                                Spacer()
                                Image(systemName: "camera.viewfinder")
                                    .font(.headline)
                                Text(SpatialCopy.value("spatial.scan.start", defaultValue: "Iniciar Escaneamento"))
                                    .font(.headline)
                                    .fontWeight(.bold)
                                Spacer()
                            }
                            .frame(minHeight: 44) // A11y Touch Target
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(WiFiCasaTheme.brandAccent)

                        Button(SpatialCopy.value("spatial.scan.manualEditor", defaultValue: "Usar Editor 2D Manual")) {
                            dismiss()
                            onOpenManualEditor()
                        }
                        .font(.footnote)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                        .frame(minHeight: 44)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .background(WiFiCasaTheme.backgroundBase.ignoresSafeArea())
            .navigationTitle(SpatialCopy.value("spatial.scan.prepareTitle", defaultValue: "Preparar Escaneamento"))
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(SpatialCopy.value("spatial.common.cancel", defaultValue: "Cancelar")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingLiDARUnavailable) {
                LiDARUnavailableSheet(onOpenManualEditor: {
                    dismiss()
                    onOpenManualEditor()
                })
            }
        }
    }

    private func handleStartScanTap() {
        if !LiDARCapability.isSupported {
            showingLiDARUnavailable = true
            return
        }

        dismiss()
        onStartScanning()
    }

    private func instructionRow(
        number: String,
        icon: String,
        title: String,
        description: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(WiFiCasaTheme.backgroundOverlay)
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.body.weight(.bold))
                    .foregroundStyle(WiFiCasaTheme.brandAccent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("\(number). \(title)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(WiFiCasaTheme.textPrimary)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(WiFiCasaTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    if #available(iOS 17.0, macOS 14.0, *) {
        RoomScanIntroSheet(
            onStartScanning: {},
            onOpenManualEditor: {}
        )
        .preferredColorScheme(.dark)
    }
}
