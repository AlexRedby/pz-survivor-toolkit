"""Owned Quartermaster world-container and worn-backpack distribution."""
import json
from pathlib import Path
import re
import shutil
import struct

from .. import receipts

SUITE = 'quartermaster-distribution'
MODS = ['PZSurvivorToolkit', 'PZToolkitJavaPatches']


def definitions():
    return {SUITE: {'status': 'ready', 'clients': 1, 'default_mods': MODS,
                   'cases': [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                              'kinds': kinds, 'languages': ['EN'], 'modes': ['toolkit']}
                             for case, kinds in [('sort', ['sp', 'mp']), ('backpack', ['sp']), ('deposit', ['sp', 'mp']),
                                                 ('batch', ['mp']), ('barricaded-door', ['sp', 'mp'])]]}}


def validate(selection):
    if (selection.get('cases') not in (['sort'], ['backpack'], ['deposit'], ['batch'], ['barricaded-door']) or selection.get('kind') not in ('sp', 'mp')
            or (selection.get('cases') == ['backpack'] and selection.get('kind') != 'sp')
            or selection.get('mode') != 'toolkit' or selection.get('clients', 1) != 1
            or selection.get('languages') != ['EN'] or not set(MODS) <= set(selection.get('mods', []))
            or selection.get('options', {}).get('world_template')
            or selection.get('cases') == ['batch'] and selection.get('kind') != 'mp'
            or selection.get('cases') == ['batch'] and selection.get('options', {}).get('mp_host') is not True
            or selection.get('cases') in (['deposit'], ['barricaded-door']) and selection.get('kind') == 'mp'
            and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('Distribution requires sort/deposit/barricaded-door in fresh SP/Host or backpack in fresh SP, one EN client and Toolkit')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / SUITE).rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua'),
                           ('shared', 'QueueHealthEvents.lua')]:
            (lua / side).mkdir(parents=True, exist_ok=True)
            shutil.copy2(root / ('health' if side == 'shared' else 'startup') / side / name, lua / side)
    runtime['fixture'] = {'server_ready': '[STARTUP_TEST] SERVER_READY', 'sandbox': {'Zombies': 6},
                          'failure_markers': ['[QM_DOOR] FAIL ']}


def complete(selection, role, text):
    if selection.get('cases') == ['barricaded-door']:
        try:
            rows = _deposit_records(text, 'QM_DOOR')
            return (role == 'client1' and sum(event == 'COMPLETE' for event, _ in rows) == 1
                    and _exact(rows[-1], ('COMPLETE', {'case': 'barricaded-door'})))
        except (ValueError, IndexError):
            return False
    if selection.get('cases') == ['batch']:
        try:
            records = [value for event, value in _deposit_records(text, 'QM_BATCH') if event == 'COMPLETE']
            return role == 'client1' and _exact(records, [dict(case='batch', rejected=True, accepted=True,
                                                              manual=True, continued=True)])
        except (ValueError, KeyError, TypeError):
            return False
    if selection.get('cases') == ['deposit']:
        try:
            records = [value for event, value in _deposit_records(text) if event == 'COMPLETE']
            return role == 'client1' and _exact(records, [dict(case='deposit', kind=selection['kind'],
                                                            merged=True, confirmedRejectionMP=selection['kind'] == 'mp')])
        except (ValueError, KeyError, TypeError):
            return False
    if selection.get('cases') == ['backpack']:
        return role == 'client1' and len(re.findall(r'\[QM_BACKPACK\] COMPLETE[ \t]*\r?$', text, re.MULTILINE)) == 1
    return role == 'client1' and len(re.findall(r'\[QM_DISTRIBUTION\] COMPLETE(?:\s|$)', text)) == 1


def _one(text, event):
    values = re.findall(r'\[QM_DISTRIBUTION\] ' + event + r' (\{[^\r\n]+\})', text)
    if len(values) != 1:
        raise ValueError('Missing/duplicate distribution ' + event)
    return json.loads(values[0])


def _exact(value, expected):
    if type(value) is not type(expected):
        return False
    if type(expected) is dict:
        return set(value) == set(expected) and all(_exact(value[key], item) for key, item in expected.items())
    if type(expected) is list:
        return len(value) == len(expected) and all(_exact(a, b) for a, b in zip(value, expected))
    return value == expected


