# Imagens já usadas pela landing page

Estado: referências visuais do site; não são capturas aprovadas da candidata.
Responsável: orquestrador/Íris.
Última revisão: 2026-10-04 — dependência de LandingScreen e preservação dos bytes na mudança de diretório.
Referência: [documentação do site](../../../../documentacao/features/site-institucional/README.md).

As três imagens são importadas por `LandingScreen.tsx`. Foram transferidas de `store/app-store/screenshots/final/pt-BR/iphone-6.7/` para retirar do acervo da loja materiais que não têm build atual comprovada, preservando a apresentação do site existente.

Não atestam aparência da build atual nem devem ser reutilizadas para submissão. A atualização visual do site exige capturas da build pretendida e confronto de copy; não alterar métricas ou telas em editor para simular produto. Responsável: Íris/executor; evento: próxima revisão do site; fechamento: substituir pelas capturas identificadas e revisar a renderização.

## Divergências identificadas

- `01-entenda-sua-conexao.jpg`: Home antiga, com “Tudo parece normal / Analisar rede”.
- `02-meca-sua-internet.jpg`: medição antiga com duas fases e “Pular”; o checkout usa ping/download/upload e cancelamento.
- `04-veja-sua-evolucao.jpg`: resultado individual, não demonstra evolução no histórico.

A mudança de diretório preserva a página existente; não resolve essas divergências. Não reutilizar essas imagens no kit da loja. A pendência acima só fecha com substituição e revisão do conteúdo efetivamente exibido pelo site.
