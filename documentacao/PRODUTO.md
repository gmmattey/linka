# Produto Linka

Responsável: Codex principal; Íris mantém intenção, experiência e critérios de produto.
Revisão: 2026-10-04. Base: checkout de integração `docs/quatro-fontes`, sobre main `39269c7a`, incluindo a correção de Atalhos da PR #273 e o material WIP integrado.
Alcance: síntese das capacidades e limites documentados, com conferência estática das regras críticas; não certifica a build distribuída.
Fontes pares: [Arquitetura](ARQUITETURA.md) para contratos e mapa técnico; [Operação](OPERACAO.md) para configuração, validação e publicação; [Governança](GOVERNANCA.md) para trabalho e autoridade.

## Intenção e curadoria

Linka é um SpeedTest minimalista e nativo para iPhone, iPad e Mac: **abrir → iniciar medição → ver resultado → repetir**. A pessoa mede sem cadastro, onboarding obrigatório, formulário, seleção de modo ou escolha manual de servidor.
A ação é explícita, inclusive quando expressa por uma integração Apple. Abrir o app não autoriza um teste pesado. Observação viva da Home não significa medição contínua de velocidade.
O projeto nasceu da necessidade de acessar o próprio modem e recuperar sua senha; passou por ferramentas de rede e voltou ao foco na medição. Por isso, acesso ao roteador permanece útil, mas não justifica transformar o Linka em central de ferramentas.

Toda capacidade precisa melhorar **medir, entender ou acompanhar a conexão no Apple sem competir com o resultado**:

- Medição e número real vêm antes de marca, interpretação, anúncios e gráficos.
- Detalhes aparecem progressivamente; minimalismo visual não simplifica a metodologia.
- Ausência, zero, erro e resultado parcial são diferentes. Não fabricar dado para completar uma tela.
- Interpretação exige evidência; IA e sinais indiretos não comprovam causa raiz, culpa da operadora ou velocidade contratada.
- O produto é Apple. O site é institucional; não existe direção de produto Android, speed test Web ou PWA.
- Expansões comerciais e automações não viram escopo por constarem em propostas antigas. Minha Rede tem decisão explícita abaixo; cadastro não autoriza ofertas comerciais ou recomendação de troca.

## Medição, Home e recuperação

[SpeedTestViewModel](../aplicativo-ios/LinkaApp/Sources/Adapters/SpeedTestViewModel.swift) coordena o teste; [MainView](../aplicativo-ios/LinkaApp/Sources/UI/MainView.swift) apresenta início, progresso, resultado, erro e troca de conexão.
O teste formal passa por ping, download, upload e evidências finais. Não há promessa de duração fixa. Responsividade sob carga e referência regional complementam a leitura, sem medir um jogo específico.
Falha durante uma fase deve preservar fatos já obtidos. Cancelamento, background e mudança de conexão interrompem a execução; não juntar fases de redes diferentes nem salvar uma execução cancelada como concluída.
O caminho concluído tenta salvar no histórico; falha de gravação não desfaz o resultado. Preservar resultado parcial em memória não comprova gravação automática de parcial no histórico.
“Perda” derivada das sondas HTTP não é medição isolada de perda IP/ICMP. Indisponibilidade de referência regional ou responsividade não invalida automaticamente a banda medida.

A Home usa observação HTTP efêmera e aquecimento antes de interpretar. Ping não estima velocidade: eventual referência de banda vem de teste completo recente da mesma rede Wi-Fi identificada. Celular ou identidade ausente não recebem banda inventada.
A leitura viva deve ser invalidada na troca de rede, pausada durante o teste e separada do resultado salvo. Ela não alimenta o histórico como se fosse nova medição formal.
A [triagem de conectividade](../aplicativo-ios/LinkaApp/Sources/UI/ConnectivityTriageView.swift) oferece recuperação após falha: falta de caminho, acesso a endpoint, falha de resolução, suspeita de portal ou resultado inconclusivo. Um endpoint acessível não prova saúde de toda a Internet; suspeita de portal não é confirmação.

