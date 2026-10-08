# Operação

Responsável: Marco/Codex e executor da candidata. Revisão: 2026-10-04, base main `39269c7a`. Procedimento local; não comprova release ou estado atual da Apple.

## Ambiente e validação

GitHub guarda código/PRs. Actions foi desativado por decisão do Luiz, e os workflows foram removidos. Não reativar CI hospedada sem nova decisão. Usar o [Fastlane](../fastlane/Fastfile) e o [script de preparação](../.agents/scripts/release.sh) existentes, sem wrappers ou checklists novos por tentativa.

A raiz Git é `ios/` no workspace original. Requisitos: Mac, Xcode/SDK compatíveis, XcodeGen, Ruby/Bundler e Python 3 com PyYAML. [Gemfile.lock](../Gemfile.lock) fixa as dependências:

```sh
export BUNDLE_PATH=build/bundle
export BUNDLE_APP_CONFIG=build/bundle-config
bundle install
export LINKA_SIMULATOR_UDID='UDID_EXISTENTE_ESCOLHIDO'
bundle exec fastlane ios validate
```

`validate` executa os onze pacotes listados em `LinkaLocalRelease::PACKAGES`, testes iOS em série e build Release de simulador, sem upload. Usa o projeto existente: não regenera PBX/schemes/Info.plist sobre WIP. Recusa `project.yml` alterado contra HEAD e confere identidade efetiva de app/widget; revisar e registrar mudanças do projeto antes da validação completa. WIP de código pode ser testado, mas não enviado por beta.

Para alteração isolada: `swift test --package-path aplicativo-ios/<pacote>`. Não executar `swift test` na raiz nem supor cobertura de outros pacotes, Mac, dispositivo físico ou jornada visual. Para o site, em `aplicacao-web/`: `npm run lint` e `npm run build`; não há `npm test` canônico. Logs de validação ficam em `build/validation/`.

## Simuladores e cache

```sh
xcode-select -p
xcrun simctl list devices available
xcrun simctl list runtimes
```

Escolher um dispositivo existente e compatível por UDID, um executor por vez. Não criar simuladores por agente, branch, captura ou falha. Usar iPad quando o layout exigir; validar Mac no Mac. Não depender de nome fixo ou de `booted` ambíguo. Se outro trabalho usa o destino, coordenar; não desligá-lo.

Fastlane trava o UDID entre worktrees, desativa testes paralelos e limita a um destino. Reutiliza `aplicativo-ios/build/DerivedData` por worktree, com execuções seriais. Para apenas compilar, destino `generic/platform=iOS Simulator` dispensa iniciar dispositivo. Serialização reduz runners, mas não garante zero clone interno do Xcode.

Não apagar caches como primeira reação, criar pastas com timestamp a cada teste nem usar `simctl delete all`, `erase all` ou `shutdown all`. Só criar um destino se não houver compatível e houver necessidade registrada. Limpeza de dispositivo exige identificação e autorização; preservar dados de terceiros. O inventário de 04/10 encontrou nove simuladores desligados, sem nomes duplicados; os 17 diretórios LinkaApp de DerivedData eram caches, principalmente de worktrees, não simuladores.

## Preparação, TestFlight e publicação

1. Delimitar a mudança, testar e atualizar as seções afetadas e [RELEASE_NOTES](../RELEASE_NOTES.md).
2. Preparar nova candidata com `.agents/scripts/release.sh patch`, `minor`, `major` ou `X.Y.Z`. Ele incrementa iOS, preserva Mac, gera em cópia isolada e aplica só versão/build, sem substituir customizações de projeto. Não repetir bump para promover a mesma build.
3. Conferir diff, commit/PR e merge dentro da autorização recebida. Beta exige `main` limpa e igual a `origin/main`; não ocultar WIP com limpeza.
4. Depois de autorização para TestFlight daquela candidata, executar `bundle exec fastlane ios beta authorized:true`, mantendo UDID e variáveis do Bundler da mesma sessão.

A candidata local para a beta interna de Minha Rede é iOS/widget 1.1.5 (56); Mac permanece em 1.1.5 (54). Preparação local não prova archive, envio ou distribuição na Apple.

### Minha Rede — beta interna pelo Xcode

