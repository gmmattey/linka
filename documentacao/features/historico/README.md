# Histórico de medições

Estado do documento: vigente para o checkout WIP, sem atestado de produção.
Responsável: Codex principal; Camillo para persistência e contratos.
Última revisão: 2026-10-04 — leitura estática do repositório, factory, CloudKit, UI e testes citados.
Base conferida: `feat/macos-visual-direction-and-service-status`, HEAD `9eb1a094` + WIP preexistente.
Referências: [governança](../../GOVERNANCA_DOCUMENTAL.md), [arquitetura](../../arquitetura/README.md), fontes abaixo.
Termos de busca: histórico, measurements.json, FileMeasurementHistoryRepository, CloudKit, comparação, retenção.

## Propósito e limites

Consultar medições anteriores, abrir seus resultados e acompanhar mudanças reais. O histórico guarda fatos; [Insights](../insights/README.md) calcula comparações e padrões. Não é um backend próprio, não exige criar conta Linka para medir e não garante sincronização sem iCloud configurado.

## Comportamento atual

| Ação / estado | Comportamento no código | Limite ou recuperação |
|---|---|---|
| Teste concluído | Adapter tenta salvar `NetworkMeasurement` por ID | Falha de save não desfaz resultado; não há garantia de sucesso silencioso |
| Consulta | Filtra período, conexão, outcome, offset/limit e ordem | Ordenação por data desempata por UUID |
| Mesmo ID salvo novamente | Upsert substitui registro anterior | Não duplica a medição |
| Sem arquivo inicial | Store abre vazio | Não confundir com arquivo corrompido |
| JSON corrompido ou versão desconhecida | Erro `corruptedStore` / `unsupportedStoreVersion` | Sem reset destrutivo automático |
| Exclusão individual/total | Persistência local; decorator agenda exclusão remota | Tombstones mantêm exclusões pendentes enquanto remoto falha |
| Sem iCloud ou sync não permitido | Fonte local continua utilizada | Falha remota não deve bloquear leitura local |
| 0 / 1 / 2+ registros filtrados | `HistoryVisualizationState.resolve` escolhe vazio / medição única / gráfico | Gráfico com 2 registros não equivale a tendência estatística válida |

### Plataformas, acesso e experiência

iPhone/iPad e Mac compartilham o contrato e a factory. [HistoryView](../../../aplicativo-ios/LinkaApp/Sources/UI/HistoryView.swift) integra filtro, ordenação, abertura do resultado, exclusão, resumo e acesso a Insights. A factory consulta a capability `.history` para sincronização; o pacote de persistência não conhece preço/plano. Políticas atuais estão em [LinkaEntitlements](../../../aplicativo-ios/LinkaEntitlements/Sources/LinkaEntitlements.swift), não devem ser duplicadas aqui.

A tela contém WIP de publicidade; isso não muda o contrato de retenção do repositório. Não foi validada visualmente em nenhum destino. [Protótipo](../../design/prototipo/) e [Design System](../../design/design_system/) orientam geometria, acessibilidade e adaptação. Estados de carregamento/erro, confirmação destrutiva, VoiceOver, Dynamic Type e teclado precisam de execução posterior; esta leitura não comprova sua qualidade visual.

## Mapa técnico