**Pendente:** Camillo/Pedro, antes de alterar a interpretação do resultado, devem reconciliar o caso de todas as sondas falharem com valores zero e a persistência de parciais. Tito fecha a validação com build identificada, rede lenta/offline, troca de conexão, cancelamento e resultado parcial. Referência regional requer resposta real do protocolo antes de ser anunciada operacional.

## Histórico, comparação e Ambientes

[HistoryView](../aplicativo-ios/LinkaApp/Sources/UI/HistoryView.swift) permite filtrar, ordenar, abrir e excluir medições. Zero registros pede uma primeira medição; um registro mostra o resultado; dois ou mais podem gerar gráfico, sem que isso constitua tendência estatística suficiente.
Histórico é Free. A fonte local continua útil sem iCloud; sincronização não é garantida e não transporta todos os campos locais. Exclusão e falha de sincronização precisam preservar a intenção da pessoa, sem ressuscitar registros.
Os [avaliadores de Insights](../aplicativo-ios/NetworkInsights/Sources/NetworkInsights.swift) calculam comparações e padrões a partir dos registros fornecidos. Dados insuficientes não significam ausência de padrão; ausência não entra na média como zero.
Adequação a vídeo, jogos, streaming e upload descreve condições observadas, não garante qualidade de serviço externo. Jogos/vídeo dependem de evidências adicionais confiáveis; não restaurar uma conclusão positiva baseada só em ping.
O limiar atual de streaming 4K é download **maior que 25 Mbps**, com condição de perda; igualdade não deve ser anunciada como adequada por herança de plano antigo.

[Ambientes](../aplicativo-ios/LinkaApp/Sources/UI/NetworkProfilesSection.swift) são lugares nomeados manualmente e associados explicitamente a uma medição, não cômodos reconhecidos por SSID/BSSID.
A associação exige resultado completo Wi-Fi, identificação habilitada e SSID disponível; o acesso usa Otimização. Ignorar a associação não muda nada. Excluir ambiente remove associações, não medições.
Nomes repetidos são permitidos, com identidades distintas. A referência exige ao menos três leituras anteriores elegíveis em 30 dias; a medição atual não conta como sua própria referência.
Ambientes e associações são locais, sem sincronização CloudKit. A migração preserva nomes/identidades, mas não atribui medições antigas automaticamente nem restaura reconhecimento por fingerprint.

**Pendente:** Tito, na próxima candidata de histórico/Ambientes, valida exclusão offline e em dois aparelhos, migração, nomes repetidos e associação nas três plataformas. Camillo decide paridade de campos sincronizados antes de prometê-la. Íris/Codex devem decidir se a antiga ação “Refazer referência” será descartada ou especificada; ela não é capacidade comprovada. Agrupamento legado por identificador de provedor não prova identidade da rede.

## Assist e interpretação

[AssistViewModel](../aplicativo-ios/LinkaApp/Sources/Adapters/AssistViewModel.swift) combina medição e contexto declarado. Assist é secundário, condicionado ao acesso e à configuração do serviço; não substitui nem atrasa a medição.
Entrada pela Home pode selecionar um objetivo e coletar nova medição. Existe entrada por resultado existente; portanto, não afirmar que toda análise exige novo teste. O contexto atual não envia lista de medições recentes nesse caminho.
Carregamento, resposta, erro, falta de configuração, falta de acesso e evidência insuficiente são estados diferentes. Timeout e falha remota permitem recuperação, sem resposta fictícia.
Relato da pessoa não se torna fato medido. Validação de IDs e estrutura da resposta não garante a verdade de cada frase. Investigação local de falha é distinta da interpretação remota.
“Sem causa identificada” não significa “conexão saudável”. Não atribuir modelo/provedor de IA por um fallback de texto; não afirmar que toda evidência local chega ao backend.

**Pendente:** Íris/Camillo, antes da próxima mudança de Assist, definem validade e reuso da medição em cada entrada. Íris e responsável pelo serviço reconciliam a copy positiva de ausência de causa; Camillo revisa atribuição de procedência. Tito fecha timeout, offline, idioma e falta de evidência na candidata. Segurança e ativação de novos transportes são tratadas em Arquitetura/Operação; proposta Netscope não comprova substituição do caminho atual.

