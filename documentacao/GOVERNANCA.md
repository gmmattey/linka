# Governança

Responsável: Giam & Marco (Squad Linka). Revisão: 2026-10-15. Fonte normativa única do Linka; `AGENTS.md` é apenas a entrada rápida para agentes.

## Quatro documentos

| Fonte | Conteúdo |
|---|---|
| [Produto](PRODUTO.md) | Propósito, capacidades, jornada, design e decisões de produto |
| [Arquitetura](ARQUITETURA.md) | Módulos, contratos, persistência, falhas e limites técnicos |
| [Operação](OPERACAO.md) | Desenvolvimento, simuladores, validação, release e materiais de loja |
| Governança | Responsabilidades, pistas de execução, autorização e manutenção dessas fontes |

Features são seções, não documentos. Decisões e pendências ficam junto do assunto. Não criar READMEs por feature, índices intermediários, templates soltos fora de `.agents/`, relatórios de migração, planos permanentes ou arquivos de decisões separados. Um detalhe que só importa à implementação pertence ao código/teste; uma evidência de entrega pertence à PR e ao Cartão de Missão da rodada. O histórico dos documentos substituídos continua no Git.

README raiz serve apenas para chegar às quatro fontes. AGENTS/CLAUDE são entradas de ferramentas; skills/configurações de agentes, schemas, fixtures, assets e protótipos são artefatos técnicos. CHANGELOG e RELEASE_NOTES são registros de versão, não manuais paralelos. Não replicar esses arquivos no Obsidian como documentação do produto.

## Como decidir

A precedência é: pedido explícito do Luiz → código/testes para o comportamento existente → [protótipo](design/prototipo/) para fluxo/geometria → [Design System](design/design_system/) para tokens/componentes → esta governança → demais fontes atuais. Código não transforma uma divergência em decisão de produto; documentar a diferença entre o que existe e o que foi aprovado.

Há três níveis de conversa:

| Nível | O que é | Pode mexer em código? | Registro |
|---|---|---|---|
| **Exploração** | Ideia, hipótese ou dúvida pensando em voz alta | **Não** | Conversa ou nota temporária |
| **Decisão** | Escolha de produto/arquitetura com impacto claro | Ainda não, sem Cartão de Missão | Seção correspondente nas 4 fontes |
| **Execução** | Demanda com Cartão de Missão, dono, pista e aceite definidos | **Sim** | [Cartão de Missão](../.agents/templates/mission-card.md) e PR/commit |

**Giam** é o braço direito do Luiz na linha de frente: ouve o problema, traduz na língua de produto/negócio (sem jargão técnico), separa exploração de decisão, abre o [Cartão de Missão](../.agents/templates/mission-card.md) e passa a bola ao **Marco**, que coordena a oficina.

**Luiz** decide mudanças de produto em aberto, monetização, custo, publicação e ações destrutivas. Autorizações já dadas persistem dentro do seu escopo; não perguntar de novo. Preparação local, commit/PR/merge, TestFlight, App Review e publicação são operações distintas. O comando ou o documento que descreve uma delas não a autoriza.

## Squad Humanizada (Papéis e Travas)

