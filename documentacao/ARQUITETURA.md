# Arquitetura do Linka

Responsável: Camillo pelos contratos; Codex principal pela integração. Revisão: 2026-10-04, inspeção estática da base `39269c7a`, branch `docs/quatro-fontes`.
Este documento distingue implementação local, decisões preservadas e dependências ainda abertas. Não comprova operação externa, distribuição ou aceite em aparelho.
Os pares são [Produto](PRODUTO.md), [Operação](OPERACAO.md) e [Governança](GOVERNANCA.md): intenção, procedimentos e autoridade não são duplicados aqui.

## 1. Fronteiras e composição

O motor mede; adapters convertem fatos e integram APIs Apple; bibliotecas calculam, armazenam ou interpretam; SwiftUI apresenta. Nenhuma superfície deve reimplementar metodologia para satisfazer uma demonstração visual.

```text
LinkaEngine.SpeedTestCore → MeasurementState → SpeedTestViewModel
    → NetworkCore.NetworkMeasurement
        → MeasurementHistory ← MeasurementHistoryCloudKit
        → NetworkInsights / NetworkOptimization
        → NetworkAssist → NetworkDiagnostics → relay/NDS V2
        → NetscopeEvidence → UI com reader desabilitado
        → ShareCardView / resumo do widget
Histórico + assignments manuais → NetworkProfiles → baseline de ambiente
Sonda leve + contexto Apple → LiveTelemetryCollector → Home efêmera
NetscopeTransport: biblioteca injetável; ainda sem transporte real composto
```

| Fonte ativa | Responsabilidade / limite |
|---|---|
| [LinkaEngine](../aplicativo-ios/LinkaEngine/Package.swift) | Medição, fases, adaptação, cancelamento e falhas; sem dependência de histórico, StoreKit ou UI no manifest. |
| [NetworkCore](../aplicativo-ios/NetworkCore/Sources/NetworkMeasurement.swift) | Fatos, unidades, validação e envelopes de evidência compartilhados. |
| [MeasurementHistory](../aplicativo-ios/MeasurementHistory/Package.swift) / [CloudKit](../aplicativo-ios/MeasurementHistoryCloudKit/Package.swift) | Repositório local e sincronização por decorator, com mapper próprio. |
| [NetworkInsights](../aplicativo-ios/NetworkInsights/Package.swift) / [NetworkOptimization](../aplicativo-ios/NetworkOptimization/Sources/NetworkOptimization.swift) | Cálculos sobre entradas fornecidas; interpretação não altera a medição original. |
| [NetworkAssist](../aplicativo-ios/NetworkAssist/Package.swift) / [NetworkDiagnostics](../aplicativo-ios/NetworkDiagnostics/Sources/) | Porta/validação de interpretação e adapters HTTP/diagnóstico; não são o motor. |
| [LinkaModules](../aplicativo-ios/LinkaModules/Package.swift) | Factories, composição, aliases e gates; não constitui outro motor. |
| [LinkaApp](../aplicativo-ios/LinkaApp/Sources/) / [project.yml](../aplicativo-ios/project.yml) | Ciclo de vida, permissões, adapters e interfaces iPhone/iPad/Mac. Versões mínimas de pacote não garantem disponibilidade de cada API. |
| [NetscopeEvidence](../aplicativo-ios/NetscopeEvidence/Package.swift) / [NetscopeTransport](../aplicativo-ios/NetscopeTransport/Package.swift) | Projeção/codec e cliente atestado isolados de Assist/NDS; estado detalhado na seção 7. |

A composição do app tem autoridade sobre qual implementação é usada. Existência de protocolo, pacote, entitlement ou teste não prova integração, provisionamento ou execução.

## 2. Medição, ausência e telemetria

[SpeedTestCore](../aplicativo-ios/LinkaEngine/Core/SpeedTestCore.swift) produz estados reais de latência, download e upload; [SpeedTestViewModel](../aplicativo-ios/LinkaApp/Sources/Adapters/SpeedTestViewModel.swift) converte o resultado, captura contexto e coordena persistência/widget.
Uma execução limpa evidências anteriores e pausa a sonda viva. Cancelamento, background e troca de conexão não devem combinar fases de redes diferentes nem salvar uma execução cancelada como concluída.
`errorState(preserving:reason:)` conserva métricas já obtidas em falha fatal; isso não significa que todo resultado parcial seja persistido. O save automático observado ocorre no caminho `.done` não cancelado; falha do save não invalida a medição exibida.

`NetworkMeasurementContract` tem schema 1: `complete` exige download, upload e latência; `partial` exige ao menos uma métrica. Números são finitos e não negativos; perda é percentual entre 0 e 100. Mbps, ms e percentuais não são intercambiáveis. `nil` significa não medido/indisponível; zero só representa zero realmente medido.
`PacketProbeEvidence`, `RegionalGameReference` e `LoadResponsivenessEvidence` possuem semântica/versionamento próprios. Schema do registro, metodologia 1 e protocolo remoto V2 não são a mesma versão.

Responsividade confiável exige baseline e tráfego sustentado nas duas direções, descartando warm-up; integridade inconclusiva impede tratar os escalares do envelope como alta confiança. O caminho consumidor admite escalares legados sem envelope; não promover legado retroativamente a alta confiança.
Referência regional de jogos não é latência do servidor da partida. [LoadResponsivenessMeasurement](../aplicativo-ios/LinkaEngine/Core/LoadResponsivenessMeasurement.swift) e [avaliador](../aplicativo-ios/NetworkInsights/Sources/LoadResponsiveness.swift) definem medição versus consumo.

A Home não executa teste contínuo de banda: o ViewModel coleta RTT HTTP leve quando não mede; [LiveTelemetryCollector](../aplicativo-ios/LinkaModules/Sources/LiveTelemetryCollector.swift) mantém janela efêmera e [LiveUsageSuitabilityEvaluator](../aplicativo-ios/NetworkInsights/Sources/LiveUsageSuitability.swift) distingue aquecimento, inferência e dados insuficientes.
O loop composto usa intervalo de 3 s; o buffer admite 8 amostras/30 s e avaliação após 5. Throughput inferido requer teste completo, valores positivos, mesmo SSID e idade até 4 h. Não inferir banda por ping nem usar provedor como identidade da rede.
Troca de rede/background invalida buffer/baseline; retorno assíncrono não pode reaplicar contexto antigo. A sonda HTTP não é DNS isolado, apesar do nome interno `liveDnsLatencyMs`, e não entra no histórico como medição formal.

[NetworkInsights](../aplicativo-ios/NetworkInsights/Sources/NetworkInsights.swift) exclui ausências das estatísticas; tendência requer amostras/tempo suficientes. Gráfico com duas medições não prova tendência estatística.
[UsageSuitabilityEvaluator](../aplicativo-ios/NetworkInsights/Sources/UsageSuitability.swift) separa `adequate`, `limited`, `notAssessed`; vídeo/jogos exigem evidência compatível. Limiares numéricos e testes de fronteira ficam no código, sem uma segunda tabela documental a manter.
[ConnectionPathEvaluator](../aplicativo-ios/NetworkInsights/Sources/ConnectionPath.swift) fornece interpretação, não uma sonda de cada salto; indícios de carga/jitter não confirmam defeito do roteador.

## 3. Persistência, sincronização e saída de dados

Há contratos distintos, que não devem ser tratados como formatos equivalentes:

| Formato / fonte | Regra e limite |
|---|---|
| Swift `NetworkMeasurement` | Modelo local validado, com campos opcionais aditivos. |
| [Store JSON](../aplicativo-ios/MeasurementHistory/Sources/FileMeasurementHistoryRepository.swift) | Actor, schema 1, datas Foundation `.deferredToDate`, gravação atômica. Corrupção/versão desconhecida falham sem apagar automaticamente. |
| [Schema externo](arquitetura/contratos/network-measurement.schema.json) e [fixtures](arquitetura/contratos/fixtures/) | Intercâmbio ISO-8601, `additionalProperties: false`; não cobre todo o modelo Swift atual. Não prometer round-trip integral. |
| [Mapper CloudKit](../aplicativo-ios/MeasurementHistoryCloudKit/Sources/CloudKitMeasurementSync.swift) | Projeção explícita; campos locais ausentes no remoto não podem ser inventados no retorno. |

[LinkaMeasurementHistory.makeRepository](../aplicativo-ios/LinkaModules/Sources/History.swift) usa `Documents/measurements.json`, retenção `.unlimited` e instância compartilhada por URL; o provider de entitlement da primeira criação acompanha essa instância.
[SyncingMeasurementHistoryRepository](../aplicativo-ios/MeasurementHistoryCloudKit/Sources/SyncingMeasurementHistoryRepository.swift) mantém a fonte local e sincroniza em segundo plano conforme acesso. Container `iCloud.com.linka.assist`, private database, zona `MeasurementHistoryZone`, record `Measurement` são configuração de código, não prova de serviço provisionado.
Conflitos do mesmo ID preferem completo, maior preenchimento e data de modificação; o merge preenche ausências e valida. Tombstones preservam exclusões pendentes para evitar ressurreição enquanto a remoção remota não confirma.
O mapper leva métricas e blobs de probes, referência regional e responsividade, mas não `wifiContext`, `advancedWiFiDiagnostics`, `dnsResolutionMs`, `location` ou `devicePlatform`. Não há paridade integral local↔iCloud.
O schema externo também não representa todos esses campos/envelopes. Mudanças de contrato exigem decisão de compatibilidade, fixtures e testes dos consumidores; não basta atualizar o tipo Swift.

