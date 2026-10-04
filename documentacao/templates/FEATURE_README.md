# {{nome_da_feature}}

Estado do documento: rascunho
Responsável: {{responsavel}}
Última revisão: {{AAAA-MM-DD}} — {{escopo_conferido}}
Referências: {{links_para_fontes_decisoes_e_evidencias}}

> TEMPLATE: substituir os campos `{{...}}` antes de usar. Informação não conferida fica como “não verificada”; não preencher por suposição. Remover esta orientação na cópia preenchida.

Disponibilidade da feature: {{estado_por_plataforma_ou_nao_verificado}}
Base conferida: {{commit_build_ou_WIP_e_escopo}}
Termos de busca: {{nomes_na_interface_aliases_e_modulos}}

## Propósito e limites

- Problema do usuário: {{problema}}
- Quem usa e em qual contexto: {{usuario_contexto}}
- Resultado esperado: {{beneficio_observavel}}
- Fora de escopo: {{nao_objetivos}}

## Comportamento atual

Descrever somente o que foi conferido, indicando a fonte. Comportamento desejado ainda não entregue fica em “Mudanças em andamento”.

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

## Mapa técnico

Caminhos de código devem ser relativos à raiz Git, acompanhados de links relativos ao documento. Preferir símbolos estáveis a números de linha isolados.

| Responsabilidade | Módulo, arquivo e símbolo de entrada | Fonte |
|---|---|---|
| {{responsabilidade}} | {{caminho_e_simbolo}} | {{link}} |

## Fluxo e contratos

- Fluxo de dados: {{origem_processamento_consumidores}}
- Contratos, schemas e versões: {{links_para_fontes_sem_copiar_o_contrato}}
- Persistência, sincronização e compatibilidade: {{comportamento_e_fonte_ou_nao_se_aplica}}
- Concorrência, ciclo de vida e cancelamento: {{comportamento_e_fonte}}
- Falhas, timeout e dados ausentes/parciais: {{tratamento_e_fonte}}
- Privacidade, permissões e dados sensíveis: {{comportamento_e_fonte}}

## Dependências e impacto

| Feature ou componente relacionado | Relação e impacto de uma mudança | Referência |
|---|---|---|
| {{dependencia}} | {{quem_produz_quem_consome_e_risco}} | {{link}} |

Decisões arquiteturais e regras compartilhadas: {{links_para_arquitetura_design_e_decisoes}}. Manter essas regras na fonte compartilhada.

## Operação e limitações técnicas

- Configuração necessária: {{nomes_e_mecanismo_sem_valores_secretos}}
- Procedimentos de diagnóstico: {{links_ou_comandos_com_diretorio_e_pre_requisitos}}
- Limitações conhecidas: {{limite_impacto_e_fonte}}

## Critérios de aceite

Usar identificadores estáveis para relacionar comportamento e evidência. Critério esperado não é prova de execução.

| ID | Cenário e condição | Resultado esperado | Fonte da regra |
|---|---|---|---|
| AC-01 | {{cenario}} | {{resultado_observavel}} | {{referencia}} |

## Evidências existentes

Separar inspeção estática, teste local, build, simulador, dispositivo físico, TestFlight, App Review e produção. Um nível não prova o seguinte.

| Critério | Nível e ambiente | Versão/commit ou WIP | Data | Procedimento e referência | Resultado e limites |
|---|---|---|---|---|---|
| AC-01 | {{nivel_dispositivo_sistema}} | {{versao}} | {{data}} | {{comando_com_diretorio_ou_passos_e_link}} | {{resultado_real_ou_nao_executado}} |

## Validação ainda necessária

| Cenário ou risco | Por que falta validar | Responsável | Prazo ou evento de revisão | Critério de fechamento |
|---|---|---|---|---|
| {{cenario}} | {{lacuna}} | {{responsavel}} | {{prazo_evento}} | {{evidencia_necessaria}} |

## Mudanças em andamento

Não misturar proposta com comportamento atual. Se não houver iniciativa conhecida após a consulta às fontes, registrar isso e o alcance da consulta.

| Iniciativa e plano/issue | Estado | Decisão ou autorização registrada | Diferença para o estado atual | Responsável |
|---|---|---|---|---|
| {{link}} | {{proposto_decidido_em_execucao_validacao_pendente}} | {{referencia_ou_pendente}} | {{mudanca}} | {{responsavel}} |

## Divergências e perguntas abertas

| Divergência entre fontes ou dúvida | Impacto | Responsável | Prazo ou evento de revisão | Critério de fechamento |
|---|---|---|---|---|
| {{fontes_e_divergencia_ou_duvida}} | {{impacto}} | {{responsavel}} | {{prazo_evento}} | {{evidencia_ou_decisao_necessaria}} |
