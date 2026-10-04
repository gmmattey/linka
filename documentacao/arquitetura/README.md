# Arquitetura compartilhada do Linka

Estado: vigente para o checkout WIP; planos e integrações externas têm estado separado.
Responsável: Codex principal; Camillo responde por contratos e limites compartilhados.
Última revisão: 2026-10-04 — composição local dos cinco pacotes de medição/dados/interpretação, adapters, histórico remoto e planos de origem.
Base: branch `feat/macos-visual-direction-and-service-status`, HEAD `9eb1a094` + WIP preexistente. Nenhuma equivalência com main, build distribuída ou produção é presumida.
Referências: [AGENTS](../../AGENTS.md), [governança documental](../GOVERNANCA_DOCUMENTAL.md), manifests/fontes e documentação temática abaixo.

## Limites e fluxo

```text
LinkaEngine.SpeedTestCore → MeasurementState
            ↓ adapter SpeedTestViewModel (LinkaApp)
NetworkCore.NetworkMeasurement
    ├→ MeasurementHistory ← decorator MeasurementHistoryCloudKit
    ├→ NetworkInsights ← seleção de registros por adapters
    ├→ NetworkAssist ← contexto + gate em LinkaModules
    │      └→ NetworkDiagnostics → relay/NDS V2
    ├→ cartão PNG / resumo do widget
    └→ associação local de ambiente por measurementID (store separado)

Sonda leve + dados de plataforma → LiveTelemetryCollector
    → LiveUsageSuitabilityEvaluator → Home (sem persistir telemetria)
```

| Camada | Responsabilidade e limite |
|---|---|
| [LinkaEngine](../../aplicativo-ios/LinkaEngine/Package.swift) | Medir; não importa histórico, assinatura, Assist ou SwiftUI no manifest |
| [NetworkCore](../../aplicativo-ios/NetworkCore/Sources/NetworkMeasurement.swift) | Modelo, unidades, validação e evidência compartilhada; não interpreta intenção do usuário |
| [MeasurementHistory](../../aplicativo-ios/MeasurementHistory/Package.swift) | Repositório de fatos; depende de NetworkCore, não de UI/StoreKit |
| [NetworkInsights](../../aplicativo-ios/NetworkInsights/Package.swift) | Cálculos e avaliadores puros sobre fatos; não consulta rede/histórico sozinho |
| [NetworkAssist](../../aplicativo-ios/NetworkAssist/Package.swift) | Contexto, validação, porta de transporte e motores locais de indícios; não mede |
| [LinkaModules](../../aplicativo-ios/LinkaModules/Sources/) | Composição, aliases de compatibilidade, gates e factories; não deve duplicar o motor |
| [LinkaApp](../../aplicativo-ios/LinkaApp/Sources/) | Ciclo de vida, adapters Apple, navegação e apresentação |

Documentos de capacidades: [medição](../features/medicao/README.md), [histórico/ambientes/exportação](../features/historico/README.md), [Insights/Home viva](../features/insights/README.md), [Assist](../features/assist/README.md). Compartilhar domínio não significa compartilhar método, credencial ou autorização.

## Contrato canônico e serialização

[NetworkMeasurementContract](../../aplicativo-ios/NetworkCore/Sources/NetworkMeasurement.swift) usa `schemaVersion = 1`. `complete` exige download, upload e latência; `partial` exige ao menos uma métrica. Valores devem ser finitos e não negativos; perda fica entre 0 e 100. Mbps, milissegundos e percentuais não são intercambiáveis. Valores opcionais ausentes não são zeros. Tipo de conexão interno é opcional (`wifi`, `cellular`, `ethernet`, `other`); ausência interna não é o enum `unknown` proposto pelo Netscope.

`PacketProbeEvidence`, `RegionalGameReference` e `LoadResponsivenessEvidence` são envelopes opcionais com versão própria. `methodologyVersion` 1 não equivale ao schema da medição nem ao protocolo remoto NDS V2. `trustedLoadedLatencies` admite escalares legados quando não há envelope; envelope inconclusivo impede usar seus escalares como evidência confiável. Não reclassificar retroativamente legado como alta confiança.

Há três serializações distintas:

