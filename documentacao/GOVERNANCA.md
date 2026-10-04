# Governança

Responsável: Marco/Codex. Revisão: 2026-10-04, sobre main `39269c7a`. Fonte normativa única do Linka; `AGENTS.md` é apenas a entrada para agentes.

## Quatro documentos

| Fonte | Conteúdo |
|---|---|
| [Produto](PRODUTO.md) | Propósito, capacidades, jornada, design e decisões de produto |
| [Arquitetura](ARQUITETURA.md) | Módulos, contratos, persistência, falhas e limites técnicos |
| [Operação](OPERACAO.md) | Desenvolvimento, simuladores, validação, release e materiais de loja |
| Governança | Responsabilidades, autorização e manutenção dessas fontes |

Features são seções, não documentos. Decisões e pendências ficam junto do assunto. Não criar READMEs por feature, índices intermediários, templates, relatórios de migração, planos permanentes ou arquivos de decisões separados. Um detalhe que só importa à implementação pertence ao código/teste; uma evidência de entrega pertence à PR. O histórico dos documentos substituídos continua no Git.

README raiz serve apenas para chegar às quatro fontes. AGENTS/CLAUDE são entradas de ferramentas; skills/configurações de agentes, schemas, fixtures, assets e protótipos são artefatos técnicos. CHANGELOG e RELEASE_NOTES são registros de versão, não manuais paralelos. Não replicar esses arquivos no Obsidian como documentação do produto.

## Como decidir

A precedência é: pedido explícito do Luiz → código/testes para o comportamento existente → [protótipo](design/prototipo/) para fluxo/geometria → [Design System](design/design_system/) para tokens/componentes → esta governança → demais fontes atuais. Código não transforma uma divergência em decisão de produto; documentar a diferença entre o que existe e o que foi aprovado.

Marco é o interlocutor principal. Começar pelo problema, pessoa afetada, comportamento esperado e impacto. Pergunta ou hipótese é discussão; só pedido de execução autoriza implementar. Usar julgamento para escolhas técnicas pequenas e reversíveis, sem pedir confirmação a cada passo.

Luiz decide mudanças de produto em aberto, monetização, custo, publicação e ações destrutivas. Autorizações já dadas persistem dentro do seu escopo; não perguntar de novo. Preparação local, commit/PR/merge, TestFlight, App Review e publicação são operações distintas. O comando ou o documento que descreve uma delas não a autoriza.

## Squad

| Papel | Responsabilidade | Escrita |
|---|---|---|
| Marco/Codex | Delimitar, integrar, proteger WIP e comunicar resultado | No escopo solicitado |
| Íris | Produto, jornada, UX/UI, copy e critérios de aceite | Somente quando delegada; leitura por padrão |
| Camillo | Arquitetura, motor, contratos e integrações | Somente quando delegada |
| Pedro | Implementação delimitada e verificações | Somente quando delegada |
| Tito | Revisão independente, regressão, segurança e evidência | Leitura por padrão |

As configurações estão em [`.codex/agents`](../.codex/agents/). Usar os defaults de modelo/esforço do projeto e escalar pela criticidade, não pelo nome. Delegar só se especialização/paralelismo ajudar. Informar objetivo, checkout, arquivos, permissão de escrita, retorno e limites; evitar agentes escrevendo nos mesmos arquivos. Quando Luiz pedir Maestri, usar os agentes conectados por ele. Não simular handoff, revisão ou aprovação.

## Fluxo proporcional

Mudança pequena: delimitar → implementar → verificar → relatar. Sem plano, relatório ou chamada de toda a squad por obrigação.

Camillo investiga antes de implementar se houver múltiplos módulos, API/contrato compartilhado, integração entre sistemas/produtos ou superfícies Apple, schema/persistência transversal, motor, nova dependência estrutural, refatoração, segurança/privacidade sistêmica ou grande impacto de erro. O plano curto cabe na PR/issue ou em uma seção temporária da fonte afetada: problema, decisão, contratos, falhas, validação e limites. Ao concluir, conservar só a decisão durável.

Quando há decisão de produto, Íris ajuda a fechar comportamento e aceite. Pedro ou Codex implementa o plano; lacuna recuperável recebe a menor solução coerente. Contradição material volta ao responsável, sem arquitetura improvisada. Tito revisa quando risco justificar; Camillo retorna se a implementação materializar decisão arquitetural relevante.

Hotfix usa o menor escopo que corrige o defeito e validação proporcional; análise estrutural pode ocorrer depois conforme o risco. Não usar urgência para esconder refatoração ou publicar sem autorização. No máximo duas rodadas sobre o mesmo bloqueio técnico; depois reavaliar escopo e decisão, sem loop de agentes.

Tito classifica `BLOQUEIA` (defeito material), `AJUSTA` (correção nesta entrega) ou `ISSUE_FUTURA` (fora do escopo). O responsável integra os achados, sem declarar aprovação não recebida.

## Preservação e evidência

- Conferir branch, status e diff antes de alterar. Proteger WIP, arquivos não rastreados e worktrees de outras frentes. Não usar force push ou limpeza destrutiva sem autorização.
- Trabalhar em branch e limitar o commit ao escopo. Não embutir correções alheias para facilitar merge.
- Atualizar a fonte afetada na mesma entrega; registrar motivo, comportamento, validação e limite. Se nada documental mudou, basta explicar no retorno.
- Não inventar medições, causa de falha, funcionalidades, aprovação, teste, preço ou estado da loja. Ausência de dado não é zero medido.
- Distinguir inspeção de fonte, testes simulados de controles, teste/build do app, simulador, dispositivo físico, TestFlight, App Review e publicação. Registrar revisão, ambiente e resultado; um nível não prova o seguinte.
- Aceite visual exige a build pretendida no destino correspondente. No Mac, cobrir destinos alcançáveis: sidebar, toolbar/comandos, sheets, alertas, detalhes e ações destrutivas; não validar só a tela principal.
- Segredos não entram em cliente, Git, documentação ou mensagens. Mudanças de coleta/publicidade/privacidade exigem coerência entre implementação e comunicação pública.

## Manutenção enxuta

Antes de editar, ler esta governança e a seção do tema. Ao concluir, revisar links, retirar conteúdo substituído e manter somente o que muda uma decisão ou ajuda a operar. Não copiar listas de fontes e status em vários lugares.

Pendência material tem responsável, evento de revisão e condição de fechamento, numa linha ou tabela do assunto. “Validar depois” sem condição não encerra o trabalho. Bloqueio real continua visível; não criar outro documento para contorná-lo. Antes de release, conferir as seções afetadas contra a candidata, incluindo oferta, privacidade, materiais e diferenças de plataforma.

O Obsidian mantém apenas cópias dessas quatro fontes. A sincronização é pontual, identificada pelo commit; não há plugin/rotina instalada. Git é canônico. Reconciliar anotações pessoais antes de substituir cópias e não alterar notas de outros produtos.
