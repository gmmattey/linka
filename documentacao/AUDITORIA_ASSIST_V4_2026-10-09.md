# Auditoria estática — Assist Contextual V4 (09/10/2026)

## Escopo e limite
Inspeção do branch padrão via GitHub, sem build, testes de runtime, acesso ao Worker ou confirmação da build publicada. Evidência principal: `aplicativo-ios/LinkaApp/Sources/Adapters/AssistViewModel.swift`, `aplicativo-ios/LinkaApp/Sources/UI/AssistView.swift`, `AssistProblemSelectionView.swift`, `NetworkAssist/Sources/NetworkAssist.swift`, `LinkaApp/Sources/UI/MyNetworkView.swift`, `project.yml`, `documentacao/ARQUITETURA.md`. A auditoria não certifica integralmente as fases 1–3.

## Achados confirmados
1. **Bloqueador:** `AssistViewModel.load` exige `currentMeasurement`; sem ela retorna `assist.noMeasurement`. Uma consultoria aberta sem teste não funciona no contrato atual. V4 precisa admitir contexto sem medição e preservar caminho de diagnóstico existente.
2. **Bloqueador:** `NetworkAssistContext` e `NetworkAssistRequest` exigem `currentMeasurement: NetworkMeasurement`; não possuem campos tipados para plano, equipamentos, conexões, sessão, consentimento e perguntas de seguimento. Criar versão nova de contrato e migração, sem quebrar NDS v2.
3. **Alto:** `AssistViewModel.makeContext` define `let recent: [NetworkMeasurement] = []` apesar de receber `recentMeasurements`; a escolha atual impede aproveitar histórico no Assist. Não remover guarda indiscriminadamente: V4 precisa elegibilidade temporal, ambiente/rede e consentimento.
4. **Alto:** `AssistViewModel.State` contém apenas idle/loading/success/error; não modela perguntas adaptativas, aguardar teste, ação, reteste, retomada. Implementar orquestrador #320.
5. **Alto:** `NetworkAssistPolicy.measurementUnderstanding` define `observationalOnly=true`, `mayInferRootCause=false`, `mayRecommendRepair=false`, `mustGroundInProvidedData=true`. É correto para interpretação de medição, mas insuficiente para orientações passo a passo V4; criar política específica para orientações seguras sem permitir alteração automática nem alegações de causa raiz.
6. **Aproveitável:** `NetworkAssistProviding.streamAnswer`, estados de disposition, evidências e respostas estruturadas já existem. `AssistProblemSelectionView` já aceita `reportedProblem` livre (até 200 caracteres) e categorias; isso não equivale a chat multi-turno.
7. **Aproveitável:** `MyNetworkView` usa `LinkaInventoryStore`, `RegisteredNetworkDevice`, `DeviceConnection`, plano ativo e Ambientes, indicando UI integrada das fases anteriores no branch padrão. Isso **não prova** que todos os dados sejam persistidos corretamente nem que estejam disponíveis ao Assist.
8. **Integração real:** `project.yml` declara endpoint de relay `https://linka-assist-relay.buildealabs.workers.dev/v2/assist`; não foi auditado backend remoto nem seu suporte a sessão/novo schema.
9. **Risco de fonte documental:** `documentacao/ARQUITETURA.md` e `PRODUTO.md` são revisões de 04/10 e descrevem foco em speed test. A V4 deve reconciliar direção e documentação oficial após decisão de produto.

## Matriz de prontidão
| Capacidade | Estado comprovado | Gap V4 |
|---|---|---|
| Diagnóstico com medição | Implementação estática identificada | Preservar compatibilidade |
| Texto livre inicial | Implementado como `reportedProblem` | Não é conversa aberta contínua |
| Streaming de resposta | Loop assíncrono presente | UI/contrato de turnos e cancelamento não confirmados |
| Equipamentos/plano/topologia | UI `MyNetworkView` identificada | Projeção autorizada para Assist não demonstrada |
| Histórico para Assist | Explicitamente esvaziado no makeContext | Seleção de medições elegíveis |
| Consultoria sem teste | Bloqueada por guard | Contrato opcional + perguntas iniciais |
| Ação/reteste/sessão | Não demonstrados no código examinado | #317 e #320 |
| Backend IA V4 | Não auditado | Contrato, custos, segurança, versão e rollback |

