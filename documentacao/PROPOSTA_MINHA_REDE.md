# Proposta de produto e especificação técnica — Minha Rede (Linka)

**Status:** proposta para revisão; não equivale a implementação nem a decisão já incorporada aos quatro documentos oficiais.
**Data:** 2026-10-08
**Repositório:** `gmmattey/linka`
**Intenção:** reposicionar o Linka de speed test com interpretação para **assistente pessoal da rede doméstica**, sem perder a confiabilidade das medições.

## 1. Decisão de produto e experiência

**Princípio:** a pessoa cadastra o que possui uma vez; o Linka passa a contextualizar orientações considerando os equipamentos e, progressivamente, seu plano, ambientes e medições.

- Área de produto proposta: **Minha Rede**. Não criar um segundo aplicativo.
- **V1 — Meus equipamentos:** cadastro manual ou por foto, **pesquisa técnica na web com IA** por marca/modelo/revisão, sugestão de ficha técnica com fontes, confirmação da função do aparelho na instalação, **origem/propriedade e localização opcionais**, consulta/edição/exclusão. Lançar isoladamente.
- **V2 — Perfil de rede e topologia declarada:** operadora, velocidade contratada declarada, associação voluntária de equipamentos a Ambientes e **relações entre aparelhos cadastrados**, com tipo de ligação (Ethernet/Wi-Fi/fibra/outro/não sei). Quando houver 2+ equipamentos, sugerir “Este aparelho está conectado a qual?” com opção Pular/Não sei. Não prometer descoberta/topologia automática.
  - Especificação detalhada da V2: [Perfil de rede, plano contratado, vínculos e visão consolidada](PROPOSTA_MINHA_REDE_V2.md), com issues #285, #284, #286 e #287; **execução somente após validar V1**.
- **V3 — Recomendações fundamentadas:** comparação de capacidades registradas com medições válidas e condições observadas; indicação explícita de evidência insuficiente. Não atribuir causalidade sem base.
- **V4 — Assist contextual:** perguntas e orientações usando somente campos autorizados pelo usuário + medições elegíveis; memória de ações e reteste, com consentimento e transparência.

**Benefício da V1:** a pessoa informa ou fotografa marca/modelo, a IA pesquisa preferencialmente a documentação oficial, apresenta a ficha técnica com fontes e o usuário confirma os dados e o papel do aparelho em sua rede. A V1 ainda não promete recomendar troca com base em medições.

### Limites de UX

- Fluxo: **Minha Rede → Adicionar equipamento → Digitar marca/modelo OU Fotografar etiqueta → Confirmar modelo/revisão → Buscar ficha técnica com IA → Conferir dados/fontes → Indicar papel na minha instalação → Propriedade/origem e local (opcionais) → Salvar → Detalhes**. Na V2, ao existir outro aparelho cadastrado, oferecer associação opcional entre eles. Se estiver offline, salvar dados manuais e oferecer completar a ficha depois.
- CTA principal: **Adicionar equipamento**. A câmera é alternativa, não barreira.
- Tela vazia explica o benefício em linguagem comum; um único equipamento deve funcionar sem cadastrar plano, cômodos ou criar conta. A pesquisa externa requer internet e pode falhar sem impedir cadastro.
- Dados não identificados aparecem como **Não informado**, nunca como especificação deduzida.
- A Home de teste continua simples; o cadastro não dispara speed test nem exige cadastro para medir.
- Evitar cardização excessiva; usar listas/seções nativas e estrutura visual do Linka existente.

## 2. V1 — contrato de dados proposto

Criar modelo independente, por exemplo `RegisteredNetworkDevice`, em módulo de inventário (`NetworkInventory`) ou no agrupamento modular que a implementação confirmar adequado.

