# Otimização após a medição

Estado do documento: vigente para a inspeção estática declarada; validação de execução pendente.
Responsável: Codex principal; manutenção técnica por Pedro.
Última revisão: 2026-10-04 — código, contratos locais, fontes de testes e planos do tema.
Referências: [Governança](../../../AGENTS.md); [processo documental](../../GOVERNANCA_DOCUMENTAL.md); fontes abaixo.

Disponibilidade da feature: implementações locais descritas por plataforma abaixo; não atesta distribuição.
Base conferida: checkout WIP da branch `feat/macos-visual-direction-and-service-status`, HEAD `9eb1a094` mais alterações locais. Não é snapshot de main/produção.
Termos de busca: Otimização, reteste, oportunidades, NetworkOptimization.

## Propósito e limites

- Problema/resultado esperado: Transformar fatos medidos em sugestões determinísticas e comparar um reteste explícito, mantendo resultado como protagonista.
- Quem usa: pessoa usando o Linka no ecossistema Apple, nas condições de acesso descritas abaixo.
- Fora de escopo: Causa raiz, garantia de ganho, controle automático de rede e mudança da metodologia do LinkaEngine.

## Comportamento atual

| Entrada ou ação | Resposta do produto | Regra e fonte |
|---|---|---|
| Abrir Otimização após resultado | Constrói oportunidades usando baseline e histórico fornecidos. | Regras determinísticas; no máximo três tipos atuais. |
| Free explora capacidade | Prévia com compra; fluxo completo exige optimization. | isPlusActive vem da decisão do app. |
| Seguir orientação e medir novamente | Reteste usa medição existente e compara ao baseline. | Não modifica DNS/roteador automaticamente. |
| Acessar ambientes ou DNS | Destinos secundários integrados à Otimização. | Regras específicas nas features relacionadas. |

As regras acima se referem aos símbolos do mapa técnico; são observação estática, não prova de jornada executada.

### Estados e recuperação

| Estado/condição | Comportamento e recuperação |
|---|---|
| Sem oportunidades | UI comunica ausência; não inventa recomendação. |
| Reteste incompleto/tipo de rede diferente/SSID Wi-Fi diferente ou ausente | notComparable. |
| Comparação sem métrica improved | noSignificantGain. |
| Uma ou mais métricas improved | improved com métricas; não implica que nenhuma outra piorou. |

Estados de permissão, offline e cancelamento não expostos especificamente pela implementação não são tratados como estados comprovadamente distintos. Resultados parciais aplicáveis estão descritos acima.

### Plataformas e acesso

iPhone/iPad usam NavigationStack/folha; Mac tem conteúdo próprio e destino contextual. Pacote declara iOS 16/macOS 13; compilação corrente não executada.
 Configuração de targets: [aplicativo-ios/project.yml](../../../aplicativo-ios/project.yml). Mínimo de pacote não comprova disponibilidade do recurso em dispositivo.

### Experiência e referências compartilhadas

- Entradas/destinos: ações descritas acima e views no mapa; folhas, confirmação, erro, detalhe e gestão precisam de validação visual no candidato.
- Acessibilidade: controles SwiftUI e labels existentes foram inspecionados nas views; VoiceOver, Dynamic Type, teclado e adaptação não foram executados.
- Fontes de aparência: [protótipo](../../design/prototipo/), [Design System](../../design/design_system/), [direção macOS](../../design/README.md). Não se declara conformidade visual por leitura de código.

## Mapa técnico

| Caminho relativo à raiz Git | Símbolos/responsabilidade |
|---|---|
| [aplicativo-ios/NetworkOptimization/Sources/NetworkOptimization.swift](../../../aplicativo-ios/NetworkOptimization/Sources/NetworkOptimization.swift) | `OptimizationPlanBuilder; OptimizationRetestComparator` |
| [aplicativo-ios/LinkaApp/Sources/UI/OptimizationView.swift](../../../aplicativo-ios/LinkaApp/Sources/UI/OptimizationView.swift) | `OptimizationView; OptimizationRetestResultView` |
| [aplicativo-ios/LinkaApp/Sources/UI/MainView.swift](../../../aplicativo-ios/LinkaApp/Sources/UI/MainView.swift) | `handleOptimizationRetestCompletion` |
| [aplicativo-ios/LinkaApp/Sources/UI/MacMainView.swift](../../../aplicativo-ios/LinkaApp/Sources/UI/MacMainView.swift) | `MacMainView` |

## Fluxo e contratos

OptimizationPlanBuilder avalia resposta sob carga, instabilidade por jitter/perda e latência abaixo do habitual com histórico elegível. Ordena por confiança e ID. Instabilidade Wi-Fi sugere proximidade; celular/Ethernet não recebem essa ação. Reinício é limitado a Wi-Fi/Ethernet. Comparador exige complete/tipo igual/SSID igual no Wi-Fi e delega diferenças a NetworkInsights. Não há checagem explícita de estabilidade de rota nesse comparador. Sessão no app; pacote não persiste nem chama IA/backend.

## Dependências e impacto

