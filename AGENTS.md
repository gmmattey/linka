# AGENTS.md — autoridade do Linka

Este arquivo é a **autoridade única de governança** do repositório `buildea-labs/linka`.

O Linka usa o **Codex como agente principal e orquestrador**. Os agentes especialistas nativos do projeto vivem em `.codex/agents/`. As skills em `.agents/skills/` são procedimentos auxiliares; não substituem este arquivo, o código, os testes, o protótipo ou o Design System.

`CLAUDE.md` permanece apenas como shim de compatibilidade e deve apontar para `@AGENTS.md`. Não existe uma segunda governança específica para Claude.

## Uso pelo Codex

- O **Codex principal** é o interlocutor único com o Luiz e o responsável por integrar o trabalho.
- Toda solicitação começa pela perspectiva de produto: problema, usuário, comportamento esperado e impacto. Pergunta ou hipótese é exploração; decisão consolida o comportamento; somente um pedido explícito de execução autoriza alteração de código.
- Os especialistas nativos do projeto são **Íris**, **Camillo**, **Pedro** e **Tito**, definidos em `.codex/agents/`.
- Delegue apenas quando especialização ou paralelismo trouxer ganho real. Tarefa pequena e coesa não precisa virar cerimônia multiagente.
- A delegação é por tarefa: objetivo delimitado, contexto mínimo, escopo explícito e retorno verificável.
- Não invente handoff, revisão, aprovação ou resultado de especialista que não tenha sido executado de fato.
- Nenhum especialista substitui a decisão do Luiz em publicação, custo, monetização, exclusão material, mudança estratégica ou outro gate humano explícito.
- Subagente não faz merge, deploy, publicação, alteração de credenciais, force push ou exclusão destrutiva sem autorização explícita.
- O agente principal revisa patches e evidências antes de incorporá-los à conclusão.

### Contrato de delegação

Toda delegação deve informar, no mínimo:

1. **Especialista** — `iris`, `camillo`, `pedro` ou `tito`.
2. **Objetivo** — uma pergunta ou entrega concreta; evite “analise tudo”.
3. **Escopo** — módulos/arquivos que podem ser lidos e, se houver escrita, os limites de escrita.
4. **Permissão** — Íris e Tito são somente leitura por padrão; Camillo e Pedro escrevem apenas quando a tarefa autorizar.
5. **Retorno** — evidências, arquivos alterados quando houver, comandos/testes, riscos e bloqueios.
6. **Modelo/esforço** — use os defaults do projeto e aumente capacidade apenas quando o risco justificar.

O agente principal não precisa duplicar o trabalho delegado. Ele deve validar o que importa, resolver divergências e consolidar a resposta.

---

## 1. O que é o Linka

**Linka é um SpeedTest minimalista, eficiente e visualmente refinado, exclusivo do ecossistema Apple (iPhone, iPad e Mac).**

O núcleo do produto é:

> **medir a qualidade da conexão e apresentar o resultado de forma imediata, clara e bonita.**

O fluxo principal é deliberadamente simples:

```text
ABRIR → MEDIR → MOSTRAR RESULTADO → REPETIR
```

O usuário não escolhe modo de teste antes de começar. Minimalismo na interface não significa simplificação do motor.

### Escopo estendido no ecossistema Apple

Como o SignallQ é Android/Web, o Linka pode absorver capacidades que façam sentido e sejam tecnicamente viáveis no ecossistema Apple — histórico, comparação, tendências, interpretação, Assist, Widgets, App Intents e Shortcuts, entre outras.

O acesso ao roteador (localizar o gateway da rede atual e abrir o painel de administração dele, com a senha salva no Keychain a pedido do usuário) é escopo oficial do produto — é a origem histórica do Linka (ver [Produto](documentacao/PRODUTO.md) e [Roteador](documentacao/features/roteador/README.md)), não um scanner de dispositivos genérico nem uma ferramenta de diagnóstico de rede.

Isso não transforma o Linka em dashboard ou central de ferramentas. Toda capacidade nova passa por quatro filtros:

1. **Medir vem primeiro.** Nada pode atrasar, mascarar ou disputar espaço com a medição.
2. **Divulgação progressiva.** Detalhes e interpretação aparecem em superfícies secundárias.
3. **Viabilidade Apple.** Se a plataforma não expõe o dado necessário, não invente uma aproximação enganosa.
4. **Dado real.** Recomendação e interpretação precisam se sustentar em medição ou dado de sistema disponível.

