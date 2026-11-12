"""Grouped native root-magazine unload controls with exact ammo identity receipts."""
import json
import os
import zipfile
from .. import preparation_process
from pathlib import Path
import re
import shutil
import zlib

from ..mod_selection import lua_sources
from .tv_controls import MODS

CASES = ('direct', 'bulk')
EQUIP_CASES = ('equip-edit',)
EQUIP_NATIVE_CRC = {
    'media/lua/shared/TimedActions/ISEquipWeaponAction.lua': 3528902511,
    'media/lua/shared/TimedActions/ISReadABook.lua': 916973327,
    'media/lua/client/TimedActions/ISInventoryTransferAction.lua': 3908838083,
}
NAMES = ('front', 'target', 'cancelled', 'tail', 'unrelated', 'gun-tail')
LOADS = dict(front=5, target=3, cancelled=4, tail=2, unrelated=6, **{'gun-tail': 2})
AMMO = 'Base.Bullets9mm'
OTHER = 'Base.ShotgunShells'
PREFIX = '[MAGAZINE_UNLOAD] '
PRODUCERS = dict(direct='native ISInventoryPaneContextMenu.onUnloadBulletsFromMagazine',
                 bulk='BulkFirearms.unloadEntries + queueUnload')
NATIVE_CRC = {
    'media/lua/shared/TimedActions/ISUnloadBulletsFromMagazine.lua': 641621167,
    'media/lua/shared/TimedActions/ISUnloadBulletsFromFirearm.lua': 3496344359,
    'media/lua/shared/TimedActions/ISEquipWeaponAction.lua': 3528902511,
    'media/lua/shared/TimedActions/ISReloadWeaponAction.lua': 547021931,
    'media/lua/client/ISUI/ISInventoryPaneContextMenu.lua': 2574700613,
}
SELECTED_CRC = {'CleanUI': ('ISInventoryPaneContextMenu.lua', 2066944516),
                'P4TidyUpMeister': ('P4TidyUpMeister.lua', 945150908),
                'WildernessProgressionArcheryNexusCompanion': ('WPANC_BowReload.lua', 1505744173)}


