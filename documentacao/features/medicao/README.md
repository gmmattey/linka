# Medição da conexão

Estado do documento: vigente para a base WIP identificada abaixo; não atesta release.
Responsável: Codex principal; Camillo responde pelos limites do motor.
Última revisão: 2026-10-04 — leitura estática de motor, contrato, adapter e testes citados.
Base conferida: checkout `feat/macos-visual-direction-and-service-status`, HEAD `9eb1a094`, com alterações locais preexistentes. Não é retrato de main nem de produção.
Referências: [governança](../../GOVERNANCA_DOCUMENTAL.md), [arquitetura compartilhada](../../arquitetura/README.md), fontes abaixo.
Termos de busca: speed test, download, upload, ping, jitter, estabilidade, responsividade sob carga, GameLift, SpeedTestCore.

## Propósito e limites

Medir a conexão por ação da pessoa e apresentar os valores obtidos. O resultado principal continua sendo velocidade; interpretação pertence a [Insights](../insights/README.md) e [Assist](../assist/README.md). Não mede um jogo específico, não comprova causa raiz de roteador/operadora e não faz speed test no site institucional.

## Comportamento atual

O fluxo é `startTest → runTest → ping → download → upload → evidências finais → resultado → persistência`. O [SpeedTestViewModel](../../../aplicativo-ios/LinkaApp/Sources/Adapters/SpeedTestViewModel.swift) consome a stream do motor e faz a integração; a UI não implementa transferências.

| Situação | Comportamento observado no código | Recuperação/limite |
|---|---|---|
| Iniciar ou repetir | `startTest` limpa evidências da execução anterior, avança geração e suspende polling vivo | Nova execução não deve herdar resultado anterior |
| Sem rota no início | `runTest` publica `.error` com `.offline` | Nova tentativa por ação da pessoa |
| Medindo | Stream publica fase, progresso e métricas | Não há duração total fixa garantida |
| Falha fatal durante download/upload | `errorState(preserving:reason:)` mantém os fatos já capturados | Preservação em memória não significa gravação de resultado parcial |
| Cancelar ou entrar em background | Adapter cancela a task; `onTermination` cancela a task interna do motor | Não salva a execução cancelada como concluída; pode restaurar último snapshot válido |
| Trocar de conexão | `cancelForConnectionChange` interrompe e invalida contexto da execução | Não unir fases de redes diferentes |
| Terminar | `processResultState` compõe o resultado; o caminho `.done` não cancelado tenta salvar e atualiza widget | Falha de gravação é capturada e não derruba a medição |
| Permissão/contexto ausente | Dados de plataforma são opcionais | Não equivalem a zero nem impedem por si só a medição de banda |

### Metodologia conferida

- [SpeedTestEnvironment.cloudflare](../../../aplicativo-ios/LinkaEngine/Core/LoadResponsivenessMeasurement.swift) configura `speed.cloudflare.com/__down`, `__up` e HEAD em `__down?bytes=0`. `URLSessionSpeedTestTransport` usa sessão efêmera; a sonda tem timeout de 1 segundo. Isso descreve a configuração local, não disponibilidade atual da CDN.
- `performDetailedPingTest` executa 100 sondas HTTP sequenciais; com 1–2 falhas na janela inicial amplia para 300. Registra tentativas, sucessos, falhas, timeouts e maior sequência de falhas. O percentual representa falhas dessas sondas HTTP, não uma medição isolada de perda IP/ICMP.
- Baseline descarta até duas respostas iniciais, calcula estatísticas de latência e usa mediana quando disponível. Jitter deriva da diferença absoluta entre respostas consecutivas.
- Download usa quatro workers com chunks de 10 MB; upload, quatro workers com payload de 5 MB. `SpeedTestTiming.production` define 12–18 segundos por direção, warm-up de 2 segundos e mínimo útil de 10 segundos. `shouldStopPhase` considera convergência respeitando piso/teto; esses valores não são promessa de duração total ou precisão física.
- `runPhaseTimeBased`, `loadSaturation` e `loadIntegrity` compõem evidência por direção. Baseline e ambas as direções precisam sustentar a integridade válida. Uma baseline materialmente invertida pode receber uma remedição ociosa. Métricas de banda não se tornam inválidas só porque responsividade ficou inconclusiva.
- [GameLiftRegionalReferenceProbe.measure](../../../aplicativo-ios/LinkaEngine/Core/GameLiftRegionalReferenceProbe.swift) roda após as fases do teste formal, antes do resultado final. Locale ordena três candidatas do catálogo estático; há três sondas por candidata, mínimo de duas respostas para seleção, e três sondas de confirmação. O código usa UDP porta 7770 e exige eco idêntico do payload. Ausência de resposta é inconclusiva; não há fallback HTTP/ICMP. Compatibilidade real desse protocolo com o serviço não foi verificada nesta tarefa. Essa etapa roda no teste formal, não apenas quando alguém abre o detalhe Jogos.
- Enriquecimento de provedor usa `IPInfoOrgLookup`, com consulta a `ipinfo.io/json` e timeout próprio; DNS e localização/contexto têm caminhos separados. Essas chamadas são tráfego real potencial, não coleta comprovadamente anônima.

