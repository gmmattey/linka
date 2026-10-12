"""Import the supplied Design Canvas export into static HTML fragments for the site.

Usage: python scripts/import-prototype.py path/to/prototype.zip
"""

import json
import re
import subprocess
import sys
import zipfile
from pathlib import Path

from bs4 import BeautifulSoup, NavigableString


ROOT = Path(__file__).resolve().parents[1]
ROUTES = {
    "Linka Site.dc.html": "/",
    "Assist.dc.html": "/assist",
    "Linka Plus.dc.html": "/linka-plus",
    "Servicos.dc.html": "/servicos",
    "SpeedTest.dc.html": "/speedtest",
    "Historico e iCloud.dc.html": "/historico-icloud",
    "Avaliacao do Plano.dc.html": "/avaliacao-do-plano",
    "Widget e Atalhos.dc.html": "/widget-atalhos",
    "Privacidade.dc.html": "/privacidade",
    "Termos de Uso.dc.html": "/termos",
    "Suporte.dc.html": "/suporte",
}

# The export includes concepts that are still internal. Keep its layout while
# describing the public app and clearly labeling previews.
COPY = {
    "/": {
        "Abra o painel do seu roteador direto no app, pelo WebView.": "Abra o painel do seu roteador no próprio app.",
        "Sua casa, mapeada.": "Minha Rede em preparação.",
        "R$ 34,90 por ano. Uma assinatura, iPhone, iPad e Mac.": "Preço de tabela: R$ 34,90/ano. Confira a oferta atual na App Store.",
        "Plano, equipamentos e conexões da casa.": "Cadastro de equipamentos em preparação.",
        "A entrega frente ao contratado, sem acusar a operadora.": "Comparação com o plano em preparação.",
        "Fotografe a etiqueta do roteador e confirme o modelo.": "Leitura de etiqueta em preparação.",
        "Seu último resultado na tela inicial e nas rotinas.": "Integração com Atalhos para dados de Wi-Fi.",
        "Baixe o Linka, faça o primeiro teste grátis e assine o Linka+ quando quiser ir além.": "Baixe o Linka e faça o primeiro teste grátis. Confira a oferta atual do Linka+ na App Store.",
    },
    "/assist": {
        "Speedtests dão o número. O Assist dá a explicação.": "Speedtests dão o número. O Assist ajuda a entender.",
        "Comece por um problema comum ou escreva o seu.": "Comece com uma pergunta sobre sua conexão.",
        "A pergunta aberta está sempre disponível. As jornadas são atalhos.": "Estes exemplos mostram como o Assist pode ajudar a interpretar uma medição.",
        "Quatro etapas. Nenhuma adivinhação.": "Da medição à orientação.",
        "Pergunta aberta sempre acessível, com quatro jornadas guiadas como atalho.": "Abra o Assist pelo resultado ou pela área de diagnóstico.",
        'Perguntas progressivas com opções, "não sei", voltar e texto livre.': "O Assist usa os dados disponíveis e pede contexto quando precisa.",
        "De uma oportunidade de melhoria ao Assist, e de volta a um novo teste.": "Depois da orientação, refaça o teste para comparar.",
        "Equipamento, plano e medição, quando pertinentes.": "Medição e dados de rede disponíveis, quando pertinentes.",
        "Plano, preço e topologia ficam no seu aparelho. Contexto só segue ao Assist com a sua autorização.": "O Assist usa os dados necessários para responder à pergunta. Consulte a Política de Privacidade para detalhes.",
    },
    "/linka-plus": {
        "Sua rede inteira, entendida.": "Mais contexto sobre sua conexão.",
        "Cerca de R$ 2,91 por mês": "Confira a oferta atual na App Store",
        "Assine uma vez. Vale em todos os seus aparelhos.": "Uma assinatura vale nos aparelhos compatíveis.",
        "Meça, pergunte ao Assist e acompanhe pelo widget.": "Meça, consulte o Assist e acompanhe o histórico.",
        "A mesma conta de rede em uma tela maior.": "Consulte medições e detalhes da conexão.",
        "Cadastre equipamentos e revise fichas técnicas no desktop.": "Use os recursos disponíveis para Mac.",
        "Linka+ por R$ 34,90 ao ano.": "Conheça o Linka+.",
        "Baixe o app, faça o teste grátis e assine quando quiser ir além.": "Baixe o app e confira a oferta atual do Linka+ na App Store.",
        "O plano anual custa R$ 34,90 por ano, cerca de R$ 2,91 por mês.": "O preço de tabela é R$ 34,90 por ano. A App Store mostra a oferta vigente antes da compra.",
    },
    "/servicos": {
        "Grátis · iCloud no Linka+": "Grátis · iCloud em preparação",
        "Suas medições, guardadas e sincronizadas.": "Suas medições ficam no aparelho. Sincronização em preparação.",
        "Linka+ Avaliação do plano": "Em preparação Avaliação do plano",
        "Linka+ Widget e Atalhos": "Linka+ Atalhos",
        "Sua conexão na tela inicial e nas rotinas.": "Dados de Wi-Fi no app Atalhos.",
        "R$ 34,90 por ano": "Preço na App Store",
    },
    "/historico-icloud": {
        "Sincronização em segundo plano entre seus aparelhos.": "Sincronização entre aparelhos em preparação.",
        "O histórico é grátis. A sincronização pelo iCloud é do Linka+.": "O histórico é grátis. A sincronização pelo iCloud está em preparação.",
        "Exclua medições quando quiser; a retenção é configurável.": "Consulte e apague medições no Histórico.",
    },
    "/avaliacao-do-plano": {
        "Avaliação do plano · Linka+": "Avaliação do plano · Em preparação",
        "Cadastre o plano e compare com os seus testes recentes, sem acusar a operadora.": "A comparação com o plano residencial está em preparação.",
        "Faça testes em Wi-Fi ou cabo, em horários diferentes.": "Medições em horários diferentes ajudam a acompanhar a conexão.",
        "Um diagnóstico de entrega em 4 estados calibrados.": "A avaliação de entrega ainda não está no app público.",
        "Entrega abaixo do esperado? Pergunte ao Assist.": "Enquanto isso, consulte seus resultados no Histórico.",
    },
    "/widget-atalhos": {
        "Widget e Atalhos · Linka+": "Atalhos · Linka+",
        "Sua conexão na tela inicial.": "Dados de Wi-Fi no Atalhos.",
        "Veja o último resultado sem abrir o app e conecte o Linka à sua rotina.": "Use o Atalhos para importar dados avançados de Wi-Fi quando disponíveis.",
        "Resumo do último resultado direto na tela inicial.": "Widget do último resultado em preparação.",
        "Integre o Linka às suas automações no app Atalhos.": "Importe dados de Wi-Fi pelo app Atalhos.",
        "O widget não guarda identificadores de Wi-Fi.": "O widget do resultado ainda está em preparação.",
        "Sem atualização periódica em segundo plano: só muda quando você mede.": "Os dados de Wi-Fi avançado dependem das permissões do sistema.",
        "captura: widget na tela inicial": "Widget em preparação",
    },
    "/suporte": {
        "giammattey.luiz@gmail.com": "suporte@linka.app",
        "O histórico, o plano e os equipamentos ficam no seu aparelho. Apague medições no Histórico ou remova o app. Para dados sincronizados pelo iCloud, apague-os também nos Ajustes do iCloud.": "As medições do Histórico ficam no aparelho. Apague medições pelo app ou remova o app para retirar os dados locais. Consulte a Política de Privacidade para saber mais.",
    },
}

