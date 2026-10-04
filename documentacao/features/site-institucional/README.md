# Site institucional

Estado do documento: vigente para o código local; publicação e conformidade pública não verificadas.
Responsável: Codex principal; Íris orienta conteúdo e jornada.
Última revisão: 2026-10-04 — roteamento React, páginas, navegação, configuração de CTA e scripts.
Base conferida: checkout WIP `feat/macos-visual-direction-and-service-status`, HEAD `9eb1a094` mais alterações locais, incluindo InfoScreen. Não representa produção/main.
Referências: [produto](../../PRODUTO.md), [design](../../design/README.md), [governança](../../../AGENTS.md).
Termos de busca: site, landing, suporte, privacidade, termos, Como medimos, React, Vite, App Store.

## Propósito e limites

Apresentar o Linka, explicar o que mede, oferecer suporte/informações públicas e encaminhar para o app Apple. A aplicação Web não executa o motor de speed test. Acesso em navegador de outras plataformas não significa versão Android/Web do produto.

O código atual promove principalmente iPhone. Essa escolha de comunicação não comprova nem nega distribuição para iPad/Mac. O conteúdo público precisa ser confrontado com a versão candidata antes de publicação; texto de marketing ou privacidade não é prova de comportamento do app.

## Fluxo e navegação real

[main.tsx](../../../aplicacao-web/src/main.tsx) monta React em `StrictMode` e importa o CSS. [App.tsx](../../../aplicacao-web/src/App.tsx), símbolo `App`, lê `window.location.pathname`, remove uma barra final e seleciona a página. Não há roteador externo nessa seleção; links normais navegam pelas URLs.

| URL / entrada | Comportamento implementado | Fonte |
|---|---|---|
| `/` | Landing com apresentação, screenshots, etapas Meça/Entenda/Acompanhe, Plus e CTA | [LandingScreen](../../../aplicacao-web/src/screens/LandingScreen.tsx) |
| `/sobre` | Apresentação e foco do app | [InfoScreen, pages](../../../aplicacao-web/src/screens/InfoScreen.tsx) |
| `/como-medimos` | Descrição pública das fases/metodologia | [InfoScreen](../../../aplicacao-web/src/screens/InfoScreen.tsx) |
| `/privacidade` | Dados de medição, Wi-Fi, histórico/iCloud, Assist, anúncios, compras e contato | [InfoScreen](../../../aplicacao-web/src/screens/InfoScreen.tsx) |
| `/termos` | Natureza informativa, assinatura e link para EULA Apple | [InfoScreen](../../../aplicacao-web/src/screens/InfoScreen.tsx) |
| `/suporte` | Orientação para informar aparelho/sistema/versão/problema e ação mailto | [InfoScreen](../../../aplicacao-web/src/screens/InfoScreen.tsx) |
| `/casawifi` e `/casawifi/privacidade` | Ambos selecionam a política de WiFi Casa no roteamento React | [App](../../../aplicacao-web/src/App.tsx) |
| Qualquer outro caminho no React | Página não encontrada, com retorno ao início | [NotFoundScreen](../../../aplicacao-web/src/screens/NotFoundScreen.tsx) |

[Header](../../../aplicacao-web/src/ui/components/layout/Header.tsx) oferece Home pela marca, Como medimos, Privacidade e Suporte; sinaliza a página ativa por `aria-current`. [Footer](../../../aplicacao-web/src/ui/components/layout/Footer.tsx) acrescenta Sobre e Termos, mais marca e ano corrente. O rodapé não oferece navegação principal para WiFi Casa.

Existem também documentos estáticos sob [public](../../../aplicacao-web/public/), inclusive políticas de WiFi Casa e LagCheck. A precedência entre arquivo estático, fallback do host e React não foi validada: a tabela descreve o código React, não promete resposta HTTP dessas URLs em produção.

## Configuração, dados e comportamento

`LandingScreen` lê `VITE_LINKA_APP_STORE_URL`. Com valor, `AppStoreCallToAction` é um link; sem valor, vira `span` com rótulo acessível de disponibilidade após aprovação. Portanto não presumir botão funcional sem configuração. `VITE_LINKA_PLUS_ANNUAL_PRICE` define texto de preço; há fallback literal no código, que não deve ser tratado como preço vigente da loja.

