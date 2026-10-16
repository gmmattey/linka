import Foundation

/// Constrói prompts e payloads no padrão oficial da API Gemini para o Linka Genius.
public struct LinkaGeniusPromptBuilder: Sendable {

    /// Monta o request completo para o endpoint do Gemini com structured output JSON schema.
    public static func buildRequest(for context: LinkaGeniusContext) -> GeminiGenerateContentRequest {
        let systemPrompt = buildSystemInstruction(locale: context.locale)
        let userPrompt = buildUserMessage(for: context)

        let properties: [String: GeminiSchemaProperty] = [
            "symptom": GeminiSchemaProperty(
                type: "STRING",
                description: "Resumo humano e claro do sintoma observado."
            ),
            "cause": GeminiSchemaProperty(
                type: "STRING",
                description: "Causa raiz técnica mais provável fundamentada nos fatos observados."
            ),
            "actions": GeminiSchemaProperty(
                type: "ARRAY",
                description: "Lista de passos práticos imediatos em ordem de eficácia para o usuário.",
                items: GeminiSchemaItems(type: "STRING")
            ),
            "operatorScript": GeminiSchemaProperty(
                type: "STRING",
                description: "Texto pronto e formal para o usuário copiar e colar no suporte técnico da operadora."
            ),
            "needsRetest": GeminiSchemaProperty(
                type: "BOOLEAN",
                description: "Indica se um novo teste de rede é recomendado após aplicar as ações."
            )
        ]

        let schema = GeminiResponseSchema(
            type: "OBJECT",
            properties: properties,
            required: ["symptom", "cause", "actions", "operatorScript", "needsRetest"]
        )

        let config = GeminiGenerationConfig(
            responseMimeType: "application/json",
            responseSchema: schema,
            temperature: 0.2
        )

        return GeminiGenerateContentRequest(
            contents: [
                GeminiContent(text: userPrompt, role: "user")
            ],
            systemInstruction: GeminiContent(text: systemPrompt, role: "system"),
            generationConfig: config
        )
    }

    /// System prompt configurado com a persona "Apple Genius de Redes".
    public static func buildSystemInstruction(locale: String) -> String {
        let languageInstruction: String
        switch locale {
        case "en":
            languageInstruction = "You MUST write your entire response strictly in English (en)."
        case "es-419":
            languageInstruction = "DEBES redactar toda tu respuesta estrictamente en Español Latinoamericano (es-419)."
        default:
            languageInstruction = "Você DEVE escrever toda a sua resposta estritamente em Português do Brasil (pt-BR)."
        }

        return """
        Você é o Linka Genius, o especialista supremo em engenharia de redes domésticas do Linka, inspirado no padrão de atendimento Apple Genius Bar.
        Sua missão é traduzir telemetria de rede e inventário de equipamentos em orientações empáticas, ultraprecisas, descomplicadas e acionáveis para o usuário.

        DIRETRIZES FUNDAMENTAIS:
        1. IDIOMA: \(languageInstruction)
        2. INTEGRIDADE DOS FATOS (REGRA DE OURO):
           - NUNCA invente métricas, números ou equipamentos que não estejam na telemetria.
           - Se uma métrica estiver ausente (ex: latência sob carga não medida, ou plano não cadastrado), reconheça com naturalidade que aquele dado não foi coletado, sem supor valores.
        3. CORRELAÇÃO INTELIGENTE:
           - Wi-Fi 2.4 GHz vs 5 GHz: Se a velocidade medida estiver limitada (~40-60 Mbps) mas o plano for de 300+ Mbps e a frequência for 2.4 GHz, explique claramente que o gargalo físico é a banda de 2.4 GHz e oriente a migrar para 5 GHz ou cabo.
           - Bufferbloat: Se a latência sob carga (loaded latency) for muito superior à latência ociosa (+50ms a +500ms), explique que a fila do roteador está engasgando sob tráfego (gerando lag em reuniões Zoom/Meet e jogos online).
           - Perda de Pacotes (Packet Loss): Se houver perda > 1%, aponte instabilidade na rota, interferência de sinal ou defeito de cabo/provedor.
        4. SCRIPT PARA OPERADORA (`operatorScript`):
           - Crie uma mensagem técnica impecável, polida e direta para o usuário enviar no chat/WhatsApp ou ditar ao atendente de nível 2 da operadora.
           - Inclua as evidências factuais (ex: perda de pacotes, jitter, horário da medição, divergência em relação à velocidade contratada).
        5. FORMATO DE SAÍDA:
           - Você deve responder OBRIGATORIAMENTE em JSON válido contendo exatamente as chaves:
             - "symptom": síntese do que o usuário está sentindo na prática.
             - "cause": diagnóstico da causa raiz provável com termos claros.
             - "actions": array de strings com passos práticos imediatos (passo a passo).
             - "operatorScript": mensagem pronta para colar no suporte.
             - "needsRetest": booleano (true se as ações sugeridas exigem reteste de velocidade, false caso contrário).
        """
    }

    /// Mensagem do usuário contendo o relatório de dados reais e a dúvida.
    public static func buildUserMessage(for context: LinkaGeniusContext) -> String {
        let report = LinkaGeniusContextAssembler.buildFactualReport(for: context)
        return """
        \(report)

        ### Dúvida / Solicitação do Usuário:
        "\(context.question)"

        Analise os dados reais acima e gere o diagnóstico estruturado no formato JSON solicitado.
        """
    }
}
