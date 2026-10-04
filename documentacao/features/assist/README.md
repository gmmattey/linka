# Assist — entender a medição

Estado do documento: vigente para o WIP; serviço remoto e release não verificados.
Responsável: Codex principal; Camillo pelos contratos e Íris pela experiência.
Última revisão: 2026-10-04 — código de contexto, serviço, transporte, UI e testes citados.
Base conferida: `feat/macos-visual-direction-and-service-status`, HEAD `9eb1a094` + alterações locais.
Referências: [governança](../../GOVERNANCA_DOCUMENTAL.md), [arquitetura](../../arquitetura/README.md), [Netscope](../../arquitetura/NETSCOPE.md).
Termos de busca: Assist, NDS V2, relay, NetworkAssistContext, explicação, investigação local, Netscope.

## Propósito e limites

Explicar fatos de uma medição e contexto declarado pela pessoa, em superfície secundária. O motor mede; `NetworkAssist` valida contexto/resposta; `NetworkDiagnostics` adapta a chamada remota. O pacote Assist não busca histórico nem escolhe o plano de assinatura. Investigações locais de falha são uma capacidade separada do transporte remoto; indícios não provam causa raiz.

## Jornada, estados e plataformas

| Situação | Comportamento observado | Limite/recuperação |
|---|---|---|
| Entrada pela Home | Seleção de contexto e caminho de coleta nova antes da análise | `MainView.startAssistMeasurement` / `beginPendingAssistCollection` |
| Entrada por resultado | Existe `requestAssistFromResult` com `AssistEntryPoint.result(measurement)` | Não afirmar universalmente que toda entrada exige novo teste; ver divergência abaixo |
| Carregando | `AssistViewModel` usa estado `.loading` e consome stream | Evento final é validado; presença de stream não prova streaming HTTP real |
| Respondido | UI recebe texto, detalhes, recomendação/dimensões e procedência quando disponíveis | Referência a ID conhecido não comprova veracidade semântica de cada frase |
| Sem configuração/acesso | `notConfigured` / `notEntitled` | Estado de erro e recuperação explícita |
| HTTP/timeout/decode | API lança erro tipado; ViewModel apresenta erro e permite retry | Nenhuma prova de disponibilidade remota nesta revisão |
| Dados insuficientes/fora do escopo | Disposições `insufficientEvidence`, `requiresDiagnosis`, `unsupported` | Não substituir falta de evidência por zero |
| Falha do teste | `investigateFailure` pode produzir investigação local; `suggestedAction` retorna no máximo uma sugestão | Não depende de relay, não mede de novo por conta própria |

Entradas: [MainView](../../../aplicativo-ios/LinkaApp/Sources/UI/MainView.swift), [AssistProblemSelectionView](../../../aplicativo-ios/LinkaApp/Sources/UI/AssistProblemSelectionView.swift), [AssistView](../../../aplicativo-ios/LinkaApp/Sources/UI/AssistView.swift). iPhone/iPad e Mac compartilham serviço/contrato e usam adapters Apple. `AssistContainer.openAppSettings` só executa quando UIKit existe; no Mac nativo não há esse atalho implementado pelo método. Não prometer abertura de páginas privadas de Wi-Fi/DNS. Acesso passa por `EntitlementGatedNetworkAssistProvider`, usando a política central; promoção e compra não devem ser confundidas.

Referências visuais: [protótipo](../../design/prototipo/) e [Design System](../../design/design_system/). VoiceOver, Dynamic Type, teclado, estados vazios/erro e fechamento de sheets não foram exercitados; não há aprovação visual nesta entrega.

## Mapa técnico e fluxo

