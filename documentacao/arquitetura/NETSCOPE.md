# Netscope — decisões, contrato proposto e pendências

Estado: rascunho — proposta arquitetural consolidada; integração e operação não verificadas neste checkout.
Responsável: Codex principal; Camillo por contrato/segurança; Luiz pelos gates de produto, privacidade e custo.
Última revisão: 2026-10-04 — preservação integral da substância do plano WIP e contraste com a composição local.
Base: branch `feat/macos-visual-direction-and-service-status`, HEAD `9eb1a094` + WIP, não main/produção.
Referências atuais: [arquitetura](README.md), [Assist](../features/assist/README.md), [AssistContainer](../../aplicativo-ios/LinkaApp/Sources/Adapters/AssistContainer.swift), [governança](../GOVERNANCA_DOCUMENTAL.md).
Origem: conteúdo não rastreado de `documentacao/arquitetura/NETSCOPE.md`, datado de 2026-09-22, preservado abaixo para não perder contrato, segurança, retenção, fases ou gates após a remoção do original pelo orquestrador.

## Estado observado e como interpretar este documento

O app deste checkout compõe Assist via relay/NDS V2. A busca por Netscope nos fontes Swift de LinkaApp e LinkaModules não encontrou composição cliente. Outras worktrees e o backend externo não foram auditados: este documento não afirma que repositório, Worker, D1 ou provider existem ou deixam de existir fora desta base. Nenhum endpoint foi chamado, nenhum teste/build/deploy foi executado.

O registro abaixo preserva a proposta original e suas revisões parciais. Verbos no futuro, nomes de PR e requisitos são expectativas, não entregas. O status de aprovação de planejamento abaixo é uma declaração da fonte histórica; não é nova aprovação de implementação, cobrança ou ativação. As contradições identificadas nesta consolidação têm precedência como pendências explícitas, sem resolução silenciosa.

## Conflitos e decisões ainda abertas

| Item | Fontes conflitantes / limite | Responsável e evento | Critério de fechamento |
|---|---|---|---|
| Uso por confiança/instalação | Decisão 1.8 propõe cota inferior sem App Attest; §§6.1, 6.2 e 12 proíbem quota por instalação/trust tier e §13 mantém decisão Mac pendente | Camillo + Luiz, antes do contrato/rollout dependente | Formalizar integridade técnica separada de acesso de produto, sem cota inferior herdada |
| Allowlist | §11 menciona beta allowlist; §12 explicitamente não impõe allowlist | Codex + responsável backend, antes do canário | Critério de canário compatível com política vigente, sem criar gate por pessoa |
| Estados | Experiência lista quatro estados; §11 cita seis e outras seções mencionam limite de uso | Íris + Camillo, antes de congelar UI/OpenAPI | Enum e erro operacional coerentes, sem inventar estado de rate limit de produto |
| Contrato V1 | OpenAPI externo é declarado fonte, mas não está incorporado nem verificado aqui; exemplos não são fixtures aprovadas | Camillo, antes de implementar consumidor | Conferir versão/commit externo, request/response, erros e testes de contrato |
| Provedores | Workers AI é candidato inicial; providers externos/adapters e orçamento são proposta | Luiz + operador backend, antes de egress/custo | Autorização rastreável, avaliação, kill switch e teto global testados |
| Retenção e D1 | Prazos de 90 dias, 30–90 e 7–30 são propostas, não comprovação de jobs implementados | Responsável backend + Codex, antes de tráfego real | Schema, limpeza executável, evidência e política pública concordantes |
| Gates históricos | Criação do repo, domínio, Mac, privacidade, custo e marca constam pendentes na fonte | Codex + Luiz, antes da ação correspondente | Reconciliar com evidências atuais sem pedir de novo autorização já documentada |
| Plano versus implementação | Não há cliente composto nesta base examinada | Camillo + Tito, próxima integração Netscope | Diff cliente, OpenAPI, testes locais/contrato e evidência física separada |

## Critérios de aceite da consolidação

