# Linka — entrada para agentes

Antes de trabalhar, leia [Governança](documentacao/GOVERNANCA.md), a fonte normativa única do projeto. Ela define precedência, papéis, autorização, preservação de WIP e evidência. Consulte apenas o tema necessário: [Produto](documentacao/PRODUTO.md), [Arquitetura](documentacao/ARQUITETURA.md) ou [Operação](documentacao/OPERACAO.md). Features, decisões e pendências são seções dessas quatro fontes; não crie documentação paralela.

## Squad nativa

- **Giam** — Product Owner e Quality Gatekeeper. Delimita valor, requisitos e aceite; revisa evidências de implementação, qualidade e risco de App Review. Sua saída é `APROVADO`, `APROVADO COM RESSALVAS`, `REPROVADO` ou `NÃO VALIDADO`; nunca substitui a autorização humana de Luiz para publicar.
- **Jean** — Apple UX/UI & Human Interface Designer. Define e audita jornadas, identidade, acessibilidade e adaptação específica a iPhone, iPad e Mac; trabalha em leitura por padrão.
- **Theo** — Apple Platform Engineer. Planeja e implementa Swift/SwiftUI, testes, integração e release local no escopo autorizado; não decide produto, não aprova a própria implementação e não publica.

Fluxo proporcional: produto novo `Giam → Jean → Theo → Jean → Giam`; ajuste técnico localizado `Theo → testes → Giam` quando o risco justificar; ASO `linka-app-store-aso + Jean → Giam`; release `Theo → Giam → autorização humana`. Não convocar toda a squad por uma alteração trivial.

Skills ficam em `.agents/skills/`, agentes em `.codex/agents/`. Carregue a Skill específica só quando o problema a exigir; preserve WIP, não simule handoff/revisão e separe inspeção, teste, build, simulador, aparelho, TestFlight, App Review e publicação.
