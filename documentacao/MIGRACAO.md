# Migração documental — 2026-10-04

Estado: concluída a migração documental local; aceites funcionais permanecem separados.
Responsável: Codex principal (Marco).
Base: branch `feat/macos-visual-direction-and-service-status`, HEAD `9eb1a09412db5279424adfb4a68a48e943eea18e` com WIP preexistente.
Última revisão: 2026-10-04 — reconciliação de fontes, estrutura e referências locais.
Referências: [governança](GOVERNANCA_DOCUMENTAL.md), [entrada documental](README.md), [features](features/INDICE.md), [ledger](../.agents/plano.md).

## Pedido e alcance

Luiz solicitou gerar a documentação pela nova governança e excluir a anterior, permanecendo somente a nova atualizada. A migração produz referências por capacidade, produto, design, arquitetura e operação; remove manuais, planos e relatórios substituídos e os arquivos de `.old/` dentro de `documentacao/` e `.agents/`. Não mantém cópia legada concorrente no checkout.

A base é esta worktree, não a mais nova versão possível do produto: não foi feito fetch nem integração de outras branches. Diferenças encontradas no código são documentadas, sem correção funcional. Código/configuração WIP, assets atuais, protótipo atual, tokens/JSX, schema e fixtures permanecem preservados. Licença, changelog, notas de candidata, metadata e imagens de loja são artefatos legais/de versão/publicação, não documentação anterior do comportamento; não foram substituídos por alegações novas de release.

## Cobertura e responsabilidade

- Íris: Produto, Design, interface/acessibilidade e site; leu código e fontes anteriores, com escrita documental explicitamente delegada nesta tarefa.
- Camillo: Medição, Histórico, Insights, Assist, arquitetura e Netscope.
- Pedro: Plus/publicidade, Wi-Fi avançado, roteador, DNS, otimização, Ambientes e status de serviços.
- Orquestrador: integrações Apple, triagem, operação, índices, ledger, governança, referências, remoções e validação documental.
- Tito: revisão independente por amostra, somente leitura. Pediu preservar o contrato de compartilhamento no Histórico. A fonte final contém cartão, renderização, privacidade, falha e a intenção de permitir somente resultado concluído atual/histórico; diferença dos gates reais permanece como HIS-11. O orquestrador conferiu essa inclusão. Não é auditoria exaustiva do app nem aprovação de release.

## Fontes substituídas

Caminhos antigos são proveniência textual. Os links levam apenas às fontes atuais. A tabela registra cobertura por assunto; não transforma aceites dos planos antigos em concluídos.

