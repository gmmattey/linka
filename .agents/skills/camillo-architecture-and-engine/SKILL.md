---
name: camillo-architecture-and-engine
description: Arquitetura sistêmica, engenharia Swift, contratos, persistência e modularidade do Linka sob a guarda do Camillo.
---

# Camillo Architecture & Engine

Use quando o gate arquitetural de `documentacao/GOVERNANCA.md` for acionado ou ao modificar `LinkaEngine` e os pacotes compartilhados (`NetworkCore`, `MeasurementHistory`, `NetworkInsights`, `NetworkAssist`, `LinkaEntitlements`, `LinkaAppIntents`).

## Pergunta principal

> **O que esta decisão pode quebrar silenciosamente e qual é o custo para desfazer depois?**

## Regras estruturais inegociáveis

1. **Fronteira limpa (`View → Adapter → Motor`):** Pacotes de domínio/motor não importam SwiftUI, UIKit ou AppKit. A interface nunca calcula bytes, não duplica regra de medição e não abre sessão de rede por fora.
2. **Interpretação fora do motor:** Assist, recomendação e diagnóstico consomem dado medido, mas não contaminam a coleta pura.
3. **Contrato e Concorrência:** Mudança incompatível exige migração explícita. Em `async/await`, dono da `Task`, cancelamento, `actor`/`MainActor` e limpeza de `URLSession`/timers precisam estar explícitos.
4. **Falha fechada:** Ausência de dado, erro, timeout ou cancelamento nunca viram `0` nem sucesso silencioso.
5. **Simplicidade e coesão:** Não crie pacote, camada ou protocolo para feature hipotética. Tamanho de arquivo é sinal para revisar coesão, não punição automática.

## Saída do Plano Arquitetural (antes do código)

Quando investigar para o time, entregue ao **Marco**:
- problema e decisão recomendada (e o que foi descartado com motivo);
- pacotes e contratos afetados;
- comportamento em falha, timeout, cancelamento e corrupção de dado;
- impacto por plataforma (iPhone, iPad, Mac);
- testes necessários para o **Renan** auditar;
- **o que não será feito nesta fatia**.
