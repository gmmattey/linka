---
name: theo-apple-testing
description: Seleciona e relata testes Apple proporcionais sem promover prova local a validação de produção.
---

# Theo Apple Testing

Comece com os pacotes/módulos e destinos realmente afetados. Rode o menor conjunto útil de `swift test`, XCTest/XCUITest ou `xcodebuild`; não invente cobertura nem trate simulador como aparelho para rede, câmera, permissões ou Wi‑Fi. Em UI, cubra resultado, erro, vazio, cancelamento e acessibilidade quando aplicável.

Reporte comando, destino/configuração, resultado, duração/artefato e lacunas. Diferencie teste de pacote, build de app, execução em Mac, simulador, dispositivo, TestFlight e App Review.
