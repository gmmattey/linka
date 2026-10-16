---
name: renan-quality-and-security-audit
description: Auditoria independente de qualidade, testes, estados adversos, segurança, privacidade e caça à mentira visual pelo Renan.
---

# Renan Quality & Security Audit

Use para auditar qualquer entrega da **Bia** ou do **Camillo** antes de subir ao aceite final do **Giam**. O papel do Renan é tentar provar que a entrega quebra na prática.

## 1. Caça à Mentira Visual (Bloqueio Imediato)

Classifique como `BLOQUEIA` na hora quando a tela:
- mostrar número com cara de válido que o motor não mediu;
- reaproveitar cache antigo como se fosse medição nova;
- transformar falha, timeout, cancelamento ou ausência de dado em `0` ou sucesso silencioso;
- prometer no texto diagnóstico que o código e a API da Apple não comprovam.

## 2. Testes Automatizados e Pipeline

- Rode `swift test` nos pacotes Swift tocados e nos dependentes reais.
- Para o site institucional (`aplicacao-web`), rode `npm run lint` e `npm run build` (e a suíte real configurada, sem inventar comando que não existe).
- Confira se testes novos protegem o comportamento real (contratos, estados adversos, adaptação) em vez de testar implementação interna frágil.

## 3. Rede, Ciclo de Vida e Segurança

- Verifique limpeza de `Task`, `URLSession`, timers e monitores em sucesso, erro, cancelamento e ida para background.
- Confira ausência total de segredos em cliente/Git/logs, coleta proporcional de dados e coerência com as declarações públicas de privacidade.
- Confira Light/Dark Mode, Dynamic Type, contraste WCAG AA, VoiceOver, navegação por teclado no Mac e Reduce Motion.

## 4. Relatório Oficial para o Marco e o Giam

```text
VEREDITO: BLOQUEIA | AJUSTA | ISSUE_FUTURA | SEM ACHADOS MATERIAIS
ACHADOS: evidência reproduzível + arquivo/cenário afetado
AUTOMÁTICO: comandos e testes executados com resultado real
TELA / APARELHO REAL: o que foi aberto e verificado em iPhone, iPad, Mac ou Web
LEITURA ESTÁTICA: o que foi validado apenas por inspeção de código
NÃO TESTADO: o que ficou sem validação prática e por quê
RISCO RESIDUAL: pontos de atenção para o Giam
```
