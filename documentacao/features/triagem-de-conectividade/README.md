# Triagem de conectividade

Estado: vigente como descrição estática.
Responsável: orquestrador; Camillo para contrato das sondas.
Última revisão: 2026-10-04 — serviço, classificador e entradas de UI.
Base conferida: WIP sobre `9eb1a09412db5279424adfb4a68a48e943eea18e`.
Referências: [serviço/classificador](../../../aplicativo-ios/NetworkConnectivityTriage/Sources/NetworkConnectivityTriage.swift), [tela](../../../aplicativo-ios/LinkaApp/Sources/UI/ConnectivityTriageView.swift).
Termos de busca: offline, connectionLost, portal cativo, DNS, reteste.

## Propósito

Após falha de conexão, mostrar o que o aparelho consegue observar e permitir retestar. Não atribuir causa ao roteador ou provedor por dedução. É uma superfície de recuperação separada de medição e Assist, sem diagnóstico por IA.

## Comportamento e estados

[MainView](../../../aplicativo-ios/LinkaApp/Sources/UI/MainView.swift) e [MacMainView](../../../aplicativo-ios/LinkaApp/Sources/UI/MacMainView.swift) abrem a sheet de triagem. A tela mostra progresso, relatório, indisponibilidade e reteste. `NetworkConnectivityTriageService.run` lê o caminho de rede; só sonda HTTPS quando o caminho está satisfeito.

| Observação | Resultado do classificador |
|---|---|
| Caminho indisponível | `noNetworkPath` |
| Caminho exige conexão | `inconclusive` |
| Ao menos uma sonda bem-sucedida | `internetReachable` |
| Todas as sondas falham na resolução de nome | `dnsResolutionUnavailable` |
| Redirecionamento ou resposta inesperada | `captivePortalSuspected` |
| Timeout/falha sem evidência suficiente | `inconclusive` |

Portal cativo permanece suspeita. Um sucesso demonstra acesso ao endpoint naquele instante, não saúde de toda a Internet. A UI oferece nova medição; não altera DNS nem configura equipamentos.

## Mapa técnico, dados e limites

`NWConnectivityPathProvider` usa Network; `URLSessionConnectivityHTTPProbe` usa GET em sessão efêmera, cookies desabilitados, cache ignorado e timeout de requisição de 5 s. Redirecionamentos são bloqueados pelo delegate. Os endpoints padrão são `/v1/health` e `/v1/version` do host NDS declarado no código; não é chamada ao avaliador/IA. O serviço usa task group e verificações de cancelamento.

O relatório contém outcome e snapshot de caminho. Não há repositório ou persistência no serviço/tela examinados. Chamadas HTTP de sondagem continuam existindo: “local” não significa “sem rede”. A tela trata cancelamento e erro; não documentamos comportamento de background como validado sem execução.

| Plataforma | Fonte | Limite de evidência |
|---|---|---|
| iPhone/iPad | MainView e ConnectivityTriageView | Entrada estática inspecionada; layout/VoiceOver não executados |
| Mac | MacMainView e mesma sheet | Entrada estática inspecionada; navegação real não executada |

## Aceite e validação

| ID | Cenário e resultado esperado | Evidência existente |
|---|---|---|
| TRI-01 | Sem caminho: não sondar endpoints | Guarda do serviço inspecionada |
| TRI-02 | Evidência insuficiente: inconclusivo | Classificador inspecionado |
| TRI-03 | Redirecionamento: suspeita, sem causa definitiva | Delegate/classificador/copy da tela inspecionados |
| TRI-04 | Reteste usa fluxo normal do app | Callbacks de MainView/MacMainView inspecionados |

[Testes do pacote](../../../aplicativo-ios/NetworkConnectivityTriage/Tests/NetworkConnectivityTriageTests.swift) existem; não foram executados. Procedimento futuro na raiz: `swift test --package-path aplicativo-ios/NetworkConnectivityTriage`. Não houve sondagem real, build, teste visual ou físico nesta revisão.

## Pendências

| Pendência | Responsável | Evento | Fechamento |
|---|---|---|---|
| Offline, timeout, cancelamento, background e reteste nos três destinos | Tito/executor | Próxima alteração ou release relevante | Execução identificando build, rede e resultado |
| VoiceOver, texto ampliado e adaptação da sheet | Íris/Tito | Próxima revisão visual | Evidência na build pretendida por destino |