1. Modelo Swift `Codable` e validação `NetworkMeasurementContract` usados pelos consumidores locais.
2. Store JSON interno de histórico, versão 1 e datas Foundation `.deferredToDate`, com gravação atômica. Não é o documento de intercâmbio ISO-8601.
3. [Schema JSON externo](contratos/network-measurement.schema.json) e [fixtures](contratos/fixtures/), que descrevem apenas parte do modelo atual. `additionalProperties: false` torna material a falta de campos como `packetProbeEvidence`, `regionalGameReference`, `dnsResolutionMs`, `wifiContext`, `advancedWiFiDiagnostics` e `devicePlatform`. Não anunciar round-trip externo integral do modelo antes de reconciliar esse contrato.

CloudKit tem mapper explícito e não sincroniza todos os campos locais. [MeasurementRecordMapper](../../aplicativo-ios/MeasurementHistoryCloudKit/Sources/CloudKitMeasurementSync.swift) inclui upload sob carga e os três blobs de evidência; contexto Wi-Fi avançado/local, DNS, localização e plataforma não entram no record examinado. Ausência no remoto não permite inventar os campos na leitura.

## Backend efetivamente composto neste checkout

[AssistContainer](../../aplicativo-ios/LinkaApp/Sources/Adapters/AssistContainer.swift) cria `NetworkAssistService<BuildeaDiagnosticTransport>` envolvendo [BuildeaDiagnosticAPI](../../aplicativo-ios/NetworkDiagnostics/Sources/BuildeaDiagnosticAPI.swift). `transportAuth: .relay` dispensa bearer no cliente; o endpoint default é o relay `/v2/assist`. Overrides de configuração e `assistUsesRemoteDiagnostic` são descritos no [Assist](../features/assist/README.md). Não há validação ao vivo desses endereços nesta entrega.

O [NDSRequestBuilder](../../aplicativo-ios/NetworkDiagnostics/Sources/NDSRequestBuilder.swift) projeta fatos e contexto permitido. Capabilities descrevem evidência, enquanto outputs solicitados descrevem trabalho pedido ao serviço. V2 separa resultado estruturado (`raw`) da explicação; erro mantém código, mensagem, retryable e request ID. A biblioteca Assist conhece uma porta de transporte; o adapter remoto está fora dela. Históricos/relatos declarados não viram fatos medidos. O atual `AssistViewModel.makeContext` envia lista recente vazia, apesar da capacidade maior do contrato.

**Netscope:** não foram encontradas referências Swift a Netscope na composição de `LinkaApp`/`LinkaModules` examinada. Isso não afirma inexistência em outras worktrees ou no repositório externo. O plano WIP foi consolidado integralmente em substância em [NETSCOPE.md](NETSCOPE.md), separando proposta, conflitos e gates. Não trocar NDS por Netscope apenas por remover documentação antiga; integração requer contrato explícito, validação e autorização pertinente.

## Decisões compartilhadas preservadas dos planos

| Tema | Expectativa preservada | Implementação/limite observado |
|---|---|---|
| Produto e valor recorrente | Teste útil sem conta e sem limitar quantidade para forçar compra; acompanhamento/entendimento em superfície secundária | Regras comerciais vivem no pacote de entitlement; preço antigo não é preço atual confirmado |
| Motor | Único caminho de medição, cancelamento real, fatos parciais e privacidade | `SpeedTestCore` é composto pelo adapter; lacunas de zero/sonda regional registradas em Medição |
| Home viva | Uma fonte de leitura, baseline só da rede atual, invalidar troca/background, sem banda contínua | Buffer e relatório efêmeros encontrados; não há aceite físico/visual nesta tarefa |
| Alta confiança sob carga | Mesma origem lógica para baseline/carga, excluir warm-up, ambas as direções, inconclusivo explícito | Envelope existe; calibração física e convergência entre planos v2 e metodologia 1 pendentes |
| Mac e iPad | Mesmos contratos, interfaces nativas, ausência de dado honesta; não clonar UI nem inventar APIs | Bibliotecas compartilhadas; paridade visual, intents registrados e dispositivo são evidências separadas |
| Origem do dispositivo | Campo opcional/aditivo sem quebrar legado e ícone correto entre aparelhos | `devicePlatform` existe no modelo, mas não no mapper CloudKit examinado |
| Ambientes | Associação explícita pós-resultado por UUID; não inferir cômodo por SSID | Store schema 2, migração de nomes e assignments locais descritos no Histórico |
| Assist do agora | Medição atual, contexto declarado, sem reaproveitar histórico como diagnóstico atual | Contexto exclui recentes; entrada pelo resultado precisa reconciliação de intenção |
| Segurança | Nenhuma chave permanente de provider no bundle; rotação histórica como ação operacional distinta | Caminho relay examinado não envia bearer; não há auditoria geral/recibo de rotação nesta sessão |
| Triagem offline | Piloto local separado do engine/Assist: sondas públicas health/version, relatório efêmero, reteste principal e sem atribuição causal | Intenção preservada de `plano-triagem-conectividade-offline.md`; pacote/UI documentados estaticamente na [Triagem](../features/triagem-de-conectividade/README.md); runtime não executado |

