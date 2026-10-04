# Design do Linka

Estado: vigente como direção e mapa das fontes; conformidade visual atual não validada.
Responsável: Codex principal; Íris mantém intenção e critérios.
Última revisão: 2026-10-04 — decisões anteriores, inventário de recursos e leitura estática do WIP `9eb1a094` com alterações locais.
Referências: [produto](../PRODUTO.md), [governança](../../AGENTS.md), [interface real](../features/interface-e-acessibilidade/README.md), [site](../features/site-institucional/README.md).
Substituição documental: conteúdo de `design_system/readme.md` e `DIRECAO_VISUAL_MACOS.md` consolidado aqui; fontes substituídas removidas e referências atualizadas na [migração](../MIGRACAO.md).

## Como usar

Para intenção e voz, começar pelo [produto](../PRODUTO.md). Para destinos existentes, usar o [mapa da interface](../features/interface-e-acessibilidade/README.md). O [protótipo](prototipo/) orienta fluxo e geometria; o [Design System](design_system/) orienta tokens, identidade e componentes. A precedência é a do AGENTS.md: divergências com comportamento real ficam explícitas, não são apagadas por uma declaração de conformidade.

Este README não substitui assets, protótipo, componentes ou tokens e não transforma demos em capacidade de produção.

## Identidade e recursos preservados

| Recurso | Uso e limite |
|---|---|
| [Wordmark oficial](design_system/assets/wordmark.svg) | Marca completa quando requerida; não substituir por texto puro. |
| [Ícones](design_system/assets/icons/) | Fonte de verdade de símbolos e variantes de app/plataforma; ícone do app é símbolo, não wordmark. |
| [Tokens](design_system/tokens/) | Cores, tipografia, espaçamento e movimento CSS. |
| [Componentes](design_system/components/) | Brand, core, layout, content e speedtest; presença no catálogo não prova uso pelo app. |
| [Guidelines](design_system/guidelines/) | Espécimes de cores, tipografia, marca, plataformas e componentes; conferir antes de reutilizar. |
| [Protótipo](prototipo/) | HTML, frames e recursos de referência preservados, inclusive material histórico que precisa de classificação. |
| [DesignSystem.swift](../../aplicativo-ios/LinkaApp/Sources/UI/DesignSystem.swift) | Implementação nativa de `Color`, `Font`, controles e `LinkaMotion`. |
| [LinkaScreenBackground](../../aplicativo-ios/LinkaApp/Sources/UI/LinkaScreenBackground.swift) | Fundo implementado com variantes `fullScreen`, `heroCard`, `gradientOnly`, tema e Reduzir Movimento. |

Identidade usa tinta azul e acento quente; fontes nativas, hierarquia por tipografia e espaço, números legíveis e controles confortáveis. Tokens CSS e Swift não são gerados automaticamente um do outro nesta documentação. Swift usa superfícies e cores de texto semânticas UIKit/AppKit; tipografia arredondada é reservada a métricas em vários estilos, enquanto títulos de conteúdo usam desenho padrão. Não afirmar igualdade literal entre CSS e app.

O antigo README descrevia início automático, idioma apenas pt-BR, fundos sempre planos, ausência de navegação/modais e apenas dois ícones. Essas descrições não são regra do WIP atual. Gradientes e cores de estado existem no código. As alegações antigas de contraste AA são registros da fonte anterior, não medições refeitas nesta revisão.

## Catálogo de componentes preservados — leitura do JSX

Os 19 componentes abaixo são implementações React de referência. Não são wrappers de SwiftUI nem prova de uso pelo site atual, que tem Header/Footer próprios. Seus antigos `*.prompt.md` serão substituídos por este mapa; não são requisitos adicionais. Props citadas são as que o JSX lê, não promessa de suporte a qualquer atributo HTML.

