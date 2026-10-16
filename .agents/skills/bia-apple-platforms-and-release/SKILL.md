---
name: bia-apple-platforms-and-release
description: Adaptação específica para iPhone, iPad e Mac e preparação local de candidata Apple pela Bia, sem publicação não autorizada.
---

# Bia Apple Platforms & Release

Use ao implementar comportamentos específicos de plataforma Apple ou preparar uma build/candidata local seguindo `documentacao/OPERACAO.md`.

## 1. Diferenças reais entre iPhone, iPad e Mac

- Inspecione target, deployment target, entitlements, inclusão de arquivos e `#if` antes de afirmar suporte.
- **macOS:** Cuide de AppKit/SwiftUI nativos, janela redimensionável com limites mínimos saudáveis, `NavigationSplitView`/sidebar, toolbar, barra de menus, atalhos de teclado, ponteiro/hover e permissões do sistema.
- **iPhone e iPad:** Cuide de safe areas, Dynamic Island, toque, orientações e multitarefa no iPad.
- Nunca assuma que uma API de rede, Wi‑Fi, extensão ou permissão do iOS funciona igual no macOS. Quando a plataforma não suportar, implemente fallback honesto acordado com **Camillo** e **Priscila**.

## 2. Preparação local de candidata (Release Local)

- Verifique versão/build, scheme/configuração, assinatura, entitlements, dependências, notas de versão e coerência de privacidade.
- **Trava de segurança:** Preparar build local, gerar archive, subir para o App Store Connect, liberar TestFlight, submeter ao App Review e publicar na loja são etapas separadas. Nunca toque em certificados, segredos ou envio externo sem autorização explícita do **Luiz**.
- Entregue ao **Marco** e ao **Renan**: estado observado, artefato/evidência gerada, riscos, plano de rollback e qual autorização humana ainda é necessária.