NetworkOptimization depende de NetworkCore e NetworkInsights. App recebe histórico; ambientes usam baseline do pacote, DNS é fluxo separado.

Alteração nas condições de acesso deve revisar [Plus](../linka-plus/README.md). Mudanças de dados ou fluxo exigem revisão dos consumidores citados, sem duplicar regra na UI.

## Operação e limitações técnicas

Sem configuração de servidor para regras locais; falha de histórico não pode justificar conclusão histórica inventada. Comparação é observação, não teste causal controlado.

## Critérios de aceite

Critérios para conferir a capacidade existente; não são testes declarados como aprovados.

| ID | Cenário | Resultado esperado | Fonte |
|---|---|---|---|
| AC-01 | Celular instável | Não orientar proximidade/reinício de roteador. | Mapa técnico e fluxo acima |
| AC-02 | Sem identidade histórica confirmada | Não inventar piora habitual. | Mapa técnico e fluxo acima |
| AC-03 | Reteste em Wi-Fi diferente ou incompleto | Não apresentar ganho comparável. | Mapa técnico e fluxo acima |

## Evidências existentes

| Critérios | Nível/ambiente | Base/data | Procedimento | Resultado e limite |
|---|---|---|---|---|
| AC-01 a AC-03 | Inspeção estática local | WIP descrito; 2026-10-04 | Leitura dos símbolos e busca com rg | Regras documentadas; não comprova runtime |

Fontes de testes existentes consultadas (não executadas nesta entrega):
- [aplicativo-ios/NetworkOptimization/Tests/NetworkOptimizationTests.swift](../../../aplicativo-ios/NetworkOptimization/Tests/NetworkOptimizationTests.swift).

Testes de pacotes/app, build, simulador, dispositivo físico, TestFlight, App Review e produção: **não executados/verificados nesta tarefa documental**. Nenhum plano foi marcado como entregue.

## Validação ainda necessária

| Cenário/risco | Responsável | Evento de revisão | Critério de fechamento |
|---|---|---|---|
| Revisar diferença da comparabilidade com Camillo/Íris antes de afirmar ganho em release; validar cancelamento/erro/reteste e todos os destinos Mac. | Tito, com executor autorizado | Antes da próxima release que inclua a capacidade | Evidência reproduzível da build candidata e dos cenários, ou decisão explícita de escopo |
| Acessibilidade e todos os destinos alcançáveis | Tito/Íris | Próxima validação visual da capacidade | Conferir estados aplicáveis em iPhone/iPad/Mac; registrar limitações por plataforma |

## Mudanças em andamento

A autorização desta sessão cobre documentação do WIP. Não concede implementação, encerramento de plano ou publicação. As fontes anteriores foram reconciliadas e removidas na [migração documental](../../MIGRACAO.md); expectativas ainda abertas permanecem abaixo.

Origem e substituições registradas na [migração](../../MIGRACAO.md).

Plano menciona oportunidade de banda com evidência e rota estável no antes/depois. Builder atual tem três tipos sem regra específica de banda; comparador confere tipo/SSID, não rota. DNS e ambientes, antes fases futuras no plano, já têm código e destinos neste WIP; isso não encerra o plano.

## Divergências e perguntas abertas

| Pendência | Responsável | Evento | Fechamento |
|---|---|---|---|
| Resolver/registrar diferenças acima entre planos, comentários e composição real | Codex principal, com especialista do tema | Integração documental e antes da release afetada | Decisão rastreável ou correção autorizada com evidência; não presumir entrega |

## Expectativas preservadas dos planos e estado

Esta tabela conserva trabalho aberto após a substituição das fontes antigas. Não constitui nova autorização de implementação.

| ID | Estado | Expectativa ou lacuna | Responsável | Evento | Critério de fechamento |
|---|---|---|---|---|---|
| OPT-P01 | Expectativa do plano não implementada no builder inspecionado | Oportunidade de banda exigindo banda/sinal/histórico confirmados; não há esse tipo no enum atual. | Íris/Camillo | Próxima evolução das regras | Decidir manter/deferir/remover; se mantida, regra e testes com evidência real. |
| OPT-P02 | Divergência de aceite | Plano exige rota estável no reteste; comparador atual não a verifica explicitamente. | Camillo/Tito | Antes de publicar promessa de comparabilidade | Critério alinhado a contrato/testes ou limitação explícita aprovada. |
| OPT-P03 | Futuro, sem implementação demonstrada | DoT e adaptadores de roteadores explicitamente compatíveis continuam fases futuras; DoH/DNS e ambientes têm documentação própria. | Íris/Luiz | Quando priorizados | Decisão de escopo e viabilidade antes de implementação. |
| OPT-P04 | Validação pendente | Cancelamento/offline/erro preservam baseline e retomada explícita; regressão de motor/histórico e acessibilidade pós-resultado. | Tito | Candidato de release | Evidência executada proporcional, sem chamar leitura estática de aprovação. |

Fontes das extensões: [Ambientes](../perfis-de-rede/README.md) e [DNS](../dns/README.md).