def _deposit_records(text, prefix='QM_DEPOSIT'):
    records = []
    for line in text.splitlines():
        marker = '[' + prefix + '] '
        offset = line.find(marker)
        if offset < 0:
            continue
        event, separator, body = line[offset + len(marker):].partition(' ')
        if not separator:
            raise ValueError('Malformed deposit receipt')
        records.append((event, receipts.decode_object(body)))
    return records


def _deposit(root, selection):
    issues, receipt, authority_receipt = [], None, None
    try:
        root, kind = Path(root), selection['kind']
        text = (root / 'client1-launch.log').read_text(errors='replace')
        records = _deposit_records(text)
        expected_events = ['PREPARED', 'LOCAL', *(['AUTHORITY'] if kind == 'sp' else []), 'CLEANUP', 'COMPLETE']
        if [event for event, _ in records] != expected_events:
            raise ValueError('Deposit client lifecycle missing, duplicated or reordered')
        values = dict(records)
        packet, receipt = values['PREPARED'], values['LOCAL']
        if (set(packet) != {'kind', 'ids', 'ballastId', 'boxes'} or packet['kind'] != kind
                or type(packet['ids']) is not list or len(packet['ids']) != 3
                or any(type(value) is not int for value in packet['ids']) or len(set(packet['ids'])) != 3
                or kind == 'sp' and (type(packet['ballastId']) is not int or packet['ballastId'] in packet['ids'])
                or kind == 'mp' and packet['ballastId'] is not False
                or type(packet['boxes']) is not list or len(packet['boxes']) != 3):
            raise ValueError('Invalid exact deposit preparation identities')
        for point in packet['boxes']:
            if (type(point) is not dict or set(point) != {'x', 'y', 'z', 'index'}
                    or any(type(value) is not int for value in point.values()) or point['index'] < 0):
                raise ValueError('Invalid deposit world-container descriptor')
        source, limited, tail = packet['boxes']
        if (limited['x'] != source['x'] + 2 or limited['y'] != source['y']
                or tail['x'] != source['x'] + 1 or tail['y'] != source['y'] + 1
                or len({point['z'] for point in packet['boxes']}) != 1):
            raise ValueError('Deposit crates are not adjacent to the same actor position')
        expected = dict(kind=kind, ids=packet['ids'], ballastId=packet['ballastId'],
                        destinations=[2, 1, 3] if kind == 'sp' else [1, 1, 3], sourceCount=1 if kind == 'sp' else 2,
                        limitedCapacity=1 if kind == 'sp' else 0, limitedWeight=.9375 if kind == 'sp' else 0,
                        tailWeight=.0625, conserved=4 if kind == 'sp' else 3)
        rejection_id = receipt.get('rejectionId')
        if (type(rejection_id) is not int or (rejection_id == 0) != (kind == 'sp')
                or not _exact(receipt, dict(expected, merged=True, confirmedRejectionMP=kind == 'mp',
                                            rejectionId=rejection_id, startCapacity=2 if kind == 'sp' else 100))):
            raise ValueError('Deposit exact client effect/merge/native-rejection evidence differs')
        authority = (root / 'server-launch.log').read_text(errors='replace') if kind == 'mp' else text
        server_records = _deposit_records(authority)
        if kind == 'mp' and [event for event, _ in server_records] != ['PREPARED', 'AUTHORITY', 'CLEANUP']:
            raise ValueError('Deposit authority lifecycle missing, duplicated or reordered')
        server_values = dict(server_records)
        authority_receipt = server_values['AUTHORITY']
        if not _exact(server_values['PREPARED'], packet) or not _exact(authority_receipt, expected):
            raise ValueError('Deposit client/server item identities/capacity/conservation differ')
        if not _exact(values['CLEANUP'], {'objects': 3}) or not _exact(server_values['CLEANUP'], {'objects': 3}):
            raise ValueError('Deposit owned cleanup missing')
        if not complete(selection, 'client1', text) or any('[QUEUE_TEST] FAIL ' in value for value in (text, authority)):
            raise ValueError('Deposit completion missing or native fixture failed')
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'deposit',
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}],
            'evidence': {'receipt': receipt, 'authority': authority_receipt,
                         'limits': ['Boundary fixture uses native queued transfers; no UI/menu or physical input claim.',
                                    'Host uses one menu client and real native Request rejection.']}}


