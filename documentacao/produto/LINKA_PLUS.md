# Linka Free e Linka Plus

Este documento define a divisão de produto Free/Plus e a arquitetura inicial dos módulos opcionais do Linka no ecossistema Apple.

`AGENTS.md` continua sendo a autoridade de governança do repositório.

## Princípio

O Linka é, no núcleo, um SpeedTest minimalista. Sobre esse núcleo, pode absorver capacidades vindas do SignallQ (que virou produto Android/Web-only) desde que sejam viáveis no ecossistema Apple e passem pela curadoria de minimalismo — protagonismo do resultado, divulgação progressiva, base em dado real ([`AGENTS.md`](../../AGENTS.md) §1 e §9).

O Linka Plus é o pacote pago que habilita as capacidades adicionais: acompanhar, comparar, interpretar e responder perguntas sobre os dados que o próprio Linka mediu ou que a Apple expõe ao aplicativo. O que ele evita é virar central de reparo — sem instruir troca de canal Wi-Fi específico do vizinho, saúde do modem do provedor ou qualquer dado que a Apple não permita observar de dentro do app.

## Free

O teste principal permanece completo e útil sem assinatura:

- medição de latência;
- download;
- upload;
- resultado;
- detalhes básicos;
- reteste.

Não limitar quantidade de testes para forçar assinatura.

## Plus

O Plus habilita capacidades adicionais sem alterar o motor de medição:

- histórico e comparação;
- tendências baseadas nas próprias medições;
- Assist para perguntas sobre medição atual e histórico;
- integrações Apple, como Widgets, App Intents/Siri Shortcuts e histórico compartilhado quando forem implementadas.

## Arquitetura

`LinkaEngine` continua responsável exclusivamente pela medição.

`LinkaModules` é um Swift Package separado e não importa SwiftUI, UIKit, StoreKit ou SDK de IA. A UI e adapters concretos ficam no app.

```text
LinkaApp (SwiftUI)
    |
    +-- LinkaEngine      -> mede
    |
    +-- LinkaModules
          +-- EntitlementProviding
          +-- HistoryProviding
          +-- InsightProviding
          +-- AssistProviding / AssistTransport
          +-- AppleIntegrationProviding
```

A ligação deve ocorrer por protocolos. Uma implementação local pode ser substituída por persistência, StoreKit, CloudKit ou serviço remoto sem mudar as telas consumidoras.

## Política de acesso

A matriz fica centralizada em `LinkaAccessPolicy`:

| Capacidade | Free | Plus |
| --- | --- | --- |
| SpeedTest | sim | sim |
| Histórico | sim | sim |
| Insights | não | sim |
| Assist | não | sim |
| Integrações Apple | não | sim |

A UI não deve espalhar verificações de assinatura. Ela pergunta ao provedor de entitlement se uma capacidade está disponível.

## Estado das implementações

### Funcional agora

- contratos públicos dos módulos;
- política Free/Plus;
- histórico persistido em disco (`FileMeasurementHistoryRepository`), integrado ao fluxo principal do app;
- comparação determinística entre duas medições e tendência via `NetworkInsights`;
- StoreKit 2 real (compra, restauração, entitlements) e paywall (`PurchaseSheet`);
- Widgets de tela de bloqueio/início, atualizados após cada medição;
- App Intents/Siri Shortcuts (início de teste, última medição, histórico); a medição silenciosa via atalho existe mas fica desligada por padrão (feature flag);
- Network Assist conectado a um relay remoto real, sem chave embutida no cliente;
- código de sincronização CloudKit entre dispositivos, incluindo resolução de conflito e fila de exclusão offline;
- testes unitários da matriz de acesso, histórico, comparação, Assist e sincronização CloudKit.

### Implementado no código, mas ainda não operante em produção

- **CloudKit/sincronização entre dispositivos**: o código está pronto e testado, mas o container iCloud ainda não foi provisionado no Apple Developer Portal. Enquanto isso não acontecer, o app degrada com segurança para funcionamento 100% local — a sincronização não chega ao usuário final.

### Deliberadamente ainda não implementado

- persistência/autenticação de conta de usuário (o Linka não exige login);
- backend de contas.

Atualizado após auditoria de código em 2026-09-11: esta seção descrevia StoreKit, CloudKit, Widgets e App Intents como não implementados; todos já estão no código. Mantenha esta lista sincronizada com o estado real do app a cada mudança relevante de escopo, em vez de deixá-la descrever uma fundação inicial que já foi superada.

## Assist: limite de escopo

Entrada permitida:

- pergunta do usuário;
- medição atual;
- medições recentes do Linka.

Exemplos adequados:

- "Minha velocidade mudou desde ontem?"
- "Esse resultado é diferente dos últimos testes?"
- "Meu ping aumentou?"

O Assist opera sobre medição e dado do sistema exposto pela Apple. Ele não deve fabricar diagnóstico sem base — nada de inferir causa raiz a partir de dado que a Apple não expõe ao app.

## Integração ao projeto Xcode

`aplicativo-ios/project.yml` declara `LinkaModules` como package local ao lado de `LinkaEngine`.

Após alterar dependências ou arquivos do projeto, regenere o `.xcodeproj` via XcodeGen no ambiente de desenvolvimento e valide build no simulador/dispositivo antes de merge.

## Gate antes de merge

1. `swift test` em `aplicativo-ios/LinkaModules`.
2. Regenerar `LinkaApp.xcodeproj` com XcodeGen.
3. Build iOS e macOS.
4. Confirmar que o SpeedTest existente não mudou.
5. Confirmar que não há SwiftUI/UIKit/StoreKit dentro de `LinkaModules`.
6. Confirmar que não existe API key ou endpoint de IA embutido.

## Promoção e publicidade — 2 de outubro de 2026

Até o fim de 31/10/2026 (São Paulo), a campanha libera recursos Plus sem compra. Esse acesso promocional mantém anúncios não personalizados. Acesso a recursos e ausência de anúncios são decisões independentes.

Uma assinatura/trial StoreKit válido ou acesso vitalício válido permanece sem anúncios. Após a campanha, quem não tiver compra válida volta ao Free com anúncios; o fim da promoção não remove anúncios automaticamente. Medição e resultado não exibem anúncios.
