import Foundation

#if canImport(DeviceCheck)
import DeviceCheck
#endif

/// Consulta sem efeito colateral à disponibilidade do framework Apple. A
/// composição ainda deve classificá-la como iPhone/iPad físico e injetar um
/// provider que faça challenge, registro e assertion; esta consulta não cria
/// chave, não solicita rede e não oferece caminho degradado para macOS.
public enum NetscopeSystemAppAttestAvailability {
    public static var isSupported: Bool {
        #if canImport(DeviceCheck)
        DCAppAttestService.shared.isSupported
        #else
        false
        #endif
    }
}
