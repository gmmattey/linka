# Produto Linka

Estado: vigente como referência de produto; implementação e validação têm alcance separado abaixo.
Responsável: Codex principal, com Íris para intenção e experiência.
Última revisão: 2026-10-04 — consolidação de visão, história relevante, voz e curadoria; leitura estática do checkout WIP.
Base: branch `feat/macos-visual-direction-and-service-status`, HEAD `9eb1a094` mais alterações locais. Não representa `main`, produção ou versão de loja.
Referências: [governança](../AGENTS.md), [processo documental](GOVERNANCA_DOCUMENTAL.md), [design](design/README.md), [interface Apple](features/interface-e-acessibilidade/README.md), [site](features/site-institucional/README.md).
Decisão desta entrega: autorização do Luiz nesta sessão para consolidar a documentação pelo WIP; fontes substituídas removidas conforme o [registro de migração](MIGRACAO.md).

## Propósito e usuário

Linka mede a qualidade da conexão e apresenta um resultado imediato, claro e visualmente refinado para quem usa iPhone, iPad ou Mac. A pessoa deve conseguir medir sem dominar conceitos de telecomunicações, escolher modo ou servidor, criar conta ou passar por onboarding obrigatório.

O fluxo principal é **abrir → iniciar medição → ver resultado → repetir**. A medição começa por ação explícita; abrir o app não é autorização para um teste pesado. Comandos e integrações Apple podem expressar essa ação. A Home também tem leitura viva: observação de rede não equivale a velocidade medida continuamente.

O número medido é protagonista durante a medição e no resultado. Histórico, interpretação e ações especializadas ajudam a entender ou acompanhar a conexão em camadas secundárias. Minimalismo não autoriza reduzir a qualidade do motor, esconder erro ou inventar dados.

## História que orienta o produto

O projeto começou quando Giam precisava acessar o próprio modem e não lembrava a senha. A investigação doméstica cresceu para ferramentas de rede e teste de velocidade. A trajetória Linka → Velu → SignallQ trouxe interpretação e diagnóstico; o aprendizado foi que acumular capacidades pode esconder a pergunta que a pessoa veio resolver.

Em 2026, Linka retomou o foco na medição e no ecossistema Apple. O histórico de PWA e a divisão antiga “Linka só mede, SignallQ interpreta” explicam decisões da época, mas não definem o produto atual. SignallQ tem direção Android/Web; Linka pode incorporar interpretação tecnicamente viável no Apple com curadoria. Acesso ao roteador continua no escopo por resolver a necessidade que originou o produto.

Essa história é contexto humano registrado nas fontes anteriores, não evidência de disponibilidade, datas de release ou validação técnica. A experiência de Giam com telecomunicações e jornadas de atendimento explica a prioridade de traduzir informação técnica em algo utilizável; não é alegação de certificação da medição.

## Curadoria e limites

Pergunta de entrada: **isso melhora medir, entender ou acompanhar a conexão no Apple sem competir com o resultado?**

| Regra | Consequência prática |
|---|---|
| Medir vem primeiro | Assist, anúncios e conteúdo secundário não atrasam, cobrem ou substituem a medição. |
| Divulgação progressiva | Métricas auxiliares, metodologia e interpretação aparecem em detalhes quando ajudam. |
| Viabilidade Apple | Sem dado exposto pela plataforma, declarar indisponibilidade; não fabricar RSSI, topologia ou causa raiz. |
| Dado real | Ausência, zero e erro têm significados diferentes. Resultado parcial válido continua visível. |
| Foco | Histórico, comparação, ambientes, DNS e Assist têm de justificar a jornada; sua existência no código não autoriza expandi-los. |
| Limite de plataforma | Produto Apple nativo. Site institucional apresenta o app; não é speed test Web, PWA ou versão Android. |
| Roteador | Encontrar o gateway atual e abrir seu painel; credencial guardada a pedido da pessoa, com possibilidade de remoção. Não virar inventário genérico de dispositivos. |
| Privacidade | Coletar apenas o necessário; não prometer anonimização, retenção, ausência de compartilhamento ou funcionamento local sem conferência da implementação. |

O motor é separado da interface. Simulações do protótipo não podem substituir medição em produção. Regras determinísticas confiáveis precedem interpretação quando aplicável; IA não cria evidência. Linka não certifica a velocidade contratada nem conclui responsabilidade do provedor só por observar desempenho ruim.

## Voz e copy

A voz é curta, objetiva, segura e calma. Remover uma frase quando isso não prejudicar compreensão ou controle. Usar linguagem comum, verbos diretos e títulos claros; não narrar artificialmente cada passo nem transformar telas em argumento de venda.

