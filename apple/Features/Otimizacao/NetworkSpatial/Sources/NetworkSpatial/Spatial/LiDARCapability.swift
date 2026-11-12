import Foundation

#if canImport(ARKit) && os(iOS)
import ARKit
#endif

#if canImport(RoomPlan) && os(iOS)
import RoomPlan
#endif

/// Verificação estática e determinística de disponibilidade do sensor LiDAR e da engine RoomPlan da Apple.
/// Totalmente seguro para execução no macOS (CLI `swift test`) e no simulador iOS sem crashes.
public enum LiDARCapability {
    /// Retorna `true` exclusivamente em dispositivos iOS físicos equipados com sensor LiDAR e suporte a RoomPlan.
    public static var isSupported: Bool {
        #if canImport(RoomPlan) && os(iOS) && !targetEnvironment(simulator)
        if #available(iOS 16.0, *) {
            return RoomCaptureSession.isSupported
        }
        #elseif canImport(ARKit) && os(iOS) && !targetEnvironment(simulator)
        return ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        #endif
        return false
    }
}
