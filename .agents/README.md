# Agentes e skills do Linka

Estado: vigente.
Responsável: Codex principal.
Última revisão: 2026-10-04 — entradas documentais e estrutura de planejamento.
Referência: [governança documental](../documentacao/GOVERNANCA_DOCUMENTAL.md).

A governança do Linka está em [`AGENTS.md`](../AGENTS.md). O runtime principal é o **Codex**.

Esta pasta `.agents/` continua existindo para **skills, workflow, scripts e artefatos de planejamento**. Os agentes executáveis do Codex não vivem mais aqui: eles são agentes nativos versionados em `.codex/agents/`.

## Estrutura atual

```text
.codex/
├── config.toml
└── agents/
    ├── iris.toml
    ├── camillo.toml
    ├── pedro.toml
    └── tito.toml

.agents/
├── README.md
├── WORKFLOW.md
├── plano.md
├── scripts/
├── skills/
└── plano-<tema>.md  # quando uma iniciativa exigir plano separado
```

Não use perfis JSON em `.agents/plugins/` para simular agentes. A migração de 2026-09-06 aposentou essa camada.

## Squad nativa do Codex

O **Codex principal** é o orquestrador e interlocutor com o Luiz. Ele decide quando delegar, integra os retornos e continua responsável pela entrega final.

- **Íris** — Produto, jornada, UX/UI, copy, curadoria, priorização e critérios de aceite. Somente leitura.
- **Camillo** — Principal Engineer transversal: arquitetura, contratos, motor, pacotes Swift, integrações Apple entre superfícies e revisão sistêmica. Escrita quando o gate arquitetural ou uma delegação explícita justificar; não é implementador obrigatório da rotina.
- **Pedro** — Desenvolvedor: implementa código após o plano de engenharia aplicável, com testes e validação proporcional. Resolve lacunas recuperáveis pela menor decisão compatível com a arquitetura; não reabre o plano durante a execução.
- **Tito** — Qualidade, regressão, testes, acessibilidade, segurança/privacidade e revisão independente. Somente leitura por padrão; responde com `BLOQUEIA`, `AJUSTA` ou `ISSUE_FUTURA`.

Especialistas não precisam aparecer em toda tarefa. Se o trabalho for pequeno, coeso e puder ser resolvido com segurança pelo agente principal, não crie handoff artificial.

Camillo é acionado obrigatoriamente pelo gate arquitetural do `AGENTS.md`: contratos, múltiplos módulos, APIs, integrações, persistência compartilhada, `LinkaEngine`, dependência estrutural, refatoração, segurança/privacidade sistêmica ou grande raio de impacto. Depois do plano, Pedro é o executor preferencial; fora do gate, o Codex principal implementa ou delega pelo ganho real.

## Skills

Skills são **procedimentos**, não agentes e não fontes de verdade. A descoberta ocorre pelo `SKILL.md` e pelo `name` do frontmatter.

### Produto

- `pensar-como-medicao` — curadoria do escopo do Linka.
- `desenhar-experiencia` — fluxo e estados.
- `desenhar-interface` — especificação visual a partir do protótipo e Design System.
- `aplicar-voz-linka` — voz/copy do produto.
- `matar-cheiro-de-ia` — filtro de linguagem e formatação artificial.

### Engenharia

- `arquitetar-modulo` — arquitetura da mudança e fronteira Engine/UI.
- `aconselhar-arquitetura` — decisões difíceis do motor e contratos.
- `criar-componente-ui` — SwiftUI/React institucional conforme o Design System.
- `escrever-adaptador-nativo` — adapter entre capacidades Apple, pacotes e UI.
- `escrever-testes` — testes junto com implementação.
- `garantir-iphone-real` — validação em dispositivo real.
- `rodar-no-iphone` — build, assinatura e instalação local.

### Qualidade

- `validar-modularidade` — acoplamento, duplicação e fronteiras.
- `auditar-seguranca-e-testes` — pipeline, rede real, privacidade e comportamento.

### Compartilhadas / agente principal

- `conversar-com-o-luiz` — como o Codex principal comunica decisões e limitações ao Luiz.
- `registrar-issue` — issue, PR e commit na voz de trabalho do Linka.
- `delegar-subagente` — contrato para delegação aos agentes nativos do Codex.

Uma skill pode ser usada por outro papel quando fizer sentido. A lista indica responsabilidade principal, não propriedade exclusiva.

## Como delegar

O Codex usa os agentes definidos em `.codex/agents/`. Não precisa reconstruir seus prompts a cada chamada nem carregar perfis JSON legados.

A delegação deve conter:

```text
Especialista: <iris|camillo|pedro|tito>
Objetivo: <entrega concreta>
Escopo de leitura: <arquivos/módulos>
Escopo de escrita: <somente leitura ou limites explícitos>
Restrições: preserve mudanças existentes; sem merge/deploy/publicação/segredos.
Retorno: evidências, arquivos alterados, comandos/testes, riscos e bloqueios.
```

Para detalhes, use [`skills/delegar-subagente/SKILL.md`](skills/delegar-subagente/SKILL.md).

## Fontes canônicas

Ordem de precedência definida em [`AGENTS.md`](../AGENTS.md) §3:

1. pedido explícito do Luiz na sessão atual;
2. código e testes;
3. protótipo canônico;
4. Design System;
5. `AGENTS.md`;
6. `.agents/WORKFLOW.md`;
7. demais documentação atual compatível.

## O que não deve voltar

- agentes simulados por prompt JSON;
- política de modelo específica do Claude (`Haiku / Sonnet / Opus`);
- personagens como camada de teatro entre o Luiz e a execução;
- papel novo só porque uma skill existe;
- especialista permanente para tarefa que aparece uma vez;
- agente que aprova a própria entrega.

Novo especialista só entra quando houver responsabilidade recorrente que esteja prejudicando qualidade ou paralelismo da squad atual.

## Histórico da migração

Em **2026-09-06**, o Linka migrou sua squad ativa para o runtime nativo do Codex:

```text
Giammattey  → Íris       Produto
Tiago       → Camillo    Engenharia / Arquitetura
Igor        → Tito       Qualidade
```

As responsabilidades foram reorganizadas, não apenas renomeadas: arquitetura voltou a ficar explicitamente com **Camillo**, produto ficou com **Íris**, e **Tito** permanece independente da implementação.

Os antigos perfis JSON em `.agents/plugins/squad-linka/` foram aposentados em favor de `.codex/agents/*.toml`. As skills foram preservadas porque continuam úteis como runbooks independentes do runtime.

Os planos anteriores foram consolidados na documentação por capacidade e no ledger de `plano.md`. A migração autorizada remove os arquivos `.old/` do checkout; histórico rastreado permanece no Git. Changelogs e notas de candidata são artefatos de versão, não manuais de comportamento atual.
