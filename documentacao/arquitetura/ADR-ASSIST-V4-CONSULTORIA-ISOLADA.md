# ADR — Assist V4: consultoria isolada do diagnóstico

- **Status:** aceito
- **Data:** 10/10/2026
- **Decisão:** Assist V4 introduz uma modalidade de consultoria com contrato,
  transporte, autenticação e retenção próprios. O diagnóstico por medição
  existente continua inalterado.

## Contexto

O Assist legado depende de uma medição atual e de `NetworkAssistContext`. Seu
transporte é `POST /v2/assist`, encaminhado pelo relay ao diagnóstico remoto.
Forçar uma pergunta aberta nesse formato exigiria medição fictícia, permitiria
confundir a origem de dados e poderia mudar o comportamento já publicado.

Consultoria, por outro lado, pode começar sem medição e só pede contexto,
permissão ou reteste quando eles forem pertinentes. Ela precisa declarar fatos,
lacunas e evidências sem transformar texto de IA em execução de ferramenta.

## Decisão

1. Preservar o modo legado como está: mesma política observacional, mesmo
   `NetworkAssist`, mesmo `/v2/assist` e mesma exigência de medição.
2. Criar o contrato `assist.consultation/1.0` e o transporte fixo
   `POST /v1/assist/consultations`. Ele aceita somente contexto tipado com
   proveniência, validade e recibo de consentimento; nenhuma medição ausente é
   inventada para satisfazer o contrato legado.
3. Isolar a consultoria em D1, idempotência, retenção limitada e exclusão por
   owner opaco. Sessões, turns, chaves e challenges não usam o armazenamento
   de status ou diagnóstico.
4. Exigir App Attest para a rota de turnos: challenge de uso único, binding de
   método/caminho/corpo exato, validação Apple e contador monotônico. Não há
   fallback para cabeçalho estático, token legado ou Netscope.
5. Manter a rota, provider e custo em kill switches independentes. Sem
   configuração explícita de provider e orçamento, a resposta é
   indisponibilidade honesta; não existe tráfego de IA implícito.
6. Limitar a integração inicial a iPhone/iPad. A consultoria não entra no
   target macOS e não ativa UI normal enquanto os critérios de #312 e #320 não
   forem concluídos.

## Consequências

- #311 continua responsável pela completude do contrato de contexto/evidência.
- #312 entrega a jornada SwiftUI e consentimento visível; o transporte não é
  uma UI ativa.
- #320 continua dono da máquina de estados, autorização de ferramentas,
  retomada, reteste e histórico. Nenhuma resposta remota dispara ação por si.
- Rollback da consultoria é desligar sua flag. Não há rollback que modifique
  dados, rotas ou política do Assist legado.

## Evidência de decisão

- Relay V4 implantado com a flag desligada, D1 exclusivo vazio e sem provider;
  sua rota responde `CONSULTATION_NOT_ENABLED` até ativação deliberada.
- O app iOS assinado contém
  `com.apple.developer.devicecheck.appattest-environment=development`.
- Em 10/10/2026, o teste
  `testSystemAppAttestCreatesGenuineAttestationOnPhysicaliPhone` passou em um
  iPhone 17 físico, gerando chave e atestação Apple reais. Essa prova valida a
  fronteira de identidade, não autoriza tráfego de consultoria nem fecha #312
  ou #320.
