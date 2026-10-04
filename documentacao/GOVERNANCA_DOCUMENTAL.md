# Governança documental do Linka

Estado: vigente desde 2026-10-04.
Decisão: Luiz solicitou a nova governança e, em seguida, a geração do acervo atualizado com exclusão dos documentos anteriores; execução registrada em MIGRACAO.md.
Responsável: Codex principal (Marco), orquestrador do Linka.
Autoridade: [AGENTS.md](../AGENTS.md), especialmente §3 e §14.
Última revisão: 2026-10-04 — processo, estrutura por feature e política de substituição do acervo; limitações de evidência registradas por tema.

## Resultado esperado

Qualquer pessoa ou agente deve conseguir identificar o comportamento esperado, a decisão que o sustenta, o que foi implementado e o que foi validado. A documentação acompanha a entrega e não depende da memória de uma conversa.

Este processo vale para todo o repositório: documentação, planos, README de módulos, contratos, design, site e materiais de loja. Caminhos literais abaixo são relativos à raiz Git (`ios/` neste workspace); links Markdown são relativos ao arquivo que os contém. Cópias fora dessa raiz não se tornam fontes oficiais automaticamente.

## Autoridade e fontes por assunto

A precedência é a do AGENTS.md §3. Este documento detalha o processo, sem criar outra autoridade. Código e testes demonstram o que existe; uma decisão aprovada descreve o que se deseja. Divergência entre ambos deve ser registrada, nunca escondida promovendo intenção a comportamento entregue.

| Assunto | Fonte que deve ser mantida | Responsabilidade de conteúdo |
|---|---|---|
| Governança e limites de atuação | [AGENTS.md](../AGENTS.md) | Orquestrador |
| Etapas de execução | [WORKFLOW.md](../.agents/WORKFLOW.md) | Orquestrador |
| Descoberta dos documentos | [Entrada documental](README.md) e [índice de features](features/INDICE.md) | Orquestrador |
| Visão e comportamento de produto | [Produto](PRODUTO.md) e README de cada feature | Orquestrador, com Íris quando houver decisão de produto |
| História do produto | [Contexto do produto](PRODUTO.md) | Orquestrador; preservar o contexto da época |
| Fluxo e geometria; tokens e componentes | `documentacao/design/prototipo/`; `documentacao/design/design_system/` | Íris orienta; executor autorizado mantém |
| Arquitetura e contratos duráveis | `documentacao/arquitetura/`, `documentacao/arquitetura/contratos/`, README do módulo | Executor; Camillo conforme gate arquitetural |
| Plano de execução | `.agents/plano.md` e planos específicos referenciados nele | Orquestrador |
| Evidência e pendências de uma entrega | Issue/PR, relatório ou plano identificado | Executor registra; Tito revisa quando acionado |
| Operação e publicação | [Operação](operacao/README.md), `store/app-store/`, `RELEASE_NOTES.md` | Executor registra; orquestrador confere |

Uma regra tem um local de manutenção. Outros documentos apontam para ela, sem copiar parágrafos normativos. Um novo documento durável entra no índice; documentação local de módulo pode ser descoberta pelo README do módulo. Relatórios e planos temporários precisam ser ligados à iniciativa, sem lotar o índice geral.

## Documentação por feature

Para documentar uma capacidade do produto, usar os [templates por feature](templates/README.md). Começar com `documentacao/features/<feature>/README.md`, reunindo propósito, comportamento atual, mapa técnico, validação e links para mudanças em andamento. Separar funcional, técnico e validação apenas quando melhorar a leitura, mantendo links no README e uma fonte para cada conteúdo.

A descoberta das features usa o [índice de features](features/INDICE.md), ligado à [entrada documental](README.md). Arquitetura, contratos e design compartilhados permanecem nas fontes existentes; o documento da feature aponta para elas. Templates não atestam implementação; cada README identifica as fontes e o alcance real da revisão.

## Quem responde pela manutenção

