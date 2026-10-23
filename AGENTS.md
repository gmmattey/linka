# Linka — entrada para agentes

Antes de trabalhar, leia [Governança](documentacao/GOVERNANCA.md), a fonte normativa única do projeto. Ela define precedência, papéis, pistas de execução, autorização, preservação de WIP e evidência. Consulte apenas o tema necessário: [Produto](documentacao/PRODUTO.md), [Arquitetura](documentacao/ARQUITETURA.md) ou [Operação](documentacao/OPERACAO.md). Features, decisões e pendências são seções dessas quatro fontes; não crie documentação paralela.

## Squad Ultra-Enxuta (4 Titulares & Governança Unificada)

- **Marcelo (`marcelo`)** — **Braço direito do Luiz, Líder de Produto & Orquestrador da Oficina.** Porta de entrada com o Luiz na língua de negócio/produto, separa exploração de decisão, abre e aprova o [Cartão de Missão](.agents/templates/mission-card.md), define a pista, protege o WIP, aciona Priscila, Camillo e Renan, e dá o aceite final pelas 7 perguntas (`APROVADO`, `APROVADO COM RESSALVAS`, `REPROVADO` ou `NÃO VALIDADO`). Nunca substitui o sinal verde do Luiz para publicar.
- **Priscila (`priscila`)** — **Diretora de Experiência, UX/UI & Guardiã do Protótipo Apple.** Define e audita jornadas, visual 1:1 com o protótipo, acessibilidade (WCAG AA, Dynamic Type, Dark Mode) e adaptação ergonômica nativa para iPhone, iPad e Mac; trabalha em leitura por padrão.
- **Camillo (`camillo`)** — **Engenheiro Principal Full-Stack & Arquitetura.** Conduz o Gate Arquitetural e a implementação de ponta a ponta: protege `LinkaEngine` e os pacotes Swift compartilhados (`NetworkCore`, `MeasurementHistory`, `NetworkInventory`, `AssistConsultation`), e constrói as telas SwiftUI nativas 1:1 com o desenho da Priscila.
- **Renan (`renan`)** — **Qualidade, Aparelho Real & Caça-Bugs Implacável.** Independente de quem programou: audita código, testes automatizados, cenários adversos de rede, ciclo de vida, segurança e funcionamento real em iPhone, iPad e Mac físico (`BLOQUEIA`, `AJUSTA`, `ISSUE_FUTURA` ou `SEM ACHADOS MATERIAIS`) antes do aceite final do Marcelo.

## Ciclo Ágil de 3 Passos (Zero Burocracia & Prova Real)

Para acelerar entregas e eliminar falhas, o processo abandona cartões de missão em disco e handoffs burocráticos:
1. **Passo 1 — Enquadramento Direto (Marcelo):** 1 parágrafo claro na conversa (o que fazer, o que NÃO fazer e critério de sucesso). Sem arquivos descartáveis.
2. **Passo 2 — Construção & Auto-Teste (Camillo + Priscila):** Priscila define o visual 1:1 e Camillo implementa de ponta a ponta (motor e SwiftUI). Camillo roda localmente a build e os testes antes de passar para o Renan.
3. **Passo 3 — Prova de Fogo (Renan):** Renan atua como caça-bugs independente. Roda testes nos pacotes Swift (`swift test`), valida cenários adversos de rede e emite o veredito em 1 linha (`✓ APROVADO` com evidência ou `✗ BLOQUEADO`).

Uma entrega por vez (**WIP = 1**). Detalhes operacionais em [`.agents/WORKFLOW.md`](.agents/WORKFLOW.md).

