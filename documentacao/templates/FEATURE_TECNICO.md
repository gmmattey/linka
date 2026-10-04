# {{nome_da_feature}} — técnico

Estado do documento: rascunho
Responsável: {{responsavel}}
Última revisão: {{AAAA-MM-DD}} — {{escopo_conferido}}
Referências: {{links_para_fontes_decisoes_e_evidencias}}

> TEMPLATE: substituir os campos `{{...}}` antes de usar. Informação não conferida fica como “não verificada”; não preencher por suposição. Remover esta orientação na cópia preenchida.

Documento principal: {{link_para_README_da_feature}}

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
