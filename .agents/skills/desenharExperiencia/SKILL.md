---
name: desenhar-experiencia
description: Desenha fluxo e estados do Linka antes de pixels e código, sem inflar o produto.
---

# Skill: desenhar-experiencia

Use esta skill para definir **o que acontece**: fluxo, estados, ações, falhas e saída.

Fontes, em ordem: visão atual do produto, `AGENTS.md`, escopo Free/Plus, protótipo e Design System.

## Filtro inicial

Pergunta de `documentacao/PRODUTO.md`:

> **Isso melhora medir, entender ou acompanhar a conexão no Apple sem competir com o resultado?**

Se não, não desenhe infraestrutura para a ideia nesta tarefa.

## Fluxo principal

```text
ABRIR → MEDIR → MOSTRAR RESULTADO → REPETIR
```

Uma feature pode criar superfícies secundárias, mas não deve complicar o caminho principal sem benefício claro.

## Para cada mudança, responda

1. qual estado muda;
2. o que o usuário vê ao entrar;
3. qual ação existe, se houver;
4. qual é a saída;
5. o que acontece em erro/offline/timeout/permissão/partial;
6. se adiciona toque ou fricção antes do resultado;
7. como funciona com Reduce Motion;
8. o que a mudança **não deve virar**.

## Regras

- estado não fica preso;
- erro conta a verdade;
- ausência de dado não vira zero;
- resultado medido vem antes da interpretação;
- histórico/Assist/detalhes usam divulgação progressiva;
- não crie tela nova quando expansão ou superfície existente resolve melhor;
- não crie onboarding/login/seleção de modo como fricção do fluxo principal sem decisão explícita de produto.

## Saída

```text
ESTADO: onde muda
ANTES: o que o usuário encontra
AÇÃO: o que faz
DEPOIS: saída/estado seguinte
DEU RUIM: falhas e recuperação
REDUCED MOTION: comportamento
NÃO VIRA: limites do escopo
ACEITE: comportamento observável
```

O Codex principal combina esse resultado com a arquitetura quando o gate aplicável for acionado. A forma visual detalhada pode usar `desenhar-interface`.