def definitions():
    effects = {case: dict(effectsVerified=True, serverAuthorityVerified=True, tailCompleted=True) for case in CASES}
    edits = {case: dict(effectsVerified=True, pendingEditsVerified=True) for case in CASES}
    return {'magazine-unload': dict(status='ready', clients=1, default_mods=list(MODS),
        scenario_actions={'native-magazine-unload': dict(mods=list(MODS),
            checks={'success-queued': effects, 'server-authority': effects, 'cancel-waiting': edits, 'move-independent': edits},
            toolkit_only=['cancel-waiting', 'move-independent'],
            scope='Grouped full selected pack fresh SP/menu Host direct native inventory callback and public BulkFirearms unloadEntries/queueUnload controls. Plain exact root magazines and alternating Base.Shotgun A,B,A,B unloads submitted loaded/unheld behind the real front, native own-equip hand protection and final P4 hand restoration, exact unchanged live chamber/spent/magazine fields, classified vanilla empty-start jobDelta NaN with final native finite0 reset. ShotgunShells and Bullets9mm each have exact currentUses output accounting. Pack-captured callbacks including pinned non-bow WPANC delegations are preserved. Natural -1-duration native animation/server loops, untouched native callbacks and only the exact owned bulk start guard. Queue-on cancels a waiting loaded magazine and moves independent tail before target while front is active. Separately requested same-front repeats constructed while loaded must enter native start at zero, finish native perform without extra debit/output, and preserve the independent tail; read-only Lifecycle receipts identify actual native episodes (SP complete, Host perform plus server authority). Native starts and partial loaded-count progress for nonempty commands, final canonical magazine identities, authoritative new ammo IDs and per-output uses1, exact loose-plus-loaded round conservation, unchanged baseline/unrelated inputs and independent tail. Loose round units use getCurrentUses; getCount is factory metadata and is never multiplied into output credit. No active edits, recovery, group fetch, future output capacity authority or physical-input coverage.'),
            'native-equip-edit': dict(mods=list(MODS),
                checks={'success-queued': {'equip-edit': dict(effectsVerified=True, tailCompleted=True)},
                        'server-authority': {'equip-edit': dict(serverAuthorityVerified=True)},
                        'cancel-waiting': {'equip-edit': dict(pendingEditsVerified=True)},
                        'move-independent': {'equip-edit': dict(pendingEditsVerified=True)},
                        'move-dependent': {'equip-edit': dict(pendingProtectionVerified=True)}},
                toolkit_only=['cancel-waiting', 'move-independent', 'move-dependent'],
                scope='Grouped full selected pack native explicit pending Equip actions: SP reorder-two/reorder-three/cancel, inert worn backpack, unavailable nested input, container-transfer coupling and Hammer Script+Attributes component eligibility protected; menu Host new rights remain unavailable. Unchanged native source-order queue-off controls, paid native front/tail readers, canonical final hands and full inventory multiset/count, original native delegates/durations, attested source-owned transfer stop guard, native lifecycle receipts and P4 quiescence. Programmatic constructors; no active edit, physical input or future capacity credit.')},
        cases=[dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'], modes=['native', 'toolkit'], languages=['EN']) for case in (*CASES, *EQUIP_CASES)])}


def validate(selection):
    workload = selection.get('options', {}).get('equip_workload', False)
    if type(workload) is not bool or workload and selection.get('cases') != list(EQUIP_CASES):
        raise ValueError('equip_workload requires boolean true with equip-edit alone')
    if workload and selection.get('kind') != 'sp':
        raise ValueError('The Equip UI work profile qualifies the SP permission slice only')
    baseline = selection.get('options', {}).get('equip_workload_baseline', False)
    if type(baseline) is not bool or baseline and not workload:
        raise ValueError('equip_workload_baseline requires the explicit work profile')
    cases = selection.get('cases')
    ordered = type(cases) is list and bool(cases) and (cases == list(EQUIP_CASES) or cases == [case for case in CASES if case in cases])
    if (not ordered or selection.get('kind') not in ('sp', 'mp')
        or selection.get('mode') not in ('native', 'toolkit') or selection.get('languages') != ['EN']
        or type(selection.get('clients')) is not int or selection['clients'] != 1 or selection.get('mods') != MODS
        or selection.get('options', {}).get('world_template')
        or selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('Magazine unload requires an ordered unload subset or equip-edit alone, fresh full-selected-pack SP/menu Host and one EN client')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / 'magazine-unload').rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueEnergyPlacement.lua',
            *sorted((root / 'magazine-unload/java').glob('*.java')), *verifier_sources(project, selection)]


def audit_native(game, selection=None):
    result = {}
    selected = EQUIP_NATIVE_CRC if selection and selection.get('cases') == list(EQUIP_CASES) else NATIVE_CRC
    for relative, expected in selected.items():
        actual = zlib.crc32((Path(game) / relative).read_bytes())
        if actual != expected: raise ValueError('Magazine native source audit requires review: ' + relative)
        result[relative] = actual
    return result


def audit_selected(locations):
    result = {}
    for identifier, (name, expected) in SELECTED_CRC.items():
        files = [path for path in lua_sources(Path(locations[identifier])) if path.name == name]
        if len(files) != 1 or zlib.crc32(files[0].read_bytes()) != expected:
            raise ValueError('Magazine selected producer audit requires review: ' + identifier)
        result[identifier] = expected
    return result


def _reviewed_equip_pins(text, baseline=False):
    """Read only the fixture's closed literal table and explicit baseline branch."""
    code = re.sub(r'(?m)^\s*--[^\n]*', '', text)
    tables = re.findall(r'(?ms)^local sources=\{(.*?)^\}', code)
    loops = re.findall(r'(?ms)^ for _,source in ipairs\(sources\)do\n(.*?)^ end\n(?= assert\(publicCurrent\(\))', code)
    if len(tables) != 1 or len(loops) != 1 or len(re.findall(r'\bsources\b', code)) != 2:
        raise ValueError('Equip reviewed-source fixture layout requires review: literal sources/table loop')
    def compact(value):
        # Whitespace inside a literal belongs to its filename/message.
        return ''.join(part if index % 2 else re.sub(r'\s+', '', part)
                       for index, part in enumerate(re.split(r"('[^'\\\r\n]*')", value)))
    name = r'[A-Za-z][A-Za-z0-9_]*\.lua'
    entry = r"\{'(client|shared|server)','(" + name + r")',([0-9]+)\},"
    table = compact(tables[0])
    rows = re.findall(entry, table)
    if not rows or re.sub(entry, '', table) or len({row[1] for row in rows}) != len(rows):
        raise ValueError('Equip reviewed-source fixture requires unique literal source pins')
    prefix = ("localadler=source[3]ifconfig.optionsandconfig.options.equip_workload_baseline==truethen"
              "assert(config.options.equip_workload==true,'baseline callback proof requires work profile')")
    suffix = ("endassert(matches('media/lua/'..source[1]..'/PZSurvivorToolkit/'..source[2],adler,"
              "'PZSurvivorToolkit',true)==true,'callback observation source bytes changed '..source[2])")
    loop = compact(loops[0])
    if not loop.startswith(prefix) or not loop.endswith(suffix):
        raise ValueError('Equip reviewed-source fixture layout requires review: exact baseline/source check')
    choices = loop[len(prefix):-len(suffix)]
    choice = r"source\[2\]=='(" + name + r")'thenadler=([0-9]+)"
    if not re.fullmatch('if' + choice + '(?:elseif' + choice + ')*end', choices):
        raise ValueError('Equip reviewed-source baseline requires explicit literal overrides')
    overrides = re.findall(choice, choices)
    names = {row[1] for row in rows}
    if (len({row[0] for row in overrides}) != len(overrides) or any(row[0] not in names for row in overrides)
            or len(re.findall(r'\badler\s*=', code)) != 1 + len(overrides)
            or any(not 0 <= int(value) <= 0xffffffff for value in [row[2] for row in rows] + [row[1] for row in overrides])):
        raise ValueError('Equip reviewed-source pins/overrides require review')
    selected = dict(overrides) if baseline else {}
    return {side + '/PZSurvivorToolkit/' + filename: int(selected.get(filename, pin)) for side, filename, pin in rows}


def _source_adler(data):
    """BufferedReader UTF8 text -> UTF16 units, one LF per CR/LF/CRLF record.

    Preserve BOM and Unicode separators as data. Reject malformed UTF8 before
    launch rather than guessing the JVM decoder's replacement grouping.
    """
    try: text = data.decode('utf-8')
    except UnicodeDecodeError as error: raise ValueError('Equip reviewed source is not valid UTF8') from error
    records = re.split(r'\r\n|\r|\n', text) if text else []
    if text.endswith(('\r', '\n')): records.pop()
    a, b = 1, 0
    for record in records:
        units = (record + '\n').encode('utf-16-le')
        for index in range(0, len(units), 2):
            a = (a + units[index] + 256 * units[index + 1]) % 65521
            b = (b + a) % 65521
    return b * 65536 + a


def audit_equip_sources(project, selection, locations):
    """Reject stale fixture pins against effective candidate Lua before staging."""
    if selection.get('cases') != list(EQUIP_CASES): return {}
    options = selection.get('options', {})
    baseline = options.get('equip_workload_baseline', False)
    if type(baseline) is not bool or baseline and options.get('equip_workload') is not True:
        raise ValueError('Equip reviewed-source baseline requires the explicit work profile')
    fixture = Path(project) / 'tests/native_queue/magazine-unload/client/QueueEquipCallbackObservation.lua'
    try:
        pins = _reviewed_equip_pins(fixture.read_text(encoding='utf-8'), baseline)
        if 'PZSurvivorToolkit' not in locations: raise ValueError('Equip reviewed-source preflight needs the candidate Toolkit location')
        candidates = lua_sources(Path(locations['PZSurvivorToolkit']))
        result = {}
        for relative, expected in pins.items():
            files = [path for path in candidates if path.as_posix().endswith('/media/lua/' + relative)]
            if len(files) != 1: raise ValueError('Equip reviewed-source preflight needs one effective Toolkit source: ' + relative)
            actual = _source_adler(files[0].read_bytes())
            if actual != expected:
                raise ValueError('Equip reviewed-source preflight requires review: ' + relative
                                 + ' expected ' + str(expected) + ', candidate ' + str(actual))
            result[relative] = actual
        return result
    except OSError as error:
        raise ValueError('Equip reviewed-source preflight cannot read candidate inputs: ' + str(error)) from error


def _work_probe(project, output, game, jdk, locations, runtime):
    source = Path(project) / 'tests/native_queue/magazine-unload/java/EquipWorkProbe.java'
    classes = Path(output) / 'equip-work-probe/classes'; classes.mkdir(parents=True)
    patches = Path(locations['PZToolkitJavaPatches']) / '42/media/java/PZToolkitJavaPatches.jar'
    classpath = os.pathsep.join(map(str, [Path(game) / 'projectzomboid.jar', Path(game) / 'ZombieBuddy.jar', patches]))
    preparation_process.run([str(Path(jdk) / 'bin/javac'), '--release', '25', '-cp', classpath, '-d', str(classes), str(source)],
                            check=True, capture_output=True, text=True, timeout=60)
    compiled = sorted(classes.rglob('*.class'))
    if not compiled: raise ValueError('Equip work probe compilation produced no classes')
    jar = classes.parent / 'EquipWorkProbe.jar'
    with zipfile.ZipFile(jar, 'x', zipfile.ZIP_DEFLATED) as archive:
        for path in compiled: archive.write(path, path.relative_to(classes).as_posix())
    runtime.setdefault('fixture', {}).setdefault('mods', []).append('EquipWorkProbe')
    for role in runtime['roles'].values():
        layer = Path(role['cache']) / 'mods/EquipWorkProbe/42'
        (layer / 'media/java').mkdir(parents=True)
        (layer / 'mod.info').write_text('name=Disposable queue work probe\nid=EquipWorkProbe\nversionMin=42.21\nrequire=\\ZombieBuddy\njavaPkgName=net.alexredby.equipworkprobe\njavaJarFile=media/java/EquipWorkProbe.jar\n')
        shutil.copy2(jar, layer / 'media/java/EquipWorkProbe.jar')


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    reviewed = audit_equip_sources(project, selection, locations)
    audit = audit_native(game, selection); audit.update(audit_selected(locations))
    root = Path(project) / 'tests/native_queue'
    if selection.get('options', {}).get('equip_workload'):
        _work_probe(project, output, game, jdk, locations, runtime)
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            shutil.copy2(root / 'startup' / side / name, lua / side / name)
        shutil.copy2(root / 'health/shared/QueueHealthEvents.lua', lua / 'shared')
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL magazine-unload'], native_magazine_audit=audit, sandbox={'Zombies': 6})
    if reviewed: runtime['fixture']['equip_reviewed_source_audit'] = reviewed


def _raw(text, marker):
    return [json.loads(match.group(1)) for match in re.finditer(re.escape(PREFIX + marker + ' ') + r'([^\n]+)', text)]


def complete(selection, role, text):
    return role == 'client1' and _raw(text, 'COMPLETE') == [dict(cases=list(selection.get('cases', CASES)))]


def verifier_sources(project, selection):
    return [Path(__file__).with_name('magazine_unload_verifier.py'), Path(__file__).with_name('magazine_unload_equip_verifier.py'), Path(__file__).parents[1] / 'placement.py',
            Path(project) / 'tests/test_queue_magazine_unload.py', Path(project) / 'tests/test_queue_magazine_unload_equip.py', Path(project) / 'tests/test_queue_equip_work.py']


def check_case(row, selection, prepared, verified):
    from .magazine_unload_verifier import check_case as check
    return check(row, selection, prepared, verified)


def verify(root, selection, catalog):
    from ..provenance import run_verifier
    module = 'magazine_unload_equip_verifier.py' if selection.get('cases') == list(EQUIP_CASES) else 'magazine_unload_verifier.py'
    return run_verifier(Path(__file__).with_name(module), __package__, root, selection, catalog)