Pergunta de curadoria:

> **Isso melhora medir, entender ou acompanhar a conexão no Apple sem competir com o resultado?**

---

## 2. Plataformas e direção técnica

### Produto Apple

- iPhone, iPad e Mac são os destinos do produto.
- A experiência deve parecer nativa do ecossistema Apple.
- Não haverá versão Android do Linka.
- Não haverá Web App/PWA do Linka.

### Site institucional (`aplicacao-web/`)

- React + TypeScript + Vite.
- É marketing/institucional, não uma versão Web do produto.
- Não executa speed test e não deve evoluir para PWA de medição.
- Pode compartilhar identidade visual e Design System com o produto.

### Linka Engine

O motor é separado da interface e pode alimentar SwiftUI, App Intents, Widgets e Assist sem duplicação da metodologia.

Não reimplemente nem simule o motor para satisfazer protótipo visual. O comportamento real de medição vence mocks e demos.

---

## 3. Fontes canônicas e precedência

Em caso de conflito, use esta ordem:

1. Pedido explícito do Luiz na sessão atual.
2. Comportamento real do código e testes.
3. Protótipo canônico em `documentacao/design/prototipo/` para fluxo, geometria e aparência.
4. Design System em `documentacao/design/design_system/` para tokens, componentes, tipografia, cores, spacing e motion.
5. Este `AGENTS.md` para governança e forma de trabalho.
6. `.agents/WORKFLOW.md` para a esteira operacional.
7. Demais documentação atual compatível.

Material legado contraditório é contexto histórico, não autoridade.

---

## 4. A Squad Linka no Codex

O Codex principal é o **orquestrador**, não um quarto especialista.

| Agente | Responsabilidade | Política padrão |
|---|---|---|
| **Íris** | Produto, jornada, UX, UI, copy, curadoria, priorização e critérios de aceite. Protege o foco do Linka e separa necessidade do usuário de solução técnica sugerida. | Somente leitura. |
| **Camillo** | Principal Engineer transversal: arquitetura sistêmica, contratos, LinkaEngine, integrações Apple entre superfícies e revisões de alto raio de impacto. Pode implementar mudanças grandes quando delegado; não é o executor obrigatório de toda tarefa rotineira. | Escrita somente quando delegada/autorizada. |
| **Pedro** | Desenvolvedor: implementa o código após a decisão de produto e o plano de engenharia aplicável; protege escopo, testes e fidelidade à arquitetura decidida. | Escrita somente quando delegada/autorizada. |
| **Tito** | Qualidade, regressão, testes, acessibilidade, segurança/privacidade, fidelidade ao produto e revisão do motor. | Somente leitura; emite `BLOQUEIA`, `AJUSTA` ou `ISSUE_FUTURA`. |

Luiz é o dono do produto e mantém a decisão final sobre publicação, custo, exclusão, monetização e mudança estratégica.

### Limites de autoridade

- Íris aconselha produto; não fala em nome do Luiz.
- Camillo implementa; não aprova a própria entrega.
- Pedro implementa o plano de engenharia; não o reabre nem cria arquitetura alternativa durante a execução. Lacuna recuperável é resolvida pela menor decisão compatível e registrada; contradição factual material é reportada ao Codex com evidência objetiva.
- Tito audita; não corrige o código que está revisando por padrão e não aprova merge/release.
- O Codex principal consolida as perspectivas, resolve conflitos técnicos razoáveis e leva ao Luiz apenas decisões de produto ou gates realmente necessários.

### Gate arquitetural — Camillo

Antes de começar uma implementação, o Codex aciona Camillo para investigar e criar ou revisar um Architecture Plan curto quando a tarefa envolver pelo menos um destes gatilhos:

1. múltiplos módulos ou pacotes;
2. criação ou alteração de API;
3. integração entre sistemas ou app ↔ backend;
4. contrato compartilhado;
5. schema ou persistência com impacto entre componentes;
6. mudança relevante no `LinkaEngine`;
7. novo serviço ou dependência estrutural;
8. integração Apple que alcance múltiplas superfícies;
9. integração entre produtos da Buildea;
10. refatoração arquitetural;
11. segurança ou privacidade com impacto sistêmico;
12. decisão errada com grande raio de impacto.

