# Capacidades do Linka

Estado: vigente como índice do checkout documentado.
Responsável: Codex principal (Marco).
Última revisão: 2026-10-04 — organização das capacidades e fontes locais; runtime não validado.
Base: WIP sobre `9eb1a09412db5279424adfb4a68a48e943eea18e`.
Referências: [produto](../PRODUTO.md), [governança](../GOVERNANCA_DOCUMENTAL.md), [migração](../MIGRACAO.md).

Começar pela capacidade percebida pelo usuário. O README reúne comportamento, mapa técnico, aceite, evidência e pendências. Disponibilidade pública ou paridade entre Apple devices não é presumida por existir código compartilhado.

| Capacidade | Propósito | Termos e módulos | Responsabilidade |
|---|---|---|---|
| [Medição](medicao/README.md) | Medir a conexão e apresentar fatos | LinkaEngine, NetworkCore, SpeedTestViewModel | Camillo/executor |
| [Histórico](historico/README.md) | Guardar e consultar medições | MeasurementHistory, CloudKit, ambientes, exportação | Camillo/executor |
| [Insights](insights/README.md) | Comparar dados e avaliar usos com evidência | NetworkInsights, suitability, telemetria | Camillo/executor |
| [Assist](assist/README.md) | Orientar com os dados disponíveis | NetworkAssist, NetworkDiagnostics, NDS | Camillo/executor |
| [Linka Plus e publicidade](linka-plus/README.md) | Explicar acesso, oferta, compra e anúncios | LinkaEntitlements, StoreKit, AdMob, consentimento | Orquestrador/executor |
| [Diagnóstico Wi-Fi](diagnostico-wifi/README.md) | Incorporar dados expostos pela plataforma | AdvancedWiFi, CoreWLAN, Atalhos | Pedro/executor |
| [Roteador](roteador/README.md) | Acessar o painel da rede atual | gateway, RouterDiscovery, Keychain | Pedro/executor |
| [DNS](dns/README.md) | Comparar resolvedores e configurar com consentimento | NetworkDNSBenchmark, DoH, perfil | Pedro/executor |
| [Otimização](otimizacao/README.md) | Sugerir ações sustentadas por medições | NetworkOptimization, comparação | Pedro/executor |
| [Ambientes de medição](perfis-de-rede/README.md) | Associar medições a locais nomeados pela pessoa | NetworkProfiles, schema 2, assignments, perfis legados | Pedro/executor |
| [Status de serviços](status-de-servicos/README.md) | Consultar incidentes externos | ServiceStatus, push, catálogo | Pedro/executor |
| [Integrações Apple](integracoes-apple/README.md) | Acionar o app e consultar o último resultado | WidgetKit, Siri, AppIntents, App Group | Camillo/executor |
| [Triagem de conectividade](triagem-de-conectividade/README.md) | Recuperar-se de falha/offline sem inventar causa | NetworkConnectivityTriage, reteste | Camillo/executor |
| [Interface e acessibilidade](interface-e-acessibilidade/README.md) | Navegar e ler resultados nos destinos Apple | SwiftUI, iPhone, iPad, Mac, localização | Íris/executor |
| [Site institucional](site-institucional/README.md) | Apresentar o app e informações públicas | React, Vite, suporte, privacidade | Íris/executor |

## Estado da revisão

Todos os documentos acima adotam a estrutura nova nesta migração. O alcance de inspeção e a disponibilidade por plataforma estão no README de cada capacidade. Não há atestado de validação de runtime do conjunto. Pendências de produto e técnica têm responsável, evento de revisão e critério de fechamento nas respectivas fontes; o [plano de entrada](../../.agents/plano.md) reúne frentes compartilhadas.