## Otimização e DNS

[OptimizationView](../aplicativo-ios/LinkaApp/Sources/UI/OptimizationView.swift) apresenta oportunidade sustentada por fatos ou informa que não há melhoria clara. Free recebe prévia; o fluxo completo exige acesso à capacidade.
Orientação seguida de reteste compara antes/depois, sem alterar roteador ou DNS automaticamente. Resultado incompleto, tipo de rede diferente ou SSID Wi-Fi diferente/ausente tornam o reteste não comparável.
Uma métrica melhor não significa melhora de todas; ausência de ganho significativo precisa ser apresentada. Comparação observacional não prova que a ação causou a diferença, e o comparador atual não verifica explicitamente estabilidade da rota.
Sugestão de proximidade do roteador não se aplica ao celular. Regra específica de troca de banda, DoT e adaptadores de roteadores continuam propostas, não capacidades entregues.

[DNSBenchmarkView](../aplicativo-ios/LinkaApp/Sources/UI/DNSBenchmarkView.swift) permite comparar cinco provedores DoH sob ação explícita. Candidato sem respostas suficientes é inconclusivo; empate não cria vencedor único.
Aplicar DNS exige seleção e confirmação informada: efeito no dispositivo, consultas enviadas ao provedor e possibilidade de remoção. Salvo não significa ativo; a configuração precisa aparecer habilitada após nova leitura do sistema.
O app remove sua própria configuração, não gerencia perfis de terceiros. Comparar DNS não promete aumento de download, não é VPN e não modifica o roteador.

**Pendente:** Camillo/Íris, antes de prometer comparabilidade, alinham o critério de rota e a apresentação de métricas que pioraram. Tito valida reteste, cancelamento e recuperação; DNS exige candidata assinada, ativação, reinício, remoção e conflitos VPN/MDM. Sem capability/provisionamento, aplicação deve permanecer indisponível honestamente; declarar entitlement no projeto não fecha esse aceite.

## Wi-Fi, roteador e serviços externos

Detalhes de Wi-Fi dependem da plataforma, permissão e configuração. Sem dado exposto, não inventar RSSI, canal, largura de canal, MCS, topologia ou causa raiz.
No iPhone/iPad, a integração avançada é opt-in por Atalhos: a pessoa adiciona o template e habilita o uso. Cancelar ou voltar sem dados permite tentar novamente ou medir sem detalhes avançados.
No Mac, captura nativa usa dados disponíveis do sistema; não promete paridade campo a campo com o Atalho. Dados expirados, repetidos, inválidos ou de outro contexto não devem ser anexados como se fossem atuais.
O [coordenador de App Intents](../aplicativo-ios/LinkaApp/Sources/Adapters/AppIntentCoordinator.swift) já usa o resolver compartilhado corrigido na PR #273. A divergência promocional descrita nos documentos anteriores foi corrigida no código integrado; não permanece como bug aberto presumido.

[Roteador](../aplicativo-ios/LinkaApp/Sources/UI/RouterDiscoveryView.swift) localiza o gateway atual e verifica acesso ao painel antes da abertura confirmada no navegador. Gateway encontrado não garante painel HTTP acessível nem prova estado de permissão.
No iOS, senha pode ser guardada e removida no Keychain a pedido da pessoa; o caminho Mac não oferece essa gestão de senha. Não é scanner de dispositivos, configuração automática ou serviço remoto de credenciais.
[Status de serviços](../aplicativo-ios/LinkaApp/Sources/UI/ServiceStatusView.swift) consulta catálogo/incidentes, permite buscar e acompanhar serviços elegíveis. Incidente remoto não diagnostica a conexão local.
Preferência de alerta, permissão do sistema, token e entrega push são etapas distintas. A ausência de incidente no catálogo não é garantia de disponibilidade, sobretudo após falha de atualização.

**Pendente:** Tito valida Atalho real, cancelamento, permissões, contexto parcial e associação em iPhone/Mac antes de anunciar a capacidade na candidata. Para roteador, fecha painel real/inacessível, rede local negada e senha. Íris/Pedro decidem como mostrar status antigo; Tito/Codex verificam registro de instalação mesmo sem alertas e entrega APNs antes de prometer notificações operacionais. Ofertas de equipamentos/afiliados exigem decisão explícita de Luiz e não estão implementadas.