- NS-DOC-01: conservar propósito, isolamento, rotas, campos, semântica de ausência, autenticação, anti-replay, orçamento global, privacidade, fases e gates da fonte.
- NS-DOC-02: manter pendências conflitantes explícitas; nenhuma fase L/A/R ganha estado concluído por existir neste documento.
- NS-DOC-03: separar inspeção local de funcionamento externo, dispositivo, TestFlight e produção.

Evidência de 2026-10-04: comparação textual do conteúdo preservado com a fonte e leitura da composição local; nenhum teste de runtime executado. A validação futura de cada fase continua descrita no registro, com Camillo responsável por contrato e Tito por evidência de execução antes da integração/ativação pertinente.

---

## Registro completo de decisões e expectativas de origem

### Proposta V1 registrada em 2026-09-22

**Status:** decisão de arquitetura aprovada para planejamento; nenhuma infraestrutura, domínio, segredo, repositório ou deploy foi criado por este documento.

**Data:** 22 de setembro de 2026
**Produto consumidor:** Linka (iPhone, iPad e Mac)
**Capacidade:** Netscope — interpretação remota e baseada em IA de uma medição do Linka.

## 1. Decisões consolidadas

1. Netscope é uma capacidade exclusiva do Linka nesta V1. Não atende SignallQ e não importa nem executa as regras legadas de NDS/Assist.
2. A medição continua local e protagonista no Linka. Netscope é uma superfície secundária, acionada após existir resultado real.
3. O endpoint público será `https://api.signallq.com/v1/linka/*`. O domínio compartilhado é apenas endereço de infraestrutura; não implica compartilhamento de código, dados ou confiança com SignallQ.
4. O serviço será um **novo Cloudflare Worker**, com **D1 exclusivo**, secrets exclusivos, CI exclusivo e painel administrativo separado.
5. Será criado um **novo repositório GitHub privado**, provisoriamente chamado `netscope-api`, no mesmo proprietário do repositório Linka. Ele não será uma pasta de `linka/ios`.
6. A IA interpreta somente um snapshot permitido de fatos observados. Ela não mede, não altera o resultado local, não inventa evidência e não transforma ausência/falha em “rede boa”.
7. Workers AI será o primeiro provedor elegível. OpenAI, Gemini e Grok entram como adaptadores desligados até haver orçamento, avaliação de qualidade e autorização para ativação.
8. App Attest será usado quando disponível em iPhone/iPad. macOS e dispositivos sem suporte terão nível de confiança e cota inferiores; não existe fallback equivalente silencioso.

## 2. Problema e resultado esperado

Hoje uma mesma medição pode produzir uma indicação local de uso ruim para vídeo/jogos e um Assist remoto que diz que está tudo normal. Isso é contraditório porque os sistemas não compartilham o mesmo contrato de evidência nem a mesma semântica de insuficiência.

O Netscope deve receber a evidência que o Linka efetivamente observou e devolver uma leitura explícita sobre aquela medição:

- o que os dados sustentam;
- quais dados foram usados;
- o que não pode ser concluído;
- a próxima ação possível, quando houver;
- estado distinto para `inconclusive`, indisponibilidade e limite de uso.

Não é objetivo da V1 afirmar causa raiz de ISP, roteador ou dispositivo sem evidência compatível, corrigir a rede, criar chat ilimitado, centralizar diagnósticos de outros produtos ou persistir histórico bruto de rede.

## 3. Experiência de produto

O primeiro resultado do teste não muda: métricas e decisão local aparecem imediatamente. Depois, o usuário pode tocar em **“Entender esta medição”** e abrir o Netscope.

Na interface, a capacidade pode ser apresentada como **Netscope**; o texto de apoio deve ser direto: **“Uma leitura baseada nos dados medidos.”** A expressão “com IA” é transparência secundária, não promessa no primeiro frame.

Estados obrigatórios:

| Estado | Mensagem esperada | Ação |
|---|---|---|
| `completed` | O que a medição indica, com evidências reveláveis. | Ver detalhes ou repetir teste. |
| `inconclusive` | “Ainda não dá para concluir sobre X”, com o dado ausente. | Medir novamente. |
| `unavailable` | “A leitura não está disponível agora. Seu resultado continua salvo.” | Tentar novamente ou ver resultado. |
| `out_of_scope` | “O Linka não consegue confirmar isso com esta medição.” | Ver o resultado ou medir novamente. |

Nenhum desses estados pode bloquear, atrasar, cobrir ou substituir o resultado da medição. O carregamento não deve simular raciocínio humano ou diagnóstico em curso.

## 4. Arquitetura-alvo

```text
┌─────────────────────────────────────── Linka ───────────────────────────────────────┐
│ LinkaEngine mede e apresenta resultado local                                          │
│   └─ Netscope client: seleciona evidência permitida, autentica e chama API            │
└───────────────────────────────────────┬──────────────────────────────────────────────┘
                                        │ HTTPS
                                        ▼
                    api.signallq.com/v1/linka/*
                                        │
┌──────────────────────────── Netscope Worker (novo) ──────────────────────────────────┐
│ valida schema/body cap → limita abuso → valida identidade/assinatura → verifica quota │
│                         │                         │                                  │
│                         ▼                         ▼                                  │
│              D1 exclusivo Netscope          AI router / policy                        │
│              instalações, quotas,           Workers AI inicialmente                   │
│              custo, configuração,           adapters OpenAI/Gemini/Grok desligados   │
│              auditoria sanitizada           validação estrita da saída                 │
└───────────────────────────────────────────────────────────────────────────────────────┘
                                        ▲
                                        │ Cloudflare Access + MFA
                              Netscope Console (painel interno)
```

### 4.1 Limites de isolamento

O Netscope não reutiliza:

- Worker, código de domínio, regras diagnósticas ou contratos do NDS;
- D1, migrations, bindings, logs ou namespaces de rate limit de SignallQ/NDS;
- secret, token, cookie, sessão administrativa ou credencial de provedor de outro produto;
- rota catch-all ou proxy que aceite URL/modelo/prompt fornecido pelo cliente.

É permitido reutilizar somente padrões técnicos não sensíveis, como Hono, validação de schemas, allowlist de logs, body cap, request ID e testes de Worker.

## 5. Contrato público V1

O OpenAPI do repositório Netscope será a fonte de verdade. Toda mudança incompatível abre `v2`; o app não depende de campos informais.

### Rotas

```text
POST /v1/linka/attestation/challenge
POST /v1/linka/attestation/register
POST /v1/linka/analysis
POST /v1/linka/feedback
GET  /v1/linka/health
```

`/admin/*` não faz parte do contrato do app e fica protegido por outra audiência de autenticação.

### Request de análise, em resumo

```json
{
  "schema_version": "1.0.0",
  "measurement": {
    "download_mbps": 320.4,
    "upload_mbps": 120.6,
    "latency_ms": 18.2,
    "jitter_ms": 2.1,
    "connection_kind": "wifi",
    "wifi_details": {
      "band": "5ghz",
      "channel": 36
    }
  },
  "usage_context": { "objective": "video_call", "subcategory": "" },
  "locale": "pt-BR",
  "app": { "version": "", "platform": "ios" },
  "consent": { "diagnostic_processing": true }
}
```

Todos os campos métricos são opcionais. Campo ausente significa “não medido/não disponível”; nunca zero por conveniência. O contrato final remove valores de exemplo ambíguos e define unidades, faixas e semântica de ausência por campo.

### 5.1 Contexto de conexão não é inferência

`connection_kind` é uma evidência de sistema obrigatoriamente tipada, com enum fechado:

```text
wifi | cellular | ethernet | other | unknown
```

`wifi`, `cellular` e `ethernet` só são enviados quando a API de plataforma realmente reportar a interface correspondente. Velocidade, latência, IP, nome de rede ou heurística nunca determinam o tipo de conexão. `other` cobre uma interface reconhecida fora do conjunto de produto; `unknown` significa que o sistema não a determinou. O Worker rejeita enum inválido e nunca assume `wifi` como default.

