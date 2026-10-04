# Workflow da Squad — Linka

Este documento descreve a esteira operacional do Linka no **Codex**. A autoridade de governança continua em [`AGENTS.md`](../AGENTS.md). Os agentes nativos do projeto são definidos em `.codex/agents/`.

A voz do produto é definida em [`documentacao/PRODUTO.md`](../documentacao/PRODUTO.md).

> **Direção de voz:** o Linka fala menos e se posiciona mais. Se uma frase puder ser removida sem prejudicar o entendimento, remova.

## Quem faz o quê

- **Codex principal** — orquestra, conversa com o Luiz, delimita escopo, integra resultados e revisa a entrega.
- **Íris** — produto, jornada, UX/UI, copy, curadoria e critérios de aceite. Somente leitura.
- **Camillo** — Principal Engineer transversal: arquitetura, contratos, motor, integrações Apple entre superfícies e revisão sistêmica. Escrita quando autorizada; não é o implementador obrigatório de tarefas comuns.
- **Pedro** — desenvolvedor: implementa o plano definido, escreve testes relevantes e valida o módulo tocado. Escrita somente quando delegado/autorizado.
- **Tito** — qualidade, regressão, testes, acessibilidade, segurança e revisão independente. Somente leitura por padrão.

Especialista é ferramenta de trabalho, não personagem que precisa aparecer em toda tarefa. O Codex não deve criar handoff só para cumprir rito.

---

## Passo 0 — Roteador (Codex principal)

Toda demanda é classificada antes de execução:

| Classe | Critério | Trilha |
|---|---|---|
| **Trivial** | copy, documentação, tweak visual ou bug isolado pequeno, sem tocar motor/contrato compartilhado | Fast-lane |
| **Feature** | nova capacidade, mudança de fluxo, UI + motor ou novo módulo | Full-flow |
| **Hotfix** | comportamento quebrado em produção afetando usuário | Hot-lane |
| **Rejeitar** | não melhora medir/entender/acompanhar no Apple ou exige capacidade que a plataforma não expõe | volta ao Luiz com justificativa |

Quando houver dúvida de produto, o Codex consulta **Íris**. Quando a decisão for puramente técnica e reversível, o Codex decide sem interromper o Luiz.

## Gate arquitetural

Camillo é obrigatório antes de implementar quando houver múltiplos módulos/pacotes; API; integração entre sistemas, app ↔ backend ou produtos Buildea; contrato compartilhado; schema/persistência entre componentes; alteração relevante no `LinkaEngine`; novo serviço/dependência estrutural; integração Apple em múltiplas superfícies; refatoração arquitetural; segurança/privacidade sistêmica; ou grande raio de impacto.

No hotfix, aplica-se a análise estrutural posterior prevista na Hot-lane do AGENTS.md §5; os demais limites de escopo e publicação permanecem.

Nesses casos: Produto/Íris define o comportamento → Camillo cria ou revisa o Architecture Plan → Pedro ou Codex principal implementa → Tito valida → Camillo revisa de novo apenas se a entrega materializar uma decisão arquitetural relevante. Fora desses gatilhos, o Codex principal ou Pedro pode implementar normalmente.

---

## Fast-lane

Para mudanças pequenas e reversíveis.

1. **Codex principal** delimita o problema e o aceite mínimo.
2. O **Codex principal** implementa ou delega só quando isso trouxer ganho real. Camillo só participa se o gate arquitetural for acionado ou se a revisão dele agregar confiança.
3. **Tito** é acionado quando uma revisão independente agregar confiança: comportamento, regressão, acessibilidade, medição ou contrato. Mudança puramente documental não exige Tito por rito.
4. **Codex principal** revisa o diff/evidências e relata ao Luiz.

Sem `plano.md` obrigatório, sem release notes obrigatórias e sem release automática.

---

## Full-flow

Para feature ou mudança material.

### 1. Produto — Íris

Íris devolve:

- problema real;
- comportamento esperado;
- estados relevantes;
- escopo e não-objetivos;
- critérios de aceite;
- conflitos com protótipo, Design System ou curadoria do Linka.

Íris não escolhe solução técnica só para preencher o plano.

### 2. Arquitetura — Camillo, quando o gate acionar

Camillo confronta o problema com o código e propõe:

- menor solução coerente com a arquitetura existente;
- módulos/pacotes afetados;
- contratos e persistência afetados;
- erros, cancelamento, timeout e resultado parcial;
- testes/validações necessárias;
- riscos de regressão;
- o que não será feito nesta fatia.

Mudanças em `LinkaEngine`, `NetworkCore`, `MeasurementHistory`, `NetworkInsights`, `NetworkAssist` ou contratos compartilhados recebem revisão mais profunda.

### 3. Plano — Codex principal

O Codex consolida produto + arquitetura em `.agents/plano.md` quando o gate ou o tamanho/risco justificar.

O plano deve ser curto e conter:

```text
OBJETIVO
COMPORTAMENTO ESPERADO
MUDANÇA TÉCNICA
ACEITE
NÃO-OBJETIVOS
RISCOS / VALIDAÇÃO
```

Se ainda houver decisão material de produto sem resposta, o Codex apresenta a questão ao Luiz. Não transforma dúvida de produto em suposição técnica.

### 4. Implementação — Pedro ou Codex principal

- trabalha em branch apropriada;
- implementa apenas o escopo combinado;
- preserva alterações existentes;
- escreve testes relevantes junto com a mudança;
- mantém UI e medição desacopladas;
- não quebra contrato em silêncio;
- não transforma descoberta lateral em feature nova;
- revisa o próprio diff e executa validação proporcional antes de devolver.

