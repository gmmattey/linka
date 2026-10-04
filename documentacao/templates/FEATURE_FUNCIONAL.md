# {{nome_da_feature}} — funcional

Estado do documento: rascunho
Responsável: {{responsavel}}
Última revisão: {{AAAA-MM-DD}} — {{escopo_conferido}}
Referências: {{links_para_fontes_decisoes_e_evidencias}}

> TEMPLATE: substituir os campos `{{...}}` antes de usar. Informação não conferida fica como “não verificada”; não preencher por suposição. Remover esta orientação na cópia preenchida.

Documento principal: {{link_para_README_da_feature}}

## Propósito e limites

- Problema do usuário: {{problema}}
- Quem usa e em qual contexto: {{usuario_contexto}}
- Resultado esperado: {{beneficio_observavel}}
- Fora de escopo: {{nao_objetivos}}

## Comportamento atual

Descrever somente o que foi conferido, indicando a fonte. Comportamento desejado ainda não entregue fica em “Mudanças em andamento” no README da feature, indicado em “Documento principal”.

| Entrada ou ação da pessoa | Resposta do produto | Regra e fonte |
|---|---|---|
| {{entrada}} | {{comportamento}} | {{regra_e_referencia}} |

### Estados e recuperação

Cobrir os estados aplicáveis: vazio, carregando, sucesso, resultado parcial, indisponível, offline, erro, cancelamento e permissão negada. Para estados não aplicáveis, explicar brevemente.

| Estado ou condição | O que a pessoa vê | Ação disponível e recuperação |
|---|---|---|
| {{estado}} | {{apresentacao}} | {{acao}} |

### Plataformas e acesso

| Plataforma | Disponibilidade e diferenças | Restrições, permissões ou acesso pago | Fonte |
|---|---|---|---|
| iPhone | {{comportamento}} | {{condicoes}} | {{fonte}} |
| iPad | {{comportamento}} | {{condicoes}} | {{fonte}} |
| Mac | {{comportamento}} | {{condicoes}} | {{fonte}} |

### Experiência e referências compartilhadas

- Pontos de entrada e destinos alcançáveis: {{telas_menus_sheets_atalhos}}
- Acessibilidade e adaptação: {{voiceover_dynamic_type_teclado_movimento_conforme_escopo}}
- Design, protótipo e copy: {{links_para_fontes_canonicas}}
- Limites de medição ou interpretação relevantes ao usuário: {{limites_e_fonte}}
