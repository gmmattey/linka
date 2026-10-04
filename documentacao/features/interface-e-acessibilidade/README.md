# Interface Apple e acessibilidade

Estado do documento: vigente para o mapa estático; aceite visual e acessível pendente.
Responsável: Codex principal; Íris orienta experiência, Tito valida quando acionado.
Última revisão: 2026-10-04 — navegação principal, destinos secundários e pontos de acessibilidade no código.
Base conferida: WIP da branch `feat/macos-visual-direction-and-service-status`, HEAD `9eb1a094` mais alterações locais; não produção/main.
Referências: [produto](../../PRODUTO.md), [design](../../design/README.md), [governança](../../../AGENTS.md).
Disponibilidade: código condicionado para iOS/iPadOS e macOS; execução, distribuição e paridade não comprovadas nesta revisão.
Termos de busca: Home, Velocímetro, Histórico, Ajustes, Assist, Otimização, acessibilidade, VoiceOver, Dynamic Type, sidebar, sheets.

## Propósito e limites

A pessoa deve conseguir medir, ler o resultado e acessar contexto sem se perder entre telas. A interface adapta a apresentação ao dispositivo e mantém medição, observação atual e interpretação distinguíveis. Esta fonte descreve navegação e apresentação; não especifica a metodologia do motor, contratos remotos, política comercial ou resultados de desempenho.

## Entradas, dados e estado

[LinkaApp.swift](../../../aplicativo-ios/LinkaApp/Sources/LinkaApp.swift) compõe a janela e escolhe `MacMainView` no Mac ou `MainView` nas demais plataformas. `LinkaMacCommands` envia pedidos ao coordenador: medir (`⌘R`), cancelar (`⌘.`) e abrir Ajustes (`⌘,`, desabilitado durante medição).

[MainView](../../../aplicativo-ios/LinkaApp/Sources/UI/MainView.swift) recebe `SpeedTestViewModel`, estado de entitlement e pedidos do coordenador de intents. `AppRoute` modela Ajustes, Histórico e detalhe de medição. O `NavigationStack` e os grupos `attachAssistPresentation`, `attachResultPresentation`, `attachSecondaryPresentation` materializam os destinos. Estado de apresentação fica em propriedades SwiftUI; os dados de medição e histórico vêm dos adaptadores, não são produzidos pela View.

Fluxo: ação da pessoa/intenção → coordenação → ViewModel → fase/medição publicada → tela de medição ou resultado → detalhe, compartilhamento ou reteste. Assist seleciona objetivo, pode aguardar nova medição e então apresenta a leitura. `pendingAssistMeasurement` evita tratar contexto anterior como nova coleta. A correção de execução desse fluxo não foi testada aqui.

## Mapa de navegação observado

Os links abaixo apontam para a implementação; nomes entre crases são símbolos ou estados que permitem localizar os caminhos. O mapa é inventário estático para orientar validação, não declaração de que todos os destinos foram exercitados.