| Campo | Obrigatório? | Regra |
|---|---|---|
| `id: UUID` | sim | Identidade estável |
| `kind` | sim | `modem`, `router`, `modemRouter`, `ont`, `meshNode`, `extender`, `other` |
| `brand` | não | Marca confirmada ou preenchida manualmente |
| `model` | sim | Texto confirmado pelo usuário |
| `hardwareRevision` | não | Revisão/versão de hardware (ex. V2/V3/V4) necessária para desambiguar fichas distintas |
| `installedRole` | não | `mainRouter`, `accessPoint`, `repeater`, `meshSatellite`, `fiberTermination`, `bridge`, `other`, `unknown`; indicação do usuário, NÃO dedução técnica definitiva |
| `fiberDirectConnected` | não | `yes/no/unknown` declarado e confirmado pelo usuário; diferente de capacidade física de porta óptica |
| `nickname` | não | Nome livre, ex.: “Roteador da sala” |
| `ownershipSource` | não | `userOwned`, `ispProvided`, `thirdParty`, `unknown` — declarado pela pessoa; **não inferir fabricante/operadora pela marca** |
| `installationLocation` | não | Local/cômodo informado manualmente; texto editável e/ou referência estável a `NetworkEnvironment.id` existente, sem atribuição automática a medições |
| `specifications` | não | Dados estruturados e validados com referência de fonte por atributo, data de consulta e estado `verified/unverified/unknown` |
| `enrichmentStatus` | não | `notRequested/loading/partial/complete/failed` para recuperação e novas consultas |
| `createdAt`, `updatedAt` | sim | Datas de alteração |

Especificações opcionais: padrão Wi-Fi, bandas, taxas teóricas, portas Ethernet, **tipo de entrada WAN (RJ45/fibra/SFP quando verificável)**, papel suportado (router/AP/repeater), capacidade mesh e revisão de firmware **somente com fonte rastreável adequada à revisão de hardware**. Incluir `sourceType` (`user`, `manufacturer`, `curatedCatalog`, `thirdPartyUnverified`), `sourceReference`, `retrievedAt` e status da verificação por campo. Uma resposta da IA não é uma fonte de verdade. Dados confirmados manualmente não são automaticamente “homologados pelo fabricante”.

**Não capturar na V1:** número de série, credenciais, senha Wi-Fi, MAC/BSSID, dados da etiqueta sem utilidade. Não reaproveitar credenciais existentes para o inventário. Etiquetas podem conter senhas e outros dados pessoais.

### Contrato canônico de ficha técnica (padronização para Linka)

O resultado da IA **não será armazenado como texto livre**. O backend deve normalizar respostas para um contrato versionado (exemplo conceitual abaixo). Cada atributo pode ser `null`/desconhecido e precisa da sua evidência. **Modelo e revisão são chaves de correspondência**, mas não garantem que o equipamento da casa esteja no modo de operação esperado.

```json
{
  "schemaVersion": 1,
  "identity": {
    "brand": "TP-Link",
    "model": "Archer C6",
    "hardwareRevision": null,
    "marketRegion": "BR"
  },
  "deviceType": "router",
  "technicalCapabilities": {
    "wifiStandards": [],
    "bandsGHz": [],
    "lanPorts": null,
    "wanPorts": null,
    "wanMedia": "unknown",
    "fiberTermination": "unknown",
    "ethernetPortSpeedsMbps": [],
    "radioCapabilities": [],
    "supportsMesh": null,
    "meshTechnology": null,
    "supportedBackhaul": [],
    "supportedModes": [],
    "firmwareSupportStatus": "unknown"
  },
  "installation": {
    "role": "unknown",
    "fiberArrivesHere": "unknown",
    "ownershipSource": "unknown",
    "installationLocation": null,
    "confirmedByUser": false
  },
  "evidence": [],
  "enrichmentStatus": "partial",
  "lastCheckedAt": null
}
```

**Convenções obrigatórias:** todos os apps/clientes usam os mesmos nomes, unidades, enums e significados; versões de schema devem ter migração; `unknown` ou `null` não significam `false`; `capability` não se confunde com `configuration` nem com `measurement`. `wanMedia` usa valores tipados (por exemplo `ethernet`, `fiber`, `mixed`, `unknown`); `fiberTermination` expressa capacidade documentada e não afirma como a residência está conectada. `installation.role` e `installation.fiberArrivesHere` são **declarados/confirmados pelo usuário**, não derivados de busca. O esquema exato deve ser validado nos pacotes e testes antes da implementação.

A IA/serviço pesquisa a documentação e devolve **campos canônicos + evidências por atributo**; se a fonte corresponder a outra variante ou houver conflito, o atributo permanece desconhecido. Os campos localmente salvos terão procedência `userDeclared`, `manufacturerDocumented` ou `unverified` conforme o caso. A interface distingue o que foi pesquisado, o que a pessoa confirmou e o que foi efetivamente medido pelo Linka.

### Campos necessários para futuras avaliações de adequação e troca

A V1 **cria a estrutura e tenta preencher capacidades documentadas**; não obriga o usuário a fornecer todas as informações nem antecipa o algoritmo de recomendação. Organizar os dados em três grupos separados:

| Categoria | Dados a armazenar, quando disponíveis | Origem e fase |
|---|---|---|
| **Identidade da variante** | Fabricante, modelo, revisão de hardware, região, tipo de equipamento | Usuário + pesquisa oficial, V1 |
| **Capacidades Wi-Fi** | Padrões IEEE (Wi-Fi 4/5/6/6E/7 quando documentado), bandas 2,4/5/6 GHz, largura máxima de canal por banda, taxa PHY anunciada **por banda**, streams espaciais/MIMO por banda (se documentado) | IA + manual/datasheet com fonte, V1 |
| **Capacidades cabeadas/fibra** | Número de portas e velocidades nominais LAN/WAN por porta (ex.: 100/1000/2500 Mbps), mídia WAN Ethernet/óptica/SFP, padrão de terminação de fibra quando houver (GPON/XGS-PON, se documentado) | IA + manual/datasheet, V1 |
| **Topologia possível** | Modos suportados (roteador, AP, bridge, repetidor), tecnologia Mesh específica (não confundir EasyMesh/OneMesh/mesh proprietário), suporte de backhaul Ethernet/Wi-Fi | IA + manual/datasheet, V1 |
| **Ciclo de vida** | Versão/linha de firmware publicamente documentada, suporte/atualizações quando verificáveis, datas de lançamento/descontinuação somente com fonte | IA + fonte oficial, V1, todos opcionais |
| **Instalação real** | Qual aparelho é principal; se recebe fibra; posição/cômodo, equipamento a montante/jusante e tipo de ligação real (cabo ou Wi-Fi) | Papel básico declarado e confirmado, V1; relações/cômodos detalhados, V2 |
| **Demanda da casa** | Operadora, plano de download/upload contratado, quantidade aproximada de dispositivos, principais usos (jogos, vídeo, trabalho) e problemas relatados | Declaração do usuário, V2; opcional |
| **Evidências observadas** | Download/upload, RTT, jitter, perda, responsividade sob carga, bandas/SSID/sinal **apenas se disponíveis confiavelmente na plataforma**, ambiente e data de teste | Medições reais já existentes ou futuras do Linka, associadas de forma explícita, V3 |

**Exemplos de avaliação futura:** (a) plano de 600 Mbps vs porta WAN de 100 Mbps documentada pode indicar limitação potencial, dependendo da topologia; (b) cobertura ruim em cômodo distante não implica troca do roteador sem medições/contexto; (c) roteador com Wi-Fi 6 não prova experiência Wi-Fi 6 no aparelho do usuário. **Nunca concluir causa raiz apenas por ficha técnica ou velocidade teórica de rádio.** Distinguir capacidade máxima teórica, limite físico, configuração declarada e resultado medido.

**Validação da IA:** propriedades internas opcionais podem ser `null`/`unknown`, mas não receber um valor default fabricado. Taxas devem ter unidade explícita (Mbps), largura de canal em MHz, bandas em GHz, e cada propriedade um `evidenceRef` verificável. Divergências entre versões/revisões permanecem não verificadas até o usuário escolher a variante correta. Não inferir porte do roteador, cobertura em m² ou número máximo de clientes quando o fabricante não documentar metodologia confiável.

**Implicação de arquitetura:** a ficha técnica da V1 é **reaproveitável pelo Assist**, com `schemaVersion`, proveniência e compatibilidade retroativa. Dados sobre a residência não devem ser confundidos com características do modelo. Futuras decisões de recomendação deverão conferir suficiência/atualidade de dados, origem e plataforma antes de concluir que vale investir em outro equipamento.

### Complemento — propriedade, local e conexões entre equipamentos

**V1, coleta leve e opcional:**
- **De quem é o equipamento?** “Meu”, “Fornecido pela operadora”, “Outro” ou “Não sei”. É uma declaração de origem/posse, não inferência da ficha técnica; o fato de ser fornecido pela operadora não comprova bloqueios nem contrato de comodato.
- **Onde está instalado?** Escolher um Ambiente já existente (por ID estável) ou preencher um rótulo de localização, como “Sala”. Não exigir cômodo, nem deduzir automaticamente pela rede Wi-Fi, SSID ou GPS. Ambientes no Linka atualmente são nomes associados manualmente a medições; **associar um equipamento a um Ambiente não atribui medições automaticamente**, nem muda o comportamento existente.
- Os dois campos devem permitir “Não sei”/“Prefiro não informar”, edição e remoção. Não enviar nomes de ambientes ou posse ao serviço de pesquisa técnica: ele precisa somente de marca/modelo/revisão/região.