## Free, Plus e publicidade

A [política central](../aplicativo-ios/LinkaEntitlements/Sources/LinkaEntitlements.swift) mantém medição e histórico acessíveis no Free, inclusive diante de snapshot inválido. Plus libera capacidades adicionais; modo Expert controla exibição, não a execução do motor.
**Plus pago válido é sem anúncios. Promoção libera capacidades, mas mantém elegibilidade a anúncios.** A precedência do resolver é compra verificada válida → promoção suportada e vigente → Free, compartilhada pelo app e pelos intents Wi-Fi.
A campanha configurada alcança iOS/iPadOS até o fim de 31/10/2026 em São Paulo; não há promoção automática no Mac. Isso descreve a configuração fonte, não garante campanha visível na loja ou data remota atualizada.
Preço vem do StoreKit; não de screenshot, comentário ou fallback do site. Compra pendente, cancelada, indisponível e restauração não podem ser apresentadas como assinatura confirmada.
[Publicidade](../aplicativo-ios/LinkaApp/Sources/Adapters/Ads/LinkaAdsCoordinator.swift) depende de plataforma, configuração, entitlement e consentimento. Home e Histórico elegíveis disputam uma tentativa por sessão; Histórico precisa ter conteúdo.
Iniciar medição cancela o fluxo pendente e remove anúncio. Anúncio não cobre resultado, imita controle ou interrompe teste. O adapter Mac não apresenta anúncios. Configuração de anúncios não personalizados não autoriza afirmar ausência de coleta do SDK.

**Pendente:** Tito, antes da release comercial, valida compra/restauração/expiração, promoção/Free/Plus pago e início do teste durante consentimento. Pedro fecha a fronteira temporal exata do encerramento da campanha antes desse evento; Codex confronta política, candidata e comunicação pública sem inferir preço vigente.

## Integrações Apple e compartilhamento

[LinkaApp](../aplicativo-ios/LinkaApp/Sources/LinkaApp.swift) compõe as ações Apple. Iniciar teste abre o app; último resultado e histórico têm handlers próprios. Não presumir que toda ação seja exclusiva do Plus porque existe um helper genérico de entitlement.
O [widget](../aplicativo-ios/LinkaWidget/Sources/LinkaSpeedTestWidget.swift) mostra resumo persistido e data, com estado vazio quando ausente; não mede continuamente. A ação de medição silenciosa não tem execução implementada no handler atual e não deve ser divulgada como disponível.
O [compartilhamento](../aplicativo-ios/LinkaApp/Sources/UI/ShareCardView.swift) está implementado: o cartão próprio usa a medição e seletores nativos iOS/macOS. A decisão é disponibilizá-lo somente para resultado concluído atual ou histórico; a aplicação uniforme desse gate e sua validação permanecem pendentes, conforme Arquitetura. Não é screenshot bruto nem nova medição.
O cartão inclui métricas, data, tipo de conexão e banda confirmada quando disponível. Não lê SSID, provedor/identificador de rede, IP ou BSSID; não há opt-in para incluí-los nessa implementação. Disponibilidade de destinos depende do sistema, sem integração dedicada a mensageiro.
Essa proteção do cartão não comprova anonimização de todo o produto. Contexto local, sincronização, Assist, SDKs e serviços têm limites próprios; política pública deve refletir a composição real.

**Pendente:** Tito/executor, na candidata que alterar integrações, conferem cada ação Free/Plus, instalação do widget, idioma e atualização do resumo. Compartilhamento não fica classificado como “não implementado”; permanece pendente a validação da imagem gerada, campos ausentes, privacidade e apresentação por plataforma. Codex mantém medição silenciosa indisponível até decisão e implementação comprovadas.

## Experiência, acessibilidade e identidade