| Entrada | Destinos e ações alcançáveis | Fonte |
|---|---|---|
| Home iPhone/iPad | Medir, Histórico, Ajustes, compartilhar resultado; fases idle/connecting/downloading/uploading/done/error/connectionChanged | [MainView, AppRoute](../../../aplicativo-ios/LinkaApp/Sources/UI/MainView.swift) |
| Resultado/Home secundária | Detalhes, adequação de uso, detalhe de uso vivo, caminho da conexão, triagem de conectividade; recuperação de Wi-Fi avançado e aviso de migração Expert | [attachResultPresentation, attachSecondaryPresentation](../../../aplicativo-ios/LinkaApp/Sources/UI/MainView.swift) |
| Assist | Seleção de problema/objetivo, coleta, resultado, tentar novamente, detalhes; acesso condicionado pela política de entitlement | [AssistProblemSelectionView](../../../aplicativo-ios/LinkaApp/Sources/UI/AssistProblemSelectionView.swift), [AssistView](../../../aplicativo-ios/LinkaApp/Sources/UI/AssistView.swift) |
| Sidebar Mac | Velocímetro, Histórico, Assist, Otimização, Ajustes; `MacDestination` tem esses cinco destinos | [MacMainView](../../../aplicativo-ios/LinkaApp/Sources/UI/MacMainView.swift) |
| Modais Mac | Compra, gestão de assinatura, seletor/resultado Assist, triagem, resultado do reteste, detalhe histórico/atual, uso, caminho da conexão, alerta Wi-Fi indisponível | [MacMainView, modificadores sheet/alert](../../../aplicativo-ios/LinkaApp/Sources/UI/MacMainView.swift) |
| Histórico | Filtro all/wifi/mobile, ordenação recent/fastest/slowest, seleção de medição e compra | [HistoryView](../../../aplicativo-ios/LinkaApp/Sources/UI/HistoryView.swift), [HistoricalMeasurementDetailView](../../../aplicativo-ios/LinkaApp/Sources/UI/HistoricalMeasurementDetailView.swift) |
| Detalhe de medição | Métricas e contexto; compra em `MeasurementDetailView`; histórico tem View própria | [MeasurementDetailView](../../../aplicativo-ios/LinkaApp/Sources/UI/MeasurementDetailView.swift) |
| Ajustes | Aparência, idioma, Plus/gestão de assinatura, Ambientes, roteador, Status de serviços, identificação Wi-Fi, Wi-Fi avançado e links externos | [SettingsView em SettingsSheet.swift](../../../aplicativo-ios/LinkaApp/Sources/UI/SettingsSheet.swift) |
| Roteador | iOS usa RouterDiscoveryView; Mac usa MacRouterPanelView com localização, encontrado, inacessível/indisponível e confirmação para abrir painel | [RouterDiscoveryView](../../../aplicativo-ios/LinkaApp/Sources/UI/RouterDiscoveryView.swift), [MacRouterPanelView](../../../aplicativo-ios/LinkaApp/Sources/UI/SettingsSheet.swift) |
| Otimização | Oportunidade/conclusão, reteste, criação de ambiente e navegação para comparação DNS | [OptimizationView, OptimizationRetestResultView](../../../aplicativo-ios/LinkaApp/Sources/UI/OptimizationView.swift) |
| DNS | Comparação e confirmação explícita para criar configuração | [DNSBenchmarkView](../../../aplicativo-ios/LinkaApp/Sources/UI/DNSBenchmarkView.swift) |
| Ambientes | Lista, detalhe, edição de nome, confirmação de exclusão | [NetworkProfilesManagementView, NetworkEnvironmentDetailView, NetworkProfileNameEditor](../../../aplicativo-ios/LinkaApp/Sources/UI/NetworkProfilesSection.swift) |
| Status de serviços | Busca, grupos, atualização, erro/vazio, expansão de incidente e controles de acompanhamento conforme elegibilidade | [ServiceStatusView](../../../aplicativo-ios/LinkaApp/Sources/UI/ServiceStatusView.swift) |
| Compra e compartilhamento | PurchaseSheet e apresentação de compartilhamento; disponibilidade depende de plataforma/estado | [PurchaseSheet](../../../aplicativo-ios/LinkaApp/Sources/UI/PurchaseSheet.swift), [ShareSheet](../../../aplicativo-ios/LinkaApp/Sources/UI/ShareSheet.swift) |

## Estados e recuperação