- **Orquestrador:** identifica impacto documental, escolhe a fonte, resolve duplicidades, confere a entrega e mantém pendências visíveis. É o responsável final pelo processo.
- **Autor da mudança:** atualiza a documentação afetada na mesma entrega e apresenta evidência ou limitações.
- **Íris:** participa quando mudar intenção, jornada, copy ou critérios de aceite. Sua atuação continua somente leitura por padrão.
- **Camillo:** participa nos gatilhos arquiteturais existentes; documentação isolada não cria um gate novo.
- **Tito:** revisa coerência e evidência quando acionado pelo risco. Não se registra revisão dele sem execução real.
- **Luiz:** decide produto e os gates humanos existentes. Correção factual, links e organização reversível não exigem nova aprovação.

O responsável de conteúdo não é uma aprovação automática nem uma obrigação de convocar toda a squad.

## Fluxo obrigatório por entrega

1. **Antes de editar:** ler AGENTS.md, consultar o índice e as fontes do tema; verificar branch/diff e preservar WIP. Distinguir exploração, decisão e execução. Apontar quais documentos serão afetados; em tarefa pequena isso cabe no retorno da entrega.
2. **Durante o trabalho:** atualizar a fonte existente. Separar comportamento atual de proposta. Registrar decisão material, motivo, escopo e referência da autorização quando necessária. Não criar outro plano para contornar um conflito.
3. **Antes de concluir:** conferir documentação contra o diff, verificar caminhos/links locais e comandos descritos, revisar contradições e atualizar o estado e a evidência. Se um comando não foi executado, não marcar como validado.
4. **No PR ou retorno final:** informar documentos alterados, validação feita e pendências. Se não houver impacto documental, registrar uma frase com o motivo. Sem PR, o retorno final cumpre esse papel; não criar relatório extra por obrigação.
5. **Na integração:** só declarar a entrega concluída quando a documentação necessária estiver coerente. Pendência não bloqueante recebe responsável, critério de fechamento e prazo ou evento de revisão explícito.

### Gatilhos de atualização

| Mudança | O que revisar |
|---|---|
| Jornada, capacidade, limite de plataforma, copy ou monetização | Visão, documento do recurso, design e comunicação pública afetada |
| Motor, metodologia, contrato, schema ou persistência | Arquitetura, contrato/fixtures, README dos consumidores e afirmações em “Como medimos” |
| Comando, dependência, configuração, CI ou release | README e procedimento operacional correspondente |
| Privacidade, permissões, coleta ou compartilhamento | Descrição técnica, política pública e material de loja afetado |
| Resultado de teste, build ou publicação | Evidência da entrega com ambiente, versão e limite da conclusão |
| Caminho movido, documento substituído ou regra alterada | Links de entrada, índice e referências que apontam para a fonte antiga |

Hotfix pode adiar contexto complementar, mas não manter instrução operacional perigosa ou afirmação pública falsa. O que ficar para depois precisa de registro rastreável, responsável e prazo/evento de revisão; não basta escrever “atualizar docs depois”.

## Estado e identificação dos documentos

Novos documentos duráveis e documentos substantivamente revisados devem trazer, no topo:

```text
Estado: rascunho | vigente | substituído | histórico
Responsável: papel da squad ou pessoa responsável
Última revisão: AAAA-MM-DD — escopo efetivamente conferido
Referências: decisão, issue/PR, código/contrato ou evidência aplicável
Substitui / substituído por: link, quando aplicável
```

- **Rascunho:** hipótese ou proposta; não autoriza implementação.
- **Vigente:** referência aplicável ao escopo declarado; não significa que tudo nela foi entregue ou validado em produção.
- **Substituído:** outra fonte assumiu o assunto; indicar qual.
- **Histórico:** registro da época, sem autoridade sobre o comportamento atual.

Correção de typo/link não exige preencher metadados de todo um documento legado. Não mudar a data de revisão de conteúdo que não foi conferido. Arquivos gerados, schemas e assets mantêm seu formato; escopo e estado ficam no README que os apresenta.

Para planos, registrar separadamente o andamento: proposto, decidido, em execução, implementado com validação pendente, concluído ou cancelado. “Concluído” exige critérios de aceite verificados; decisão aprovada sozinha não prova implementação.

## Planos, decisões e trabalho simultâneo