META = {
    "/": ("Linka — Speedtest e Assist para iPhone", "Meça sua internet e acompanhe o histórico. O Linka+ ajuda a entender resultados e dados de rede disponíveis."),
    "/linka-plus": ("Linka+ — Assist, histórico e Wi-Fi avançado", "Conheça Assist, padrões no histórico e diagnóstico Wi-Fi avançado. Confira a oferta atual na App Store."),
    "/servicos": ("Serviços — Linka", "Speedtest, histórico, Assist e recursos em preparação do Linka."),
    "/historico-icloud": ("Histórico de medições — Linka", "Acompanhe suas medições no aparelho. Sincronização pelo iCloud em preparação."),
    "/avaliacao-do-plano": ("Avaliação do plano em preparação — Linka", "A comparação com o plano residencial está em preparação."),
    "/widget-atalhos": ("Atalhos — Linka", "Importe dados avançados de Wi-Fi pelo Atalhos. Widget do resultado em preparação."),
}


def values(source):
    script = re.search(r'<script type="text/x-dc"[^>]*>(.*?)</script>', source, re.S).group(1)
    runner = r"""
const vm = require('node:vm');
let source = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => source += chunk);
process.stdin.on('end', () => {
  const DCLogic = class { constructor() { this.props = { theme: 'light', storeUrl: 'https://apps.apple.com/br/app/linka-wi-fi-e-internet/id6808479321' }; } setState() {} };
  const context = vm.createContext({ DCLogic, console });
  vm.runInContext(source + '\nthis.instance = new Component();', context);
  process.stdout.write(JSON.stringify({ ...context.instance.renderVals(), __examples: context.instance.J || null }));
});
"""
    result = subprocess.run(["node", "-e", runner], input=script, text=True, encoding="utf-8", capture_output=True, check=True)
    return json.loads(result.stdout)