| Família / componentes | Comportamento e limites de uso |
|---|---|
| [Wordmark](design_system/components/brand/Wordmark.jsx) | SVG com `role=img`, label linka, tamanhos sm/md/lg e cores configuráveis. Mantém marca vetorial; conferir contra asset oficial ao alterar. |
| [Button](design_system/components/core/Button.jsx) | `plain`, `subtle`, `tinted`, `filled`; fallback plain. `icon`, `onClick`, children e style. Altura mínima explícita só para tinted/filled; não é “único ghost”. Não repassa genericamente disabled/aria/type; validar semântica antes de uso em formulário/ícone isolado. |
| [Card](design_system/components/core/Card.jsx) | Container com borda contínua ou dashed, label opcional e padding. Não implica que toda seção deva virar card. |
| [Eyebrow](design_system/components/core/Eyebrow.jsx) | Texto mono em caixa alta, size sm/md, tone e tag configuráveis. Usar como apoio, não substituir heading semântico por aparência. |
| [Icon](design_system/components/core/Icon.jsx) | Chevron nas três direções, retry, arrow-right, close e menu. Nome desconhecido gera SVG sem paths. Não fornece label acessível por prop; consumidor precisa definir semântica do controle. |
| [TextLink](design_system/components/core/TextLink.jsx) | Link com seta opcional; href default `#` é placeholder, precisa de destino real. |
| [StatusLabel](design_system/components/core/StatusLabel.jsx) | Ponto e texto, tone active ou aparência alternativa; não mede estado nem declara aria-live. |
| [SiteHeader](design_system/components/layout/SiteHeader.jsx) | Marca, items e activeHref; homeHref default `#`, item ativo usa `#`. Consumidor define navegação real. |
| [SiteFooter](design_system/components/layout/SiteFooter.jsx) | Marca, copyright e tagline; defaults demonstrativos, inclusive ano fixo. Não substitui Footer de produção automaticamente. |
| [PageHero](design_system/components/layout/PageHero.jsx) | Eyebrow opcional, h1, lead, children; align e maxWidth. Evitar múltiplos h1 não planejados. |
| [ValueCard](design_system/components/content/ValueCard.jsx) e [StepItem](design_system/components/content/StepItem.jsx) | Composições Card/Eyebrow para texto, ação ou etapa numerada. Não autorizam promessas de valor nem criam jornada por si. |
| [ComparisonTable](design_system/components/content/ComparisonTable.jsx) | Grade de divs com colunas, rows e destaque. Não é tabela HTML semântica; precisa revisão de acessibilidade se apresentar dados tabulares reais. |
| [LegalSection](design_system/components/content/LegalSection.jsx) | section/h2/conteúdo e spacing; organiza texto, não valida conteúdo jurídico. |
| [MetricRing](design_system/components/speedtest/MetricRing.jsx) | Recebe progress/value/unit/connecting/size e desenha anel. Não mede, não limita automaticamente progress à faixa válida e não fornece descrição acessível completa. Não restaura gauge no Mac contra direção vigente. |
| [PhaseDots](design_system/components/speedtest/PhaseDots.jsx) | Recebe phases/activeKey; representa ordem e fase. A fonte consumidora deve fornecer estado real e descrição acessível. |
| [StatDisplay](design_system/components/speedtest/StatDisplay.jsx) | label/value/unit/accent; tipografia responsiva via clamp. Não tem prop size nem formatação/validação automática de métricas. |
| [DetailsDisclosure](design_system/components/speedtest/DetailsDisclosure.jsx) | Estado local, defaultOpen falso e aria-expanded. Área aberta limitada a 160px, fechada por altura/opacidade; conteúdo longo/foco precisam conferência. |
| [AdSlot](design_system/components/speedtest/AdSlot.jsx) | Placeholder Card dashed para leaderboard 728×90 ou banner 320×50, label/note. Não integra SDK, entitlement, consentimento ou posição na jornada. Não estabelece anúncio no resultado Web; o site não mede e a política do app vem do módulo de anúncios. |

Antes de reutilizar, verificar props e teclado, foco, toque, conteúdo longo, movimento reduzido e contraste no destino. As limitações acima são observadas no código e não autorizam mudança de componente nesta entrega. Executor e Tito devem fechá-las no evento de adoção do componente, com comportamento real e evidência acessível registrada.

## Direção macOS preservada — decisão de 16/09/2026

O Mac é um espaço calmo para **medir, entender e agir**. Mais área de tela não autoriza mostrar tudo. Esta direção é específica do Mac e não redesenha implicitamente iPhone/iPad.

1. Um resultado, estado ou decisão principal por tela e uma ação primária por estado.
2. Assist e Otimização ficam no cabeçalho ou em camada seguinte, sem competir com a ação principal.
3. Métricas auxiliares, diagnóstico físico, metadados e explicações usam expansão, detalhe ou sheet; ficam fechados quando desnecessários à primeira decisão.
4. Cada dado tem um lugar; não repeti-lo em hero, card, lateral e rodapé.
5. Sidebar nativa, estável, com wordmark oficial; símbolo no ícone do app. Conteúdo com largura deliberada; lateral apenas para contexto recorrente, sem duplicação.
6. Páginas utilitárias preferem listas, seções e separadores a cartões decorativos.
7. Vazio explica falta, importância e próximo passo. Erro começa pelo resumo compreensível; resposta técnica longa vai para detalhe. Dado não confirmado não recebe aparência de certeza.
8. Sheets trazem título e decisão no topo, ação explícita, cancelamento nativo e rolagem só quando necessária.

