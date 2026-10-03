# Wi-Fi avançado durante a promoção Plus

## Problema e decisão
A UI libera Plus promocional, mas App Intents consultavam somente compras e negavam importação Wi-Fi avançada a quem não comprou. A promoção deve liberar a capacidade sem retirar anúncios.

## Contrato compartilhado
`LinkaEntitlementSnapshotResolver` seleciona compra verificada válida, depois promoção aplicável à plataforma/data, depois Free. `StoreKitEntitlementProvider` e `ShortcutEntitlementSnapshot` usam o mesmo contrato. Verificação StoreKit e seleção dos produtos permanecem nos adaptadores. Override DEBUG continua restrito ao desenvolvimento; macOS continua sem promoção.

## Limites
Não alterar importação, validação de payload, vínculo com AP, engine, preços, calendário ou versão. Preservar a semântica temporal existente: campanha inclui o instante endsAt; política de capacidade trata validUntil como expiração exclusiva. Não ampliar o período neste hotfix.

## Validação
Testar promoção sem compra com advancedWiFi liberado e anúncios; precedência da compra; fim da promoção; plataforma sem promoção; compra expirada. Rodar suite LinkaEntitlements. Build do app e fluxo físico do Atalho são validações separadas: corrigir entitlement não garante disponibilidade de dados Wi-Fi no iOS.
