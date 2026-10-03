# Plus promocional com anúncios — plano arquitetural

Decisão do Luiz: promoção libera recursos Plus com publicidade; assinatura válida remove publicidade. Recursos e publicidade usam políticas distintas em LinkaEntitlements. StoreKit verificado prevalece sobre promoção.

A coordenadora recebe elegibilidade e resolução atuais. Compra, restauração ou estado não resolvido invalidam tarefas, loader e anúncio. Cada suspensão e callback é protegido por geração; callback também exige identidade do loader vigente. Views refletem a política sem reimplementá-la.

Medição pausa anúncios de forma reversível. Seu encerramento não dispara publicidade automaticamente; somente destino elegível pode solicitar. O orçamento de uma tentativa nativa por sessão é consumido imediatamente antes do request real, permitindo retomar preparação cancelada antes disso. Opções de privacidade voltam a funcionar após medição.

UMP carrega o formulário antes de consultar a permissão revogável e apresentar. NPA, personalização desabilitada e publisher first-party ID desabilitado precedem inicialização/request. Decisão explícita do Luiz: manter anúncios não personalizados e corrigir o aviso ATT. ATT precede UMP e SDK para usuários elegíveis; compra paga continua sem entrar nessa trilha. Se o app não estiver ativo e ATT ainda não foi respondido, aguardar nova tentativa do placement ao voltar a ativo. Negação/restrição não bloqueia NPA. Revalidar geração após resposta sem prender medição. Manifesto, configuração SDK, política pública e App Store Connect devem refletir comportamento real; NPA isolado não prova ausência de rastreamento.

Validação: unitários da política promocional/paga/expirada; revogação durante consentimento; cancelamento de medição sem gastar tentativa; privacidade após medição; build e testes do app. Evidência física, inventário de privacidade e nova submissão permanecem gates separados. Sem alteração de engine, persistência, preço ou calendário da promoção.