Pedro implementa a arquitetura decidida; não a critica nem a devolve para reabertura. Lacuna recuperável recebe a menor decisão compatível com o plano e é registrada no retorno. Contradição factual material é reportada ao Codex com evidência, sem arquitetura alternativa improvisada. Camillo pode implementar a mudança quando a investigação dele continuar naturalmente até a execução; isso não o transforma no executor obrigatório da squad. Partes independentes podem ser delegadas em paralelo apenas quando os escopos de escrita forem disjuntos.

### 5. Evaluate — Tito

Tito tenta quebrar a entrega e responde com verdict tipado:

| Verdict | Significado | Ação |
|---|---|---|
| **BLOQUEIA** | regressão, medição incorreta, quebra de contrato, risco de segurança/privacidade ou comportamento materialmente errado | volta para correção |
| **AJUSTA** | deve ser corrigido nesta entrega, mas não representa problema estrutural | Pedro ajusta dentro do plano; Camillo só entra se materializar nova decisão arquitetural |
| **ISSUE_FUTURA** | melhoria real fora do escopo atual | registra no backlog e segue |

Cobertura proporcional ao risco:

- lint/typecheck/build/testes aplicáveis;
- estados ruins de rede, timeout, cancelamento e resultado parcial;
- acessibilidade;
- fidelidade ao protótipo e Design System;
- copy/voz do produto;
- segurança/privacidade;
- fronteira UI/motor e contratos compartilhados.

**Teto de rodadas:** duas rodadas Camillo ↔ Tito para a mesma falha material. Se a segunda correção não resolver, o Codex interrompe o loop e reavalia arquitetura/escopo com Camillo e, quando relevante, Íris.

### 6. Integração — Codex principal

O Codex:

- revisa o diff final;
- confere evidências de Camillo/Tito;
- confronta a entrega com os critérios de Íris;
- diferencia o que foi testado do que não foi;
- apresenta ao Luiz riscos ou decisões restantes sem fabricar aprovação de especialista.

### 7. Merge e release

- Validação e release rodam localmente no Mac, pelo [Fastlane existente](../fastlane/Fastfile), conforme [operação](../documentacao/operacao/README.md). GitHub serve para código e PRs; não reativar Actions nem criar CI hospedada sem nova decisão do Luiz.

- Mudança material segue o gate humano definido em [`AGENTS.md`](../AGENTS.md).
- `.agents/scripts/release.sh`, TestFlight, App Store, deploy e publicação **nunca são automáticos** sem autorização explícita do Luiz.
- `RELEASE_NOTES.md`, quando necessário, descreve mudança observável para o usuário, não implementação interna.
- Antes de release relevante, revise `documentacao/PRODUTO.md`, `documentacao/features/linka-plus/README.md`, `documentacao/arquitetura/README.md` e as iniciativas ligadas em `.agents/plano.md` contra o código atual — não deixe esses documentos descrever uma fundação que o código já superou.

---

## Hot-lane

Para produção quebrada.

1. **Codex principal** define severidade, sintoma e menor escopo possível.
2. O **Codex principal** ou um delegado faz correção cirúrgica. Sem refatoração oportunista.
3. **Tito** roda a validação mínima capaz de detectar regressão relevante.
4. **Codex principal** revisa e apresenta resultado, risco residual e o que não foi testado.
5. Se o hotfix acionar o gate arquitetural, Camillo registra a análise estrutural posterior. Dívida necessária para evitar reincidência vira issue separada; não é escondida dentro do hotfix.

---

## Delegação nativa

Use os agentes em `.codex/agents/` diretamente. A skill [`delegar-subagente`](skills/delegar-subagente/SKILL.md) documenta o contrato de delegação.

Regras:

- objetivo concreto;
- escopo explícito;
- leitura por padrão;
- escrita apenas quando autorizada;
- tarefas paralelas não escrevem nos mesmos arquivos;
- não delegar tarefa vaga só para dizer que houve multiagente;
- o agente principal continua responsável por integrar e verificar o retorno.

Modelo/esforço seguem `.codex/config.toml` e [`AGENTS.md`](../AGENTS.md) §4a. Escale pela criticidade da tarefa, não pelo nome do especialista.

---

## Comunicação por artefato

Estado vive em artefatos, não em conversa simulada:

- `.agents/plano.md` — plano de mudança material;
- issue/PR/commit — decisão e escopo executado;
- verdict de Tito — `BLOQUEIA / AJUSTA / ISSUE_FUTURA` com evidência;
- `RELEASE_NOTES.md` — mudança observável para usuário.

---

## Documentação em cada entrega

Aplicar a [Governança documental](../documentacao/GOVERNANCA_DOCUMENTAL.md) em todas as trilhas: identificar fontes no início, atualizar o conteúdo impactado durante a execução e conferir links, estado e evidências antes de concluir. No PR ou retorno final, registrar documentos alterados ou justificar ausência de impacto documental, além de pendências com responsável e prazo/evento de revisão.

Fast-lane permanece sem plano ou relatório extra obrigatório. Hotfix só adia contexto complementar com pendência rastreável. Revisão de release segue os requisitos acima e não transforma build, TestFlight ou App Review em publicação.

## Regras comuns

- Não implemente antes de entender o problema.
- Não crie feature só porque é tecnicamente possível.
- Não apresente hipótese como fato.
- Mudança visual relevante é comparada com protótipo e Design System.
- Mudança no motor exige revisão de contratos, testes e consumidores.
- Especialista não aprova a própria entrega.
- Se algo não foi testado, diga que não foi testado.
- Luiz não é chamado para decidir detalhe técnico recuperável no código.
- Publicação, release, custo, segredo e operação destrutiva mantêm gate humano.

> *Uma coisa de cada vez. Termina. Valida. Integra.*