| Condição | Apresentação observada / ação | Limite |
|---|---|---|
| Home sem evidência suficiente | Estado warming; detalhes da leitura viva | Não equivale a medição de banda. |
| Sem rota | Estado offline e caminhos de recuperação | Não diagnostica sozinho se falha é provedor ou roteador. |
| Medindo | Fase de medição, atualização de métricas e cancelamento | Animação não é evidência da precisão do motor. |
| Resultado ou parcial | Detalhes recebem a medição; campos opcionais exigem apresentação honesta | Todas as combinações de ausência/parcial não foram exercitadas. |
| Erro/troca de conexão | Ramos próprios e possibilidade de nova tentativa | Mensagens e restauração de estado exigem teste no app. |
| Histórico 0/1/2+ | `HistoryVisualizationState.resolve`: empty/singleMeasurement/trend | Uma medição não é tendência. Ordenação usa fallback numérico para ausentes: não confundir com valor exibido. |
| Wi-Fi negado/desativado/indisponível | Estados separados nos Ajustes; diálogo oferece ações conforme estado | Não prometer dado que a plataforma não expõe. |
| Ação destrutiva | Ambientes usam confirmationDialog para exclusão | Persistência e reversibilidade não auditadas nesta feature documental. |

## Plataformas, preferências e acessibilidade

| Plataforma | Implementação observada | Validação necessária |
|---|---|---|
| iPhone | NavigationStack, toolbar, sheets, rótulos acessíveis e áreas mínimas em ações principais | Dispositivo compacto, Safe Areas, teclado, VoiceOver e texto ampliado. |
| iPad | `horizontalSizeClass == .regular` guia `isPad` em MainView; não é detecção infalível de hardware | Split View/largura compacta e regular, rotação, modais e texto ampliado. |
| Mac | Sidebar própria em HStack e NavigationStack; mínimo declarado 960×600, lateral 280 no Velocímetro; comandos nativos | Redimensionamento, foco, teclado, VoiceOver e todos os destinos secundários. Sidebar nativa é direção de produto; estrutura SwiftUI não prova aderência visual. |

`MainView` lê `accessibilityReduceMotion` e desliga animação de fase quando necessário; `LinkaScreenBackground` também considera essa preferência, não recebe toque e é oculto da acessibilidade. `LiveUsageCasesView` combina elementos e fornece label/hint textual. Toolbar da Home tem labels para voltar, Histórico, compartilhar e Ajustes. Esses recursos são evidência de implementação, não certificação de acessibilidade.

[DesignSystem.swift](../../../aplicativo-ios/LinkaApp/Sources/UI/DesignSystem.swift) usa cores dinâmicas UIKit/AppKit e estilos de texto nativos. [LinkaWidgetShared.swift](../../../aplicativo-ios/LinkaWidgetShared/Sources/LinkaWidgetShared.swift) e os testes de Ajustes dão referências a aparência sistema/claro/escuro e idioma sistema/português/inglês/espanhol latino-americano. Textos literais ainda existem, por exemplo em Status de serviços e comandos Mac; não afirmar localização integral.

## Dependências e limites

- [SpeedTestViewModel](../../../aplicativo-ios/LinkaApp/Sources/Adapters/SpeedTestViewModel.swift): fases, resultados e coordenação; mudanças afetam consumidores visuais.
- [LinkaEntitlements](../../../aplicativo-ios/LinkaEntitlements/Sources/LinkaEntitlements.swift): acesso a recursos; esta documentação não fixa preço, promoção ou disponibilidade comercial.
- Histórico, Assist, DNS e Ambientes têm dados/serviços próprios; navegar para a tela não comprova disponibilidade remota, sincronização ou configuração do sistema.
- Preferências, credenciais, medição e dados de rede não devem ser copiados para evidências públicas. Esta revisão não certifica privacidade do compartilhamento nem retenção dos módulos.
- Os planos anteriores de raiz e `.agents/` misturam Home viva, Histórico e outras iniciativas: critérios ali escritos não foram promovidos a entrega concluída. O ledger abaixo preserva decisões e lacunas relevantes para substituí-los no tema de interface.

## Critérios de aceite