### Suíte Canônica de Skills (7 Procedimentos Essenciais)
1. **`conversar-com-o-luiz`** *(Toda a Squad)*: Padrão de comunicação de amigo pra amigo, resultado primeiro, zero jargão técnico e propostas em 2-3 opções claras.
2. **`matar-cheiro-de-ia`** *(Toda a Squad)*: Filtro obrigatório contra jargões, muletas de IA, corporativês e floreios em textos, copy, commits e PRs.
3. **`marcelo-produto-e-aceite`** *(Marcelo)*: Enquadramento de demandas nas 5 pistas, abertura de missões, proteção de WIP e as 7 perguntas de aceite final.
4. **`priscila-design-system-ux`** *(Priscila)*: Padrões visuais 1:1, Design System, tokens semânticos, ergonomia por plataforma e acessibilidade WCAG AA.
5. **`camillo-engenharia-e-arquitetura`** *(Camillo)*: Separação motor vs UI, diagnóstico de rede determinístico, contratos tipados e implementação full-stack.
6. **`renan-qa-e-prova-real`** *(Renan)*: Metodologia caça-bugs independente, cenários adversos de rede, ciclo de vida e prova em aparelho real.
7. **`loja-e-aso`** *(Marcelo, Priscila, Renan)*: Estratégia de ASO, metadados, screenshots autorais e conformidade com diretrizes das lojas.

## Estrutura do Repositório e Estado Real

O repositório é estritamente focado no ecossistema nativo Apple (**iPhone, iPad e Mac**), modularizado via Swift Packages locais gerados por XcodeGen:

```text
linka/
├── aplicativo-ios/            # Projeto nativo Apple (iOS, iPadOS, macOS)
│   ├── project.yml            # Definição canônica do XcodeGen
│   ├── LinkaApp.xcodeproj     # Projeto gerado
│   ├── LinkaApp/              # Target de aplicação e telas SwiftUI
│   ├── LinkaEngine/           # Motor puro de medição (Download, Upload, Ping, Bufferbloat)
│   ├── NetworkCore/           # Modelos fundamentais e contratos de medição
│   ├── NetworkInventory/      # Minha Rede (Equipamentos, Topologia, Roteadores)
│   ├── AssistConsultation/    # Núcleo tipado da consultoria Assist V4
│   ├── MeasurementHistory/    # Histórico e persistência local
│   ├── MeasurementHistoryCloudKit/ # Sincronização em nuvem via CloudKit privado
│   ├── LinkaWidget/           # Extensão de Widgets (WidgetKit)
│   ├── LinkaAppIntents/       # Integração com Atalhos da Siri (App Intents)
│   └── NetworkDiagnostics/    # Probes e diagnósticos avançados de rota e DNS
├── documentacao/              # Os 4 Pilares Canônicos normativos
│   ├── PRODUTO.md             # Pilar 1: Capacidades, métricas e jornadas do usuário
│   ├── ARQUITETURA.md         # Pilar 2: Módulos, dependências e contratos
│   ├── OPERACAO.md            # Pilar 3: Validação, simulador, TestFlight e loja
│   └── GOVERNANCA.md          # Pilar 4: Squad humanizada, 5 pistas e regras de decisão
├── brand/                     # Identidade visual, paleta, ícones e assets de marca
├── fastlane/                  # Automações de build, assinatura (Match) e TestFlight
└── store/                     # Metadados e screenshots para App Store Connect
```

> **Aviso de Infraestrutura:** A pasta `aplicacao-web/` e a configuração `firebase.json` foram permanentemente removidas deste repositório. O site institucional e o speedtest web oficial residem no monorepo [`~/Projetos/web/landings`](file:///Users/giammattey/Projetos/web/landings) (`sites/linka/`).

## Separação de Repositórios: Landing Page e Presença Web

O repositório `linka` é dedicado exclusivamente ao aplicativo nativo Apple (**iPhone, iPad e Mac**), pacotes Swift modulares e automações de release.
- **Site Institucional, Speedtest Web e Landing Page:** Foram totalmente centralizados no monorepo [`~/Projetos/web/landings`](file:///Users/giammattey/Projetos/web/landings) (especificamente em `sites/linka/`).
- **Proibição de Código Web Local:** Agentes **NÃO** devem recriar a pasta `aplicacao-web/` ou arquivos de deploy web (`firebase.json`). Qualquer alteração nas páginas públicas e no speedtest web deve ser feita exclusivamente no repositório `web/landings`.
