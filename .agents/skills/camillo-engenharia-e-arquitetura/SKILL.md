---
name: camillo-engenharia-e-arquitetura
description: Padrões de arquitetura, motores de rede determinísticos, contratos e implementação full-stack (mobile nativo e web) do Camillo.
---

# Skill: camillo-engenharia-e-arquitetura

Esta skill guia o **Camillo** na engenharia de software de ponta a ponta: do motor de rede à montagem das telas.

## 1. Separação de Responsabilidades (Fronteiras Claras)
- **Motor Puro (Engine):** Módulos de medição e rede não conhecem frameworks de interface (SwiftUI, Compose, HTML). Não fazem suposições de layout.
- **Telas & UI:** Telas apenas observam estados reativos (`StateFlow`, `@Observable`, signals/props) e despacham intenções do usuário. Nunca disparam chamadas de rede avulsas ou calculam métricas diretamente.
- **Contratos Compartilhados:** Modelos de domínio possuem esquemas tipados, imutáveis e testáveis.

## 2. Rigor Diagnóstico e de Rede
- **Verdade para o Usuário:** Falha, timeout, desconexão ou ausência de dados **NUNCA** viram zero, nota inventada ou sucesso silencioso.
- **Métricas Determinísticas:** Cada medição possui protocolo (UDP, TCP, ICMP, HTTP), timeout explícito, cancelamento gracioso e tratamento para perda de pacotes.
- **Isolamento de Domínios:** Diferencie estritamente problemas locais (LAN / Wi-Fi / Roteador) de problemas externos (WAN / Operadora / Rota do servidor).

## 3. Disciplina de Código Full-Stack
- **Mudanças Cirúrgicas:** Altere apenas o necessário para a missão aprovada. Não refatore código alheio sem necessidade explícita.
- **Proteção do WIP:** Leia `git status` e preserve alterações em andamento.
- **Auto-Revisão:** Antes de passar para o Renan, revise o próprio diff, execute testes automatizados locais e liste arquivos tocados e eventuais limitações técnicas.