**V2, relações de rede declaradas progressivamente:**
- Se houver **mais de um equipamento cadastrado**, após salvar oferecer: “Quer indicar a qual equipamento este está conectado?”. Opções “Escolher equipamento”, “Não sei” e “Agora não”. Não perguntar a quem possui um único aparelho nem impedir salvar.
- Associar **dois IDs persistentes de equipamentos** e um `connectionMedium` padronizado: `ethernet`, `wifi`, `fiber`, `other`, `unknown`. Quando conhecido, registrar quem está a montante (de onde vem a ligação) e quem está a jusante; direção e meio podem ficar desconhecidos.
- Contrato futuro sugerido: `DeviceConnection { id, upstreamDeviceId?, downstreamDeviceId?, endpoints: [deviceId,deviceId], connectionMedium, declaredByUser, updatedAt }`. Refinar o contrato antes do código: não duplicar pares invertidos, não permitir conexão consigo mesmo e tratar exclusão de equipamento limpando relações; exigir IDs existentes. Relações ainda não coletadas não são ausência comprovada de conexão.
- A IA pode explicar modos suportados e sugerir perguntas, mas **não descobrir a topologia real** apenas pelo modelo do roteador, gateway ou nome da rede. Não realizar scanner local nem automatizar login em roteadores.
- UI futura: lista simples “Conectado a: ONT da operadora — por cabo” dentro da ficha; **não exigir mapa gráfico**. Priorizar correção e edição manual; uma topologia visual é evolução opcional.
- O Assist futuro distinguirá **dado de catálogo** (capacidade de porta/rádio), **dado declarado da instalação** (posse, cômodo, vínculos) e **métrica observada**. Isso ajuda a investigar gargalos, mas **não prova causa raiz**.

**Exemplo declarado:** “Fibra → ONT Nokia (fornecida pela operadora, sala) → Ethernet → Archer C6 (meu, sala, roteador principal) → Wi‑Fi → repetidor (meu, corredor)”. Todos os vínculos dependem de confirmação da pessoa.

**Estratégia de entrega:** gravar propriedade e localização na V1 com campos opcionais, sem comprometer cronograma de IA/ficha; **modelar a possibilidade de relações versionadas desde a V1**, mas entregar a edição de ligações/topologia na V2. Não exigir plano contratado ou leitura de medições para fazer o cadastro.

## 3. Identificação por fotografia

1. A pessoa escolhe fotografar a etiqueta (câmera ou seleção de imagem).
2. Rodar OCR **no dispositivo** (Apple Vision) primeiro; detectar candidatos a marca/modelo por heurística, sem presumir que texto reconhecido esteja correto.
3. Exibir sugestão editável e pedir confirmação explícita.
4. A fotografia é descartada após extração por padrão; não incluí-la em sincronização, analytics ou payload de Assist.
5. Falha de leitura retorna ao campo manual sem impedir cadastro.
6. **A IA remota de pesquisa técnica faz parte da V1**, mas recebe por padrão apenas marca, modelo, versão de hardware e região após confirmação. **Não enviar a foto da etiqueta ou OCR bruto** por padrão. Informar ao usuário que a ficha será pesquisada online e qual serviço processa os dados; exigir escolha explícita para qualquer envio adicional.
7. OCR identifica **texto de etiqueta**, não autentica fabricante nem garante ficha técnica correta.

### Enriquecimento técnico com pesquisa na web + IA (requisito V1)

A IA **não possui pesquisa na internet automaticamente**. Implementar um serviço remoto de enriquecimento com busca/retrieval explícitos e resposta estruturada:

1. Com modelo e revisão confirmados, o app consulta um backend existente ou novo endpoint seguro (`DeviceSpecEnrichmentService`; avaliar o Worker atual do Assist).
2. O backend pesquisa fontes públicas, dando prioridade ao fabricante/manual/datasheet da **mesma variante regional e revisão**. Não aceitar snippets isolados como verificação completa; recuperar páginas/documentos quando permitido.
3. O serviço usa um modelo de IA para extrair/normalizar um **JSON tipado** de atributos, cada um com URL, referência e confiança; rejeitar URLs não rastreáveis, contradições ou informação de outra variante.
4. A interface exibe a ficha proposta, cita as fontes e permite revisar/corrigir antes de armazenar. Ausência, conflito ou versão indefinida são estados explícitos.
5. Guardar **snapshot local de especificações e fontes** no inventário. Usar cache no backend por marca+modelo+revisão+região (com prazo de validade), controle de custo/rate limit e timeout. Sem busca bem-sucedida, cadastro manual continua utilizável.
6. Para a V1, o usuário pode acionar **Atualizar especificações**; mudanças relevantes exigem nova revisão/confirmacão, sem sobrescrever silenciosamente dados salvos.
7. Testar modelos inexistentes, descrições conflitantes, variantes semelhantes, falta de conectividade, erro de serviço, JSON inválido e páginas com conteúdo adversarial (instruções na web não podem comandar a IA ou ações do app).