def _backpack(root, selection):
    issues, receipt = [], None
    try:
        text = (Path(root) / 'client1-launch.log').read_text(errors='replace')
        records = re.findall(r'\[QM_BACKPACK\] (PREPARED|RESULT|COMPLETE)(?:[ \t]|$)([^\r\n]*)', text, re.MULTILINE)
        if [event for event, _ in records] != ['PREPARED', 'RESULT', 'COMPLETE']:
            raise ValueError('Backpack preparation/result/completion missing, duplicated or reordered')
        prepared, receipt = [json.loads(value) for _, value in records[:2]]
        ids = prepared.get('ids') if type(prepared) is dict else None
        if (type(ids) is not list or len(ids) != 6 or any(type(value) is not int for value in ids)
                or len(set(ids)) != 6 or set(prepared) != {'ids'}):
            raise ValueError('Backpack item identities are not six unique integers')
        expected = dict(ids=ids, moved=1, retained=4, backpackWorn=True, stuckRetained=True, menuDispatched=True,
                        toolbarVisible=True, sourceBag=True, transfer=True, rejectedDestinationSkipped=True)
        if (type(receipt) is not dict or set(receipt) != set(expected)
                or any(type(receipt[key]) is not type(value) or receipt[key] != value
                       for key, value in expected.items())
                or any(type(value) is not int for value in receipt['ids'])):
            raise ValueError('Backpack exact menu/source/movement/transfer/rejected-destination effects differ')
        if not complete(selection, 'client1', text) or records[2][1].strip() or '[QM_BACKPACK] FAIL ' in text:
            raise ValueError('Backpack completion gate missing or fixture failed')
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'backpack',
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}],
            'evidence': {'receipt': receipt, 'limits': ['Programmatic native context-menu callback; no physical input or Host coverage.']}}


def _batch(root, selection):
    issues, receipts = [], {}
    try:
        root = Path(root)
        text = (root / 'client1-launch.log').read_text(errors='replace')
        server = (root / 'server-launch.log').read_text(errors='replace')
        if not re.search(r'\[PZToolkitJavaPatches\][^\r\n]*itemBatchAdmission=true(?:,|\s|$)', server):
            raise ValueError('Server batch-admission activation missing')
        records = _deposit_records(text, 'QM_BATCH')
        authority = _deposit_records(server, 'QM_BATCH')
        if [event for event, _ in records] != ['PREPARED', 'REJECTED', 'ACCEPTED', 'CLEANUP', 'COMPLETE']:
            raise ValueError('Batch client lifecycle missing, duplicated or reordered')
        if [event for event, _ in authority] != ['PREPARED', 'REJECTED', 'ACCEPTED', 'CLEANUP']:
            raise ValueError('Batch authority lifecycle missing, duplicated or reordered')
        local, remote = dict(records), dict(authority)
        packet = local['PREPARED']
        ids, ballast = packet.get('ids'), packet.get('ballastId')
        if (set(packet) != {'kind', 'ids', 'ballastId', 'boxes'} or packet['kind'] != 'batch'
                or type(ids) is not list or len(ids) != 4 or any(type(value) is not int for value in ids)
                or len(set(ids)) != 4 or type(ballast) is not int or ballast in ids
                or type(packet['boxes']) is not list or len(packet['boxes']) != 3
                or not _exact(remote['PREPARED'], packet)):
            raise ValueError('Batch preparation identities differ')
        for stage, destinations, count, weight in [('rejected', [1, 1, 1, 3], 3, .875),
                                                   ('accepted', [2, 2, 1, 3], 1, 1)]:
            event = stage.upper()
            expected = dict(kind='batch', stage=stage, ids=ids, ballastId=ballast, destinations=destinations,
                            sourceCount=count, limitedCapacity=1, limitedWeight=weight,
                            tailWeight=.0625, conserved=5)
            result = local[event]
            txid = result.get('transactionId')
            if (type(txid) is not int or txid == 0
                    or not _exact(result, dict(result=expected, merged=True, transactionId=txid))
                    or not _exact(remote[event], expected)):
                raise ValueError('Batch exact effects/merge/outcome differ: ' + stage)
            receipts[stage] = result
        if (local['REJECTED']['transactionId'] == local['ACCEPTED']['transactionId']
                or not _exact(local['CLEANUP'], {'objects': 3}) or not _exact(remote['CLEANUP'], {'objects': 3})
                or not complete(selection, 'client1', text)
                or any('[QUEUE_TEST] FAIL ' in value for value in (text, server))):
            raise ValueError('Batch terminal/cleanup gates failed')
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'batch',
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}],
            'evidence': {'receipts': receipts, 'limits': ['Menu Host with one client, native queued container transfers; no physical UI input.']}}