Usar o scheme compartilhado `LinkaApp-InternalBeta` para iPhone/iPad ou `LinkaApp_macOS-InternalBeta` para a preparação Mac. Ambos arquivam com `InternalBeta`, configuração do tipo Release com `LINKA_INTERNAL_BETA`; não usam `DEBUG`. Os schemes públicos `LinkaApp` e `LinkaApp_macOS` continuam arquivando em `Release`, com Minha Rede e endpoint de pesquisa desativados. A beta preserva as configurações de assinatura e publicidade de Release.

A composição central `InventoryBuildConfiguration` ativa a área local na beta interna. O endpoint distribuído deve ser uma constante HTTPS do Worker verificado, com host e caminho permitidos explicitamente; não lê variável de ambiente nem preferências na beta. A candidata fixa `https://linka-device-spec-lookup.buildealabs.workers.dev/v1/device-specs/lookup`, provisionado e verificado com o Worker desativado (HTTP 200, `unavailable`). A chave do provedor e a ativação remota continuam pendentes; o cadastro manual funciona e a configuração do endpoint não comprova pesquisa com IA. Debug mantém endpoint por variável de processo apenas para desenvolvimento. Nenhuma chave de provedor vai no aplicativo.

Após revisão e autorização da candidata, no Xcode selecionar o scheme interno, destino genérico iOS e **Product → Archive**. Conferir versão/build do app e widget, configuração `InternalBeta`, assinatura e endpoint antes de distribuir. No Organizer escolher **TestFlight Internal Only**; export equivalente exige `testFlightInternalTestingOnly=true` com `method=app-store-connect`. Essa restrição impede distribuição externa/App Store; o nome do scheme sozinho não oferece essa proteção. Não usar o fluxo público/automático de upload para essa candidata. Preparar a versão Mac não autoriza seu envio.

O usuário autorizou IA na beta sem teto monetário global nesta etapa; permanecem limites técnicos por consulta no backend. Ativação do Worker e endpoint verificado, consultas reais, archive, upload e distribuição continuam evidências distintas. Não afirmar pesquisa funcionando antes de verificar o serviço e o cliente. Esta configuração não publica nem ativa Minha Rede no Release público.

Configurar localmente `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT` (p8 Base64) e `APPLE_TEAM_ID`. Não colocar valores na linha de comando compartilhada, logs ou Git. A chave temporária usa permissões restritas e limpeza ao terminar. Beta valida obrigatoriamente, consulta build usada, confere app/widget no archive e IPA e só então envia. Não cria tag nem faz push automático.

Cada envio preserva `build/releases/attempt-NNNN/testflight-evidence.json`, archive/export, SHA e hash da IPA. O cache é reutilizado; artefatos diferentes não se sobrescrevem. Se interromper depois do início do upload, o estado permanece incerto: consultar Apple antes de repetir, sem bump automático para esconder falha.

O script e Fastlane compartilham `build/.release.lock`; preparação usa substituição atômica e rollback condicionado à própria escrita. Isso coordena ferramentas aderentes, não garante transação contra qualquer editor, SIGKILL ou queda. Inspecionar diff/evidência antes de retomar após interrupção.

Beta cobre iOS/TestFlight. App Review, publicação e release Mac são operações separadas, não lanes implementadas aqui. Uma autorização não se estende automaticamente à seguinte; usar a autorização existente quando seu escopo cobrir a ação. Build processada não prova distribuição a grupo, aprovação ou publicação.

## Marca e capturas

[brand/manifest.json](../brand/manifest.json) mapeia nove exportações e seus SHA256 para [Assets.xcassets](../aplicativo-ios/LinkaApp/Sources/Assets.xcassets/). Atualizar a fonte e renovar as exportações/manifesto juntos. Usar Linka claro/escuro em `brand/linka/`, Plus em `brand/linka-plus/`, Assist em `brand/assist/` e ícones em `brand/icons/`. Não redesenhar a marca, trocar por texto ou adicionar efeitos. O Plus preserva `+`, proporção e transparência; cores claro azul #102245/laranja #E0701F, escuro branco/laranja #FF9552.

O site tem wordmark inline e ícones próprios; não presumir equivalência de SVGs. Seu gerador de ícones também sobrescreve assets do app: não executá-lo para “organizar”.