A voz é curta, calma e concreta: “Download”, “Upload”, “Detalhes”, “Testar novamente”. Erro explica o ocorrido e oferece recuperação. Evitar entusiasmo artificial, slogans na interface e promessas como “ideal para qualquer uso”.
Números, unidades e datas seguem o idioma efetivo. Há preferências de aparência/idioma; presença de tradução não prova qualidade integral em pt-BR, inglês e espanhol.
No iPhone/iPad, navegação secundária usa caminhos contextuais, toolbar e sheets; não há requisito de adicionar tab bar. iPad adapta largura/orientação, sem herdar automaticamente o redesign Mac.

Direção macOS vigente:

- Uma decisão e uma ação primária por estado; download/upload protagonistas e reteste claro.
- Sidebar nativa e estável com wordmark; Assist e Otimização contextuais, sem transformar a área principal em dashboard.
- Detalhes, rede e metodologia recolhidos quando não são necessários à primeira decisão; cada dado tem um lugar.
- Listas, seções e separadores em telas utilitárias; sem cardização, sombras ou animação decorativa por padrão.
- Vazio explica o que falta e o próximo passo; erro começa pelo resumo, com conteúdo técnico em detalhe.
- Sheets têm título, decisão e saída claros. Não restaurar gauge/pills de planos antigos nem anunciar janela 780×560: o mínimo declarado atual é 960×600.

[DesignSystem.swift](../aplicativo-ios/LinkaApp/Sources/UI/DesignSystem.swift) e [fundo nativo](../aplicativo-ios/LinkaApp/Sources/UI/LinkaScreenBackground.swift) materializam tokens e variantes. Fundo com gradiente existe; a direção não é uma proibição literal de todo gradiente. CSS e Swift não têm igualdade automática.
[Protótipo](design/prototipo/) orienta fluxo/geometria e [recursos do Design System](design/design_system/) orientam identidade. Demos, frame Android histórico e JSX não comprovam capacidades nativas: MetricRing não mede, AdSlot não integra anúncios; Button tem variantes, não é “único ghost”.
Usar wordmarks e ícones oficiais, sem redesenho ou substituição por texto. O [catálogo do app](../aplicativo-ios/LinkaApp/Sources/Assets.xcassets/) é a origem do [kit brand](../brand/manifest.json); preservar proporções, cores e transparência e atualizar cópias pelo manifesto. O site tem implementação própria de marca.

**Pendente:** Íris/Tito, antes de declarar padronização, percorrem todos os destinos alcançáveis — sidebar, menu, toolbar, sheets, alertas e detalhes — nos estados vazio/carregando/resultado/erro/destrutivo aplicáveis. Fechamento exige build identificada, janela ampla/estreita, iPad retrato/paisagem/Split View, teclado, VoiceOver, texto ampliado, contraste e Reduzir Movimento. Referências antigas e componentes de demonstração são confrontados ao serem reutilizados; não geram redesign automático.

## Site e comunicação pública

[App.tsx](../aplicacao-web/src/App.tsx) e [LandingScreen](../aplicacao-web/src/screens/LandingScreen.tsx) apresentam o produto e páginas informativas, sem executar o motor. CTA depende de URL configurada; sem ela, não simular download disponível.
As três imagens da landing foram preservadas como ilustração antiga: Home/medição anteriores e resultado individual associado à ideia de evolução. Mudança de pasta não atualizou a aparência. Nenhuma captura sem build identificada é prova da candidata.
Copy pública deve descrever medição e acompanhamento, com limites de plataforma/permissão/configuração; não prometer descobrir a causa da rede travar. Texto comercial completo, URLs de suporte/privacidade/termos e preparação da loja pertencem a Operação.

**Pendente:** Íris/executor, antes da próxima publicação, alinham imagens e títulos ao estado visível, removem promessa de servidor “ideal” sem base e reconciliam páginas Sobre/Privacidade com as capacidades reais. Codex verifica preço, CTA, URLs e versão distribuída; Tito confere navegação, acessibilidade e comportamento no host. Políticas de outros produtos presentes no site não são apagadas por inferência.

## Critério de conclusão de produto

