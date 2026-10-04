# Painel do roteador e limite de equipamentos

Estado do documento: vigente para a inspeção estática declarada; validação de execução pendente.
Responsável: Codex principal; manutenção técnica por Pedro.
Última revisão: 2026-10-04 — código, contratos locais, fontes de testes e planos do tema.
Referências: [Governança](../../../AGENTS.md); [processo documental](../../GOVERNANCA_DOCUMENTAL.md); fontes abaixo.

Disponibilidade da feature: implementações locais descritas por plataforma abaixo; não atesta distribuição.
Base conferida: checkout WIP da branch `feat/macos-visual-direction-and-service-status`, HEAD `9eb1a094` mais alterações locais. Não é snapshot de main/produção.
Termos de busca: Roteador, gateway, painel, Keychain, equipamentos.

## Propósito e limites

- Problema/resultado esperado: Encontrar o gateway e abrir seu painel para quem precisa administrar a própria rede, sem scanner ou diagnóstico causal.
- Quem usa: pessoa usando o Linka no ecossistema Apple, nas condições de acesso descritas abaixo.
- Fora de escopo: Automatizar configuração/login, identificar fabricante por suposição, varrer dispositivos ou recomendar compra comercial como capacidade entregue.

## Comportamento atual

| Entrada ou ação | Resposta do produto | Regra e fonte |
|---|---|---|
| Abrir painel em Ajustes | Localiza gateway, verifica HTTP/HTTPS e pede confirmação antes de abrir URL externa. | ActiveGatewayDiscovery + GatewayProber; Mac inicia localização em task. |
| Salvar/remover senha no iOS | SecureField salva/remove item com serviço com.linka.router e conta router_admin. | Ação explícita; item único, não há chave de identidade por roteador neste fluxo. |
| Abrir no Mac | Usa navegador; não oferece salvar credenciais. | MacRouterPanelView na SettingsSheet. |

As regras acima se referem aos símbolos do mapa técnico; são observação estática, não prova de jornada executada.

### Estados e recuperação

| Estado/condição | Comportamento e recuperação |
|---|---|
| Localizando | Botão indisponível enquanto busca. |
| Gateway não encontrado | unavailable; tentar localizar novamente. |
| Gateway encontrado, painel inacessível | unreachable mantém IP e oferece Ajustes; não prova recusa de permissão. |
| Painel confirmado | found libera confirmação para navegador; cancelar fecha diálogo. |

Estados de permissão, offline e cancelamento não expostos especificamente pela implementação não são tratados como estados comprovadamente distintos. Resultados parciais aplicáveis estão descritos acima.

### Plataformas e acesso

iPhone/iPad: RouterDiscoveryView sob os(iOS), com senha opcional no Keychain. Mac: MacRouterPanelView com gateway/probe compartilhados, sem senha. Entradas inspecionadas não aplicam gate Plus.
 Configuração de targets: [aplicativo-ios/project.yml](../../../aplicativo-ios/project.yml). Mínimo de pacote não comprova disponibilidade do recurso em dispositivo.

### Experiência e referências compartilhadas

- Entradas/destinos: ações descritas acima e views no mapa; folhas, confirmação, erro, detalhe e gestão precisam de validação visual no candidato.
- Acessibilidade: controles SwiftUI e labels existentes foram inspecionados nas views; VoiceOver, Dynamic Type, teclado e adaptação não foram executados.
- Fontes de aparência: [protótipo](../../design/prototipo/), [Design System](../../design/design_system/), [direção macOS](../../design/README.md). Não se declara conformidade visual por leitura de código.

## Mapa técnico

| Caminho relativo à raiz Git | Símbolos/responsabilidade |
|---|---|
| [aplicativo-ios/LinkaApp/Sources/UI/RouterDiscoveryView.swift](../../../aplicativo-ios/LinkaApp/Sources/UI/RouterDiscoveryView.swift) | `RouterDiscoveryView.locatePanel` |
| [aplicativo-ios/LinkaApp/Sources/UI/SettingsSheet.swift](../../../aplicativo-ios/LinkaApp/Sources/UI/SettingsSheet.swift) | `MacRouterPanelView` |
| [aplicativo-ios/NetworkDiagnostics/Sources/LocalGatewayDiscovery.swift](../../../aplicativo-ios/NetworkDiagnostics/Sources/LocalGatewayDiscovery.swift) | `ActiveGatewayDiscovery; LocalGatewayDiscovery` |
| [aplicativo-ios/NetworkDiagnostics/Sources/GatewayProber.swift](../../../aplicativo-ios/NetworkDiagnostics/Sources/GatewayProber.swift) | `GatewayProber.probe` |
| [aplicativo-ios/LinkaApp/Sources/UI/KeychainHelper.swift](../../../aplicativo-ios/LinkaApp/Sources/UI/KeychainHelper.swift) | `KeychainHelper` |

## Fluxo e contratos

Mac tenta gateway da interface local; fallback NWPathMonitor Wi-Fi examina gateways IPv4 privados. Timeout de descoberta padrão 3 s. Probe faz HEAD HTTP/HTTPS concorrentes, prefere HTTPS, timeout padrão 0,5 s, sem celular/cache/redirecionamento; aceita 200–499 exceto 3xx com host esperado. Resposta não comprova marca ou autenticação do painel. UI só abre após confirmação. Falha do Keychain não tem confirmação robusta de persistência na view: hasSavedPassword é atualizado após chamada do helper.

## Dependências e impacto

NetworkDiagnostics fornece descoberta/probe; app usa SwiftUI, UIKit/AppKit, Network e Security. Não confundir pacote de diagnóstico remoto com envio de credenciais: este fluxo não as envia ao serviço remoto.

