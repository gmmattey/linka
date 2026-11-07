#!/usr/bin/env python3
"""Release do Linka para Mac (download direto hoje, Mac App Store amanhã).

Uso:
  release-mac.py status
  release-mac.py notes [--since REF]
  release-mac.py prepare [auto|patch|minor|major|build|X.Y.Z] [--since REF] [--dry-run]
  release-mac.py build
  release-mac.py publish --authorized [--public]

Versionamento (padrão Apple, o mesmo do DMG e da Mac App Store):
  - CFBundleShortVersionString = MARKETING_VERSION, SemVer X.Y.Z, só cresce.
  - CFBundleVersion = CURRENT_PROJECT_VERSION, inteiro que só cresce, sem repetir
    nem entre versões, porque a App Store Connect recusa build repetido.
  - Tag git `mac-vX.Y.Z` aponta o commit de cada versão publicada.

Notas: nascem dos commits (Conventional Commits) desde a última tag `mac-v*`.
Um commit (ou o corpo do squash do PR) pode trazer uma ou mais linhas
`Notas: texto para a pessoa`; cada uma vira um item e substitui o assunto.
`Notas: -` deixa o commit de fora.

Fonte única de verdade: project.yml (versão), RELEASE_NOTES.md (notas) e o
GitHub Release (binário). Nada de binário no Git.
"""
import argparse
import datetime
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / 'aplicativo-ios' / 'project.yml'
NOTES = ROOT / 'RELEASE_NOTES.md'
OUT = ROOT / 'build' / 'releases' / 'mac'
TAG_PREFIX = 'mac-v'
TARGET = 'LinkaApp_macOS'
SEMVER = re.compile(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')

# Caminhos que afetam o app do Mac: o que mexe só no iPhone fica fora das notas.
MAC_PATHS = re.compile(
    r'(UI/Mac/|MacMainView|macOS|-macOS|LinkaApp\.swift|Info-macOS|'
    r'aplicativo-ios/(LinkaEngine|NetworkCore|NetworkDiagnostics|NetworkInventory|NetworkProfiles|'
    r'NetworkInsights|NetworkOptimization|NetworkDNSBenchmark|NetworkConnectivityTriage|'
    r'MeasurementHistory|MeasurementHistoryCloudKit|AssistConsultation)/|'
    r'LinkaApp/Resources/.*Localizable|AppIcon|brand/icons)')
GROUPS = [('Novidades', {'feat'}), ('Melhorias', {'perf', 'refactor', 'style'}), ('Correções', {'fix'})]
IGNORED_TYPES = {'docs', 'chore', 'test', 'ci', 'build', 'revert'}


def run(*cmd, check=True, cwd=ROOT):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if check and r.returncode:
        sys.exit(f'Erro: {" ".join(cmd)}\n{r.stderr.strip()}')
    return r.stdout.strip()


def fail(msg):
    sys.exit(f'Erro: {msg}')


# ---------- versão ----------
def target_block(text):
    m = re.search(rf'^  {TARGET}:\n(?:(?:    .*|)\n)+?(?=^  \S|\Z)', text, re.M)
    if not m:
        fail(f'Target {TARGET} não encontrado em project.yml.')
    return m


def read_version():
    text = PROJECT.read_text()
    block = target_block(text).group(0)
    v = re.search(r'MARKETING_VERSION: "([^"]+)"', block)
    b = re.search(r'CURRENT_PROJECT_VERSION: "([^"]+)"', block)
    d = re.search(r'MACOSX_DEPLOYMENT_TARGET: "?([\d.]+)"?', text)
    if not (v and b and SEMVER.match(v.group(1)) and b.group(1).isdigit()):
        fail('Versão do Mac inválida em project.yml (use X.Y.Z e build inteiro).')
    return v.group(1), int(b.group(1)), (d.group(1) if d else '13.0')


def write_version(version, build):
    text = PROJECT.read_text()
    m = target_block(text)
    block = m.group(0)
    block = re.sub(r'(MARKETING_VERSION: )"[^"]+"', rf'\g<1>"{version}"', block, count=1)
    block = re.sub(r'(CURRENT_PROJECT_VERSION: )"[^"]+"', rf'\g<1>"{build}"', block, count=1)
    PROJECT.write_text(text[:m.start()] + block + text[m.end():])


def tags():
    run('git', 'fetch', '--tags', '--quiet', 'origin', check=False)
    out = run('git', 'tag', '--list', f'{TAG_PREFIX}*', '--sort=-v:refname')
    return [t for t in out.splitlines() if SEMVER.match(t[len(TAG_PREFIX):])]


def bump(version, kind):
    a, b, c = map(int, version.split('.'))
    return {'major': f'{a + 1}.0.0', 'minor': f'{a}.{b + 1}.0', 'patch': f'{a}.{b}.{c + 1}'}[kind]


# ---------- notas ----------
def commits(since):
    sep, end = '\x1f', '\x1e'
    raw = run('git', 'log', '--no-merges', f'--format=%H{sep}%s{sep}%b{end}', f'{since}..HEAD' if since else 'HEAD')
    for chunk in raw.split(end):
        chunk = chunk.strip('\n')
        if not chunk:
            continue
        sha, subject, body = (chunk.split(sep) + ['', ''])[:3]
        yield sha.strip(), subject.strip(), body


def touches_mac(sha):
    files = run('git', 'show', '--name-only', '--format=', sha).splitlines()
    return any(MAC_PATHS.search(f) for f in files)


def sentence(text):
    text = re.sub(r'\s*\(#\d+\)$', '', text.strip())
    text = text[:1].upper() + text[1:]
    return text if text.endswith(('.', '!', '?')) else text + '.'


def collect(since):
    groups = {name: [] for name, _ in GROUPS}
    breaking = False
    for sha, subject, body in commits(since):
        m = re.match(r'^(\w+)(?:\(([^)]*)\))?(!)?:\s*(.+)$', subject)
        if not m:
            continue
        ctype, scope, bang, desc = m.groups()
        overrides = [o.strip() for o in re.findall(r'^Notas:\s*(.+)$', body, re.M)]
        if overrides == ['-']:
            continue
        if ctype in IGNORED_TYPES or (ctype not in {t for _, ts in GROUPS for t in ts}):
            continue
        if scope not in ('macos', 'mac') and not touches_mac(sha):
            continue
        breaking |= bool(bang) or 'BREAKING CHANGE' in body
        for text in [sentence(o) for o in overrides] or [sentence(desc)]:
            for name, types in GROUPS:
                if ctype in types and text not in groups[name]:
                    groups[name].append(text)
    return groups, breaking


def render(version, build, groups):
    title = f'# Linka para Mac {version} ({build})'
    lines = [title, '']
    filled = False
    for name, _ in GROUPS:
        if groups[name]:
            filled = True
            lines += [f'**{name}**', ''] + [f'- {t}' for t in groups[name]] + ['']
    if not filled:
        lines += ['- Ajustes internos e de estabilidade.', '']
    return '\n'.join(lines).rstrip() + '\n'


def baseline(since):
    if since:
        return since
    ts = tags()
    return ts[0] if ts else None


def insert_notes(version, section):
    text = NOTES.read_text() if NOTES.exists() else ''
    head = f'# Linka para Mac {version} ('
    start = text.find(head)
    if start != -1:
        nxt = text.find('\n# ', start + 1)
        text = text[:start] + (text[nxt + 1:] if nxt != -1 else '')
    NOTES.write_text(section + '\n' + text.lstrip('\n'))


def section_of(version):
    text = NOTES.read_text()
    start = text.find(f'# Linka para Mac {version} (')
    if start == -1:
        fail(f'RELEASE_NOTES.md não tem a seção do Mac {version}. Rode prepare.')
    nxt = text.find('\n# ', start + 1)
    return text[start:nxt if nxt != -1 else None].strip() + '\n'


# ---------- comandos ----------
def cmd_status(_):
    v, b, d = read_version()
    ts = tags()
    print(f'Mac em project.yml: {v} ({b}), macOS mínimo {d}')
    print(f'Última tag publicada: {ts[0] if ts else "nenhuma"}')


def cmd_notes(a):
    v, b, _ = read_version()
    groups, _ = collect(baseline(a.since))
    print(render(v, b, groups))


def cmd_prepare(a):
    v, b, _ = read_version()
    base = baseline(a.since)
    if base is None and a.kind in ('auto', 'patch', 'minor', 'major'):
        print('Aviso: sem tag mac-v* anterior; notas usarão todo o histórico. Use --since REF para limitar.')
    groups, breaking = collect(base)
    kind = a.kind
    if kind == 'auto':
        kind = 'major' if breaking else 'minor' if groups['Novidades'] else 'patch'
    if kind == 'build':
        nv = v
        if f'{TAG_PREFIX}{nv}' in tags():
            fail(f'{nv} já foi publicada; suba a versão (patch, minor ou major).')
    elif SEMVER.match(kind):
        nv = kind
    else:
        nv = bump(v, kind)
    published = [t[len(TAG_PREFIX):] for t in tags()]
    key = lambda s: tuple(map(int, s.split('.')))
    if published and key(nv) <= key(published[0]):
        fail(f'{nv} não é maior que a última publicada ({published[0]}).')
    if key(nv) < key(v):
        fail(f'{nv} é menor que a versão atual ({v}).')
    nb = b + 1
    section = render(nv, nb, groups)
    print(f'Mac: {v} ({b}) → {nv} ({nb})  [{kind}]\n')
    print(section)
    if a.dry_run:
        print('Modo seco: nada foi alterado.')
        return
    if run('git', 'status', '--porcelain', '--', str(PROJECT), str(NOTES)):
        fail('project.yml ou RELEASE_NOTES.md têm mudanças não commitadas; commite antes.')
    write_version(nv, nb)
    insert_notes(nv, section)
    run('xcodegen', 'generate', cwd=ROOT / 'aplicativo-ios')
    print('Atualizados: project.yml, projeto Xcode e RELEASE_NOTES.md. Revise o texto, '
          'commite e faça merge antes de rodar build.')


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def release_dir(v, b):
    return OUT / f'{v}-{b}'


def cmd_build(_):
    v, b, minos = read_version()
    if run('git', 'status', '--porcelain', '--untracked-files=no'):
        fail('árvore com mudanças não commitadas; a build precisa de um commit limpo.')
    section_of(v)
    subprocess.run([str(ROOT / '.agents/scripts/build-mac-direct.sh')], check=True)
    src = ROOT / 'build' / 'macos-direct.noindex' / f'Linka-{v}-{b}.dmg'
    if not src.exists():
        fail(f'DMG não encontrado: {src}')
    dest = release_dir(v, b)
    dest.mkdir(parents=True, exist_ok=True)
    dmg = dest / src.name
    dmg.write_bytes(src.read_bytes())
    digest = sha256(dmg)
    (dest / 'SHA256SUMS').write_text(f'{digest}  {dmg.name}\n')
    manifest = {
        'product': 'Linka para Mac', 'bundleVersion': v, 'build': b, 'minimumSystemVersion': minos,
        'file': dmg.name, 'sha256': digest, 'size': dmg.stat().st_size,
        'commit': run('git', 'rev-parse', 'HEAD'),
        'date': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        'tag': f'{TAG_PREFIX}{v}',
    }
    (dest / 'latest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
    (dest / 'NOTES.md').write_text(section_of(v))
    print(f'==> Pronto em {dest}')


def cmd_publish(a):
    if not a.authorized:
        fail('publicar exige --authorized (decisão do Luiz). Nada foi enviado.')
    v, b, _ = read_version()
    dest = release_dir(v, b)
    if not (dest / 'latest.json').exists():
        fail(f'rode build antes: {dest} não existe.')
    manifest = json.loads((dest / 'latest.json').read_text())
    head = run('git', 'rev-parse', 'HEAD')
    if manifest['commit'] != head:
        fail('HEAD mudou desde a build; gere a build de novo.')
    run('git', 'fetch', 'origin', 'main', '-q')
    if run('git', 'branch', '-r', '--contains', head, '--list', 'origin/main') == '':
        fail('o commit da build ainda não está em origin/main.')
    tag = f'{TAG_PREFIX}{v}'
    if tag in tags():
        fail(f'a tag {tag} já existe.')
    cmd = ['gh', 'release', 'create', tag, str(dest / manifest['file']), str(dest / 'SHA256SUMS'),
           str(dest / 'latest.json'), '--target', head, '--title', f'Linka para Mac {v} ({b})',
           '--notes-file', str(dest / 'NOTES.md')]
    cmd += ['--latest'] if a.public else ['--draft']
    print(run(*cmd))
    print('Publicado como ' + ('versão pública.' if a.public else 'rascunho; confira e publique no GitHub.'))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    s = p.add_subparsers(dest='cmd', required=True)
    s.add_parser('status').set_defaults(fn=cmd_status)
    n = s.add_parser('notes'); n.add_argument('--since'); n.set_defaults(fn=cmd_notes)
    pr = s.add_parser('prepare'); pr.add_argument('kind', nargs='?', default='auto')
    pr.add_argument('--since'); pr.add_argument('--dry-run', action='store_true'); pr.set_defaults(fn=cmd_prepare)
    s.add_parser('build').set_defaults(fn=cmd_build)
    pu = s.add_parser('publish'); pu.add_argument('--authorized', action='store_true')
    pu.add_argument('--public', action='store_true'); pu.set_defaults(fn=cmd_publish)
    a = p.parse_args()
    if a.cmd == 'prepare' and not (a.kind in ('auto', 'patch', 'minor', 'major', 'build') or SEMVER.match(a.kind)):
        fail('tipo inválido: use auto, patch, minor, major, build ou X.Y.Z.')
    a.fn(a)


if __name__ == '__main__':
    main()
