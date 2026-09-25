import Foundation

#if canImport(DeviceCheck)
import DeviceCheck
#endif

#if canImport(UIKit)
import UIKit
#endif

/// The device families this availability check can distinguish, kept
/// independent of UIKit so the phone-only gate below is testable without a
/// device or the UIKit framework.
public enum NetscopeDeviceIdiom: Equatable, Sendable {
    case phone
    case other
}

#if canImport(UIKit)
/// Reads the real device idiom. iPad reports `.pad`, Mac Catalyst reports
/// `.mac`; both map to `.other` here.
enum NetscopeSystemDeviceIdiom {
    static var current: NetscopeDeviceIdiom {
        UIDevice.current.userInterfaceIdiom == .phone ? .phone : .other
    }
}
#endif

/// Consulta sem efeito colateral à disponibilidade do framework Apple.
///
/// Netscope é iPhone-only por decisão de produto: não há iPad físico para
/// gerar prova própria, então iPad e Mac (nativo ou Catalyst) permanecem
/// indisponíveis até existir essa prova, independentemente do que o
/// framework da Apple reportar. A composição ainda deve injetar um provider
/// que faça challenge, registro e assertion; esta consulta não cria chave,
/// não solicita rede e não oferece caminho degradado para iPad ou macOS.
public enum NetscopeSystemAppAttestAvailability {
    /// Testable core: phone-gating is pure and does not need UIKit or a
    /// device. The DeviceCheck half can only be verified on real hardware,
    /// same as before this change.
    static func isSupported(idiom: NetscopeDeviceIdiom) -> Bool {
        guard idiom == .phone else { return false }
        #if canImport(DeviceCheck)
        return DCAppAttestService.shared.isSupported
        #else
        return false
        #endif
    }

    public static var isSupported: Bool {
        #if canImport(UIKit)
        isSupported(idiom: NetscopeSystemDeviceIdiom.current)
        #else
        false // No UIKit: native macOS, never iPhone.
        #endif
    }
}
