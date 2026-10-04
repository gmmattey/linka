# Entender e comparar a conexão

Estado do documento: vigente para o checkout WIP; validação em execução pendente.
Responsável: Codex principal; Camillo pelos avaliadores, Íris pela interpretação apresentada.
Última revisão: 2026-10-04 — inspeção estática das fontes e testes citados.
Base conferida: `feat/macos-visual-direction-and-service-status`, HEAD `9eb1a094` + WIP, não main/produção.
Referências: [governança](../../GOVERNANCA_DOCUMENTAL.md), [arquitetura](../../arquitetura/README.md).
Termos de busca: adequação de uso, comparação, tendência, estabilidade, Home viva, telemetria, responsividade, caminho da conexão.

## Propósito e limites

Transformar fatos medidos em comparações e leituras de uso sem disputar com o resultado principal. A biblioteca não mede, não faz I/O e não consulta histórico por conta própria. Os adapters escolhem os registros e aplicam entitlement. Os avaliadores de caminho usam sinais indiretos; seus rótulos não comprovam causa raiz de equipamento ou operadora.

## Comportamento atual e mapa técnico

| Capacidade | Regra atual | Fonte e símbolo |
|---|---|---|
| Comparação | Delta absoluto e percentual quando definido; download/upload preferem maior, demais métricas menor | [NetworkInsights.swift](../../../aplicativo-ios/NetworkInsights/Sources/NetworkInsights.swift), `MetricComparator.compare` |
| Estatística | Quantidade, mínimo, máximo, média, mediana, desvio padrão populacional e variação; ausências excluídas | Mesmo arquivo, `BasicNetworkInsightsAnalyzer.summarize` |
| Tendência | Regressão pelo tempo real; default mínimo 3 amostras, limiar de estabilidade 3% | Mesmo arquivo, `NetworkInsightsConfiguration`, `trend` |
| Períodos | Compara médias das coleções fornecidas | `comparePeriods` no mesmo arquivo |
| Redes | Agrupa por conexão + SSID de Wi-Fi quando presente, com fallback a `networkIdentifier`; default mínimo 5 registros | [NetworkGroupInsights.swift](../../../aplicativo-ios/NetworkInsights/Sources/NetworkGroupInsights.swift), `NetworkGroupInsightsAnalyzer` |
| Horários | Janela default de 2h, mínimo 5 dias no histórico e 3 dentro da janela, degradação mínima 20% | [NetworkTimeWindowPattern.swift](../../../aplicativo-ios/NetworkInsights/Sources/NetworkTimeWindowPattern.swift), `NetworkTimeWindowPatternDetector.detect` |
| Uso formal | `adequate`, `limited`, `notAssessed`, com métrica limitante | [UsageSuitability.swift](../../../aplicativo-ios/NetworkInsights/Sources/UsageSuitability.swift), `UsageSuitabilityEvaluator` |
| Responsividade | Categoria pela pior diferença absoluta carga−repouso: até 30 ms alta, até 100 ms média, acima baixa | [LoadResponsiveness.swift](../../../aplicativo-ios/NetworkInsights/Sources/LoadResponsiveness.swift), `LoadResponsivenessEvaluator` |
| Caminho | Etapas aparelho/Wi-Fi/roteador/operadora/Internet, `unavailable` quando sem sinal necessário | [ConnectionPath.swift](../../../aplicativo-ios/NetworkInsights/Sources/ConnectionPath.swift), `ConnectionPathEvaluator` |

### Regras formais de uso

São parâmetros do código, não garantias de um serviço externo. Igualdade segue as comparações implementadas; o caso 4K é deliberadamente distinto.

| Uso | Condições atuais para adequação |
|---|---|
| Chamada de vídeo | Evidência de probes concluída; upload ≥3 Mbps; latência em repouso e pior latência confiável sob carga ≤150 ms; jitter ≤30 ms; perda ≤2% |
| Jogo online | Probes concluídos; referência regional com status medido e P50 ≤50 ms; ambas as latências confiáveis sob carga presentes e pior ≤50 ms; jitter ≤30 ms; perda ≤1% |
| Streaming HD | Download ≥5 Mbps |
| Streaming 4K | Download **>25 Mbps** e perda ≤2% |
| Upload/trabalho | Upload ≥5 Mbps e jitter ≤40 ms; se latência presente, ≤200 ms; perda ≤2% |

