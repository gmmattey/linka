#!/bin/bash
set -euo pipefail
# Preparação local: python3 + PyYAML, plutil e XcodeGen no PATH.
# A geração é isolada; só versão/build são transplantados ao projeto WIP.
exec python3 - "$@" <<'PY'
import copy
from contextlib import contextmanager
import fcntl
import os
import stat
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

try:
    import yaml
except ImportError:
    sys.exit('Erro: python3 precisa de PyYAML para ler project.yml semanticamente.')

VERSION = r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)'
KEYS = ('MARKETING_VERSION', 'CURRENT_PROJECT_VERSION')


def require(condition, message):
    if not condition:
        raise ValueError(message)


class UniqueLoader(yaml.SafeLoader):
    pass


def unique_mapping(loader, node):
    result = {}
    for key, value in node.value:
        key = loader.construct_object(key)
        require(key not in result, 'Chave YAML duplicada: ' + str(key))
        result[key] = loader.construct_object(value)
    return result


UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping)


def version_pair(settings):
    pair = tuple(str(settings.get(k, '')) for k in KEYS)
    require(re.fullmatch(VERSION, pair[0]), 'MARKETING_VERSION deve ser X.Y.Z estrito.')
    require(re.fullmatch(r'[1-9][0-9]*', pair[1]), 'CURRENT_PROJECT_VERSION deve ser inteiro positivo.')
    return pair


def version_nodes(node, path=()):
    if isinstance(node, yaml.MappingNode):
        for key, value in node.value:
            current = path + (key.value,)
            if key.value in KEYS:
                yield current, value
            else:
                yield from version_nodes(value, current)


def pbx(data):
    return json.loads(subprocess.check_output(
        ['plutil', '-convert', 'json', '-o', '-', '--', '-'], input=data))


def configurations(objects, owner):
    return {objects[k]['name']: k for k in
            objects[owner['buildConfigurationList']]['buildConfigurations']}


def verify_project(project, targets, expected, mac_pairs):
    objects = project['objects']
    global_configs = configurations(objects, objects[project['rootObject']])
    for cid in global_configs.values():
        require(version_pair(objects[cid]['buildSettings']) == expected, 'Versão global PBX divergente.')
    actual = {o['name']: o for o in objects.values() if o.get('isa') == 'PBXNativeTarget'}
    for name, target in targets.items():
        require(name in actual, 'Target ausente no PBX: ' + name)
        configs = configurations(objects, actual[name])
        require(set(configs) == set(global_configs), 'Configurações divergentes: ' + name)
        for config, cid in configs.items():
            settings = dict(objects[global_configs[config]]['buildSettings'])
            settings.update(objects[cid]['buildSettings'])
            wanted = expected if target['platform'] == 'iOS' else mac_pairs[name]
            require(version_pair(settings) == wanted, 'Versão PBX divergente: ' + name + '/' + config)


@contextmanager
def release_lock(root):
    # Mesmo lock do Fastfile. Nunca remover o arquivo: outro processo pode
    # estar aguardando no mesmo inode. Contenção aborta, sem esperar.
    folder = root / 'build'
    folder.mkdir(exist_ok=True)
    with (folder / '.release.lock').open('a+b') as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('Outra preparação/release usa esta worktree; abortado sem alterar WIP.')
        try:
            yield
        finally:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)