| Responsabilidade | Fonte e símbolos |
|---|---|
| API e consultas | [MeasurementHistoryRepository.swift](../../../aplicativo-ios/MeasurementHistory/Sources/MeasurementHistoryRepository.swift): `MeasurementQuery`, `HistoryRetentionPolicy`, `MeasurementHistoryCollection` |
| Store persistente | [FileMeasurementHistoryRepository.swift](../../../aplicativo-ios/MeasurementHistory/Sources/FileMeasurementHistoryRepository.swift): `loadIfNeeded`, `persist`, `storeSchemaVersion` |
| Store volátil | [InMemoryMeasurementHistoryRepository.swift](../../../aplicativo-ios/MeasurementHistory/Sources/InMemoryMeasurementHistoryRepository.swift) |
| Composição do app | [History.swift](../../../aplicativo-ios/LinkaModules/Sources/History.swift): `LinkaMeasurementHistory.makeRepository`, `defaultFileURL` |
| Sincronização | [SyncingMeasurementHistoryRepository.swift](../../../aplicativo-ios/MeasurementHistoryCloudKit/Sources/SyncingMeasurementHistoryRepository.swift): `syncNow`, `applyRemote`, `pushRemoteDelete` |
| Record e conflito | [CloudKitMeasurementSync.swift](../../../aplicativo-ios/MeasurementHistoryCloudKit/Sources/CloudKitMeasurementSync.swift): `MeasurementRecordMapper`, `MeasurementConflictResolver`, `UserDefaultsTombstoneStore` |
| UI | [HistoryView.swift](../../../aplicativo-ios/LinkaApp/Sources/UI/HistoryView.swift): `HistoryVisualizationState`, `HistoryView` |

## Fluxo, persistência e privacidade

`SpeedTestViewModel → makeRepository → SyncingMeasurementHistoryRepository → FileMeasurementHistoryRepository → sync remoto em background`.

O store é um actor, valida a medição antes do save e mantém documento JSON com versão 1. Grava atomicamente em `Documents/measurements.json`, criando o diretório quando necessário. Datas internas usam `.deferredToDate` para preservar precisão; não confundir esse arquivo com o schema externo ISO-8601. Retenção admite máximo de entradas e idade; default é `.unlimited`, também usado pela factory examinada. Não há prazo de retenção automático implícito.

A factory reutiliza a instância por URL com cache protegido por lock; usa o provider de entitlement da primeira criação daquela URL. A sincronização usa private database, container `iCloud.com.linka.assist`, zona `MeasurementHistoryZone`, record `Measurement`. Esses identificadores no código não provam provisionamento ou operação em produção.

Conflitos do mesmo ID preferem outcome completo, depois maior quantidade de campos preenchidos, depois data de modificação; o merge preenche ausências do vencedor e valida o resultado. Records inválidos são descartados pelo mapper. Exclusões pendentes são preservadas para impedir ressurreição enquanto push remoto não completa.

O mapper transfere métricas escalares listadas nele, upload sob carga e blobs opcionais de estabilidade, referência regional e responsividade. Não mapeia `wifiContext`, `advancedWiFiDiagnostics`, `dnsResolutionMs`, `location` ou `devicePlatform` neste checkout. Logo, não afirmar paridade integral local ↔ iCloud. Contexto Wi-Fi persiste no JSON local; nomes/identificadores de rede são dados potencialmente sensíveis. Não afirmar anonimização. Exportação/compartilhamento precisa de revisão própria.

## Critérios de aceite e evidência

### Ambientes de medição

Ambientes são nomes escolhidos pela pessoa para agrupar resultados, não localização detectada. [OptimizationProfileCoordinator](../../../aplicativo-ios/LinkaApp/Sources/Adapters/OptimizationProfileCoordinator.swift) associa explicitamente o resultado aberto a um `NetworkEnvironment`; `refresh` carrega, não associa automaticamente. Pré-condições verificadas no coordinator: medição completa, Wi-Fi, identificação habilitada e SSID não vazio. O gate Plus está na [NetworkProfilesSection](../../../aplicativo-ios/LinkaApp/Sources/UI/NetworkProfilesSection.swift), não dentro do coordinator; não presumir que qualquer chamada direta já esteja autorizada.

[NetworkProfile.swift](../../../aplicativo-ios/NetworkProfiles/Sources/NetworkProfile.swift) define `NetworkEnvironment` (UUID, nome, datas) e `EnvironmentMeasurementAssignment` (measurementID, environmentID, assignedAt). Nomes repetidos são possíveis; UUID distingue ambientes. [NetworkProfileRepository](../../../aplicativo-ios/NetworkProfiles/Sources/NetworkProfileRepository.swift) oferece CRUD, assignment, reassign e `createAndAssign`; remoção do ambiente elimina associações, não medições do histórico.