| Fonte anterior removida | Destino da informação aplicável |
|---|---|
| `documentacao/arquitetura/INDICE.md` | [documentacao/README.md](README.md) |
| `documentacao/arquitetura/PLANO_HISTORICO_MEDICOES.md` | [documentacao/features/historico/README.md](features/historico/README.md) |
| `documentacao/arquitetura/PLANO_NETWORK_INSIGHTS.md` | [documentacao/features/insights/README.md](features/insights/README.md) |
| `documentacao/arquitetura/PLANO_NETWORK_ASSIST.md` | [documentacao/features/assist/README.md](features/assist/README.md) |
| `documentacao/arquitetura/PLANO_NETSCOPE.md` | [documentacao/arquitetura/NETSCOPE.md](arquitetura/NETSCOPE.md) |
| `documentacao/atalhos/linka-wifi-advanced.md` | [documentacao/features/diagnostico-wifi/README.md](features/diagnostico-wifi/README.md) |
| `documentacao/funcional/VISAO.md` | [documentacao/PRODUTO.md](PRODUTO.md) |
| `documentacao/funcional/HISTORIA.md` | [documentacao/PRODUTO.md](PRODUTO.md) |
| `documentacao/funcional/RecomendacaoEquipamentos.md` | [documentacao/features/roteador/README.md](features/roteador/README.md) |
| `documentacao/produto/LINKA_PLUS.md` | [documentacao/features/linka-plus/README.md](features/linka-plus/README.md) |
| `documentacao/produto/VOZ.md` | [documentacao/PRODUTO.md](PRODUTO.md) |
| `documentacao/produto/app-store-connect-urls.md` | [documentacao/features/site-institucional/README.md](features/site-institucional/README.md) |
| `documentacao/release-process.md` | [documentacao/operacao/README.md](operacao/README.md) |
| `documentacao/design/DIRECAO_VISUAL_MACOS.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/readme.md` | [documentacao/design/README.md](design/README.md) |
| `DSI_ARQUITETURA.md` | [documentacao/arquitetura/README.md](arquitetura/README.md) |
| `design-qa.md` | [documentacao/features/site-institucional/README.md](features/site-institucional/README.md) |
| `plano.md` | [documentacao/features/assist/README.md](features/assist/README.md) |
| `plano-assist-agora.md` | [documentacao/features/assist/README.md](features/assist/README.md) |
| `plano-triagem-conectividade-offline.md` | [documentacao/features/triagem-de-conectividade/README.md](features/triagem-de-conectividade/README.md) |
| `plano-valor-linka.md` | [documentacao/PRODUTO.md](PRODUTO.md) |
| `plano-correcoes-produto.md` | [.agents/plano.md](../.agents/plano.md) |
| `plano-issue-135-finalizar-ajustes.md` | [documentacao/features/interface-e-acessibilidade/README.md](features/interface-e-acessibilidade/README.md) |
| `plano-issue-149-apple-ui-consistency.md` | [documentacao/features/interface-e-acessibilidade/README.md](features/interface-e-acessibilidade/README.md) |
| `plano-jornada-apple-sem-navbar.md` | [documentacao/features/interface-e-acessibilidade/README.md](features/interface-e-acessibilidade/README.md) |
| `plano-direcao-visual-mac-ios.md` | [documentacao/design/README.md](design/README.md) |
| `.agents/plano-ambientes-de-medicao.md` | [documentacao/features/perfis-de-rede/README.md](features/perfis-de-rede/README.md) |
| `.agents/plano-dns-linka-plus.md` | [documentacao/features/dns/README.md](features/dns/README.md) |
| `.agents/plano-otimizacao-linka-plus.md` | [documentacao/features/otimizacao/README.md](features/otimizacao/README.md) |
| `.agents/plano-perfis-de-rede-linka-plus.md` | [documentacao/features/perfis-de-rede/README.md](features/perfis-de-rede/README.md) |
| `.agents/plano-ipad-largura-adaptativa.md` | [documentacao/features/interface-e-acessibilidade/README.md](features/interface-e-acessibilidade/README.md) |
| `.agents/plano-macos-layout-ux.md` | [documentacao/features/interface-e-acessibilidade/README.md](features/interface-e-acessibilidade/README.md) |
| `.agents/plano-paridade-ios-macos.md` | [documentacao/features/interface-e-acessibilidade/README.md](features/interface-e-acessibilidade/README.md) |
| `pr-body-150.md` | [documentacao/operacao/README.md](operacao/README.md) |
| `pr-body.txt` | [documentacao/operacao/README.md](operacao/README.md) |
| `documentacao/design/design_system/components/speedtest/PhaseDots.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/components/speedtest/DetailsDisclosure.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/components/speedtest/MetricRing.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/components/speedtest/StatDisplay.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/components/speedtest/AdSlot.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/components/core/Icon.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/components/core/TextLink.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/components/core/Card.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/components/core/StatusLabel.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/components/core/Eyebrow.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/components/core/Button.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/components/layout/PageHero.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/components/layout/SiteFooter.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/components/layout/SiteHeader.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/components/brand/Wordmark.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/components/content/StepItem.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/components/content/ComparisonTable.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/components/content/LegalSection.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `documentacao/design/design_system/components/content/ValueCard.prompt.md` | [documentacao/design/README.md](design/README.md) |
| `store/app-store/screenshots/README.md` | [store/app-store/README.md](../store/app-store/README.md) |
| `store/app-store/screenshots/rascunhos-kit-marketing-iris-2026-09-06/README.md` | [store/app-store/README.md](../store/app-store/README.md) |
| `store/app-store/screenshots/rascunhos-iris-2026-09-06/README.md` | [store/app-store/README.md](../store/app-store/README.md) |
| `store/app-store/screenshots/marketing/pt-BR/mac/README.md` | [store/app-store/README.md](../store/app-store/README.md) |
| `store/app-store/screenshots/final/pt-BR/mac/README.md` | [store/app-store/README.md](../store/app-store/README.md) |
| `store/app-store/review/README.md` | [store/app-store/README.md](../store/app-store/README.md) |

README de LinkaEntitlements, MeasurementHistory, NetworkInsights, NetworkAssist e LinkaAppIntents foi reescrito como entrada à fonte por feature, eliminando descrições de integração futura já superadas. `.agents/plano.md` foi reescrito como ledger com estado/links, sem encerrar implementações por inferência. Governança, WORKFLOW, skills com referências e README raiz foram alinhados aos destinos novos.

## Arquivos históricos obsoletos

70 arquivos foram removidos sob `.old/` (inclui snapshots antigos de documentação/design e planos aposentados). São materiais já classificados como históricos; não foram revalidados como produto atual. Não se migram instruções de Android/PWA/Firebase ou personas antigas como decisões atuais. O histórico rastreado permanece recuperável no Git.

O plano Netscope não rastreado foi preservado integralmente em substância em [NETSCOPE.md](arquitetura/NETSCOPE.md), com estado proposto, conflitos e limites locais no topo. Antes de excluir o original, a comparação de linhas confirmou que apenas o título antigo foi substituído; o conteúdo restante estava no novo documento.

## Validação e limites

A inspeção de código, contratos e testes é estática. Não foram executados testes do app/pacotes, build, simulador, dispositivo físico, serviços remotos, TestFlight, App Review ou publicação. A existência de teste/contrato/link não é validação de comportamento em execução.

Validação final executada em 2026-10-04, neste checkout:

- 15 README de capacidades preenchidos, com responsável, revisão, base e limitações; nenhum placeholder de template nesses documentos.
- 609 links Markdown locais conferidos quanto à existência do destino; nenhum ausente. URLs externas e âncoras não foram verificadas por esse procedimento.
- 130 arquivos anteriores removidos: 60 fontes substituídas e 70 arquivos de snapshots/planos históricos. Nenhuma entrada do inventário de remoção continua no disco.
- `git diff --check` limpo; arquivos novos conferidos diretamente quanto a whitespace e placeholders.
- Comparação SHA-256 contra baseline capturado antes das edições documentais: nenhuma alteração em código, configuração ou assets rastreados fora dos snapshots históricos removidos intencionalmente. WIP funcional preexistente permaneceu preservado.
- Conteúdo Netscope não rastreado comparado integralmente antes da remoção; revisão independente de Tito confirmou igualdade do corpo original e enquadramento como proposta.

A revisão de Tito foi por amostra, conforme alcance acima, e a conferência global foi documental. Nenhum commit, push, merge ou publicação realizado.

## Pendências que permanecem

As pendências funcionais/técnicas estão nos README das capacidades e [ledger](../.agents/plano.md), com responsáveis e eventos. Incluem protocolo regional, semântica de ausência, schema externo, campos CloudKit, promoção no Atalho, frescor de status, acessibilidade, privacidade pública e operação Netscope. A migração não as resolve nem as esconde.

Responsável pela manutenção: orquestrador. Evento de revisão: próxima mudança do tema e antes de release relevante. Fechamento: documentação e código da candidata confrontados, com evidência correspondente ao nível declarado.