**Dois conceitos diferentes no cadastro:**
- **Capacidade física do equipamento** (pode receber fibra diretamente? tem porta óptica/ONT/SFP? funciona em modo roteador/AP?) é informação técnica pesquisável.
- **Papel real na casa** (é o principal? está em AP? é o aparelho onde chega a fibra?) depende da instalação. A IA pode sugerir possibilidades e fazer perguntas, mas não deve afirmar o papel sem confirmação do usuário ou prova confiável específica.

**Exemplo:** TP-Link Archer C6 dispõe de entrada WAN Ethernet e modos roteador/AP; sem porta óptica direta nas variantes documentadas, normalmente depende de ONT/modem da operadora para terminar fibra. Porém somente o usuário pode confirmar se ele é o principal, está atrás do modem/ONT ou atua como AP. A TP-Link publica versões V2/V3/V4 etc., com diferenças de especificações; exigir identificação da revisão quando isso importar. Referências: https://www.tp-link.com/br/home-networking/wifi-router/archer-c6/v3/ e https://www.tp-link.com/br/support/download/archer-c6/v3/

A pesquisa com IA faz parte do benefício central da V1, **não** de uma fase futura. A forma exata de pesquisa e provedores deve ser decidida após análise de custo, termos e capacidade do backend existente.

## 4. Arquitetura e persistência

**Código vigente a preservar:** `LinkaApp` SwiftUI, `LinkaModules`, `NetworkProfiles` (Ambientes), `MeasurementHistory`, `NetworkAssist` e `RouterDiscoveryView`.

Sugestão de composição:

```text
MinhaRedeView / DeviceFormView / DeviceDetailsView
             ↓
     NetworkInventoryRepository (protocol)
             ↓
       armazenamento local versionado
             ↑
   DeviceLabelOCRService (Vision, efêmero)
             ↓ (somente marca/modelo/revisão confirmados)
   DeviceSpecEnrichmentService → backend/Worker → busca web + leitura de fontes → IA JSON tipado → validação de evidências
```

- Preferir repositório local isolado do histórico de medições, com gravação atômica, versionamento de schema, migração e testes de persistência; reavaliar se existe infraestrutura reutilizável suficiente antes de criar pacote novo.
- **Cadastro manual** funciona offline e independe de autenticação, StoreKit, backend ou Assist; **enriquecimento automático com IA** exige internet, serviço remoto e orçamento/limite de consultas. A ficha salva segue acessível offline.
- Não vincular automaticamente equipamentos a SSID ou gateway. Um mesmo gateway IP aparece em redes distintas; identificação de gateway não é identificação garantida de um roteador.
- Não modificar `LinkaEngine` para suportar inventário.
- **Sem CloudKit na V1** até definir conflitos, exclusões e privacidade; explicitar dados locais na interface. Nunca persistir fotos/etiquetas brutas remotamente por padrão; uso da IA deve ter disclosure e política compatíveis.
- Reusar estilo, acessibilidade, localização e padrões de navegação existentes.
- Adicionar eventos analíticos apenas abstratos (ex.: cadastro concluído), sem imagem, modelo, serial, endereço ou senha.

## 5. Integrações e conflitos a reconciliar