[FileNetworkProfileRepository](../../../aplicativo-ios/NetworkProfiles/Sources/FileNetworkProfileRepository.swift) mantém schema 2 em `Application Support/Linka/network-profiles-v1.json`. Migração de schema 1 preserva IDs/nomes/datas dos perfis, descarta identidade/referências antigas e começa com assignments vazias. Valida IDs únicos e associações sem órfãos/duplicação; gravação é atômica. Versão desconhecida/corrupção falha explicitamente. SSID é pré-condição efêmera, não chave do novo store; ambientes/associações não entram em `NetworkMeasurement` nem no mapper CloudKit.

Comparação usa UUID do ambiente como identidade opaca em [NetworkBaselineBuilder / NetworkBaselineComparator](../../../aplicativo-ios/NetworkOptimization/Sources/NetworkOptimization.swift). Coordinator filtra resultados completos Wi-Fi, associados explicitamente e dos últimos 30 dias; exclui a medição atual da baseline. Decisão preservada: mínimo três referências, mediana, métricas ausentes como nil; comparar apenas a medição associada ao mesmo ambiente, sem retroatribuir histórico ou deduzir cômodo. O store e as condições de baseline foram inspecionados; aceites físicos/visuais de migração não foram executados.

Expectativa preservada de `documentacao/features/perfis-de-rede/README.md`: escolher/criar somente após resultado, ignorar sem alterar nada, nova medição sem seleção automática; Ajustes lista/renomeia/exclui, sem criação solta. Erro de store oferece nova tentativa; identificação desligada, SSID ausente, móvel, parcial ou falta de acesso impedem associação. Não transportar ambientes para NDS/Assist/widget, nem inferir AP por BSSID/MAC/localização. Esse limite substitui a identidade automática por fingerprint de SSID da proposta anterior de perfis; não migrar a associação antiga como se fosse um cômodo confirmado.

### Exportação e compartilhamento

O caminho encontrado exporta uma imagem de uma medição, não todo o banco. [ShareCardView / ShareCardRenderer.renderPNGData](../../../aplicativo-ios/LinkaApp/Sources/UI/ShareCardView.swift) renderiza um cartão 360×480 pontos em escala 3 por `ImageRenderer`, usando UIKit/AppKit conforme plataforma. Consome fatos de `NetworkMeasurement`; não tira screenshot bruto nem recalcula velocidade. O cartão exclui `networkIdentifier`/SSID/provedor e equivalentes IP/BSSID por desenho; mudanças futuras precisam preservar essa seleção explícita.

**Contrato de produto preservado do plano de paridade iOS/macOS:** `ShareCardView` é a fonte única do conteúdo e da privacidade; a intenção é disponibilizar compartilhamento apenas para resultado concluído atual ou histórico. Renderizar via `ImageRenderer`/PNG e apresentar no compartilhamento nativo, sem screenshot da janela. Falha de renderização não pode afirmar sucesso nem expor SSID, provedor, IP ou BSSID. Essa intenção não é uma declaração de que todos os gates estão implementados.

**Expectativa preservada: disponibilizar somente para resultado concluído atual ou histórico. Gate e validação em runtime pendentes; controle ainda não validado integralmente.**