def _barricaded_door(root, selection):
    issues, receipt, authority_receipt = [], None, None
    try:
        root, kind = Path(root), selection['kind']
        text = (root / 'client1-launch.log').read_text(errors='replace')
        records = _deposit_records(text, 'QM_DOOR')
        events = ['PREPARED', 'RESULT', *(['AUTHORITY'] if kind == 'sp' else []), 'CLEANUP', 'COMPLETE']
        if [event for event, _ in records] != events:
            raise ValueError('Door fixture lifecycle missing, duplicated or reordered')
        local = dict(records)
        prepared, receipt = local['PREPARED'], local['RESULT']
        ids = prepared.get('ids')
        if (type(ids) is not list or len(ids) != 2 or any(type(value) is not int for value in ids)
                or len(set(ids)) != 2 or set(prepared) != {'ids'}):
            raise ValueError('Door fixture needs two unique item identities')
        expected = dict(ids=ids, moved=2, normalDoorOpened=True, barricadedDoorClosed=True,
                        barricadeIntact=True, conserved=True)
        if not _exact(receipt, dict(expected, nativeWalking=True, detour=True)):
            raise ValueError('Barricaded-door routing or exact distribution effects differ')
        authority = (root / 'server-launch.log').read_text(errors='replace') if kind == 'mp' else text
        if kind == 'mp':
            remote = _deposit_records(authority, 'QM_DOOR')
            if [event for event, _ in remote] != ['PREPARED', 'AUTHORITY', 'CLEANUP']:
                raise ValueError('Door authority or cleanup receipt missing, duplicated or reordered')
            remote = dict(remote)
        else:
            remote = local
        authority_receipt = remote['AUTHORITY']
        if not _exact(remote['PREPARED'], prepared) or not _exact(authority_receipt, expected):
            raise ValueError('Door authoritative item/door/barricade effects differ')
        cleanup = {'objects': 15, 'localRemoved': True, 'registryCleared': True}
        if (not _exact(local['CLEANUP'], cleanup)
                or not _exact(remote['CLEANUP'], cleanup if kind == 'sp' else {'objects': 15})
                or not _exact(local['COMPLETE'], {'case': 'barricaded-door'})
                or not complete(selection, 'client1', text)
                or any('[QM_DOOR] FAIL ' in value or '[QUEUE_TEST] FAIL ' in value for value in (text, authority))):
            raise ValueError('Door fixture completion/cleanup gate missing or fixture failed')
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'barricaded-door',
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}],
            'evidence': {'receipt': receipt, 'authority': authority_receipt,
                         'limits': ['Native toolbar callback in SP or one-client menu Host; no physical input or second client.']}}


def _group_configuration(stage, names):
    if stage == 'blank':
        return dict(cats=[], items=[], presets=[], priority=0, noDuplicates=False, appearance=[])
    first, local = stage in ('created', 'joined'), stage == 'detached'
    return dict(cats=[], items={name: True for name in (names[:1] if local else names)},
                presets=[], priority=4 if local else 6 if first else 9 if stage == 'unique' else 11,
                noDuplicates=stage == 'unique',
                appearance=dict(name='PZST local cooking' if local else 'PZST cooking group' if first else 'PZST shared cooking',
                                icon=dict(kind='item', value='Base.BookCooking1' if first else 'Base.BookCooking2'),
                                color=dict(zip(('r', 'g', 'b', 'a'),
                                               (.5, .75, .25, 1) if local else (.25, .5, .75, 1) if first else (.75, .25, .5, 1)))))