Alteração nas condições de acesso deve revisar [Plus](../linka-plus/README.md). Mudanças de dados ou fluxo exigem revisão dos consumidores citados, sem duplicar regra na UI.

## Operação e limitações técnicas

Rede local e conectividade com gateway necessárias; verificar permissões/ATS/assinatura em dispositivo. Descoberta documentada é IPv4; não prometer cobertura de toda topologia IPv6/VPN.

## Critérios de aceite

Critérios para conferir a capacidade existente; não são testes declarados como aprovados.

| ID | Cenário | Resultado esperado | Fonte |
|---|---|---|---|
| AC-01 | HTTP redireciona para outro destino | Não confirmar painel pelo redirect. | Mapa técnico e fluxo acima |
| AC-02 | Pessoa cancela confirmação | Não abrir navegador. | Mapa técnico e fluxo acima |
| AC-03 | Remover senha no iOS | Remover item local; não alterar roteador nem histórico. | Mapa técnico e fluxo acima |

## Evidências existentes

| Critérios | Nível/ambiente | Base/data | Procedimento | Resultado e limite |
|---|---|---|---|---|
| AC-01 a AC-03 | Inspeção estática local | WIP descrito; 2026-10-04 | Leitura dos símbolos e busca com rg | Regras documentadas; não comprova runtime |

Fontes de testes existentes consultadas (não executadas nesta entrega):
- [aplicativo-ios/NetworkDiagnostics/Tests/GatewayDiscoveryTests.swift](../../../aplicativo-ios/NetworkDiagnostics/Tests/GatewayDiscoveryTests.swift).
- [aplicativo-ios/NetworkDiagnostics/Tests/GatewayProberTests.swift](../../../aplicativo-ios/NetworkDiagnostics/Tests/GatewayProberTests.swift).

Testes de pacotes/app, build, simulador, dispositivo físico, TestFlight, App Review e produção: **não executados/verificados nesta tarefa documental**. Nenhum plano foi marcado como entregue.

## Validação ainda necessária

| Cenário/risco | Responsável | Evento de revisão | Critério de fechamento |
|---|---|---|---|
| Validar painel real, bloqueio de rede local, HTTPS inválido, fechamento durante busca e resultado de Keychain. Equipamentos: Íris/Luiz precisam decidir escopo antes de qualquer implementação comercial. | Tito, com executor autorizado | Antes da próxima release que inclua a capacidade | Evidência reproduzível da build candidata e dos cenários, ou decisão explícita de escopo |
| Acessibilidade e todos os destinos alcançáveis | Tito/Íris | Próxima validação visual da capacidade | Conferir estados aplicáveis em iPhone/iPad/Mac; registrar limitações por plataforma |

## Mudanças em andamento

A autorização desta sessão cobre documentação do WIP. Não concede implementação, encerramento de plano ou publicação. As fontes anteriores foram reconciliadas e removidas na [migração documental](../../MIGRACAO.md); expectativas ainda abertas permanecem abaixo.

Origem e substituições registradas na [migração](../../MIGRACAO.md).

Plano de paridade dizia não portar administração nesta fase e descrevia heurística Bonjour; código atual já possui MacRouterPanelView e descoberta de gateway. RecomendacaoEquipamentos é proposta futura com provider/afiliados/flag, não implementação demonstrada; busca por Equipment/equipment/affiliate/Affiliate em Swift não encontrou implementação.

## Divergências e perguntas abertas

| Pendência | Responsável | Evento | Fechamento |
|---|---|---|---|
| Resolver/registrar diferenças acima entre planos, comentários e composição real | Codex principal, com especialista do tema | Integração documental e antes da release afetada | Decisão rastreável ou correção autorizada com evidência; não presumir entrega |

## Expectativas preservadas dos planos e estado

Esta tabela conserva trabalho aberto após a substituição das fontes antigas. Não constitui nova autorização de implementação.

| ID | Estado | Expectativa ou lacuna | Responsável | Evento | Critério de fechamento |
|---|---|---|---|---|---|
| ROUTER-P01 | Proposta futura, não implementada | Equipamentos: flag desligada por padrão; quando off, nenhuma busca, impressão ou clique. Se autorizado, intenção baseada em evidência → provider → guardrails → até três ofertas com aviso de comissão. | Íris/Luiz | Antes de decidir monetização de equipamentos | Decisão explícita Apple-first e arquitetura aprovada; não converter exemplos causais do legado em fatos medidos. |
| ROUTER-P02 | Proposta futura, não implementada | Legado sugere Amazon Creators API inicial e extensibilidade a Mercado Livre, Magazine Luiza/Kabum; tipos de oferta incluem origem, preço/moeda/disponibilidade opcionais, URL e fetchedAt. Não existe contrato ativo assumido com esses providers. | Camillo/Luiz | Somente após decisão de produto/comercial | Verificar API e condições reais, custo/privacidade e desenhar contrato Apple; paths TypeScript antigos não são implementação Linka. |
| ROUTER-P03 | Expectativa futura não validada | Compra não pode ser sugerida sem evidência suficiente; falha de provider deve resultar em ausência de oferta; ranking/compatibilidade e transparência comercial precisam testes. | Íris/Tito | Antes de ativar qualquer oferta | Gate de produto e testes impedem oferta indevida; telemetria/links comissionados têm decisão própria. |
| ROUTER-P04 | Validação pendente | Mac com rede local negada e iOS com painel inacessível não podem afirmar estado de permissão detectado; gateway pode existir sem painel. | Tito | Antes da release do painel | Cenários físicos com permissão concedida/negada e sem serviço HTTP. |
