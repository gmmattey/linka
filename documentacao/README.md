# Documentação do Linka

Estado: vigente para o checkout documentado.
Responsável: Codex principal (Marco).
Última revisão: 2026-10-04 — reorganização por capacidade e inspeção estática das fontes locais.
Base: branch `feat/macos-visual-direction-and-service-status`, WIP sobre `9eb1a09412db5279424adfb4a68a48e943eea18e`. Não representa automaticamente main, TestFlight ou produção.
Referências: [AGENTS.md](../AGENTS.md) e [governança documental](GOVERNANCA_DOCUMENTAL.md).

## Encontrar uma resposta

| Pergunta | Fonte |
|---|---|
| O que é o Linka, para quem existe e como fala? | [Produto](PRODUTO.md) |
| Como uma capacidade funciona e onde vive no código? | [Índice de features](features/INDICE.md) |
| Quais fronteiras e contratos são compartilhados? | [Arquitetura](arquitetura/README.md) |
| Qual direção visual e quais assets usar? | [Design](design/README.md) |
| Como desenvolver, validar e preparar publicação? | [Operação](operacao/README.md) |
| O que continua pendente ou em andamento? | [Plano de entrada](../.agents/plano.md) e pendências de cada feature |
| Como manter estes documentos? | [Governança](GOVERNANCA_DOCUMENTAL.md) e [templates](templates/README.md) |
| O que esta migração substituiu e verificou? | [Registro de migração](MIGRACAO.md) |

## Como interpretar a documentação

“Vigente” identifica a referência mantida, não um selo de funcionamento em produção. Cada documento separa código inspecionado, comportamento desejado, validação existente e pendências. Testes citados como fonte não foram necessariamente executados. Para mudar uma capacidade, consultar seu README, as dependências indicadas e o código atual.

Os documentos anteriores substituídos são removidos por solicitação expressa do Luiz de 2026-10-04; não haverá uma segunda documentação em `.old/`. Assets, protótipo atual, schemas e fixtures continuam como fontes especializadas. A preservação de um contrato não significa que sua equivalência ao modelo Swift tenha sido validada: consultar as divergências de arquitetura.
