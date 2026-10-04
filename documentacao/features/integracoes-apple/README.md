# Widgets, Siri e Atalhos

> Integração em 2026-10-04 sobre main `8507ce71`: a divergência promocional dos Atalhos descrita no snapshot 9eb1a094 + WIP abaixo foi corrigida na PR #273. Provider e App Intents usam `LinkaEntitlementSnapshotResolver`. Ver [contrato incorporado à main](../../arquitetura/PLANO_WIFI_AVANCADO_PROMOCIONAL.md). Esta integração preserva o código atual; não repete validação física ou release.

Estado: vigente como descrição estática do checkout.
Responsável: orquestrador; Camillo para contratos entre superfícies.
Última revisão: 2026-10-04 — composição do executor, contratos, widget e escrita de resumo.
Base conferida: WIP sobre `9eb1a09412db5279424adfb4a68a48e943eea18e`; distribuição não verificada.
Referências: [Intents](../../../aplicativo-ios/LinkaAppIntents/Sources/Intents.swift), [contratos](../../../aplicativo-ios/LinkaAppIntents/Sources/Contracts.swift), [composição do app](../../../aplicativo-ios/LinkaApp/Sources/LinkaApp.swift).
Termos de busca: WidgetKit, App Intents, Siri, Shortcuts, App Group, último resultado.

## Propósito e comportamento

Acessar a medição ou seu resultado pelas superfícies Apple. O widget apresenta um resumo persistido, não uma medição contínua. `StartSpeedTestIntent` abre o app e pede o início do teste; o motor continua no app. A família pequena mostra download/data ou estado sem medição; a média inclui upload e ping quando presentes. Ambas têm ação de analisar.

| Ação | Comportamento na composição atual de LinkaApp |
|---|---|
| `startSpeedTest` | Publica solicitação no coordinator, sem checagem de `appleIntegrations` nesse handler |
| `getLatestResult` | Lê a última medição do repositório; devolve resumo localizado ou mensagem de vazio |
| `openHistory` | Solicita abertura do histórico sem gate de integração no handler |
| `openPurchase` | Solicita compra quando a oferta temporária não está ativa |
| `openLatestMeasurement` | Ramo protegido por `appleIntegrations`; solicita abertura do detalhe |
| `measureNetworkSilently` | Intent oculto, condicionado a preferência; handler atual não implementa a medição silenciosa e retorna erro de não configurado quando passa o gate |

O helper `LinkaAppIntentExecutor.entitlementGated` oferece gate uniforme, mas não é o executor registrado por `LinkaApp.init`. Comentários antigos sobre exclusividade total Plus não descrevem essa composição. A política de acesso é detalhada em [Linka Plus](../linka-plus/README.md). Atalhos de importação Wi-Fi são uma integração distinta: [diagnóstico Wi-Fi](../diagnostico-wifi/README.md).

## Mapa técnico e fluxo

| Responsabilidade | Fonte/símbolo |
|---|---|
| Ações tipadas, resposta e erros | [Contracts.swift](../../../aplicativo-ios/LinkaAppIntents/Sources/Contracts.swift), `LinkaAppIntentExecutor.execute` |
| Registro para Siri/Atalhos | [AppShortcuts.swift](../../../aplicativo-ios/LinkaAppIntents/Sources/AppShortcuts.swift) |
| Comunicação com UI | [AppIntentCoordinator.swift](../../../aplicativo-ios/LinkaApp/Sources/Adapters/AppIntentCoordinator.swift) |
| Persistência do resumo e idioma | [LinkaWidgetShared.swift](../../../aplicativo-ios/LinkaWidgetShared/Sources/LinkaWidgetShared.swift) |
| Timeline | [LinkaWidgetTimelineProvider.swift](../../../aplicativo-ios/LinkaWidget/Sources/LinkaWidgetTimelineProvider.swift) |
| Apresentação e ação | [LinkaSpeedTestWidget.swift](../../../aplicativo-ios/LinkaWidget/Sources/LinkaSpeedTestWidget.swift) |
| Publicação após medição | [SpeedTestViewModel.swift](../../../aplicativo-ios/LinkaApp/Sources/Adapters/SpeedTestViewModel.swift), escrita de `LatestMeasurementSummary` e `reloadTimelines` |

App → resumo Codable no App Group `group.com.linka.assist` → reload da timeline → widget lê. A timeline usa uma entrada com política `.never`; não há polling periódico nessa implementação. O resumo contém download, upload/latência opcionais e data. Falha de decodificação ou armazenamento ausente resulta em resumo ausente. Não expõe identificadores Wi-Fi nesse payload.

## Plataformas, estados e limites

Os pacotes declaram iOS/macOS; o widget visual é integrado pelo projeto do app. Isso não comprova instalação em cada sistema. O Package.swift de LinkaWidget exclui os arquivos de view/bundle do alvo de teste: teste desse pacote não comprova a aparência da extensão. Conferir entitlements de App Group e destinos no projeto candidato.

Estados: sem resumo, resumo existente, ação pendente, acesso negado, executor não configurado e resposta sem valor. Erros do executor são explícitos; dado ausente não vira zero. O widget respeita a preferência de idioma compartilhada (`system`, pt-BR, en, es-419); fallback de idioma não suportado é inglês.

## Aceite e evidências

| ID | Critério | Evidência disponível em 2026-10-04 |
|---|---|---|
| APP-01 | Widget vazio não fabrica medição | Inspeção de view/provider |
| APP-02 | Ação abre app e usa o fluxo de medição | Inspeção de Intent, handler e coordinator; runtime não executado |
| APP-03 | Resumo preserva valores opcionais e data | Inspeção de modelo compartilhado e view |
| APP-04 | Acesso segue handler registrado, sem presumir helper não utilizado | Inspeção de LinkaApp.init e Contracts.swift |

Testes existentes: [LinkaAppIntents](../../../aplicativo-ios/LinkaAppIntents/Tests/), [LinkaWidgetShared](../../../aplicativo-ios/LinkaWidgetShared/Tests/) e [LinkaWidget](../../../aplicativo-ios/LinkaWidget/Tests/). Nenhum executado nesta migração. Build, dispositivo, Siri, instalação do widget e TestFlight não validados.

## Pendências e mudanças

| Tema | Responsável | Evento | Critério de fechamento |
|---|---|---|---|
| Disponibilidade real por plataforma e invocação após instalação | Tito/executor | Próxima mudança ou release de integrações | Teste de cada ação na build candidata, incluindo Free/Plus |
| Divergência entre comentários de gate uniforme e composição | Camillo | Próxima manutenção de integrações | Alinhar contrato/comentários à decisão de produto confirmada, com testes |
| Medição silenciosa não implementada no handler | Orquestrador | Antes de comunicar a capacidade | Decidir escopo e comprovar implementação, ou manter indisponível |
