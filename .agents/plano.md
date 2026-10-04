# Frentes do Linka — ponto de entrada

Estado: vigente como mapa de trabalho; não é declaração de conclusão das features.
Responsável: Codex principal (Marco).
Última revisão: 2026-10-04 — reconciliação documental por tema.
Base: WIP sobre `9eb1a09412db5279424adfb4a68a48e943eea18e`, branch `feat/macos-visual-direction-and-service-status`.
Referências: [documentação](../documentacao/README.md), [migração](../documentacao/MIGRACAO.md), [AGENTS.md](../AGENTS.md).

## Decisão de execução atual

Luiz aprovou validação e release locais no Mac, sem GitHub Actions pago. A migração documental anterior e a organização de brand/loja permanecem no WIP. Esta rodada adapta a automação existente; não autoriza upload, App Review ou publicação.

Plano de Camillo: manter `fastlane/Fastfile` como ponto único de validação e beta; desativar Actions; validar pacotes e destino iOS existente, serialmente, com cache fixo por worktree. Beta exige main limpa e SHA remoto, identidade coerente no YAML/archive/IPA, autorização e evidência persistida antes/depois do envio. Chave temporária privada é removida ao terminar. Na integração sobre main 8507ce71, global/iOS/widget e Mac preservam 1.1.5/54; as identidades anteriores 52/49 pertencem somente ao snapshot inicial. `release.sh` só prepara a candidata e recupera seus arquivos se a geração falhar.

Aceite: controles testados sem envio real, workflows removidos, Actions remoto desativado, WIP alheio preservado e procedimento atualizado em [operação](../documentacao/operacao/README.md). Nenhum novo simulador, script paralelo ou fluxo de publicação. Estado: implementação integrada no WIP e controles revisados sem bloqueio novo por Tito. Fastlane carregado e testes simulados dos controles passaram; nenhuma release ou teste/build do app executado. Camillo/Fastlane, Pedro/versionamento, Codex/integração e Tito/revisão.

## Frentes e fontes mantidas

| Frente | Estado reconhecido nesta revisão | Fonte da decisão/comportamento e pendências | Responsável |
|---|---|---|---|
| Medição, estabilidade e resposta sob carga | Implementação observada; validação física e divergências de contrato pendentes | [Medição](../documentacao/features/medicao/README.md) e [arquitetura](../documentacao/arquitetura/README.md) | Camillo/executor/Tito |
| Telemetria/Home viva e cenários de uso | Código observado; evidência viva não equivale a resultado formal | [Insights](../documentacao/features/insights/README.md) e [interface](../documentacao/features/interface-e-acessibilidade/README.md) | Camillo/Íris |
| Histórico, 0/1/2 medições e CloudKit | Comportamento estático documentado; round-trip e visual da candidata pendentes | [Histórico](../documentacao/features/historico/README.md) | Camillo/Tito |
| Assist, NDS e segurança | Composição local descrita; operação remota não verificada | [Assist](../documentacao/features/assist/README.md), [arquitetura](../documentacao/arquitetura/README.md) e [Netscope](../documentacao/arquitetura/NETSCOPE.md) | Camillo/orquestrador |
| Plus promocional, StoreKit e publicidade | WIP local preservado; não equivale a compra/consentimento validados | [Plus](../documentacao/features/linka-plus/README.md) | Executor/Tito |
| Wi-Fi avançado e roteador | Integrações observadas; diferenças entre plataformas e entitlement abertas | [Wi-Fi](../documentacao/features/diagnostico-wifi/README.md) e [roteador](../documentacao/features/roteador/README.md) | Pedro/Camillo |
| DNS, otimização e Ambientes | Planos anteriores reconciliados com código; aceites não encerrados por documentação | [DNS](../documentacao/features/dns/README.md), [otimização](../documentacao/features/otimizacao/README.md), [Ambientes](../documentacao/features/perfis-de-rede/README.md) | Pedro/Íris |
| Status e notificações | Contrato local descrito; entrega push/relay e frescor pendentes | [Status](../documentacao/features/status-de-servicos/README.md) | Pedro/Tito |
| Paridade Apple, iPad e Mac | Inventário estático; divergências dimensionais e aceite visual ainda abertos | [Interface](../documentacao/features/interface-e-acessibilidade/README.md) e [design](../documentacao/design/README.md) | Íris/Tito |
| Widgets, Siri e Atalhos | Composição atual documentada; invocação/instalação não executadas | [Integrações Apple](../documentacao/features/integracoes-apple/README.md) | Camillo/Tito |
| Triagem offline | Serviço e UI observados; redes e acessibilidade sem execução | [Triagem](../documentacao/features/triagem-de-conectividade/README.md) | Executor/Tito |
| Site e materiais públicos | Código/material local inventariado; produção/loja não consultadas | [Site](../documentacao/features/site-institucional/README.md), [operação](../documentacao/operacao/README.md) | Íris/orquestrador |

Cada pendência tem evento e critério de fechamento na fonte correspondente. Estados acima são evidência da inspeção documental, não novas prioridades nem aprovação dos planos antigos. Não usar o nome desta branch para inferir qual dessas frentes será a próxima execução.

## Regras preservadas entre frentes

- Medição não recebe pergunta prévia sobre ambiente; associações são explícitas após resultado elegível.
- Observação da Home não comprova banda medida nem causa de falha. Falta de evidência permanece inconclusiva.
- Mudança de contrato/persistência exige revisar consumidores e compatibilidade, sem promover registros antigos a evidência de metodologia nova.
- Nenhum segredo permanente no cliente; ativação de transporte remoto depende do contrato e dos gates da frente correspondente.
- iOS/iPadOS/macOS têm entradas e limitações próprias; não declarar paridade ou visual pronto por compilação.

## Próxima alteração material

Abrir plano específico quando o gate arquitetural exigir; ligar aqui com escopo, estado e responsável. Usar os critérios e divergências da feature como entrada, evitando reintroduzir vários planos inteiros sob um título alheio. O orquestrador confere a fonte impactada antes de implementação e antes de release relevante.
