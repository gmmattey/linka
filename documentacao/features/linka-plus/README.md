# Linka Plus, promoção e publicidade

> Integração em 2026-10-04 sobre main `8507ce71`: a divergência promocional dos Atalhos descrita no snapshot 9eb1a094 + WIP abaixo foi corrigida na PR #273. Provider e App Intents usam `LinkaEntitlementSnapshotResolver`. Ver [contrato incorporado à main](../../arquitetura/PLANO_WIFI_AVANCADO_PROMOCIONAL.md). Esta integração preserva o código atual; não repete validação física ou release.

Estado do documento: vigente para a inspeção estática declarada; validação de execução pendente.
Responsável: Codex principal; manutenção técnica por Pedro.
Última revisão: 2026-10-04 — código, contratos locais, fontes de testes e planos do tema.
Referências: [Governança](../../../AGENTS.md); [processo documental](../../GOVERNANCA_DOCUMENTAL.md); fontes abaixo.

Disponibilidade da feature: implementações locais descritas por plataforma abaixo; não atesta distribuição.
Base conferida: checkout WIP da branch `feat/macos-visual-direction-and-service-status`, HEAD `9eb1a094` mais alterações locais. Não é snapshot de main/produção.
Termos de busca: Free, Plus, StoreKit, paywall, promoção, anúncios, UMP.

## Propósito e limites

- Problema/resultado esperado: Manter medição e histórico úteis gratuitamente e liberar capacidades adicionais por entitlement, sem confundir promoção com assinatura sem anúncios.
- Quem usa: pessoa usando o Linka no ecossistema Apple, nas condições de acesso descritas abaixo.
- Fora de escopo: Preços e disponibilidade comercial em produção; documentação detalhada de Widgets e integrações Apple pertence à feature própria.

## Comportamento atual

| Entrada ou ação | Resposta do produto | Regra e fonte |
|---|---|---|
| Medir ou abrir histórico | Disponível no Free mesmo com snapshot inválido. | speedTest/history são exceções explícitas em decision. |
| Comprar/restaurar Plus | StoreKit verifica transação do produto anual; restauração chama AppStore.sync. | Produto ausente ou verificação inválida não libera compra. |
| Receber promoção | No iOS, fallback promocional até 31/10/2026 em São Paulo; compra válida prevalece. | isActive é false fora de os(iOS); endsAt é centralizado. |
| Entrar na Home ou no Histórico elegível | Uma tentativa de anúncio nativo por sessão do coordinator; Histórico exige conteúdo. | Entitlement resolvido + LinkaAdsEnabled + elegibilidade; primeiro placement vence. |
| Iniciar medição | Cancela fluxo publicitário pendente, invalida geração e remove anúncio. | measurementDidStart bloqueia continuações tardias. |
| Usar ações Apple | startSpeedTest/getLatestResult/openHistory passam pelo executor próprio sem appleIntegrations; default aplica gate. | LinkaApp.init registra a composição real; helper entitlementGated não prova gate uniforme. |

As regras acima se referem aos símbolos do mapa técnico; são observação estática, não prova de jornada executada.

### Estados e recuperação

| Estado/condição | Comportamento e recuperação |
|---|---|
| Produto carregando/indisponível/erro | productState distingue os estados; tentar carregar/restaurar sem liberar por suposição. |
| Compra pendente/cancelada | Outcomes distintos; não tratar como compra confirmada. |
| Consentimento falha ou não permite request | Não carrega anúncio; opções de privacidade seguem UMP. |
| Plus pago ativo | subscription/trial/lifetime válidos são paidPlus; promoção permanece eligibleFree. |

Estados de permissão, offline e cancelamento não expostos especificamente pela implementação não são tratados como estados comprovadamente distintos. Resultados parciais aplicáveis estão descritos acima.

### Plataformas e acesso

iPhone e iPad: StoreKit, promoção condicionada à data e GoogleMobileAds/UMP. Mac: StoreKit, sem promoção automática e métodos de anúncios sem operação neste adapter.
 Configuração de targets: [aplicativo-ios/project.yml](../../../aplicativo-ios/project.yml). Mínimo de pacote não comprova disponibilidade do recurso em dispositivo.