def _group_rule(stage):
    return dict(mode='all', include=['readable'] if stage in ('created', 'joined') else ['experience', 'readable'],
                exclude=['writeable'])


def _groups(root, selection, text, authority, earlier_ids):
    packet = _one(text, 'GROUP_PREPARED')
    ids, names = packet['ids'], packet['names']
    types = ['Base.BookCooking1', 'Base.BookCooking1', 'Base.BookCooking2', 'Base.BookCooking2', 'Base.BookCooking1']
    if (set(packet) != {'ids', 'types', 'names', 'creator', 'member'} or not _exact(packet['types'], types)
            or type(ids) is not list or len(ids) != 5 or any(type(value) is not int for value in ids)
            or len(set(ids)) != 5 or set(ids) & set(earlier_ids)
            or type(names) is not list or len(names) != 2 or any(type(name) is not str or not name for name in names)
            or len(set(names)) != 2 or type(packet['creator']) is not str or not packet['creator']
            or selection['kind'] == 'mp' and packet['creator'] != 'client1'):
        raise ValueError('Grouped books preparation identities/actor differ')
    member = packet['member']
    if (type(member) is not dict or set(member) != {'x', 'y', 'z', 'index'}
            or any(type(value) is not int for value in member.values()) or member['index'] < 0):
        raise ValueError('Invalid grouped world member descriptor')
    if selection['kind'] == 'mp' and not _exact(_one(authority, 'GROUP_PREPARED_AUTHORITY'), packet):
        raise ValueError('Group preparation differs from authority')
    def rows(body, event):
        return [receipts.decode_object(value) for value in re.findall(
            r'\[QM_DISTRIBUTION\] ' + event + r' (\{[^\r\n]+\})', body)]
    local, remote = rows(text, 'GROUP_LOCAL'), rows(authority, 'GROUP_AUTHORITY')
    stages = ['created', 'joined', 'updated', 'detached', 'rejoined', 'unique']
    if len(local) != 6 or len(remote) != 6:
        raise ValueError('Group creation/join/update/detach/unique authority stages missing or duplicated')
    group = local[0]['groupId']
    if type(group) is not str or not group or len(group) > 128:
        raise ValueError('Invalid stable group identity')
    for own, server, stage in zip(local, remote, stages):
        first, detached = stage in ('created', 'joined'), stage in ('created', 'detached')
        source = 'updated' if stage in ('detached', 'rejoined') else stage
        target = 'blank' if stage == 'created' else stage
        expected = dict(stage=stage, groupId=group, revision=1 if first else 3 if stage == 'unique' else 2,
                        creator=packet['creator'], links=[group, False if detached else group],
                        configurations=[_group_configuration(source, names), _group_configuration(target, names)],
                        rules=[_group_rule(source), dict(mode='all', include=[], exclude=[]) if stage == 'created'
                               else _group_rule(target)])
        if not _exact(own, expected) or not _exact(server, expected):
            raise ValueError('Group effective appearance/filter/scope/authority differs: ' + stage)
    result = _one(text, 'GROUP_TRANSFERS_LOCAL')
    destinations = [row['container'] for row in result['items']]
    if destinations not in ([2, 2, 2, 3, 3], [2, 2, 3, 2, 3], [2, 2, 2, 4, 3], [2, 2, 4, 2, 3]):
        raise ValueError('Grouped exact book destinations violate group uniqueness/fallback')
    expected = dict(ids=ids, items=[dict(id=value, fullType=kind, container=dest)
                                   for value, kind, dest in zip(ids, types, destinations)],
                    groupId=group, groupRevision=3, memberCount=2, noDuplicates=True, priorities=[9, 5],
                    existingGroupCopy=True, sameBatch=True, differentVolume=True, moved=4, conserved=5)
    if not _exact(result, expected) or not _exact(_one(authority, 'GROUP_TRANSFERS_AUTHORITY'), expected):
        raise ValueError('Grouped book transfer conservation/authority differs')
    if not _exact(_one(text, 'GROUP_COMPLETE'), dict(stages=6, members=2, localDetached=True, groupDuplicates=True)):
        raise ValueError('Group cleanup/completion gate missing')
    shot = _one(text, 'GROUP_SHOT')
    if (set(shot) != {'name', 'width', 'height'} or shot['name'] != 'quartermaster-group-editor'
            or any(type(shot[key]) is not int or shot[key] < 100 for key in ('width', 'height'))):
        raise ValueError('Group editor screenshot receipt differs')
    screenshot = root / 'client1/Screenshots/quartermaster-group-editor.png'
    data = screenshot.read_bytes()
    if (len(data) < 33 or data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR'
            or any(value < 300 for value in struct.unpack('>II', data[16:24]))):
        raise ValueError('Group editor native screenshot missing or invalid')
    return dict(stages=local, transfers=result, screenshot=str(screenshot))


