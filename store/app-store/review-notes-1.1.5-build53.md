# App Review — candidata 1.1.5 (53)

Rascunho para usar somente após upload/processamento e validação física da candidata. Não descreve a build 52.

## Review Notes (English)

This update fixes ad eligibility during our temporary Plus promotion. Promotional Plus access unlocks features but does not remove ads. A verified paid subscription remains ad-free.

On a fresh installation on a physical iPhone or iPad, with “Allow Apps to Request to Track” enabled in system Settings and no existing ATT decision for Linka, launch the app and allow the StoreKit entitlement check to finish. For a user without a paid subscription, the system ATT request appears before the ad consent/loading flow, including during the free Plus promotion. No completed measurement is required for the Home placement. The History placement is also eligible when it contains measurements and no ad request has already been used in that session.

The app always requests non-personalized ads (npa=1, publisher privacy personalization disabled, publisher first-party ID disabled), regardless of the ATT answer. Denying tracking does not restrict app functionality; ads may still be served without IDFA. Advertising depends on consent and inventory availability. There are no ads during a measurement or on its result screen.

ATT is an OS-managed one-time request. If the permission was previously decided or system restrictions disable requests, iOS/iPadOS does not display it again. Do not use a paid Plus account for this review flow. Promotional access is ad-eligible.

The subscription screen includes annual renewal terms, price, Restore Purchases and links to Privacy and Terms of Use. EULA: https://linka-speedtest.web.app/termos

## Pendências antes do envio

- Anexar link de gravação física da candidata, cobrindo ATT e fluxo seguinte.
- Conferir App Privacy do SDK e manter declaração de tracking coerente; não declarar “nenhum dado coletado”.
- Confirmar que não há mensagem IDFA remota duplicada no AdMob.
- Publicar a atualização da política de privacidade junto à entrega.
