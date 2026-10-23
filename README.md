# Linka

SpeedTest minimalista e nativo para **iPhone, iPad e Mac**, com diagnóstico contextual e inventário residencial (**Minha Rede**). O site institucional e landing page pública estão centralizados em `~/Projetos/web/landings` (`sites/linka/`).

---

## Fontes de Verdade Oficiais (Single Source of Truth)

Nenhuma decisão de produto, contrato ou regra visual existe "de cabeça" ou espalhada em arquivos soltos. O projeto possui **4 pilares documentais canônicos** em [`documentacao/`](documentacao/) e fontes técnicas únicas por domínio:

| Domínio | Fonte de Verdade Canônica | Guardião (Squad Lean) | O que governa |
|---|---|---|---|
| **1. Produto & Jornada** | [`documentacao/PRODUTO.md`](documentacao/PRODUTO.md) | **Marcelo** | Intenção, regras de negócio, fluxos, limites do que o app promete e critérios de aceite funcional |
| **2. Arquitetura & Contratos** | [`documentacao/ARQUITETURA.md`](documentacao/ARQUITETURA.md) + [`documentacao/arquitetura/`](documentacao/arquitetura/) | **Camillo** | Módulos Swift, fronteiras, contratos JSON/OpenAPI, persistência local/CloudKit, ADRs e auditorias |
| **3. Operação, Build & Loja** | [`documentacao/OPERACAO.md`](documentacao/OPERACAO.md) + [`RELEASE_NOTES.md`](RELEASE_NOTES.md) | **Renan** | Comandos de validação, simuladores, TestFlight, chaves, App Store e histórico de candidatas |
| **4. Governança & Ciclo Ágil** | [`documentacao/GOVERNANCA.md`](documentacao/GOVERNANCA.md) + [`AGENTS.md`](AGENTS.md) | **Marcelo** | Papéis da Squad Lean, Ciclo Ágil de 3 passos, regra de desempate e proteção de WIP |
| **5. UX/UI, Protótipos & Marca** | [`documentacao/design/prototipo/`](documentacao/design/prototipo/) + [`DesignSystem.swift`](aplicativo-ios/LinkaApp/Sources/UI/DesignSystem.swift) + [`brand/manifest.json`](brand/manifest.json) | **Priscila** | Protótipos interativos iOS/macOS, tokens visuais, wireframes do Assist V4 e ativos oficiais da marca |

> **Ordem de precedência em caso de conflito:**
> Pedido explícito do Luiz → Comportamento provado em código/testes → Protótipo oficial (`documentacao/design/prototipo/`) → Design System → `GOVERNANCA.md` → Demais fontes.

---

## Mapa da Pasta do Projeto

```text
linka/
├── README.md                     # Este guia e mapa das Fontes de Verdade
├── AGENTS.md                     # Entrada rápida da Squad Lean (Marcelo, Priscila, Camillo, Renan)
├── CHANGELOG.md                  # Histórico consolidado de versões
├── RELEASE_NOTES.md              # Notas das builds enviadas ao TestFlight / App Store
├── aplicativo-ios/               # App nativo (iPhone, iPad, Mac, Widget, App Intents) e pacotes Swift
│   ├── project.yml               # Manifesto canônico do XcodeGen
│   ├── LinkaApp/                 # Targets de UI e Adapters (iOS, iPadOS e macOS)
│   ├── LinkaEngine/              # Motor puro de medição (Ping, Download, Upload, Responsividade)
│   ├── NetworkCore/              # Contratos e modelos compartilhados de medição
│   ├── NetworkInventory/         # Minha Rede (Equipamentos, Planos, Topologia e Avaliador B1)
│   ├── AssistConsultation/       # Núcleo e contratos tipados da consultoria Assist V4
│   └── ...                       # Demais pacotes modulares (History, Insights, Assist, DNS, Netscope)
├── documentacao/                 # Os 4 Pilares Canônicos + subpastas técnicas
│   ├── PRODUTO.md                # Pilar 1: Produto, capacidades e jornadas
│   ├── ARQUITETURA.md            # Pilar 2: Arquitetura, módulos e contratos
│   ├── OPERACAO.md               # Pilar 3: Validação, simulador, TestFlight e loja
│   ├── GOVERNANCA.md             # Pilar 4: Governança, Squad Lean e Ciclo Ágil de 3 Passos
│   ├── arquitetura/              # ADRs, auditorias técnicas e JSON Schemas/fixtures
│   └── design/                   # Protótipos HTML/JSX, tokens do Design System e wireframes
├── brand/                        # Kit oficial de marca (Linka, Linka+, Assist, ícones) e manifest.json
├── store/                        # Testes de UI para capturas da App Store
├── fastlane/                     # Automação local de validação e envio ao TestFlight
├── .agents/                      # Skills canônicas da squad e WORKFLOW.md
└── .codex/                       # Configuração dos 4 agentes da squad (.toml)
```

Licença em [LICENSE](LICENSE).
