# Ambientes de medição (antigos perfis de rede)

Estado do documento: vigente para a inspeção estática declarada; validação de execução pendente.
Responsável: Codex principal; manutenção técnica por Pedro.
Última revisão: 2026-10-04 — código, contratos locais, fontes de testes e planos do tema.
Referências: [Governança](../../../AGENTS.md); [processo documental](../../GOVERNANCA_DOCUMENTAL.md); fontes abaixo.

Disponibilidade da feature: implementações locais descritas por plataforma abaixo; não atesta distribuição.
Base conferida: checkout WIP da branch `feat/macos-visual-direction-and-service-status`, HEAD `9eb1a094` mais alterações locais. Não é snapshot de main/produção.
Termos de busca: Ambientes, Onde você mediu?, Perfis de rede, NetworkProfiles.

## Propósito e limites

- Problema/resultado esperado: Associar manualmente uma medição a um lugar nomeado e comparar suas leituras locais, sem inferir cômodo pela rede.
- Quem usa: pessoa usando o Linka no ecossistema Apple, nas condições de acesso descritas abaixo.
- Fora de escopo: Reconhecimento automático por SSID/BSSID, monitoramento, sincronização de ambientes e reatribuição retroativa do histórico.

## Comportamento atual

| Entrada ou ação | Resposta do produto | Regra e fonte |
|---|---|---|
| Após resultado, escolher/criar ambiente | Associa somente measurementID atual ao UUID escolhido. | Nome manual não vazio; nomes repetidos permitidos. |
| Trocar associação | Upsert substitui assignment da medição. | Uma associação por measurementID; ambiente deve existir. |
| Gerir ambientes em Ajustes | Listar, renomear e excluir; criação vinculada ao resultado. | Gate optimization; sem identificação habilitada/SSID/Wi-Fi completo não associar. |
| Excluir ambiente | Remove ambiente e assignments; não exclui medições. | Store separado do histórico. |

As regras acima se referem aos símbolos do mapa técnico; são observação estática, não prova de jornada executada.

### Estados e recuperação

| Estado/condição | Comportamento e recuperação |
|---|---|
| Sem ambientes | Criar após resultado elegível; gestão não fabrica ambiente. |
| Sem identificação/SSID ou celular/parcial | Explica indisponibilidade; não pede permissão automaticamente para salvar. |
| Referência em formação | Exige pelo menos três leituras anteriores elegíveis em 30 dias. |
| Arquivo corrompido/versão futura/migração falhou | Erro preserva arquivo; tentar acesso novamente, sem sobrescrever silenciosamente. |

Estados de permissão, offline e cancelamento não expostos especificamente pela implementação não são tratados como estados comprovadamente distintos. Resultados parciais aplicáveis estão descritos acima.

### Plataformas e acesso

iPhone/iPad e Mac usam mesmo coordinator e repositório; gestão em SettingsSheet, associação em OptimizationView. Acesso pago usa capability optimization.
 Configuração de targets: [aplicativo-ios/project.yml](../../../aplicativo-ios/project.yml). Mínimo de pacote não comprova disponibilidade do recurso em dispositivo.

### Experiência e referências compartilhadas

- Entradas/destinos: ações descritas acima e views no mapa; folhas, confirmação, erro, detalhe e gestão precisam de validação visual no candidato.
- Acessibilidade: controles SwiftUI e labels existentes foram inspecionados nas views; VoiceOver, Dynamic Type, teclado e adaptação não foram executados.
- Fontes de aparência: [protótipo](../../design/prototipo/), [Design System](../../design/design_system/), [direção macOS](../../design/README.md). Não se declara conformidade visual por leitura de código.

## Mapa técnico

| Caminho relativo à raiz Git | Símbolos/responsabilidade |
|---|---|
| [aplicativo-ios/NetworkProfiles/Sources/NetworkProfile.swift](../../../aplicativo-ios/NetworkProfiles/Sources/NetworkProfile.swift) | `NetworkEnvironment; EnvironmentMeasurementAssignment` |
| [aplicativo-ios/NetworkProfiles/Sources/FileNetworkProfileRepository.swift](../../../aplicativo-ios/NetworkProfiles/Sources/FileNetworkProfileRepository.swift) | `FileNetworkProfileRepository; storeSchemaVersion` |
| [aplicativo-ios/LinkaApp/Sources/Adapters/OptimizationProfileCoordinator.swift](../../../aplicativo-ios/LinkaApp/Sources/Adapters/OptimizationProfileCoordinator.swift) | `OptimizationProfileCoordinator; recalculateReferenceStates` |
| [aplicativo-ios/LinkaApp/Sources/UI/NetworkProfilesSection.swift](../../../aplicativo-ios/LinkaApp/Sources/UI/NetworkProfilesSection.swift) | `NetworkProfilesManagementView` |
| [aplicativo-ios/NetworkOptimization/Sources/NetworkOptimization.swift](../../../aplicativo-ios/NetworkOptimization/Sources/NetworkOptimization.swift) | `NetworkBaselineBuilder; NetworkBaselineComparator` |

## Fluxo e contratos

Histórico + medição aberta → coordinator → associação explícita por UUID → NetworkBaselineBuilder. Medição atual é excluída da baseline; contagem exibida pode incluí-la, portanto contagem não é prova de referência pronta. Store schema 2 mantém nomes/datas/UUIDs/assignments, sem SSID/fingerprint/BSSID/métricas. Migração schema 1 preserva nome/ID/datas e descarta identidade/referência antiga sem atribuir medições. Escrita atômica; store network-profiles-v1.json mantém nome legado apesar do schema 2. Medições removidas do histórico deixam de contar.