Screenshots são importadas de [assets locais do site](../../../aplicacao-web/src/assets/screenshots/). Foram movidas sem alterar os bytes na organização de marca/loja de 2026-10-04; não pertencem mais ao conjunto de submissão da loja. São material ilustrativo armazenado no repositório, não uma medição executada pelo navegador nem prova de que a build atual tem aquela aparência.

Landing e InfoScreen atualizam título e meta description em `useEffect`; NotFoundScreen atualiza título. SEO renderizado inicialmente pelo host/crawler não foi avaliado. InfoScreen usa conteúdo local tipado (`InfoPage`/`pages`), com seções e ações opcionais. Não há chamada ao motor, histórico do app ou backend de diagnóstico nesses componentes lidos. Isso não equivale a auditoria de todas as dependências ou do tráfego do site.

Estados: página informativa pronta; CTA habilitado/desabilitado pela configuração; rota desconhecida com recuperação Home. Essas páginas não têm estado de resultado parcial de medição, cancelamento de speed test ou permissão Wi-Fi — não medem. Carregamento/offline e falha de assets dependem do navegador/host, sem experiência específica comprovada nesta leitura.

## Estilo, acessibilidade e dependências

O site usa tokens em [styles/tokens](../../../aplicacao-web/src/styles/tokens/) e estilos locais, com layouts responsivos em LandingScreen. Cabeçalhos semânticos, `main`, `nav` rotulada, `aria-current`, textos alternativos e ações com altura mínima aparecem no código. Não houve teste de teclado, leitor de tela, contraste, zoom ou movimento reduzido. Animações `linkaRise` existem em InfoScreen/NotFoundScreen: a cobertura efetiva de Reduzir Movimento deve ser conferida no CSS e navegador antes de alegar suporte integral.

Dependências de execução declaradas: React e React DOM; build com TypeScript/Vite e lint com ESLint em [package.json](../../../aplicacao-web/package.json). O site compartilha identidade, mas não importa a UI Swift. Os links externos do app são objeto de asserções em [SettingsProductionStateTests.testExternalLinksUseCanonicalOriginAndSpecificPaths](../../../aplicativo-ios/LinkaApp/Tests/SettingsProductionStateTests.swift); o teste usa a origem `linka-speedtest.web.app`. Isso é expectativa de código, não verificação de domínio ativo.

## Operação e limites de validação

### URLs esperadas para loja e app

Fonte de implementação: [LinkaExternalLinks](../../../aplicativo-ios/LinkaApp/Sources/Support/LinkaExternalLinks.swift). Esta tabela absorve `documentacao/features/site-institucional/README.md` e registra os campos esperados, não o conteúdo atual do App Store Connect.

| Campo / finalidade | Valor de referência |
|---|---|
| Marketing URL / website | `https://linka-speedtest.web.app` |
| Privacy Policy URL | `https://linka-speedtest.web.app/privacidade` |
| Support URL | `https://linka-speedtest.web.app/suporte` |
| Terms of Use | `https://linka-speedtest.web.app/termos` |
| Sobre | `https://linka-speedtest.web.app/sobre` |
| Como medimos | `https://linka-speedtest.web.app/como-medimos` |
| Atendimento Linka | `suporte@linka.app` |

Antes de submissão, o orquestrador deve conferir cada URL no host e os campos no portal Apple: fechamento exige página específica correta, acesso público e valores reais da ficha confrontados. A proposta antiga de migrar a origem para `linka.app` não corresponde ao `canonicalOrigin` lido; domínio de e-mail não define origem do site. Nenhuma URL pública da ficha do app foi inferida: o CTA depende da variável de ambiente descrita acima.

### Registro histórico do site

`design-qa.md` registra uma comparação em Safari desktop, Home escura e Termos, com a direção de marketing escolhida e screenshots reais em lugar de telas inventadas; também mantinha o CTA informativo sem URL configurada. Os artefatos apontados naquela fonte são locais/temporários e não foram reabertos. O status histórico “passed” não é aceite do WIP atual, de outras larguras, acessibilidade ou produção. Essa informação fica preservada aqui para a substituição do relatório, sem perpetuar seu preço como vigente.