Não há conjunto de capturas atual aprovado para loja. As antigas foram retiradas. Três imagens em [assets do site](../aplicacao-web/src/assets/screenshots/) continuam usadas: Home com CTA antigo, medição/fases antigas e resultado individual apresentado como evolução. Não reutilizar para loja; substituir em revisão visual do site por capturas identificadas.

O [teste de captura](../store/app-store/screenshots/AppStoreScreenshotsUITests.swift) usa screenshots reais, mas esperas e botão antigo opcional podem omitir telas sem falhar. Antes de enviar, exigir os estados necessários e conferir candidata, dispositivo/sistema, idioma, origem dos resultados e privacidade. Não fabricar números ou editar preço antigo para simular captura atual. Fonte, projeto e UI test não são prova de execução.

## Ficha pt-BR — base local, não enviada

**Nome:** Linka: Wi-Fi e Internet

**Subtítulo:** Meça e acompanhe sua conexão

**Promocional:** Meça download, upload e ping. Consulte o histórico e compare sua conexão em diferentes locais e horários.

**Descrição:** O Linka mede sua conexão no iPhone, iPad e Mac. Inicie um teste e consulte download, upload, ping e outros dados disponíveis. Guarde seus resultados no histórico e compare medições feitas em diferentes locais e horários. Veja detalhes de Wi-Fi quando disponíveis e acesse o painel do roteador da rede atual quando ele puder ser localizado e estiver acessível. Recursos adicionais do Linka Plus incluem Assist, padrões no histórico e detalhes avançados de Wi-Fi, conforme a plataforma, as permissões e a configuração. Os dados disponíveis variam conforme a conexão e o dispositivo. Uma medição descreve aquele momento. Repita o teste para acompanhar mudanças.

**Palavras-chave:** velocidade,conexao,internet,wifi,ping,jitter,latencia,historico,roteador,download,upload

