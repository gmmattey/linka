// Generated from the user supplied Design Canvas export.
import html0 from './pages/home.html?raw';
import html1 from './pages/assist.html?raw';
import html2 from './pages/linka-plus.html?raw';
import html3 from './pages/servicos.html?raw';
import html4 from './pages/speedtest.html?raw';
import html5 from './pages/historico-icloud.html?raw';
import html6 from './pages/avaliacao-do-plano.html?raw';
import html7 from './pages/widget-atalhos.html?raw';
import html8 from './pages/suporte.html?raw';

export const prototypePages: Record<string, { title: string; description: string; style: string; html: string; examples?: Array<{ label: string; sub: string; q: string; tag: string; head: string; why: string; steps: string[] }> | null }> = {
  "/": {
  "title": "Linka — Speedtest e Assist para iPhone",
  "description": "Meça sua internet e acompanhe o histórico. O Linka+ ajuda a entender resultados e dados de rede disponíveis.",
  "style": "\n:root{--bg:#fff;--alt:#F5F5F7;--card:#fff;--ink:#102245;--text:#1D1D1F;--muted:#5F6C88;--border:color-mix(in oklch,#102245 12%,white);--warm:#E0701F;--warmink:#A34A00;--on:#fff;--display:ui-rounded,-apple-system,BlinkMacSystemFont,system-ui,sans-serif;--body:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;--mono:ui-monospace,'SF Mono',Menlo,Consolas,monospace}\nhtml{scroll-behavior:smooth}\nbody{margin:0;background:var(--bg);color:var(--text);font-family:var(--body);-webkit-font-smoothing:antialiased}\na{color:var(--ink);text-decoration:none}a:hover{color:var(--warmink)}\n@keyframes rise{from{opacity:0;transform:translateY(24px)}to{opacity:1;transform:none}}\n",
  "examples": null,
  "html": html0
},
  "/assist": {
  "title": "Assist — o concierge de rede do Linka",
  "description": "Pergunte por que a internet está lenta, cai ou trava. O Assist investiga com você.",
  "style": "\n:root{--bg:#fff;--alt:#F5F5F7;--card:#fff;--ink:#102245;--text:#1D1D1F;--muted:#5F6C88;--border:color-mix(in oklch,#102245 12%,white);--warm:#E0701F;--warmink:#A34A00;--on:#fff;--display:ui-rounded,-apple-system,BlinkMacSystemFont,system-ui,sans-serif;--body:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;--mono:ui-monospace,'SF Mono',Menlo,Consolas,monospace}\nhtml{scroll-behavior:smooth}body{margin:0;background:var(--bg);color:var(--text);font-family:var(--body);-webkit-font-smoothing:antialiased}\na{color:var(--ink);text-decoration:none}a:hover{color:var(--warmink)}\n@keyframes rise{from{opacity:0;transform:translateY(24px)}to{opacity:1;transform:none}}\n",
  "examples": [
    {
      "label": "Wi-Fi lento no quarto",
      "sub": "O sinal cai longe do roteador",
      "q": "O Wi-Fi do quarto está lento. É o meu plano?",
      "tag": "Conclusão",
      "head": "A diferença entre testes pode apontar para o Wi-Fi.",
      "why": "Se o teste perto do roteador entrega perto do contratado e no quarto cai muito, a diferença aponta para o sinal no caminho.",
      "steps": [
        "Teste ao lado do roteador e depois no quarto.",
        "Compare os dois resultados no Linka.",
        "Se a queda se repetir, considere reposicionar o roteador."
      ]
    },
    {
      "label": "Travando em chamadas",
      "sub": "Vídeo congela, áudio corta",
      "q": "Minhas chamadas de vídeo travam.",
      "tag": "Investigação",
      "head": "Para chamadas, latência e oscilação pesam mais que a velocidade.",
      "why": "O Assist pergunta quando acontece e quantos aparelhos usam a rede antes de concluir qualquer coisa.",
      "steps": [
        "Responda: Wi-Fi ou cabo? Em que horário trava?",
        "Rode um teste durante o problema.",
        "O Assist cruza as respostas com a latência medida."
      ]
    },
    {
      "label": "Oscilação na rede",
      "sub": "Compare medições recentes",
      "q": "Minha conexão está oscilando?",
      "tag": "Histórico",
      "head": "Compare medições em horários diferentes.",
      "why": "Uma medição descreve um momento. O histórico ajuda a ver quando a conexão mudou.",
      "steps": [
        "Abra o Histórico.",
        "Compare testes feitos em horários diferentes.",
        "Refaça o teste quando o problema aparecer."
      ]
    },
    {
      "label": "Detalhes do Wi-Fi",
      "sub": "Veja os sinais disponíveis",
      "q": "O que posso conferir no Wi-Fi?",
      "tag": "Wi-Fi",
      "head": "Confira os dados de Wi-Fi disponíveis.",
      "why": "O Linka mostra apenas os dados que o sistema permite consultar. Isso ajuda a escolher o próximo teste.",
      "steps": [
        "Abra os detalhes da conexão.",
        "Confira os dados disponíveis.",
        "Compare com uma nova medição."
      ]
    }
  ],
  "html": html1
},
  "/linka-plus": {
  "title": "Linka+ — Assist, histórico e Wi-Fi avançado",
  "description": "Conheça Assist, padrões no histórico e diagnóstico Wi-Fi avançado. Confira a oferta atual na App Store.",
  "style": "\n:root{--bg:#fff;--alt:#F5F5F7;--card:#fff;--ink:#102245;--text:#1D1D1F;--muted:#5F6C88;--border:color-mix(in oklch,#102245 12%,white);--warm:#E0701F;--warmink:#A34A00;--on:#fff;--display:ui-rounded,-apple-system,BlinkMacSystemFont,system-ui,sans-serif;--body:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;--mono:ui-monospace,'SF Mono',Menlo,Consolas,monospace}\nhtml{scroll-behavior:smooth}body{margin:0;background:var(--bg);color:var(--text);font-family:var(--body);-webkit-font-smoothing:antialiased}\na{color:var(--ink);text-decoration:none}a:hover{color:var(--warmink)}\n@keyframes rise{from{opacity:0;transform:translateY(24px)}to{opacity:1;transform:none}}\n",
  "examples": null,
  "html": html2
},
  "/servicos": {
  "title": "Serviços — Linka",
  "description": "Speedtest, histórico, Assist e recursos em preparação do Linka.",
  "style": "\n:root{--bg:#fff;--alt:#F5F5F7;--card:#fff;--ink:#102245;--text:#1D1D1F;--muted:#5F6C88;--border:color-mix(in oklch,#102245 12%,white);--warm:#E0701F;--warmink:#A34A00;--on:#fff;--display:ui-rounded,-apple-system,BlinkMacSystemFont,system-ui,sans-serif;--body:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;--mono:ui-monospace,'SF Mono',Menlo,Consolas,monospace}\nhtml{scroll-behavior:smooth}body{margin:0;background:var(--bg);color:var(--text);font-family:var(--body);-webkit-font-smoothing:antialiased}\na{color:var(--ink);text-decoration:none}a:hover{color:var(--warmink)}\n@keyframes rise{from{opacity:0;transform:translateY(24px)}to{opacity:1;transform:none}}\n",
  "examples": null,
  "html": html3
},
  "/speedtest": {
  "title": "SpeedTest grátis — Linka",
  "description": "Meça download, upload e latência em segundos, sem cadastro. Grátis no Linka.",
  "style": "\n:root{--bg:#fff;--alt:#F5F5F7;--card:#fff;--ink:#102245;--text:#1D1D1F;--muted:#5F6C88;--border:color-mix(in oklch,#102245 12%,white);--warm:#E0701F;--warmink:#A34A00;--on:#fff;--display:ui-rounded,-apple-system,BlinkMacSystemFont,system-ui,sans-serif;--body:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;--mono:ui-monospace,'SF Mono',Menlo,Consolas,monospace}\nhtml{scroll-behavior:smooth}body{margin:0;background:var(--bg);color:var(--text);font-family:var(--body);-webkit-font-smoothing:antialiased}\na{color:var(--ink);text-decoration:none}a:hover{color:var(--warmink)}\n@keyframes rise{from{opacity:0;transform:translateY(24px)}to{opacity:1;transform:none}}\n",
  "examples": null,
  "html": html4
},
  "/historico-icloud": {
  "title": "Histórico de medições — Linka",
  "description": "Acompanhe suas medições no aparelho. Sincronização pelo iCloud em preparação.",
  "style": "\n:root{--bg:#fff;--alt:#F5F5F7;--card:#fff;--ink:#102245;--text:#1D1D1F;--muted:#5F6C88;--border:color-mix(in oklch,#102245 12%,white);--warm:#E0701F;--warmink:#A34A00;--on:#fff;--display:ui-rounded,-apple-system,BlinkMacSystemFont,system-ui,sans-serif;--body:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;--mono:ui-monospace,'SF Mono',Menlo,Consolas,monospace}\nhtml{scroll-behavior:smooth}body{margin:0;background:var(--bg);color:var(--text);font-family:var(--body);-webkit-font-smoothing:antialiased}\na{color:var(--ink);text-decoration:none}a:hover{color:var(--warmink)}\n@keyframes rise{from{opacity:0;transform:translateY(24px)}to{opacity:1;transform:none}}\n",
  "examples": null,
  "html": html5
},
  "/avaliacao-do-plano": {
  "title": "Avaliação do plano em preparação — Linka",
  "description": "A comparação com o plano residencial está em preparação.",
  "style": "\n:root{--bg:#fff;--alt:#F5F5F7;--card:#fff;--ink:#102245;--text:#1D1D1F;--muted:#5F6C88;--border:color-mix(in oklch,#102245 12%,white);--warm:#E0701F;--warmink:#A34A00;--on:#fff;--display:ui-rounded,-apple-system,BlinkMacSystemFont,system-ui,sans-serif;--body:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;--mono:ui-monospace,'SF Mono',Menlo,Consolas,monospace}\nhtml{scroll-behavior:smooth}body{margin:0;background:var(--bg);color:var(--text);font-family:var(--body);-webkit-font-smoothing:antialiased}\na{color:var(--ink);text-decoration:none}a:hover{color:var(--warmink)}\n@keyframes rise{from{opacity:0;transform:translateY(24px)}to{opacity:1;transform:none}}\n",
  "examples": null,
  "html": html6
},
  "/widget-atalhos": {
  "title": "Atalhos — Linka",
  "description": "Importe dados avançados de Wi-Fi pelo Atalhos. Widget do resultado em preparação.",
  "style": "\n:root{--bg:#fff;--alt:#F5F5F7;--card:#fff;--ink:#102245;--text:#1D1D1F;--muted:#5F6C88;--border:color-mix(in oklch,#102245 12%,white);--warm:#E0701F;--warmink:#A34A00;--on:#fff;--display:ui-rounded,-apple-system,BlinkMacSystemFont,system-ui,sans-serif;--body:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;--mono:ui-monospace,'SF Mono',Menlo,Consolas,monospace}\nhtml{scroll-behavior:smooth}body{margin:0;background:var(--bg);color:var(--text);font-family:var(--body);-webkit-font-smoothing:antialiased}\na{color:var(--ink);text-decoration:none}a:hover{color:var(--warmink)}\n@keyframes rise{from{opacity:0;transform:translateY(24px)}to{opacity:1;transform:none}}\n",
  "examples": null,
  "html": html7
},
  "/suporte": {
  "title": "Suporte — Linka",
  "description": "Ajuda com o Linka. Fale com a Lk Software.",
  "style": "\n:root{--bg:#fff;--alt:#F5F5F7;--card:#fff;--ink:#102245;--text:#1D1D1F;--muted:#5F6C88;--border:color-mix(in oklch,#102245 12%,white);--warm:#E0701F;--warmink:#A34A00;--on:#fff;--display:ui-rounded,-apple-system,BlinkMacSystemFont,system-ui,sans-serif;--body:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;--mono:ui-monospace,'SF Mono',Menlo,Consolas,monospace}\nhtml{scroll-behavior:smooth}body{margin:0;background:var(--bg);color:var(--text);font-family:var(--body);-webkit-font-smoothing:antialiased}\na{color:var(--ink);text-decoration:none}a:hover{color:var(--warmink)}\n@keyframes rise{from{opacity:0;transform:translateY(24px)}to{opacity:1;transform:none}}\n",
  "examples": null,
  "html": html8
}
};
