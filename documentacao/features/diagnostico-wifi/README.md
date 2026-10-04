# Diagnóstico Wi-Fi avançado e atalho

> Integração em 2026-10-04 sobre main `8507ce71`: a divergência promocional dos Atalhos descrita no snapshot 9eb1a094 + WIP abaixo foi corrigida na PR #273. Provider e App Intents usam `LinkaEntitlementSnapshotResolver`. Ver [contrato incorporado à main](../../arquitetura/PLANO_WIFI_AVANCADO_PROMOCIONAL.md). Esta integração preserva o código atual; não repete validação física ou release.

Estado do documento: vigente para a inspeção estática declarada; validação de execução pendente.
Responsável: Codex principal; manutenção técnica por Pedro.
Última revisão: 2026-10-04 — código, contratos locais, fontes de testes e planos do tema.
Referências: [Governança](../../../AGENTS.md); [processo documental](../../GOVERNANCA_DOCUMENTAL.md); fontes abaixo.

Disponibilidade da feature: implementações locais descritas por plataforma abaixo; não atesta distribuição.
Base conferida: checkout WIP da branch `feat/macos-visual-direction-and-service-status`, HEAD `9eb1a094` mais alterações locais. Não é snapshot de main/produção.
Termos de busca: Wi-Fi avançado, Linka Wi-Fi Advanced, RSSI, SNR, CoreWLAN.

## Propósito e limites

- Problema/resultado esperado: Anexar à medição detalhes Wi-Fi realmente disponíveis, por integração opt-in, para entender a conexão sem inventar causa raiz.
- Quem usa: pessoa usando o Linka no ecossistema Apple, nas condições de acesso descritas abaixo.
- Fora de escopo: Scanner, MCS, spatial streams, largura de canal inventada, troca automática de banda e diagnóstico causal; atalhos gerais/Widgets ficam em outra feature.

## Comportamento atual

| Entrada ou ação | Resposta do produto | Regra e fonte |
|---|---|---|
| Configurar em Ajustes no iOS | Abre template iCloud Shortcuts para adição explícita pela pessoa. | Não instala silenciosamente; URL está em LinkaAdvancedWiFiIntegration. |
| Medir com integração configurada e habilitada | MainView executa atalho; retorno importa dados e permite iniciar teste. | Cancelamento/retorno sem dados oferece tentar novamente ou medir sem dados avançados. |
| Registrar campos ou JSON | Valida acesso e entrada; grava inbox temporária sanitizada. | JSON: até 4096 bytes, schema/versão suportados, UUID não repetido, até 30 s no futuro e 180 s de idade. |
| Medir com detalhes no Mac | CoreWLAN fornece SSID/BSSID transitório, TX, RSSI e canal quando disponíveis. | makeNativeDiagnostics exige identificador derivado de AP; ViewModel confere associação com medição. |

As regras acima se referem aos símbolos do mapa técnico; são observação estática, não prova de jornada executada.

### Estados e recuperação

| Estado/condição | Comportamento e recuperação |
|---|---|
| Sem Plus/configuração/desabilitado | Ajustes distingue requiresPlus, needsConfiguration, active, disabled. |
| Captura parcial | Campos inválidos ou ausentes continuam opcionais; não preencher com zero. |
| Payload inválido/expirado/duplicado | Importação rejeitada; sem anexo fictício. |
| Mac sem dados/permissão suficiente | Captura retorna nil; UI oferece indisponibilidade, sem prometer equivalência de todos os campos do atalho. |

Estados de permissão, offline e cancelamento não expostos especificamente pela implementação não são tratados como estados comprovadamente distintos. Resultados parciais aplicáveis estão descritos acima.

### Plataformas e acesso

iPhone/iPad: App Intents específicos compilados sob os(iOS), dependem do app Atalhos e ações disponíveis no sistema. Mac: coleta nativa CoreWLAN, sem depender do atalho iOS.
 Configuração de targets: [aplicativo-ios/project.yml](../../../aplicativo-ios/project.yml). Mínimo de pacote não comprova disponibilidade do recurso em dispositivo.

### Experiência e referências compartilhadas

