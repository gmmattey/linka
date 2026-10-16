---
name: bia-swiftui-and-adapters
description: Construção de telas SwiftUI/Web e adaptadores nativos do Linka pela Bia, 1:1 com o protótipo da Priscila e integrados ao motor do Camillo.
---

# Bia SwiftUI & Adapters

Use para implementar interfaces e adaptadores depois que o escopo do **Giam**, o desenho da **Priscila** e (quando aplicável) o contrato do **Camillo** estiverem fechados.

## Regra central

> **A tela não implementa o motor. O motor não conhece a tela. O adaptador traduz estado, ciclo de vida e intenção entre os dois.**

## Antes de criar ou alterar

1. Confira o estado correspondente no protótipo e no Design System (`priscila-apple-visual`).
2. Procure componente e token semântico já existentes antes de criar peça nova.
3. Verifique se o pacote do **Camillo** (`NetworkCore`, `LinkaEngine`, `MeasurementHistory`, `NetworkInsights`, `NetworkAssist`) já entrega o dado necessário. Se faltar contrato, pare e peça ao **Marco** para acionar o Camillo.

## Durante a implementação

- **Protagonismo do resultado:** O número medido vem primeiro; interpretação vive em superfície secundária.
- **Estados honestos:** Carregando, parcial, erro, offline e cancelado mantêm seu significado real — nunca esconda falha atrás de `0` ou estado vazio genérico.
- **Ciclo de vida limpo:** Toda `Task`, timer ou monitor iniciado pelo adapter tem dono e é cancelado ao fechar a tela, trocar estado ou ir para background.
- **Acabamento nativo:** Suporte completo a Light/Dark Mode, Dynamic Type, contraste, VoiceOver, foco por teclado (especialmente no Mac) e Reduce Motion.
- **Copy afiada:** Aplique `aplicar-voz-linka` e `matar-cheiro-de-ia`. Rótulo de controle é contrato e não varia no improviso.
