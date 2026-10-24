import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
public struct MeasurementActiveSheet: View {
    @ObservedObject var viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 54

    public var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                // Animação central de ondas Wi-Fi com profundidade luminosa
                ZStack {
                    Circle()
                        .fill(WiFiCasaTheme.brandAccentSubtle)
                        .frame(width: 140, height: 140)

                    Circle()
                        .stroke(WiFiCasaTheme.brandAccent.opacity(0.25), lineWidth: 2)
                        .frame(width: 110, height: 110)

                    Image(systemName: "wifi")
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(WiFiCasaTheme.brandAccent)
                }
                .accessibilityHidden(true)

                VStack(spacing: 8) {
                    if let room = viewModel.activeMeasuringRoom {
                        Text(room.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(WiFiCasaTheme.textPrimary)
                    }

                    Text(viewModel.currentStep.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Barra de progresso nativa
                ProgressView(value: viewModel.measurementProgress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(WiFiCasaTheme.brandAccent)
                    .padding(.horizontal, 40)

                if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(WiFiCasaTheme.scoreFair)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                            .multilineTextAlignment(.center)

                        if viewModel.isPermissionDeniedError {
                            Button {
                                #if os(iOS)
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                                #endif
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "gear")
                                    Text("Abrir Ajustes")
                                }
                                .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(WiFiCasaTheme.brandAccent)
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 32)
                }

                Spacer()

                Button(role: .cancel) {
                    viewModel.cancelMeasurement()
                    dismiss()
                } label: {
                    Text("Cancelar Teste")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .background(WiFiCasaTheme.backgroundBase.ignoresSafeArea())
            .navigationTitle("Medição Ativa")
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") {
                        viewModel.cancelMeasurement()
                        dismiss()
                    }
                }
            }
        }
    }
}