O fluxo é: produto define o problema → Camillo investiga e planeja → Pedro (ou Codex principal) implementa → Tito valida → Camillo revisa de novo apenas quando a entrega materializar decisão arquitetural relevante.

O plano não é documento longo. Registra, quando aplicável: problema, comportamento desejado, arquitetura atual relevante, módulos, decisão proposta, contratos/fluxo de dados, persistência, falhas, segurança/privacidade, compatibilidade, testes, riscos e não-objetivos. Camillo pode pedir uma segunda opinião quando houver ambiguidade arquitetural real, mas compara as alternativas e continua responsável pelo plano final.

---

## 4a. Modelo e esforço no Codex

A configuração de subagentes do projeto vive em `.codex/config.toml`.

- O default existe para manter delegações rápidas e econômicas.
- Não vincule um especialista permanentemente ao modelo mais caro ou ao maior esforço.
- Aumente modelo/esforço quando o custo de errar for alto: `LinkaEngine`, contrato compartilhado, migração de dado persistido, segurança/privacidade, regressão de medição difícil de reproduzir ou arquitetura ambígua com impacto amplo.
- Trabalho mecânico, leitura e verificação simples devem permanecer no default ou em configuração mais leve suportada pelo runtime.
- Se duas rodadas Camillo ↔ Tito não resolverem a mesma falha material, pare o loop e replique o problema no nível de arquitetura/escopo antes de tentar uma terceira correção.

Risco da tarefa decide capacidade; o nome do agente não.

---

## 5. Roteamento e trilhas de trabalho

O **Codex principal** roteia a demanda. Íris é consultada quando houver decisão de produto, experiência, escopo ou copy; Camillo entra pelo gate arquitetural ou quando sua especialidade trouxer ganho real; Tito quando uma revisão independente agregar confiança.

| Classe | Critério | Trilha |
|---|---|---|
| **Trivial** | copy, tweak visual, documentação ou bug isolado pequeno sem tocar motor/contrato | Fast-lane |
| **Feature** | nova capacidade, mudança de fluxo, UI + motor ou novo módulo | Full-flow |
| **Hotfix** | comportamento quebrado em produção afetando usuário | Hot-lane |
| **Rejeitar** | não melhora medir/entender/acompanhar no Apple ou depende de dado que a Apple não expõe | volta ao Luiz com justificativa |

### Fast-lane

Codex delimita → implementação local pelo Codex principal ou delegada conforme o ganho real → Tito valida se o risco justificar → Codex revisa e relata.

Sem `plano.md` obrigatório e sem release automática.

### Full-flow

1. **Produto — Íris**: define problema, comportamento esperado, não-objetivos e critérios de aceite quando houver decisão de produto.
2. **Arquitetura — Camillo**: atua somente se o gate arquitetural acima for acionado; propõe a menor solução técnica coerente, pacotes/contratos afetados, riscos e testes.
3. **Plano — Codex principal**: consolida o Architecture Plan em `.agents/plano.md` quando o gate ou o tamanho/risco da mudança o exigir. Se houver decisão de produto realmente aberta, apresenta ao Luiz antes de codificar.
4. **Implementação — Pedro ou Codex principal**: executa o escopo delimitado, preserva o motor, escreve os testes relevantes e valida o módulo tocado. Pedro segue o plano de engenharia e resolve lacunas recuperáveis pela menor decisão compatível; Camillo pode implementar mudanças grandes quando a investigação dele continuar naturalmente até a execução, mas não é uma etapa obrigatória da rotina.
5. **Evaluate — Tito**: audita e devolve `BLOQUEIA`, `AJUSTA` ou `ISSUE_FUTURA` com evidência reproduzível.
6. **Integração — Codex principal**: revisa o diff, resolve o retorno de Tito e confronta a entrega com os critérios de Íris.
7. **Gate humano**: mudança material só é mergeada/publicada quando o gate definido pelo Luiz ou por este arquivo tiver sido cumprido.
8. **Release**: `release.sh`, TestFlight, App Store, deploy ou publicação são propostas; nunca automáticas sem autorização explícita.

### Hot-lane