URLs declaradas: [marketing](https://linka-speedtest.web.app), [privacidade](https://linka-speedtest.web.app/privacidade), [suporte](https://linka-speedtest.web.app/suporte), [termos/EULA](https://linka-speedtest.web.app/termos). Contato: suporte@linka.app. Conferir disponibilidade HTTP, limites de campos e conteúdo real no portal antes de submissão; não foram verificados nesta reorganização.

Notas de review: medição por ação da pessoa, sem conta Linka obrigatória; acesso adicional depende de entitlement. iOS/iPad usa Atalhos configurado para Wi-Fi avançado; Mac depende de APIs/permissões. Informar versão/build, destinos, compra/restauração, configuração reproduzível e campanha aplicável. Não declarar preço fixo, causa raiz ou resposta infalível. Promoção é elegível a anúncios; compra paga válida não. O rascunho específico da build 53 permanece no [histórico Git](https://github.com/gmmattey/linka/blob/39269c7a9d2ed461fb944de09d5b27c34d3d1d4d/store/app-store/review-notes-1.1.5-build53.md), não é nota pronta para qualquer candidata.

Antes de enviar publicidade: verificar ausência do pedido ATT e gravar consentimento UMP na candidata física e contexto correto de conta/permissão; conferir App Privacy/SDK, ausência de mensagem remota duplicada e política publicada. A retirada do ATT não dispensa verificar os tratamentos efetivos dos SDKs; inventário/consentimento não garantem anúncio. Não inferir oferta ou preço do antigo paywall sem build/catálogo identificados.

## Validação conhecida e próxima candidata

A PR [#274](https://github.com/gmmattey/linka/pull/274) registrou testes simulados dos controles (16 cenários beta, 15 de versão e seis de concorrência), sintaxe, links, plist e lint/build do site. Isso não foi build/teste do app, assinatura ou envio Apple. A reorganização documental também não acrescenta evidência runtime.

| Pendente | Responsável | Quando e condição de fechamento |
|---|---|---|
| Testes/jornadas da candidata | Executor/Tito | Próxima candidata: revisão, build, destinos e resultados registrados, incluindo físico/visual conforme escopo |
| Assinatura, catálogo e processamento | Executor | TestFlight autorizado: conferir identidade/hash e estado real na Apple |
| Texto, URLs, privacidade e capturas | Íris/Marco | Antes de submissão: materiais confrontados com candidata/portal; atualizar site quando afetado |

Referências: [Produto](PRODUTO.md), [Arquitetura](ARQUITETURA.md), [Governança](GOVERNANCA.md).

## Minha Rede — integração gradual e condição de lançamento

Decisão de 08/10/2026: V1 pública completa e Free para iPhone/iPad/Mac, incluindo pesquisa com IA. Entregas internas podem avançar separadamente; flags/endpoint desligados mantêm o recorte em revisão. Código local e testes simulados não comprovam piloto, fonte real, coleta física, paridade visual ou publicação.

Implementação e evidências: [core #289](https://github.com/gmmattey/linka/pull/289), [jornada Apple #290](https://github.com/gmmattey/linka/pull/290), [backend #30](https://github.com/gmmattey/netscope-api/pull/30) e [consolidação documental #277](https://github.com/gmmattey/linka/pull/277). Consultar essas PRs para os commits, revisões e estado de integração. Modelo/Household, CRUD, OCR e clientes compõem a entrega interna; entradas públicas e backend permanecem desabilitados. Merge de código não comprova piloto, provisionamento, deploy ou publicação. Os gates abaixo continuam obrigatórios antes do lançamento.

Ordem: preservar refs/stashes/WIP → integrar correções independentes → core/persistência/CRUD → OCR → pesquisa/ficha → QA conjunta. PR276 de ATT e PR288 de teste CTA são frentes separadas; Netscope L06 não é dependência automática do lookup. Nenhuma etapa autoriza restaurar snapshot antigo sobre main ou misturar versões/configurações alheias.

| Gate | Responsável e condição de fechamento |
|---|---|
| Integridade local | Camillo/Tito: reinício/offline, conflito/revisão, corrupção/schema futuro, falha de escrita, renomear/excluir Ambiente e falha parcial, duas instâncias e notificações, sem alterar assignments/Histórico |
| Editor/OCR | Pedro/Tito: descarte, permissões, etiqueta ambígua/credenciais mescladas, resposta tardia após troca/cancelamento/exclusão; confirmar ausência de foto/OCR bruto em armazenamento/payload |
| Contrato/fontes | Camillo/Íris/Tito: fixtures app/backend, unidades/estruturas, modelos inexistentes, variantes/conflitos, fontes efetivamente consultadas e confiáveis, instruções adversariais, revisão antes de persistir; não aceitar eco de identidade como prova |
| Piloto de custo | Luiz/operador: aprovar provider/modelo, limite de ferramentas/tokens e reserva conservadora por pior caso, teto global e duração do piloto; testar reserva atômica pré-dispatch, concorrência/cache, timeout/incerteza e kill switch antes de tráfego pago |
| Plataforma/QA | Tito/Íris: candidata identificada em iPhone/iPad/Mac, dispositivo físico para câmera/permissões e serviço real, VoiceOver/Dynamic Type/teclado, CRUD/offline/fontes, regressão medição/Histórico/Ambientes/Assist/DNS/Otimização/Ferramentas |
| Ativação/publicação | Luiz/executor: autorização explícita para recursos/deploy/tráfego pago e, separadamente, distribuição/loja; disclosures, App Privacy, política/site e materiais confrontados com comportamento real |

Não colocar chave no app, logs, fixtures ou PR. Definir bindings/migrations localmente não provisiona nem autoriza deploy. Serviço deve permanecer indisponível quando desligado, sem política válida, sem fonte suficiente ou com reserva/custo incerto. Custo máximo precisa de evidência do modelo e ferramentas aprovados, não apenas variável de ambiente afirmando aprovação. Definir retenção/cache/expurgo e reconciliar ledger ao mudar política. Quando pesquisa falha, manter cadastro/ficha anterior e permitir nova tentativa explícita.

Fechamento V1 exige todos os aceites de [#279–#283](https://github.com/gmmattey/linka/issues/278) e decisão de lançamento registrada. V2 [#284–#287](https://github.com/gmmattey/linka/issues/284) só executa após validação V1; planos e vínculos ainda são contratos futuros, sem prometer sincronização ou recomendações. Material de loja só depois de homologar o comportamento correspondente.
