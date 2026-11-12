import XCTest
@testable import LinkaEngine

/// Expert Mode: `SpeedTestCore.resolveDNS` é uma sondagem única, cronometrada,
/// separada da janela de 10 sondagens de `performPingTest`. Requer rede real
/// (mesma dependência de rede que os demais testes de integração deste alvo,
/// ver `SpeedTestCoreTests`).
final class SpeedTestCoreDNSResolutionTests: XCTestCase {

    func test_resolveDNS_validHost_returnsPositiveFiniteValue() async throws {
        let result = await SpeedTestCore.resolveDNS(host: "speed.cloudflare.com", timeoutMs: 5000)

        guard let result else {
            throw XCTSkip("Sem conectividade de rede neste ambiente de teste — não é possível validar o caminho de sucesso.")
        }

        XCTAssertTrue(result.isFinite)
        XCTAssertGreaterThan(result, 0)
    }

    func test_resolveDNS_unresolvableHost_returnsNilNeverZero() async {
        // TLD reservado por RFC 2606 para testes/documentação — nunca
        // resolve de verdade, então isto exercita a falha de resolução sem
        // depender de um servidor DNS que rejeite consultas de propósito.
        let result = await SpeedTestCore.resolveDNS(host: "this-host-does-not-exist.invalid", timeoutMs: 5000)

        XCTAssertNil(result)
    }

    // O caminho de timeout (`withTaskGroup` com uma `Task.sleep` corrida
    // contra a resolução real) não tem teste dedicado: sem injeção de um
    // resolvedor, qualquer timeout curto o bastante para ser determinístico
    // em CI também é curto o bastante para às vezes perder a corrida contra
    // uma resolução DNS local rápida (observado: resolução real completando
    // em ~1ms), tornando o teste inerentemente instável. O padrão
    // `withTaskGroup`/`Task.sleep` em si é idioma padrão de concorrência
    // Swift, não uma peça de lógica nova arriscada.
}