### Experiência e referências compartilhadas

- Entradas/destinos: ações descritas acima e views no mapa; folhas, confirmação, erro, detalhe e gestão precisam de validação visual no candidato.
- Acessibilidade: controles SwiftUI e labels existentes foram inspecionados nas views; VoiceOver, Dynamic Type, teclado e adaptação não foram executados.
- Fontes de aparência: [protótipo](../../design/prototipo/), [Design System](../../design/design_system/), [direção macOS](../../design/README.md). Não se declara conformidade visual por leitura de código.

## Mapa técnico

| Caminho relativo à raiz Git | Símbolos/responsabilidade |
|---|---|
| [aplicativo-ios/LinkaEntitlements/Sources/LinkaEntitlements.swift](../../../aplicativo-ios/LinkaEntitlements/Sources/LinkaEntitlements.swift) | `LinkaEntitlementPolicy; LinkaTemporaryFreeOffer` |
| [aplicativo-ios/LinkaEntitlements/Sources/StoreKitEntitlementProvider.swift](../../../aplicativo-ios/LinkaEntitlements/Sources/StoreKitEntitlementProvider.swift) | `StoreKitEntitlementProvider.refreshSnapshot; purchase; restore` |
| [aplicativo-ios/LinkaApp/Sources/Adapters/Ads/LinkaAdsCoordinator.swift](../../../aplicativo-ios/LinkaApp/Sources/Adapters/Ads/LinkaAdsCoordinator.swift) | `LinkaAdSessionGate; LinkaAdRequestGate; LinkaAdsCoordinator` |
| [aplicativo-ios/LinkaApp/Sources/LinkaApp.swift](../../../aplicativo-ios/LinkaApp/Sources/LinkaApp.swift) | `LinkaApp.init` |
| [aplicativo-ios/LinkaApp/Sources/UI/SettingsSheet.swift](../../../aplicativo-ios/LinkaApp/Sources/UI/SettingsSheet.swift) | `SubscriptionManagementSheet` |

## Fluxo e contratos

StoreKit → snapshot → decisão por capability/UI. Free inclui speedTest/history; Plus inclui insights, assist, appleIntegrations, advancedWiFiDiagnostics, expertMode, usageDiagnostics e optimization. Expert Mode é gate de exibição, não de cálculo. Publicidade usa adEligibility separado. UMP atualiza consentimento e apresenta formulário se necessário; requests usam npa=1, personalização e publisher first-party ID desativados. Isso não prova conformidade regulatória nem ausência de toda coleta do SDK. DEBUG admite forcePlus; não é prova de assinatura de distribuição.

## Dependências e impacto

LinkaEntitlements depende de Foundation/StoreKit; app liga GoogleMobileAds e UserMessagingPlatform somente no iOS. AppIntents consome política, mas sua composição precisa ser conferida por ação.

Alteração nas condições de acesso deve revisar [Plus](../linka-plus/README.md). Mudanças de dados ou fluxo exigem revisão dos consumidores citados, sem duplicar regra na UI.

## Operação e limitações técnicas

Configuração LinkaAdsEnabled/“LINKA_ADS_ENABLED”, IDs StoreKit em LinkaStoreProductID, metadados do app e SDK. Não fixar preço a partir de comentário: catálogo comercial não foi consultado.

## Critérios de aceite

Critérios para conferir a capacidade existente; não são testes declarados como aprovados.

| ID | Cenário | Resultado esperado | Fonte |
|---|---|---|---|
| AC-01 | Free com entitlement inválido | Medição/histórico continuam acessíveis. | Mapa técnico e fluxo acima |
| AC-02 | Promoção válida e assinatura paga | Ambas liberam capacidades; apenas assinatura paga válida suprime anúncios pela política. | Mapa técnico e fluxo acima |
| AC-03 | Medição começa durante UMP | Nenhuma continuação autorizada pelo gate carrega anúncio sobre a medição. | Mapa técnico e fluxo acima |