Uma entrega está pronta para avaliação quando a pessoa consegue iniciar, cancelar, ler e repetir a medição sem perder controle; dados reais, parciais e ausentes permanecem distinguíveis; interpretação e publicidade respeitam o resultado; acesso e privacidade correspondem ao comportamento declarado.
Aceite exige evidência proporcional na build pretendida e nos destinos afetados, incluindo recuperação e acessibilidade. Código e testes existentes sustentam leitura estática, não execução nem aprovação visual; aprovação passada não valida outro checkout.
Nesta revisão documental não houve app, teste, build, simulador, aparelho, serviço remoto, consulta de loja ou release. A síntese não fecha planos, não cria escopo e não declara publicação. Procedimentos e evidências de execução ficam em Operação; contratos e riscos técnicos ficam em Arquitetura.

## Minha Rede — decisão de produto de 08/10/2026

O Linka passa a conhecer os equipamentos da pessoa para contextualizar a rede doméstica, mantendo a medição simples e independente. **V1 completa em iPhone, iPad e Mac, gratuita, incluindo cadastro e pesquisa técnica com IA.** Cadastro básico não exige conta, Plus, plano contratado, Ambiente, câmera ou internet. A pesquisa precisa de internet; sua indisponibilidade não impede salvar, editar ou consultar o inventário local. Não há sincronização entre dispositivos na V1.

A decisão de correção de 08/10/2026 substitui o formulário inicial: **identificar → pesquisar → confirmar e salvar**. A pessoa fotografa/escolhe uma etiqueta ou digita o equipamento em um campo. A pesquisa começa por ação explícita; não há confirmação redundante. Cadastro manual e salvamento sem pesquisa continuam disponíveis offline.

- A pesquisa aceita qualquer marca, sem lista fechada, região ou revisão obrigatórias. A identificação pode ser incompleta; o Linka só pergunta mais quando há ambiguidade real. Sugestões de modelos semelhantes são separadas, nunca substituem silenciosamente o informado.
- OCR usa Vision local e preenche sugestão editável, sem lista de marcas. Foto, texto bruto, senha, serial, SSID e MAC não são armazenados nem enviados. A consulta recebe somente identificação pública e os opcionais de revisão/região conhecidos.
- A IA pesquisa a internet e propõe identidade, tipo e capacidades sustentadas por fontes. O resultado aparece no mesmo lugar da busca, sem salto ao topo. Progresso não usa porcentagem ou etapas inventadas. Falha, cancelamento e resposta tardia preservam o rascunho.
- Um cartão resume o equipamento e até três capacidades; detalhes e fontes ficam expansíveis. “Salvar equipamento” confirma e guarda a ficha em uma operação, sem telas separadas de revisar/aplicar. Correções do usuário não são sobrescritas por nova pesquisa.
- “Completar informações” fica no detalhe após salvar: apelido, local e instalação opcionais. Perguntas como “Este é o roteador principal?” e “É neste aparelho que a fibra chega?” admitem Não sei. Tipo e ficha não comprovam instalação, propriedade, topologia ou desempenho observado.
- Resultados parciais são úteis; dados conflitantes ou dependentes de variante desconhecida ficam ausentes. “Não encontrado” só descreve pesquisa concluída sem dados suficientes. Erro de serviço, rede, timeout ou validação tem mensagem de falha e nova tentativa; todos permitem salvar a identificação.
- O fluxo explica em linguagem simples o uso de IA e os dados enviados. Fornecedores e tratamento técnico ficam em detalhes de privacidade acessíveis, sem mensagem de Cloudflare/IP no cadastro.
- Exclusão e descarte têm confirmação. Equipamento e ficha salvos funcionam offline e após reinício. VoiceOver, Dynamic Type, teclado e apresentação nativa fazem parte do aceite nas três plataformas. Salvar/abrir cadastro não dispara medição nem exige conta ou Plus.

**Entrega gradual interna, lançamento público completo.** Os pacotes podem integrar separadamente: persistência/CRUD, OCR, pesquisa/ficha e QA. Uma tela interna de cadastro com pesquisa desligada não encerra a V1. Disponibilidade pública depende da jornada completa, fontes confiáveis, serviço operacional aprovado e validação nas três plataformas. Código em branch não significa merge, build distribuída ou homologação.