Vídeo/jogos sem as evidências obrigatórias retornam `notAssessed`. `packetLossOutcome` usa `limited` quando perda está ausente; não interpreta ausência como 0%. `trustedLoadedLatencies` impede consumo de envelope inconclusivo; sem envelope, existe fallback escalar legado. `evaluateHighConfidence` exige envelope válido; `evaluateForConsumer` admite legado. Não apresentar esses dois níveis como equivalentes.

## Home e telemetria ao vivo

Esta é observação efêmera, diferente do resultado formal de [medição](../medicao/README.md). A decisão preservada da Home é uma fonte de leitura (`liveUsageReport`) para hero e usos, sem teste de banda contínuo, sem armazenar telemetria no histórico e sem concluir qualidade por três respostas boas.

Fluxo conferido: `SpeedTestViewModel.startLivePolling → performLivePing → LiveTelemetryCollector.recordProbe → snapshot → LiveUsageSuitabilityEvaluator → liveUsageReport`.

- [SpeedTestViewModel](../../../aplicativo-ios/LinkaApp/Sources/Adapters/SpeedTestViewModel.swift) espera 3 segundos entre ciclos, só coleta quando `!isTesting`, consulta `apple.com/library/test/success.html`, aceita HTTP 200..<400 e registra falha como amostra `nil`. Essa duração é RTT HTTP, embora o campo visual interno se chame `liveDnsLatencyMs`; não é DNS isolado.
- [SlidingWindowTelemetryBuffer](../../../aplicativo-ios/LinkaModules/Sources/LiveTelemetryCollector.swift) mantém até 8 amostras, remove antigas ao acrescentar (limite default 30 segundos), calcula mediana, diferença média absoluta entre RTTs válidos e percentual de falhas. O comentário menciona RFC 3550, mas a implementação examinada é essa média; não afirmar conformidade com estimador RTP sem revisão.
- [LiveUsageSuitabilityEvaluator](../../../aplicativo-ios/NetworkInsights/Sources/LiveUsageSuitability.swift) mantém todos os usos sem avaliação antes de 5 amostras. Perda repetida exige pelo menos duas falhas estimadas na janela. Confiança distingue `liveTelemetry`, `historicalBaselineInferred` e `insufficientData`.
- Throughput vem de teste completo no mesmo `wifiContext.ssid`, com upload e download positivos e até quatro horas. Não busca pelo nome do provedor. `resetLiveUsageState` e `reconcileLiveUsageNetworkIdentity` limpam buffer, baseline e relatório na invalidação; retorno assíncrono só é aceito se o SSID ainda corresponder.
- A implementação de `LiveTelemetryCollector.start` tem defaults próprios (4 segundos); não confundir essa API com o loop de 3 segundos efetivamente composto pelo ViewModel.
- RSSI/taxa de link no Mac dependem do contexto de plataforma. Sem identidade Wi-Fi não há baseline de banda; celular não ganha velocidade estimada. O adapter passa `isConstrained: false` neste caminho; não é confirmação de que o sistema esteja fora de modo restrito.

### Estados e plataformas

| Estado | Significado / recuperação |
|---|---|
| Aquecendo ou dados insuficientes | Aguardar amostras; não exibir conclusão formal |
| Sem baseline | Medição explícita pode fornecer throughput; não estimar banda pelo ping |
| Offline/troca de rede/background | Invalidar fatos vivos e reiniciar aquecimento conforme ciclo de vida |
| Medindo | Polling não deve competir com o motor |
| Histórico insuficiente | `insufficientData`/`insufficientSamples`, diferente de `noPatternDetected` |
| Sem acesso à análise | Decorator retorna `notEntitled`; cálculo puro não define plano comercial |

iPhone/iPad/Mac usam a biblioteca [NetworkInsights](../../../aplicativo-ios/NetworkInsights/Package.swift). [EntitlementGatedNetworkInsightsAnalyzer](../../../aplicativo-ios/LinkaModules/Sources/Entitlements.swift) protege a análise que ele envolve; isso não prova que todo avaliador de uso seja Plus. Superfícies: [HistoryView](../../../aplicativo-ios/LinkaApp/Sources/UI/HistoryView.swift), [UsageDiagnosticsView](../../../aplicativo-ios/LinkaApp/Sources/UI/UsageDiagnosticsView.swift), [ConnectionPathView](../../../aplicativo-ios/LinkaApp/Sources/UI/ConnectionPathView.swift), [MainView](../../../aplicativo-ios/LinkaApp/Sources/UI/MainView.swift), [NetworkStabilityPatternsViewModel](../../../aplicativo-ios/LinkaApp/Sources/Adapters/NetworkStabilityPatternsViewModel.swift). Visual, VoiceOver, teclado e Dynamic Type não foram validados; [Design System](../../design/design_system/) e [protótipo](../../design/prototipo/) seguem como referências.

