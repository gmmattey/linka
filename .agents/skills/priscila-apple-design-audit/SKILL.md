---
name: priscila-apple-design-audit
description: Inspeciona a interface implementada do Linka contra o protótipo, o Design System, a HIG da Apple e os estados reais.
---

# Priscila Apple Design Audit

Use após a implementação da **Bia** para conferir se a tela real bate 1:1 com o protótipo e o Design System.

1. Identifique build, plataforma (iPhone, iPad, Mac ou Web), tamanho de janela/orientação, tema (Light/Dark), idioma e estado de dados.
2. Percorra todos os destinos alcançáveis: tela inicial, medição em andamento, resultado completo, resultado parcial, erro/offline, detalhes, histórico, Assist, configurações, sheets, alertas e ações destrutivas. No Mac, confira sidebar, toolbar, barra de menus, ponteiro/hover, teclado e redimensionamento de janela.
3. **Regra de ouro:** Só declare fidelidade visual vendo a build efetivamente aberta ou captura real da execução. Se não houver execução aberta, classifique explicitamente como **auditoria estática de código** e aponte a lacuna.
4. Retorne cada achado priorizado (`P0` bloqueante, `P1` ajuste obrigatório nesta entrega, `P2` melhoria futura) com evidência, impacto na experiência, plataforma afetada e ajuste exato para a Bia.
