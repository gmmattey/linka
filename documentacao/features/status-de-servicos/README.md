# Status de serviços e alertas

Estado do documento: vigente para a inspeção estática declarada; validação de execução pendente.
Responsável: Codex principal; manutenção técnica por Pedro.
Última revisão: 2026-10-04 — código, contratos locais, fontes de testes e planos do tema.
Referências: [Governança](../../../AGENTS.md); [processo documental](../../GOVERNANCA_DOCUMENTAL.md); fontes abaixo.

Disponibilidade da feature: implementações locais descritas por plataforma abaixo; não atesta distribuição.
Base conferida: checkout WIP da branch `feat/macos-visual-direction-and-service-status`, HEAD `9eb1a094` mais alterações locais. Não é snapshot de main/produção.
Termos de busca: Status de serviços, incidentes, alertas, ServiceStatusStore.

## Propósito e limites

- Problema/resultado esperado: Consultar incidentes de serviços remotos e escolher alertas, distinguindo indisponibilidade do serviço da conexão medida pelo Linka.
- Quem usa: pessoa usando o Linka no ecossistema Apple, nas condições de acesso descritas abaixo.
- Fora de escopo: Diagnóstico da rede local, garantia de disponibilidade, monitoramento pelo próprio telefone e confirmação de APNs/produção sem evidência.

## Comportamento atual

| Entrada ou ação | Resposta do produto | Regra e fonte |
|---|---|---|
| Abrir Status em Ajustes | Carrega catálogo e incidentes; agrupa por categoria e permite buscar nome. | GET catalog e incidents; catálogo remoto controla disponibilidade de monitoramento. |
| Expandir incidente | Mostra título/resumo; iOS diferencia confiança, Mac resume por severidade. | Não equivale a medir a rede da pessoa. |
| Ativar alertas | Guarda preferência local, pede permissão se ainda não decidida e sincroniza instalação. | Exige notificationEligible e monitoringEnabled. |
| Receber token/incidente | Sincroniza token e tenta abrir detalhe do incidente focado. | Observers e inbox; sem prova de entrega push nesta revisão. |

As regras acima se referem aos símbolos do mapa técnico; são observação estática, não prova de jornada executada.

### Estados e recuperação

| Estado/condição | Comportamento e recuperação |
|---|---|
| Sem catálogo/dados/busca vazia | Sem dados de status; UI sugere atualizar. |
| Atualização falha/offline | Mensagem de falha; dados existentes não são explicitamente limpos. |
| Sem monitoramento | Toggle desabilitado; não exibe normalidade como monitoramento ativo. |
| Monitorado sem incidente não resolvido | UI diz Operando normalmente; inferência do catálogo/incidentes, sem prazo de frescor local. |
| Permissão negada/APNs falha | Escolha local permanece; token pode ficar ausente e app continua exibindo incidentes. |

Estados de permissão, offline e cancelamento não expostos especificamente pela implementação não são tratados como estados comprovadamente distintos. Resultados parciais aplicáveis estão descritos acima.

### Plataformas e acesso

iPhone/iPad e Mac têm views próprias e registro de notificações via UIApplication/NSApplication. Entradas/store inspecionados não exigem Plus. iOS possui refreshable; Mac atualiza em task ao abrir.
 Configuração de targets: [aplicativo-ios/project.yml](../../../aplicativo-ios/project.yml). Mínimo de pacote não comprova disponibilidade do recurso em dispositivo.

### Experiência e referências compartilhadas

- Entradas/destinos: ações descritas acima e views no mapa; folhas, confirmação, erro, detalhe e gestão precisam de validação visual no candidato.
- Acessibilidade: controles SwiftUI e labels existentes foram inspecionados nas views; VoiceOver, Dynamic Type, teclado e adaptação não foram executados.
- Fontes de aparência: [protótipo](../../design/prototipo/), [Design System](../../design/design_system/), [direção macOS](../../design/README.md). Não se declara conformidade visual por leitura de código.

## Mapa técnico

| Caminho relativo à raiz Git | Símbolos/responsabilidade |
|---|---|
| [aplicativo-ios/LinkaApp/Sources/Adapters/ServiceStatusStore.swift](../../../aplicativo-ios/LinkaApp/Sources/Adapters/ServiceStatusStore.swift) | `ServiceStatusStore; LinkaService; LinkaServiceIncident; ServiceStatusDeviceIdentity` |
| [aplicativo-ios/LinkaApp/Sources/UI/ServiceStatusView.swift](../../../aplicativo-ios/LinkaApp/Sources/UI/ServiceStatusView.swift) | `ServiceStatusView; statusText; macStatusSummary` |
| [aplicativo-ios/LinkaApp/Sources/UI/SettingsSheet.swift](../../../aplicativo-ios/LinkaApp/Sources/UI/SettingsSheet.swift) | `SettingsSheet` |
| [aplicativo-ios/LinkaApp/Sources/LinkaApp.swift](../../../aplicativo-ios/LinkaApp/Sources/LinkaApp.swift) | `LinkaApp` |

## Fluxo e contratos

