# Linka 1.1.7 (61) — candidata TestFlight interno

- Enviada em 24/10/2026 pelo Xcode para o TestFlight interno; a App Store Connect aceitou o pacote e iniciou o processamento.
- Estende a promoção que libera os recursos do Linka Plus no iPhone e iPad até 1º de janeiro de 2027, sem incluir o Mac.
- Distribui anúncios nativos apenas nas áreas elegíveis do app gratuito: Home, Resultado, Minha Rede, Roteador, Status de serviços e Histórico a cada quatro resultados.
- Mantém a medição em primeiro plano: iniciar um teste remove anúncios carregados e não inicia novos slots durante a coleta.

# Linka 1.1.6 (60) — candidata TestFlight interno

- **Linka Genius com IA (Gemini 3.8 Flash):**
  - Diagnóstico especialista estilo Apple Genius com leitura de telemetria completa (bufferbloat, perda de pacotes, jitter, gateway e Wi-Fi).
  - Identificação de causa-raiz e geração de script técnico pronto para copiar e acionar o suporte da operadora.
- **Redesign Completo do Widget:**
  - Mini-anel de velocímetro refinado com tipografia tabular monoespaçada e botão de ação rápido.
  - Suporte completo a widgets de Tela Bloqueada (Lock Screen) e StandBy: Circular, Retangular e Inline.
- **Design System e Contraste WCAG AA:**
  - Alinhamento rigoroso de cores em todas as ferramentas e menus (eliminação de azuis de sistema e adoção de `brandAccentWarm`/`brandAccentWarmInk`).
  - Contraste validado em Light e Dark Mode conforme WCAG AA e áreas de toque mínimas de 44pt.
- **Universal Links Públicos Seguros:**
  - Suporte e resolução de rotas universais seguras no ecossistema Apple.

# Linka 1.1.6 (59) — candidata TestFlight interno

- **Minha Rede Fase 3 (Desempenho e Avaliação Factual):**
  - Avaliação automática e honesta da entrega do plano residencial com base nos testes recentes do usuário.
  - Guarda B1 de isolamento celular: apenas medições em Wi-Fi e cabo Ethernet locais são correlacionadas ao plano residencial; conexões celulares, hotspots pessoais e redes onerosas são rigorosamente ignoradas.
  - Respeito à vigência temporal do contrato (evitando comparar medições antigas com planos novos).
  - Diagnóstico claro de entrega com 4 estados calibrados e microcopy explicativa sem jargões ou falsas acusações contra operadoras.
- **Minha Rede Fase 2 (Perfil e Conexões):**
  - Perfil doméstico com cadastro de plano de internet, velocidades de download/upload nominais independentes e tecnologia residencial.
  - Mapeamento de conexões declaradas entre aparelhos e visualização consolidada em 4 seções nativas na MyNetworkView.
- Mantém Minha Rede 100% gratuita, local e offline em iPhone, iPad e Mac.

# Linka 1.1.6 (57) — disponível no TestFlight interno

- Avança a versão após a Apple informar que 1.1.5 está encerrada para novas submissões; a candidata 1.1.5 (56) não foi enviada ao TestFlight.

- Adiciona Minha Rede à candidata interna para cadastrar, editar e excluir equipamentos localmente, inclusive offline.
- Permite fotografar ou importar uma etiqueta para sugerir marca/modelo com leitura local e confirmação da pessoa.
- Ativa pesquisa de ficha técnica com IA no piloto interno, com fontes e confirmação antes de salvar. Uma consulta real com fonte oficial e o fluxo de revisão/salvamento no Mac foram verificados; a cobertura de modelos ainda está em avaliação.
- Mantém Minha Rede desativada no Release público. Enviada pelo Xcode em modo TestFlight Internal Only, processada e disponível ao grupo interno Projeto Adonis.

# Linka 1.1.5 (55)

- Remove o pedido de permissão de rastreamento (ATT), mantendo consentimento e anúncios não personalizados.
- Corrige a importação de dados do Wi-Fi avançado pelo Atalhos durante a promoção gratuita do Linka Plus.
- Mantém os recursos promocionais com anúncios não personalizados e preserva o acesso sem anúncios para assinaturas válidas.
