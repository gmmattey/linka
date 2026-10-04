# Desenvolvimento e publicação locais

Estado: fluxo local implementado e controles revisados; sem release executada nesta rodada.
Responsável: Codex principal; executor da candidata registra a evidência.
Última revisão: 2026-10-04 — automação local, versionamento e inventário de simuladores.
Base: WIP sobre `9eb1a094`; não é evidência de candidata publicada.
Referências: [governança](../GOVERNANCA_DOCUMENTAL.md), [Fastlane](../../fastlane/Fastfile), [preparação de versão](../../.agents/scripts/release.sh).

## Um fluxo, executado no Mac

Decisão do Luiz: GitHub para código e PRs, sem CI do GitHub. Actions foi desativado no repositório remoto `gmmattey/linka` e os dois workflows foram removidos do checkout. A consulta de 2026-10-04 confirmou `enabled: false`, nenhuma execução em andamento, nenhuma proteção clássica de main e nenhum ruleset listado. Não reativar Actions nem introduzir outro serviço de CI sem nova decisão.

Usar este guia para o procedimento, `RELEASE_NOTES.md` para mudanças da candidata e a evidência gerada para o resultado. Não criar um script ou checklist por tentativa. A automação existente fica em `fastlane/Fastfile` e `.agents/scripts/release.sh`.

## Preparar o ambiente

A raiz Git é `ios/`. Usar macOS, Xcode/SDK compatíveis, ferramentas de linha de comando, XcodeGen e Python 3 com PyYAML (usado pelo script de preparação). O [Gemfile.lock](../../Gemfile.lock) fixa as dependências do Fastlane. A instalação local evita disputar permissões com o Ruby global:

```sh
export BUNDLE_PATH=build/bundle
export BUNDLE_APP_CONFIG=build/bundle-config
bundle install
```

Repetir as variáveis na sessão que executará Fastlane. `build/` é ignorado pelo Git. Não guardar credenciais nessa documentação nem em arquivos versionados.

## Validar sem enviar

Na raiz Git, informar o UDID existente escolhido e executar:

```sh
export LINKA_SIMULATOR_UDID='UDID_EXISTENTE_ESCOLHIDO'
bundle exec fastlane ios validate
```

A lane não acessa a Apple para publicação. Valida os onze pacotes do fluxo anterior: NetworkCore, MeasurementHistory, NetworkInsights, NetworkAssist, NetworkDiagnostics, NetworkConnectivityTriage, LinkaEntitlements, LinkaAppIntents, LinkaModules, LinkaEngine e LinkaWidgetShared. Depois confere o projeto e executa testes iOS em série e build Release para simulador. A validação não deve regenerar PBX, schemes ou Info.plist sobre WIP; mudanças de especificação precisam ser reconciliadas antes da candidata. A lane recusa `project.yml` alterado em relação a HEAD; depois de revisar a preparação/geração, registrar a mudança em commit antes da validação completa. WIP de código pode ser validado, mas não enviado pela lane beta. Outros pacotes, macOS, dispositivo físico e qualidade visual não estão automaticamente cobertos.

Para uma mudança isolada, `swift test --package-path aplicativo-ios/<pacote>` executa o pacote afetado; não substitui a validação completa da candidata. No site, executar `npm run lint` e `npm run build` em `aplicacao-web/`; não há `npm test` canônico.

### Simulador: reutilizar antes de criar

O orquestrador escolhe um destino existente por tarefa e informa o UDID aos agentes. Apenas um executor usa esse destino por vez. Não criar um simulador por agente, branch, tentativa ou captura. Reutilizar um iPhone disponível compatível; usar iPad existente quando a mudança exigir esse layout. macOS é validado no Mac, não em um “simulador de Mac”.

Antes de executar, consultar o ambiente instalado:

```sh
xcode-select -p
xcrun simctl list devices available
xcrun simctl list runtimes
```

Selecionar o UDID explicitamente, sem depender apenas do nome ou do alias `booted`. Se o destino estiver em uso por outra tarefa, coordenar o uso; não encerrar a sessão alheia. Ausência de runtime compatível é um requisito faltante, não motivo para criar vários dispositivos. Criar um novo somente quando não existir destino adequado e houver necessidade concreta registrada.

Para executar testes locais, a partir de `aplicativo-ios/`, substituir o marcador pelo UDID existente escolhido:

```sh
LINKA_SIMULATOR_UDID='UDID_EXISTENTE_ESCOLHIDO'
xcodebuild test -project LinkaApp.xcodeproj -scheme LinkaApp \
  -destination "platform=iOS Simulator,id=$LINKA_SIMULATOR_UDID" \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  -derivedDataPath build/DerivedData -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

Usar o mesmo destino e `build/DerivedData` para build/teste da mesma worktree, sequencialmente. Worktrees distintas mantêm caches separados; não compartilhar a pasta entre processos concorrentes. Não criar uma nova pasta com timestamp a cada tentativa nem apagar caches como primeira resposta a uma falha. Para apenas compilar, preferir `xcodebuild build` com `-destination 'generic/platform=iOS Simulator'`, sem iniciar um dispositivo; isso não valida navegação ou aparência.

A execução serial reduz a multiplicação de runners de teste; não comprova ausência absoluta de clones internos do Xcode. Não executar `simctl delete all`, `erase all` ou `shutdown all`. Limpeza fica limitada a um dispositivo comprovadamente descartável e autorizado; dados de outros projetos devem permanecer.

O inventário local de 2026-10-04 tem nove dispositivos disponíveis iOS 26.5, todos desligados e sem nomes duplicados. Não existe iPhone 17 simples nessa máquina. O destino é escolhido no inventário atual, não por nome fixo herdado de CI. Dezessete diretórios globais LinkaApp de DerivedData foram encontrados, principalmente de worktrees; não são simuladores e não foram apagados.

`xcodegen generate` altera o projeto gerado. Preservar WIP e conferir o diff; não usar geração como limpeza de simulador.

## Preparar uma candidata

1. Delimitar a mudança, validar e atualizar documentação/`RELEASE_NOTES.md`.
2. Na raiz Git, executar `.agents/scripts/release.sh patch`, `minor`, `major` ou `X.Y.Z` somente quando preparar uma nova candidata. Não repetir o bump para promover a mesma build.
3. Revisar o diff e integrar a PR conforme autorização e governança. O script não faz commit, merge, tag, upload ou publicação.
4. Para beta, usar main limpa e correspondente à referência remota. Não esconder WIP com limpeza destrutiva nem enviá-lo como se fosse o commit identificado.

Na integração sobre `origin/main` 8507ce71, iOS/widget e Mac preservam 1.1.5 (54), sem incremento. A revisão inicial usou 52/49; esses números não foram transplantados sobre a main mais recente. O script prepara iOS e preserva a versão Mac; uma candidata Mac requer escopo próprio. O número local não comprova disponibilidade no catálogo Apple.

## TestFlight, somente com autorização

A lane `beta` exige autorização explícita, main limpa e SHA confirmado contra origin/main. Executa a validação completa sem opção de pular. Antes de upload, confere app e widget no archive e IPA contra a identidade da candidata. Nenhuma tag ou push acontece automaticamente.

Configurar no ambiente local `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT` (p8 em Base64) e `APPLE_TEAM_ID`, sem incluir valores em comandos compartilhados ou logs. A chave temporária fica privada e é removida ao terminar, inclusive em falhas.

Depois de autorização para a candidata específica:

```sh
bundle exec fastlane ios beta authorized:true
```

O UDID e as variáveis do Bundler permanecem os mesmos da validação. O parâmetro expressa a autorização já recebida; sua existência não autoriza o agente a publicar por conta própria.

A evidência de cada tentativa é preservada em `build/releases/attempt-NNNN/testflight-evidence.json`, junto ao archive/export dessa tentativa. Cache de compilação é reutilizado; artefatos de candidatas diferentes não se sobrescrevem. A evidência registra identidade, SHA, validação, hash da IPA e etapa/estado de envio. Interrupção após início do upload deve permanecer incerta, nunca sucesso presumido. Conferir o estado Apple antes de repetir; não incrementar build automaticamente para contornar uma falha de registro.

## App Review e publicação

Preparação local → PR e validação → merge autorizado → TestFlight autorizado → confirmar distribuição pretendida → App Review autorizada → confirmar publicação. Uma etapa não autoriza a seguinte; aproveitar autorização já dada quando cobrir a ação.

A lane beta é iOS/TestFlight. Não existe lane de App Review, promoção pública ou distribuição macOS neste fluxo. Confirmar plataforma, build, metadata, privacidade, oferta e estado real antes dessas operações. TestFlight processado não comprova grupo de testes, aprovação de review ou disponibilidade pública.

## Evidência e limites

| Evidência | Alcance |
|---|---|
| Inspeção/sintaxe e testes com ferramentas simuladas | Controles locais; não valida assinatura ou envio real |
| Pacotes/build/testes locais | Ambiente, SHA/WIP e destinos efetivamente executados |
| Jornada no simulador | Estado observado naquele simulador/build |
| Dispositivo físico | Cenário e hardware registrados |
| Processamento Apple | Build específica recebida/processada; não publicação |
| App Store | Estado confirmado na loja, distinto de tag ou TestFlight |

Materiais em [store/app-store](../../store/app-store/README.md) são locais; atualmente não há capturas novas prontas para publicação. Conferir URLs ao vivo e campos da loja antes de submissão.

## Validação desta alteração

Dependências instaladas localmente e Fastlane 2.240.1 carregado; `bundle check`, listagem das lanes, sintaxe Ruby/Bash/Python, plist do projeto, links e `git diff --check` passaram. O harness do Fastlane executou 16 cenários simulados de beta, além de log de diagnóstico e contenção por UDID, sem comandos externos de release. O script teve 15 fixtures de versionamento repetidas no arquivo final e seis casos de concorrência; XcodeGen real foi executado somente em cópia temporária. Nenhum desses resultados é build/teste do app, assinatura ou envio real.

Tito revisou os controles finais sem bloqueio ou ajuste adicional. Locks coordenam as ferramentas que os respeitam; comparação de bytes e troca atômica não são uma transação contra qualquer editor externo, SIGKILL ou queda da máquina. Se houver interrupção, inspecionar o diff e a evidência antes de retomar.

## Pendências da próxima candidata

| Item | Responsável | Evento | Fechamento |
|---|---|---|---|
| Rodar validação real e jornadas nas plataformas afetadas | Executor/Tito | Próxima candidata | Evidências com revisão, versão/build, destino e resultado |
| Confirmar assinatura, catálogo e processamento Apple | Executor | Próximo TestFlight autorizado | Identidade/hash e estado real conferidos |
| Conferir metadata, URLs, privacidade e novas capturas | Íris/orquestrador | Antes de submissão | Materiais confrontados com candidata e portal |