def css_style(value):
    if isinstance(value, str):
        return value
    if not isinstance(value, dict):
        return ""
    unitless = {"fontWeight", "lineHeight", "opacity", "zIndex", "flex", "order"}
    return ";".join(
        re.sub(r"[A-Z]", lambda match: "-" + match.group().lower(), key)
        + ":" + str(val) + ("px" if isinstance(val, (int, float)) and key not in unitless and val != 0 else "")
        for key, val in value.items()
    )


def resolve(expr, scope):
    expr = expr.strip()
    if expr in ("true", "false"):
        return expr == "true"
    value = scope
    for part in expr.split("."):
        if isinstance(value, dict):
            value = value.get(part)
        else:
            return None
    return value


def interpolate(text, scope, attr=None):
    def replace(match):
        value = resolve(match.group(1), scope)
        if attr == "style":
            value = css_style(value)
        return "" if value is None else str(value)
    return re.sub(r"{{\s*([^}]+?)\s*}}", replace, text)


def render_children(node, scope):
    for child in list(node.children):
        if isinstance(child, NavigableString):
            child.replace_with(interpolate(str(child), scope))
            continue
        if child.name == "sc-for":
            items = resolve(child.get("list", "").strip("{} "), scope) or []
            for index, item in enumerate(items):
                nested = dict(scope, **{child.get("as", "item"): item, "$index": index})
                clone = BeautifulSoup(str(child), "html.parser").find("sc-for")
                render_children(clone, nested)
                for rendered in list(clone.contents):
                    child.insert_before(rendered.extract())
            child.decompose()
            continue
        if child.name == "sc-if":
            condition = resolve(child.get("condition", child.get("when", "")).strip("{} "), scope)
            if not condition:
                child.decompose()
                continue
            render_children(child, scope)
            child.unwrap()
            continue
        for key, value in list(child.attrs.items()):
            if key == "onclick":
                if "f.toggle" in value:
                    child.attrs["data-faq"] = ""
                    child.attrs["aria-expanded"] = "false"
                elif "c.pick" in value:
                    child.attrs["data-assist-index"] = str(scope.get("$index", 0))
                    child.attrs["aria-pressed"] = "true" if scope.get("$index", 0) == 0 else "false"
                del child.attrs[key]
            elif key.lower().startswith("on") or key.startswith("style-"):
                del child.attrs[key]
            elif isinstance(value, str):
                child.attrs[key] = interpolate(value, scope, key)
        render_children(child, scope)


def render_root(node, scope):
    for key, value in list(node.attrs.items()):
        if isinstance(value, str):
            node.attrs[key] = interpolate(value, scope, key)
    render_children(node, scope)


