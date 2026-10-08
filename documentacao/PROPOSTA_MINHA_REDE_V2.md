# Linka — Minha Rede | Fase 2: perfil e organização da rede doméstica

**Status:** especificação para revisão, não implementação aprovada.
**Data:** 2026-10-08.
**Programa:** [épico #278](https://github.com/gmmattey/linka/issues/278).
**Base necessária:** [V1 — Minha Rede](PROPOSTA_MINHA_REDE.md), em análise na [PR #277](https://github.com/gmmattey/linka/pull/277).
**Primeira tarefa já existente:** [#284 — relacionar equipamentos](https://github.com/gmmattey/linka/issues/284).

## 1. Intenção e valor da entrega

**V1 responde “Quais equipamentos eu tenho e o que cada um suporta?”.**
**V2 responde “Qual é meu plano e como a minha rede doméstica está organizada?”.**
**V3 responderá “O que os testes indicam e o que vale melhorar?”.**

A V2 deve fornecer um **perfil consultável, editável e progressivo**, sem exigir diagnóstico, escaneamento, conexão com operadora ou IA remota. A V1 entrega o inventário dos equipamentos; a V2 acrescenta contexto da contratação, vínculos entre os equipamentos e visão consolidada. O valor já existe antes da V3: a pessoa consegue entender e registrar a própria instalação.

### Incluído na V2
1. **Plano de internet:** cadastro manual da operadora e do serviço contratado.
2. **Organização da instalação:** visualizar os equipamentos por função e local, aproveitando informações da V1 e os Ambientes existentes.
3. **Conexões entre equipamentos:** registro **declarado** de ligações Ethernet, Wi-Fi, fibra e outras; pergunta opcional após cadastrar o segundo aparelho.
4. **Visão Minha Rede:** uma tela única que reúne serviço, equipamentos e conexões conhecidas, com estados incompletos honestos.
5. **Preparação para V3:** contratos duráveis e proveniência clara dos dados; não vincular medições automaticamente.

### Explicitamente fora da V2
- Determinar topologia, modelo, porta ou configurações lendo automaticamente roteadores ou escaneando a rede.
- Concluir “roteador defeituoso”, “operadora entregou menos”, “precisa comprar mesh” sem evidências.
- Conversa de IA contextual, recomendações comerciais, mudança de configuração ou testes de rede executados silenciosamente.
- Consulta obrigatória de fatura, contrato, APIs de operadora, Anatel ou catálogo de planos.
- Mapa gráfico interativo, planta da casa ou posicionamento automático por GPS/SSID.
- Obrigatoriedade de login, CloudKit, assinatura Plus ou pagamento para salvar perfil básico.

## 2. Jornada e arquitetura de informação

### 2.1 Minha Rede — visão geral

Entrada pela área **Minha Rede** (mesmo ponto de navegação definido na V1).

Ordem de conteúdo sugerida, com seções nativas e sem transformar a Home de velocidade em dashboard:

**Meu plano**
- Operadora: “Não informado” até cadastrar.
- Plano: “600 Mbps download · 300 Mbps upload”, somente se os dois números tiverem sido declarados; o que faltar continua **Não informado**.
- Tecnologia: Fibra (declarada), Cabo, DSL, Rádio/fixo sem fio, Satélite, Móvel, Outra ou Não sei.
- Ação contextual “Cadastrar plano” / “Editar plano”.

**Equipamentos**
- Lista já existente na V1 (ex.: ONT Nokia — Sala — da operadora; Archer C6 — Sala — meu; repetidor — Corredor).
- Ação “Adicionar equipamento”.
- Dado de localização é declaração do usuário, não medição da cobertura.

**Como estão conectados**
- Lista simples de relações informadas: “ONT Nokia → cabo → Archer C6” e “Archer C6 → Wi-Fi → Repetidor”.
- Aparecer somente com 2+ equipamentos, podendo mostrar estado vazio e CTA “Informar conexões”.
- Sem gráfico de rede na entrega mínima. Nunca desenhar ligação inferida da presença de dois dispositivos.

**Ambientes**
- Reutilizar ambientes nomeados já disponíveis. Um aparelho pode indicar um Ambiente (ID estável) ou localização textual sem criar automaticamente um Ambiente novo.
- Acessos à gestão existente, quando adequado; não criar nova implementação paralela de Ambiente.

**Estado incompleto**
- Cada seção explica o que está faltando e permite prosseguir depois.
- Nunca bloquear testes de velocidade/Histórico/Assist por falta de dados.
- Nenhum onboarding obrigatório ao abrir o app.

### 2.2 Cadastro do plano

Fluxo: `Minha Rede → Meu plano → Cadastrar/Editar → Salvar`.

Campos e linguagem:
- **Operadora**: nome livre, obrigatório **somente para salvar um plano cadastrado como identificado**, mas pode permanecer ausente sem bloquear o resto do perfil. Não construir lista fechada de marcas na V2.
- **Download contratado (Mbps)**: positivo, opcional.
- **Upload contratado (Mbps)**: positivo, opcional; **não assumir** que é igual ao download.
- **Tecnologia de acesso**: `fiber`, `cable`, `dsl`, `fixedWireless`, `satellite`, `mobile`, `other`, `unknown`. A escolha é declarada, não detectada.
- **Nome comercial do plano**: texto opcional, ex.: “Fibra 600”.
- **Valor mensal**: opcional; se preenchido, armazenar inteiro em centavos e moeda ISO 4217 (BRL para entrada padrão brasileira). Não enviar para analytics/IA.
- **Observação**: opcional e curta, se houver utilidade; **não** pedir CPF, endereço, número de contrato, login, senha ou fatura.
- **Vigência/alteração**: `effectiveFrom` opcional, `updatedAt` obrigatório, para não vincular uma medição antiga a um contrato novo sem contexto.

A UI oferece “Não sei”/“Não informar” para campos opcionais. Se a pessoa não souber o upload, salvar somente download. Validação de unidades numéricas e formatação regional; sem valores negativos, NaN, infinito ou `0 Mbps` como “desconhecido”.

**Escolha de escopo:** V2 pode começar com **um serviço ativo por perfil doméstico**, mas usar ID estável e separação de `NetworkServicePlan` para suportar múltiplos perfis/links no futuro. Não deduzir de SSID que todas as leituras do aparelho usam esse serviço. Na alteração de plano, preservar ao menos **registro de versões declaradas com data**, ou projetar contrato capaz de manter revisões sem sobrescrever contexto histórico; implementar o mínimo que evita atribuir retroativamente planos novos a medições antigas.

### 2.3 Registrar conexões entre equipamentos

Usar e detalhar a [issue #284](https://github.com/gmmattey/linka/issues/284).

Jornada: `Minha Rede → Equipamento → Conexões → Adicionar ligação → Selecionar outro equipamento → Informar tipo de conexão → Confirmar`.

- Exibir convite opcional após o 2º equipamento: **“Quer informar a qual equipamento ele está conectado?”**, com **“Agora não”** e **“Não sei”**.
- Tipo de ligação: **Cabo Ethernet**, **Wi-Fi**, **Fibra**, **Outro**, **Não sei**.
- Direção opcional: “A conexão vem deste aparelho”, “Vai para este aparelho” ou “Não sei”. Evitar expor `upstream`/`downstream` ao usuário leigo.
- Permitir editar ou remover ligações, inclusive com equipamentos em Ambientes distintos.
- Aceitar topologias incompletas; “não informado” **não** significa “não conectado”.
- Exemplo: Fibra da operadora → ONT Nokia (terminação declarada na V1), **Ethernet** → Archer C6, **Wi-Fi** → repetidor. O ponto externo “Internet/Operadora” é **somente representação conceitual**, não um dispositivo cadastrado artificialmente.
- **Meios físicos e função são coisas diferentes:** Wi-Fi não prova modo repetidor; Ethernet não prova conexão WAN; “tem entrada óptica” não prova chegada da fibra naquela casa.

Para dados estruturados, separar **aparelhos cadastrados**, **ligações declaradas** e **capacidade documentada do fabricante**. Não colocar o campo “Conectado a X” como texto solto no registro do dispositivo.

## 3. Contratos de dados sugeridos (tipados e versionados)

Esta proposta complementa `RegisteredNetworkDevice` da V1. Confirmar a implementação efetiva e preservar compatibilidade antes de codificar.

### 3.1 Perfil doméstico

```swift
struct HomeNetworkProfile: Codable, Identifiable {
    let id: UUID
    var displayName: String       // ex.: "Minha casa", editável
    var activePlanID: UUID?      // um plano ativo para este perfil na V2
    var createdAt: Date
    var updatedAt: Date
}
```

Um perfil por padrão na V2, **sem impedir migração** futura para múltiplas casas/redes. Se ainda não houver `HomeNetworkProfile` no projeto, sua criação não deve introduzir autenticação/sincronização obrigatórias nem duplicar `NetworkEnvironment`: **perfil = instalação doméstica; Ambiente = local nomeado para medição/equipamento**.

### 3.2 Serviço contratado (declaração)

```swift
struct NetworkServicePlan: Codable, Identifiable {
    let id: UUID
    let homeProfileID: UUID
    var providerName: String?
    var commercialName: String?
    var technology: AccessTechnology       // unknown permitido
    var downloadContractedMbps: Decimal?    // > 0
    var uploadContractedMbps: Decimal?      // > 0
    var monthlyPriceMinorUnits: Int?       // >= 0, se informado
    var currencyCode: String?              // ISO 4217, default BRL no formulário
    var effectiveFrom: Date?
    var declaredByUser: Bool               // verdadeiro na V2
    var createdAt: Date
    var updatedAt: Date
}
```

Os exemplos Swift são **contratos conceituais**, não APIs já existentes. Preferir serialização explícita/segura para `Decimal` ou um tipo inteiro de velocidade com escala definida (ex.: kbps), evitando ponto flutuante impreciso e validando limites de entrada. A decisão deve ficar registrada em schema/fixtures.

Atualização do serviço: preservar versões ou revisões suficientes para que a V3 não atribua uma medição de setembro ao plano registrado em outubro. **Não prometer vínculo automático retroativo.**

### 3.3 Conexões físicas/lógicas declaradas

```swift
struct DeviceConnection: Codable, Identifiable {
    let id: UUID
    let homeProfileID: UUID
    let endpointADeviceID: UUID
    let endpointBDeviceID: UUID
    var medium: ConnectionMedium           // ethernet/wifi/fiber/other/unknown
    var sourceDeviceID: UUID?              // direção declarada, quando conhecida
    var declaredByUser: Bool
    var createdAt: Date
    var updatedAt: Date
}
```

- Ambos os extremos precisam existir no inventário **do mesmo perfil**, distintos entre si.
- `sourceDeviceID` só pode ser um dos extremos. Nulo = direção desconhecida; não inferir automaticamente pela função ONT/AP.
- Evitar duplicar ligação idêntica ao inverter A/B; **não proibir dois tipos diferentes de ligação** entre um mesmo par se o usuário declarar explicitamente dois links (por exemplo, Ethernet + Wi-Fi).
- Permitir conexões que formam ciclo quando explicitamente declaradas; ciclo não comprova erro físico e não deve ser apagado automaticamente.
- Excluir equipamento deve remover/vincular limpeza das relações em transação consistente; renomear não quebra vínculo.
- `connectionMedium` informa meio declarado, **não é prova de velocidade do enlace**.

### 3.4 Ambientes e integridade

O código atual usa `NetworkEnvironment(id, name, ...)` e `EnvironmentMeasurementAssignment` no pacote `NetworkProfiles`, com persistência local em `FileNetworkProfileRepository`.

- **Não** alterar a semântica dos assignments por medição.
- O cadastro V1 já prevê `installationLocation`: a V2 deve **reutilizar** essa associação, não criar um segundo campo concorrente.
- Associar aparelho ao Ambiente **não associa medições** e não implica que todo teste daquele cômodo veio do mesmo roteador.
- Renomear Ambiente conserva UUID/vínculo; apagar Ambiente deve deixar localização do aparelho em estado “Não informado” ou usar rótulo local separado quando pré-existente, sem deixar referência órfã.
- Não vincular Ambiente a rede por SSID/BSSID como certeza. Ambientes são lugares declarados, não topologia detectada.

## 4. Composição e persistência

```text
MinhaRedeOverviewView
  ├─ PlanoInternetView / PlanEditorView
  ├─ RegisteredDevicesView (V1)
  ├─ DeviceConnectionsView / ConnectionEditorView (V2)
  └─ Ambientes (componente/fluxo existente)
           ↓
  HomeNetworkProfileRepository / NetworkServicePlanRepository
  NetworkInventoryRepository (V1) + DeviceConnectionRepository (V2)
  NetworkProfiles (Ambientes existentes)
           ↓
    stores locais versionados, testáveis, gravação atômica
```

**Decisão arquitetural inicial:** instanciar/compôr repositórios no LinkaApp/LinkaModules conforme padrão vigente. **Não** expandir `LinkaEngine`, `NetworkMeasurement` ou NDS apenas para registrar plano e relações. A V3 criará uma **projeção explícita e autorizada** de contexto para o Assist, com proveniência/idade das declarações e métricas elegíveis.

Persistência local, sem obrigar iCloud/conta. Se a V1 não estiver efetivamente integrada ao projeto, não executar V2 supondo contratos inexistentes: adaptar os exemplos aos tipos concretos da V1, sem reconstruir o inventário.

**Privacidade:**
- Plano, valor e relações ficam locais por padrão. Não compartilhar nome do Ambiente, provedor, preço, topologia ou endereço IP com o serviço de pesquisa técnica da V1.
- Sem armazenar credenciais, CPF, número do contrato, endereço físico, serial, MAC/BSSID ou foto de etiqueta em dados da V2.
- Logs/analytics somente eventos abstratos, sem valores declarados.
- Exclusão do perfil remove referências e dados relacionados conforme decisão explícita e segura; não apaga automaticamente medições de Histórico.
- O app informa que cada campo do plano/topologia é **declarado**, não detectado ou verificado.

## 5. Estados, mensagens e UX nativa

- **Sem equipamentos:** Minha Rede mostra CTA de cadastro V1; plano pode ser cadastrado independentemente.
- **1 equipamento:** exibir detalhes e plano; **não** convidar ligação entre equipamentos.
- **2+ equipamentos sem relações:** mostrar CTA “Informar conexões”, sem afirmar “equipamentos desconectados”.
- **Plano incompleto:** apresentar somente fatos conhecidos, “Upload não informado” em vez de preencher automaticamente igual ao download.
- **Sem rede/offline:** CRUD e visão geral funcionam; não usar IA remota nem consulta automática.
- **Ambiente apagado:** limpar referência no inventário sem quebrar Histórico.
- **Dispositivo excluído:** remover ligações relacionadas de forma consistente, sem apagar planos/Histórico.
- **Acessibilidade:** VoiceOver, Dynamic Type, foco/labels, teclado numérico localizado e estados vazios; layouts coerentes com iPhone/iPad. Mac é decisão de paridade separada, não promessa.
- **Monetização:** proposta de perfil doméstico básico Free; capacidades Premium avançadas permanecem discussão posterior, sem paywall nessa jornada.

## 6. Critérios de aceite integrados da V2

- [ ] Cadastrar/editar/excluir (ou limpar) o plano declarado sem exigir operadora/speed completos para uso de Minha Rede.
- [ ] Salvar download e upload separadamente, unidades corretas, sem completar ausência com zero ou espelhamento.
- [ ] Visualizar equipamentos com propriedade/localidade da V1 sem duplicar Ambientes.
- [ ] Criar, editar e excluir vínculos declarados entre dois ou mais equipamentos, com direção e meio desconhecidos permitidos.
- [ ] Sem auto-descoberta e sem renderização de ligação presumida.
- [ ] Persistir offline com schema versionado, migrações idempotentes e falha segura; preservar dados da V1.
- [ ] Nenhuma mudança automática em assignments de medição/histórico ao alterar equipamento/ambiente.
- [ ] Excluir equipamento remove ligações dependentes; exclusão/renomeação de Ambiente não deixa referências inválidas.
- [ ] Visão Minha Rede apresenta plano, equipamentos e ligações realmente cadastradas, inclusive estados incompletos.
- [ ] Sem envio de plano/preço/topologia/nomes dos Ambientes a IA ou analytics por padrão.
- [ ] Testes de modelos/repositórios/UI e revisão de VoiceOver, offline, regresso em medição/Histórico/Assist.
- [ ] Não confundir velocidade contratada com velocidade medida, nem tecnologia declarada com a detectada.

## 7. Sequenciamento e dependências

**Gate:** V1 concluída e revisada em código (schema real, UX, persistência), proposta de produto aprovada/documentos oficiais alinhados. A V2 não deve depender de implementação hipotética.

1. **V2-A — Perfil do serviço:** contrato/repositório, formulário do plano e revisões declaradas.
2. **V2-B — Relacionamentos:** ampliar a [#284](https://github.com/gmmattey/linka/issues/284); ligações declaradas com integridade por IDs.
3. **V2-C — Visão consolidada:** Meu plano + equipamentos V1 + Ambientes existentes + lista de conexões.
4. **V2-D — Integração/QA:** persistência/migração/offline, regressões e preparação explícita de leitura para V3.

**Ainda a decidir, sem bloquear especificação:** se a primeira distribuição da V2 terá paridade iPad/macOS; se armazenaremos planos históricos em revisão imutável ou log de mudanças (recomendação: preservar versão e vigência); se “valor mensal” entrará visível no MVP2 (é opcional e não essencial). Não prometer importação de operadora/fatura nem sincronização automática.

**Importante:** esta especificação não implementa a V2 nem afirma que o código atual tem esses tipos/telas.
