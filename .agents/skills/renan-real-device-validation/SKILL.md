---
name: renan-real-device-validation
description: Constrói, instala e valida o Linka em iPhone, iPad e Mac reais pelo Renan, separando simulador de aparelho físico.
---

# Renan Real Device Validation

Use para provar que a entrega sobrevive ao ecossistema Apple real. Simulador serve para layout rápido, mas não prova medição de rede real, permissões, ciclo de vida nem rede móvel.

## 1. Quando a prova real é obrigatória

Mudanças que tocam medição, diagnóstico de rede, Assist, permissões, background, App Intents/Widgets, resultado na tela ou adaptação macOS exigem validação na máquina/aparelho correspondente.

## 2. Roteiro por superfície

- **Mac (`aplicativo-ios/LinkaApp.xcodeproj` / `.agents/scripts/build-mac.sh`):** Abra o app real e percorra sidebar, toolbar, menus, atalhos de teclado, sheets, alertas, detalhes, ações destrutivas e redimensionamento de janela (estreita, padrão e tela cheia). Não valide só a tela inicial.
- **iPhone:** Safe area / Dynamic Island, Dynamic Type, Wi‑Fi e celular, perda/troca de rede no meio do teste, background/foreground, cancelamento, Light/Dark e VoiceOver/Reduce Motion.
- **iPad:** Adaptação de largura, portrait/landscape e Split View/Stage Manager quando aplicável.

## 3. Regras de ambiente e assinatura

- Não altere `DEVELOPMENT_TEAM`, certificados ou entitlements compartilhados no repositório apenas para forçar compilação local.
- Não tente contornar restrições do sistema nem confunda build local com envio para TestFlight ou App Store (que exigem autorização explícita do Luiz).
- Registre sempre: aparelho/destino usado, tipo de rede, cenários executados, resultado e o que não pôde ser executado em hardware físico.
