# Marca implementada no Linka

Estado: exportações idênticas aos assets do app local.
Responsável: orquestrador; Íris para identidade.
Última revisão: 2026-10-04 — catálogo, consumidores SwiftUI e comparação SHA-256.
Base: checkout WIP sobre `9eb1a094`; não atesta binário publicado.
Referências: [design](../documentacao/design/README.md) e [manifesto de origem](manifest.json).

## Arquivos para usar

| Uso | Claro | Escuro / variante |
|---|---|---|
| Marca Linka | [wordmark](linka/wordmark.svg) | [wordmark escuro](linka/wordmark-dark.svg) |
| Linka Plus | [Linka+](linka-plus/linka-plus.svg) | [Linka+ escuro](linka-plus/linka-plus-dark.svg) |
| Assist | [Assist](assist/assist-wordmark.png) | [Assist escuro](assist/assist-wordmark-dark.png) |
| Ícone iOS/iPadOS | [AppIcon-iOS](icons/AppIcon-iOS.png) | Mesmo arquivo configurado no catálogo |
| Ícone Mac | [1x](icons/AppIcon-Mac-1x.png) | [2x](icons/AppIcon-Mac@2x.png) |

Estas são cópias de distribuição, sem redesenho ou conversão. A implementação continua lendo [Assets.xcassets](../aplicativo-ios/LinkaApp/Sources/Assets.xcassets/), inclusive as variantes em Contents.json. Atualizar exportações quando o asset fonte mudar e renovar o manifesto; não editar a cópia isoladamente.

## Correspondência com o código

- `wordmark`: SplashView, sidebar Mac e ShareCardView.
- `LinkaPlusWordmark`: LinkaPlusWordmarkView, usado por compra, Ajustes, Histórico e aviso de Expert Mode.
- `AssistWordmark`: AssistView.
- `AppIcon`: Contents.json e configuração de target do app.

O site renderiza wordmark inline em seu componente React e usa seu próprio conjunto de ícones públicos. Esta tarefa não substitui a marca do site nem executa `generate-icons.js`, que também sobrescreve assets do app. Não presumir igualdade entre outros SVG só porque têm o mesmo nome.

A loja aponta para este kit, sem outra cópia em `store/app-store/brand/`. Não existe marca Netscope implementada na composição local examinada; nenhuma foi criada.

## Limites de uso

Preservar geometria, cores, proporção e transparência. Não substituir wordmark por texto nem inserir promessa comercial no asset. As regras específicas do Plus estão no [guia do kit](linka-plus/README.md).

Verificação feita: nove exportações com hashes iguais às respectivas fontes. Renderização/contraste na candidata e estado da loja não foram validados. Responsável pela próxima conferência: executor/Íris, antes de usar em novo material público; fechamento exige origem e variante corretas na composição final.