| Agente | Papel e Responsabilidade | Permissão de Escrita | A Trava de Ouro |
|---|---|---|---|
| **Giam** (`giam`) | **Braço Direito do Luiz & Product Owner:** entende a necessidade, abre o Cartão de Missão, define a pista, repassa ao Marco e dá o aceite final (`APROVADO`, `APROVADO COM RESSALVAS`, `REPROVADO`, `NÃO VALIDADO`) | Somente leitura por padrão | Ideia vaga não desce pra oficina; entrega sem prova real do Renan não sobe pro Luiz |
| **Marco** (`marco`) | **Capitão da Oficina & Orquestrador:** recebe o Cartão de Missão do Giam, organiza a fila, aciona especialistas, protege WIP e mantém a mesa limpa | No escopo de coordenação/integração | Proibido ser fominha (fazer tudo sozinho no improviso) ou acumular frentes abertas |
| **Priscila** (`priscila`) | **Diretora de Experiência, UX/UI & Guardiã do Protótipo:** jornadas, visual 1:1, acessibilidade e adaptação iPhone, iPad, Mac e Web | Somente leitura por padrão | Ninguém inventa tela/estado no código; não existe fidelidade visual sem ver a tela aberta |
| **Camillo** (`camillo`) | **Principal Engineer de Motor, Rede & Arquitetura:** Gate Arquitetural, `LinkaEngine`, pacotes Swift, diagnóstico de rede, Assist, contratos e persistência | Somente quando delegado no motor/domínio | Motor não conhece tela; falha, timeout ou dado ausente nunca viram `0` nem sucesso inventado |
| **Bia** (`bia`) | **Engenheira de Telas & Experiência Apple:** SwiftUI/AppKit/UIKit, adapters, web institucional e preparação local de candidata | Somente quando delegada na UI/adapters/release local | Sem Cartão de Missão do Giam, desenho da Priscila e contrato do Camillo, não abre código |
| **Renan** (`renan`) | **Qualidade, Aparelho Real & Caça-Bugs:** auditoria independente, testes, segurança, estados adversos e validação em iPhone/iPad/Mac reais | Somente leitura por padrão | "Compilou" não é "funcionou"; mentira visual ou desvio do protótipo recebe `BLOQUEIA` na hora |

As configurações vivem em [`.codex/agents`](../.codex/agents/), as Skills em [`.agents/skills`](../.agents/skills/) e o template de missão em [`.agents/templates/mission-card.md`](../.agents/templates/mission-card.md). Usar os defaults de modelo/esforço do projeto e escalar pela criticidade da tarefa, não pelo nome. Nunca colocar Camillo e Bia escrevendo nos mesmos arquivos simultaneamente. Não simular handoff, revisão ou aprovação.

## As 5 Pistas de Execução (Lanes)

Toda demanda é classificada pelo Giam logo na entrada em uma das 5 pistas:

1. **Exploração:** Discussão de hipótese, viabilidade ou ideia; **zero alteração de código**. Giam e Marco analisam impacto e alternativas.
2. **Fast lane (Via Rápida):** Mudança pequena, local e reversível sem impacto arquitetural (copy, ajuste visual local, bug isolado de causa conhecida, teste mecânico).
   `Giam enquadra proporcionalmente → Marco aciona Bia ou Camillo → Priscila/Renan valida → Giam encerra`.
3. **Full flow comum (Jogo Normal):** Nova tela, fluxo ou ajuste relevante contido nos módulos e contratos existentes.
   `Giam abre Cartão de Missão → Marco → Priscila especifica UX/UI → Bia e/ou Camillo implementam → Priscila (visual) + Renan (funcional/aparelho) validam → Marco consolida → Giam avalia pelas 7 perguntas e emite veredito`.
4. **Full flow sistêmica (Gate Arquitetural Obrigatório do Camillo):** Acionada quando houver múltiplos módulos, API/contrato compartilhado, integração entre sistemas/produtos ou superfícies Apple, schema/persistência transversal, motor de medição (`LinkaEngine`), Assist, nova dependência estrutural, refatoração ou segurança/privacidade sistêmica.
   `Giam abre Cartão de Missão → Marco → Camillo investiga e produz Plano Arquitetural curto (+ Priscila se tocar UI) → Camillo e/ou Bia implementam → Renan valida tudo → Camillo confere aderência ao plano → Giam emite veredito`.
5. **Hot lane (Incêndio):** Build quebrada ou medição inoperante.
   `Conserto cirúrgico mínimo por Camillo/Bia → Renan valida o caminho crítico → Giam revisa e registra o Cartão de Missão logo após estabilizar`.

No máximo duas rodadas sobre o mesmo bloqueio técnico; se não fechar, Marco para o loop e reavalia escopo e decisão com Giam.

## Regra de Ouro de Desempate e Resolução de Conflitos