## Integrações e impacto

[Histórico](../historico/README.md) fornece registros; `NetworkInsights` depende apenas de `NetworkCore` no manifest. [Assist](../assist/README.md) recebe fatos calculados pelos adapters, não consulta Insights dentro da biblioteca `NetworkAssist`. Alterar métricas/limiares afeta resultado, detalhe, histórico, Home, contexto local do Assist e consumidores de otimização. Não persistir interpretações como se fossem métricas originais.

## Critérios de aceite e evidência

| ID | Critério | Fonte estática, WIP de 2026-10-04 |
|---|---|---|
| INS-01 | Ausência não entra em média como zero; tendência depende de amostras/tempo | [NetworkInsightsTests](../../../aplicativo-ios/NetworkInsights/Tests/NetworkInsightsTests.swift) e `BasicNetworkInsightsAnalyzer` |
| INS-02 | Envelope inconclusivo não gera responsividade confiável | [LoadResponsivenessTests](../../../aplicativo-ios/NetworkInsights/Tests/LoadResponsivenessTests.swift), `evaluateHighConfidence`/`evaluateForConsumer` |
| INS-03 | Distinguir padrões ausentes de amostras insuficientes | [NetworkTimeWindowPatternTests](../../../aplicativo-ios/NetworkInsights/Tests/NetworkTimeWindowPatternTests.swift) e detector |
| INS-04 | Home respeita aquecimento e baseline da mesma rede | [LiveTelemetryCollectorTests](../../../aplicativo-ios/LinkaModules/Tests/LiveTelemetryCollectorTests.swift), [LiveUsageSuitabilityTests](../../../aplicativo-ios/NetworkInsights/Tests/LiveUsageSuitabilityTests.swift) e adapter |
| INS-05 | Limites de vídeo/jogos e 4K correspondem à implementação | [UsageSuitabilityTests](../../../aplicativo-ios/NetworkInsights/Tests/UsageSuitabilityTests.swift); existe divergência abaixo, não suite aprovada |

Nenhum teste foi executado. Evidência é leitura do código e de cobertura declarada nos testes, não resultado de execução. Validação futura na raiz: `swift test --package-path aplicativo-ios/NetworkInsights` e `swift test --package-path aplicativo-ios/LinkaModules`. Build, simulação, dispositivo e produção permanecem não verificados.

## Expectativas preservadas, divergências e pendências

| Tema | Expectativa versus implementação | Responsável / evento / fechamento |
|---|---|---|
| Jogos | `testOnlineGamingFallsBackToLatencyMsWhenLoadedLatencyIsMissing` espera adequado sem carga; código exige ambas as direções e probes/referência | Camillo + Pedro; próxima mudança do avaliador; reconciliar fixtures, regra e execução dos testes |
| 4K | Plano geral menciona igualdade adequada; código e teste específico exigem >25 Mbps | Íris + Camillo; antes de modificar limiares; decisão explícita e teste de fronteira |
| Caminho da conexão | Etapa roteador atribui `likelyProblem` por jitter/carga sem sonda do gateway | Íris + Camillo; próxima revisão dessa superfície; linguagem não causal e critérios sustentados por evidência |
| Redes legadas | Fallback `networkIdentifier` pode ser provedor, não identidade inequívoca da rede | Camillo; próxima alteração de agrupamento; definir separação de legado e testar redes distintas do mesmo provedor |
| Home | Decisão deseja limpar dados na troca/background, pausa na medição e divulgação progressiva | Tito; antes da release da Home; execução física, acessibilidade e estados 0–8 amostras por build |
| Responsividade | Plano fala em v2; tipos atuais usam metodologia 1, com caminho escalar legado | Camillo; próxima alteração do contrato; nomenclatura e compatibilidade formalizadas |

Origem: `PLANO_NETWORK_INSIGHTS.md`, partes Home/estabilidade/responsividade de `.agents/plano.md`, `plano-valor-linka.md`. O antigo limite “somente estatística, nenhuma integração com interface” não descreve mais a biblioteca/composição atual. Não são importadas alegações históricas de testes verdes como evidência do WIP.