def route_links(soup, store_url):
    for link in soup.find_all("a", href=True):
        href = link["href"]
        if href in ROUTES:
            link["href"] = ROUTES[href]
        elif href == "Teste de Velocidade.dc.html":
            if link.get_text(" ", strip=True).startswith("Testar"):
                link["href"] = store_url
                link.string = "Testar no app"
            else:
                link["href"] = "/speedtest"
    for image in soup.find_all("img", src=True):
        src = image["src"]
        if src.startswith(("assets/", "brand/")):
            image["src"] = "/prototype/" + src


def public_values(route, vals):
    if route == "/":
        vals["gallery"][4]["tier"] = "Em preparação"
        vals["plus"] = [
            {"t": "Assist", "d": "Ajuda a entender uma medição e os sinais disponíveis.", "href": "Assist.dc.html"},
            {"t": "Padrões no histórico", "d": "Acompanhe mudanças entre medições.", "href": "Historico e iCloud.dc.html"},
            {"t": "Wi-Fi avançado", "d": "Mais detalhes da rede quando o sistema permite.", "href": "Widget e Atalhos.dc.html"},
            {"t": "Sem anúncios", "d": "Remova a publicidade do app.", "href": "Linka Plus.dc.html"},
        ]
        vals["rows"][3].update(a="Histórico", b="Padrões no histórico (Linka+)")
        vals["rows"][2]["b"] = "Assist ajuda a interpretar (Linka+)"
        vals["rows"][4]["b"] = "Sem conta para medir"
        vals["rows"][5]["b"] = "iPhone, iPad e Mac compatível"
    elif route == "/assist":
        vals["__examples"][0]["head"] = "A diferença entre testes pode apontar para o Wi-Fi."
        vals["j"]["head"] = vals["__examples"][0]["head"]
        vals["__examples"][2].update(label="Oscilação na rede", sub="Compare medições recentes", q="Minha conexão está oscilando?", tag="Histórico", head="Compare medições em horários diferentes.", why="Uma medição descreve um momento. O histórico ajuda a ver quando a conexão mudou.", steps=["Abra o Histórico.", "Compare testes feitos em horários diferentes.", "Refaça o teste quando o problema aparecer."])
        vals["__examples"][3].update(label="Detalhes do Wi-Fi", sub="Veja os sinais disponíveis", q="O que posso conferir no Wi-Fi?", tag="Wi-Fi", head="Confira os dados de Wi-Fi disponíveis.", why="O Linka mostra apenas os dados que o sistema permite consultar. Isso ajuda a escolher o próximo teste.", steps=["Abra os detalhes da conexão.", "Confira os dados disponíveis.", "Compare com uma nova medição."])
        for index in (2, 3):
            vals["chips"][index]["label"] = vals["__examples"][index]["label"]
            vals["chips"][index]["sub"] = vals["__examples"][index]["sub"]
        vals["rows"][1]["b"] = "Perguntas sobre a medição e a rede"
        vals["rows"][2].update(a="Histórico", b="Ajuda a comparar medições")
        vals["rows"][3].update(a="Wi-Fi", b="Mostra dados disponíveis")
        vals["rows"][5]["b"] = "Sem conta para medir"
        vals["faq"][0]["a"] = "O Assist usa a medição e outros dados disponíveis para responder com mais contexto."
        vals["trust"][1]["t"] = "Consulte a Política de Privacidade para saber quais dados são usados."
    elif route == "/linka-plus":
        vals["perks"] = ["Assist para interpretar resultados", "Padrões no histórico", "Diagnóstico Wi-Fi avançado", "Sem anúncios", "iPhone, iPad e Mac compatível"]
        vals["features"] = [
            {"tag": "Linka+", "t": "Assist", "d": "Pergunte sobre a medição e receba orientação baseada nos dados disponíveis.", "href": "Assist.dc.html"},
            {"tag": "Linka+", "t": "Padrões no histórico", "d": "Acompanhe mudanças entre suas medições.", "href": "Historico e iCloud.dc.html"},
            {"tag": "Linka+", "t": "Wi-Fi avançado", "d": "Veja detalhes de Wi-Fi quando o sistema permite.", "href": "Widget e Atalhos.dc.html"},
            {"tag": "Linka+", "t": "Sem anúncios", "d": "Remova a publicidade do app.", "href": "#planos"},
        ]
        vals["rows"] = [row for row in vals["rows"] if not any(term in row["n"] for term in ("Minha Rede", "Avaliação do plano", "Etiqueta", "Widget", "iCloud"))]
        vals["rows"].insert(4, {"n": "Padrões no histórico", "f": "—", "fs": "color:var(--muted);opacity:.6"})
        vals["devices"][2]["t"] = "Disponível em Macs compatíveis; recursos podem variar."
        for device in vals["devices"]:
            device["shot"] = device["n"]
        vals["faq"][1]["a"] = "Speedtest, Histórico, diagnóstico do caminho e acesso ao painel do roteador. Confira a oferta atual do Linka+ na App Store."