| Camada | Fonte e símbolos |
|---|---|
| Contexto do app | [AssistViewModel.swift](../../../aplicativo-ios/LinkaApp/Sources/Adapters/AssistViewModel.swift): `makeContext`, `load`, `retry` |
| Composição/configuração | [AssistContainer.swift](../../../aplicativo-ios/LinkaApp/Sources/Adapters/AssistContainer.swift): `configuration`, `makeAssistProvider`, `makeRulesProvider` |
| Gate de produto | [Entitlements.swift](../../../aplicativo-ios/LinkaModules/Sources/Entitlements.swift): `EntitlementGatedNetworkAssistProvider` |
| Contrato/validação | [NetworkAssist.swift](../../../aplicativo-ios/NetworkAssist/Sources/NetworkAssist.swift): `NetworkAssistService`, `NetworkAssistContext`, `NetworkAssistRequest`, `NetworkAssistResponse`, `NetworkAssistTransport` |
| HTTP e tradução | [BuildeaDiagnosticAPI.swift](../../../aplicativo-ios/NetworkDiagnostics/Sources/BuildeaDiagnosticAPI.swift), [BuildeaDiagnosticTransport.swift](../../../aplicativo-ios/NetworkDiagnostics/Sources/BuildeaDiagnosticTransport.swift) |
| Investigação local | [NetworkAssistInvestigation.swift](../../../aplicativo-ios/NetworkAssist/Sources/NetworkAssistInvestigation.swift): `NetworkAssistInvestigationEngine`; [AssistFailureSignalMapping.swift](../../../aplicativo-ios/LinkaApp/Sources/Adapters/AssistFailureSignalMapping.swift) |
| Sugestão/narrativa local | [NetworkAssistActionSuggestion.swift](../../../aplicativo-ios/NetworkAssist/Sources/NetworkAssistActionSuggestion.swift), [NetworkAssistStabilityNarrative.swift](../../../aplicativo-ios/NetworkAssist/Sources/NetworkAssistStabilityNarrative.swift) |

`NetworkMeasurement → AssistViewModel.makeContext → entitlement → NetworkAssistService → BuildeaDiagnosticTransport → BuildeaDiagnosticAPI → resposta validada → UI`.

### Contexto e guardrails

Defaults do serviço: pergunta até 500 caracteres, até 20 medições recentes, até 50 evidências e relato livre até 200 caracteres. São capacidades do contrato, não uma declaração do que o app envia. `makeContext` neste checkout ignora a lista recente recebida e define `recent = []`; leitura atual não transporta histórico silencioso por esse caminho. Evidências locais incluem medição atual, responsividade elegível, probes e referência regional quando presentes.

`NetworkAssistService` valida medição, fontes/IDs únicos e conhecidos, números finitos e resposta não vazia; `answered` exige evidência referenciada. A política `measurementUnderstanding` limita inferência causal e reparo. Isso é validação estrutural, não verificação factual completa do texto de IA. `streamAnswer` faz ponte para um único evento `.completed` quando o transport não implementa streaming real; propaga cancelamento à task.

O transporte remoto efetivo envia `currentMeasurement`, locale e contexto declarado ao builder. Objective/subcategory guiados têm prioridade; relato livre não se torna fato medido. As evidências locais aditivas não são automaticamente transmitidas como novos campos de NDS: não afirmar que o Worker já compreende probes regionais ou toda evidência de alta confiança.

### Configuração e backend

`assistUsesRemoteDiagnostic` consulta UserDefaults, depois Info.plist, com default `true`. `NDAssistRelayEndpoint` configura a URL; `LINKA_NDS_ENDPOINT` pode sobrescrevê-la no ambiente de execução. Default local: relay `linka-assist-relay.buildealabs.workers.dev/v2/assist`; timeout de 55 segundos. `transportAuth: .relay` não envia bearer token do cliente. Segredos de fornecedor não pertencem ao app; esta leitura não é auditoria de todo o bundle/servidor.

[NetworkDiagnosticsConfiguration](../../../aplicativo-ios/NetworkDiagnostics/Sources/NetworkDiagnosticsConfiguration.swift) deriva endpoint V2 substituindo `/v1/` quando aplicável. `BuildeaDiagnosticAPI.evaluate` faz POST JSON, interpreta HTTP não 2xx e envelope `error.code/message/retryable/request_id`, depois decodifica `NDSResponse`. Não há fallback de request para V1; o mapper ainda consegue ler campos de respostas legadas. `raw` e `explanation` têm papéis distintos; `steps` da recomendação são preservados quando usados.

**Limite observado:** `semCausaIdentificada == true` produz copy positiva no mapper atual. A ausência de causa identificada não é, por si, prova de saúde; essa escolha precisa de revisão semântica conjunta com o contrato remoto. Netscope é uma proposta separada nesta base, detalhada no [documento específico](../../arquitetura/NETSCOPE.md); não substitui automaticamente este caminho NDS.