## Decisões propostas
- Preservar `measurementUnderstanding` e endpoint V2 como modo legado; introduzir `consultation` com schema próprio, versionamento e feature flag.
- Criar `AssistContextAssembler` que lê inventário/plano/topologia e apenas medições elegíveis; nunca transmitir automaticamente detalhes pessoais.
- Orquestrador #320 controla intenção, consentimento, perguntas, execução autorizada de testes, resposta, ação e reteste; a IA não determina diretamente estados nem dispara ferramentas.
- UI #312 deve manter wireframes aprovados e ser integrada ao estado real, não mocks.
- A auditoria de backend e execução de testes no Mac são **gates pendentes**, não evidências de conclusão.

## Adendo de auditoria local — 10/10/2026

Esta verificação foi feita no worktree de consultoria V4 e não consultou nem
ativou endpoint, Worker, provider, tráfego, custo ou retenção remota.

### Persistência que existe no cliente

| Área | Evidência estática e teste executado | Limite para o Assist V4 |
|---|---|---|
| Ambientes / topologia declarada | [`FileNetworkProfileRepository`](../aplicativo-ios/NetworkProfiles/Sources/FileNetworkProfileRepository.swift) mantém JSON local schema 2 com ambientes e vínculo único medição→ambiente; valida duplicatas/órfãos e usa escrita atômica. `swift test` em `NetworkProfiles`: 7/7. | O schema não guarda sessão, turnos, consentimento, ação ou histórico de consultoria. A migração de schema 1 descarta propositalmente identidade/fingerprint legados. |
| Histórico de medições | [`FileMeasurementHistoryRepository`](../aplicativo-ios/MeasurementHistory/Sources/FileMeasurementHistoryRepository.swift) mantém JSON local schema 1, valida cada medição, aplica retenção configurada, permite exclusão e usa escrita atômica. `swift test` em `MeasurementHistory`: 14/14. | Persistir uma medição não autoriza enviá-la ao Assist; não há repositório de `InvestigationSession`, transcrição, handoff, consentimento ou retenção/exclusão da consultoria. |

### Relay legado e fronteira de compatibilidade

- O aplicativo ainda configura o relay legado em `/v2/assist` por
  [`AssistContainer`](../aplicativo-ios/LinkaApp/Sources/Adapters/AssistContainer.swift)
  e [`NetworkDiagnosticsConfiguration`](../aplicativo-ios/NetworkDiagnostics/Sources/NetworkDiagnosticsConfiguration.swift).
  [`BuildeaDiagnosticAPI`](../aplicativo-ios/NetworkDiagnostics/Sources/BuildeaDiagnosticAPI.swift)
  continua serializando o contrato de diagnóstico baseado em `NetworkMeasurement`.
- [`AssistViewModel`](../aplicativo-ios/LinkaApp/Sources/Adapters/AssistViewModel.swift)
  continua recusando ausência de medição e zera explicitamente o histórico que
  recebe. Isso confirma que persistência local existente não é projeção
  autorizada para o relay legado.
- `swift test` em `NetworkAssist` passou 45/45 e
  `AssistViewModelTests` no iPhone 17 Pro Simulator passou 10/10. Essas
  suítes confirmam validação local, exigência de medição e compatibilidade
  do cliente; usam doubles e não comprovam resposta, autenticação ou
  disponibilidade do relay.
- Não há fonte do Worker/relay neste repositório. Logo, autenticação por
  proprietário, compatibilidade bilateral de schema, idempotência, logs,
  retenção, exclusão, limites de custo, feature flag operacional e rollback
  **não foram auditados**. Nenhum endpoint foi chamado nesta verificação.
- O núcleo [`AssistConsultation`](../aplicativo-ios/AssistConsultation/) segue
  separado: sua prova local não altera `/v2/assist` nem habilita transporte.

## Gate de aceite para iniciar V4
- [ ] Confirmar schema e persistência concretos de inventário/plano/topologia e elegibilidade de medições.
- [ ] Inspecionar Worker e contratos do relay; planejar compatibilidade de versões e limites de custo.
- [ ] Definir ADR da política de consultoria vs diagnóstico observacional.
- [ ] Definir máquina de estados, contratos tipados, autorização de teste e retenção de sessão.
- [ ] Criar testes de compatibilidade com Assist legado e cenários sem medição.
- [ ] Executar build/testes e QA em iPhone; não declarar concluído apenas por inspeção estática.
