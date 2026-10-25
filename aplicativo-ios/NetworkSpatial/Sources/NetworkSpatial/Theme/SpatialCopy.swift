import Foundation
import SwiftUI

/// Sistema canônico de localização e cópia para o módulo de Cobertura Residencial (NetworkSpatial).
/// Suporta nativamente Português (pt-BR), Inglês (en) e Espanhol (es-419).
/// Integra-se à preferência do Linka (`linka.language.preference.v1`) com fallback seguro
/// e dicionário embutido para execução isolada em testes e preview.
public enum SpatialCopy {
    public static let languagePreferenceKey = "linka.language.preference.v1"

    public static var currentLanguageTag: String {
        let preference = UserDefaults.standard.string(forKey: languagePreferenceKey) ?? "system"
        switch preference {
        case "pt-BR", "en", "es-419":
            return preference
        default:
            switch Locale.autoupdatingCurrent.language.languageCode?.identifier.lowercased() {
            case "pt": return "pt-BR"
            case "es": return "es-419"
            default: return "en"
            }
        }
    }

    public static var currentLocale: Locale {
        switch currentLanguageTag {
        case "pt-BR": return Locale(identifier: "pt-BR")
        case "es-419": return Locale(identifier: "es-419")
        default: return Locale(identifier: "en")
        }
    }