`wifi_details` é opcional e só pode existir quando `connection_kind = wifi`. Seus subcampos são independentes e opcionais:

| Campo | Regra |
|---|---|
| `frequency_mhz` | somente valor devolvido pela API do sistema; não derivar de throughput, latência ou nome da rede. |
| `band` | `2.4ghz`, `5ghz` ou `6ghz`, somente quando a plataforma devolver a banda explicitamente. |
| `channel` | somente canal informado pela plataforma. |
| `link_speed_mbps` | somente taxa de link observada; não confundir com download do teste. |

No iPhone/iPad, o Netscope não pede permissão, entitlement ou localização nova apenas para preencher esses dados. Se uma API não os expuser no contexto já autorizado, o campo permanece ausente. No Mac, a mesma regra vale: só se envia o dado já observável pelas APIs autorizadas. A ausência de frequência, banda, canal ou taxa de link nunca é substituída por `null`, zero artificial ou estimativa.

`usage_context` tem outra natureza: é **contexto declarado pela pessoa**, como `video_call` ou `gaming`; não é evidência da rede. Ele é transportado separadamente, pode orientar a pergunta da IA e a ação sugerida, mas nunca aparece como dado medido em `evidence_used`.

### Response de análise, em resumo

```json
{
  "schema_version": "1.0.0",
  "request_id": "",
  "status": "completed",
  "declared_context": { "objective": "video_call" },
  "assessment": { "title": "", "summary": "", "confidence": "" },
  "evidence_used": [{ "metric": "connection_kind", "value": "wifi", "source": "system_observed" }],
  "limitations": [""],
  "next_action": { "title": "", "steps": [""] },
  "provenance": { "provider": "", "model": "", "policy_version": "" }
}
```

`evidence_used` declara somente fatos observados, inclusive `connection_kind` quando recebido. `declared_context` ecoa, quando houver, a intenção declarada e não prova qualidade de rede. A resposta deve tratá-lo como premissa (“para uma chamada de vídeo, como você indicou”), nunca como medição.

Não há chain-of-thought, prompt, chave de provider nem configuração administrativa na resposta.

## 6. Segurança e autenticação

### 6.1 Consumo pelo app

O Linka não contém API key estática.

1. O app pede um challenge de uso único e curta duração.
2. Quando `DCAppAttestService.isSupported` estiver disponível, iPhone/iPad criam/atestam chave App Attest.
3. O servidor valida App ID, Team ID, ambiente, chave e contador; registra somente a chave pública e estado mínimo.
4. Cada análise é assinada com hash de corpo, método, rota, nonce e timestamp.
5. O Worker valida token curto, assinatura, nonce consumível, expiração e contador monotônico antes de chamar IA.
6. Falhas retornam resposta genérica `401`/`403`, sem revelar se o problema foi challenge, chave ou contador.

No macOS, ou quando App Attest não for suportado, o Linka usa uma chave local no Keychain/Secure Enclave quando disponível. O serviço marca `mac_unattested` como sinal técnico de integridade, sem tratá-lo como equivalente a App Attest ou como quota/limitação de produto.

### 6.2 Defesas contra abuso e custo

- limite de borda por IP efêmero e rota;
- proteção técnica contra rajada e abuso, sem cota de produto por instalação ou trust tier;
- body cap, limite de concorrência, timeout total e idempotency key;
- orçamento diário/mensal global antes da chamada de IA;
- reserva de custo máximo antes da chamada e ajuste após resposta;
- circuit breaker, timeout individual por provider e kill switch;
- modelo, endpoint, URL, prompt, tool-call ou provider nunca vêm do cliente;
- egress limitado aos providers configurados.

O limitador de borda protege a rajada. O D1 reserva somente o teto global de emergência; a regra de negócio de uso pertence ao Linka. Um não substitui o outro.

### 6.3 Painel administrativo

O painel usa Cloudflare Access com identidade humana e MFA. O mínimo de papéis é `viewer`, `operator` e `security_admin`.

