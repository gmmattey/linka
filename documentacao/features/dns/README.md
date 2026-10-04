# Comparar resposta e configurar DNS

Estado do documento: vigente para a inspeção estática declarada; validação de execução pendente.
Responsável: Codex principal; manutenção técnica por Pedro.
Última revisão: 2026-10-04 — código, contratos locais, fontes de testes e planos do tema.
Referências: [Governança](../../../AGENTS.md); [processo documental](../../GOVERNANCA_DOCUMENTAL.md); fontes abaixo.

Disponibilidade da feature: implementações locais descritas por plataforma abaixo; não atesta distribuição.
Base conferida: checkout WIP da branch `feat/macos-visual-direction-and-service-status`, HEAD `9eb1a094` mais alterações locais. Não é snapshot de main/produção.
Termos de busca: Resposta de DNS, DoH, NEDNSSettingsManager, NetworkDNSBenchmark.

## Propósito e limites

- Problema/resultado esperado: Comparar respostas DoH nesta conexão e permitir configuração explícita do provedor escolhido, sem prometer aumento de velocidade.
- Quem usa: pessoa usando o Linka no ecossistema Apple, nas condições de acesso descritas abaixo.
- Fora de escopo: Histórico DNS, automação, VPN, DoT, mudar roteador ou atribuir causalidade à diferença observada.

## Comportamento atual

| Entrada ou ação | Resposta do produto | Regra e fonte |
|---|---|---|
| Otimização → comparar DNS | Entrada Plus abre sessão sob ação explícita; Free recebe prévia. | isPlusActive controla navegação em OptimizationView. |
| Iniciar comparativo | Três rodadas, cinco provedores, mesma query por rodada, rotação determinística. | Cloudflare, Google, Quad9, OpenDNS, AdGuard; catálogo local. |
| Selecionar provedor válido e confirmar | Cria configuração própria DoH e consulta estado novamente. | Consentimento informa efeito no dispositivo, envio de consultas, política e remoção. |
| Remover configuração | Remove preferências do próprio manager e confirma ausência. | Não enumera perfis de terceiros; exige remoção antes de substituir configuração existente. |

As regras acima se referem aos símbolos do mapa técnico; são observação estática, não prova de jornada executada.

### Estados e recuperação

| Estado/condição | Comportamento e recuperação |
|---|---|
| Idle/running/cancelled/failed | Iniciar, cancelar ou tentar novamente; todos inconclusivos produzem failed. |
| Menos de duas respostas válidas | Candidato inconclusivo, sem zero sintético. |
| Medianas iguais | Sem vencedor único; seleção manual permanece factual. |
| Configuração salva mas não habilitada | awaitingActivation; active só com isEnabled após load. |
| Manager indisponível/erro | unavailable/failed; não afirmar DNS ativo. |

Estados de permissão, offline e cancelamento não expostos especificamente pela implementação não são tratados como estados comprovadamente distintos. Resultados parciais aplicáveis estão descritos acima.

### Plataformas e acesso

iPhone/iPad e Mac têm UI e adapter NetworkExtension. Entitlements dns-settings constam nos dois arquivos; isso não prova provisioning, aprovação Apple ou efeito system-wide.
 Configuração de targets: [aplicativo-ios/project.yml](../../../aplicativo-ios/project.yml). Mínimo de pacote não comprova disponibilidade do recurso em dispositivo.

### Experiência e referências compartilhadas

- Entradas/destinos: ações descritas acima e views no mapa; folhas, confirmação, erro, detalhe e gestão precisam de validação visual no candidato.
- Acessibilidade: controles SwiftUI e labels existentes foram inspecionados nas views; VoiceOver, Dynamic Type, teclado e adaptação não foram executados.
- Fontes de aparência: [protótipo](../../design/prototipo/), [Design System](../../design/design_system/), [direção macOS](../../design/README.md). Não se declara conformidade visual por leitura de código.

## Mapa técnico

| Caminho relativo à raiz Git | Símbolos/responsabilidade |
|---|---|
| [aplicativo-ios/NetworkDNSBenchmark/Sources/NetworkDNSBenchmark.swift](../../../aplicativo-ios/NetworkDNSBenchmark/Sources/NetworkDNSBenchmark.swift) | `DNSProviderCatalog; DNSBenchmarkPlan; DNSBenchmarkCandidate; DNSBenchmarkResult` |
| [aplicativo-ios/NetworkDNSBenchmark/Sources/DNSBenchmarkSessionGuards.swift](../../../aplicativo-ios/NetworkDNSBenchmark/Sources/DNSBenchmarkSessionGuards.swift) | `DNSPathSessionGate` |
| [aplicativo-ios/LinkaApp/Sources/Adapters/DNSBenchmarkCoordinator.swift](../../../aplicativo-ios/LinkaApp/Sources/Adapters/DNSBenchmarkCoordinator.swift) | `DNSBenchmarkCoordinator; DoHBootstrapTransport; DNSRequestDeadline` |
| [aplicativo-ios/LinkaApp/Sources/Adapters/DNSConfigurationManager.swift](../../../aplicativo-ios/LinkaApp/Sources/Adapters/DNSConfigurationManager.swift) | `SystemDNSConfigurationManager; DNSConfigurationCoordinator` |
| [aplicativo-ios/LinkaApp/Sources/UI/DNSBenchmarkView.swift](../../../aplicativo-ios/LinkaApp/Sources/UI/DNSBenchmarkView.swift) | `DNSBenchmarkView` |
| [aplicativo-ios/LinkaApp/Sources/UI/OptimizationView.swift](../../../aplicativo-ios/LinkaApp/Sources/UI/OptimizationView.swift) | `OptimizationView` |