### Plataformas e experiência

O [pacote](../../../aplicativo-ios/LinkaEngine/Package.swift) declara iOS 16 e macOS 13 como mínimos da biblioteca; isso não determina sozinho o deployment target do app. iPhone/iPad e Mac consomem o mesmo motor. Disponibilidade de Wi-Fi/contexto depende dos adapters de plataforma e permissões já concedidas; não presumir RSSI ou banda no iPhone. Acesso de produto é definido por `LinkaEntitlementPolicy`, fora do motor.

Entradas visuais: [MainView](../../../aplicativo-ios/LinkaApp/Sources/UI/MainView.swift), resultado, detalhes, reteste e abertura pelo histórico. [Protótipo](../../design/prototipo/) e [Design System](../../design/design_system/) continuam referências compartilhadas. VoiceOver, Dynamic Type, teclado, reduzir movimento e destinos macOS não foram exercitados; esta revisão não aprova aparência.

## Mapa técnico e contratos

| Responsabilidade | Fonte e símbolos |
|---|---|
| Medição e ciclo de vida | [SpeedTestCore.swift](../../../aplicativo-ios/LinkaEngine/Core/SpeedTestCore.swift): `runTest`, `runPhaseTimeBased`, `performDetailedPingTest`, `errorState` |
| Transporte, ambiente e envelope interno | [LoadResponsivenessMeasurement.swift](../../../aplicativo-ios/LinkaEngine/Core/LoadResponsivenessMeasurement.swift): `SpeedTestTransport`, `SpeedTestEnvironment`, `EngineLoadResponsivenessEvidence` |
| Estado/falha do motor | [MeasurementState.swift](../../../aplicativo-ios/LinkaEngine/Core/MeasurementState.swift), [EngineFailureReason.swift](../../../aplicativo-ios/LinkaEngine/Core/EngineFailureReason.swift) |
| Modelo persistível | [NetworkMeasurement.swift](../../../aplicativo-ios/NetworkCore/Sources/NetworkMeasurement.swift): `NetworkMeasurementContract`, `PacketProbeEvidence`, `LoadResponsivenessEvidence`, `RegionalGameReference` |
| Conversão, save e retomada | [SpeedTestViewModel.swift](../../../aplicativo-ios/LinkaApp/Sources/Adapters/SpeedTestViewModel.swift): `update`, `processResultState`, `skipOrCancel`, `handleScenePhaseChange` |

O motor não depende de `NetworkCore` no seu manifest; o adapter converte tipos do engine para o contrato compartilhado. `schemaVersion` da medição e `methodologyVersion` dos envelopes têm papéis distintos. Ausência de envelope em registro antigo não prova integridade válida. Consulte a [arquitetura](../../arquitetura/README.md) para serialização e divergência do schema externo.

## Critérios de aceite e evidência estática