## Critérios de aceite e evidência estática

| ID | Regra | Fonte conferida em 2026-10-04, WIP acima |
|---|---|---|
| AST-01 | Medição/contexto inválidos não chegam ao transport | [NetworkAssistTests](../../../aplicativo-ios/NetworkAssist/Tests/NetworkAssistTests.swift): `testInvalidMeasurementNeverReachesTransport`, `testEmptyAndOversizedQuestionsAreRejected` |
| AST-02 | Resposta não inventa ID de evidência e `answered` exige citação | Mesmo arquivo: `testProviderCannotInventEvidenceReference`, `testAnsweredResponseMustCiteEvidence` |
| AST-03 | Não configurado falha explicitamente | Mesmo arquivo: `testUnconfiguredTransportFailsClosed` |
| AST-04 | Stream valida resposta final e cancela transporte | Mesmo arquivo: `testStreamAnswerValidatesFinalResponseEvenForStreamingTransport`, `testStreamAnswerCancellationPropagatesToTransport` |
| AST-05 | Sem sinal suficiente não sugerir causa/ação local | [NetworkAssistInvestigationTests](../../../aplicativo-ios/NetworkAssist/Tests/NetworkAssistInvestigationTests.swift) e [NetworkAssistActionSuggestionTests](../../../aplicativo-ios/NetworkAssist/Tests/NetworkAssistActionSuggestionTests.swift) |
| AST-06 | Preservar semântica V2/locale/erros no adapter | [BuildeaDiagnosticTransportV2Tests](../../../aplicativo-ios/NetworkDiagnostics/Tests/BuildeaDiagnosticTransportV2Tests.swift) e [AssistViewModelTests](../../../aplicativo-ios/LinkaApp/Tests/AssistViewModelTests.swift); validação em execução pendente |

Todos são critérios e fontes estáticas, não testes aprovados nesta sessão. Nenhum teste/build/app/chamada remota executado. Validação futura na raiz: `swift test --package-path aplicativo-ios/NetworkAssist` e `swift test --package-path aplicativo-ios/NetworkDiagnostics`, depois teste de jornada na build pretendida. Produção, provider real e custo não foram consultados.

## Decisões preservadas e pendências

| Tema | Expectativa versus implementação | Responsável / evento / fechamento |
|---|---|---|
| Assist do agora | `plano-assist-agora.md` exigia nova medição em toda entrada e nenhum Assist de histórico; contexto atual exclui recentes, mas há entrada `.result(measurement)` | Íris + Camillo; próxima mudança da jornada; definir validade/reuso do resultado e testar cada entrada em iPhone/Mac |
| Histórico remoto antigo | `plano-valor-linka.md` registrava agregados de 30/7 dias; `makeContext` atual passa vazio | Codex; fechamento desta migração; comunicar estado atual e não reutilizar a alegação antiga |
| Sem causa identificada | Mapper transforma flag em leitura positiva | Íris + responsável NDS; antes de prometer diagnóstico saudável; contrato e testes distinguindo ausência de achado de insuficiência |
| Procedência | `formatProvenance` tem fallback textual “ChatGPT – Luna” sem modelLabel | Camillo; próxima revisão de atribuição; não apresentar provider/modelo não comprovado |
| Credencial histórica exposta | Plano de correções pedia revogação/rotação; composição atual relay não comprova a ação operacional | Codex; antes de encerrar pendência de segurança; evidência de revogação sem registrar segredo |
| Testes, UI e falha remota | Inspeção não cobre operação nem tradução real da resposta | Tito; antes da release afetada; build identificada, timeout/offline/locale/fechamento e acessibilidade |

Origem consolidada: `PLANO_NETWORK_ASSIST.md`, `plano-assist-agora.md`, `plano.md` (compatibilidade NDS), partes de `plano-valor-linka.md` e `plano-correcoes-produto.md`. A antiga fase “sem endpoint” é substituída pelo mapa de composição atual; números históricos de testes/publicação não foram transferidos como prova do WIP. Planos não foram marcados como entregues.