def verify(root, selection, catalog):
    if selection.get('cases') == ['barricaded-door']:
        return _barricaded_door(root, selection)
    if selection.get('cases') == ['batch']:
        return _batch(root, selection)
    if selection.get('cases') == ['deposit']:
        return _deposit(root, selection)
    if selection.get('cases') == ['backpack']:
        return _backpack(root, selection)
    issues, receipt, book_result, groups = [], None, None, None
    try:
        root = Path(root)
        text = (root / 'client1-launch.log').read_text(errors='replace')
        packet = _one(text, 'PREPARED')
        ids = packet['ids']
        if len(ids) != 4 or any(type(value) is not int for value in ids) or len(set(ids)) != 4:
            raise ValueError('Distribution item identities are not unique integers')
        expected = {'items': [{'id': value, 'container': dest} for value, dest in zip(ids, [2, 3, 1, 1])],
                    'moved': 2, 'retained': 2, 'favorite': True}
        receipt = _one(text, 'LOCAL')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
        if receipt != expected or _one(authority, 'AUTHORITY') != expected:
            raise ValueError('Client/server distribution effects differ from exact designated destinations')
        books = _one(text, 'BOOKS_PREPARED')
        book_ids = books['ids']
        types = ['Base.BookCarpentry1', 'Base.BookCarpentry1', 'Base.BookCarpentry2',
                 'Base.BookCarpentry2', 'Base.BookCarpentry1']
        if (not _exact(books, dict(ids=book_ids, types=types)) or type(book_ids) is not list
                or len(book_ids) != 5 or any(type(value) is not int for value in book_ids)
                or len(set(book_ids)) != 5 or set(book_ids) & set(ids)):
            raise ValueError('Skill-book exact preparation identities differ')
        if selection['kind'] == 'mp' and not _exact(_one(authority, 'BOOKS_PREPARED_AUTHORITY'), books):
            raise ValueError('Skill-book preparation differs from Host authority')
        book_result = _one(text, 'BOOKS_LOCAL')
        destinations = [row['container'] for row in book_result['items']]
        if destinations not in ([2, 2, 2, 3, 3], [2, 2, 3, 2, 3]):
            raise ValueError('Skill-book direct destination uniqueness/fallback differs')
        expected_books = dict(ids=book_ids,
                              items=[dict(id=value, fullType=kind, container=dest)
                                     for value, kind, dest in zip(book_ids, types, destinations)],
                              noDuplicates=True, fallbackNoDuplicates=False, priorities=[7, 5],
                              existingCopy=True, sameBatch=True, differentVolume=True, moved=4, conserved=5)
        if (not _exact(book_result, expected_books)
                or not _exact(_one(authority, 'BOOKS_AUTHORITY'), expected_books)):
            raise ValueError('Skill-book authoritative configuration/transfer effects differ')
        groups = _groups(root, selection, text, authority, ids + book_ids)
        marker = '[QM_DISTRIBUTION] COMPLETE moved=2 retained=2 walking=true pickup=true destinations=2 favorite=true'
        if not complete(selection, 'client1', text) or text.count(marker) != 1:
            raise ValueError('Distribution movement/transfer/cleanup gate missing')
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'sort',
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}],
            'evidence': {'receipt': receipt, 'books': book_result, 'groups': groups,
                         'limits': ['Programmatic native button callback; no physical input or second client.']}}
