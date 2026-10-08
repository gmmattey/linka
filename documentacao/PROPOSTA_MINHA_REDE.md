# Proposta de produto e especificação técnica — Minha Rede (Linka)

**Status:** proposta para revisão; não equivale a implementação nem a decisão já incorporada aos quatro documentos oficiais.
**Data:** 2026-10-08
**Repositório:** `gmmattey/linka`
**Intenção:** reposicionar o Linka de speed test com interpretação para **assistente pessoal da rede doméstica**, sem perder a confiabilidade das medições.

## 1. Decisão de produto e experiência

**Princípio:** a pessoa cadastra o que possui uma vez; o Linka passa a contextualizar orientações considerando os equipamentos e, progressivamente, seu plano, ambientes e medições.

- Área de produto proposta: **Minha Rede**. Não criar um segundo aplicativo.
- **V1 — Meus equipamentos:** cadastro manual, preenchimento assistido por foto, consulta/edição/exclusão e informações técnicas **confirmadas**. Lançar isoladamente.
- **V2 — Perfil de rede:** operadora, velocidade contratada declarada, associação voluntária de equipamentos a ambientes e relações manuais entre modem/roteador/extensores. Não prometer topologia automática.
- **V3 — Recomendações fundamentadas:** comparação de capacidades registradas com medições válidas e condições observadas; indicação explícita de evidência insuficiente. Não atribuir causalidade sem base.
- **V4 — Assist contextual:** perguntas e orientações usando somente campos autorizados pelo usuário + medições elegíveis; memória de ações e reteste, com consentimento e transparência.

**Benefício da V1:** a pessoa deixa registrado seu equipamento e pode consultar suas características e limitações documentadas; o app não promete, nessa fase, dizer se é hora de trocá-lo com base em medições.

### Limites de UX

- Fluxo: **Minha Rede → Adicionar equipamento → Digitar modelo OU Fotografar etiqueta → Conferir → Salvar → Detalhes**.
- CTA principal: **Adicionar equipamento**. A câmera é alternativa, não barreira.
- Tela vazia explica o benefício em linguagem comum; um único equipamento deve funcionar sem cadastrar plano, cômodos ou criar conta.
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
| `nickname` | não | Nome livre, ex.: “Roteador da sala” |
| `specifications` | não | Dados estruturados, com origem e nível de confiança explícitos |
| `createdAt`, `updatedAt` | sim | Datas de alteração |

Especificações opcionais: padrão Wi-Fi, bandas, portas Ethernet, capacidade mesh, referência de firmware **apenas quando provenientes de fonte confiável**. Incluir `sourceType` (`user`, `manufacturer`, `curatedCatalog`) e `sourceReference` quando aplicável. Dados confirmados manualmente pelo usuário não são “homologados pelo fabricante”.

**Não capturar na V1:** número de série, credenciais, senha Wi-Fi, MAC/BSSID, dados da etiqueta sem utilidade. Não reaproveitar credenciais existentes para o inventário. Etiquetas podem conter senhas e outros dados pessoais.

## 3. Identificação por fotografia

1. A pessoa escolhe fotografar a etiqueta (câmera ou seleção de imagem).
2. Rodar OCR **no dispositivo** (Apple Vision) primeiro; detectar candidatos a marca/modelo por heurística, sem presumir que texto reconhecido esteja correto.
3. Exibir sugestão editável e pedir confirmação explícita.
4. A fotografia é descartada após extração por padrão; não incluí-la em sincronização, analytics ou payload de Assist.
5. Falha de leitura retorna ao campo manual sem impedir cadastro.
6. **IA remota é opcional e futura**, não pré-requisito da V1. Se for usada depois, requer aviso claro, consentimento e filtragem/redução de dados sensíveis, sem expor a imagem completa por padrão.
7. OCR identifica **texto de etiqueta**, não autentica fabricante nem garante ficha técnica correta.

### Ficha técnica

