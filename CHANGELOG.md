# CHANGELOG - Linka

Todas as mudanças notáveis deste projeto são documentadas neste arquivo. Para detalhes das builds enviadas ao TestFlight, consulte [`RELEASE_NOTES.md`](RELEASE_NOTES.md).

## [Em desenvolvimento — Outubro 2026]

### Governança & Organização (Squad 2.0)
- Implantação da **Squad 2.0 Humanizada** (**Giam, Marco, Priscila, Camillo, Bia e Renan**), com 5 Raias de execução, Regra de Desempate em 5 níveis e Cartão de Missão obrigatório.
- Reorganização da estrutura de pastas na raiz do repositório, consolidação dos 4 Pilares de Fontes de Verdade (`PRODUTO.md`, `ARQUITETURA.md`, `OPERACAO.md`, `GOVERNANCA.md`) e resgate dos protótipos HTML oficiais em `documentacao/design/prototipo/`.

### Assist Contextual V4 (Fundação & Transporte Isolado)
- Pacotes `AssistConsultation` e `AssistConsultationTransport` criados com contrato tipado `assist.consultation/1.0`, separado do diagnóstico legado (`/v2/assist`).
- Prova física de App Attest genuíno concluída em iPhone 17 real conectado ao relay isolado (`POST /v1/assist/consultations`), mantendo feature flag desativada até homologação completa da jornada visual.

---

## [v1.1.6 (Builds 57–59)] - Outubro 2026 (TestFlight Interno)

### Minha Rede V1, V2 e V3
- **Minha Rede V1 (Inventário e Ficha Técnica com IA):** Cadastro local e gratuito de equipamentos em iPhone, iPad e Mac, sugestão por OCR local (Vision) em etiquetas e pesquisa técnica com fontes oficiais via Worker dedicado (`v2/device-specs/lookup`).
- **Minha Rede V2 (Plano Residencial e Topologia):** Cadastro de plano de internet fixa com versionamento temporal ("Salvar correções" vs. "Troquei de plano"), mapeamento de conexões entre aparelhos (`Origem → Meio → Destino`) e visão consolidada em 4 seções.
- **Minha Rede V3 (Desempenho Factual e Guarda B1):** Motor determinístico `ResidentialPlanEvaluator` com isolamento estrito contra redes celulares/hotspots (Guarda B1) e correlação honesta das medições elegíveis com o plano contratado.

### macOS
- Formalizado o target `LinkaApp_macOS` no XcodeGen, com sidebar nativa, atalhos de teclado, Ajustes nativos e paridade funcional para Histórico, Minha Rede, Otimização, DNS, Roteador e Compartilhamento.

---

## [v1.1.5 (Build 55)] - Outubro 2026
- Remoção do pedido de permissão de rastreamento (ATT), mantendo consentimento UMP e anúncios não personalizados no nível gratuito.
- Correção da importação de dados de Wi-Fi avançado via Atalhos durante a campanha promocional do Linka Plus.

---

## [v1.1.0 (Build 42)] - 2026-09-01
- Padronização do processo de release e versionamento (Issue #150).
- Unificação da versão na tela de Ajustes para o formato `1.1.0 (42)`.

---

## [v1.0.0-beta] - Agosto 2026
- Lançamento inicial do motor nativo `LinkaEngine` (Ping, Download e Upload), Histórico local/iCloud, Linka Assist V2 e estética Apple-first.