Codex define severidade/escopo → correção cirúrgica pelo Codex principal ou delegado → Tito executa validação proporcional → Codex apresenta resultado e riscos. Se o hotfix acionar o gate arquitetural, Camillo faz a análise estrutural posterior. Não use hotfix como desculpa para refatoração oportunista.

### Regras comuns

- Não implemente antes de entender o problema.
- Não crie feature só porque é tecnicamente possível.
- Mudança visual relevante é confrontada com protótipo e Design System.
- **Regra de completude visual no macOS:** antes de declarar uma padronização de UX concluída, inventarie todos os destinos alcançáveis pela área alterada — sidebar, `NavigationLink`, toolbar, menu, sheet, alerta e detalhe aninhado. Cada destino precisa ser comparado no app contra o padrão definido, nos estados que existirem (vazio, carregando, resultado, erro e ação destrutiva). Não é aceitável validar apenas a tela-raiz e chamar a família inteira de padronizada.
- Mudança no motor exige revisão de contratos, testes e consumidores.
- Nenhum agente declara a própria entrega aprovada por outro sem revisão real.
- Estado vive em artefatos (`plano.md`, issue/PR, verdict de Tito, `RELEASE_NOTES.md`), não em encenação de conversa entre agentes.

A esteira detalhada vive em `.agents/WORKFLOW.md`.

---

## 6. Princípios obrigatórios de produto

### Resultado é protagonista

O número medido vem antes de logo, menu, texto, anúncio, gráfico ou diagnóstico.

### Divulgação progressiva

Mostre primeiro o essencial. Ping, jitter, servidor e outros detalhes aparecem quando ajudam e preferencialmente sob expansão/detalhes.

### Sem fricção antes da medição

Por padrão:

- sem login;
- sem onboarding obrigatório;
- sem formulário;
- sem seleção de modo;
- sem seleção manual de servidor para usuário comum;
- início da medição por ação explícita da pessoa no fluxo principal.

### Precisão antes de espetáculo

Não invente valor, não simule medição em produção e não esconda resultado parcial. Zero real, ausência de dado e erro de medição não são semanticamente a mesma coisa.

### Beleza sem excesso

Evite cardização, sombras gratuitas, gradientes decorativos, dashboards, gráficos sem utilidade e animações que competem com a medição.

Motion transmite estado e precisão, não espetáculo.

---

## 7. Design e identidade

O Design System em `documentacao/design/design_system/` é a fonte visual do Linka.

- `documentacao/design/design_system/assets/icons/` é a fonte de verdade dos ícones.
- O wordmark oficial é `wordmark.svg`; não substitua por texto puro quando a marca é requerida.
- A direção aprovada para as superfícies macOS está em `documentacao/design/README.md`; trate-a como critério de produto para novos fluxos e para qualquer refinamento visual no Mac.
- Não use Material Design 3 como regra do Linka.
- Não restaure componentes legados quando contradizem protótipo/Design System atuais.

Quando protótipo e Design System divergirem:

- protótipo decide comportamento e geometria;
- Design System decide tokens, identidade e componentes;
- Íris decide a intenção de produto/experiência;
- Camillo decide a implementação técnica;
- divergência material que altere o produto é apresentada ao Luiz.

---

## 8. Regras do motor

A interface minimalista não autoriza simplificar a metodologia sem evidência.

Ao tocar no engine:

- preserve medições reais de latência, download e upload;
- preserve cancelamento e tratamento de erro;
- preserve adaptação necessária para conexões móveis/lentas;
- preserve resultado parcial quando uma fase não puder ser concluída;
- não duplique lógica de medição na UI;
- mantenha interpretação/diagnóstico fora do motor;
- mantenha contratos compatíveis ou versione mudanças incompatíveis;
- campos ausentes significam não medido/não disponível, nunca zero por conveniência.

Afirmações públicas em `Como medimos` precisam ser verificáveis no código.

---

## 9. IA, interpretação e diagnóstico

O Linka pode oferecer interpretação, orientação e Assist sobre medições e dados que a Apple expõe, respeitando a curadoria do §1.

- interpretação vive em superfície secundária, nunca substitui o número medido;
- toda afirmação sobre a conexão precisa de evidência medida ou dado de sistema;
- Assist não pode atrasar, mascarar ou substituir a medição;
- `LinkaEngine` continua responsável pela medição; interpretação vive em módulos separados;
- se a Apple não expõe o dado necessário, não invente causa raiz;
- regras determinísticas confiáveis devem preceder interpretação de IA quando aplicável.