- sessão `httpOnly`, `Secure` e `SameSite`;
- CSRF para qualquer mutação;
- CORS por allowlist, sem `*`;
- reautenticação para alteração de orçamento, provider e bloqueio;
- auditoria append-only de leitura sensível, exportação e mutação;
- app tokens e credenciais Linka não acessam rotas administrativas;
- API keys continuam sendo alteradas somente por secrets do Worker/CI protegido, nunca pelo painel.

## 7. D1: dados, privacidade e retenção

O banco é exclusivo por ambiente: `netscope-dev`, `netscope-staging` e `netscope-prod` (nomes finais sujeitos à configuração Cloudflare).

| Tabela/área | Dados permitidos | Não guardar | Retenção inicial proposta |
|---|---|---|---|
| `installations` | pseudônimo HMAC, plataforma, versão, trust tier, estado, timestamps | ID cru, IP, SSID/BSSID, push token | apagar após 90 dias inativos |
| `attestation_keys` | key id, chave pública, contador, estado | assertion/receipt bruto salvo | enquanto ativa + limpeza por inatividade |
| `challenges`/`replay_guards` | hash, expiração, consumo | corpo, header, assertion | minutos/horas conforme TTL |
| `usage_windows` | contagem, tokens e custo globais | payload de rede/prompt/resposta, consumo por instalação | 30–90 dias agregados |
| `provider_policies` | provider, modelo, timeout, rollout, orçamento | API keys | enquanto política ativa + auditoria |
| `analysis_audit` | request ID, modelo, latência, outcome, custo, hash de evidência | métricas brutas, prompt, resposta textual | 7–30 dias |
| `admin_audit` | ator, ação, alvo, antes/depois redigidos | segredos | conforme política operacional |
| contexto de conexão recebido | processado em memória para a análise | tipo de rede, frequência, banda, canal e taxa de link em logs/D1 | não persistir na V1 |

O identificador local é aleatório e fica no Keychain. O D1 recebe apenas versão pseudonimizada por HMAC com chave rotacionável. Dados brutos, prompt, resposta textual e relato livre ficam desligados por padrão.

Antes do rollout, a política de privacidade, App Privacy e Privacy Manifest devem refletir processamento remoto, identidade pseudônima e retenção reais.

## 8. IA e qualidade da resposta

AI-first não significa IA sem estrutura. O Netscope usa uma interface `AiProvider` e política versionada:

1. recebe somente projeção allowlist da medição, com `connection_kind` observado e `wifi_details` apenas quando efetivamente presentes;
2. limita tamanho e tokens;
3. chama provider configurado;
4. valida JSON Schema, locale, tamanho de texto e referências apenas às evidências enviadas;
5. rejeita saída malformada, fora de escopo ou que cite tipo de conexão, frequência, banda, canal ou taxa de link ausente das evidências; rejeita também contexto declarado apresentado como fato medido;
6. devolve `unavailable` ou `inconclusive` se provider, validação ou orçamento falhar.

Não há fallback para regras NDS nem fallback textual otimista. A IA não altera os fatos nem transforma dados ausentes em certeza. O tipo de conexão contextualiza a leitura, mas não prova qualidade por si só: a IA não transfere pressupostos de Wi-Fi para rede móvel ou Ethernet. Se o objetivo declarado exigir evidências indisponíveis — por exemplo, jogos sem latência/jitter/perda suficientes — o resultado é `inconclusive`. Feedback V1 é apenas estruturado (`helpful`, `not_helpful`, `incorrect`), sem texto livre.

## 9. Repositórios e responsabilidades

| Repositório | Responsabilidade |
|---|---|
| `linka` existente | Medição, interface Apple, adaptação de evidência, atestação cliente e renderização de respostas tipadas. |
| `netscope-api` novo e privado | Worker, OpenAPI, D1, autenticação, quotas, AI router, painel, CI, documentação de operação. |
| SignallQ/NDS | Sem mudança nesta fase. Compartilham somente o domínio de borda, não código ou estado. |

Motivo para não colocar o serviço em `linka/ios`: ciclos de release Apple e infraestrutura têm segredos, banco, permissões, incidentes e deploys diferentes. Misturar tudo aumenta o raio de falha e conflita com o WIP existente do app.

