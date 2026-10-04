# Linka

SpeedTest para iPhone, iPad e Mac: medir a conexão, entender o resultado e acompanhar mudanças. O site é institucional; não executa a medição.

Estado deste documento: vigente como entrada do repositório.
Responsável: Codex principal (Marco).
Última revisão: 2026-10-04 — caminhos, estrutura e procedimentos locais.
Referência: [AGENTS.md](AGENTS.md).

## Começar

- [Documentação atual](documentacao/README.md): produto, arquitetura, design e operação.
- [Capacidades do app](documentacao/features/INDICE.md): comportamento, código, testes e pendências por feature.
- [Desenvolvimento e publicação](documentacao/operacao/README.md): pré-requisitos, comandos e limites da validação.
- [Trabalho em andamento](.agents/plano.md): fontes por frente e critérios de fechamento.

## Estrutura

| Diretório | Conteúdo |
|---|---|
| [aplicativo-ios](aplicativo-ios/) | App SwiftUI, extensões e pacotes Swift |
| [aplicacao-web](aplicacao-web/) | Site React/TypeScript/Vite |
| [documentacao](documentacao/) | Referências atuais conforme a nova governança |
| [store/app-store](store/app-store/) | Materiais de loja, sujeitos à revisão contra a candidata |
| [fastlane](fastlane/) | Validação e TestFlight locais no Mac, sem GitHub Actions |

A documentação descreve o checkout identificado em cada fonte, inclusive WIP; não confirma a versão publicada. Não se usa `swift test` na raiz: selecionar o pacote conforme a [operação](documentacao/operacao/README.md).

Governança: [AGENTS.md](AGENTS.md), [workflow](.agents/WORKFLOW.md) e [processo documental](documentacao/GOVERNANCA_DOCUMENTAL.md). Licença em [LICENSE](LICENSE).
