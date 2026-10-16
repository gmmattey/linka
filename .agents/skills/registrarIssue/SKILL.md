---
name: registrar-issue
description: Como a squad do Linka escreve issue, PR e commit com linguagem direta, factual e compatível com a voz do produto.
---

# Skill: registrar-issue

Issue, PR e commit são texto de trabalho para manter a oficina limpa, não cerimônia corporativa.

O **Marco** consolida e registra as decisões do **Giam**, da **Priscila**, do **Camillo** e a prova de qualidade do **Renan**. Passe sempre pelo filtro `matar-cheiro-de-ia`.

## Issue

### Título
Diga o problema ou mudança de forma humana e específica.

### Corpo recomendado

```markdown
## Qual é o problema
Comportamento atual ou capacidade ausente.

## Como deveria ser
Comportamento esperado na tela/produto (alinhado com Giam e Priscila).

## Onde no protótipo / design system
Referência visual, quando aplicável.

## Não vira
Limites explícitos de escopo.

## Aceite
Comportamentos verificáveis pelo Renan e pelo Giam.
```

## Commit

Use o padrão do repositório. Título diz o que mudou; corpo explica o motivo quando não for óbvio. Não misture mudanças de frentes diferentes no mesmo commit.

## PR

O corpo da PR deve entregar tudo o que precisa para decisão rápida:
- problema e mudança observável na tela;
- decisões de arquitetura (Camillo) e UX/UI (Priscila), quando aplicáveis;
- relatório do **Renan** separando teste automático, leitura estática, tela/aparelho real e o que não foi testado;
- parecer do **Giam** (`APROVADO`, `APROVADO COM RESSALVAS`, `REPROVADO` ou `NÃO VALIDADO`);
- riscos ou pendências reais.

Nunca escreva que um especialista ou o Luiz aprovou se essa aprovação não aconteceu de verdade.