## 10. Entregáveis por PR

### PR L-01 — Mapeamento de evidência do Linka

**Repositório:** `linka`
**Entrega:** mapa de métricas reais, origem, unidade, ausência, privacidade, contexto de uso e estados atuais de UI; inclui matriz iPhone/iPad/macOS para `connection_kind` e cada campo de `wifi_details`, com API de origem e condição de indisponibilidade.
**Aceite:** não há campo inventado; cada campo remoto tem política de privacidade; diferença entre evidência observada e contexto declarado documentada; nenhum dado de Wi-Fi exige permissão ou entitlement novo nesta V1.
**Não inclui:** backend, IA ou mudança no motor.

### PR A-01 — Bootstrap do Netscope

**Repositório:** `netscope-api`
**Entrega:** `AGENTS.md`, ADRs, TypeScript/Hono, Wrangler sem IDs reais, OpenAPI como fonte de verdade, lint, typecheck, Vitest e CI.
**Aceite:** `GET /health` local, sem domínio, D1 real, secret ou deploy.

### PR A-02 — Contrato, modelo de ameaça e privacidade

**Repositório:** `netscope-api`
**Entrega:** schemas, fixtures, tabela campo-a-campo de dados/retention e modelo de ameaça.
**Aceite:** testes cobrem campos ausentes, `inconclusive`, `unavailable`, dados proibidos e compatibilidade de schema; fixtures cobrem `cellular`, `ethernet`, `unknown` e Wi-Fi sem detalhes; schema rejeita `wifi_details` fora de Wi-Fi e impede `declared_context` em `evidence_used`.
**Bloqueia:** qualquer chamada a provider antes de estar aprovado.

### PR A-03 — Identidade, anti-replay, quotas e D1

**Repositório:** `netscope-api`
**Entrega:** migrations D1, challenges, instalações pseudônimas, chaves públicas, assertions, teto global e proteção técnica contra abuso.
**Aceite:** testes de challenge vencido/reutilizado, body/rota divergente, contador regressivo/concurrente, revogação, limite e ausência de log sensível.

### PR L-02 — Cliente Netscope e atestação

**Repositório:** `linka`
**Entrega:** `NetscopeClient`, `NetscopeAttestationProvider`, Keychain e trust tiers iOS/iPad/macOS.
**Aceite:** App Attest válido/inválido e fallback macOS testáveis; tipo de conexão vem exclusivamente de API já autorizada em cada plataforma, sem novo prompt de permissão; teste de velocidade não espera nem falha por causa da Leitura.

### PR A-04 — Roteador de IA seguro

**Repositório:** `netscope-api`
**Entrega:** Workers AI inicialmente, adapters externos desligados, allowlist de evidência, validator de output, custo, timeout e kill switch.
**Aceite:** timeout, JSON inválido, evidência alucinada, prompt injection, provider desativado e orçamento zero retornam estados honestos sem vazamento; tentativa de citar frequência/banda/canal ausente ou de tratar contexto declarado como medição é rejeitada pelo validador.

### PR L-03 — Experiência Netscope no Linka

**Repositório:** `linka`
**Entrega:** CTA pós-resultado, loading calmo, leitura, evidência, reteste, insuficiência e indisponibilidade.
**Aceite:** cobertura iPhone/iPad/Mac, VoiceOver, Dynamic Type, localização e preservação do resultado como protagonista.

### PR A-05 — Netscope Console

**Repositório:** `netscope-api`
**Entrega:** painel administrativo, Cloudflare Access, RBAC, auditoria, orçamento, rollout, políticas e bloqueio de instalações.
**Aceite:** app não acessa admin; permissões, CSRF, CORS hostil, expiração de sessão e auditoria são testados.

### PR A-06 — Providers externos e avaliação

**Repositório:** `netscope-api`
**Entrega:** adapters OpenAI, Gemini e Grok; todos inicialmente desativados.
**Aceite:** cada ativação requer avaliação de qualidade, custo, privacidade/DPA, quota e feature flag própria.

