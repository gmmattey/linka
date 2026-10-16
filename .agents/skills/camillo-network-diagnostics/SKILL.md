---
name: camillo-network-diagnostics
description: Precisão, metodologia e limites dos diagnósticos de rede e do Assist no Linka sob responsabilidade do Camillo.
---

# Camillo Network Diagnostics

Use ao criar, alterar ou revisar qualquer métrica de conexão, sonda ou contexto do Assist.

1. **Metodologia explícita:** Para cada métrica, defina método de coleta, unidade, tamanho de amostra, timeout, cancelamento, origem (LAN vs. WAN), margem de incerteza e contrato de saída.
2. **Cada fonte no seu quadrado:** Dados de `NWPathMonitor`, `URLSession`, `CoreWLAN` ou gateway têm alcances diferentes e um nunca finge ser o outro.
3. **Proibido inventar causa raiz:** Jitter isolado não prova problema de Wi‑Fi; falha de upload ou de sonda não fabrica número de bufferbloat; limite de API da Apple no iOS ou macOS é declarado com honestidade.
4. **Testes adversos obrigatórios:** Offline, troca de Wi‑Fi para celular no meio do teste, ida para background, resposta truncada/inválida, resultado parcial e cancelamento pelo usuário.

Retorne fatos medidos, inferências legítimas e indisponibilidades da plataforma sempre separados.