Na pasta `aplicacao-web`, scripts existentes: `npm run dev`, `npm run lint`, `npm run build` (`tsc -b && vite build`) e `npm run preview`; não há script `npm test` no package.json lido. Dependências instaladas e ambiente Node compatível são pré-requisitos a conferir quando executar. Nenhum desses comandos foi executado nesta entrega documental. Hosting, variáveis efetivas e deploy não foram consultados.

## Critérios de aceite e evidência

| ID | Cenário | Resultado esperado | Evidência estática em 2026-10-04 |
|---|---|---|---|
| WEB-01 | Navegar por links e URL direta | Página correta ou retorno compreensível ao início | App, Header, Footer e NotFoundScreen lidos; comportamento HTTP não exercitado. |
| WEB-02 | CTA com/sem URL de loja | Link somente quando configurado; ausência não disfarçada de compra disponível | Ramos de AppStoreCallToAction conferidos; configuração real não consultada. |
| WEB-03 | Ver conteúdo institucional | Nenhum teste de velocidade no browser; screenshots reconhecíveis como apresentação | Componentes principais lidos; nenhuma execução de motor neles. |
| WEB-04 | Conteúdo público sobre método, privacidade e Plus | Afirmações correspondem ao código e à versão distribuída | Conteúdo localizado; conferência integral com app/serviços/loja pendente. |
| WEB-05 | Navegar com teclado/leitor de tela e tela estreita | Links, foco, semântica e leitura utilizáveis | Marcação e responsividade presentes; validação visual e acessível não executada. |

## Divergências e pendências

| Lacuna | Responsável | Evento de revisão | Critério de fechamento |
|---|---|---|---|
| Sobre promete foco exclusivo/sem telas extras, enquanto o app tem rotas secundárias | Íris + orquestrador | Próxima revisão de copy, antes de publicar | Texto alinhado ao escopo real sem esconder recursos ou ampliar promessa. |
| Como medimos afirma seleção de servidor ideal | Responsável pelo motor + Íris | Antes da próxima publicação de metodologia | Afirmação vinculada a implementação verificável ou corrigida. |
| Privacidade e publicidade contêm regras de WIP, incluindo promoção, npa e ausência de ATT | Responsáveis pelos módulos + Tito | Antes de publicar política ou app afetado | Comparar runtime/configuração/versão candidata e registrar limites; não inferir pelo texto. |
| Política WiFi Casa existe em React e arquivos públicos | Orquestrador + responsável pelo produto | Antes de publicar/remover duplicatas | Rota efetiva identificada, conteúdo conferido pelo produto e fonte única definida. |
| URL de loja, preço, screenshots e foco iPhone podem divergir da versão distribuída | Orquestrador | Próxima atualização institucional/release | Valores e assets confrontados com referência identificada; sem usar fallback como preço verificado. |
| Deep links, 404, SEO, acessibilidade e offline não exercitados | Tito + executor | Próxima alteração/deploy autorizado | Lint/build e matriz de URLs/dispositivos com evidência, mais verificação no host. |

## Consolidação e mudanças em andamento

Esta fonte consolida a descrição do site antes dispersa em visão/design e acrescenta mapa pelo código. Nenhuma alteração de copy, política, preço, asset ou infraestrutura foi feita. O WIP de InfoScreen foi lido, não declarado publicado. Descrições anteriores foram substituídas e esta fonte foi ligada ao índice; não se remove material de outros produtos por inferência.

### Imagens da landing page — organização de 2026-10-04

As três ilustrações existentes foram movidas, sem alteração de bytes, para [assets do site](../../../aplicacao-web/src/assets/screenshots/README.md). Continuam antigas: Home com CTA anterior, medição com fases/controle anteriores e resultado individual apresentado como evolução. Esta organização não atualizou a aparência da landing page. Responsáveis: Íris/executor; evento: próxima revisão do site, antes de reutilização em campanha; fechamento: substituir por capturas da candidata identificada, alinhar texto ao estado visível e revisar a página. Build e lint passaram após a mudança dos imports; isso não é validação visual nem publicação.