## Dependências e impacto

NetworkProfiles depende de NetworkCore; baseline em NetworkOptimization depende de NetworkInsights. Histórico fornece leituras, mas não recebe campo ambiente nem migração de seu schema.

Alteração nas condições de acesso deve revisar [Plus](../linka-plus/README.md). Mudanças de dados ou fluxo exigem revisão dos consumidores citados, sem duplicar regra na UI.

## Operação e limitações técnicas

Application Support/Linka/network-profiles-v1.json no coordinator. Não remover arquivo para “recuperar” corrupção sem decisão de preservação. Ambientes/assignments são locais; não há integração CloudKit neste repositório.

## Critérios de aceite

Critérios para conferir a capacidade existente; não são testes declarados como aprovados.

| ID | Cenário | Resultado esperado | Fonte |
|---|---|---|---|
| AC-01 | Dois nomes iguais | Preservar IDs distintos e associação por UUID. | Mapa técnico e fluxo acima |
| AC-02 | Migração v1 | Preservar nomes/IDs, não inferir assignments nem reter fingerprint. | Mapa técnico e fluxo acima |
| AC-03 | Excluir ambiente | Histórico permanece; assignments do ambiente são removidas. | Mapa técnico e fluxo acima |
| AC-04 | Três leituras anteriores associadas elegíveis | Formar referência; leituras da mesma rede sem assignment não contam. | Mapa técnico e fluxo acima |

## Evidências existentes

| Critérios | Nível/ambiente | Base/data | Procedimento | Resultado e limite |
|---|---|---|---|---|
| AC-01 a AC-04 | Inspeção estática local | WIP descrito; 2026-10-04 | Leitura dos símbolos e busca com rg | Regras documentadas; não comprova runtime |

Fontes de testes existentes consultadas (não executadas nesta entrega):
- [aplicativo-ios/NetworkProfiles/Tests/NetworkProfilesTests.swift](../../../aplicativo-ios/NetworkProfiles/Tests/NetworkProfilesTests.swift).
- [aplicativo-ios/NetworkOptimization/Tests/NetworkOptimizationTests.swift](../../../aplicativo-ios/NetworkOptimization/Tests/NetworkOptimizationTests.swift).

Testes de pacotes/app, build, simulador, dispositivo físico, TestFlight, App Review e produção: **não executados/verificados nesta tarefa documental**. Nenhum plano foi marcado como entregue.

## Validação ainda necessária

| Cenário/risco | Responsável | Evento de revisão | Critério de fechamento |
|---|---|---|---|
| Validar migração com store legado real, CRUD/exclusão, associação pós-resultado e gestão nas três plataformas; relação com o [Histórico](../historico/README.md) documentada. | Tito, com executor autorizado | Antes da próxima release que inclua a capacidade | Evidência reproduzível da build candidata e dos cenários, ou decisão explícita de escopo |
| Acessibilidade e todos os destinos alcançáveis | Tito/Íris | Próxima validação visual da capacidade | Conferir estados aplicáveis em iPhone/iPad/Mac; registrar limitações por plataforma |

## Mudanças em andamento

A autorização desta sessão cobre documentação do WIP. Não concede implementação, encerramento de plano ou publicação. As fontes anteriores foram reconciliadas e removidas na [migração documental](../../MIGRACAO.md); expectativas ainda abertas permanecem abaixo.

Origem e substituições registradas na [migração](../../MIGRACAO.md).

Plano antigo descrevia fingerprint de SSID e baseline automática por rede. O plano de Ambientes e código schema 2 substituem essa identidade por associação explícita. O nome OptimizationEnvironmentCoordinator sugerido no plano não foi adotado: símbolo atual é OptimizationProfileCoordinator. Não marcar migração validada em aparelho pela presença de testes.

## Divergências e perguntas abertas

| Pendência | Responsável | Evento | Fechamento |
|---|---|---|---|
| Resolver/registrar diferenças acima entre planos, comentários e composição real | Codex principal, com especialista do tema | Integração documental e antes da release afetada | Decisão rastreável ou correção autorizada com evidência; não presumir entrega |

## Expectativas preservadas dos planos e estado

Esta tabela conserva trabalho aberto após a substituição das fontes antigas. Não constitui nova autorização de implementação.

| ID | Estado | Expectativa ou lacuna | Responsável | Evento | Critério de fechamento |
|---|---|---|---|---|---|
| ENV-P01 | Substituído no modelo atual | Fingerprint por SSID, sugestão de nome do SSID e lastAnalyzedAt do plano antigo não definem Ambientes schema 2. | Codex | Integração documental | Registrar prevalência do modelo manual; não restaurar associação automática. |
| ENV-P02 | Expectativa antiga não entregue e não reafirmada pelo plano de Ambientes | Ação Refazer referência do plano de perfis não foi localizada na UI de gestão atual; baseline é derivada das assignments/histórico. | Íris/Codex | Próxima decisão de Ambientes | Decidir explicitamente retirar/deferir ou especificar efeito sem apagar histórico. |
| ENV-P03 | Validação pendente | Sem seleção automática do último ambiente; ignorar associação não altera nada. Migração não retroatribui leituras; nome repetido não conflita. | Tito | Antes de release com schema 2 | CRUD/migração/associação nas três plataformas e pt-BR/en/es-419. |
| ENV-P04 | Integração documental pendente | Histórico é fonte de métricas; assignments são externas e locais. Exclusão/poda de leitura deixa de contar na baseline; não duplicar documento de Histórico. | Codex | Consolidação da feature de histórico | Referências cruzadas e sem promessa de sincronização de ambientes. |
