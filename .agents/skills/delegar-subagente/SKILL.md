---
name: delegar-subagente
description: Delegar uma tarefa independente aos agentes nativos Íris, Camillo ou Tito do Codex com objetivo, escopo, permissões e retorno verificáveis.
---

# Skill: delegar-subagente

Use esta skill quando uma parte do trabalho for concreta, independente e suficientemente delimitada para ganhar com especialização ou paralelismo.

Os agentes são definidos nativamente em `.codex/agents/`:

- **Íris (`iris`)** — produto, experiência, curadoria, UX/UI, copy e critérios de aceite. Somente leitura.
- **Camillo (`camillo`)** — engenharia, arquitetura, implementação, motor e integrações Apple. Escrita apenas quando autorizada.
- **Pedro (`pedro`)** — desenvolvimento e implementação após o plano de engenharia aplicável. Escrita apenas quando autorizada; executa a arquitetura decidida e não a reabre durante o trabalho.
- **Tito (`tito`)** — qualidade, auditoria, regressão, testes, acessibilidade e segurança. Somente leitura por padrão.

## Antes de delegar

Defina:

1. objetivo concreto;
2. contexto mínimo necessário;
3. arquivos/módulos que podem ser lidos;
4. escopo de escrita, se houver;
5. restrições;
6. formato de retorno esperado.

Não delegue tarefa vaga, decisão acoplada ao próximo passo crítico ou duas tarefas que escrevam nos mesmos arquivos.

## Mensagem mínima

```text
Especialista: <iris|camillo|pedro|tito>
Objetivo: <entrega concreta>
Escopo de leitura: <arquivos ou módulos>
Escopo de escrita: <somente leitura ou arquivos/módulos autorizados>
Restrições: preserve mudanças existentes; sem merge, deploy, publicação, segredo ou exclusão destrutiva.
Retorno: evidências, arquivos alterados quando houver, comandos/testes, riscos e bloqueios.
```

Para Tito, exigir verdict `BLOQUEIA`, `AJUSTA` ou `ISSUE_FUTURA` com evidência reproduzível.

Para Camillo, o agente principal revisa o diff antes de integrar.

Íris aconselha produto; não representa decisão do Luiz.

## Depois de delegar

O Codex principal integra o retorno, resolve divergências e valida o que for material. Não repita todo o trabalho do subagente, mas também não trate o retorno como verdade automática.

Modelo e esforço seguem `.codex/config.toml` e `documentacao/GOVERNANCA.md`. Escale pela criticidade da tarefa, não pelo nome do especialista.
