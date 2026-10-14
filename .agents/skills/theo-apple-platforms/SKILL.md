---
name: theo-apple-platforms
description: Delimita capacidades e interação reais entre iOS, iPadOS e macOS.
---

# Theo Apple Platforms

Inspecione target, deployment target, entitlements, source inclusion e `#if` antes de declarar suporte. Classifique cada destino como nativo, Catalyst, app iPad compatível ou não suportado. Para macOS, cubra AppKit/SwiftUI quando presentes, janelas/redimensionamento, menu, mouse/trackpad/teclado e permissões; para iOS/iPad, touch, orientações e multitarefa.

Não transfira permissão, API Wi‑Fi, extensões, publicidade ou comportamento de um destino ao outro por analogia. Registre API indisponível e fallback honesto.