| Família | Critério de leitura |
|---|---|
| Velocímetro | Download/upload protagonistas, repetir como ação única, detalhes e rede recolhidos. |
| Histórico | Tendência quando aplicável e lista densa; profundidade na medição aberta. |
| Assist | Pergunta e caminho primeiro; medição como contexto compacto. |
| Otimização | Uma oportunidade ou conclusão primeiro; comparar/retestar como passos seguintes. |
| DNS | Estado do resolvedor e decisão de comparar; metodologia em camada secundária. |
| Ajustes e Ambientes | Seções agrupadas, listas e próximo passo concreto no vazio. |
| Status de serviços | Resumo curto por serviço; conteúdo remoto extenso em detalhe. |

## Auditoria histórica e alcance atual

O documento anterior registra inspeção do app Mac instalado em 16/09/2026, com medição e dados locais reais: resultado do Velocímetro aprovado naquela inspeção; Histórico, seleção do Assist, Ajustes e Ambientes vazio considerados saudáveis; Otimização sem oportunidade e Status de serviços precisavam ajuste; DNS indisponível precisava ajuste leve.

Esse registro não identifica aqui uma build reproduzida nesta sessão e não valida o WIP de 04/10. Preservam-se as pendências históricas: DNS carregando/erro, Assist resultado/erro, oportunidades e reteste de Otimização, detalhe do Histórico, Ambientes preenchidos, sheets e alertas. Código atual já contém expansões em Status de serviços, mas isso não fecha o aceite visual.

## Critérios e validação

| ID | Critério | Evidência disponível nesta revisão |
|---|---|---|
| DS-01 | Marca e símbolos usam fontes oficiais. | Assets e pontos de implementação localizados; renderização não conferida. |
| DS-02 | Mac respeita hierarquia e divulgação progressiva em todos os destinos. | Direção preservada e navegação mapeada; aceite visual não executado. |
| DS-03 | Tema, contraste, teclado, VoiceOver e tamanho de texto mantêm leitura e controle. | APIs semânticas, rótulos e tratamento de movimento identificados; medições/testes manuais não executados. |
| DS-04 | Demos e tokens não prometem comportamento inexistente. | Divergências conhecidas registradas; revisão integral dos espécimes pendente. |

Aceite visual exige a build pretendida instalada: percorrer sidebar, toolbar, menu, navegação, sheets, alertas e detalhes aninhados nos estados vazio, carregando, resultado, erro e destrutivo que existirem. Verificar ação principal, ausência de repetição, leitura em janela ampla e estreita, foco e rotulagem. Inspeção visual não substitui teste de teclado, VoiceOver, contraste ou Dynamic Type.

## O que precisa atualização

| Item preservado | Lacuna | Responsável / evento | Fechamento |
|---|---|---|---|
| Protótipo e frames, incluindo frame Android histórico | Não representam automaticamente o produto Apple atual ou todas as rotas | Íris + orquestrador, ao tocar o fluxo | Identificar referências aplicáveis e históricas sem apagar assets arbitrariamente. |
| Guidelines e descrições de componentes | Podem conservar início automático, copy antiga, cores/contraste e limites já superados | Íris + executor, próxima manutenção de design | Comparação com Swift/CSS e registro de divergências por componente. |
| Tokens CSS e Swift | Mapeamento semântico não equivale a igualdade de valores | Executor + Tito, próxima mudança visual | Matriz dos tokens tocados e contraste medido no destino real. |
| Catálogo de componentes | Fonte anterior listava lacunas em lista/linha/nav/sheet/switch/segmentado, animação de entrada, tamanho de StatDisplay, divisor e ilustrações de linha | Íris, ao reutilizar esses padrões | Conferir o catálogo atual e decidir se falta componente; não implementar por herança da lista. |
| Famílias macOS | Auditoria histórica parcial | Tito, antes de declarar padronização/release afetada | Matriz de destinos/estados com build e evidência, inclusive pendências históricas. |

Não houve teste, build, captura de tela, abertura de app ou alteração de recursos visuais nesta entrega documental.