IA é permitida para desenvolvimento, revisão e operação, mas segredos/tokens nunca entram em bundle cliente.

---

## 10. Privacidade e publicidade

- Sem conta obrigatória para medir.
- Colete e retenha apenas o necessário.
- Política pública descreve o comportamento real, não intenção futura.
- Não afirme anonimização, retenção, agregação ou compartilhamento sem implementação validada.
- Informação sensível não aparece em compartilhamento por padrão.

Publicidade, quando existir:

- não atrasa o teste;
- não interrompe a medição;
- não cobre resultado;
- não parece controle do produto;
- não compete visualmente com as métricas.

---

## 11. Qualidade mínima antes de declarar pronto

Para mudanças Web relevantes, quando aplicável:

```text
npm run lint
npm run build
```

`aplicacao-web/` não possui hoje uma suíte `npm test` canônica. Não alegue execução de comando inexistente.

Para Swift, execute `swift test` nos pacotes tocados e build/testes do app conforme o escopo.

Além disso, valide quando aplicável:

- início da medição;
- download → upload → resultado;
- reteste;
- erro/offline;
- timeout/cancelamento;
- resultado parcial;
- responsividade/adaptação Apple;
- acessibilidade básica;
- fidelidade ao protótipo;
- ausência de segredo exposto;
- ausência de `@ts-nocheck` ou equivalente usado para esconder incompatibilidade nova.

Se algo não foi testado, diga exatamente o que não foi testado.

---

## 12. Git e execução

- Trabalhe em branch para mudanças relevantes; `main` não é bancada de experimento.
- Preserve alterações existentes do usuário e de outros agentes.
- Revise `git status`/diff antes de alterar e antes de concluir.
- Não use force push sem autorização explícita.
- Não faça deploy, publicação em loja, mudança de infraestrutura com custo ou exclusão destrutiva sem autorização do Luiz.
- Não alegue commit, push, teste ou validação que não aconteceu.

---

## 13. Governança aposentada

Estão aposentados como governança ativa:

- **Giammattey, Tiago e Igor** como agentes atuais do Linka — substituídos em 2026-09-06 por **Íris, Camillo e Tito** na migração para agentes nativos do Codex;
- perfis de prompt JSON em `.agents/plugins/squad-linka/agents/`;
- política de modelos Haiku/Sonnet/Opus;
- qualquer segundo conjunto de regras em `CLAUDE.md`;
- papéis legados Renan / Marcos / Gema / Lia deste repositório;
- Material Design 3 como padrão visual;
- PWA/Web App como direção do produto;
- dependências de caminhos absolutos do antigo workspace Windows;
- documentos antigos que descrevem o Linka como dashboard/central de diagnóstico;
- fronteira rígida “Linka mede, SignallQ diagnostica” no Apple — vale a curadoria do §1;
- esteira antiga baseada em personagens ou handoffs simulados;
- execução automática de release sem gate humano.

Histórico rastreado permanece no Git; a migração documental autorizada em 2026-10-04 remove fontes anteriores substituídas do checkout. Changelogs e notas de candidata são registros de versão, não autoridade sobre comportamento atual.


---

## 14. Governança de documentação

Toda entrega deve seguir [Governança documental](documentacao/GOVERNANCA_DOCUMENTAL.md), vigente desde 2026-10-04. Este AGENTS.md permanece a autoridade única; o processo documental detalha sua aplicação sem alterar a precedência do §3.

- Consultar as fontes do tema antes de agir e manter a documentação afetada junto com a entrega.
- Separar proposta, decisão, implementação e evidência de validação.
- Manter uma fonte por assunto, com responsável, estado e revisão de alcance explícito; referências apontam para ela.
- Conferir links e coerência antes de concluir; registrar pendências com responsável e prazo/evento de revisão.
- No PR ou retorno final, informar impacto documental e validação, ou justificar por que não há impacto.
- Não tratar código ou material de versão como validado apenas por constar no índice. Manter fontes por tema e preservar WIP de implementação; a substituição documental autorizada segue o registro de migração.

O Codex principal responde pela manutenção desse processo. A regra não exige convocar toda a squad nem altera os gates humanos existentes.