O programa é o [épico #278](https://github.com/gmmattey/linka/issues/278): modelo [#279](https://github.com/gmmattey/linka/issues/279), cadastro [#280](https://github.com/gmmattey/linka/issues/280), OCR [#281](https://github.com/gmmattey/linka/issues/281), ficha/QA [#282](https://github.com/gmmattey/linka/issues/282) e pesquisa [#283](https://github.com/gmmattey/linka/issues/283). Painel/credenciais do roteador ([#142](https://github.com/gmmattey/linka/issues/142), [#179](https://github.com/gmmattey/linka/issues/179)) seguem outro escopo. Nenhum dado passa automaticamente ao Assist, NDS ou Netscope diagnóstico.

### Minha Rede V2 — Perfil doméstico, plano declarado e visão consolidada

Entregue e consolidada na main pelas PRs #296 (Core), #297 (UI de Plano e Conexões) e #298 (Visão Consolidada):

- **Meu plano:** Cadastro honesto de operadora de internet fixa (sem catálogo fechado nem inferência de chip celular), velocidades de download e upload nominais independentes em Mbps, tecnologia de acesso residencial (`AccessTechnology`: fibra, cabo, DSL, rádio, modem 4G/5G com chip fixo residencial, satélite, outra, não sei) e valor mensal opcional.
  - *Distinção temporal:* "Salvar correções" edita no lugar erros de digitação; "Troquei de plano" encerra o plano anterior (`effectiveTo = now`) e inicia uma nova versão, preservando o contexto histórico para que a futura V3 não compare medições passadas com contratos novos.
  - *Zero confusão com plano móvel:* Microcopy no topo explicita que se trata da internet fixa residencial. Nenhuma API de SIM card ou telefonia celular é lida.
- **Como estão conectados:** Quando a rede possui dois ou mais equipamentos, lista as conexões declaradas no formato `Origem → Meio → Destino` com `LinkMedium` (cabo Ethernet, Wi-Fi, fibra, outro, não sei), respeitando o sentido da internet ou usando travessão neutro (`A — Meio — B`) quando não informado.
  - *Convite não-intrusivo:* Surge após cadastrar o segundo aparelho, com opções "Conectar a outro aparelho", "Agora não" e "Não sei responder". Ausência de ligação declarada nunca é tratada como "desconectado" ou "defeito".
- **Visão consolidada em 4 seções:** `MyNetworkView` organiza harmonicamente: *Meu plano*, *Equipamentos* (exibindo tipo e cômodo/local na mesma linha), *Como estão conectados* (oculta se `< 2` aparelhos) e *Ambientes* (atalho para gestão existente, com nota de rodapé explícita desvinculando medições passadas).
- **Acesso gratuito:** Minha Rede permanece 100% Free no iPhone, iPad e Mac, sem paywall, sem login e com dados estritamente locais.

### Minha Rede V3 — Desempenho do plano residencial e correlação com testes

Entregue e integrada ao `NetworkInventory` e `LinkaApp`:
- **Avaliação factual:** O app correlaciona as medições elegíveis com o plano residencial ativo, exibindo os percentuais de entrega de download e upload e a quantidade de testes considerados.
- **Hierarquia de estados e ausência:** Diferencia categoricamente *Sem testes elegíveis* (`noData`), *Desempenho condizente* (`meetingPlan`, >= 80%), *Superou o plano* (`exceeding`, >= 105%), *Desempenho parcial* (`partiallyMeeting`, 50% ..< 80%) e *Abaixo do contratado* (`belowPlan`, < 50%).
- **Microcopy orientativa e honesta:** Zero acusações levianas contra a operadora e zero recomendações comerciais; orientações físicas transparentes sobre atenuação Wi-Fi, distância e bandas de 2,4 GHz vs. 5 GHz.
- **Acesso gratuito mantido:** 100% Free no iPhone, iPad e Mac, local-first.

### Evolução preservada para V4

- **V4** poderá oferecer Assist contextual com consentimento/projeção explícita, ações guiadas e reteste.
- Não estão implementadas por esta decisão: ofertas/afiliados, sincronização CloudKit e monetização avançada.