### Ambientes

[NetworkEnvironment / EnvironmentMeasurementAssignment](../aplicativo-ios/NetworkProfiles/Sources/NetworkProfile.swift) associam medições a ambientes por UUID e escolha explícita após resultado. Não inferem cômodo por SSID nem selecionam automaticamente o último ambiente.
[FileNetworkProfileRepository](../aplicativo-ios/NetworkProfiles/Sources/FileNetworkProfileRepository.swift) grava schema 2 em `Application Support/Linka/network-profiles-v1.json`: nomes, datas, IDs e assignments; não duplica métricas, SSID, BSSID ou fingerprint.
Migração do schema 1 conserva nome/ID/datas, descarta identidade/referências antigas e inicia assignments vazias. Escrita é atômica; versões desconhecidas/corrupção falham. Não retroatribuir medições.
[OptimizationProfileCoordinator](../aplicativo-ios/LinkaApp/Sources/Adapters/OptimizationProfileCoordinator.swift) deriva baseline do histórico elegível e exclui o resultado atual; contagem exibida não prova referência pronta. Remover ambiente não apaga histórico; leitura apagada deixa de contar. Ambientes/assignments são locais, fora do mapper CloudKit.

### Compartilhamento e widget

[ShareCardView / ShareCardRenderer](../aplicativo-ios/LinkaApp/Sources/UI/ShareCardView.swift) são a fonte única do cartão: `ImageRenderer` → PNG → compartilhamento nativo, sem screenshot da janela, sem recalcular métricas e sem SSID/provedor/IP/BSSID.
**Decisão preservada: compartilhar somente resultado concluído atual ou histórico**, mas MainView exige `.done`, enquanto [MeasurementDetailView](../aplicativo-ios/LinkaApp/Sources/UI/MeasurementDetailView.swift) e presenters checam medição não nula sem exigir `outcome == .complete`, portanto o gate uniforme e sua validação em runtime permanecem pendentes com Pedro/Tito antes de declarar o contrato integral; PNG inválido/ausente não é sucesso de compartilhamento.
O caminho inspecionado exporta um cartão individual; não foi localizado exportador CSV/PDF em lote. Não equiparar cartão, arquivo interno do store e contrato externo.
[LinkaWidgetShared](../aplicativo-ios/LinkaWidgetShared/Sources/LinkaWidgetShared.swift) guarda resumo Codable e idioma no App Group `group.com.linka.assist`, sem identificadores Wi-Fi. O app publica e recarrega a timeline; [provider](../aplicativo-ios/LinkaWidget/Sources/LinkaWidgetTimelineProvider.swift) usa `.never`, sem polling periódico. Dado ausente/indecodificável permanece ausente.

## 4. Capacidades Apple e serviços auxiliares

| Capacidade / fonte ativa | Contrato durável e fronteira |
|---|---|
| [App Intents](../aplicativo-ios/LinkaAppIntents/Sources/Contracts.swift) e [coordenador](../aplicativo-ios/LinkaApp/Sources/Adapters/AppIntentCoordinator.swift) | Ações tipadas reutilizam serviços/coordenadores; registro no código não comprova descoberta por Siri/Atalhos ou equivalência de todos os destinos no Mac. |
| Wi-Fi avançado — mesmo coordenador e [ApplePlatformSignalProvider](../aplicativo-ios/LinkaApp/Sources/Adapters/ApplePlatformSignalProvider.swift) | iOS importa opt-in por Atalho; Mac captura nativamente via CoreWLAN. Inbox sanitizada/deduplicada: JSON até 4096 bytes, até 30 s no futuro, validade 180 s. Associação temporal/rede/AP é conferida pelo ViewModel. BSSID cru vira hash com salt local; isso não prova anonimização universal. Ausência permite medir sem detalhes. |
| [NetworkOptimization](../aplicativo-ios/NetworkOptimization/Sources/NetworkOptimization.swift) | Regras locais por fatos, sem IA/persistência própria. Reteste exige completo, mesmo tipo e mesmo SSID no Wi-Fi; ainda não verifica explicitamente estabilidade de rota. Ação para Wi-Fi não se transfere por analogia a celular/Ethernet. |
| [DNSBenchmark](../aplicativo-ios/NetworkDNSBenchmark/Sources/NetworkDNSBenchmark.swift) e [coordenador](../aplicativo-ios/LinkaApp/Sources/Adapters/DNSBenchmarkCoordinator.swift) | `getaddrinfo` do sistema fica fora do ranking DoH. DoH usa IP bootstrap, SNI/Host do provider e deadline que cancela socket. Sessão UUID/caminho invalida resultados tardios; resultado é efêmero, não histórico/perfil. |
| [DNSConfigurationManager](../aplicativo-ios/LinkaApp/Sources/Adapters/DNSConfigurationManager.swift) | Configuração persiste via `NEDNSSettingsManager`; recarregar estado após save, não presumir aplicação. Comparar não implica poder aplicar: capability/provisionamento/assinatura são gates separados. |
| [GatewayDiscovery](../aplicativo-ios/NetworkDiagnostics/Sources/LocalGatewayDiscovery.swift) e [GatewayProber](../aplicativo-ios/NetworkDiagnostics/Sources/GatewayProber.swift) | Gateway local; probe HTTP/HTTPS sem celular/cache/redirect, prefere HTTPS. Resposta comprova endpoint acessível, não fabricante/autenticação. Abrir painel exige confirmação; não é scanner. [KeychainHelper](../aplicativo-ios/LinkaApp/Sources/UI/KeychainHelper.swift) só guarda senha por pedido. |
| [NetworkConnectivityTriage](../aplicativo-ios/NetworkConnectivityTriage/Sources/) | Piloto separado do engine/Assist: caminho + GET health/version, sem avaliação IA; relatório efêmero. Sessão sem cookies/cache e sem redirects; “local” não significa sem tráfego. Não atribuir causa sem evidência. |
| [ServiceStatusStore](../aplicativo-ios/LinkaApp/Sources/Adapters/ServiceStatusStore.swift) | GET catálogo/incidentes/detalhe; PUT instalação e subscriptions. Refresh também sincroniza instalação sem exigir opt-in a alertas. ID fica no Keychain; preferências/token em UserDefaults. Falha pode manter dados antigos; ausência de incidente não prova serviço saudável/fresco. |

Dados Wi-Fi avançados/importados não devem vazar por sincronização, cartão ou payload remoto por simples expansão do modelo. Cada consumidor mantém sua seleção explícita; declaração de entitlement não confirma permissão concedida nem provisioning.

## 5. Acesso e publicidade

[LinkaEntitlementSnapshotResolver](../aplicativo-ios/LinkaEntitlements/Sources/LinkaEntitlements.swift) prioriza compra verificada válida → promoção aplicável à plataforma/data → Free. [StoreKitEntitlementProvider](../aplicativo-ios/LinkaEntitlements/Sources/StoreKitEntitlementProvider.swift) e `ShortcutEntitlementSnapshot` compartilham o resolver nesta base: a antiga divergência promocional dos intents foi corrigida no código, sem dispensar teste físico.
Medição/histórico permanecem Free; capacidades adicionais usam `LinkaEntitlementPolicy` e decorators em [Entitlements.swift](../aplicativo-ios/LinkaModules/Sources/Entitlements.swift). Expert Mode controla exibição, não cálculo. DEBUG não é comprovação de compra; macOS não recebe a promoção atual.
Acesso a recursos e elegibilidade de anúncios são decisões separadas: promoção mantém anúncios; compra válida remove. Fronteira temporal ainda precisa revisão: oferta admite `date <= endsAt`, enquanto `validUntil <= date` expira o acesso.

[LinkaAdsCoordinator](../aplicativo-ios/LinkaApp/Sources/Adapters/Ads/LinkaAdsCoordinator.swift) invalida tasks/loader/anúncio por geração e identidade do loader quando muda compra/restauração/resolução. Medição pausa publicidade reversivelmente; terminar não dispara anúncio automaticamente.
A tentativa nativa por sessão é consumida antes do request real, não durante preparo cancelado. O app não solicita ATT; UMP/SDK continuam condicionados à elegibilidade, e compra paga não entra nessa trilha. App inativo aguarda nova tentativa sem consumir a sessão; medição e mudança de compra revogam continuações pendentes.
NPA, personalização e publisher first-party ID desabilitados precedem inicialização/request; callbacks revalidam geração. Isso não comprova ausência de tracking/coleta: manifesto, política, SDK e App Privacy devem concordar com o comportamento efetivo.

## 6. Assist atualmente composto

