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

<a id="assist-contextual-v4"></a>
## Assist Contextual V4 — documentação funcional do agente especialista

**Integração documental:** 09/10/2026, versão 1.0. **Status:** proposta funcional para revisão e implementação; não representa funcionalidade implantada. Origem: documentação funcional elaborada com Luiz nesta conversa. Conteúdo incorporado a esta fonte, sem criar outro manual por feature.

**Responsável pelo produto:** Luiz. **Programa:** Minha Rede, Fase 4. Execução: [épico #301](https://github.com/gmmattey/linka/issues/301) e issues #310–#321. Arquitetura, contratos e limites em [Arquitetura — Assist V4](ARQUITETURA.md#assist-contextual-v4); testes, ativação e reversão em [Operação — Assist V4](OPERACAO.md#assist-contextual-v4).

O estado existente descrito acima continua válido para a modalidade de medição. Esta proposta amplia o Assist, sem substituir o motor, liberar novos envios ou certificar as fases anteriores. A base de referência da documentação é `8268dac778bbdd8b2ed9eab7ec5a463597cf0f7a`.

### V4.1 Decisão de produto, objetivos e limites

O Assist será o técnico pessoal da rede: conhece os dados cadastrados e autorizados, consulta referências técnicas pertinentes, utiliza medições elegíveis e ajuda a investigar problemas e decidir melhorias. Não depende de o usuário conhecer backhaul, latência, AP ou gateway.

A escolha proposta é **um agente especialista supervisionado**, não vários agentes conversando entre si. Combina instruções de domínio, procedimentos, documentação recuperada, ferramentas delimitadas e memória explícita da consulta. Não requer treinamento de modelo próprio nem nova identidade visual. É o agente de atendimento do produto, não os agentes de desenvolvimento do Codex.

O modelo interpreta a pergunta, relaciona evidências e propõe a próxima etapa; o software controla leitura, envio, execução, orçamento e apresentação. O agente pode orientar além de parafrasear regras existentes, mas não declarar fatos sobre a residência sem base nem criar poderes que o aplicativo não possui. A distinção entre workflows e agentes embasa esta escolha de arquitetura, não uma promessa de superioridade universal. [V4-R2]

| Modalidade no mesmo Assist | Exige medição? | Comportamento |
|---|---|---|
| Entender uma medição — “O que significa esse resultado?” | Sim, para interpretar aquele resultado | Preservar diagnóstico e regras existentes. |
| Consultoria contextual — “Meu roteador é adequado?” | Não para iniciar | Usar cadastro, fontes e perguntas; solicitar teste apenas quando necessário. |

Não haverá dois chats nem escolha técnica obrigatória de modo. A origem e a intenção determinam o contexto. “O que é um ponto de acesso?” recebe explicação sem cadastro ou teste obrigatório.

**Objetivos:** reduzir orientações genéricas; não repetir cadastros; evitar compras desnecessárias; oferecer próxima ação executável; registrar tentativas; admitir insuficiência; preservar minimalismo.

**Entrega inicial:** pergunta aberta; quatro jornadas guiadas; entrada por Oportunidades; consulta à ficha/documentação; solicitação autorizada de testes existentes; resposta estruturada; ações e histórico local de consultas.

**Fora da entrega inicial:** alteração automática de roteador/DNS, reinício remoto, reset de fábrica, atualização automática de firmware, scanner arbitrário, monitoramento contínuo, compras/contratação, agentes em segundo plano e sincronização de conversas. Comparação automática de ofertas fica desligada até haver fonte confiável e autorização operacional.

**Plataformas:** desenhar e homologar a nova experiência em iPhone/iPad. Preservar Assist e Minha Rede existentes no Mac. Ativar a consultoria no Mac exige homologação própria de interface, autenticação e ferramentas; não presumir paridade nem remover capacidades anteriores.

### V4.2 Autoridade e requisitos funcionais

| Participante | Responsabilidade | Limite |
|---|---|---|
| Usuário | Relatar sintomas, confirmar instalação, autorizar envio/testes, aceitar ações | Declaração não vira medição ou confirmação do fabricante. |
| Linka e motor | Produzir e armazenar resultados com método/contexto | Não inferir equipamento, cômodo ou causa sem evidência. |
| Avaliadores determinísticos | Validar unidades, elegibilidade, comparação e achados | Não reduzir toda investigação a causas previamente cadastradas. |
| Agente especialista | Entender intenção, formular hipóteses qualificadas, consultar referências e orientar | Não executar diretamente nem promover hipótese a causa comprovada. |
| Validador de saída | Conferir esquema, referências, valores e ações | JSON válido não garante a verdade de toda frase. |

**RF-01 — Entrada aberta:** “Pergunte sobre sua rede...” na entrada, perguntas guiadas, resultados e acompanhamento; os quatro atalhos são alternativas, não uma limitação de assuntos.

**RF-02 — Contexto opcional:** conversar sem equipamento, plano ou teste. Solicitar informação apenas quando sua ausência limita a pergunta atual. Cadastro completo não é barreira à medição nem à explicação geral; acesso comercial permanece separado.

**RF-03 — Rede correta:** usar instalação escolhida/confirmada. Um único perfil, gateway repetido ou nome Wi-Fi semelhante não comprova vínculo entre teste e casa.

**RF-04 — Consentimento:** antes do primeiro envio, informar processadores, categorias e finalidade. A pergunta também é dado enviado; desligar contexto não torna a pergunta local. Consentimento de contexto não autoriza testar, configurar ou comprar. Conferir o requisito de compartilhamento com IA de terceiros nas diretrizes Apple antes da ativação. [V4-R3]

**RF-05 — Pergunta adaptativa:** uma pergunta relevante por vez, opções, “Não sei” e texto livre. Não repetir fato confirmado e pertinente; mudança/contradição justifica perguntar novamente, explicando o motivo.

**RF-06 — Encerramento útil:** parar quando houver resposta suficiente, ação segura ou ausência de investigação viável. Após repetidos “Não sei”, oferecer orientação limitada ou teste opcional, não prolongar artificialmente.

**RF-07 — Teste autorizado:** mostrar finalidade, impacto e condições antes da medição. Gesto explícito inicia; IA propõe. Recusa/impossibilidade mantém a consulta utilizável.

**RF-08 — Resposta fundamentada:** distinguir observação, declaração, especificação, conhecimento geral e hipótese. Ausência de evidência não significa ausência de problema.

**RF-09 — Pesquisa real:** especificação desconhecida, variante ou condição comercial atual exige ferramenta e fonte rastreável. Conhecimento interno do modelo não equivale a pesquisa realizada.

**RF-10 — Acompanhamento:** ação aceita tem identidade; pode ser concluída, ignorada, impossível ou retestada. Não repetir tentativa malsucedida sem nova razão.

**RF-11 — Continuidade:** voltar, fechar, interromper, editar e retomar não apagam a sessão. Nova pergunta pode complementar; mudança que abandone ação pendente pede confirmação.

**RF-12 — Histórico/exclusão:** rascunhos e orientações seguem política local proposta. Excluir consulta não apaga medições. Excluir medição invalida referências futuras e remove projeções/caches correspondentes, sem ressuscitar valores pelo resumo.

**RF-13 — Erro não é diagnóstico:** falha da IA, timeout, indisponibilidade ou bloqueio de acesso são estados do Assist, não evidência de defeito da rede do usuário.

**RF-14 — Uso comercial preservado:** reutilizar política atual de acesso. Esta especificação não cria preço, franquia diária ou nova liberação Free/Plus. Leitura, cópia e exclusão de orientações já salvas não exigem nova compra.

### V4.3 Jornada comum de ponta a ponta

```text
Pergunta aberta / atalho / medição / equipamento / oportunidade
  → sessão local + contexto pertinente
  → acesso + consentimento antes do envio
  → resposta direta OU pergunta OU pesquisa OU proposta de teste
  → validação e autorização de execução
  → resposta estruturada + evidências + próxima ação
  → salvar / perguntar / seguir ação / retestar
  → comparação qualificada + histórico / retomada / exclusão
```

Sem consentimento, conservar rascunho e ferramentas locais. Com autorização, enviar resumo tipado, não cópia irrestrita do banco. Perguntas e testes admitem recusa. Pesquisa pública não recebe cômodo, endereço, senha ou conversa completa como termos de busca.

No reteste, classificar melhora observada, piora, ausência de mudança relevante ou inconclusivo. Melhorar após uma ação não prova que ela foi a causa. Falha de transporte preserva o último estado estável e a última resposta validada.

<a id="assist-v4-lentidao"></a>
### V4.4 Minha internet está lenta

**Intenção:** entender o sintoma e escolher próximo passo, sem culpar automaticamente Wi-Fi ou operadora. Contexto: interface, data/método, medições elegíveis, ambiente confirmado, plano, equipamentos e conexões relevantes. Histórico não representa automaticamente o estado atual.

Perguntar apenas lacunas: casa inteira ou um lugar; todos os aparelhos ou um; todos os usos ou só um aplicativo; horário e situação comparável quando relevantes.

| Situação | Próxima etapa | Limite |
|---|---|---|
| Um cômodo | Comparação controlada perto do roteador e no ponto afetado | Diferença não isola distância, interferência ou defeito. |
| Um aparelho | Comparar outro aparelho no mesmo local por declaração ou teste compatível | Não afirmar ter testado outro aparelho pelo iPhone atual. |
| Um serviço | Investigar sintoma específico; status externo só com integração/fonte | Teste geral normal não prova saúde daquele serviço. |
| Piora sob uso simultâneo | Consultar responsividade sob carga; teste controlado | Ping isolado não descreve carga. |
| Download abaixo do plano | Conferir condições, portas, caminho e comparação | Wi-Fi isolado não prova descumprimento contratual. |
| Sem conectividade para IA | Preservar triagem local e rascunho | Não simular resposta remota. |

Saídas: indício com próximo teste; ação simples compatível; evidência insuficiente; encaminhamento fundamentado. Não recomendar 5 GHz sem disponibilidade/seleção confirmadas nem reinício universal.

**Implementação parcial iOS:** depois de declarar contexto local compatível, a pessoa pode tocar em **Fazer teste agora**. O app informa antes que haverá tráfego e que o resultado concluído entra no histórico normal do Linka; a medição formal devolve à mesma sessão somente seus fatos, tipo de conexão e data. Isso não envia a investigação ao Assist, não cria comparação por si só e não permite separar LAN, Internet, DNS ou operadora.

**Aceite:** início útil sem medição; teste recusado não bloqueia; local/data corretos; origem não confirmada continua hipótese; ação/reteste retornam à mesma sessão. Execução: [#313](https://github.com/gmmattey/linka/issues/313).

<a id="assist-v4-roteador"></a>
### V4.5 Meu roteador é adequado

Avaliar necessidade real, não classificar geração como boa/ruim. Selecionar aparelho ambíguo, confirmar variante e papel; perguntar objetivo. Considerar portas no caminho, capacidades documentadas, upload/download, simultaneidade declarada, experiências por ambiente e estabilidade.

Avaliação preventiva sem teste pode dizer “As especificações são compatíveis com esse uso; ainda não avaliamos o desempenho na sua casa”. Ausência de problema relatado ou teste não comprova adequação.

Wi-Fi 5 não implica troca; taxa PHY não é velocidade garantida; porta importa quando está no caminho; firmware publicado não comprova firmware instalado; equipamento da operadora não comprova bloqueio; suporte a modo não comprova configuração atual.

Saídas: manter, ajustar, investigar, atualização como candidata por limitação relevante ou insuficiência. Considerar aproveitar o equipamento e AP antes de substituição. Sem ofertas específicas nesta etapa.

**Aceite:** iniciar sem teste; modelo ambíguo gera pergunta; especificação com procedência; condição não vira garantia. Execução: [#314](https://github.com/gmmattey/linka/issues/314).

<a id="assist-v4-mesh"></a>
### V4.6 Preciso de uma rede mesh

Avaliar distribuição de cobertura e mobilidade; mesh é alternativa, não conclusão padrão. Identificar locais afetados e distinguir diferença local de problema do acesso à internet. Perguntar possibilidade de cabo, posição e deslocamento quando relevantes.

Um ponto afetado favorece avaliar reposicionamento/AP antes de sistema inteiro; vários pontos justificam comparar distribuição. Cabo permite AP ou mesh cabeada, sem obrigar uma alternativa.

Não determinar nós apenas por metragem, assumir interoperabilidade, garantir capacidade de enlace intermediário ou tratar cômodos cadastrados como cobertura medida. Explicar backhaul como “a ligação entre os pontos da rede”.

Saídas: mesh não justificada pelos dados; reposicionamento; AP candidato; mesh candidata; teste adicional. Explicar vantagens relativas e alternativas mais simples, sem obrigação de compra.

**Aceite:** comparar alternativas; cabo/compatibilidade confirmados ou desconhecidos; sem alcance ou sinal inventado. Execução: [#315](https://github.com/gmmattey/linka/issues/315).

<a id="assist-v4-plano"></a>
### V4.7 Meu plano vale a pena

Distinguir adequação técnica, adequação ao uso e avaliação de preço. Usar capacidade/mensalidade declaradas, vigência, satisfação, simultaneidade e medições elegíveis. Perguntar objetivo: economizar, estabilidade, capacidade ou alternativas. Sem preço, avaliar capacidade; sem referência externa atual, não afirmar caro/justo frente ao mercado.

**Sem catálogo:** explicar compatibilidade com uso, lacunas e necessidade de investigar Wi-Fi antes de upgrade. Preparar negociação sem inventar uma oferta melhor.

**Extensão de mercado:** desligada até auditar catálogo/termos. Oferta precisa de fonte, data, vigência promocional, preço posterior, instalação, fidelidade, multas informadas e cobertura confirmada ou pendente. Cidade/CEP não garantem endereço elegível; avaliação básica não exige endereço completo.

**Cálculo:** código soma mensalidades do horizonte, taxas conhecidas e custo de saída informado, subtrai descontos comprovados; IA explica. Informação ausente torna comparação parcial, não zero presumido. Custo/Mbps é secundário, não qualidade.

Saídas: uso compatível; avaliar redução; capacidade adicional candidata; considerar negociação; dados comerciais insuficientes; investigação técnica antes da troca. Não declarar obrigação contratual, multa ou direito sem informação verificável e revisão específica.

**Aceite:** funcionar sem ofertas; economia com premissas; teste antigo não recebe plano novo; mensalidade só nesta intenção e com autorização. Execução: [#316](https://github.com/gmmattey/linka/issues/316).

<a id="assist-v4-pergunta-aberta"></a>
### V4.8 Pergunta aberta

Exemplos: aproveitar roteador antigo como AP, explicar bandas, melhorar videochamadas. Não forçar tudo às quatro jornadas. Identificar explicação geral, instrução específica, investigação ou decisão comercial; aproveitar procedimentos sem reiniciar assunto. Esclarecimento não zera investigação.

Instrução específica exige modelo/revisão/documento aplicável; incerteza gera condição ou pergunta. Explicação geral não exige medição. Mudança durante ação oferece “Continuar nesta consulta” ou “Iniciar outra”. Editar pergunta anterior cria revisão e invalida conclusões dependentes, sem reescrever silenciosamente histórico. Fora de redes, informar limite brevemente.

**Aceite:** envio real; múltiplos turnos; referências pertinentes; cadastro vazio; cancelamento/erro/retomada/exclusão. Execução: [#319](https://github.com/gmmattey/linka/issues/319).

<a id="assist-v4-oportunidades"></a>
### V4.9 Oportunidades de melhoria

Preservar motor determinístico existente. Oportunidade comunica achado; Assist aprofunda. “Investigar com Assist” transfere ID da oportunidade, versão da regra e referências; destino revalida. Ação sugerida pelo motor é candidata a revisão contextual, não ordem nem prova causal.

Consulta existente para o contexto pode ser retomada; taps repetidos não duplicam sessão. Medição apagada não reaparece: preservar pergunta e explicar falta. Modalidade desligada mantém navegação antiga funcional. DNS/Ambientes usam componentes existentes, sem novo cadastro ou mudança de configuração para alimentar consulta. Execução: [#321](https://github.com/gmmattey/linka/issues/321).

<a id="assist-v4-ux"></a>
### V4.10 Direção visual e experiência de resposta

Conservar hierarquia discutida: contexto compacto, pergunta clara, seleção simples, resposta organizada e campo livre persistente. PNGs/SVGs anteriores são reconstruções, não screenshots originais nem aceite pixel a pixel. Referências já registradas: [#312](https://github.com/gmmattey/linka/issues/312), [#319](https://github.com/gmmattey/linka/issues/319), [#321](https://github.com/gmmattey/linka/issues/321). Validar na build pretendida, conforme Governança.

**Entrada:** Assist, linha/seção compacta de contexto, quatro sugestões e campo aberto. Sem números fictícios/zeros decorativos. “Usar dados da minha rede” reflete autorização real.

**Investigação:** uma pergunta, opções acessíveis e texto. “2 de 4” apenas com percurso conhecido; no adaptativo usar “Investigando” ou etapa. Voltar preserva escolhas; alterar recalcula dependências.

**Resposta:** conclusão → justificativa curta → equipamento/plano/medição pertinente → uma próxima ação principal → “Dados usados na resposta” recolhível → pergunta complementar se necessária → Copiar/Salvar discretos → campo livre no rodapé. Blocos ausentes não deixam buracos. Insuficiência é resultado, não erro vermelho. Copiar exclui identificadores desnecessários; Salvar confirma gravação e trata erro.

**Acessibilidade:** controles/tokens nativos do Linka; claro/escuro, tipografia semântica, foco, teclado, VoiceOver e texto ampliado. Não diminuir fonte para caber. Rótulo e estado selecionado nas opções; não depender só da cor. Campo não encobre conteúdo/evidências. Cobrir telas pequenas, teclado aberto, texto longo e orientações iPad.

### V4.11 Memória, ações, reteste e proteção

**Memória da consulta:** intenção, respostas confirmadas, referências, hipóteses, tentativas e resultados. Não persistir raciocínio interno. Resumo não altera consentimento nem transforma hipótese em fato.

**Memória da residência:** “Troquei de roteador” pode propor edição, mas Minha Rede só muda por confirmação separada. Sessão anterior continua ligada ao contexto anterior.

**Política local proposta:** rascunhos retomáveis por sete dias; orientações salvas até exclusão; sem sincronização nesta versão. Prazos são proposta a aprovar e implementar, não configuração operacional comprovada. Permitir exclusão imediata.

**Ações:** pendente, concluída por declaração, verificada por evidência, ignorada, impossível. Concluir não prova melhora. Assist não reinicia nem altera DNS. Orientação manual com risco de interrupção requer justificativa, aviso e momento adequado.

**Reteste:** registrar objetivo/variável alterada. Comparar metodologia e condições compatíveis; ambientes distintos podem ser a variável de comparação controlada. Interrupção, caminho incerto ou várias mudanças limitam a conclusão. Reutilizar #317, não criar comparador concorrente.

Não solicitar credenciais, serial, MAC, CPF ou endereço completo. Texto pode conter segredo: avisar/minimizar sem prometer filtro perfeito. Separar uso local, envio a processador, teste e ação manual. Mudança de fornecedor/categorias exige informação e autorização aplicáveis. Revogar bloqueia novos envios/tenta cancelar ativos, sem desfazer processamento já realizado. [V4-R3]

Páginas, resultados e saída da IA são dados não confiáveis. Não abrir endpoint local nem executar conteúdo de manual por ordem da IA. Controles reduzem, não eliminam, alucinação e prompt injection. [V4-R5]

<a id="assist-v4-aceite"></a>
### V4.12 Critérios de aceite e rastreabilidade

| ID | Cenário | Resultado necessário | Issues |
|---|---|---|---|
| AC-01 | Pergunta aberta sem teste/cadastro | Explicação ou pergunta útil; não erro sem medição | #311, #319, #320 |
| AC-02 | Envio recusado com contexto disponível | Nenhum envio; rascunho/ferramentas locais preservados | #311, #312 |
| AC-03 | Lentidão em um cômodo | Propor comparação; não inventar RSSI/causa | #313 |
| AC-04 | Variante desconhecida | Pedir confirmação ou qualificar | #314 |
| AC-05 | Mesh com cabo disponível | Comparar alternativas; sem compra automática | #315 |
| AC-06 | Plano sem fonte comercial | Avaliar uso; não afirmar preço justo/oferta disponível | #316 |
| AC-07 | Oportunidade válida | Abrir/retomar com evidências corretas | #321 |
| AC-08 | Teste recusado/falhou/interrompido | Orientação limitada e sessão consistente | #317, #320 |
| AC-09 | App fechado e reaberto | Restaurar localmente, sem envio/teste automático | #317, #320 |
| AC-10 | IA inventa valor/fonte/ferramenta | Bloquear conteúdo inválido e tratar fallback | #311, #318 |
| AC-11 | Excluir consulta | Remover consulta; preservar medições | #317 |
| AC-12 | Excluir medição | Invalidar referências/caches; não ressuscitar valores | #311, #317 |
| AC-13 | Assinatura muda durante consulta | Reavaliar acesso; preservar dados salvos | #312, #320 |
| AC-14 | Reteste não comparável | Inconclusivo com explicação | #317 |
| AC-15 | Teclado, texto grande, VoiceOver | Jornada completa sem cortar ações | #312, #318 |

Aceite exige percurso completo e evidência de execução. Matriz de testes e rollout em [Operação](OPERACAO.md#assist-contextual-v4). Publicar documentação não encerra estas issues.

### V4.13 Decisões pendentes e fontes

| Decisão | Responsável | Condição de fechamento |
|---|---|---|
| Provedor/modelo e orçamento de consultoria | Luiz + backend | Avaliação técnica e autorização financeira antes de tráfego pago; autorizações de outros serviços não se ampliam por inferência. |
| API/autenticação | Backend | Inspeção e homologação reais; comentário no app não basta. |
| Free/Plus da modalidade | Luiz | Mapeamento explícito preservando direitos atuais. |
| Retenção/processadores | Luiz + privacidade | Configuração, política pública e consentimento coerentes. |
| Consultoria no Mac | Produto + QA | Interface, autenticação e ferramentas homologadas. |
| Ofertas | Produto + backend | Cobertura, atualização e condições verificáveis. |

Pendências não impedem contratos e testes locais; impedem ativar ou anunciar o que delas depende. #310 permanece aberta enquanto gates operacionais não estiverem comprovados.

**Referências do documento de origem (registradas em 09/10/2026; conferir requisitos vigentes antes de ativar):**

- V4-R1: [Governança](GOVERNANCA.md), autoridade e incorporação nas quatro fontes.
- V4-R2: [Anthropic — Building effective agents](https://www.anthropic.com/engineering/building-effective-agents).
- V4-R3: [Apple — App Review Guidelines, 5.1.2(i)](https://developer.apple.com/app-store/review/guidelines/).
- V4-R4: issues de UI #312/#319 e protótipos referenciados nelas; reconstruções não certificam runtime.
- V4-R5: [OWASP — Prompt Injection](https://genai.owasp.org/llmrisk/llm01-prompt-injection/).

Fontes externas embasam práticas e restrições; não certificam o Linka. Nenhum código, política comercial, endpoint ou configuração de produção é alterado por esta integração documental.