### PR R-01 — Provisionamento e canário

**Repositórios:** `netscope-api` e `linka`
**Entrega:** D1 por ambiente, secrets, AI Gateway se aprovado, Access, rota Cloudflare, monitoramento e runbook de rollback.
**Aceite:** smoke em iPhone físico com atestação, Mac em trilha degradada, kill switch, quota, retenção e teste negativo de isolamento de SignallQ.
**Gate humano:** autorização explícita antes de criar recursos, inserir secrets, mudar DNS/rota, ativar cobrança ou publicar.

## 11. Estratégia de teste e qualidade

- unitários para schemas, ausência de dados, segurança de request, quotas, saída IA e redaction de logs;
- fixtures positivas, parciais, inválidas e fora de escopo, incluindo Wi-Fi sem frequência/banda/canal, móvel, Ethernet e tipo desconhecido;
- testes de contrato entre cliente Linka e OpenAPI;
- teste negativo: credencial/installação Netscope não acessa SignallQ/NDS e vice-versa;
- teste real em iPhone/iPad com App Attest;
- teste real no Mac no trust tier degradado;
- testes de timeout, offline, troca Wi-Fi↔móvel↔Ethernet, resposta parcial e provedor indisponível;
- acessibilidade e localização nos seis estados de interface;
- revisão de privacidade e inventário de secrets antes do canário;
- revisão adversarial de segurança antes de abrir além da beta allowlist.

## 12. Custos e rollout

Infraestrutura gratuita não equivale a IA gratuita e ilimitada. O rollout começa com serviço desligado por padrão e teto global rígido de emergência. A regra de negócio de acesso e uso pertence ao Linka; o backend não impõe allowlist nem quota por pessoa, instalação ou trust tier.

Workers AI é o único provider inicialmente considerado dentro da franquia/crédito disponível. OpenAI, Gemini e Grok permanecem sem secrets e sem cobrança habilitada até decisão humana. Exceder orçamento ou limite retorna indisponibilidade explícita; jamais uma conclusão local inventada.

## 13. Gates pendentes do Luiz

1. Autorizar a criação do repositório privado `netscope-api` e confirmar o proprietário GitHub.
2. Confirmar o uso de `api.signallq.com` para a rota Linka e a disponibilidade da zona/rota Cloudflare.
3. Aprovar a política macOS de integridade e experiência, sem transformá-la em quota ou limitação de produto.
4. Aprovar coleta, retenção e texto final de privacidade antes de qualquer tráfego remoto real.
5. Aprovar qualquer custo recorrente, provider externo, BYOK/Unified Billing ou elevação do teto global.
6. Fazer clearance de marca, domínio e App Store para “Netscope” antes de uso público.

## 14. Riscos conhecidos

- IA-first aumenta risco de inferência excessiva; schema, evidência permitida, avaliação e estados de insuficiência reduzem o risco, mas não o eliminam.
- App Attest não é universal e não é autenticação completa; fallback Mac precisa ser uma decisão explícita de produto/custo.
- D1 e planos gratuitos têm limites; agregação, retenção curta e kill switch são necessários desde a beta.
- `api.signallq.com` pode causar confusão de marca e depende de confirmação de DNS/rota.
- A política de privacidade precisa descrever a implementação real, não intenção futura.

## 15. Fontes internas desta decisão

- `AGENTS.md` do Linka: medição como resultado principal, IA em superfície secundária, ausência de dados não é zero, sem segredos no cliente.
- análise do fluxo legado em `NetworkDiagnostics/Sources/BuildeaDiagnosticTransport.swift` e `NDSRequestBuilder.swift`: não reutilizar a semântica atual de Assist/NDS.
- revisão independente de produto (Íris), arquitetura (Camillo) e segurança/qualidade (Tito), em 22 de setembro de 2026.
- revisão adversarial por Claude CLI, em 22 de setembro de 2026: veredito inicial `AJUSTA`; alterações aceitas para separar Wi-Fi/móvel/Ethernet, detalhes Wi-Fi somente observados e contexto declarado distinto de evidência.