## Fluxo e contratos

DNSSystemResolverProbe mede getaddrinfo(example.com) separado, fora do ranking. Benchmark usa DNS wire-format sobre TLS/HTTP 1.1 em NWConnection para IP bootstrap, com SNI/Host do provedor; deadline 2 s cancela socket. Sessão UUID evita resultado tardio; callback de caminho subsequente invalida sessão. Resultado efêmero não recebe repositório de histórico/perfis. Configuração do SO persiste via NEDNSSettingsManager; estado é recarregado, não inferido de save.

## Dependências e impacto

NetworkDNSBenchmark é pacote puro sem dependências locais; executor depende de Network/Security e configuração de NetworkExtension. UI depende de Otimização/Plus.

Alteração nas condições de acesso deve revisar [Plus](../linka-plus/README.md). Mudanças de dados ou fluxo exigem revisão dos consumidores citados, sem duplicar regra na UI.

## Operação e limitações técnicas

Capability dns-settings nos targets; confirmar assinatura/provisioning e políticas/endpoints antes da aplicação real. Não houve consulta aos provedores nem alteração do DNS nesta tarefa.

## Critérios de aceite

Critérios para conferir a capacidade existente; não são testes declarados como aprovados.

| ID | Cenário | Resultado esperado | Fonte |
|---|---|---|---|
| AC-01 | Falhas/timeout e uma resposta válida | Candidato não entra como vencedor válido. | Mapa técnico e fluxo acima |
| AC-02 | Troca de caminho/cancelamento | Sessão termina sem reaproveitar resultado antigo. | Mapa técnico e fluxo acima |
| AC-03 | Save sem isEnabled | Mostrar aguardando ativação, nunca ativa. | Mapa técnico e fluxo acima |

## Evidências existentes

| Critérios | Nível/ambiente | Base/data | Procedimento | Resultado e limite |
|---|---|---|---|---|
| AC-01 a AC-03 | Inspeção estática local | WIP descrito; 2026-10-04 | Leitura dos símbolos e busca com rg | Regras documentadas; não comprova runtime |

Fontes de testes existentes consultadas (não executadas nesta entrega):
- [aplicativo-ios/NetworkDNSBenchmark/Tests/NetworkDNSBenchmarkTests.swift](../../../aplicativo-ios/NetworkDNSBenchmark/Tests/NetworkDNSBenchmarkTests.swift).
- [aplicativo-ios/LinkaApp/Tests/DNSConfigurationCoordinatorTests.swift](../../../aplicativo-ios/LinkaApp/Tests/DNSConfigurationCoordinatorTests.swift).

Testes de pacotes/app, build, simulador, dispositivo físico, TestFlight, App Review e produção: **não executados/verificados nesta tarefa documental**. Nenhum plano foi marcado como entregue.

## Validação ainda necessária

| Cenário/risco | Responsável | Evento de revisão | Critério de fechamento |
|---|---|---|---|
| Validar ativação manual, reload, relaunch, remoção e conflitos VPN/MDM em iPhone/Mac assinados; verificar comportamento ao sair da tela durante request. | Tito, com executor autorizado | Antes da próxima release que inclua a capacidade | Evidência reproduzível da build candidata e dos cenários, ou decisão explícita de escopo |
| Acessibilidade e todos os destinos alcançáveis | Tito/Íris | Próxima validação visual da capacidade | Conferir estados aplicáveis em iPhone/iPad/Mac; registrar limitações por plataforma |

## Mudanças em andamento

A autorização desta sessão cobre documentação do WIP. Não concede implementação, encerramento de plano ou publicação. As fontes anteriores foram reconciliadas e removidas na [migração documental](../../MIGRACAO.md); expectativas ainda abertas permanecem abaixo.

Origem e substituições registradas na [migração](../../MIGRACAO.md).

Plano previa URLSession efêmera e ordem “randomizada”; execução atual usa NWConnection com bootstrap e rotação determinística. Provisioning físico e remoção/conflito continuam sem evidência nesta revisão.

## Divergências e perguntas abertas

| Pendência | Responsável | Evento | Fechamento |
|---|---|---|---|
| Resolver/registrar diferenças acima entre planos, comentários e composição real | Codex principal, com especialista do tema | Integração documental e antes da release afetada | Decisão rastreável ou correção autorizada com evidência; não presumir entrega |

## Expectativas preservadas dos planos e estado

Esta tabela conserva trabalho aberto após a substituição das fontes antigas. Não constitui nova autorização de implementação.

| ID | Estado | Expectativa ou lacuna | Responsável | Evento | Critério de fechamento |
|---|---|---|---|---|---|
| DNS-P01 | Validação pendente; gate anterior à aplicação | Endpoints/políticas dos cinco provedores, capability/provisioning, codesign real, App Privacy e notas de App Review. | Codex/Tito | Antes de liberar aplicação de DNS na release | Evidência de assinatura/ativação/remoção real e material público coerente. |
| DNS-P02 | Expectativa do plano ainda não demonstrada | Sem provisioning, comparação pode existir mas aplicar deve ficar indisponível. Declaração dns-settings não comprova esse gate nem funcionamento. | Pedro/Tito | Candidato sem capability e candidato assinado | Aplicação indisponível honestamente sem workaround; benchmark preservado. |
| DNS-P03 | Validação pendente | VoiceOver anuncia provedor, tempo, unidade e estado; Free não inicia consultas nem mostra candidatos. | Tito | Próxima validação visual | Percurso real Free/Plus, cancelamento, troca de rede e leitura acessível documentados. |
