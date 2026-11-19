"""Verify the native conversion of a held generator with a same-square decoy."""
from pathlib import Path
import shutil
import zipfile

from .. import receipts
from .razor_restoration import MODS

SUITE = 'generator-drop'
MARKER = '[GENERATOR_DROP] '


def definitions():
    return {SUITE: dict(status='ready', clients=2, default_mods=MODS, cases=[
        dict(id=case, kinds=[kind], clients=count, languages=languages,
             modes=['toolkit'], producer='fixture', capability='effect')
        for case, kind, count, languages in [('same-square', 'sp', 1, ['EN']),
                                              ('peer-pickup', 'mp', 2, ['EN', 'RU'])]])}


def validate(selection):
    peer = selection['kind'] == 'mp'
    options = selection.get('options', {})
    if (selection['kind'] not in ('sp', 'mp') or selection['mode'] != 'toolkit'
            or selection['cases'] != (['peer-pickup'] if peer else ['same-square'])
            or selection['clients'] != (2 if peer else 1)
            or selection['languages'] != (['EN', 'RU'] if peer else ['EN'])
            or selection['mods'] != MODS or peer and options.get('mp_host') is not True
            or options.get('world_template')):
        raise ValueError('Generator drop requires a fresh P4-free SP or two-client menu Host world')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / SUITE).rglob('*.lua')), root / 'startup/client/ZZStartup.lua',
            root / 'startup/server/ZZStartupServer.lua', root / 'health/shared/QueueHealthEvents.lua',
            root / 'support/QueuePreflight.lua', root / 'support/QueueEnergyPlacement.lua',
            Path(receipts.__file__)]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    jar = Path(locations['PZToolkitJavaPatches']) / '42/media/java/PZToolkitJavaPatches.jar'
    with zipfile.ZipFile(jar) as archive:
        if 'net/alexredby/pztoolkitjavapatches/GeneratorDropObservation$ItemConversion.class' not in archive.namelist():
            raise ValueError('Generator drop requires the selected native placement observer')
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for relative in ['startup/client/ZZStartup.lua', 'startup/server/ZZStartupServer.lua',
                         'health/shared/QueueHealthEvents.lua']:
            source = root / relative
            shutil.copy2(source, lua / source.parent.name / source.name)
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL generator-drop'], sandbox={'Zombies': 6})


def markers(text, name):
    prefix = MARKER + name + ' '
    return [line.split(prefix, 1)[1] for line in text.splitlines() if prefix in line]


def complete(selection, role, text):
    return role.startswith('client') and markers(text, 'COMPLETE') == selection['cases']


def verify(root, selection, catalog):
    peer = selection['kind'] == 'mp'
    case, = selection['cases']
    roles = ['client1', 'client2'] if peer else ['client1']
    picker = roles[-1]
    errors = []
    try:
        logs = {role: (Path(root) / (role + '-launch.log')).read_text(errors='replace')
                for role in roles + (['server'] if peer else [])}
        for role, log in logs.items():
            if markers(log, 'COMPLETE') != ([case] if role in roles else []):
                raise ValueError(role + ' completion missing or duplicated')
            if markers(log, 'STARTED') != ([case] if role == picker else []):
                raise ValueError(role + ' native pickup progress differs')
            rows = receipts.records(log, MARKER, 'AUTHORITY')
            if role != ('server' if peer else 'client1'):
                if rows:
                    raise ValueError('Unexpected client authority observation')
                continue
            row, = rows
            expected = dict(case=case, owner='client1', picker=picker, type='Base.Generator',
                            condition=73, fuel=7.5, distinctDecoy=True, exactAfterDrop=True,
                            missingAfterTake=True, decoyStillPresent=True, ownerKeptRazor=peer,
                            outputInBothHands=True, sourceFavorite=True, outputFavorite=False)
            for key, expected_value in expected.items():
                observed = row.get(key)
                if observed != expected_value or isinstance(observed, bool) != isinstance(expected_value, bool):
                    raise ValueError('Incorrect authority result for ' + key)
            for key in ('originalId', 'outputId', 'ownerOnlineId', 'pickerOnlineId'):
                if type(row.get(key)) is not int:
                    raise ValueError('Missing identity for ' + key)
            if row['originalId'] == row['outputId'] or (row['ownerOnlineId'] != row['pickerOnlineId']) != peer:
                raise ValueError('Generator conversion or player identity differs')
    except (KeyError, OSError, ValueError) as error:
        errors.append(str(error))
    return dict(issues=errors, outcomes=[dict(actor=role, case=case,
        status='failed' if errors else 'passed', reason='; '.join(errors)) for role in roles])
