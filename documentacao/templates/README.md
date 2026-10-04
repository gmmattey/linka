# Templates de documentação por feature

Estado: vigente.
Responsável: Codex principal (Marco).
Última revisão: 2026-10-04 — modelos, instruções de uso e links locais.
Referência: [Governança documental](../GOVERNANCA_DOCUMENTAL.md); organização por feature definida com Luiz nesta conversa.

## Começar com um arquivo

1. Escolher um nome de capacidade reconhecível pelo usuário, em minúsculas com hífens: `documentacao/features/<feature>/`.
2. Copiar [FEATURE_README.md](FEATURE_README.md) para `README.md` nessa pasta. Este é o modelo padrão; reúne produto, técnica e validação.
3. Conferir as fontes existentes e preencher os campos `{{...}}`. Usar “não verificado” para lacunas e “não se aplica — motivo” quando pertinente. Não transformar exemplo, hipótese ou cabeçalho de template em fato do produto.
4. Converter referências preenchidas em links Markdown relativos ao destino final. Os templates usam placeholders sem links fictícios; caminhos relativos precisam ser calculados depois da cópia.
5. Registrar a feature no índice. [FEATURES_INDICE.md](FEATURES_INDICE.md) é o modelo para `documentacao/features/INDICE.md`; o [índice de features](../features/INDICE.md) já existe: adicionar a linha, sem substituí-lo.
6. Conferir links, estado, fontes e evidências antes de encerrar. Remover orientações de preenchimento e linhas de exemplo não utilizadas.

## Separar somente quando crescer

| Modelo opcional | Destino na pasta da feature | Conteúdo a extrair do README |
|---|---|---|
| [FEATURE_FUNCIONAL.md](FEATURE_FUNCIONAL.md) | `funcional.md` | Propósito, comportamento, estados, plataformas e experiência |
| [FEATURE_TECNICO.md](FEATURE_TECNICO.md) | `tecnico.md` | Mapa técnico, fluxo, contratos, dependências e operação |
| [FEATURE_VALIDACAO.md](FEATURE_VALIDACAO.md) | `validacao.md` | Critérios, evidências e validação pendente |

Ao extrair uma seção, substituir o conteúdo no README por um resumo e link para o arquivo criado. O README mantém identidade, propósito resumido, estado, base conferida, navegação, mudanças em andamento e perguntas abertas. Não manter duas cópias da mesma regra. Cada arquivo extraído registra sua própria revisão.

## Leitura pelos agentes

O caminho de entrada é AGENTS.md → [índice de features](../features/INDICE.md) → README da feature → referências compartilhadas necessárias → código e testes. Para temas transversais, consultar a [entrada documental](../README.md). Consultar também features dependentes quando o mapa de impacto indicar. Documentação orienta a investigação; não substitui a conferência do comportamento real.

Arquitetura compartilhada, contratos e Design System continuam nas fontes existentes. Planos em `.agents/` descrevem mudanças; a documentação da feature descreve o estado consolidado, com diferenças ainda abertas explicitadas.

## Estado de adoção

O acervo por capacidade foi criado na [migração de 2026-10-04](../MIGRACAO.md). Estes arquivos continuam sendo modelos para novas capacidades; não são documentação de funcionalidades implementadas. Os README preenchidos vivem em `documentacao/features/`.