- `.agents/plano.md` continua sendo o ponto de entrada dos planos materiais. Para novas iniciativas paralelas, usar `.agents/plano-<tema>.md` e referenciá-las no plano principal com escopo, estado e responsável.
- Não acumular novas iniciativas como seções soltas sob o título de outra. Não sobrescrever plano ou WIP de outra frente.
- Tarefa fast-lane continua sem plano obrigatório.
- Ao fechar uma iniciativa, transferir somente conhecimento durável para o documento do tema. O plano conserva decisões e evidências históricas, sem virar manual de uso.
- Decisão pequena cabe no documento existente ou na issue/PR. Decisão arquitetural durável pode usar `documentacao/arquitetura/decisoes/AAAA-MM-DD-<tema>.md`, criada quando necessária, com problema, decisão, alternativas relevantes, consequências e fontes.
- Conflito material deve listar as fontes e a diferença. O orquestrador aplica AGENTS.md §3; consulta especialista pelo assunto e Luiz apenas para decisão de produto/gate real. Não executar a parte dependente de uma decisão ainda aberta.

## Evidência e honestidade

Uma afirmação de validação informa data, referência da versão/commit ou estado do checkout, ambiente, procedimento, resultado e limitações. Evidência pode estar no PR; não precisa ser copiada para todos os documentos.

Manter separados: inspeção estática, teste local, build, simulador, dispositivo físico, TestFlight, App Review e publicação/produção. Um nível não prova o seguinte. WIP testado deve ser identificado como WIP. Revisão visual requer a build pretendida no destino correspondente.

Não documentar segredos, tokens, dados pessoais ou capturas sensíveis. Usar placeholders e referências ao mecanismo de configuração. Não fabricar números, aprovações, execução de comandos ou estado de loja.

## Revisão recorrente e bloqueios

- **A cada entrega:** autor e orquestrador revisam os documentos impactados.
- **Antes de release relevante:** orquestrador confere a revisão já exigida pelo WORKFLOW, incluindo Produto, Linka Plus, arquitetura, planos ativos e materiais públicos afetados; compara com a versão candidata real.
- **Mensalmente, na primeira tarefa de manutenção documental do mês:** orquestrador faz triagem do índice, planos abertos, links e pendências vencidas. Registra data, alcance e próxima ação no próprio índice ou issue. É uma rotina a executar, não uma automação já instalada.

Bloqueiam a conclusão da parte afetada: fonte contraditória sobre comportamento material, instrução essencial quebrada, contrato incompatível, segredo exposto, aprovação inexistente ou afirmação de validação/publicação sem evidência. Lacuna editorial sem impacto operacional pode seguir como pendência rastreada. A revisão documental não substitui testes nem autoriza merge/release.

## Substituição e manutenção do acervo

Por decisão expressa do Luiz em 2026-10-04, a migração mantém somente a documentação atualizada no checkout. Documentos anteriores substituídos são excluídos, sem cópia em `.old/`. O [registro de migração](MIGRACAO.md) identifica a cobertura, substituições e limites; o histórico dos arquivos rastreados permanece no Git, sem reescrita.

Antes de excluir uma fonte, consolidar contratos, decisões relevantes e pendências no destino correspondente. Não apagar código, assets atuais, schemas, fixtures ou WIP de implementação como efeito da reorganização documental. Fontes não rastreadas exigem transferência do conteúdo relevante antes da exclusão. Conferir os links de entrada e referências de consumidores na mesma entrega.

Novas mudanças mantêm a fonte do tema atualizada; não criam outro documento concorrente. Planos de execução não são prova de implementação. A fonte vigente registra divergências e validação pendente, em vez de transformar intenção antiga em fato.

## Checklist de encerramento

- [ ] Fonte correta atualizada, ou ausência de impacto documental justificada.
- [ ] Proposta, comportamento implementado e validação estão distintos.
- [ ] Links/caminhos alterados conferidos e índice atualizado quando necessário.
- [ ] Estado, responsável e revisão refletem apenas o que foi de fato conferido.
- [ ] Sem duplicação normativa, aprovação fictícia ou dados sensíveis.
- [ ] Pendências têm responsável e prazo/evento de revisão.

O checklist cabe no PR ou retorno da tarefa. Não exige arquivo adicional.
