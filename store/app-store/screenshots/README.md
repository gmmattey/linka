# Capturas da loja

Estado: sem conjunto atual pronto para publicação.
Responsável: orquestrador/Íris e executor de capturas.
Última revisão: 2026-10-04 — inspeção visual das imagens antigas e confronto estático com HEAD 9eb1a094 + WIP.

Nenhuma captura antiga corresponde integralmente à aparência implementada neste checkout. Foram removidos os conjuntos final, fontes, marketing, rascunhos e candidates, além do gerador de composições Mac dependente dessas entradas. Cinco telas Mac ainda correspondiam parcialmente a estados existentes, mas tinham aparência anterior e nenhuma identificação verificável de build; também foram retiradas do kit atual. Nenhuma imagem substituta foi fabricada.

Três imagens antes usadas pela loja continuam como dependência existente do [site](../../../aplicacao-web/src/assets/screenshots/README.md), fora deste kit e com atualização pendente. Não são capturas atuais.

## Captura futura

O [teste de captura](AppStoreScreenshotsUITests.swift) foi preservado byte a byte nesta organização. O projeto inclui somente esse Swift no target de UI tests, sem empacotar imagens de marketing. O teste antigo usa esperas e procura um botão opcional antigo: pode omitir Resultado/Assist sem falhar. Sua execução, sozinha, não prova cobertura completa. Nenhum teste do app foi executado nesta rodada.

Antes de reutilização, registrar versão/build, commit e WIP, dispositivo/sistema, idioma, estado, origem do resultado e revisão visual. Capturar o app real; não fabricar valores ou funções. Rever o fluxo automatizado para exigir as telas pretendidas e conferir cada imagem contra a candidata.

| Pendência | Responsável | Evento | Fechamento |
|---|---|---|---|
| Atualizar fluxo de captura e produzir conjunto atual | Executor/Íris | Antes de upload | Telas necessárias capturadas na candidata identificada e revisadas visualmente |
| Confirmar formatos e exigências de submissão | Orquestrador | Próxima submissão autorizada | Requisitos vigentes conferidos e arquivos selecionados |