[AssistContainer](../aplicativo-ios/LinkaApp/Sources/Adapters/AssistContainer.swift) compõe `NetworkAssistService<BuildeaDiagnosticTransport>` sobre [BuildeaDiagnosticAPI](../aplicativo-ios/NetworkDiagnostics/Sources/BuildeaDiagnosticAPI.swift). Relay `/v2/assist`, timeout 55 s e `transportAuth: .relay` dispensam bearer do cliente; configuração admite overrides. Nenhum endpoint foi consultado nesta revisão.
[AssistViewModel.makeContext](../aplicativo-ios/LinkaApp/Sources/Adapters/AssistViewModel.swift) usa a medição atual e contexto declarado, com recentes vazios nesse caminho. Capacidade contratual de receber histórico não significa envio no app.
[NetworkAssistService](../aplicativo-ios/NetworkAssist/Sources/NetworkAssist.swift) valida fatos/IDs/números e exige evidência para `answered`; estrutura válida não garante veracidade de cada frase. [NDSRequestBuilder](../aplicativo-ios/NetworkDiagnostics/Sources/NDSRequestBuilder.swift) projeta o contrato remoto; envelopes locais novos não são enviados automaticamente.
V2 separa `raw` e explicação, preserva código/mensagem/retryable/request ID no erro; não há fallback de request para V1. A ponte de stream pode produzir um único evento final, sem provar streaming HTTP. Cancelamento deve alcançar a task de transporte.
Investigações/sugestões locais em `NetworkAssist` são independentes da chamada remota e não confirmam causa raiz. Reutilizar resultado versus exigir nova medição em toda entrada permanece decisão de jornada, não deve ser resolvida pela troca documental.

## 7. Netscope: base local presente, ativação remota pendente

Netscope interpreta snapshot permitido após resultado real; não mede, não substitui o resultado e não reutiliza regras, credenciais ou confiança de Assist/NDS. Compartilhar domínio com SignallQ não autoriza compartilhar estado.
O levantamento antigo que dizia “sem cliente Netscope” foi superado pelos módulos desta base. Isso não equivale a serviço remoto ligado:

| Etapa / código ativo | Implementação observada e limite |
|---|---|
| L01, inventário de evidência | Decisões incorporadas abaixo; elegibilidade planejada é maior que a projeção realmente implementada. |
| L02 — [NetscopeMeasurementEvidenceProjector](../aplicativo-ios/NetscopeEvidence/Sources/NetscopeEvidence.swift) | Download/upload/latência/jitter/perda, tipo de conexão e, só no Wi-Fi, banda canônica/taxa de link positiva. Filtra inválidos individualmente; ausência é omitida. Contexto declarado é separado. |
| Codec — [NetscopeV1Codec](../aplicativo-ios/NetscopeEvidence/Sources/NetscopeV1Codec.swift) | Wire `1.0.0`; objetivo obrigatório, locale/versão limitados, objetos de resposta fechados e evidência conferida contra valores enviados. `diagnostic_processing: true` é serializado; isso não implementa uma jornada de consentimento. |
| L03 — [NetscopeAnalysisView](../aplicativo-ios/LinkaApp/Sources/UI/NetscopeAnalysisView.swift) | MainView/MacMainView projetam resultado para sheet; `DisabledNetscopeAnalysisReader` permanece default e retorna `unavailable`, sem I/O. Evidência, limitações e contexto são seções distintas. Retry recarrega reader, não mede novamente. |
| L05 — [NetscopeAttestedAnalysisClient](../aplicativo-ios/NetscopeTransport/Sources/NetscopeAttestedAnalysisClient.swift) | Cliente/protocolos de atestação e HTTP injetáveis; sem URLSession, host ou Keychain concretos compostos no app. Só iPhone/iPad físicos são elegíveis; Mac/simulador/unsupported retornam indisponível antes da sequência. |

### Evidência, resposta e privacidade

`connection_kind` fecha em `wifi|cellular|ethernet|other|unknown`: fonte é API de plataforma, nunca velocidade/IP/SSID. `other` exige interface reconhecida; incerteza/caminho insatisfeito ou trocado deve ser `unknown`.
**Lacuna atual:** o sampler do ViewModel não testa `path.status` e retorna `.other` no fallback; o projector só transforma `nil` em `unknown`. Não declarar a matriz L01 integralmente cumprida.
L01 permite futuramente DNS, latências sob carga com integridade válida e canal nativo; o projector/codec atual não os transmite. Frequência não é derivada de banda/canal e permanece ausente. No iPhone/iPad não inventar detalhes que a API usada não fornece; no Mac usar apenas valores observados de CoreWLAN. Nenhuma permissão nova só para completar snapshot.
Proibidos na análise V1: SSID/BSSID/hash AP, RSSI, segurança, gateway/IP/admin URL, fornecedor/operadora, localização, IDs de medição/rede/servidor, horário bruto, histórico, envelopes/probes brutos e diagnóstico Wi-Fi avançado, inclusive importado. Não enviar relato livre; feedback futuro é estruturado.
`usage_context` orienta intenção, nunca é `evidence_used`. Resposta só cita fatos enviados como `system_observed`; codec rejeita campo desconhecido, referência inexistente/valor divergente e combinações inválidas de estado.
Estados atuais são `completed`, `inconclusive`, `unavailable`, `out_of_scope`; completed significa leitura recebida, não rede saudável. Insuficiência não vira sucesso; falha/timeout/custo/indisponibilidade não fabricam diagnóstico. Não expor prompt, chain-of-thought, provider secrets ou administração.

### Transporte e backend-alvo

L05 aceita origem HTTPS pura, sem credencial/query/fragmento/prefixo de rota. Sequência: challenge de registro → registro → body exato → binding `POST /v1/linka/analysis` + SHA-256 → challenge de assertion → assertion → no máximo uma chamada HTTP, sem retry.
Challenges de registro e assertion são distintos. O segundo hash cobre método, rota, bytes do body, nonce e timestamp Unix em ms, com campos prefixados por comprimento; não presume JSON canônico universal.
Cliente rejeita URL final diferente, HTTP não-2xx, JSON/resposta incompatíveis; erros lançados de atestação/timeout/cancelamento convergem a indisponível. Prazo/cancelamento efetivos precisam ser garantidos pelos adapters futuros, não são prova de execução nesta biblioteca.
[NetscopeProgressDecoder](../aplicativo-ios/NetscopeTransport/Sources/NetscopeProgress.swift) admite apenas `accepted`, `analysis_started`, `validating_result`; não transmite texto livre/raciocínio como progresso.

Arquitetura-alvo preservada: repositório privado `netscope-api`, Worker/D1/secrets/admin isolados por ambiente, inicialmente Workers AI; OpenAI/Gemini/Grok desligados até avaliação/autorização. Não se afirma aqui criação, deploy ou estado atual desse repositório externo.
Rotas planejadas sob `/v1/linka`: `attestation/challenge`, `attestation/register`, `analysis`, `feedback`, `health`; o desenho final dos dois challenges e OpenAPI externo exige reconciliação com L05. `/admin/*` usa audiência distinta. `api.signallq.com` é endereço proposto, não host embutido no cliente.
Servidor deve validar App ID/Team ID/ambiente/chave/contador, expiração e uso único; identidade pseudônima HMAC rotacionável, sem chave estática de provider no app. Falhas genéricas 401/403 não revelam qual verificação falhou.
Política preservada: sem quota por pessoa/instalação/trust tier e sem allowlist de pessoas; uso comercial pertence ao Linka. Proteção técnica de rajada/borda, body cap, concorrência, timeout, idempotência, reserva/ajuste de custo e teto global de emergência são distintos de limite de produto.
Modelo, URL, prompt, provider e tools nunca vêm do cliente; egress é restrito. Provider/modelo, qualidade, teto com responsável, kill switch e rollback exigem gate humano antes da ativação. O fallback Mac com chave local é proposta não adotada por L05; Mac segue desligado até decisão própria, sem “cota inferior” herdada.
Admin proposto: Access+MFA, viewer/operator/security_admin, sessão segura, CSRF, CORS restrito, reautenticação em mutações sensíveis e auditoria append-only; tokens do app não acessam admin, painel não gerencia secrets de provider.