| ID | Cenário | Resultado esperado | Fonte |
|---|---|---|---|
| UI-01 | Medir e repetir | Ação explícita, resultado protagonista, cancelamento/erro compreensíveis | [Produto](../../PRODUTO.md) |
| UI-02 | Histórico 0/1/2+ | Vazio, resumo único e tendência distinguíveis | `HistoryVisualizationState` |
| UI-03 | Navegação de cada plataforma | Todos os destinos do mapa acessíveis, com saída e foco coerentes | Código ligado no mapa e [design](../../design/README.md) |
| UI-04 | VoiceOver/teclado/texto ampliado | Estado compreensível sem depender só de cor; ações identificáveis e utilizáveis | [Design](../../design/README.md) |
| UI-05 | Reduzir Movimento/tema | Conteúdo e controles legíveis sem animação obrigatória | MainView, LinkaScreenBackground, DesignSystem |
| UI-06 | Permissão e dado ausente | Não tratar indisponível como zero, saudável ou permissão concedida | SettingsView e [produto](../../PRODUTO.md) |

## Evidência e validação pendente

Em 2026-10-04, inspeção estática do WIP pelos símbolos e modificadores acima. Foram lidos testes existentes [SettingsProductionStateTests](../../../aplicativo-ios/LinkaApp/Tests/SettingsProductionStateTests.swift), incluindo preferências/idiomas/estados Wi-Fi, e [UsageSuitabilityCopyQualityLevelTests](../../../aplicativo-ios/LinkaApp/Tests/UsageSuitabilityCopyQualityLevelTests.swift), incluindo `testHistoryVisualizationOnlyShowsTrendWithTwoOrMoreMeasurements`. A leitura comprova a presença das asserções para UI-02/UI-06, não seu resultado de execução. UI-01/UI-03/UI-04/UI-05 têm referências estáticas, sem aceite de runtime.

Não executados: testes do app/pacotes, build, simulador, Mac instalado, iPhone/iPad físico, VoiceOver, contraste, Dynamic Type ou revisão visual. Não há aprovação de publicação.

| Pendência / divergência | Responsável | Evento | Critério de fechamento |
|---|---|---|---|
| Validar mapa completo, incluindo menus, detalhe aninhado, modal, alerta e ação destrutiva | Tito | Próxima mudança de UI ou antes de declarar padronização | Matriz destino×estado×plataforma, build identificada e evidência sem lacunas ocultas. |
| Home/resultado reais versus critérios de hierarquia | Íris + Tito | Próxima revisão visual | Comparação com design em todos os estados; decisão explícita sobre divergência material. |
| Acessibilidade e localização integral não comprovadas | Tito + executor | Próxima entrega que tocar essas superfícies | VoiceOver, teclado, texto ampliado, contraste e idiomas conferidos, problemas registrados com reprodução. |
| Qual trecho do plano ainda está ativo | Orquestrador | Próxima implementação dependente | Estado/escopo confirmado sem declarar plano entregue por inspeção. |

## Consolidação e mudanças em andamento

### Ledger visual atual e decisões ainda abertas

As origens são identificadores de documentos anteriores, não links que devam permanecer após a remoção. Registro em 2026-10-04 baseado em leitura do WIP, sem nova autorização de implementação.