Evitar pedir à IA para inventar especificações. Começar com dados básicos inseridos pelo usuário e, quando houver, catálogo com fontes rastreáveis (fabricante/documentação). Se não houver correspondência confiável, mostrar “Informações técnicas ainda não verificadas”, mantendo modelo/marca cadastrados. Não é requisito da V1 uma API paga de catálogo universal.

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
```

- Preferir repositório local isolado do histórico de medições, com gravação atômica, versionamento de schema, migração e testes de persistência; reavaliar se existe infraestrutura reutilizável suficiente antes de criar pacote novo.
- Cadastro funciona offline e independe de autenticação, StoreKit, backend ou Assist.
- Não vincular automaticamente equipamentos a SSID ou gateway. Um mesmo gateway IP aparece em redes distintas; identificação de gateway não é identificação garantida de um roteador.
- Não modificar `LinkaEngine` para suportar inventário.
- **Sem CloudKit na V1** até definir conflitos, exclusões e privacidade; explicitar dados locais na interface.
- Reusar estilo, acessibilidade, localização e padrões de navegação existentes.
- Adicionar eventos analíticos apenas abstratos (ex.: cadastro concluído), sem imagem, modelo, serial, endereço ou senha.

## 5. Integrações e conflitos a reconciliar

- A documentação de produto vigente (04/10) define o Linka primordialmente como speed test e exclui expansões de equipamentos sem decisão explícita. Esta proposta é a **nova direção solicitada**; sua aprovação exige atualizar `documentacao/PRODUTO.md`, `ARQUITETURA.md` e eventuais instruções de agentes, para não haver orientação conflitante.
- `Ambientes` atuais são locais nomeados, associados manualmente a medições, **não** cômodos inferidos por SSID; não migrá-los nem alterar sem plano específico da V2.
- [#142](https://github.com/gmmattey/linka/issues/142) e [#179](https://github.com/gmmattey/linka/issues/179) cuidam do **painel do roteador**; não duplicar descoberta, gestão de credenciais ou leitura de interface administrativa. As duas issues apresentam decisões diferentes sobre credenciais; resolver em trabalho próprio, fora deste inventário.
- [#169](https://github.com/gmmattey/linka/issues/169), [#197](https://github.com/gmmattey/linka/issues/197), [#125](https://github.com/gmmattey/linka/issues/125) e [#56](https://github.com/gmmattey/linka/issues/56) se relacionam a diagnóstico/Assist; não assumir que o novo contexto já está sendo enviado ao NDS.
- [#121](https://github.com/gmmattey/linka/issues/121) é épico anterior de “mais que um speedtest”, com quatro pilares distintos. Este plano constitui **um novo programa** sem reabrir indevidamente aquele escopo.

## 6. Critérios de aceite V1

- [ ] Cadastrar manualmente roteador, modem, ONT, mesh/extensor e outros com modelo obrigatório.
- [ ] Fotografar etiqueta e sugerir marca/modelo **editáveis**, com OCR local e tratamento de permissões.
- [ ] Confirmar cadastro mesmo quando OCR falhar ou não houver fonte técnica.
- [ ] Listar, abrir detalhes, editar e excluir com confirmação quando apropriado.
- [ ] Persistir e recuperar registros após encerrar/reabrir o app, inclusive offline.
- [ ] Não salvar/uploadar foto, senha, serial ou outro texto bruto da etiqueta.
- [ ] Não apresentar ficha técnica não verificada como fato.
- [ ] Não confundir cadastro manual com equipamento automaticamente detectado.
- [ ] VoiceOver, Dynamic Type, localização pt-BR, estados vazios/erro e teste em iPhone real.
- [ ] Testes automatizados para modelagem, serialização, versionamento, OCR interpretado e operações CRUD.
- [ ] Sem regressão nos fluxos de medição, Histórico, Ambientes, Assist, Otimização e Ferramentas.
- [ ] Decisão explícita de plataformas da primeira distribuição: **proposta iPhone/iPad primeiro**; macOS e sincronização em fase posterior, sem promessa automática de paridade.

## 7. Estratégia de execução no GitHub

1. Revisar e incorporar esta proposta de produto (decidir Free/Plus e escopo iPad/macOS).
2. Abrir **um épico de reposicionamento** com V1–V4, vinculado à presente proposta.
3. V1 em issues implementáveis: **modelo/repositório**, **UX CRUD**, **foto/OCR**, **ficha técnica verificada/integração/QA**.
4. Executar nessa ordem com dependências explícitas, PRs pequenos e testes; não abrir todas as implementações V2–V4 enquanto o contrato da V1 não estiver estabilizado.
5. Atualizar materiais da App Store/ASO quando a funcionalidade estiver implementada e validada, não antes.

### Recomendações comerciais iniciais

- **Cadastro e visualização básicos gratuitos**, para não criar barreira na nova proposta de valor.
- Diagnóstico contextual e recomendações avançadas são **candidatos futuros** a benefício do Linka+, sem declarar paywall da V1 ou preço no código.
- Avaliar sucesso técnico por conclusão do cadastro, falhas de OCR, retenção de dados, crashes e clareza das respostas — sem transformar a implementação em experimento que bloqueie o lançamento.