| Caller / componente | Gate efetivamente observado |
|---|---|
| [MainView.toolbarShareButton](../../../aplicativo-ios/LinkaApp/Sources/UI/MainView.swift) | Só mostra botão quando `viewModel.uiPhase == .done`; passa `currentMeasurement` ao presenter |
| [MeasurementDetailView](../../../aplicativo-ios/LinkaApp/Sources/UI/MeasurementDetailView.swift) | Toolbar verifica apenas `if let measurement`; não testa `outcome == .complete` nesse gate |
| [HistoricalMeasurementDetailView](../../../aplicativo-ios/LinkaApp/Sources/UI/HistoricalMeasurementDetailView.swift) | Encaminha o registro recebido ao detalhe comum; o wrapper não adiciona validação de outcome |
| [MacMainView](../../../aplicativo-ios/LinkaApp/Sources/UI/MacMainView.swift) | `currentMeasurement` usa `activeMeasurement`: em `.done`, `latestFinishedMeasurement`; senão, `inspectedHistoricalMeasurement`. Instala o presenter com esse valor; o registro histórico não recebe teste de outcome nesse getter. Instalação do modifier não prova ação visível/disparada |
| `ShareMeasurementPresenter` / `MacShareMeasurementPresenter` | Exigem medição não nula, PNG e imagem decodificáveis; não validam outcome completo por conta própria |

No UIKit, falha limpa `isPresented` e não apresenta imagem; no AppKit, falha retorna e o `defer` limpa a apresentação. O Mac usa `NSSharingServicePicker`, o iPhone/iPad usa `UIActivityViewController`. Abrir/fechar o seletor não comprova que a pessoa concluiu o envio; os presenters examinados não registram confirmação de entrega ao destino.

[ShareSheet](../../../aplicativo-ios/LinkaApp/Sources/UI/ShareSheet.swift) envolve `UIActivityViewController` em UIKit; o mesmo arquivo do cartão inclui o gatilho macOS. [HistoricalMeasurementDetailView](../../../aplicativo-ios/LinkaApp/Sources/UI/HistoricalMeasurementDetailView.swift) encaminha a medição ao detalhe comum. Falha de renderização retorna `nil`; isso não é compartilhamento concluído. Destino externo é escolhido pela pessoa no mecanismo nativo.

Não foi encontrado exportador CSV/PDF nos fontes Swift consultados deste checkout. Não inferir a disponibilidade de outro branch/main ou de um plano. Exportação em lote, arquivo de intercâmbio e compatibilidade externa não estão comprovados. Conteúdo visual final e privacidade do arquivo gerado precisam de inspeção da build alvo antes de release.

### Aceites adicionais e validação pendente

| ID | Resultado esperado | Evidência estática / pendência |
|---|---|---|
| HIS-07 | Ambientes por UUID; nenhuma associação automática por SSID | Coordinator e [NetworkProfilesTests](../../../aplicativo-ios/NetworkProfiles/Tests/NetworkProfilesTests.swift) encontrados; sem execução |
| HIS-08 | Migração mantém nomes/IDs sem inventar assignments; exclusão não apaga medições | Store/repositório inspecionados; execução e UI pendentes |
| HIS-09 | Referência exclui resultado atual e só usa assignments elegíveis | Coordinator e [NetworkOptimizationTests](../../../aplicativo-ios/NetworkOptimization/Tests/NetworkOptimizationTests.swift); sem execução |
| HIS-10 | Cartão contém apenas fatos permitidos, sem identificadores sensíveis | Renderer/ShareCardView lidos; arquivo real e mecanismos de compartilhamento não exercitados |
| HIS-11 | Somente resultado concluído atual/histórico é elegível, conforme intenção preservada | MainView tem gate `.done`; detalhe/presenters aceitam medição não nula sem validar outcome; não declarar cobertura integral |

Responsáveis: Camillo/Pedro para contrato/migração/baseline e Tito para jornada. Evento: antes da próxima release que altere ambientes ou compartilhamento. Fechamento: testes por versão de store, reassign/remoção, ausência de SSID no JSON novo, fluxo iPhone/iPad/Mac, arquivo PNG inspecionado e nenhum falso sucesso. Comandos futuros na raiz: `swift test --package-path aplicativo-ios/NetworkProfiles` e `swift test --package-path aplicativo-ios/NetworkOptimization`; não executados nesta tarefa documental.