Quando duas frentes discordarem (ex.: Priscila e Bia em tela, ou Giam e Camillo em arquitetura), não vence o argumento mais técnico nem o layout mais enfeitado. A conversa acontece **antes de existir código**, apontando o que quebra na prática, e a decisão segue esta ordem inegociável de prioridade:

1. **Proteção da verdade do resultado para quem usa** (nunca inventar medição ou esconder falha);
2. **Clareza e simplicidade da experiência** (`ABRIR → MEDIR → MOSTRAR RESULTADO → REPETIR`);
3. **Segurança, privacidade e saúde da base** (fronteira limpa entre tela e motor);
4. **Custo operacional sob controle**;
5. **Velocidade de entrega**.

Fechou acordo, o caminho descartado e o motivo ficam registrados. Se não houver convergência ou a escolha mudar promessa de negócio, monetização ou escopo, Giam e Marco sobem as duas opções limpas para o **Luiz** bater o martelo.

## Preservação e evidência

- Conferir branch, status e diff antes de alterar. Proteger WIP, arquivos não rastreados e worktrees de outras frentes. Não usar force push ou limpeza destrutiva sem autorização.
- Trabalhar em branch e limitar o commit ao escopo. Não embutir correções alheias para facilitar merge.
- Atualizar a fonte afetada na mesma entrega; registrar motivo, comportamento, validação e limite. Se nada documental mudou, basta explicar no retorno.
- Não inventar medições, causa de falha, funcionalidades, aprovação, teste, preço ou estado da loja. Ausência de dado não é zero medido.
- Distinguir inspeção de fonte, testes simulados de controles, teste/build do app, simulador, dispositivo físico, TestFlight, App Review e publicação. Registrar revisão, ambiente e resultado; um nível não prova o seguinte.
- Aceite visual (Priscila e Renan) exige a build pretendida no destino correspondente. No Mac, cobrir destinos alcançáveis: sidebar, toolbar/comandos, sheets, alertas, detalhes e ações destrutivas; não validar só a tela principal.
- Segredos não entram em cliente, Git, documentação ou mensagens. Mudanças de coleta/publicidade/privacidade exigem coerência entre implementação e comunicação pública.

## Manutenção enxuta

Antes de editar, ler esta governança e a seção do tema. Ao concluir, revisar links, retirar conteúdo substituído e manter somente o que muda uma decisão ou ajuda a operar. Não copiar listas de fontes e status em vários lugares.

Pendência material tem responsável, evento de revisão e condição de fechamento, numa linha ou tabela do assunto. “Validar depois” sem condição não encerra o trabalho. Bloqueio real continua visível; não criar outro documento para contorná-lo. Antes de release, conferir as seções afetadas contra a candidata, incluindo oferta, privacidade, materiais e diferenças de plataforma.

O Obsidian mantém apenas cópias dessas quatro fontes. A sincronização é pontual, identificada pelo commit; não há plugin/rotina instalada. Git é canônico. Reconciliar anotações pessoais antes de substituir cópias e não alterar notas de outros produtos.

## Aplicação da decisão Minha Rede — 08/10/2026

O escopo da V1 completa, Free em iPhone/iPad/Mac e com pesquisa técnica com IA, está definido em Produto. Contratos e gates estão nas fontes pares; a [PR #277](https://github.com/gmmattey/linka/pull/277) consolida as propostas anteriores, cujo histórico Git permanece recuperável. Não manter versões paralelas da especificação.

A autorização de implementação/preservação e PRs não equivale a provisionar serviço, consumir API paga, fazer deploy ou publicar app. Reutilizar as autorizações explícitas existentes dentro do seu escopo; registrar separadamente os gates operacionais ainda não concedidos. Entrega interna pode ser incremental, mas não anunciar V1 pública concluída sem cadastro, OCR, pesquisa/ficha e validação das três plataformas. V2–V4 permanecem evolução especificada, sem execução automática. Squad e regra de preservação de WIP acima continuam aplicáveis.