LinkaServiceStatusEndpoint do bundle → GET catalog/incidents/incidents/{id}. PUT installations/{installationID} envia platform, app_version, locale, push_token/push_environment quando presentes; PUT subscriptions envia service_ids. ID de instalação fica no Keychain; preferências e token em UserDefaults. Mesmo refresh chama synchronizeInstallation, não apenas opt-in a alertas. Falha de sincronização é absorvida e nova abertura/troca de token tenta novamente. Contratos Codable snake_case e datas ISO8601 estão no adapter, sem schema externo verificado.

## Dependências e impacto

URLSession, Security, UserNotifications, relay remoto e APNs. Targets declaram entitlement de push; isso não confirma credenciais, entitlement assinado ou entrega remota.

Alteração nas condições de acesso deve revisar [Plus](../linka-plus/README.md). Mudanças de dados ou fluxo exigem revisão dos consumidores citados, sem duplicar regra na UI.

## Operação e limitações técnicas

LinkaServiceStatusEndpoint obrigatório para fetch; se ausente refresh retorna sem erro explícito. HTTP 200 exigido; usa URLSession.shared por padrão, sem deadline próprio/retry explícito no store. Backend operacional não foi consultado.

## Critérios de aceite

Critérios para conferir a capacidade existente; não são testes declarados como aprovados.

| ID | Cenário | Resultado esperado | Fonte |
|---|---|---|---|
| AC-01 | Serviço sem elegibilidade/monitoramento | Não permitir ativação de alertas. | Mapa técnico e fluxo acima |
| AC-02 | Falha de sincronização | Preservar escolha local para nova tentativa. | Mapa técnico e fluxo acima |
| AC-03 | Catálogo sem monitoramento | Mostrar indisponibilidade, não inferir saúde da conexão. | Mapa técnico e fluxo acima |

## Evidências existentes

| Critérios | Nível/ambiente | Base/data | Procedimento | Resultado e limite |
|---|---|---|---|---|
| AC-01 a AC-03 | Inspeção estática local | WIP descrito; 2026-10-04 | Leitura dos símbolos e busca com rg | Regras documentadas; não comprova runtime |

Não foi localizada suíte específica de ServiceStatusStore no inventário consultado de LinkaApp/Tests. Isso não prova ausência de cobertura indireta.

Testes de pacotes/app, build, simulador, dispositivo físico, TestFlight, App Review e produção: **não executados/verificados nesta tarefa documental**. Nenhum plano foi marcado como entregue.

## Validação ainda necessária

| Cenário/risco | Responsável | Evento de revisão | Critério de fechamento |
|---|---|---|---|
| Validar contratos/erro/endpoint ausente, dados antigos e APNs em iPhone/Mac assinados; revisar privacidade do registro de instalação feito no refresh mesmo sem seguir serviço. | Tito, com executor autorizado | Antes da próxima release que inclua a capacidade | Evidência reproduzível da build candidata e dos cenários, ou decisão explícita de escopo |
| Acessibilidade e todos os destinos alcançáveis | Tito/Íris | Próxima validação visual da capacidade | Conferir estados aplicáveis em iPhone/iPad/Mac; registrar limitações por plataforma |

## Mudanças em andamento

A autorização desta sessão cobre documentação do WIP. Não concede implementação, encerramento de plano ou publicação. As fontes anteriores foram reconciliadas e removidas na [migração documental](../../MIGRACAO.md); expectativas ainda abertas permanecem abaixo.

Origem e substituições registradas na [migração](../../MIGRACAO.md).

Planos visuais são referências de superfícies, não prova do relay/APNs. Não foi encontrado plano específico de status no conjunto .agents e arquitetura consultado; não afirmar release. Texto Operando normalmente deriva da ausência de incidente sem controle explícito de frescor, e precisa revisão de produto se houver falha posterior.

## Divergências e perguntas abertas

| Pendência | Responsável | Evento | Fechamento |
|---|---|---|---|
| Resolver/registrar diferenças acima entre planos, comentários e composição real | Codex principal, com especialista do tema | Integração documental e antes da release afetada | Decisão rastreável ou correção autorizada com evidência; não presumir entrega |

## Expectativas preservadas dos planos e estado

Esta tabela conserva trabalho aberto após a substituição das fontes antigas. Não constitui nova autorização de implementação.

| ID | Estado | Expectativa ou lacuna | Responsável | Evento | Critério de fechamento |
|---|---|---|---|---|---|
| STATUS-P01 | Lacuna de validação | Não há controle explícito de frescor antes de Operando normalmente; atualização pode falhar mantendo dados antigos. | Íris/Pedro | Antes de release de status | Decisão para dados antigos e teste com erro após catálogo carregado. |
| STATUS-P02 | Auditoria pendente | Registro de instalação ocorre no refresh mesmo sem alertas; confirmar necessidade e coerência com política pública e App Privacy. | Codex/Tito | Antes de release de status | Fluxo real e disclosure conferidos, sem afirmar anonimização. |
| STATUS-P03 | Validação pendente | APNs, relay, reabertura por incidente, permissão negada, token renovado e serviço desativado remotamente. | Tito | Candidato assinado iOS/macOS | Evidências separadas de contrato local, relay e entrega push. |