def replace_if_unchanged(path, expected, replacement):
    # Editores que não usam flock são detectados por bytes antes de cada
    # replace. Ao detectar concorrência, abortar e preservar a edição externa.
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.' + path.name + '.', delete=False) as stream:
            temporary = Path(stream.name)
            os.fchmod(stream.fileno(), stat.S_IMODE(path.stat().st_mode))
            stream.write(replacement)
            stream.flush()
            os.fsync(stream.fileno())
        require(path.read_bytes() == expected,
                'Edição concorrente detectada em ' + str(path) + '; operação abortada.')
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def run():
    args = sys.argv[1:]
    if args in (['--help'], ['-h']):
        print('Uso: .agents/scripts/release.sh [patch|minor|major|X.Y.Z] — preparação local, sem upload.')
        return
    require(len(args) <= 1, 'Aceito no máximo um argumento.')
    bump = args[0] if args else 'patch'
    require(bump in ('patch', 'minor', 'major') or re.fullmatch(VERSION, bump), 'Argumento inválido.')
    root = Path.cwd()
    yml = root / 'aplicativo-ios/project.yml'
    project = root / 'aplicativo-ios/LinkaApp.xcodeproj/project.pbxproj'
    require(yml.is_file() and project.is_file(), 'Execute na raiz do checkout ios.')
    with release_lock(root):
        originals = {p: p.read_bytes() for p in (yml, project)}
        text = originals[yml].decode()
        spec = yaml.load(text, Loader=UniqueLoader)
        current = version_pair(spec['settings']['base'])
        targets = spec['targets']
        require({'LinkaApp', 'LinkaWidgetExtension', 'LinkaApp_macOS'} <= set(targets), 'Targets essenciais ausentes.')
        require(all(t.get('platform') in ('iOS', 'macOS') for t in targets.values()), 'Plataforma não suportada.')
        mac_pairs = {name: version_pair(t['settings']['base']) for name, t in targets.items()
                     if t['platform'] == 'macOS'}
        nodes = list(version_nodes(yaml.compose(text)))
        writable = []
        for path, node in nodes:
            if path[:1] == ('settings',):
                wanted = current
                writable.append(node)
            elif len(path) >= 4 and path[0] == 'targets' and path[2] == 'settings':
                name = path[1]
                wanted = current if targets[name]['platform'] == 'iOS' else mac_pairs[name]
                if targets[name]['platform'] == 'iOS':
                    writable.append(node)
            else:
                continue
            require(str(node.value) == wanted[KEYS.index(path[-1])], 'Override divergente: ' + '.'.join(path))
        verify_project(pbx(originals[project]), targets, current, mac_pairs)
        major, minor, patch = map(int, current[0].split('.'))
        version = {'patch': f'{major}.{minor}.{patch + 1}', 'minor': f'{major}.{minor + 1}.0',
                   'major': f'{major + 1}.0.0'}.get(bump, bump)
        updated = (version, str(int(current[1]) + 1))
        edits = [(node.start_mark.index, node.end_mark.index,
                  json.dumps(updated[KEYS.index(path[-1])]))
                 for path, node in nodes if node in writable]
        next_text = text
        for start, end, value in sorted(edits, reverse=True):
            next_text = next_text[:start] + value + next_text[end:]
        require(shutil.which('xcodegen'), 'XcodeGen não encontrado no PATH.')
        # Copiar em vez de symlinks: XcodeGen também escreve Info.plist/schemes.
        with tempfile.TemporaryDirectory(prefix='linka-release-') as directory:
            staging = Path(directory)
            shutil.copytree(root / 'aplicativo-ios', staging / 'aplicativo-ios',
                            ignore=shutil.ignore_patterns('.build', 'build', 'DerivedData', '.git', '.swiftpm'))
            # Ambos são sources explícitos do target de UI tests no project.yml.
            for filename in ('AppStoreScreenshotsUITests.swift', 'MyNetworkUITests.swift'):
                test_source = root / 'store/app-store/screenshots' / filename
                if test_source.exists():
                    dest = staging / test_source.relative_to(root)
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(test_source, dest)
            (staging / 'aplicativo-ios/project.yml').write_text(next_text)
            subprocess.run(['xcodegen', 'generate'], cwd=staging / 'aplicativo-ios', check=True)
            generated = (staging / 'aplicativo-ios/LinkaApp.xcodeproj/project.pbxproj').read_bytes()
            verify_project(pbx(generated), targets, updated, mac_pairs)
        # Preservar configurações/schemes WIP: não copiar o projeto gerado.
        original_project = pbx(originals[project])
        objects = original_project['objects']
        desired = copy.deepcopy(original_project)
        changed_ids = set(configurations(objects, objects[original_project['rootObject']]).values())
        for owner in objects.values():
            if owner.get('isa') == 'PBXNativeTarget' and targets[owner['name']]['platform'] == 'iOS':
                changed_ids.update(configurations(objects, owner).values())
        next_pbx = originals[project].decode()
        for cid in changed_ids:
            settings = objects[cid]['buildSettings']
            pattern = r'(?m)^\t\t' + cid + r' /\*[^\n]+\*/ = \{.*?\n\t\t\};'
            match = re.search(pattern, next_pbx, re.S)
            require(match, 'Bloco PBX não reconhecido: ' + cid)
            block = match.group()
            for key, value in zip(KEYS, updated):
                if key not in settings:
                    continue
                block, count = re.subn(r'(?m)^(\s*' + key + r' = )[^;]+;',
                                      lambda m: m[1] + value + ';', block)
                require(count == 1, 'Campo PBX ambíguo: ' + cid + '/' + key)
                desired['objects'][cid]['buildSettings'][key] = value
            next_pbx = next_pbx[:match.start()] + block + next_pbx[match.end():]
        require(pbx(next_pbx.encode()) == desired, 'Alteração PBX fora de versão/build.')
        verify_project(desired, targets, updated, mac_pairs)
        require(all(p.read_bytes() == data for p, data in originals.items()), 'WIP mudou durante a preparação; nada aplicado.')
        written = {}
        try:
            for path, data in ((yml, next_text.encode()), (project, next_pbx.encode())):
                written[path] = data
                replace_if_unchanged(path, originals[path], data)
            verify_project(pbx(project.read_bytes()), targets, updated, mac_pairs)
        except BaseException:
            for path, own_bytes in reversed(list(written.items())):
                try:
                    if path.read_bytes() == own_bytes:
                        replace_if_unchanged(path, own_bytes, originals[path])
                    elif path.read_bytes() != originals[path]:
                        print('Rollback preservou edição externa: ' + str(path), file=sys.stderr)
                except Exception as rollback_error:
                    print('Rollback não aplicado: ' + str(rollback_error), file=sys.stderr)
            raise
        print(f'Preparação local: {current[0]}/{current[1]} → {updated[0]}/{updated[1]}; Mac preservado.')
        print('Sem CI remoto, merge, tag, archive, upload ou publicação. Revise o diff antes de continuar.')


try:
    run()
except (Exception, KeyboardInterrupt) as error:
    sys.exit('Erro: ' + str(error) + ' — preparação não concluída.')
PY