- Entradas/destinos: ações descritas acima e views no mapa; folhas, confirmação, erro, detalhe e gestão precisam de validação visual no candidato.
- Acessibilidade: controles SwiftUI e labels existentes foram inspecionados nas views; VoiceOver, Dynamic Type, teclado e adaptação não foram executados.
- Fontes de aparência: [protótipo](../../design/prototipo/), [Design System](../../design/design_system/), [direção macOS](../../design/README.md). Não se declara conformidade visual por leitura de código.

## Mapa técnico

| Caminho relativo à raiz Git | Símbolos/responsabilidade |
|---|---|
| [aplicativo-ios/LinkaApp/Sources/Adapters/AppIntentCoordinator.swift](../../../aplicativo-ios/LinkaApp/Sources/Adapters/AppIntentCoordinator.swift) | `AdvancedWiFiDiagnosticsInbox; ImportWiFiDiagnosticsIntent; RegisterAdvancedWiFiDiagnosticsIntent; ShortcutEntitlementSnapshot` |
| [aplicativo-ios/LinkaApp/Sources/Adapters/SpeedTestViewModel.swift](../../../aplicativo-ios/LinkaApp/Sources/Adapters/SpeedTestViewModel.swift) | `startTest; consumePendingAdvancedWiFiDiagnostics` |
| [aplicativo-ios/LinkaApp/Sources/Adapters/ApplePlatformSignalProvider.swift](../../../aplicativo-ios/LinkaApp/Sources/Adapters/ApplePlatformSignalProvider.swift) | `MacAdvancedWiFiDiagnosticsProvider.capture` |
| [aplicativo-ios/LinkaApp/Sources/Support/LinkaExternalLinks.swift](../../../aplicativo-ios/LinkaApp/Sources/Support/LinkaExternalLinks.swift) | `LinkaAdvancedWiFiIntegration; LinkaWiFiPreferences` |
| [aplicativo-ios/LinkaApp/Sources/UI/MainView.swift](../../../aplicativo-ios/LinkaApp/Sources/UI/MainView.swift) | `recoverAdvancedWiFiMeasurementIfNeeded` |
| [aplicativo-ios/LinkaApp/Sources/UI/SettingsSheet.swift](../../../aplicativo-ios/LinkaApp/Sources/UI/SettingsSheet.swift) | `openAdvancedWiFi` |

## Fluxo e contratos

Atalhos → importFields/importPayload → AdvancedWiFiDiagnosticsInbox → SpeedTestViewModel → contexto opcional da medição/histórico. SSID pode compor contexto local; BSSID cru vira SHA256 com salt local, hardwareMacAddress não integra o objeto persistido. Inbox em UserDefaults com validade de 180 s e deduplicação; captura nativa não grava inbox. Não equiparar identificador local derivado a anonimização universal. Regras de associação temporal/Wi-Fi/SSID e AP estão no ViewModel; exports e contratos remotos exigem auditoria própria.

## Dependências e impacto

NetworkCore modela contexto de medição; app implementa os intents Wi-Fi (não confundir com o pacote LinkaAppIntents de ações gerais). StoreKit fornece acesso; CoreWLAN só no Mac.

Alteração nas condições de acesso deve revisar [Plus](../linka-plus/README.md). Mudanças de dados ou fluxo exigem revisão dos consumidores citados, sem duplicar regra na UI.

## Operação e limitações técnicas

Preferências LinkaWiFiPreferences, entitlement wifi-info e permissões de identificação. O template compartilhado não foi aberto nem executado; conteúdo remoto atual não verificado.

## Critérios de aceite

Critérios para conferir a capacidade existente; não são testes declarados como aprovados.

| ID | Cenário | Resultado esperado | Fonte |
|---|---|---|---|
| AC-01 | JSON fora dos limites ou repetido | Rejeitar sem anexar à medição. | Mapa técnico e fluxo acima |
| AC-02 | Dado Wi-Fi ausente | Preservar ausência, permitindo medição sem detalhes. | Mapa técnico e fluxo acima |
| AC-03 | Captura nativa de outro AP | Não associar à medição atual. | Mapa técnico e fluxo acima |

