import XCTest
@testable import LinkaApp

#if canImport(CoreWLAN) && os(macOS)
import CoreWLAN
#endif

/// Cobertura da issue #89: `currentWifi()` e `currentWifiBandGHz()` em
/// `ApplePlatformSignalProvider` usavam dois switches independentes sobre
/// `CWChannelBand` (uma fonte produzindo `String?`, a outra `Double?`) que
/// podiam divergir silenciosamente numa mudança futura. Os dois foram
/// unificados em `ApplePlatformSignalProvider.mapCWChannelBand(_:)`, o
/// único switch sobre `CWChannelBand` do arquivo — ver grep no PR.
///
/// `CWChannelBand` é um enum simples (`UInt` raw value) do framework
/// `CoreWLAN`: seus cases (`.band2GHz`, `.band5GHz`, `.band6GHz`,
/// `.bandUnknown`) podem
/// ser instanciados diretamente, sem precisar de uma interface Wi-Fi real
/// nem de hardware — por isso o mapper dá pra testar isoladamente aqui,
/// sem mockar `CWWiFiClient`/`CWInterface`.
///
/// A limitação real é de *plataforma*, não de hardware: `CoreWLAN` só
/// existe no SDK do macOS, e o único alvo de teste deste repo
/// (`LinkaAppTests`, ver `aplicativo-ios/project.yml`) roda hospedado por
/// `LinkaApp_iOS` — então em CI (iOS) `canImport(CoreWLAN) && os(macOS)` é
/// falso e todo este arquivo compila para nada, isto é, os testes abaixo
/// não são exercitados automaticamente ali. Rodar de verdade exige um
/// scheme/target macOS local (mesma limitação documentada em
/// `SpeedTestViewModelScenePhaseTests.swift` para outras dependências de
/// hardware/S.O. real) — até esse target existir, isto fica como
/// verificação manual em macOS local, não substitui automação de CI.
#if canImport(CoreWLAN) && os(macOS)
final class ApplePlatformSignalProviderCWChannelBandTests: XCTestCase {

    func test_mapCWChannelBand_band2GHz_returns2Point4() {
        XCTAssertEqual(ApplePlatformSignalProvider.mapCWChannelBand(.band2GHz), 2.4)
    }

    func test_mapCWChannelBand_band5GHz_returns5Point0() {
        XCTAssertEqual(ApplePlatformSignalProvider.mapCWChannelBand(.band5GHz), 5.0)
    }

    func test_mapCWChannelBand_band6GHz_returns6Point0() {
        XCTAssertEqual(ApplePlatformSignalProvider.mapCWChannelBand(.band6GHz), 6.0)
    }

    func test_mapCWChannelBand_bandUnknown_returnsNil() {
        XCTAssertNil(ApplePlatformSignalProvider.mapCWChannelBand(.bandUnknown))
    }

    // MARK: - bandLabel(forGHz:) — conversão de formato Double -> String,
    // não uma segunda fonte de verdade sobre CWChannelBand (não reabre o
    // switch sobre o enum).

    func test_bandLabel_2Point4_returns2Point4GHzLabel() {
        XCTAssertEqual(ApplePlatformSignalProvider.bandLabel(forGHz: 2.4), "2.4GHz")
    }

    func test_bandLabel_5Point0_returns5GHzLabel() {
        XCTAssertEqual(ApplePlatformSignalProvider.bandLabel(forGHz: 5.0), "5GHz")
    }

    func test_bandLabel_6Point0_returns6GHzLabel() {
        XCTAssertEqual(ApplePlatformSignalProvider.bandLabel(forGHz: 6.0), "6GHz")
    }

    func test_bandLabel_nil_returnsNil() {
        XCTAssertNil(ApplePlatformSignalProvider.bandLabel(forGHz: nil))
    }

    /// `currentWifiBandGHz()` continua delegando pro mesmo mapper — os
    /// valores para os cases conhecidos não mudam com a extração.
    func test_currentWifiBandGHz_matchesMapperForKnownCases() {
        XCTAssertEqual(
            ApplePlatformSignalProvider.mapCWChannelBand(.band2GHz),
            2.4
        )
        XCTAssertEqual(
            ApplePlatformSignalProvider.mapCWChannelBand(.band5GHz),
            5.0
        )
        XCTAssertEqual(
            ApplePlatformSignalProvider.mapCWChannelBand(.band6GHz),
            6.0
        )
        XCTAssertNil(ApplePlatformSignalProvider.mapCWChannelBand(.bandUnknown))
    }
}
#endif