| Origem / tema | Decisão ou fato que fica | Estado / pendência | Responsável, evento e fechamento |
|---|---|---|---|
| `plano-jornada-apple-sem-navbar.md` | Medição explícita; contexto vivo separado do resultado salvo; navegação secundária contextual no iOS, sem tab bar como requisito novo | MainView tem NavigationStack, toolbar e sheets; cancelamento por troca de rota e integridade de dados exigem validação própria | Executor/Tito, próxima mudança de jornada: comprovar ausência de início involuntário, retorno e não mistura de rotas. |
| `plano-direcao-visual-mac-ios.md` | Escopo foi restringido ao Mac; não transportar redesign do Mac para iOS por analogia | Pills/dashboard/gauge históricos não são direção atual; sidebar e resultado primeiro prevalecem. Não reabrir redesign ao remover plano | Íris/orquestrador, integração: conservar direção do design e registrar qualquer mudança nova como decisão própria. |
| `documentacao/features/interface-e-acessibilidade/README.md` | Ação explícita, progresso real, evitar métricas residuais; proteger medição de navegação concorrente | Aceite antigo 780×560 conflita com mínimo atual 960×600; gauge antigo não deve voltar por documento | Íris + executor, próxima mudança de janela: decidir mínimo suportado e validar medidas escolhidas no Mac; não anunciar 780×560 como suportado. |
| `documentacao/features/interface-e-acessibilidade/README.md` | iPad no build e adaptação por largura, sem impor sidebar/split | Plano de coluna 720 está superado no comentário e implementação de `LinkaAdaptiveContentWidthModifier`: regular sem cap, compact 500. `project.yml` declara família 1,2; plist possui orientações iPad | Tito, próxima validação iPad: testar retrato/paisagem, Split View, larguras e sheets na build identificada; registros antigos de outro worktree não validam esta base. |
| `documentacao/features/interface-e-acessibilidade/README.md` | Mesmos modelos/coordenadores, interface adequada à plataforma; não inventar APIs/hardware | Detalhes, share, roteador e intents têm caminhos no código, mas paridade integral não foi provada; antigo veto a painel do roteador não descreve MacRouterPanelView atual | Executor/Tito, próxima entrega de paridade: testar capacidades/gates por plataforma, permissões concedidas/negadas e compartilhamento sem dado sensível. |
| `plano-issue-149-apple-ui-consistency.md` | Controles nativos, estilos comuns, hierarquia e estados compreensíveis | Inventário antigo de headers/cards/PlusBadge não prova defeito atual nem correção completa | Íris/Tito, próxima padronização: comparar cada destino do mapa, incluindo aninhados, sem declarar família pronta só pela raiz. |
| `plano-issue-135-finalizar-ajustes.md` | Ajustes controla aparência, assinatura, Wi-Fi, suporte e versão; estados distintos e links específicos | Código/testes atuais usam origem web.app, não proposta linka.app; estados estão mapeados. Gates de ads/assinatura/Release não auditados aqui | Responsáveis pelos módulos/Tito, próxima revisão Release: confrontar política, configuração e estados reais; documentação não dá aprovação de release. |
| `plano-correcoes-produto.md` | Resultado antes de interpretação; Assist não usa contexto inexistente; acessibilidade em todas as plataformas | Segurança/relay e metodologia não pertencem a este ledger visual e não foram fechados | Orquestrador, migração de planos: encaminhar itens sistêmicos ao ledger do módulo; Tito valida UI quando houver build candidata. |
| `.agents/plano.md` — Home viva e Histórico #236 | Uma fonte de evidência da Home, ausência de throughput não é medição; Histórico distingue 0/1/2+ | Código de apresentação existe; plano composto também contém motor/persistência, fora desta revisão | Orquestrador, integração: separar estados por tema; executor/Tito comprovam cenários vivos e histórico, sem concluir todo o plano. |
| Plano de direção Mac — distribuição, CloudKit e widget | Eram perguntas/gates remanescentes da implementação histórica | Estado atual de provisionamento, loja e widget Mac não investigado nesta revisão visual | Orquestrador, próxima decisão da respectiva capacidade: conferir artefato/serviço e registrar disponibilidade; não herdar bloqueio antigo como diagnóstico atual. |

O [design](../../design/README.md) conserva a decisão de 16/09 e o alcance parcial de sua auditoria. As fontes de código para largura e configuração são [DesignSystem](../../../aplicativo-ios/LinkaApp/Sources/UI/DesignSystem.swift), [project.yml](../../../aplicativo-ios/project.yml) e [Info.plist](../../../aplicativo-ios/LinkaApp/Info.plist). Nenhum registro histórico de build/teste foi reapresentado como executado nesta sessão.

Esta entrega documenta o WIP sem alterá-lo. Absorve o mapa operacional da interface que não existia de forma consolidada nas antigas fontes de visão/design; a direção visual permanece na [fonte de design](../../design/README.md). Código preservado; planos anteriores consolidados nas fontes por tema e no ledger. Índices e remoções estão registrados na [migração](../../MIGRACAO.md).