def apply_copy(route, body):
    result = str(body)
    for old, new in COPY.get(route, {}).items():
        result = result.replace(old, new)
    return result


def main(zip_path):
    target = ROOT / "src" / "generated" / "prototypePages.ts"
    target.parent.mkdir(parents=True, exist_ok=True)
    html_dir = target.parent / "pages"
    html_dir.mkdir(exist_ok=True)
    public = ROOT / "public" / "prototype"
    public.mkdir(parents=True, exist_ok=True)
    pages = {}
    with zipfile.ZipFile(zip_path) as archive:
        for name in archive.namelist():
            if name.startswith(("assets/", "brand/")) and not name.endswith("/"):
                dest = public / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(archive.read(name))
        for name, route in ROUTES.items():
            if route in ("/privacidade", "/termos"):
                continue  # Keep the repository's existing published legal text.
            source = archive.read(name).decode("utf-8")
            vals = values(source)
            public_values(route, vals)
            soup = BeautifulSoup(source, "html.parser")
            helmet = soup.find("helmet")
            title = helmet.find("title").get_text(strip=True)
            description = helmet.find("meta", attrs={"name": "description"}).get("content", "")
            title, description = META.get(route, (title, description))
            style = helmet.find("style").get_text()
            body = soup.find("x-dc").find("div", recursive=False)
            render_root(body, vals)
            route_links(body, vals["storeUrl"])
            if route == "/":
                for link in body.find_all("a", href="/speedtest"):
                    if "navegador" in link.get_text():
                        link.string = "Testar no app ›"
                        link["href"] = vals["storeUrl"]
            if route == "/assist":
                example_heading = body.find(string=lambda t: t and "Exemplo — escolha uma jornada" in t)
                if example_heading:
                    grid = example_heading.find_parent("div").parent
                    grid.find_all("div", recursive=False)[1]["data-assist-card"] = ""
            pages[route] = {"title": title, "description": description, "style": style, "html": apply_copy(route, body), "examples": vals.get("__examples")}
    imports = []
    entries = []
    for index, (route, page) in enumerate(pages.items()):
        filename = "home" if route == "/" else route.lstrip("/")
        (html_dir / f"{filename}.html").write_text(page["html"] + "\n", encoding="utf-8")
        imports.append(f"import html{index} from './pages/{filename}.html?raw';")
        metadata = {key: value for key, value in page.items() if key != "html"}
        metadata["html"] = f"__HTML_{index}__"
        entry = json.dumps(metadata, ensure_ascii=False, indent=2).replace(f'"__HTML_{index}__"', f"html{index}")
        entries.append(f"  {json.dumps(route)}: {entry}")
    target.write_text(
        "// Generated from the user supplied Design Canvas export.\n"
        + "\n".join(imports)
        + "\n\nexport const prototypePages: Record<string, { title: string; description: string; style: string; html: string; examples?: Array<{ label: string; sub: string; q: string; tag: string; head: string; why: string; steps: string[] }> | null }> = {\n"
        + ",\n".join(entries)
        + "\n};\n",
        encoding="utf-8",
    )
    print(f"Imported {len(pages)} pages to {target}")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