## Aceite arquitetural e evidência

| ID | Critério | Verificação desta entrega |
|---|---|---|
| ARQ-01 | Motor permanece separado de UI, assinatura e persistência | Manifests e composição lidos; não foi executado build |
| ARQ-02 | Schema, store e metodologia não são tratados como iguais | Campos e serializadores comparados estaticamente; divergências explicitadas |
| ARQ-03 | Falhas/ausências não se transformam em sucesso documental | Testes encontrados e lacunas registradas nos quatro temas; nenhuma suite declarada verde |
| ARQ-04 | Backend planejado não aparece como entregue | NDS composto separado de Netscope proposto; infraestrutura externa não consultada |
| ARQ-05 | Migração não perde decisões materiais nem depende de planos removidos | Tabelas de expectativas e NETSCOPE preservados; integração/remoções registradas na migração |

Evidência: leitura de arquivos do checkout em 2026-10-04. Não executados: testes, build, simulador, dispositivo, CloudKit real, chamadas NDS, deploy ou inspeção de produção. Os comandos futuros estão nos temas; rodá-los não é pré-requisito inventado para esta entrega exclusivamente documental.

## Pendências de integração documental e técnica

| Pendência | Responsável / evento | Fechamento |
|---|---|---|
| Schema externo não representa todos os campos Swift | Camillo, antes de anunciar contrato interoperável completo | Decisão aditiva/versionamento, schema + fixtures + round-trip compatível |
| Evidência histórica de testes/deploys sem revalidação | Tito + Codex, próximo aceite da iniciativa correspondente | Referência de versão, procedimento, ambiente e limites reais |
| Contradições Netscope e política macOS | Camillo + Luiz, antes da implementação/ativação dependente | Resolver os itens discriminados em NETSCOPE sem autorizar custos por inferência |

## Mapa de origem → destino

O [registro de migração](../MIGRACAO.md) relaciona as fontes removidas aos destinos atuais. Decisões de UI, DNS, otimização e demais capacidades estão nos README ligados pelo [índice](../features/INDICE.md). O ledger mantém iniciativas abertas, sem declaração fictícia de conclusão.

Schema/fixtures, protótipo, tokens/componentes e fontes de código são dependências especializadas preservadas; a remoção atingiu fontes documentais substituídas e snapshots históricos identificados.

## Integração da governança sobre main — 2026-10-04

A consolidação acima inventaria o snapshot 9eb1a094 + WIP. A PR de integração parte de main 8507ce71 e preserva o código que avançou desde esse snapshot. Os registros posteriores já presentes em main permanecem como complementos reconhecidos, sem exclusão automática:

- [Promoção nos Atalhos](PLANO_WIFI_AVANCADO_PROMOCIONAL.md): resolver compartilhado incorporado na PR #273; a divergência antiga não permanece no código integrado.
- [Publicidade e Plus](PLANO_PLUS_PROMOCIONAL_ADS.md).
- [Netscope L01](NETSCOPE_L01_MAPA_EVIDENCIAS.md), [L02](PLANO_NETSCOPE_L02.md), [L03](NETSCOPE_L03_UI_FAIL_CLOSED.md) e [L05](NETSCOPE_L05_ATTESTED_TRANSPORT.md): entregas posteriores ao levantamento inicial; não confundir o plano NETSCOPE com ausência desses módulos no checkout integrado.

Responsável: Codex principal. Estado: reconciliação de integração; revisão funcional completa dessas entregas não executada nesta PR. Evento: próxima manutenção das respectivas features. Fechamento: incorporar os contratos destes complementos ao documento da capacidade correspondente, após revisão do código, sem perder decisões ou evidências. Nenhuma validação do snapshot antigo é promovida a prova da main atual.