Pendência específica HIS-11: Camillo/Pedro devem reconciliar os gates de detalhe/presenters com a intenção de resultado completo; Tito valida entrada atual/histórica, registro parcial importado, renderização falha e cancelamento do seletor. Evento: próxima alteração de compartilhamento, antes de seu aceite. Fechamento: regra decidida, gates/testes coerentes em ambas as plataformas e evidência de que nenhum falso sucesso ou identificador sensível aparece. Esta revisão documental não corrige o código.

### Aceites do histórico principal

| ID | Regra esperada | Evidência estática disponível |
|---|---|---|
| HIS-01 | Upsert por ID é idempotente | [MeasurementHistoryTests](../../../aplicativo-ios/MeasurementHistory/Tests/MeasurementHistoryTests.swift), `testSaveIsIdempotentByMeasurementID` |
| HIS-02 | Filtro, ordenação, paginação e retenção são determinísticos | Mesmo arquivo: `testQueryFiltersSortsAndPaginates`, `testRetentionKeepsNewestEntries` |
| HIS-03 | Corrupção/versão desconhecida falham sem apagar automaticamente | Mesmo arquivo: `testCorruptedFileFailsClosed`, `testUnsupportedStoreVersionFailsClosed`; leitura de `loadIfNeeded` |
| HIS-04 | Save/exclusão persistem entre instâncias | Mesmo arquivo: `testFileRepositoryPersistsAcrossInstances`, `testFileRepositoryPersistsDeletion` |
| HIS-05 | Não apresentar uma medição como gráfico de tendência | Leitura de `HistoryVisualizationState.resolve` e condição `.trend` em `HistoryView` |
| HIS-06 | Falha de sync não substitui fonte local nem ressuscita exclusão pendente | Leitura do decorator e [CloudKitMeasurementSyncTests](../../../aplicativo-ios/MeasurementHistoryCloudKit/Tests/CloudKitMeasurementSyncTests.swift); execução pendente |

Data/ambiente da evidência: inspeção de arquivos locais em 2026-10-04, WIP acima. Nenhum teste, build, simulador, CloudKit real, dispositivo ou release executado. Para futura validação na raiz, usar `swift test --package-path aplicativo-ios/MeasurementHistory` e `swift test --package-path aplicativo-ios/MeasurementHistoryCloudKit` com toolchain Apple; testes com dependência remota devem usar stores injetados e não provar provisionamento real.

## Mudanças em andamento e pendências

O trecho Home/Histórico #236 em `.agents/plano.md` descreve divulgação progressiva e 0/1/2 medições; há correspondência estática na tela, mas não aceite visual. `PLANO_HISTORICO_MEDICOES.md` descrevia uma fundação isolada e depois integração; este README substitui essa descrição de estado, sem importar a alegação antiga de gate cumprido ou de CloudKit apenas aguardando provisionamento.

| Lacuna | Responsável / evento | Critério de fechamento |
|---|---|---|
| Campos locais não sincronizados | Camillo, próxima mudança no contrato CloudKit | Matriz campo a campo decidida, testes de round-trip e de privacidade |
| UI e exclusão offline/múltiplos aparelhos não exercitadas | Tito, antes da próxima release de histórico | Evidência na build alvo em iPhone/Mac, inclusive offline e tombstones |
| Falha de escrita altera estado em memória antes de `persist` lançar | Camillo + Pedro, próxima revisão de robustez | Teste de disco indisponível e decisão de rollback/semântica de erro |
| Antiga alegação de provisionamento não confirmada nesta base | Codex, antes de prometer sync público | Evidência do container/ambiente e dois aparelhos assinados |

## Origem documental

As fontes anteriores foram substituídas conforme o [registro de migração](../../MIGRACAO.md). Expectativas não entregues e divergências permanecem neste documento; remoção de plano não significa aceite funcional concluído.
