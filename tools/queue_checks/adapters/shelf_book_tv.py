"""Real shelf-book pickup/read/return interrupted by selected TV media commands."""
from pathlib import Path
import re
import shutil

from ..mod_selection import metadata, mod_ids

PROJECT = Path(__file__).resolve().parents[3]
MODS = mod_ids(metadata(PROJECT / 'SurvivorQoL-selected.ini')['Mods'])
MARKER = '[SHELF_TV] '


def definitions():
    return {'shelf-book-tv': {'status': 'ready', 'clients': 1, 'default_mods': list(MODS),
            'cases': [{'id': 'demote-and-control', 'producer': 'fixture', 'capability': 'effect',
                       'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['toolkit', 'native']}]}}


def validate(selection):
    if (selection.get('cases') != ['demote-and-control'] or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') not in ('toolkit', 'native') or selection.get('languages') != ['EN']
            or selection.get('clients') != 1 or selection.get('mods') != MODS
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Shelf book/TV requires the full selected EN pack, fresh SP/Host, one client and native/toolkit queue mode')
    if 'TVRadio_ReInvented' not in MODS:
        raise ValueError('Selected pack must include TVRadio_ReInvented')
    if selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is not True:
        raise ValueError('Shelf book/TV MP requires a real Host from the game menu')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return (sorted((root / 'shelf-book-tv').rglob('*.lua')) + sorted((root / 'startup').rglob('*.lua'))
            + [root / 'support/QueueEnergyPlacement.lua'])


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZShelfBookTV.lua'), ('server', 'ZZShelfBookTVServer.lua')]:
            source = root / 'shelf-book-tv' / side / name
            target = lua / side / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        shared = lua / 'shared'
        shared.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / 'shelf-book-tv/shared/QueueShelfBookTV.lua', shared / 'QueueShelfBookTV.lua')
        shutil.copy2(root / 'support/QueueEnergyPlacement.lua', shared / 'QueueEnergyPlacement.lua')
        client_startup = lua / 'client/ZZStartup.lua'
        shutil.copy2(root / 'startup/client/ZZStartup.lua', client_startup)
        server_startup = lua / 'server/ZZStartupServer.lua'
        shutil.copy2(root / 'startup/server/ZZStartupServer.lua', server_startup)
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL shelf-book-tv'], sandbox={'Zombies': 6, 'MinutesPerPage': 2.0})


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(re.escape(MARKER) + r'COMPLETE case=demote-and-control(?:\s|$)', text)) == 1


def verify(root, selection, catalog):
    root = Path(root)
    issues, evidence = [], {}
    try:
        client = (root / 'client1-launch.log').read_text(errors='replace')
        required = [r'PREPARED shelfId=\d+ bookId=\d+ tv=\d+,-?\d+,-?\d+ tapeId=\d+ mediaIndex=\d+ mediaType=\d+ power=electric daylight=true',
                    r'PROGRESS authority=(?:server|local) pagesBefore=\d+ pagesCommitted=\d+',
                    r'READ started=true pagesBefore=\d+ pagesCommitted=\d+',
                    r'COMMANDS power=ISRadioAction insert=ISDeviceMediaAction play=ISRadioAction',
                    r'POWER_EFFECT command=ToggleOnOff turnedOn=true',
                    r'INSERT_EFFECT command=ISDeviceMediaAction exactTape=true mediaIndex=\d+ mediaType=\d+',
                    r'PLAY_EFFECT command=TogglePlayMedia mediaPlaying=true',
                    r'ACTIONS powerStarted=true powered=true insertStarted=true exactTape=true playStarted=true mediaMatched=true',
                    r'RETURN sameBook=true exactCount=1',
                    r'MEDIA tapeDebited=true exactTape=true mediaIndex=\d+ mediaType=\d+ title=Carzone playing=true',
                    r'COMPLETE case=demote-and-control']
        if selection['mode'] == 'toolkit':
            required += [r'PROMOTED current=ISReadABook target=ISRadioAction after=true accepted=true',
                         r'RESUMED sameAction=false sameBook=true sameOperation=true pagesBefore=\d+ pagesAfter=\d+']
        else:
            required += [r'CONTROL queueOff=true naturalReadBeforeTV=true', r'NATURAL_ORDER readerFinishedBeforeTV=true']
        matches = [re.findall(re.escape(MARKER) + pattern + r'(?:\s|$)', client) for pattern in required]
        if any(len(found) != 1 for found in matches) or MARKER + 'FAIL ' in client:
            issues.append('Missing or duplicate real shelf-book/TV interaction evidence')
        evidence['clientMarkers'] = [line[line.find(MARKER) + len(MARKER):] for line in client.splitlines() if MARKER in line]
        sequence = ['PREPARED', 'PROGRESS', 'READ', 'COMMANDS', 'PROMOTED' if selection['mode'] == 'toolkit' else 'CONTROL']
        if selection['mode'] == 'native':
            sequence.append('NATURAL_ORDER')
        sequence += ['POWER_EFFECT', 'INSERT_EFFECT', 'PLAY_EFFECT']
        if selection['mode'] == 'toolkit':
            sequence.append('RESUMED')
        sequence += ['ACTIONS', 'RETURN', 'MEDIA', 'COMPLETE']
        lines = client.splitlines()
        positions = []
        for prefix in sequence:
            found = [index for index, line in enumerate(lines) if (at := line.find(MARKER)) >= 0
                     and line[at + len(MARKER):].startswith(prefix + ' ')]
            if len(found) != 1:
                issues.append('Expected one ordered evidence marker: ' + prefix)
            else:
                positions.append(found[0])
        if positions != sorted(positions):
            issues.append('Shelf-book/TV evidence markers are out of order')
        prepared_client = re.findall(re.escape(MARKER) +
            r'PREPARED shelfId=(\d+) bookId=(\d+) tv=(\d+),(-?\d+),(-?\d+) tapeId=(\d+) mediaIndex=(\d+) mediaType=(\d+) power=electric daylight=true(?:\s|$)', client)
        progress_client = re.findall(re.escape(MARKER) +
            r'PROGRESS authority=(?:server|local) pagesBefore=(\d+) pagesCommitted=(\d+)(?:\s|$)', client)
        read_client = re.findall(re.escape(MARKER) +
            r'READ started=true pagesBefore=(\d+) pagesCommitted=(\d+)(?:\s|$)', client)
        inserted_client = re.findall(re.escape(MARKER) +
            r'INSERT_EFFECT command=ISDeviceMediaAction exactTape=true mediaIndex=(\d+) mediaType=(\d+)(?:\s|$)', client)
        media_client = re.findall(re.escape(MARKER) +
            r'MEDIA tapeDebited=true exactTape=true mediaIndex=(\d+) mediaType=(\d+) title=Carzone playing=true(?:\s|$)', client)
        if len(prepared_client) != 1:
            issues.append('Missing unique client-owned prepared exact IDs and media identity')
        if len(progress_client) != 1 or len(read_client) != 1:
            issues.append('Missing unique client partial-read progress receipts')
        elif progress_client[0] != read_client[0] or int(progress_client[0][1]) <= int(progress_client[0][0]):
            issues.append('Client read receipt does not match a committed increase in pages')
        if len(inserted_client) != 1 or len(media_client) != 1:
            issues.append('Missing unique exact client TV media insertion/final receipts')
        elif inserted_client[0] != media_client[0] or (len(prepared_client) == 1 and inserted_client[0] != prepared_client[0][6:8]):
            issues.append('Client inserted/final media identity differs from the exact prepared tape')
        resumed_client = re.findall(re.escape(MARKER) +
            r'RESUMED sameAction=false sameBook=true sameOperation=true pagesBefore=(\d+) pagesAfter=(\d+)(?:\s|$)', client)
        if selection['mode'] == 'toolkit' and len(resumed_client) == 1:
            if len(progress_client) != 1 or resumed_client[0][0] != progress_client[0][1] or int(resumed_client[0][1]) <= int(resumed_client[0][0]):
                issues.append('Resumed reading does not advance beyond the previously committed page count')
        forbidden = ['CONTROL', 'NATURAL_ORDER'] if selection['mode'] == 'toolkit' else ['PROMOTED', 'RESUMED']
        if any(any((at := line.find(MARKER)) >= 0 and line[at + len(MARKER):].startswith(prefix + ' ')
                   for line in lines) for prefix in forbidden):
            issues.append('Evidence included the opposite queue-mode branch')
        if selection['kind'] == 'mp':
            server = (root / 'server-launch.log').read_text(errors='replace')
            progress = re.findall(re.escape(MARKER) + r'AUTH_PROGRESS pagesBefore=(\d+) pagesCommitted=(\d+) actor=client1(?:\s|$)', server)
            if len(progress) != 1 or int(progress[0][1]) <= int(progress[0][0]):
                issues.append('Missing server-committed partial reading progress before the TV interruption')
            authority = re.findall(re.escape(MARKER) + r'AUTHORITY pagesComplete=true bookReturned=true exactBookCount=1 tapeRemoved=true mediaIndex=(\d+) mediaType=(\d+) tvMedia=Carzone playing=true actor=client1(?:\s|$)', server)
            if len(authority) != 1:
                issues.append('Missing unique server-owned final book/tape/TV receipt')
            prepared = re.findall(re.escape(MARKER) + r'PREPARED shelfId=\d+ bookId=\d+ tv=\d+,-?\d+,-?\d+ tapeId=\d+ mediaIndex=(\d+) mediaType=(\d+) power=electric daylight=true(?:\s|$)', server)
            if len(prepared) != 1 or len(authority) != 1 or authority[0] != prepared[0]:
                issues.append('Server final media index/type differs from exact prepared tape')
            if len(progress) == 1 and len(progress_client) == 1 and progress[0] != progress_client[0]:
                issues.append('Client progress receipt differs from server-committed page progress')
            if len(prepared) == 1 and len(prepared_client) == 1 and prepared[0] != prepared_client[0][6:8]:
                issues.append('Client exact tape identity differs from server-prepared tape')
            evidence['serverAuthority'] = authority
        if not complete(selection, 'client1', client):
            issues.append('Missing unique shelf-book/TV completion')
    except OSError as error:
        issues.append(str(error))
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'demote-and-control',
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}],
            'evidence': dict(evidence, limits=['One EN client in fresh SP/Host; full selected pack; programmatic native UI callbacks, no physical input.'])}
