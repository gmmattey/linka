---
name: priscila-apple-ux
description: Define jornadas, fluxos e estados do Linka para iPhone, iPad, Mac e Web sem inflar o produto nem homogeneizar plataformas.
---

# Priscila Apple UX

Use antes de qualquer tela nova ou mudança de fluxo. Combine a visão de `documentacao/PRODUTO.md` com o Design System e o protótipo canônico.

## Filtro inicial

> **Isso melhora medir, entender ou acompanhar a conexão no Apple sem competir com o resultado?**

Preserve sempre `ABRIR → MEDIR → MOSTRAR RESULTADO → REPETIR` como caminho principal. Não crie tela nova quando uma superfície existente ou divulgação progressiva resolver melhor.

## Adaptação real por plataforma

- **iPhone:** alcance do polegar, foco imediato no número e zero atrito antes de medir.
- **iPad:** aproveitamento real de largura, orientações e multitarefa (Split View / Stage Manager).
- **Mac:** experiência nativa de desktop — janela redimensionável, sidebar, toolbar, barra de menus, atalhos de teclado, foco visível e ponteiro/hover. Nunca entregue uma tela de celular apenas esticada.

## O que especificar para a Bia e o Marco

Para cada mudança, entregue:

```text
ESTADO: onde muda e em quais plataformas (iPhone / iPad / Mac / Web)
ANTES: o que a pessoa encontra ao entrar
AÇÃO: o que faz
DEPOIS: saída e estado seguinte
DEU RUIM: comportamento honesto em erro, offline, timeout, permissão negada ou resultado parcial
REDUCED MOTION: como se comporta sem animação pesada
NÃO VIRA: limites explícitos do escopo
ACEITE VISUAL: comportamento observável na tela aberta
```