## Evidências existentes

| Critérios | Nível/ambiente | Base/data | Procedimento | Resultado e limite |
|---|---|---|---|---|
| AC-01 a AC-03 | Inspeção estática local | WIP descrito; 2026-10-04 | Leitura dos símbolos e busca com rg | Regras documentadas; não comprova runtime |

Fontes de testes existentes consultadas (não executadas nesta entrega):
- [aplicativo-ios/LinkaApp/Tests/SettingsProductionStateTests.swift](../../../aplicativo-ios/LinkaApp/Tests/SettingsProductionStateTests.swift).
- [aplicativo-ios/LinkaApp/Tests/ApplePlatformSignalProviderCWChannelBandTests.swift](../../../aplicativo-ios/LinkaApp/Tests/ApplePlatformSignalProviderCWChannelBandTests.swift).

Testes de pacotes/app, build, simulador, dispositivo físico, TestFlight, App Review e produção: **não executados/verificados nesta tarefa documental**. Nenhum plano foi marcado como entregue.

## Validação ainda necessária

| Cenário/risco | Responsável | Evento de revisão | Critério de fechamento |
|---|---|---|---|
| Resolver diferença de promoção entre app e intent; validar importação, cancelamento, permissão negada, contexto parcial e associação em iPhone físico/Mac assinado. | Tito, com executor autorizado | Antes da próxima release que inclua a capacidade | Evidência reproduzível da build candidata e dos cenários, ou decisão explícita de escopo |
| Acessibilidade e todos os destinos alcançáveis | Tito/Íris | Próxima validação visual da capacidade | Conferir estados aplicáveis em iPhone/iPad/Mac; registrar limitações por plataforma |

## Mudanças em andamento

A autorização desta sessão cobre documentação do WIP. Não concede implementação, encerramento de plano ou publicação. As fontes anteriores foram reconciliadas e removidas na [migração documental](../../MIGRACAO.md); expectativas ainda abertas permanecem abaixo.

Origem e substituições registradas na [migração](../../MIGRACAO.md).

Plano #134 privilegiava JSON; código também oferece ação tipada RegisterAdvancedWiFiDiagnosticsIntent. Divergência material: ShortcutEntitlementSnapshot.current consulta compra e DEBUG, mas retorna Free sem fallback promocional; StoreKitEntitlementProvider aplica promoção no app. Não declarar paridade do acesso promocional aos atalhos.

## Divergências e perguntas abertas

| Pendência | Responsável | Evento | Fechamento |
|---|---|---|---|
| Resolver/registrar diferenças acima entre planos, comentários e composição real | Codex principal, com especialista do tema | Integração documental e antes da release afetada | Decisão rastreável ou correção autorizada com evidência; não presumir entrega |

## Expectativas preservadas dos planos e estado

Esta tabela conserva trabalho aberto após a substituição das fontes antigas. Não constitui nova autorização de implementação.

| ID | Estado | Expectativa ou lacuna | Responsável | Evento | Critério de fechamento |
|---|---|---|---|---|---|
| WIFI-P01 | Implementado parcialmente; validação pendente | Template tipado e JSON legado: preservar campos parciais, schema 1, replay, tempo e SSID contraditório; confirmar conteúdo remoto e execução end-to-end. | Tito | Antes da release com integração | Atalho importado/rodado em iPhone físico e anexação correta, inclusive recusa/cancelamento. |
| WIFI-P02 | Divergência material | Promoção do app não alcança ShortcutEntitlementSnapshot.current neste WIP; não há resolver compartilhado nessa composição. | Pedro/Codex | Antes de anunciar Wi-Fi avançado gratuito pela campanha | Alinhar política autorizada e provar compra/promoção/Free no app e intent. |
| WIFI-P03 | Expectativa preservada do plano #134; auditoria transversal pendente | CloudKit não deve levar contexto avançado; NDS só fatos medidos, sem SSID/BSSID/MAC; não inferir cumprimento pelo inbox. | Tito/Camillo | Antes de mudar exportação/sincronização | Conferir allowlists/serialização de todos os consumidores com testes adequados. |