## Evidências existentes

| Critérios | Nível/ambiente | Base/data | Procedimento | Resultado e limite |
|---|---|---|---|---|
| AC-01 a AC-03 | Inspeção estática local | WIP descrito; 2026-10-04 | Leitura dos símbolos e busca com rg | Regras documentadas; não comprova runtime |

Fontes de testes existentes consultadas (não executadas nesta entrega):
- [aplicativo-ios/LinkaEntitlements/Tests/LinkaEntitlementsTests.swift](../../../aplicativo-ios/LinkaEntitlements/Tests/LinkaEntitlementsTests.swift).
- [aplicativo-ios/LinkaApp/Tests/LinkaHistoryAdSessionGateTests.swift](../../../aplicativo-ios/LinkaApp/Tests/LinkaHistoryAdSessionGateTests.swift).

Testes de pacotes/app, build, simulador, dispositivo físico, TestFlight, App Review e produção: **não executados/verificados nesta tarefa documental**. Nenhum plano foi marcado como entregue.

## Validação ainda necessária

| Cenário/risco | Responsável | Evento de revisão | Critério de fechamento |
|---|---|---|---|
| Executar matriz StoreKit/UMP em candidato real, inclusive promoção, compra paga e medição durante formulário; não executado nesta entrega. | Tito, com executor autorizado | Antes da próxima release que inclua a capacidade | Evidência reproduzível da build candidata e dos cenários, ou decisão explícita de escopo |
| Acessibilidade e todos os destinos alcançáveis | Tito/Íris | Próxima validação visual da capacidade | Conferir estados aplicáveis em iPhone/iPad/Mac; registrar limitações por plataforma |

## Mudanças em andamento

A autorização desta sessão cobre documentação do WIP. Não concede implementação, encerramento de plano ou publicação. As fontes anteriores foram reconciliadas e removidas na [migração documental](../../MIGRACAO.md); expectativas ainda abertas permanecem abaixo.

Origem e substituições registradas na [migração](../../MIGRACAO.md).

Documento antigo lista histórico como Plus em prosa e Free na matriz; prevalece Free no código. Não cobre publicidade/promoção WIP nem exceções do executor. Não importar afirmação antiga sobre CloudKit/produção como evidência desta revisão.

## Divergências e perguntas abertas

| Pendência | Responsável | Evento | Fechamento |
|---|---|---|---|
| Resolver/registrar diferenças acima entre planos, comentários e composição real | Codex principal, com especialista do tema | Integração documental e antes da release afetada | Decisão rastreável ou correção autorizada com evidência; não presumir entrega |

## Expectativas preservadas dos planos e estado

Esta tabela conserva trabalho aberto após a substituição das fontes antigas. Não constitui nova autorização de implementação.

| ID | Estado | Expectativa ou lacuna | Responsável | Evento | Critério de fechamento |
|---|---|---|---|---|---|
| PLUS-P01 | Validação pendente | Matriz StoreKit real: compra anual, pendente, cancelamento, restauração, expiração e produto indisponível; preço vem de Product, não do comentário. | Tito | Antes de release comercial | Evidência por cenário em candidato assinado. |
| PLUS-P02 | Divergência documentada | Comentário do coordinator ainda fala em consentimento somente no Histórico; prepareHomeAd também usa o fluxo no WIP. Não documentar exclusividade do Histórico. | Pedro/Codex | Próxima alteração de publicidade | Comentário e UX acordados com composição real, com revisão do início da medição. |
| PLUS-P03 | Divergência de fronteira temporal | isWithinOfferPeriod aceita exatamente endsAt, mas decision expira validUntil <= date. | Pedro | Revisão da campanha antes do encerramento | Definir a fronteira e verificar instante final/fim da promoção sem afirmar cobertura atual. |

A divergência do acesso promocional dos intents específicos está em [Diagnóstico Wi-Fi](../diagnostico-wifi/README.md), WIFI-P02. Integrações Apple gerais e Widgets estão em [fonte própria](../integracoes-apple/README.md); este documento registra apenas o limite de acesso observado.