    public static func value(_ key: String, defaultValue: String? = nil) -> String {
        let tag = currentLanguageTag

        // 1. Tenta carregar do bundle principal (se estiver no app e com .lproj gerado)
        let bundle: Bundle
        if let path = Bundle.main.path(forResource: tag, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            bundle = localizedBundle
        } else if let path = Bundle.main.path(forResource: "pt-BR", ofType: "lproj"),
                  let fallbackBundle = Bundle(path: path) {
            bundle = fallbackBundle
        } else {
            bundle = .main
        }

        let sentinel = "__SPATIAL_NOT_FOUND__"
        let localized = bundle.localizedString(forKey: key, value: sentinel, table: "Localizable")
        if localized != sentinel {
            return localized
        }

        // 2. Fallback no catálogo interno tipado por idioma
        let targetDict = internalCatalog[tag] ?? internalCatalog["pt-BR"] ?? [:]
        if let text = targetDict[key] {
            return text
        }

        // 3. Fallback no catálogo interno em pt-BR
        if let ptText = internalCatalog["pt-BR"]?[key] {
            return ptText
        }

        return defaultValue ?? key
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: value(key), locale: currentLocale, arguments: arguments)
    }

    public static func formatDate(_ date: Date, template: String = "dMMMjm") -> String {
        let formatter = DateFormatter()
        formatter.locale = currentLocale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    public static func formatDateMedium(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = currentLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Catálogo Interno Canônico Multi-Idioma

    private static let internalCatalog: [String: [String: String]] = [
        "pt-BR": [
            // Geral & Status
            "spatial.title": "Cobertura Residencial",
            "spatial.wifi.disconnected": "Wi-Fi Desconectado",
            "spatial.wifi.disconnected.desc": "Conecte seu dispositivo à rede Wi-Fi da sua residência para realizar o mapeamento e testes de qualidade.",
            "spatial.ftue.title": "Mapeamento em 3 Passos",
            "spatial.ftue.desc": "1. Verifique seus cômodos abaixo.\n2. Caminhe até cada cômodo e meça a conexão.\n3. Identifique pontos fracos e otimize sua rede.",
            "spatial.ftue.dismiss": "Dispensar guia inicial",
            "spatial.comparative.active.title": "Modo Comparativo Ativo",
            "spatial.comparative.active.desc": "Baseline 'Antes' fixado. Realize medições com o roteador na nova posição e toque aqui para ver o ganho.",

            // Problemas B2C
            "spatial.problems.header": "Como podemos melhorar sua internet?",
            "spatial.problems.subtitle": "Escolha o problema e descubra o que fazer.",
            "spatial.problem.weakRoom.title": "Wi-Fi ruim em um cômodo",
            "spatial.problem.weakRoom.subtitle": "Investigar estabilidade e alcance no ponto com problema",
            "spatial.problem.weakRoom.prompt": "Em qual cômodo o sinal costuma falhar ou ficar lento?",
            "spatial.problem.weakRoom.focus": "Avaliando a resposta do roteador local e estabilidade do sinal Wi-Fi neste ponto.",
            "spatial.problem.videoCalls.title": "Chamadas e vídeos travando",
            "spatial.problem.videoCalls.subtitle": "Detectar oscilação de latência e perda de pacotes",
            "spatial.problem.videoCalls.prompt": "Onde você costuma fazer chamadas de vídeo ou reuniões?",
            "spatial.problem.videoCalls.focus": "Medindo variação de atraso (jitter) e perda de pacotes críticos para chamadas em tempo real.",
            "spatial.problem.routerUpgrade.title": "Preciso trocar de roteador?",
            "spatial.problem.routerUpgrade.subtitle": "Avaliar antes de gastar dinheiro com equipamentos",
            "spatial.problem.routerUpgrade.prompt": "Em qual cômodo você mais sente necessidade de melhorar a internet?",
            "spatial.problem.routerUpgrade.focus": "Verificando se o gargalo real está no roteador doméstico ou na rota da operadora.",
            "spatial.problem.planAdequacy.title": "Meu plano é suficiente?",
            "spatial.problem.planAdequacy.subtitle": "Verificar resposta da rota externa e velocidade",
            "spatial.problem.planAdequacy.prompt": "Onde você deseja avaliar a velocidade e estabilidade geral?",
            "spatial.problem.planAdequacy.focus": "Aferindo taxa de transferência e tempo de resposta externo da internet.",

            // Cabeçalho de Cobertura
            "spatial.header.qualityPoints": "QUALIDADE NOS PONTOS MEDIDOS",
            "spatial.header.roomsCount": "%d de %d cômodos",
            "spatial.header.sectionRooms": "CÔMODOS DA CASA",
            "spatial.header.edit": "Editar",
            "spatial.header.helpA11y": "Ajuda e dicas de posicionamento do roteador",

            // Cartão de Cômodo
            "spatial.room.unmeasured": "Não Medido",
            "spatial.room.measure": "Medir",
            "spatial.room.remeasure": "Re-medir",
            "spatial.room.router": "Roteador",

            // Múltiplos APs
            "spatial.ap.multiple.title": "Múltiplos Pontos de Acesso",
            "spatial.ap.multiple.desc": "Detectamos %d pontos de acesso diferentes na residência.",
            "spatial.ap.multiple.view": "Ver",

            // Smart Journey CTA
            "spatial.journey.startWalk": "Iniciar Caminhada pela Casa",
            "spatial.journey.startWalk.step": "Ponto 1 de %d: %@",
            "spatial.journey.continueWalk": "Continuar Caminhada: %@",
            "spatial.journey.continueWalk.step": "Passo %d de %d",
            "spatial.journey.recommendation": "Recomendação de Posicionamento",
            "spatial.journey.newComparison": "Nova Caminhada de Comparação (%d %@)",
            "spatial.journey.weakPoint.single": "ponto fraco",
            "spatial.journey.weakPoint.multiple": "pontos fracos",
            "spatial.journey.stable": "Rede Estável — Ver Comparativo",

            // Classificações e Tags
            "spatial.rating.excellent": "Ótimo",
            "spatial.rating.good": "Bom",
            "spatial.rating.fair": "Regular",
            "spatial.rating.poor": "Ruim",
            "spatial.rating.unmeasured": "Não Medido",
            "spatial.tag.healthy": "Sinal Estável",
            "spatial.tag.weakWiFi": "Wi-Fi Fraco",
            "spatial.tag.slowProvider": "Operadora Lenta",
            "spatial.tag.unmeasured": "Não Medido",

            // AP Types
            "spatial.ap.none": "Nenhum",
            "spatial.ap.mainRouter": "Roteador Principal",
            "spatial.ap.meshSatellite": "Nó Mesh",
            "spatial.ap.repeater": "Repetidor Wi-Fi",
            "spatial.ap.short.router": "Roteador",
            "spatial.ap.short.repeater": "Repetidor",

            // Backhaul
            "spatial.backhaul.wifi": "Sem Fio (Wi-Fi)",
            "spatial.backhaul.ethernet": "Cabo de Rede (Ethernet)",
            "spatial.backhaul.unknown": "Desconhecido",

            // Loss Interpretation
            "spatial.loss.stable": "Estável",
            "spatial.loss.isolated": "Oscilação Isolada",
            "spatial.loss.confirmed": "Perda Confirmada",
            "spatial.loss.consecutive": "Perdas Consecutivas",
            "spatial.loss.severe": "Timeout Crítico",

            // Walk Session
            "spatial.walk.mapHome": "Mapear minha casa",
            "spatial.walk.recordBaseline": "Gravar Baseline Inicial",
            "spatial.walk.newComparison": "Nova caminhada de comparação",
            "spatial.walk.intro": "Vamos caminhar por %d cômodos na ordem mais eficiente pela sua casa.",
            "spatial.walk.tip1": "1 toque por cômodo quando estiver no local",
            "spatial.walk.tip2": "Duração estimada: cerca de 2 minutos",
            "spatial.walk.tip3": "Detecção inteligente de pontos de acesso Wi-Fi",
            "spatial.walk.start": "Começar Caminhada",
            "spatial.walk.guide.router": "Vá até a %@, próximo ao roteador.",
            "spatial.walk.guide.regular": "Caminhe até a %@.",
            "spatial.walk.whenThere": "📍 Quando estiver no local:",
            "spatial.walk.imHere": "Estou aqui",
            "spatial.walk.skip": "Pular este cômodo",
            "spatial.walk.measuring": "Medindo %@…",
            "spatial.walk.latency": "Latência: %@ ms",
            "spatial.walk.next": "Próximo cômodo: %@",
            "spatial.walk.allVisited": "Todos os cômodos foram visitados!",
            "spatial.walk.continue": "Continuar caminhada",
            "spatial.walk.finish": "Ver resultado final",
            "spatial.walk.completed": "Mapeamento Concluído",
            "spatial.walk.averageQuality": "Qualidade Média nos Pontos Medidos",
            "spatial.walk.seeOnMap": "Ver resultado no mapa",

            // Steps
            "spatial.step.verifying": "Verificando rede Wi-Fi...",
            "spatial.step.gateway": "Localizando roteador...",
            "spatial.step.permission": "Verificando permissão de rede local...",
            "spatial.step.waiting": "Aguardando autorização de rede local...",
            "spatial.step.probingLAN": "Medindo sinal até o roteador (LAN)...",
            "spatial.step.stability": "Avaliando estabilidade da rede...",
            "spatial.step.probingWAN": "Verificando rota para a internet (WAN)...",
            "spatial.step.throughput": "Validando taxa de vazão...",
            "spatial.step.completing": "Concluindo diagnóstico...",

            // Comparativo
            "spatial.comparison.title": "Comparativo Antes × Depois",
            "spatial.comparison.desc": "Fixe o estado atual da sua casa como ponto de partida (Antes). Em seguida, mude o roteador de lugar ou instale nós mesh para comprovar o ganho real de sinal.",
            "spatial.comparison.setBaseline": "Definir Leituras Atuais como Baseline (Antes)",
            "spatial.comparison.baselineActive": "Baseline 'Antes' Ativo",
            "spatial.comparison.roomsRegistered": "%d cômodos registrados no ponto de partida.",
            "spatial.comparison.continueMeasuring": "Com o roteador no novo local, caminhe pelos cômodos e realize novas medições na tela inicial. Quando terminar, gere o comparativo.",
            "spatial.comparison.resumeMap": "Continuar Medindo no Mapa",
            "spatial.comparison.evolution": "EVOLUÇÃO DA QUALIDADE MÉDIA",
            "spatial.comparison.before": "Antes",
            "spatial.comparison.after": "Depois",
            "spatial.comparison.byRoom": "COMPARAÇÃO POR CÔMODO",

            // Detected APs
            "spatial.aps.title": "Topologia de Rádios",
            "spatial.aps.observed": "PONTOS DE ACESSO OBSERVADOS",
            "spatial.aps.count": "Identificamos %d %@ aos quais seu dispositivo se associou durante as medições na residência.",
            "spatial.aps.measurements": "%d %@",
            "spatial.aps.techDetails": "Detalhes Técnicos",
            "spatial.aps.explanation": "Múltiplos pontos de acesso sob o mesmo nome de rede geralmente indicam nós Mesh, repetidores ou roteadores adicionais. O mesmo equipamento também pode emitir BSSIDs distintos para as frequências de 2.4 GHz e 5 GHz.",

            // Relatório PDF
            "spatial.pdf.title": "Relatório Técnico Vetorial",
            "spatial.pdf.rendering": "Renderizando Relatório Técnico Vetorial...",
            "spatial.pdf.export": "Exportar PDF",
            "spatial.pdf.share": "Compartilhar Relatório",
            "spatial.pdf.house": "Residência:",
            "spatial.pdf.ssid": "Rede (SSID):",
            "spatial.pdf.gateway": "Gateway Local:",
            "spatial.pdf.date": "Data da Emissão:",
            "spatial.pdf.average": "Qualidade Média:",
            "spatial.pdf.topology": "Topologia:",

            // Comum
            "spatial.common.close": "Fechar",
            "spatial.common.ok": "OK",
            "spatial.common.save": "Salvar",
            "spatial.common.delete": "Excluir",
            "spatial.common.cancel": "Cancelar",
            "spatial.common.tryAgain": "Tentar Novamente",
            "spatial.common.settings": "Abrir Ajustes",
            "spatial.common.emptyHistory": "Nenhuma Comparação Salva",
            "spatial.common.emptyHistoryDesc": "Realize medições e gere comparativos Antes × Depois para registrar a evolução da sua rede Wi-Fi.",
            "spatial.common.historyTitle": "Histórico de Otimizações",
            "spatial.common.defaultHouse": "Minha Casa",

            // Investigação e Modos
            "spatial.mode.guidedTwoPoint": "Investigação Completa",
            "spatial.mode.quickSingle": "Teste Rápido",
            "spatial.problem.markRouterNote": "Marque o cômodo com roteador na planta para habilitar a Investigação Completa de 2 pontos.",
            "spatial.problem.startGuided": "Iniciar Investigação Completa",
            "spatial.problem.startRoom": "Iniciar Teste no %@",
            "spatial.problem.routerNote": "Ponto base do sinal. Use para checar a emissão original.",
            "spatial.problem.lastScore": "Última nota: %d/100 (%@)",
            "spatial.problem.backToRooms": "Voltar para Escolha de Cômodo",
            "spatial.problem.errorTitle": "Não foi possível concluir o teste",
            "spatial.problem.didChangeRemeasure": "Fiz a Mudança — Medir Novamente",
            "spatial.problem.finishDiagnostic": "Concluir Diagnóstico",
            "spatial.problem.evolutionConfirmed": "Evolução Confirmada!",
            "spatial.problem.evolutionDesc": "A mudança física gerou ganho real de estabilidade na conexão neste cômodo (+%d pontos).",
            "spatial.problem.samePerformance": "Mesmo Desempenho",
            "spatial.problem.sameDesc": "A pontuação permaneceu estável (%d → %d pontos). A alteração ficou dentro da margem normal de oscilação da rede.",
            "spatial.problem.dropPerformance": "Queda de Desempenho",
            "spatial.problem.dropDesc": "A nova posição testada reduziu a qualidade da conexão (%d pontos). Retorne à posição anterior ou tente outro local.",
            "spatial.problem.saveAndClose": "Salvar e Fechar",
            "spatial.problem.baseRouter": "Base (Roteador)",
            "spatial.problem.observedHypothesis": "HIPÓTESE OBSERVADA",
            "spatial.problem.suggestedAction": "AÇÃO PRÁTICA SUGERIDA",
            "spatial.problem.observedEvidence": "EVIDÊNCIAS OBSERVADAS",
            "spatial.problem.scoreInRoom": "Pontuação no %@",
            "spatial.problem.routerLAN": "Roteador (LAN)",
            "spatial.problem.internetWAN": "Internet (WAN)",
            "spatial.problem.normal": "Normal",
            "spatial.problem.attention": "Atenção",
            "spatial.problem.lossSuffix": " (%@ perda)",
            "spatial.problem.step1Badge": "Passo 1 de 3 • Ponto de Origem",
            "spatial.problem.step1Title": "Vá até o %@",
            "spatial.problem.step1Desc": "Para descobrir com precisão se a lentidão decorre de paredes ou da sua operadora, primeiro medimos a conexão ao lado do roteador.",
            "spatial.problem.step1Button": "Estou ao Lado do Roteador — Medir Base",
            "spatial.problem.step2Badge": "Passo 2 de 3 • Ponto Problemático",
            "spatial.problem.step2Title": "Caminhe até o %@",
            "spatial.problem.step2Desc": "Base registrada (%d/100). Agora vá até o %@ para medir a perda de sinal no trajeto e o impacto das paredes.",
            "spatial.problem.step2Button": "Estou no %@ — Medir Sinal",
            "spatial.problem.measuringBase": "Medindo Base em %@...",
            "spatial.problem.measuringTarget": "Avaliando %@...",
            "spatial.problem.measuringAgain": "Medindo Novamente...",
            "spatial.problem.validatingGain": "Validando Ganho no %@...",
            "spatial.problem.retestTarget": "Fiz a Mudança — Re-testar %@",
            "spatial.problem.finishWithoutRetest": "Concluir sem Re-teste",
            "spatial.problem.saveVerdictReport": "Salvar Relatório da Solução e Fechar",
            "spatial.problem.beforeChange": "Antes da Mudança",
            "spatial.problem.afterChange": "Depois da Mudança",

            // Detalhes da Medição
            "spatial.detail.actionable": "DIAGNÓSTICO ACIONÁVEL",
            "spatial.detail.scoreQuality": "Score de Qualidade: %d / 100",
            "spatial.detail.wifiAndAP": "REDE WI-FI & PONTO DE ACESSO",
            "spatial.detail.connectedSSID": "Rede Conectada (SSID)",
            "spatial.detail.accessPoint": "Ponto de Acesso",
            "spatial.detail.apHandoff": "Mudança de ponto de acesso detectada (%@ → %@). Seu iPhone alternou de rádio durante a caminhada.",
            "spatial.detail.apTechDetails": "Detalhes Técnicos do AP",
            "spatial.detail.bssid": "Identificador (BSSID)",
            "spatial.detail.lanSection": "SEGMENTO WI-FI LOCAL (LAN)",
            "spatial.detail.gatewayRouter": "Gateway / Roteador",
            "spatial.detail.routerLatency": "Latência no Roteador (Mediana)",
            "spatial.detail.routerP95": "Pico de Latência (p95)",
            "spatial.detail.lanJitter": "Jitter Local (RFC 3550)",
            "spatial.detail.packetStability": "Estabilidade de Pacotes",
            "spatial.detail.lanLoss": "Perda de Pacotes Local",
            "spatial.detail.wanSection": "SEGMENTO INTERNET (WAN)",
            "spatial.detail.wanLatency": "Latência Externa (Mediana)",
            "spatial.detail.wanP95": "Pico Externo (p95)",
            "spatial.detail.wanJitter": "Jitter Externo",
            "spatial.detail.wanLoss": "Perda Externa",
            "spatial.detail.throughput": "Vazão (Micro-Download 2 MB)",
            "spatial.detail.testUnavailable": "Teste indisponível",
            "spatial.detail.goToNext": "Ir para o Próximo: %@",
            "spatial.detail.measureAgain": "Medir Novamente",
            "spatial.detail.roomUnmeasured": "Cômodo Não Medido",
            "spatial.detail.roomUnmeasuredDesc": "Realize um teste ativo neste cômodo para visualizar a latência até o roteador e diagnosticar sua conexão.",

            // Editor de Cômodos
            "spatial.editor.title": "Gerenciar Cômodos",
            "spatial.editor.sectionRooms": "CÔMODOS DA RESIDÊNCIA",
            "spatial.editor.footerAP": "Aponte o Roteador Principal e configure seus Nós Mesh ou Repetidores para diagnósticos acionáveis de cobertura e backhaul.",
            "spatial.editor.addRoom": "Adicionar Novo Cômodo",
            "spatial.editor.newRoom": "Novo Cômodo",
            "spatial.editor.newRoomPlaceholder": "Ex: Varanda, Corredor",
            "spatial.editor.add": "Adicionar",
            "spatial.editor.roomName": "Nome do Cômodo",
            "spatial.editor.apHeader": "Ponto de Acesso Wi-Fi",
            "spatial.editor.apType": "Tipo de Ponto",
            "spatial.editor.backhaul": "Conexão (Backhaul)",

            // Escaneamento e LiDAR
            "spatial.scan.introTitle": "Como escanear sua casa",
            "spatial.scan.introSubtitle": "Gere uma planta tridimensional precisa em menos de 2 minutos utilizando os sensores do iPhone Pro.",
            "spatial.scan.tip1Title": "Boa Iluminação",
            "spatial.scan.tip1Desc": "Acenda as luzes dos cômodos para ajudar os sensores ópticos e de profundidade a mapear os cantos.",
            "spatial.scan.tip2Title": "Abra as Portas",
            "spatial.scan.tip2Desc": "Mantenha as portas internas abertas para que o sistema identifique a transição e limites entre os cômodos.",
            "spatial.scan.tip3Title": "Caminhada Calma",
            "spatial.scan.tip3Desc": "Caminhe suavemente pelo perímetro de cada cômodo, apontando a câmera para paredes, quinas e chão.",
            "spatial.scan.start": "Iniciar Escaneamento",
            "spatial.scan.manualEditor": "Usar Editor 2D Manual",
            "spatial.scan.prepareTitle": "Preparar Escaneamento",
            "spatial.lidar.unavailableTitle": "Sensor LiDAR Não Disponível",
            "spatial.lidar.unavailableDesc": "Este dispositivo não possui o sensor de escaneamento 3D exclusivo dos modelos iPhone e iPad Pro.\n\nVocê pode criar, organizar e dimensionar todos os cômodos da sua residência com nosso Editor 2D manual!",
            "spatial.lidar.navTitle": "Escaneamento Espacial",

            // Medição Ativa
            "spatial.measuring.cancel": "Cancelar Teste",
            "spatial.measuring.title": "Medição Ativa",

            // Comparativo
            "spatial.comparison.step2Header": "Passo 2: Reposicionar e Re-medir",
            "spatial.comparison.step2Desc": "1. Mova fisicamente o roteador (ex: aproxime do corredor ou eleve a altura) ou ligue o repetidor/mesh.\n2. Aguarde 1 minuto para o sinal se estabilizar.\n3. Vá ao mapa para realizar a nova rodada de testes nos cômodos.",
            "spatial.comparison.goToMap": "Ir ao Mapa para Medir",
            "spatial.comparison.alreadyMeasured": "Já Realizei as Medições — Comparar",
            "spatial.comparison.discardBaseline": "Descartar Baseline",
            "spatial.comparison.generateWithCurrent": "Gerar Comparativo com Leituras Atuais",
            "spatial.comparison.discardAndNew": "Descartar e Iniciar Novo Baseline",
            "spatial.comparison.deltaQuality": "%@%% na Qualidade Média Medida",
            "spatial.comparison.saved": "Salvo no Histórico",
            "spatial.comparison.save": "Salvar no Histórico"
        ],
        "en": [
            // General & Status
            "spatial.title": "Home Coverage",
            "spatial.wifi.disconnected": "Wi-Fi Disconnected",
            "spatial.wifi.disconnected.desc": "Connect your device to your home Wi-Fi network to perform mapping and quality tests.",
            "spatial.ftue.title": "3-Step Mapping",
            "spatial.ftue.desc": "1. Check your rooms below.\n2. Walk to each room and measure the connection.\n3. Identify weak spots and optimize your network.",
            "spatial.ftue.dismiss": "Dismiss initial guide",
            "spatial.comparative.active.title": "Comparative Mode Active",
            "spatial.comparative.active.desc": "Baseline 'Before' is set. Take measurements with the router in the new location and tap here to see the improvement.",

            // B2C Problems
            "spatial.problems.header": "How can we improve your internet?",
            "spatial.problems.subtitle": "Choose an issue and find out what to do.",
            "spatial.problem.weakRoom.title": "Weak Wi-Fi in a room",
            "spatial.problem.weakRoom.subtitle": "Investigate stability and range at the problem spot",
            "spatial.problem.weakRoom.prompt": "In which room does the signal usually fail or get slow?",
            "spatial.problem.weakRoom.focus": "Evaluating local router response and Wi-Fi signal stability at this point.",
            "spatial.problem.videoCalls.title": "Video calls and streams freezing",
            "spatial.problem.videoCalls.subtitle": "Detect latency jitter and packet loss",
            "spatial.problem.videoCalls.prompt": "Where do you usually make video calls or attend meetings?",
            "spatial.problem.videoCalls.focus": "Measuring jitter and packet loss critical for real-time video calls.",
            "spatial.problem.routerUpgrade.title": "Do I need a new router?",
            "spatial.problem.routerUpgrade.subtitle": "Evaluate before spending money on new hardware",
            "spatial.problem.routerUpgrade.prompt": "In which room do you feel the greatest need for better internet?",
            "spatial.problem.routerUpgrade.focus": "Checking whether the real bottleneck is in your home router or provider route.",
            "spatial.problem.planAdequacy.title": "Is my plan adequate?",
            "spatial.problem.planAdequacy.subtitle": "Check external route response and throughput",
            "spatial.problem.planAdequacy.prompt": "Where do you want to evaluate overall speed and stability?",
            "spatial.problem.planAdequacy.focus": "Assessing transfer speed and external internet response times.",

            // Coverage Header
            "spatial.header.qualityPoints": "QUALITY AT MEASURED POINTS",
            "spatial.header.roomsCount": "%d of %d rooms",
            "spatial.header.sectionRooms": "HOUSE ROOMS",
            "spatial.header.edit": "Edit",
            "spatial.header.helpA11y": "Help and router placement tips",

            // Room Card
            "spatial.room.unmeasured": "Unmeasured",
            "spatial.room.measure": "Measure",
            "spatial.room.remeasure": "Re-measure",
            "spatial.room.router": "Router",

            // Multiple APs
            "spatial.ap.multiple.title": "Multiple Access Points",
            "spatial.ap.multiple.desc": "Detected %d different access points in your residence.",
            "spatial.ap.multiple.view": "View",

            // Smart Journey CTA
            "spatial.journey.startWalk": "Start Walk Around Home",
            "spatial.journey.startWalk.step": "Stop 1 of %d: %@",
            "spatial.journey.continueWalk": "Continue Walk: %@",
            "spatial.journey.continueWalk.step": "Step %d of %d",
            "spatial.journey.recommendation": "Placement Recommendation",
            "spatial.journey.newComparison": "New Comparison Walk (%d %@)",
            "spatial.journey.weakPoint.single": "weak spot",
            "spatial.journey.weakPoint.multiple": "weak spots",
            "spatial.journey.stable": "Stable Network — View Comparison",

            // Ratings and Tags
            "spatial.rating.excellent": "Great",
            "spatial.rating.good": "Good",
            "spatial.rating.fair": "Fair",
            "spatial.rating.poor": "Poor",
            "spatial.rating.unmeasured": "Unmeasured",
            "spatial.tag.healthy": "Stable Signal",
            "spatial.tag.weakWiFi": "Weak Wi-Fi",
            "spatial.tag.slowProvider": "Slow Provider",
            "spatial.tag.unmeasured": "Unmeasured",

            // AP Types
            "spatial.ap.none": "None",
            "spatial.ap.mainRouter": "Main Router",
            "spatial.ap.meshSatellite": "Mesh Node",
            "spatial.ap.repeater": "Wi-Fi Repeater",
            "spatial.ap.short.router": "Router",
            "spatial.ap.short.repeater": "Repeater",

            // Backhaul
            "spatial.backhaul.wifi": "Wireless (Wi-Fi)",
            "spatial.backhaul.ethernet": "Ethernet Cable",
            "spatial.backhaul.unknown": "Unknown",

            // Loss Interpretation
            "spatial.loss.stable": "Stable",
            "spatial.loss.isolated": "Isolated Jitter",
            "spatial.loss.confirmed": "Confirmed Loss",
            "spatial.loss.consecutive": "Consecutive Loss",
            "spatial.loss.severe": "Critical Timeout",

            // Walk Session
            "spatial.walk.mapHome": "Map my home",
            "spatial.walk.recordBaseline": "Record Initial Baseline",
            "spatial.walk.newComparison": "New comparison walk",
            "spatial.walk.intro": "We will walk through %d rooms in the most efficient order around your home.",
            "spatial.walk.tip1": "1 tap per room when you arrive",
            "spatial.walk.tip2": "Estimated duration: about 2 minutes",
            "spatial.walk.tip3": "Smart Wi-Fi access point detection",
            "spatial.walk.start": "Start Walk",
            "spatial.walk.guide.router": "Go to %@, near the router.",
            "spatial.walk.guide.regular": "Walk to %@.",
            "spatial.walk.whenThere": "📍 When you are there:",
            "spatial.walk.imHere": "I'm here",
            "spatial.walk.skip": "Skip this room",
            "spatial.walk.measuring": "Measuring %@…",
            "spatial.walk.latency": "Latency: %@ ms",
            "spatial.walk.next": "Next room: %@",
            "spatial.walk.allVisited": "All rooms have been visited!",
            "spatial.walk.continue": "Continue walk",
            "spatial.walk.finish": "See final result",
            "spatial.walk.completed": "Mapping Completed",
            "spatial.walk.averageQuality": "Average Quality at Measured Points",
            "spatial.walk.seeOnMap": "View result on map",

            // Steps
            "spatial.step.verifying": "Verifying Wi-Fi network...",
            "spatial.step.gateway": "Locating router...",
            "spatial.step.permission": "Checking local network permission...",
            "spatial.step.waiting": "Waiting for local network authorization...",
            "spatial.step.probingLAN": "Measuring signal to router (LAN)...",
            "spatial.step.stability": "Evaluating network stability...",
            "spatial.step.probingWAN": "Checking route to internet (WAN)...",
            "spatial.step.throughput": "Validating throughput...",
            "spatial.step.completing": "Completing diagnostic...",

            // Comparative
            "spatial.comparison.title": "Before × After Comparison",
            "spatial.comparison.desc": "Set the current state of your home as baseline (Before). Then move the router or add mesh nodes to prove the real signal improvement.",
            "spatial.comparison.setBaseline": "Set Current Readings as Baseline (Before)",
            "spatial.comparison.baselineActive": "'Before' Baseline Active",
            "spatial.comparison.roomsRegistered": "%d rooms recorded as baseline.",
            "spatial.comparison.continueMeasuring": "With the router in its new location, walk through the rooms and take new measurements. When done, generate the comparison.",
            "spatial.comparison.resumeMap": "Continue Measuring on Map",
            "spatial.comparison.evolution": "AVERAGE QUALITY EVOLUTION",
            "spatial.comparison.before": "Before",
            "spatial.comparison.after": "After",
            "spatial.comparison.byRoom": "ROOM-BY-ROOM COMPARISON",

            // Detected APs
            "spatial.aps.title": "Radio Topology",
            "spatial.aps.observed": "OBSERVED ACCESS POINTS",
            "spatial.aps.count": "We identified %d %@ your device associated with during measurements at home.",
            "spatial.aps.measurements": "%d %@",
            "spatial.aps.techDetails": "Technical Details",
            "spatial.aps.explanation": "Multiple access points under the same network name usually indicate Mesh nodes, repeaters, or additional routers. The same hardware may also broadcast different BSSIDs for 2.4 GHz and 5 GHz frequencies.",

            // PDF Report
            "spatial.pdf.title": "Vector Technical Report",
            "spatial.pdf.rendering": "Rendering Technical Vector Report...",
            "spatial.pdf.export": "Export PDF",
            "spatial.pdf.share": "Share Report",
            "spatial.pdf.house": "Residence:",
            "spatial.pdf.ssid": "Network (SSID):",
            "spatial.pdf.gateway": "Local Gateway:",
            "spatial.pdf.date": "Issue Date:",
            "spatial.pdf.average": "Average Quality:",
            "spatial.pdf.topology": "Topology:",

            // Common
            "spatial.common.close": "Close",
            "spatial.common.ok": "OK",
            "spatial.common.save": "Save",
            "spatial.common.delete": "Delete",
            "spatial.common.cancel": "Cancel",
            "spatial.common.tryAgain": "Try Again",
            "spatial.common.settings": "Open Settings",
            "spatial.common.emptyHistory": "No Saved Comparisons",
            "spatial.common.emptyHistoryDesc": "Perform measurements and generate Before × After comparisons to track the evolution of your Wi-Fi.",
            "spatial.common.historyTitle": "Optimization History",
            "spatial.common.defaultHouse": "My Home",

            // Investigation & Modes
            "spatial.mode.guidedTwoPoint": "Full Investigation",
            "spatial.mode.quickSingle": "Quick Test",
            "spatial.problem.markRouterNote": "Mark the room with the router on the floor plan to enable the 2-point Full Investigation.",
            "spatial.problem.startGuided": "Start Full Investigation",
            "spatial.problem.startRoom": "Start Test in %@",
            "spatial.problem.routerNote": "Base signal point. Use to check original emission.",
            "spatial.problem.lastScore": "Last score: %d/100 (%@)",
            "spatial.problem.backToRooms": "Back to Room Selection",
            "spatial.problem.errorTitle": "Could not complete the test",
            "spatial.problem.didChangeRemeasure": "I Made the Change — Test Again",
            "spatial.problem.finishDiagnostic": "Finish Diagnostic",
            "spatial.problem.evolutionConfirmed": "Improvement Confirmed!",
            "spatial.problem.evolutionDesc": "The physical change yielded real stability gain in this room (+%d points).",
            "spatial.problem.samePerformance": "Same Performance",
            "spatial.problem.sameDesc": "The score remained stable (%d → %d points). Variation stayed within normal network oscillation.",
            "spatial.problem.dropPerformance": "Performance Drop",
            "spatial.problem.dropDesc": "The tested position reduced connection quality (%d points). Return to previous position or try another spot.",
            "spatial.problem.saveAndClose": "Save and Close",
            "spatial.problem.baseRouter": "Base (Router)",
            "spatial.problem.observedHypothesis": "OBSERVED HYPOTHESIS",
            "spatial.problem.suggestedAction": "SUGGESTED ACTION",
            "spatial.problem.observedEvidence": "OBSERVED EVIDENCE",
            "spatial.problem.scoreInRoom": "Score in %@",
            "spatial.problem.routerLAN": "Router (LAN)",
            "spatial.problem.internetWAN": "Internet (WAN)",
            "spatial.problem.normal": "Normal",
            "spatial.problem.attention": "Attention",
            "spatial.problem.lossSuffix": " (%@ loss)",
            "spatial.problem.step1Badge": "Step 1 of 3 • Origin Point",
            "spatial.problem.step1Title": "Go to the %@",
            "spatial.problem.step1Desc": "To precisely pinpoint whether slowness comes from walls or your ISP, we first measure next to the router.",
            "spatial.problem.step1Button": "I'm Next to the Router — Measure Base",
            "spatial.problem.step2Badge": "Step 2 of 3 • Problem Spot",
            "spatial.problem.step2Title": "Walk to the %@",
            "spatial.problem.step2Desc": "Base recorded (%d/100). Now walk to %@ to measure path signal loss and wall impact.",
            "spatial.problem.step2Button": "I'm in %@ — Measure Signal",
            "spatial.problem.measuringBase": "Measuring Base in %@...",
            "spatial.problem.measuringTarget": "Evaluating %@...",
            "spatial.problem.measuringAgain": "Measuring Again...",
            "spatial.problem.validatingGain": "Validating Gain in %@...",
            "spatial.problem.retestTarget": "I Made the Change — Retest %@",
            "spatial.problem.finishWithoutRetest": "Finish without Retest",
            "spatial.problem.saveVerdictReport": "Save Solution Report and Close",
            "spatial.problem.beforeChange": "Before the Change",
            "spatial.problem.afterChange": "After the Change",

            // Measurement Details
            "spatial.detail.actionable": "ACTIONABLE DIAGNOSTIC",
            "spatial.detail.scoreQuality": "Quality Score: %d / 100",
            "spatial.detail.wifiAndAP": "WI-FI NETWORK & ACCESS POINT",
            "spatial.detail.connectedSSID": "Connected Network (SSID)",
            "spatial.detail.accessPoint": "Access Point",
            "spatial.detail.apHandoff": "Access point handoff detected (%@ → %@). Your iPhone switched radios while walking.",
            "spatial.detail.apTechDetails": "AP Technical Details",
            "spatial.detail.bssid": "Identifier (BSSID)",
            "spatial.detail.lanSection": "LOCAL WI-FI SEGMENT (LAN)",
            "spatial.detail.gatewayRouter": "Gateway / Router",
            "spatial.detail.routerLatency": "Router Latency (Median)",
            "spatial.detail.routerP95": "Latency Peak (p95)",
            "spatial.detail.lanJitter": "Local Jitter (RFC 3550)",
            "spatial.detail.packetStability": "Packet Stability",
            "spatial.detail.lanLoss": "Local Packet Loss",
            "spatial.detail.wanSection": "INTERNET SEGMENT (WAN)",
            "spatial.detail.wanLatency": "External Latency (Median)",
            "spatial.detail.wanP95": "External Peak (p95)",
            "spatial.detail.wanJitter": "External Jitter",
            "spatial.detail.wanLoss": "External Loss",
            "spatial.detail.throughput": "Throughput (Micro-Download 2 MB)",
            "spatial.detail.testUnavailable": "Test unavailable",
            "spatial.detail.goToNext": "Go to Next: %@",
            "spatial.detail.measureAgain": "Measure Again",
            "spatial.detail.roomUnmeasured": "Room Not Measured",
            "spatial.detail.roomUnmeasuredDesc": "Perform an active test in this room to view latency to the router and diagnose your connection.",

            // Room Editor
            "spatial.editor.title": "Manage Rooms",
            "spatial.editor.sectionRooms": "ROOMS OF THE RESIDENCE",
            "spatial.editor.footerAP": "Point out the Main Router and configure your Mesh Nodes or Repeaters for actionable coverage and backhaul diagnostics.",
            "spatial.editor.addRoom": "Add New Room",
            "spatial.editor.newRoom": "New Room",
            "spatial.editor.newRoomPlaceholder": "Ex: Balcony, Hallway",
            "spatial.editor.add": "Add",
            "spatial.editor.roomName": "Room Name",
            "spatial.editor.apHeader": "Wi-Fi Access Point",
            "spatial.editor.apType": "Point Type",
            "spatial.editor.backhaul": "Connection (Backhaul)",

            // Scan & LiDAR
            "spatial.scan.introTitle": "How to scan your home",
            "spatial.scan.introSubtitle": "Generate an accurate 3D floor plan in under 2 minutes using iPhone Pro sensors.",
            "spatial.scan.tip1Title": "Good Lighting",
            "spatial.scan.tip1Desc": "Turn on lights to help optical and depth sensors map corners.",
            "spatial.scan.tip2Title": "Open Doors",
            "spatial.scan.tip2Desc": "Keep interior doors open so the system detects room transitions and boundaries.",
            "spatial.scan.tip3Title": "Steady Walk",
            "spatial.scan.tip3Desc": "Walk steadily around each room's perimeter, pointing camera at walls, corners and floor.",
            "spatial.scan.start": "Start Scanning",
            "spatial.scan.manualEditor": "Use 2D Manual Editor",
            "spatial.scan.prepareTitle": "Prepare Scan",
            "spatial.lidar.unavailableTitle": "LiDAR Sensor Unavailable",
            "spatial.lidar.unavailableDesc": "This device does not have the 3D scanning sensor exclusive to iPhone and iPad Pro models.\n\nYou can create, arrange, and size all rooms in your home with our 2D manual editor!",
            "spatial.lidar.navTitle": "Spatial Scanning",

            // Active Measurement
            "spatial.measuring.cancel": "Cancel Test",
            "spatial.measuring.title": "Active Measurement",

            // Comparison
            "spatial.comparison.step2Header": "Step 2: Reposition and Retest",
            "spatial.comparison.step2Desc": "1. Move the router physically (e.g. closer to hallway or higher up) or turn on repeater/mesh.\n2. Wait 1 minute for signal to stabilize.\n3. Go to the map to run the new round of room measurements.",
            "spatial.comparison.goToMap": "Go to Map to Measure",
            "spatial.comparison.alreadyMeasured": "Measurements Done — Compare",
            "spatial.comparison.discardBaseline": "Discard Baseline",
            "spatial.comparison.generateWithCurrent": "Generate Comparison with Current Readings",
            "spatial.comparison.discardAndNew": "Discard and Start New Baseline",
            "spatial.comparison.deltaQuality": "%@%% in Measured Average Quality",
            "spatial.comparison.saved": "Saved to History",
            "spatial.comparison.save": "Save to History"
        ],
        "es-419": [
            // General & Status
            "spatial.title": "Cobertura Residencial",
            "spatial.wifi.disconnected": "Wi-Fi Desconectado",
            "spatial.wifi.disconnected.desc": "Conecta tu dispositivo a la red Wi-Fi de tu hogar para realizar el mapeo y las pruebas de calidad.",
            "spatial.ftue.title": "Mapeo en 3 Pasos",
            "spatial.ftue.desc": "1. Revisa tus habitaciones abajo.\n2. Camina a cada habitación y mide la conexión.\n3. Identifica puntos débiles y optimiza tu red.",
            "spatial.ftue.dismiss": "Descartar guía inicial",
            "spatial.comparative.active.title": "Modo Comparativo Activo",
            "spatial.comparative.active.desc": "Línea base 'Antes' fijada. Realiza mediciones con el router en la nueva posición y toca aquí para ver la mejora.",

            // Problemas B2C
            "spatial.problems.header": "¿Cómo podemos mejorar tu internet?",
            "spatial.problems.subtitle": "Elige el problema y descubre qué hacer.",
            "spatial.problem.weakRoom.title": "Wi-Fi débil en una habitación",
            "spatial.problem.weakRoom.subtitle": "Investigar estabilidad y alcance en el punto con problemas",
            "spatial.problem.weakRoom.prompt": "¿En qué habitación la señal suele fallar o ponerse lenta?",
            "spatial.problem.weakRoom.focus": "Evaluando la respuesta del router local y la estabilidad de la señal Wi-Fi en este punto.",
            "spatial.problem.videoCalls.title": "Videollamadas y videos trabándose",
            "spatial.problem.videoCalls.subtitle": "Detectar oscilación de latencia y pérdida de paquetes",
            "spatial.problem.videoCalls.prompt": "¿Dónde sueles hacer videollamadas o reuniones?",
            "spatial.problem.videoCalls.focus": "Midiendo variación de retraso (jitter) y pérdida de paquetes críticos para llamadas en tiempo real.",
            "spatial.problem.routerUpgrade.title": "¿Necesito cambiar de router?",
            "spatial.problem.routerUpgrade.subtitle": "Evaluar antes de gastar dinero en equipos nuevos",
            "spatial.problem.routerUpgrade.prompt": "¿En qué habitación sientes mayor necesidad de mejorar el internet?",
            "spatial.problem.routerUpgrade.focus": "Verificando si el cuello de botella real está en el router doméstico o en la ruta del operador.",
            "spatial.problem.planAdequacy.title": "¿Mi plan es suficiente?",
            "spatial.problem.planAdequacy.subtitle": "Verificar respuesta de la ruta externa y velocidad",
            "spatial.problem.planAdequacy.prompt": "¿Dónde deseas evaluar la velocidad y estabilidad general?",
            "spatial.problem.planAdequacy.focus": "Midiendo tasa de transferencia y tiempo de respuesta externo de internet.",

            // Cabecera Cobertura
            "spatial.header.qualityPoints": "CALIDAD EN PUNTOS MEDIDOS",
            "spatial.header.roomsCount": "%d de %d habitaciones",
            "spatial.header.sectionRooms": "HABITACIONES DE LA CASA",
            "spatial.header.edit": "Editar",
            "spatial.header.helpA11y": "Ayuda y consejos de ubicación del router",

            // Tarjeta Habitación
            "spatial.room.unmeasured": "No Medido",
            "spatial.room.measure": "Medir",
            "spatial.room.remeasure": "Re-medir",
            "spatial.room.router": "Router",

            // Múltiples APs
            "spatial.ap.multiple.title": "Múltiples Puntos de Acceso",
            "spatial.ap.multiple.desc": "Detectamos %d puntos de acceso diferentes en la residencia.",
            "spatial.ap.multiple.view": "Ver",

            // Smart Journey CTA
            "spatial.journey.startWalk": "Iniciar Caminata por la Casa",
            "spatial.journey.startWalk.step": "Punto 1 de %d: %@",
            "spatial.journey.continueWalk": "Continuar Caminata: %@",
            "spatial.journey.continueWalk.step": "Paso %d de %d",
            "spatial.journey.recommendation": "Recomendación de Ubicación",
            "spatial.journey.newComparison": "Nueva Caminata de Comparación (%d %@)",
            "spatial.journey.weakPoint.single": "punto débil",
            "spatial.journey.weakPoint.multiple": "puntos débiles",
            "spatial.journey.stable": "Red Estable — Ver Comparativa",

            // Calificaciones y Tags
            "spatial.rating.excellent": "Excelente",
            "spatial.rating.good": "Bueno",
            "spatial.rating.fair": "Regular",
            "spatial.rating.poor": "Malo",
            "spatial.rating.unmeasured": "No Medido",
            "spatial.tag.healthy": "Señal Estable",
            "spatial.tag.weakWiFi": "Wi-Fi Débil",
            "spatial.tag.slowProvider": "Operador Lento",
            "spatial.tag.unmeasured": "No Medido",

            // AP Types
            "spatial.ap.none": "Ninguno",
            "spatial.ap.mainRouter": "Router Principal",
            "spatial.ap.meshSatellite": "Nodo Mesh",
            "spatial.ap.repeater": "Repetidor Wi-Fi",
            "spatial.ap.short.router": "Router",
            "spatial.ap.short.repeater": "Repetidor",

            // Backhaul
            "spatial.backhaul.wifi": "Inalámbrico (Wi-Fi)",
            "spatial.backhaul.ethernet": "Cable de Red (Ethernet)",
            "spatial.backhaul.unknown": "Desconocido",

            // Loss Interpretation
            "spatial.loss.stable": "Estable",
            "spatial.loss.isolated": "Oscilación Aislada",
            "spatial.loss.confirmed": "Pérdida Confirmada",
            "spatial.loss.consecutive": "Pérdidas Consecutivas",
            "spatial.loss.severe": "Timeout Crítico",

            // Walk Session
            "spatial.walk.mapHome": "Mapear mi casa",
            "spatial.walk.recordBaseline": "Grabar Línea Base Inicial",
            "spatial.walk.newComparison": "Nueva caminata de comparación",
            "spatial.walk.intro": "Caminaremos por %d habitaciones en el orden más eficiente de tu casa.",
            "spatial.walk.tip1": "1 toque por habitación al llegar",
            "spatial.walk.tip2": "Duración estimada: unos 2 minutos",
            "spatial.walk.tip3": "Detección inteligente de puntos de acceso Wi-Fi",
            "spatial.walk.start": "Comenzar Caminata",
            "spatial.walk.guide.router": "Ve a %@, cerca del router.",
            "spatial.walk.guide.regular": "Camina a %@.",
            "spatial.walk.whenThere": "📍 Cuando estés allí:",
            "spatial.walk.imHere": "Estoy aquí",
            "spatial.walk.skip": "Saltar esta habitación",
            "spatial.walk.measuring": "Midiendo %@…",
            "spatial.walk.latency": "Latencia: %@ ms",
            "spatial.walk.next": "Siguiente habitación: %@",
            "spatial.walk.allVisited": "¡Todas las habitaciones fueron visitadas!",
            "spatial.walk.continue": "Continuar caminata",
            "spatial.walk.finish": "Ver resultado final",
            "spatial.walk.completed": "Mapeo Completado",
            "spatial.walk.averageQuality": "Calidad Promedio en Puntos Medidos",
            "spatial.walk.seeOnMap": "Ver resultado en el mapa",

            // Steps
            "spatial.step.verifying": "Verificando red Wi-Fi...",
            "spatial.step.gateway": "Localizando router...",
            "spatial.step.permission": "Verificando permiso de red local...",
            "spatial.step.waiting": "Esperando autorización de red local...",
            "spatial.step.probingLAN": "Midiendo señal al router (LAN)...",
            "spatial.step.stability": "Evaluando estabilidad de la red...",
            "spatial.step.probingWAN": "Verificando ruta a internet (WAN)...",
            "spatial.step.throughput": "Validando tasa de transferencia...",
            "spatial.step.completing": "Completando diagnóstico...",

            // Comparativa
            "spatial.comparison.title": "Comparativa Antes × Después",
            "spatial.comparison.desc": "Fija el estado actual de tu casa como punto de partida (Antes). Luego mueve el router o instala nodos mesh para comprobar la ganancia real de señal.",
            "spatial.comparison.setBaseline": "Fijar Lecturas Actuales como Línea Base (Antes)",
            "spatial.comparison.baselineActive": "Línea Base 'Antes' Activa",
            "spatial.comparison.roomsRegistered": "%d habitaciones registradas en el punto de partida.",
            "spatial.comparison.continueMeasuring": "Con el router en la nueva posición, camina por las habitaciones y realiza nuevas mediciones en la pantalla inicial. Al terminar, genera la comparativa.",
            "spatial.comparison.resumeMap": "Continuar Midiendo en el Mapa",
            "spatial.comparison.evolution": "EVOLUCIÓN DE LA CALIDAD PROMEDIO",
            "spatial.comparison.before": "Antes",
            "spatial.comparison.after": "Después",
            "spatial.comparison.byRoom": "COMPARACIÓN POR HABITACIÓN",

            // Detected APs
            "spatial.aps.title": "Topología de Radios",
            "spatial.aps.observed": "PUNTOS DE ACCESO OBSERVADOS",
            "spatial.aps.count": "Identificamos %d %@ a los que tu dispositivo se asoció durante las mediciones en la residencia.",
            "spatial.aps.measurements": "%d %@",
            "spatial.aps.techDetails": "Detalles Técnicos",
            "spatial.aps.explanation": "Múltiples puntos de acceso bajo el mismo nombre de red usualmente indican nodos Mesh, repetidores o routers adicionales. El mismo equipo también puede emitir BSSIDs distintos para las frecuencias de 2.4 GHz y 5 GHz.",

            // PDF Report
            "spatial.pdf.title": "Informe Técnico Vectorial",
            "spatial.pdf.rendering": "Renderizando Informe Técnico Vectorial...",
            "spatial.pdf.export": "Exportar PDF",
            "spatial.pdf.share": "Compartir Informe",
            "spatial.pdf.house": "Residencia:",
            "spatial.pdf.ssid": "Red (SSID):",
            "spatial.pdf.gateway": "Puerta de Enlace Local:",
            "spatial.pdf.date": "Fecha de Emisión:",
            "spatial.pdf.average": "Calidad Media:",
            "spatial.pdf.topology": "Topología:",

            // Común
            "spatial.common.close": "Cerrar",
            "spatial.common.ok": "OK",
            "spatial.common.save": "Guardar",
            "spatial.common.delete": "Eliminar",
            "spatial.common.cancel": "Cancelar",
            "spatial.common.tryAgain": "Intentar Nuevamente",
            "spatial.common.settings": "Abrir Ajustes",
            "spatial.common.emptyHistory": "Ninguna Comparación Guardada",
            "spatial.common.emptyHistoryDesc": "Realiza mediciones y genera comparativas Antes × Después para registrar la evolución de tu red Wi-Fi.",
            "spatial.common.historyTitle": "Historial de Optimizaciones",
            "spatial.common.defaultHouse": "Mi Casa",

            // Investigación y Modos
            "spatial.mode.guidedTwoPoint": "Investigación Completa",
            "spatial.mode.quickSingle": "Prueba Rápida",
            "spatial.problem.markRouterNote": "Marque la habitación con el router en el plano para habilitar la Investigación Completa de 2 puntos.",
            "spatial.problem.startGuided": "Iniciar Investigación Completa",
            "spatial.problem.startRoom": "Iniciar Prueba en %@",
            "spatial.problem.routerNote": "Punto base de la señal. Úselo para verificar la emisión original.",
            "spatial.problem.lastScore": "Último puntaje: %d/100 (%@)",
            "spatial.problem.backToRooms": "Volver a la Selección de Habitación",
            "spatial.problem.errorTitle": "No se pudo completar la prueba",
            "spatial.problem.didChangeRemeasure": "Hice el Cambio — Probar Nuevamente",
            "spatial.problem.finishDiagnostic": "Finalizar Diagnóstico",
            "spatial.problem.evolutionConfirmed": "¡Evolución Confirmada!",
            "spatial.problem.evolutionDesc": "El cambio físico generó una mejora real en la conexión de esta habitación (+%d puntos).",
            "spatial.problem.samePerformance": "Mismo Rendimiento",
            "spatial.problem.sameDesc": "El puntaje permaneció estable (%d → %d puntos). La alteración quedó dentro del margen normal de oscilación.",
            "spatial.problem.dropPerformance": "Caída de Rendimiento",
            "spatial.problem.dropDesc": "La nueva posición probada redujo la calidad de la conexión (%d puntos). Regrese a la posición anterior o pruebe otro lugar.",
            "spatial.problem.saveAndClose": "Guardar y Cerrar",
            "spatial.problem.baseRouter": "Base (Router)",
            "spatial.problem.observedHypothesis": "HIPÓTESIS OBSERVADA",
            "spatial.problem.suggestedAction": "ACCIÓN PRÁCTICA SUGERIDA",
            "spatial.problem.observedEvidence": "EVIDENCIAS OBSERVADAS",
            "spatial.problem.scoreInRoom": "Puntaje en %@",
            "spatial.problem.routerLAN": "Router (LAN)",
            "spatial.problem.internetWAN": "Internet (WAN)",
            "spatial.problem.normal": "Normal",
            "spatial.problem.attention": "Atención",
            "spatial.problem.lossSuffix": " (%@ pérdida)",
            "spatial.problem.step1Badge": "Paso 1 de 3 • Punto de Origen",
            "spatial.problem.step1Title": "Vaya a la %@",
            "spatial.problem.step1Desc": "Para descubrir con precisión si la lentitud proviene de las paredes o de su operador, primero medimos junto al router.",
            "spatial.problem.step1Button": "Estoy al Lado del Router — Medir Base",
            "spatial.problem.step2Badge": "Paso 2 de 3 • Punto Problemático",
            "spatial.problem.step2Title": "Camine a la %@",
            "spatial.problem.step2Desc": "Base registrada (%d/100). Ahora vaya a %@ para medir la pérdida de señal en el trayecto y el impacto de las paredes.",
            "spatial.problem.step2Button": "Estoy en %@ — Medir Señal",
            "spatial.problem.measuringBase": "Midiendo Base en %@...",
            "spatial.problem.measuringTarget": "Evaluando %@...",
            "spatial.problem.measuringAgain": "Midiendo Nuevamente...",
            "spatial.problem.validatingGain": "Validando Ganancia en %@...",
            "spatial.problem.retestTarget": "Hice el Cambio — Probar %@ Nuevamente",
            "spatial.problem.finishWithoutRetest": "Finalizar sin Re-prueba",
            "spatial.problem.saveVerdictReport": "Guardar Informe de Solución y Cerrar",
            "spatial.problem.beforeChange": "Antes del Cambio",
            "spatial.problem.afterChange": "Después del Cambio",

            // Detalles de la Medición
            "spatial.detail.actionable": "DIAGNÓSTICO ACCIONABLE",
            "spatial.detail.scoreQuality": "Puntaje de Calidad: %d / 100",
            "spatial.detail.wifiAndAP": "RED WI-FI Y PUNTO DE ACCESO",
            "spatial.detail.connectedSSID": "Red Conectada (SSID)",
            "spatial.detail.accessPoint": "Punto de Acceso",
            "spatial.detail.apHandoff": "Cambio de punto de acceso detectado (%@ → %@). Su iPhone alternó de antena durante la caminata.",
            "spatial.detail.apTechDetails": "Detalles Técnicos del AP",
            "spatial.detail.bssid": "Identificador (BSSID)",
            "spatial.detail.lanSection": "SEGMENTO WI-FI LOCAL (LAN)",
            "spatial.detail.gatewayRouter": "Gateway / Router",
            "spatial.detail.routerLatency": "Latencia en el Router (Mediana)",
            "spatial.detail.routerP95": "Pico de Latencia (p95)",
            "spatial.detail.lanJitter": "Jitter Local (RFC 3550)",
            "spatial.detail.packetStability": "Estabilidad de Paquetes",
            "spatial.detail.lanLoss": "Pérdida de Paquetes Local",
            "spatial.detail.wanSection": "SEGMENTO INTERNET (WAN)",
            "spatial.detail.wanLatency": "Latencia Externa (Mediana)",
            "spatial.detail.wanP95": "Pico Externo (p95)",
            "spatial.detail.wanJitter": "Jitter Externo",
            "spatial.detail.wanLoss": "Pérdida Externa",
            "spatial.detail.throughput": "Rendimiento (Micro-Download 2 MB)",
            "spatial.detail.testUnavailable": "Prueba no disponible",
            "spatial.detail.goToNext": "Ir al Siguiente: %@",
            "spatial.detail.measureAgain": "Medir Nuevamente",
            "spatial.detail.roomUnmeasured": "Habitación No Medida",
            "spatial.detail.roomUnmeasuredDesc": "Realice una prueba activa en esta habitación para ver la latencia hacia el router y diagnosticar su conexión.",

            // Editor de Habitaciones
            "spatial.editor.title": "Administrar Habitaciones",
            "spatial.editor.sectionRooms": "HABITACIONES DEL HOGAR",
            "spatial.editor.footerAP": "Indique el Router Principal y configure sus Nodos Mesh o Repetidores para diagnósticos accionables de cobertura y backhaul.",
            "spatial.editor.addRoom": "Agregar Nueva Habitación",
            "spatial.editor.newRoom": "Nueva Habitación",
            "spatial.editor.newRoomPlaceholder": "Ej: Balcón, Pasillo",
            "spatial.editor.add": "Agregar",
            "spatial.editor.roomName": "Nombre de la Habitación",
            "spatial.editor.apHeader": "Punto de Acceso Wi-Fi",
            "spatial.editor.apType": "Tipo de Punto",
            "spatial.editor.backhaul": "Conexión (Backhaul)",

            // Escaneo y LiDAR
            "spatial.scan.introTitle": "Cómo escanear su casa",
            "spatial.scan.introSubtitle": "Genere un plano tridimensional preciso en menos de 2 minutos utilizando los sensores del iPhone Pro.",
            "spatial.scan.tip1Title": "Buena Iluminación",
            "spatial.scan.tip1Desc": "Encienda las luces de las habitaciones para ayudar a los sensores ópticos y de profundidad.",
            "spatial.scan.tip2Title": "Abra las Puertas",
            "spatial.scan.tip2Desc": "Mantenga las puertas interiores abiertas para que el sistema identifique la transición entre habitaciones.",
            "spatial.scan.tip3Title": "Caminata Tranquila",
            "spatial.scan.tip3Desc": "Camine suavemente por el perímetro de cada habitación, apuntando la cámara a paredes, esquinas y suelo.",
            "spatial.scan.start": "Iniciar Escaneo",
            "spatial.scan.manualEditor": "Usar Editor 2D Manual",
            "spatial.scan.prepareTitle": "Preparar Escaneo",
            "spatial.lidar.unavailableTitle": "Sensor LiDAR No Disponible",
            "spatial.lidar.unavailableDesc": "Este dispositivo no cuenta con el sensor 3D exclusivo de los modelos iPhone y iPad Pro.\n\n¡Puede crear, organizar y dimensionar todas las habitaciones con nuestro Editor 2D manual!",
            "spatial.lidar.navTitle": "Escaneo Espacial",

            // Medición Activa
            "spatial.measuring.cancel": "Cancelar Prueba",
            "spatial.measuring.title": "Medición Activa",

            // Comparativa
            "spatial.comparison.step2Header": "Paso 2: Reposicionar y Re-probar",
            "spatial.comparison.step2Desc": "1. Mueva físicamente el router (ej: acérquelo al pasillo o elévelo) o encienda el repetidor/mesh.\n2. Espere 1 minuto a que la señal se estabilice.\n3. Vaya al mapa para realizar la nueva ronda de pruebas.",
            "spatial.comparison.goToMap": "Ir al Mapa para Medir",
            "spatial.comparison.alreadyMeasured": "Ya Realicé las Mediciones — Comparar",
            "spatial.comparison.discardBaseline": "Descartar Baseline",
            "spatial.comparison.generateWithCurrent": "Generar Comparativo con Lecturas Actuales",
            "spatial.comparison.discardAndNew": "Descartar e Iniciar Nuevo Baseline",
            "spatial.comparison.deltaQuality": "%@%% en la Calidad Media Medida",
            "spatial.comparison.saved": "Guardado en el Historial",
            "spatial.comparison.save": "Guardar en el Historial"
        ]
    ]
}