| ID | Cenário / resultado esperado | Fonte conferida em 2026-10-04, WIP `9eb1a094` |
|---|---|---|
| MED-01 | Offline gera erro tipado sem inventar medição | [SpeedTestCoreFailureTests](../../../aplicativo-ios/LinkaEngine/Tests/SpeedTestCoreFailureTests.swift), `test_runTest_offlineAtStart_yieldsSingleErrorStateAndFinishesWithoutThrowing` |
| MED-02 | Cancelar o consumidor cancela o produtor | [SpeedTestCoreCancellationTests](../../../aplicativo-ios/LinkaEngine/Tests/SpeedTestCoreCancellationTests.swift), `test_cancellingConsumingTask_cancelsInnerEngineTaskViaOnTermination` |
| MED-03 | Responsividade não usa apenas tráfego pré-warm-up | [SpeedTestCoreTests](../../../aplicativo-ios/LinkaEngine/Tests/SpeedTestCoreTests.swift), `testSaturationIsInsufficientWhenTrafficExistsOnlyBeforeWarmup`, `testLoadIntegrityRequiresBothSustainedDirectionsAndBaseline` |
| MED-04 | Falha de upload preserva download já obtido | [SpeedTestCoreFailureTests](../../../aplicativo-ios/LinkaEngine/Tests/SpeedTestCoreFailureTests.swift), `test_errorState_fatalFailureDuringUpload_preservesDownloadAlreadyMeasured` |
| MED-05 | Resultado não cancelado é convertido antes da persistência | Leitura de `startTest` e `processResultState`; [testes do adapter](../../../aplicativo-ios/LinkaApp/Tests/SpeedTestViewModelResultTimingTests.swift) são fonte para validação posterior |

Resultado desta revisão: caminhos e lógica acima identificados por leitura; testes presentes não foram executados. Não houve build, simulador, dispositivo físico, TestFlight, App Review ou consulta a produção. Comandos futuros, na raiz do repo e com toolchain Apple compatível: `swift test --package-path aplicativo-ios/LinkaEngine` e `swift test --package-path aplicativo-ios/NetworkCore`; alguns testes de DNS acessam rede.

## Mudanças em andamento e lacunas

As decisões de estabilidade/referência regional e responsividade sob carga antes reunidas em `.agents/plano.md` têm correspondência parcial no código descrito; esta migração não fecha seus aceites. A fonte antiga usava a expressão evidência v2, mas os tipos atuais declaram metodologia 1. O ledger atual aponta às frentes; as expectativas e lacunas desta medição ficam preservadas aqui e na arquitetura.

| Pendência | Responsável / evento | Fechamento necessário |
|---|---|---|
| `performDetailedPingTest` retorna latência/jitter 0 quando todas as sondas falham sem aborto fatal; diverge da regra ausência ≠ zero | Camillo + Pedro, próxima alteração do motor | Traçar efeito no adapter e decidir/cobrir tratamento sem valor inventado |
| GameLift usa eco próprio; ausência de prova de resposta física | Tito + Camillo, antes de afirmar referência regional operacional | Registro físico do protocolo, respostas, timeout e sandbox Mac assinado |
| Cancelamento, rede lenta, consumo de dados e saturação real não exercitados | Tito, antes da próxima release que inclua esta metodologia | Evidências por build em iPhone/Mac, Wi-Fi/celular, falha parcial e reteste |
| Contrato aceita `.partial`, mas o save automático examinado grava apenas `.done` não cancelado | Codex + Camillo, próxima revisão de resultado parcial | Documentar decisão de persistência e validar consumidor sem prometer histórico parcial automático |
| Resumo do widget converte upload/ping não positivos em ausência | Camillo, próxima mudança no compartilhamento de resultado | Conferir semântica de zero real e testes do resumo |

## Origem documental

As fontes anteriores foram substituídas conforme o [registro de migração](../../MIGRACAO.md). Expectativas não entregues e divergências permanecem neste documento; remoção de plano não significa aceite funcional concluído.