Preferir `Preparando`, `Download`, `Upload`, `Finalizando`, `Detalhes`, `Testar novamente`, `Como medimos`. Erro diz o que aconteceu e oferece recuperação. Evitar frases rotativas, entusiasmo artificial, promessas como “ótima para qualquer tarefa” e linguagem de diagnóstico sem evidência. Termos adicionais ficam nos detalhes. Números e unidades devem respeitar o idioma efetivo; o texto antigo limitado a pt-BR não descreve todas as opções atuais.

O primeiro resultado deve privilegiar a medida. Interpretação fica em camada secundária e só afirma o que os dados sustentam. Páginas institucionais podem explicar mais, com título claro, parágrafo inicial curto, fatos e sem repetir o posicionamento a cada seção.

Antes de publicar copy: a pessoa precisa ler? Pode ser menor? É fato? O código sustenta a promessa? A interpretação tem evidência e está no lugar certo?

## Comportamento observado e expectativa

As URLs esperadas de marketing, suporte, privacidade e termos para App Store Connect estão centralizadas no [site institucional](features/site-institucional/README.md), junto da origem usada por `LinkaExternalLinks`. São valores documentais e de código; não atestam preenchimento atual do portal Apple nem disponibilidade pública da ficha. A fonte anterior `documentacao/features/site-institucional/README.md` é absorvida ali.

| Área | Evidência estática no WIP | Limite desta conclusão |
|---|---|---|
| Entrada Apple | `LinkaApp` escolhe `MainView` ou `MacMainView`; rotas e modais documentados na [interface](features/interface-e-acessibilidade/README.md). | Presença de código não confirma execução, acessibilidade ou distribuição. |
| Medição e Home | `MainView` distingue idle, medição, resultado, erro e troca de conexão; recebe estado de `SpeedTestViewModel`. | Esta revisão não audita a metodologia nem mede precisão. |
| Acompanhamento | Histórico distingue zero, uma e múltiplas medições; Assist, Otimização e Ajustes estão alcançáveis. | Entitlements, promoção e disponibilidade remota exigem conferência própria. |
| Comunicação pública | Landing e páginas informativas são implementadas em React; veja [site](features/site-institucional/README.md). | Copy pública não é prova de política efetivamente praticada ou disponibilidade de loja. |

## Critérios de aceite e evidência

| ID | Resultado esperado | Conferência em 2026-10-04 |
|---|---|---|
| PROD-01 | Uma pessoa inicia medição sem modo prévio ou cadastro obrigatório. | Fluxo estático mapeado; jornada no app não executada. |
| PROD-02 | Resultado real, parcial e indisponível não se confundem; interpretação não substitui a medida. | Critério de produto preservado; validação de todas as fases e consumidores não executada. |
| PROD-03 | Copy e design distinguem dado, inferência e ausência de evidência. | Regras consolidadas; revisão de todas as strings/localizações pendente. |
| PROD-04 | Web comunica e encaminha ao app, sem medir. | Roteamento e componentes principais lidos; não houve build, navegador ou inspeção de produção. |

## Pendências e substituição

| Origem anterior | Destino consolidado | Tratamento |
|---|---|---|
| `documentacao/PRODUTO.md` | Este documento e [interface](features/interface-e-acessibilidade/README.md) | Início automático e veto absoluto a interpretação não foram promovidos a regra atual. |
| `documentacao/PRODUTO.md` | História acima | Preservado o contexto relevante; biografia extensa não se torna requisito. |
| `documentacao/PRODUTO.md` | Voz e copy acima | Mantida a intenção; não atesta auditoria de todas as traduções. |
| `documentacao/features/site-institucional/README.md` | [Site institucional](features/site-institucional/README.md) | URLs esperadas e gate de conferência preservados, sem afirmar atualização no portal. |
| `documentacao/design/README.md` | [Design](design/README.md) | Decisão e limites da auditoria histórica preservados separadamente da evidência atual. |

| Pendência | Responsável | Evento | Fechamento |
|---|---|---|---|
| Conferir alinhamento de resultado/Assist/copy com o produto | Íris e Tito, acionados pelo orquestrador | Próxima mudança visual ou release relevante | Build identificada, destinos e estados exercitados, divergências registradas. |
| Disponibilidade e monetização | Orquestrador | Antes de afirmação pública/release | Código, política comercial e versão candidata confrontados; nenhum preço ou promoção inferido desta documentação. |

Nenhum plano foi marcado entregue. Não foram executados testes, build, simulador, aparelho físico, publicação ou consulta de loja nesta consolidação.