Retenção abaixo é **proposta**, não jobs comprovados: instalações pseudônimas até 90 dias inativas; chaves enquanto ativas/limpeza por inatividade; challenges/replay por TTL de minutos/horas; custo global agregado por 30–90 dias; auditoria sanitizada de análise por 7–30 dias; políticas/admin audit conforme política operacional a fechar.
Métricas/contexto de conexão/uso são transitórios, não D1/log/prompt salvo/resposta textual; não guardar IP/identificadores crus/assertions. Detalhes de auditoria/HMAC e limpeza precisam de schema externo verificado. Consentimento, política pública, App Privacy e manifesto devem refletir a implementação antes de tráfego real.
Histórico completo da proposta, exemplos e sequência de PRs fica no [Git em 39269c7a](https://github.com/gmmattey/linka/blob/39269c7a9d2ed461fb944de09d5b27c34d3d1d4d/documentacao/arquitetura/NETSCOPE.md#registro-completo-de-decisões-e-expectativas-de-origem), como histórico, não segunda fonte vigente.

## 8. Interface e site: limites técnicos

SwiftUI compartilha modelos/coordenadores, não exige interfaces idênticas. [DesignSystem.swift](../aplicativo-ios/LinkaApp/Sources/UI/DesignSystem.swift) implementa tokens semânticos e adaptação Apple; [tokens CSS](design/design_system/tokens/), [componentes](design/design_system/components/) e [protótipo](design/prototipo/) são recursos, não implementação do motor nem prova de conformidade.
Não há geração automática garantindo equivalência CSS↔Swift. Preservar marca oficial, controles nativos, texto ampliado, teclado, VoiceOver e Reduzir Movimento; conformidade exige comparar todos os destinos/estados da build pretendida. Direção de produto Mac não autoriza redesign iOS por analogia.
[aplicacao-web](../aplicacao-web/package.json) é React/TypeScript/Vite institucional, sem speed test/PWA do produto. [App.tsx](../aplicacao-web/src/App.tsx) seleciona páginas por pathname; [LandingScreen](../aplicacao-web/src/screens/LandingScreen.tsx) depende de configuração para CTA/preço. Conteúdo, screenshots e rotas estáticas não comprovam comportamento ou publicação do app/host.

## 9. Pendências que esta consolidação não encerra

| Contrato / risco | Responsável; evento | Fechamento necessário |
|---|---|---|
| Motor: zero após todas as sondas falharem; prova física da referência regional; alta confiança versus legado | Camillo/Pedro/Tito; próxima mudança/release da metodologia | Tratar ausência sem zero inventado, reconciliar metodologia/testes e medir cancelamento, rede lenta, carga nas duas direções e protocolo regional em aparelho. |
| Save de parcial, rollback em falha de disco e zero no resumo do widget | Camillo/Pedro; próxima revisão de persistência | Decidir semântica, cobrir disco indisponível e consumidores; memória alterada antes de persistir não é gravação confirmada. |
| Schema externo/CloudKit incompletos; migração Ambientes e exclusão offline | Camillo/Tito; antes de ampliar sincronização/intercâmbio | Matriz campo a campo, round-trip, privacidade, migração/CRUD/assignments e dois aparelhos assinados com tombstones. |
| Insights: testes legados de jogos versus evidência exigida; 4K >25; causalidade do caminho; agrupamento legado por provedor | Íris/Camillo/Pedro; próxima mudança das regras | Decisão de limiares e fixtures coerentes, linguagem sem causa não medida e separação de redes distintas. |
| Home viva e paridade Apple | Tito/Íris; release afetada | Troca/background/0–8 amostras, baseline e estados/destinos acessíveis em build identificada; não herdar aceite visual histórico. |
| Assist: reuso de resultado, copy positiva sem causa e procedência “ChatGPT – Luna” sem modelLabel | Íris/Camillo/responsável NDS; próxima revisão do contrato | Separar ausência de achado de saúde, definir validade do contexto e só mostrar procedência comprovada. Codex confirma revogação da credencial histórica antes de encerrar segurança. |
| Otimização: estabilidade da rota; oportunidade de banda; Refazer referência | Íris/Camillo; quando priorizados | Decidir regra/escopo; comparador atual não garante rota estável, builder não implementa oportunidade de banda e baseline de ambientes é derivada. DoT/adapters de roteador seguem futuros. |
| Wi-Fi, DNS, roteador, StoreKit/ads e status | Tito/Codex; antes de release das capacidades | Atalho físico/parcial/expirado, provisioning DNS/aplicar/remover, painel sem permissão, persistência Keychain, compra/restauração/expiração, ausência do pedido ATT, consentimento UMP e NPA, frescor de status/APNs e disclosure do registro de instalação. |
| Netscope L01 versus L02/codec e consentimento | Camillo/Íris; antes de compor transporte | Resolver path insatisfeito→unknown, alinhar allowlist real/OpenAPI/fixtures e obter consentimento específico sem inferi-lo do campo true. |
| Netscope remoto: host, challenges, Keychain, App Attest, HTTP e orçamento | Camillo/operador backend/Luiz/Tito; antes de tráfego/custo | OpenAPI/commit externo, replay concorrente, redirects, timeout/cancelamento, prova física iPhone/iPad, avaliação do provider e teto/kill switch; Mac exige decisão separada. |
| Netscope privacidade/infraestrutura/marca | Codex/Luiz/operador; antes da ação dependente | Reconciliar autorizações já existentes de repo/domínio/recursos, retenção implementada, isolamento negativo SignallQ/NDS e clearance de marca; não reaprovar por inferência nem presumir produção. |
| Equipamentos/ofertas comissionadas | Íris/Luiz; somente se priorizados | Proposta futura desligada: sem busca/impressão/clique enquanto off; evidência→provider→guardrails, até três ofertas e transparência. APIs comerciais/compatibilidade não verificadas; sem oferta quando faltam fatos ou provider falha. |

Evidência desta revisão: leitura dos manifests, fontes e contratos acima, reconciliando arquitetura anterior, mapas das 15 capacidades, design e L01/L02/L03/L05. Detalhes históricos permanecem no Git; esta fonte não mantém cópias de planos nem os marca como entregues.
Fontes de testes para futuras mudanças: [engine](../aplicativo-ios/LinkaEngine/Tests/), [histórico](../aplicativo-ios/MeasurementHistory/Tests/), [CloudKit](../aplicativo-ios/MeasurementHistoryCloudKit/Tests/), [Insights](../aplicativo-ios/NetworkInsights/Tests/), [Assist](../aplicativo-ios/NetworkAssist/Tests/), [NetscopeEvidence](../aplicativo-ios/NetscopeEvidence/Tests/) e [NetscopeTransport](../aplicativo-ios/NetscopeTransport/Tests/). Presença de asserção não significa teste aprovado.
Não executados nesta entrega: suites, build, simulador, aparelhos, CloudKit/NDS/Netscope reais, App Store/produção ou revisão visual. Procedimentos e evidência operacional pertencem a Operação; mudanças técnicas continuam sujeitas aos gates de Governança.

## Minha Rede — contratos e fronteiras de 08/10/2026

Implementação em revisão na branch `feat/minha-rede-v1`, ainda não integrada à main nesta consolidação: pacote `NetworkInventory`, composição `LinkaHousehold`/`HouseholdRepository`, sessão de edição, OCR Vision e cliente de pesquisa. Os tipos concretos e testes dessa branch prevalecem para comportamento implementado; esta seção também preserva requisitos ainda a validar. Não amplia `LinkaEngine`, `NetworkMeasurement` ou contratos do NDS para registrar inventário.

### Inventário e instalação local

`RegisteredNetworkDevice` tem UUID estável, `kind` (modem/router/modemRouter/ont/meshNode/extender/other), `identity`, apelido opcional, `installation`, snapshot opcional, revisão concorrente e datas. `DeviceIdentity` separa marca, modelo, revisão de hardware e região; somente modelo é indispensável ao cadastro. `DeviceInstallation` distingue resposta Sim/Não/Desconhecido sobre principal, papel declarado, chegada de fibra, propriedade e `environmentID`/rótulo local. Capacidade do modelo, configuração declarada e evidência medida são domínios separados.

Arquivos locais versionados e gravação atômica por arquivo; revisão esperada impede sobrescrever edição concorrente ou ressuscitar registro excluído. Arquivo corrompido/schema futuro deve falhar preservando bytes, nunca recriar silenciosamente vazio. Uma única composição por processo serializa acesso a inventário e Ambientes, evitando caches concorrentes por arquivo. Mutação bem-sucedida notifica consumidores. Atomicidade por arquivo não equivale a transação entre arquivos: exclusão/renomeação de Ambiente requer teste de falhas parciais e recuperação que conserve UUIDs/rótulos e não altere assignments de medição. Falha não pode ser descrita como sucesso total.

OCR mantém foto/texto efêmeros, extrai somente candidatos de identidade e rejeita linhas mescladas com credenciais. A sessão possui cancelamento, geração e identidade do rascunho: resposta tardia, troca de modelo, descarte ou exclusão não podem preencher outro equipamento nem gravar sozinhos. Escolher sugestão não salva. Pesquisa só atualiza proposta; Salvar confirma identidade/ficha em uma operação. O texto digitado fica estável enquanto a pesquisa acontece; editar invalida respostas anteriores. Sem ficha documentada, o tipo inicial é `other`, nunca roteador presumido.

### Ficha técnica e pesquisa isolada

Contrato de snapshot versionado: `schemaVersion`, identidade da variante, `status`, `attributes`, `sources`, `checkedAt`. Cada atributo usa chave canônica, valor validado, unidade e `evidenceIDs`; cada fonte possui ID, URL, título, data e identidade correspondente. A implementação inicial transporta valores como strings validadas, inclusive JSON estruturado para capacidades por banda/portas; isso não autoriza prosa livre a se tornar especificação. Não promover resultado de IA a “verificado” apenas porque repetiu a identidade ou citou URL aberta. Distinguir declaração do usuário, sugestão documentada e dado não verificado; confirmação não equivale a homologação do fabricante.

| Grupo | Campos opcionais e unidade/semântica |
|---|---|
| Rádio | `wifiStandards` IEEE, `bandsGHz` 2.4/5/6; `radioCapabilities` por banda com `bandGHz`, `maxChannelWidthMHz`, `maxPhyRateMbps` teórica, `spatialStreams`; valores internos desconhecidos nulos |
| Portas | `lanPorts`, `wanPorts`, `ethernetPortSpeedsMbps`; `ethernetPorts` discrimina `role` lan/wan/lanWan, `portCount`, `speedMbps` nominal |
| Fibra | `wanMedia` ethernet/fiber/mixed/unknown; `fiberTermination` none/gpon/xgsPon/sfp/unknown documentado; não declara chegada de fibra na casa |
| Modos/Mesh | `supportedModes` router/accessPoint/repeater/meshSatellite/bridge/fiberTermination; `supportsMesh`, `meshTechnology`, `supportedBackhaul` ethernet/wifi; não inferir compatibilidade entre tecnologias |
| Suporte | `firmwareSupportStatus` e informações públicas de ciclo de vida somente quando rastreáveis; ausência não significa descontinuado |

Campos ausentes são omitidos/desconhecidos, nunca zero/false inventado. Atributos presentes exigem fonte correspondente à variante e unidade; conflitos ou revisão indefinida impedem afirmar característica dependente da variante. Taxa PHY não é throughput e largura de canal não é configuração observada. Não inventar cobertura em m², máximo de clientes, firmware instalado ou causa raiz. A UI formata estruturas/enums, sem expor JSON como ficha.

Backend próprio `linka-device-spec-lookup` no repositório Netscope API, separado do diagnóstico e de Assist/NDS/SignallQ. `POST /v2/device-specs/lookup` recebe `{schemaVersion:2,query,context?}`; contexto contém apenas revisão/região opcionais. Sem lista de marcas/regiões. A resposta distingue `available`, `ambiguous`, `notFound`, `unavailable`, com `requestID`, motivo, identidade, candidatos separados, atributos e fontes. O OpenAPI externo é canônico. O endpoint v1 permanece com adaptação para a beta anterior, sem campos v2.

A pesquisa usa duas chamadas: web com resposta citada em linguagem natural e estruturação estrita somente desse material. URLs/títulos vêm das citações da ferramenta; não é exigido modelo no título nem igualdade literal entre URL inicialmente aberta e URL citada/canônica. O Worker não faz fetch arbitrário dessas fontes. Modelo semelhante gera candidato, não substituição automática. Leitura por IA e citações não equivalem a certificação independente de cada afirmação.

V2 admite até 50s de pesquisa e 25s de estruturação, coordenação de 90s e cliente de 100s. V1 usa orçamento menor para respeitar o cliente antigo de 45s. Falhas de conteúdo/rede liberam concorrência, sem perdoar reserva de custo nem bloquear permanentemente todas as consultas. Cache tem namespace novo e apenas resultados aproveitáveis; falhas/negativos não são guardados. Diagnóstico privado temporário exige token próprio e habilitação nas duas camadas, passa contabilização e devolve resposta visível/ações apenas na resposta autenticada `no-store`, sem logs de conteúdo, segredos ou raciocínio interno.

O transporte novo é separado do snapshot local v1. `deviceKind` só é aceito com evidência e vira o campo `kind` existente; o atributo novo não é persistido no snapshot nem enviado ao cliente v1. Fonte/identidade pesquisadas seguem propostas até confirmar Salvar. Foto/OCR bruto, credenciais, instalação, localização e medições não fazem parte da consulta.

Páginas e entrada são dados não confiáveis, nunca instruções; provider/modelo/destino não vêm do usuário. A ficha fica local e acessível offline, sem CloudKit na V1. Operação registra separadamente versões publicadas e evidência real; código e testes simulados não comprovam pesquisa ou aceite no aparelho.

### Minha Rede V2 — Plano residencial, topologia declarada e guarda B1

Integrada na main pelas PRs #296 (Core e Guarda B1), #297 (UI de Planos e Conexões) e #298 (Visão Consolidada em 4 seções):

- **Schema de Persistência v2:** O arquivo local do inventário evoluiu para `schemaVersion = 2` gerenciando `devices`, `profiles`, `plans` e `connections`. Documentos legados v1 são promovidos em memória na leitura e reescritos como v2 somente sob mutação atômica (`.atomic`). Schemas incompatíveis (`< 1` ou `> 2`) e arquivos corrompidos são rejeitados preservando bytes em disco.
- **Plano Residencial (`NetworkServicePlan`):** Modelado com UUID estável, `ispName` (texto declarado sem matching automático com operadoras), `nominalDownloadMbps` e `nominalUploadMbps` independentes e estritamente positivos (`> 0` e finitos), tecnologia residencial (`AccessTechnology`), valor opcional em centavos inteiros com código ISO 4217, e campos de vigência `effectiveFrom` e `effectiveTo`.
  - *Separação estrita:* Zero alusão a planos móveis de smartphone. A opção `mobile` foi categoricamente eliminada do enum `AccessTechnology`; modems 4G/5G domésticos com chip são tratados como `cellularCpe` (FWA residencial).
  - *Versionamento temporal:* Edição de digitação atualiza in-place (`updateActivePlanDetails`). Troca de plano (`replaceActivePlan`) encerra o anterior com `effectiveTo = now` e ativa nova versão com `effectiveFrom = now`, resguardando contexto para comparações na futura V3.
- **Topologia Declarada (`DeviceConnection`):** Ligações entre equipamentos distintos (`endpointADeviceID != endpointBDeviceID`), meio físico/lógico `LinkMedium` (`ethernet`, `wifi`, `fiber`, `other`, `unknown`), direção opcional `sourceDeviceID` e normalização canônica (`normalizedLinkKey`) que previne duplicatas do mesmo meio, mas tolera múltiplos meios e grafos Mesh cíclicos.
- **Guarda de Isolamento Celular B1 (`ResidentialPlanEligibility`):** Ponto único e exaustivo de decisão arquitetural. Isola o plano residencial contra medições em interfaces móveis (`.cellular`), hotspots pessoais (`isPersonalHotspot`) ou rotas caras/restritas (`isExpensive`). Apenas conexões comprovadamente residenciais locais (`.wifi` ou `.ethernet`) são elegíveis para correlação futura.
- **Integridade Relacional no Ator (`HouseholdRepository`):** A exclusão de qualquer equipamento expurga em cascata atômica todas as conexões dependentes. A exclusão de plano anula o `activePlanID` no perfil doméstico. Ambientes (`NetworkProfiles`) permanecem locais e independentes; associar aparelho a um ambiente não move nem reatribui medições passadas.
- **Privacidade Absoluta:** Dados de plano, preço, topologia e ambientes são estritamente locais. Nenhum desses campos é compartilhado com o serviço remoto de busca de especificações da V1, Assist ou telemetria.

### Minha Rede V3 — Avaliação de plano residencial (`ResidentialPlanEvaluator`)

- **Motor puro no pacote `NetworkInventory`:** Avaliação pura e determinística em `ResidentialPlanEvaluator.swift`, sem acoplamento a UI e sem poluir `NetworkInsights`.
- **Isolamento B1 e Temporal:** `ResidentialPlanEligibility` filtra interfaces móveis, hotspots e redes restritas. Janelas `effectiveFrom` e `effectiveTo` impedem contaminação por medições anteriores ou posteriores à vigência do plano ativo.
- **Independência Download/Upload e Ausência != 0:** Avaliação desacoplada de direções (um campo nulo no plano não anula o outro). Ausência de dados retorna `.noData`, sem gerar `0 Mbps` fictício, divisão por zero ou `NaN`/`Inf`.
- **Integração Reativa:** `LinkaInventoryStore` injeta `MeasurementHistoryRepository`, alimenta o motor sob `@MainActor` e expõe `planEvaluation` reativo para a seção `planPerformanceSection` na `MyNetworkView`.

<a id="assist-contextual-v4"></a>
## Assist Contextual V4 — arquitetura do agente especialista supervisionado

**Integração documental:** 09/10/2026, versão 1.0. **Status:** arquitetura-alvo proposta; não implantada nem homologada por esta entrega. Reorganiza a documentação técnica da conversa nas fontes canônicas; comportamento em [Produto](PRODUTO.md#assist-contextual-v4), avaliação e ativação em [Operação](OPERACAO.md#assist-contextual-v4).

**Base inspecionada na documentação de origem:** `8268dac778bbdd8b2ed9eab7ec5a463597cf0f7a`. Os símbolos de consultoria abaixo são propostos. Reutilizar tipos concretos quando adequados; não tratar proposta como código existente. Não substituir governança, permissões dos serviços atuais ou política de diagnóstico pela mera publicação deste texto.

### V4-T1 Estado atual e consequência de integração

| Fonte da base inspecionada | Observação | Consequência |
|---|---|---|
| `NetworkAssist.swift` [V4-T1] | Context/Request exigem medição; `measurementUnderstanding` é observacional | Novo contrato de consulta independente; nunca medição fictícia para satisfazer tipo. |
| `AssistViewModel.swift` [V4-T2] | Falha sem medição; histórico esvaziado; pergunta padrão | Preservar mensagem real, admitir ausência e selecionar histórico elegível. |
| Mesmo ViewModel | idle/loading/success/error; consome completed | Estado de sessão próprio; interface assíncrona não prova streaming real. |
| `AssistContainer.swift` [V4-T3] | Entitlement, flag remota, BuildeaDiagnosticAPI, timeout 55 s | Reutilizar fronteiras; app não comprova auth/retenção/capacidade do Worker. |
| `HouseholdRepository.swift` [V4-T4] | Coordena dispositivos, planos, conexões, perfil e Ambientes | Adapter de leitura; snapshot consistente precisa de revisão específica. |

A inspeção não executou suites, Xcode, endpoints ou aparelhos, nem certificou integralmente as fases 1–3. Requisitos de auditoria operacional em #310 permanecem abertos.

### V4-T2 Composição e responsabilidades

Um único **Network Specialist Agent** em orquestração supervisionada. Modelo propõe perguntas, consulta conhecimento e escolhe ferramentas de leitura permitidas; software controla estado, permissão, orçamento, execução e apresentação crítica. Não começar com fine-tuning, múltiplos agentes, banco vetorial obrigatório ou framework pesado. SDK é opção se reduzir trabalho sem ocultar os controles. [V4-T5]

```text
App Linka: Assist UI / campo aberto / Oportunidades
  → ConsultationCoordinator (sessão local)
      → ContextAssembler
          → HouseholdRepository
          → MeasurementHistory + elegibilidade
          → NetworkOptimization / avaliadores existentes
      → ConsentController / AccessPolicy
      → LocalToolDispatcher (ferramentas existentes)
      → ConsultationRepository (histórico local)
  → ConsultationTransport (novo contrato)
Backend de consultoria (fronteira lógica própria)
  → auth + entitlement + idempotência + limites
  → ConsultationOrchestrator
      → políticas / procedimentos
      → NetworkSpecialist / ModelAdapter
      → KnowledgeRetriever
      → EvidenceValidator / ResponseValidator
  → resposta validada → renderização nativa
```

`ConsultationCoordinator`: navegação e estado local, escolhas, vínculo de turnos/testes, descarte de respostas antigas e persistência. Pacote novo ou seção isolada do atual conforme evitar ciclos.

`ContextAssembler`: na composição, usa protocolos dos repositórios e minimiza snapshot. Módulos puros não importam SwiftUI, StoreKit ou implementações HTTP.

Orquestrador remoto controla turno, escopo e orçamento; executa somente ferramentas permitidas do servidor e emite propostas tipadas de ação local. Texto do modelo nunca é comando. `ModelAdapter` normaliza saída/erros; modelo/cliente não escolhem endpoint, credencial, política, TTL, preço ou outro modelo arbitrariamente.

`KnowledgeRetriever` seleciona conhecimento curado e documentação. Validadores conferem estrutura, referências, valores, ações e restrições; declaração do próprio modelo não serve como prova específica.

O transporte de entendimento de medição permanece independente. Reuso físico do relay depende de auditoria; não alterar silenciosamente `/v2/assist`. Nenhuma dependência da consultoria entra no `LinkaEngine`. Privacidade do lookup da V1 e limites do Netscope permanecem próprios; novo contexto só segue ao transporte de consultoria com autorização específica.

<a id="assist-v4-contexto"></a>
### V4-T3 Identidades, contexto e evidências

Separar `localSessionID`, `transportSessionID`, `turnID`, `requestID` idempotente e `revision`. Não reutilizar UUIDs de medições/equipamentos/residência como identificadores públicos permanentes. Mapear para referências por sessão (`device-1`, `measurement-2`, `room-1`); nomes amigáveis podem ficar no app. Servidor não resolve referências em outra instalação.

| Campo de ContextSnapshot | Conteúdo/regra |
|---|---|
| `schemaVersion`, `snapshotID`, `revision` | Contrato e revisão de contexto. |
| `purpose`, `intent` | Finalidade/intenção; `open_question` válida. |
| `selectedProfileRef` | Perfil selecionado ou nulo se sem associação confiável. |
| `entities` | Subconjunto de aparelhos, plano, Ambientes e conexões relevantes. |
| `facts` | Valores tipados, unidade, origem e escopo. |
| `measurements` | Apenas leituras elegíveis; vazio válido. |
| `sources` | Fichas/documentos, revisão e data. |
| `capabilities` | Ferramentas realmente disponíveis nesta plataforma/sessão. |
| `consentReceiptRef` | Referência ao consentimento, não booleano da IA. |
| `createdAt` | Composição distinta da data de cada fato. |

Não apenas desbloquear `makeContext`. Projetar contexto explícito. Sequência de chamadas async não é atomicidade: conferir revisões antes/depois ou criar snapshot atômico no coordenador existente.

`EvidenceFact`: `id`, `subjectRef`, `property`, `value`, `unit`, `sourceType`, `sourceRefs`, `observedAt`, `validFrom`, `validUntil`, `scope`, `qualityStatus`, `derivedFrom`. Validade desconhecida pode ser nula, não infinita. `sourceType`: user_declared / system_observed / manufacturer_documented / curated_knowledge / derived. Hipótese é objeto separado. Ausência não vira zero/false/lista vazia como negativa comprovada.

`qualityStatus`: usable / partial / stale / conflicted / unavailable. Fonte oficial pode ser antiga ou de outra variante; confirmar UI não transforma dado sem fonte em documentação. Atestação/integridade do app não comprova a veracidade física ou método de cada medição; manter limite do envelope/metodologia.

**Elegibilidade:** conferir perfil/interface, associação explícita a ambiente, caminho, método, completude, idade e mudanças de plano/topologia. Reutilizar `ResidentialPlanEligibility`/vigência para plano, sem contornar B1. Wi-Fi e celular não isolam roteador; só comparação qualificada de experiências distintas. Para problema atual, usar investigação em andamento ou confirmar contexto; TTL isolado não transforma histórico em telemetria. Para recorrência, usar avaliadores/janelas existentes, sem thresholds paralelos. Excluir consentimento revogado, registros apagados e relações presumidas entre SSID/aparelho/cômodo/teste.

<a id="assist-v4-contratos"></a>
### V4-T4 Contratos de turno e resposta

Contrato novo proposto: **`assist.consultation/1.0`**, independente da fase de produto e do diagnóstico legado. Objetos de intercâmbio fechados (`additionalProperties: false`), limites e validação nos dois lados; negociar mudanças incompatíveis.

O núcleo local inicial de #311 está em [`AssistConsultation`](../aplicativo-ios/AssistConsultation/): DTOs, schema e fixtures versionados validam apenas a projeção local. Ele não é ligado ao `NetworkAssist`, não chama `/v2/assist` e não contém transporte, provider, retenção, custo ou persistência; essas integrações continuam dependências explícitas dos blocos posteriores e de seus gates.

Request obrigatório: `schemaVersion`, `requestID`, `transportSessionID`, `turnID`, `expectedRevision`, `locale`, `input`, `contextSnapshot`, `consentReceiptRef`.

`input` é união discriminada: `user_message { text }`; `answer { questionID, optionID?, text? }`; `tool_result { proposalID, result }`; `action_feedback { actionID, status }`. “Não sei” é opção explícita. Rejeitar vazio, opção alheia à pergunta ativa e revisão incorreta. Enviar janela limitada de turnos/resumo referenciado, não transcript irrestrito. Resumo não fornece consentimento, autorização de execução ou nova evidência.

Exemplo sintético de resposta, não JSON Schema executável:

```json
{
  "schemaVersion": "assist.consultation/1.0",
  "requestID": "request-example",
  "turnID": "turn-example",
  "revision": 2,
  "intent": "open_question",
  "disposition": "awaiting_answer",
  "claims": [],
  "limitations": ["A revisão do equipamento não foi confirmada."],
  "next": {
    "kind": "question",
    "question": {
      "id": "q-hardware",
      "text": "Qual é a versão indicada na etiqueta?",
      "options": [{"id": "unknown", "label": "Não sei"}],
      "allowFreeText": true
    }
  },
  "assessment": null
}
```

`disposition`: awaiting_answer / awaiting_approval / answered / inconclusive / out_of_scope / unavailable. Erro de transporte é distinto. `next`: question / tool_proposal / action_proposal / none; uma pergunta e uma ação principal por etapa. `assessment`: conclusão de domínio, resumo, achados, hipóteses, lacunas, alternativas e referências; não usar “adequado” universal.

`Claim { id, kind, text, evidenceRefs, appliesToRefs }` distingue observação, declaração, capacidade, conhecimento geral e hipótese. Modelo referencia IDs do sistema, não inventa URLs. App formata números de evidência. Capacidade exige variante/fonte; recomendações preservam condições; conhecimento geral usa base curada pertinente, sem fabricar citação se insuficiente.

Conclusões sugeridas: lentidão → next_test / safe_action / escalation / insufficient; roteador → keep / adjust / upgrade_candidate / insufficient; mesh → not_justified / reposition_candidate / wired_ap_candidate / mesh_candidate / insufficient; plano → usage_fit / review_cost / capacity_candidate / commercial_data_missing / insufficient.

JSON válido não garante verdade. Causa raiz, disponibilidade comercial e compatibilidade exata exigem controles/evidência específicos ou permanecem condicionais. O servidor valida propostas e referências antes de apresentar.

<a id="assist-v4-sessoes"></a>
### V4-T5 Máquina de estados e concorrência

Separar estado da consulta, turno remoto e ação. Resposta concluída não implica orientação executada.

| Estado | Evento autorizado | Destino |
|---|---|---|
| draft | Usuário inicia | context_ready |
| context_ready | Envio requer autorização | awaiting_consent |
| context_ready / awaiting_consent | Consentimento/acesso válidos + enviar | processing_turn |
| processing_turn | Pergunta validada | awaiting_answer |
| awaiting_answer | Responder/pular/Não sei | context_ready, validar pergunta/revisão |
| processing_turn | Proposta de teste válida | awaiting_test_approval |
| awaiting_test_approval | Aceite + contexto válido | measuring |
| awaiting_test_approval | Recusa/expiração | context_ready ou orientação local limitada |
| measuring | Resultado recebido/validado | processing_turn ou result_ready local |
| processing_turn | Resposta final/inconclusiva | result_ready |
| result_ready | Aceitar orientação | action_pending |
| action_pending | Pedir reteste | awaiting_test_approval |
| action_pending | Concluir/ignorar/impossível | context_ready; resultado local se não houver envio |
| result_ready | Nova pergunta na consulta | context_ready com histórico |
| paused / recoverable_error | Retomar/retry | Último estado estável; revalidar |
| completed | Continuar consulta | context_ready em nova revisão |
| Estável | Fechar | paused ou completed |
| Com atividade | Cancelar | cancelling, depois estável |
| Qualquer | Falha recuperável | recoverable_error com retorno definido |

Só gesto de envio ou continuidade explicitamente autorizada inicia novo turno nos caminhos context_ready. Retomar tela, notificação interna ou snapshot recomposto não autorizam I/O por si só. “Não sei”, recusa e pular são eventos normais, não laços infinitos. Restaurar app não reexecuta medição.

Uma chamada remota ativa por sessão; uma medição ativa no app. Respostas precisam coincidir com sessão, request e revisão. Descartar tardias após edição, revogação ou cancelamento; replay não repete ação. Mudança de rede invalida aprovação de teste anterior; usuário confirma novo cenário. Não reutilizar contexto de outro perfil.

<a id="assist-v4-ferramentas"></a>
### V4-T6 Ferramentas e handoff

Catálogo estreito, com entradas, saídas, limitações, custo e erros. Não expor HTTP/SQL/shell/filesystem genéricos, abertura arbitrária de URL ou credenciais ao modelo. O catálogo é parte da avaliação técnica. [V4-T6]

| Ferramenta proposta | Executor | Entrada/saída | Autorização |
|---|---|---|---|
| read_network_context | App | Intenção/seleção → snapshot mínimo | Escopo local; envio separado. |
| select_measurement_evidence | App | Objetivo → leituras elegíveis/lacunas | Escopo escolhido; não todo histórico. |
| evaluate_opportunities | App | Medição → achados/regra | Reutilizar motor determinístico. |
| lookup_device_specs | Servidor | Marca/modelo/revisão/região → ficha/fontes | Pesquisa técnica no escopo. |
| retrieve_network_guidance | Servidor | Tópico/restrições → trechos | Busca pública sem contexto pessoal. |
| propose_network_test | Servidor → app | Tipo/objetivo → proposta | Não executa; pessoa aprova. |
| run_existing_test | App | Proposta + aprovação → resultado | Gesto e revalidação de interface. |
| compare_measurements | App | IDs/variável → comparação qualificada | Regras testadas. |
| save_consultation | App | Resultado → confirmação local | Comando da pessoa, não escrita da IA. |
| compare_offers | Servidor, futura | Critérios → ofertas com condições | Desligada até decisão/auditoria. |

`ToolProposal`: ID do servidor, ferramenta enumerada, argumentos tipados, objetivo, referências, risco e expiração. Catálogo controla necessidade de aprovação, não modelo. Vincular autorização à proposta/sessão/argumentos normalizados/revisão; aprovação expirada, repetida ou incompatível não inicia nada.

Teste retorna completed / partial / cancelled / denied / unavailable / failed e razão. Parcial não inventa métricas. Tempo da pessoa e da medição não mantém HTTP remoto aberto.

`OpportunityHandoff`: ID, kind, ruleVersion, baselineMeasurementID, evidenceMeasurementIDs, suggestedAction e createdAt conforme #321. Resolver IDs localmente e mapear referências remotas por sessão. Revalidar idade, qualidade, existência e contexto; evitar sessão duplicada por tap. SuggestedAction é candidata, não autorização ou causa. `confidence` numérica do motor não vira probabilidade de causa raiz. Reusar ações/reteste #317; com V4 desligada preservar caminho legado honesto.

### V4-T7 Conhecimento especializado

Pacote versionado proposto `network-specialist@1`: domínio, fronteiras, evidência, procedimentos e parada. Módulos para lentidão, equipamentos, mesh/cobertura, plano e pergunta aberta são conhecimento de um agente, não agentes concorrentes.

Conteúdo mínimo: LAN/WAN, bandas e capacidades, portas/enlaces, DNS, latência/jitter/perda conforme método, responsividade, AP/roteador/bridge, terminação óptica, mesh/backhaul, adequação de uso e ações seguras.

Referência recuperada: sourceID, URL canônica, título, organização, modelo/revisão/região, data, versão/hash, trechos necessários e limites de uso. Cache público separado de contexto pessoal. Priorizar ficha validada/base curada; pesquisar apenas quando necessário, em fabricante/fontes primárias. Não mesclar variantes/conflitos nem espelhar manuais indiscriminadamente. Índice por marca/modelo/tópico e busca textual podem bastar; vetor é opcional.

Instrução-base proposta:

```text
Você é o Assist, consultor de redes domésticas do Linka.
Responda à pergunta real e use apenas o contexto autorizado.
Diferencie o que foi medido, declarado, documentado e suposto.
Explique conceitos sem exigir testes desnecessários.
Para instrução específica, confirme variante e referência aplicável.
Faça uma pergunta útil por vez se faltar informação relevante.
Prefira ação simples/reversível a compra desnecessária.
Proponha somente ferramentas do catálogo; não execute comandos.
Não invente valores, fontes, disponibilidade ou causa raiz.
Se faltar base ou ferramenta falhar, exponha o limite.
Retorne contrato tipado, não raciocínio interno.
```

Instrução complementa controles externos. Avaliação precisa demonstrar benefício do pacote, não presumir competência pelo nome do prompt.

<a id="assist-v4-api"></a>
### V4-T8 Backend, autenticação e protocolo

Workers é opção compatível com a infraestrutura mencionada; reuso depende de auditoria de contrato, auth, isolamento e orçamento. Não exigir Agents SDK/Vercel/migração por causa desta proposta. Lookup V1 e diagnóstico continuam separados.

**Rotas propostas, não operacionais:**

| Rota | Finalidade | Regra |
|---|---|---|
| POST /v1/assist/consultations | Abrir sessão remota temporária | Após consentimento; ID opaco/revisão. |
| POST /v1/assist/consultations/{id}/turns | Mensagem/resposta/resultado | Idempotency key + revisão esperada. |
| GET /v1/assist/consultations/{id}/turns/{turnID} | Recuperar tentativa | Proprietário autenticado; retenção curta. |
| POST /v1/assist/consultations/{id}/cancel | Cancelar ativa | Best effort, sem prometer evitar custo ocorrido. |
| DELETE /v1/assist/consultations/{id} | Apagar temporário | Idempotente; limites do processador à parte. |

Não misturar com `/v2/assist`. Configuração/capabilities pode divulgar modelos/processadores aprovados para transparência, sem permitir substituição pelo cliente.

Secrets de provedor só no servidor. Identidade de instalação/sessão com escopo limitado e auth inspecionada; nunca chave estática compartilhada no binário. Validar propriedade, token, expiração, replay e entitlement no servidor. Flag/booleano de consentimento não autenticam. Atestação pode complementar, não substituir autorização por recurso/entitlement nem provar medição. Ambiente de desenvolvimento isolado, sem bypass em produção; Mac requer auth aprovada própria.

**Idempotência:** reservar `(identidade, sessão, requestID, hashDoPayload)` antes do provedor em transação/coordenador por sessão. Mesma chave+payload recuperam tentativa; payload diferente conflita. Cache simples não garante exclusão mútua. Não prometer execução física exatamente uma vez no provedor. Timeout com resultado desconhecido exige recuperar tentativa ou nova ação explícita, não duplicar geração silenciosamente.

Erros: unauthorized / not_entitled / consent_required / revision_conflict / unsupported_schema / invalid_input / tool_unavailable / provider_unavailable / budget_exhausted / cancelled / result_expired. Inconclusive é resultado válido, não HTTP500. Erro do backend não diagnostica rede doméstica.

**Incremental:** MVP pode retornar JSON final e progresso real. Se stream, eventos accepted / context_checked / retrieving_sources / generating / validating / completed. Não dizer pesquisando sem pesquisa; não expor texto técnico não validado como conclusão nem raciocínio interno. Interrupção preserva último resultado válido; recuperar tentativa sem duplicar geração. Funciona também com provedor sem stream.

<a id="assist-v4-seguranca"></a>
### V4-T9 Segurança e dados

Páginas/ferramentas/saída são não confiáveis. Separar instruções e dados, schema fechado, ferramentas permitidas, referências/escopo conferidos. RAG/prompt/fine-tuning não eliminam prompt injection. [V4-T7]

Se houver fetch próprio de documentos, só HTTPS de origens públicas aprovadas, resolução e redirects validados, bloqueio de loopback/privados/link-local/metadados/IPv6 equivalentes, limites de MIME/tamanho/tempo; nunca painel de roteador como manual, execução de script/HTML ou destino livre determinado pela IA. Reusar lookup sem alterar suas fronteiras.

Renderizar blocos tipados e links selecionados no backend, sem HTML/imagem remota arbitrários ou markdown de exfiltração. Abrir link externo requer gesto. Resultado de pesquisa nunca vira comando DNS/roteador.

Recibo de consentimento versionado: finalidade, processadores, categorias, perfil, data e estado. App registra e backend confere escopo quando aplicável. Pergunta genérica remota continua exigindo autorização do texto mesmo sem contexto da rede. Permissão do sistema, IA e teste são independentes. Revogação invalida novos envios e respostas tardias, tenta cancelar atividade sem prometer apagar processamento já feito. [V4-T8]

Não enviar por padrão nomes de cômodos, SSID, IP local, serial, credencial, endereço. Mensalidade somente quando necessária à intenção plano e autorizada. Redação automática não detecta tudo; não prometer anonimização universal.

Desabilitar captura de prompt/resposta em gateway, SDK e observabilidade e conferir defaults. Gateway não implica zero armazenamento. Auditoria de retenção de infraestrutura e processadores é gate próprio. [V4-T9]

<a id="assist-v4-persistencia"></a>
### V4-T10 Persistência, memória e exclusão

Repositório local de consultas separado do histórico de medições, schema/migração, gravação atômica e preservação de bytes em erro. Proteção de arquivo adequada à plataforma; credenciais fora do transcript.

Salvar referências e projeção mínima necessária para explicar orientação, conforme consentimento/política. Excluir medição remove valores da projeção e invalida conclusão dependente; resumo não ressuscita dado. Excluir consulta não apaga teste original. Alterar Minha Rede requer confirmação própria, não atualização pelo resumo da IA.

Desenho remoto proposto: transcript completo fica local; resultado terminal recuperável por até 10 minutos e metadados mínimos de sessão/idempotência até24h. Acesso por proprietário, proteção em repouso, expiração e limpeza testadas. Isso é armazenamento de conteúdo; nunca declarar zero retenção. Fornecedor tem política distinta a informar.

Sessão remota expirada: criar outro transportSessionID ao retomar por ação da pessoa, recompor contexto autorizado, sem reaplicar aprovação antiga de teste. Resposta irrecuperável exige geração explícita; rascunho/ações locais permanecem.

Resumo versionado só contém fatos referenciados, respostas, hipóteses descartadas e tentativas. Sem treinamento contínuo ou memória compartilhada entre usuários com produção.

Parâmetros de retenção **propostos**, a aprovar: rascunho local7dias; salvo até exclusão; conteúdo remoto10min; recibos operacionais24h; telemetria agregada sem conteúdo30dias. Não são configuração comprovada; logs/fornecedor auditados à parte.

### V4-T11 Limites técnicos, custo e recuperação

Valores iniciais da documentação, sujeitos à prova técnica; não são quotas comerciais ou capacidades garantidas:

| Parâmetro | Proposta |
|---|---|
| Mensagem | Até2.000 pontos de código Unicode, normalização definida. |
| Payload entrada/saída | 256KiB /64KiB, validação prévia. |
| Evidência histórica | Até8 medições elegíveis, sem envio obrigatório de todas. |
| Pesquisa/turno | Até1 consulta pública e3 documentos pertinentes. |
| Chamadas de modelo/turno | Até4, incluindo reparo de schema/retries. |
| Ferramentas remotas/turno | Até3; local requer autorização separada. |
| Deadline remoto | 45s servidor/55s cliente novo, configurável e independente do legado. |
| Retry automático IA | Até1 em falha transitória seguramente repetível e dentro do orçamento. |
| Parada | Inconclusivo/orientação limitada quando não houver passo útil. |

Duração do teste e tempo da pessoa não entram no deadline remoto. Lookup de fichas existente tem outros prazos: não encaixar sua operação longa silenciosamente no turno; adaptar como tarefa própria ou retornar estado recuperável e exigir contrato validado.

Custo inclui tokens, pesquisa, infraestrutura e retries, por turno/consulta/tarefa concluída. Estimativa mensal: consultas × custo médio + fixos, com preços reais do fornecedor escolhido. Worker não implica gratuidade; assinatura anual não comprova viabilidade.

Orçamento de consultoria requer decisão explícita dentro do escopo; preservar autorizações anteriores sem ampliá-las por inferência. Reservar custo antes de dispatch e reconciliar depois; timeout pode ter custo e mantém reserva conservadora enquanto incerto. Teto aprovado atingido bloqueia novas gerações e mantém local. Proteção técnica contra abuso não é franquia de produto.

Fallback de fornecedor somente aprovado, avaliado e coberto por consentimento; senão indisponibilidade honesta e referências locais. Configurar retries de gateway/cliente para não multiplicar chamadas. [V4-T10]

### V4-T12 Regras de domínio e gates

Reutilizar avaliadores e oportunidades; novas regras têm ID, versão, entradas/saídas e testes de fronteira. Não duplicar thresholds no prompt/UI. Ausência de teste não impede conceito geral; jitter/perda têm método; PHY não é throughput; porta nominal não prova negociação; fibra/SFP não comprova terminação GPON; Wi-Fi antigo não implica troca; catálogo não informa instalação; antes/depois não prova causalidade.

Reinício manual precisa de motivo e aviso, nunca reflexo universal de queda de desempenho. Não orientar desativar segurança, acesso de terceiros, reset de fábrica ou manipulação de fibra como passo genérico. Consultoria não se implementa ligando `mayInferRootCause` ou ignorando `mustGroundInProvidedData`.

Fechamento: contratos/fixtures #311, orquestrador #320, UI #312, jornadas #313–#316/#319, acompanhamento #317, Oportunidades #321 e QA #318. Procedimentos, rubricas, prova técnica e rollback estão em [Operação](OPERACAO.md#assist-contextual-v4), sem declarar execução por este documento. Auth, provedor, orçamento, retenção, consentimento e disponibilidade Mac permanecem gates humanos; #310 não é fechada por documentação.

### V4-T13 Referências da documentação de origem

Base das fontes de código: commit `8268dac778bbdd8b2ed9eab7ec5a463597cf0f7a`; não equivale à build distribuída. Fontes externas registradas em09/10/2026 devem ser conferidas antes da implementação dependente.

- V4-T1: [NetworkAssist.swift](https://github.com/gmmattey/linka/blob/8268dac778bbdd8b2ed9eab7ec5a463597cf0f7a/aplicativo-ios/NetworkAssist/Sources/NetworkAssist.swift).
- V4-T2: [AssistViewModel.swift](https://github.com/gmmattey/linka/blob/8268dac778bbdd8b2ed9eab7ec5a463597cf0f7a/aplicativo-ios/LinkaApp/Sources/Adapters/AssistViewModel.swift).
- V4-T3: [AssistContainer.swift](https://github.com/gmmattey/linka/blob/8268dac778bbdd8b2ed9eab7ec5a463597cf0f7a/aplicativo-ios/LinkaApp/Sources/Adapters/AssistContainer.swift).
- V4-T4: [HouseholdRepository.swift](https://github.com/gmmattey/linka/blob/8268dac778bbdd8b2ed9eab7ec5a463597cf0f7a/aplicativo-ios/NetworkInventory/Sources/HouseholdRepository.swift).
- V4-T5: [Anthropic — Building effective agents](https://www.anthropic.com/engineering/building-effective-agents).
- V4-T6: [Anthropic — Writing effective tools for agents](https://www.anthropic.com/engineering/writing-tools-for-agents).
- V4-T7: [OWASP — Prompt Injection](https://genai.owasp.org/llmrisk/llm01-prompt-injection/).
- V4-T8: [Apple — App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) e [App Privacy](https://developer.apple.com/app-store/app-privacy-details/).
- V4-T9: [Cloudflare — AI Gateway logging](https://developers.cloudflare.com/ai-gateway/observability/logging/).
- V4-T10: [Cloudflare — Request handling](https://developers.cloudflare.com/ai-gateway/configuration/request-handling/).

As referências não certificam configuração nem homologação do backend do Linka. Nenhuma API, ferramenta, quota, política ou estado futuro é ativado por esta alteração documental.