- A documentação de produto vigente (04/10) define o Linka primordialmente como speed test e exclui expansões de equipamentos sem decisão explícita. Esta proposta é a **nova direção solicitada**; sua aprovação exige atualizar `documentacao/PRODUTO.md`, `ARQUITETURA.md` e eventuais instruções de agentes, para não haver orientação conflitante.
- `Ambientes` atuais são locais nomeados, associados manualmente a medições, **não** cômodos inferidos por SSID. Na V1, um equipamento pode referenciar um Ambiente existente **sem afetar medições/assignments**. Na V2, expandir relações de instalação, sem migração automática de medições. Validar integridade ao excluir/renomear um Ambiente.
- [#142](https://github.com/gmmattey/linka/issues/142) e [#179](https://github.com/gmmattey/linka/issues/179) cuidam do **painel do roteador**; não duplicar descoberta, gestão de credenciais ou leitura de interface administrativa. As duas issues apresentam decisões diferentes sobre credenciais; resolver em trabalho próprio, fora deste inventário.
- [#169](https://github.com/gmmattey/linka/issues/169), [#197](https://github.com/gmmattey/linka/issues/197), [#125](https://github.com/gmmattey/linka/issues/125) e [#56](https://github.com/gmmattey/linka/issues/56) se relacionam a diagnóstico/Assist; não assumir que o novo contexto já está sendo enviado ao NDS.
- [#121](https://github.com/gmmattey/linka/issues/121) é épico anterior de “mais que um speedtest”, com quatro pilares distintos. Este plano constitui **um novo programa** sem reabrir indevidamente aquele escopo.

## 6. Critérios de aceite V1

- [ ] Cadastrar manualmente roteador, modem, ONT, mesh/extensor e outros com modelo obrigatório.
- [ ] Fotografar etiqueta e sugerir marca/modelo/revisão **editáveis**, com OCR local e tratamento de permissões.
- [ ] Pesquisar informações técnicas na web por meio de backend+IA e exibir ficha estruturada, com URL e origem por atributo; confirmar antes de salvar.
- [ ] Perguntar e registrar papel real na instalação (principal/AP/repetidor etc.) e se a fibra chega diretamente nele, permitindo “Não sei”.
- [ ] Registrar opcionalmente se é equipamento próprio ou fornecido pela operadora e sua localização; seleção de Ambiente existente não modifica associações de medições.
- [ ] Preparar contrato versionado para relacionamentos entre equipamentos sem afirmar topologia automática; UI opcional de ligação após 2+ equipamentos fica na V2.
- [ ] Mostrar diferença entre “equipamento suporta X” e “equipamento está configurado como X”, sem inferência indevida.
- [ ] Confirmar cadastro mesmo quando OCR, busca, IA ou fontes técnicas falharem; permitir completar depois.
- [ ] Listar, abrir detalhes, editar e excluir com confirmação quando apropriado.
- [ ] Persistir e recuperar registros após encerrar/reabrir o app, inclusive offline.
- [ ] Não salvar/uploadar foto, senha, serial ou outro texto bruto da etiqueta.
- [ ] Não apresentar ficha técnica não verificada como fato; versionar fonte/variante e tratar incompatibilidades de revisão.
- [ ] Não confundir cadastro manual com equipamento automaticamente detectado.
- [ ] VoiceOver, Dynamic Type, localização pt-BR, estados vazios/erro e teste em iPhone real.
- [ ] Testes automatizados para modelagem, serialização, versionamento, OCR interpretado e operações CRUD.
- [ ] Sem regressão nos fluxos de medição, Histórico, Ambientes, Assist, Otimização e Ferramentas.
- [ ] Decisão explícita de plataformas da primeira distribuição: **proposta iPhone/iPad primeiro**; macOS e sincronização em fase posterior, sem promessa automática de paridade.

## 7. Estratégia de execução no GitHub

1. Revisar e incorporar esta proposta de produto (decidir Free/Plus e escopo iPad/macOS).
2. Abrir **um épico de reposicionamento** com V1–V4, vinculado à presente proposta.
3. V1 em issues implementáveis: **modelo/repositório (incluindo posse, local e extensibilidade para conexões)**, **UX CRUD/papel/local**, **foto/OCR**, **pesquisa web + IA estruturada**, **ficha técnica/integração/QA**. V2 adicionará ligação manual entre equipamentos.
4. Executar nessa ordem com dependências explícitas, PRs pequenos e testes; não abrir todas as implementações V2–V4 enquanto o contrato da V1 não estiver estabilizado.
5. Atualizar materiais da App Store/ASO quando a funcionalidade estiver implementada e validada, não antes.

### Recomendações comerciais iniciais

- **Cadastro e visualização básicos gratuitos**, para não criar barreira na nova proposta de valor.
- Diagnóstico contextual e recomendações avançadas são **candidatos futuros** a benefício do Linka+, sem declarar paywall da V1 ou preço no código.
- Avaliar sucesso técnico por conclusão do cadastro, falhas de OCR, retenção de dados, crashes e clareza das respostas — sem transformar a implementação em experimento que bloqueie o lançamento.
