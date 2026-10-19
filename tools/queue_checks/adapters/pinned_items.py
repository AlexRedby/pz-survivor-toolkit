"""Verify pinned item order in the native vehicle container window."""
import json
from pathlib import Path
import shutil


MARKER = '[PIN_ITEMS] '
SCENES = ['startup-order', 'clean-name', 'clean-category', 'clean-weight',
          'clean-name-desc', 'clean-category-desc', 'clean-weight-desc',
          'clean-category-filter']
CLEANUI_SCENES = ['clean-search-match', 'clean-search', 'vanilla-name', 'vanilla-category', 'vanilla-weight']
ORGANIZED_CATEGORIES_SCENES = ['organized-item-pin', 'category-split']


def expected_scenes(selection):
    scenes = ['startup-order']
    mods = selection.get('mods', [])
    if 'organizedCategories_core' in mods and 'CleanUI' in mods:
        scenes.append('organized-item-pin')
    scenes.extend(SCENES[1:])
    if 'organizedCategories_core' in mods:
        scenes.append('category-split')
    if 'CleanUI' in mods:
        scenes.extend(CLEANUI_SCENES)
    return scenes


def definitions():
    return {'pinned-items': {'status': 'ready', 'clients': 2,
            'default_mods': ['PZSurvivorToolkit', 'EURY_CONTAINERS'],
            'cases': [{'id': 'trunk', 'producer': 'fixture', 'capability': 'effect',
                       'kinds': ['sp', 'mp'], 'languages': ['EN', 'RU'],
                       'modes': ['toolkit', 'native']} ]}}


def validate(selection):
    kind = selection.get('kind')
    clients = selection.get('clients', 2 if kind == 'mp' else 1)
    languages = selection.get('languages')
    options = selection.get('options', {})
    if (not isinstance(options, dict)
            or selection.get('cases') != ['trunk'] or kind not in ('sp', 'mp')
            or selection.get('mode') not in ('toolkit', 'native')
            or type(clients) is not int
            or clients != (2 if kind == 'mp' else 1)
            or languages not in ((['EN', 'RU'],) if kind == 'mp' else (['EN'], ['RU']))
            or 'EURY_CONTAINERS' not in selection.get('mods', [])
            or 'PZSurvivorToolkit' not in selection.get('mods', [])
            or 'advanced_categories' in options and type(options['advanced_categories']) is not bool
            or options.get('world_template') or options.get('seed_run') or options.get('startup_connection')):
        raise ValueError('Pinned items requires fresh SP/Host, trunk, required client languages and EURY_CONTAINERS')
    if kind == 'mp' and (options.get('mp_host') is not True
                         or not {'CleanUI', 'organizedCategories_core'} <= set(selection.get('mods', []))):
        raise ValueError('Pinned-items MP requires a two-client Host and both integration mods for all 15 scenes')
    if kind == 'sp' and options.get('mp_host'):
        raise ValueError('Pinned-items SP cannot use Host mode')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return sorted((root / 'pinned-items').rglob('*.lua')) + sorted((root / 'startup').rglob('*.lua'))


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    for role in runtime['roles']:
        target = Path(output) / role / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            shutil.copy2(Path(project) / 'tests/native_queue/startup' / side / name, target / side / name)
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
                                            failure_markers=[MARKER + 'FAIL '])


def complete(selection, role, text):
    return role in ('client1', 'client2') and text.count(MARKER + 'COMPLETE trunk') == 1


def _records(text, name, issues):
    marker = MARKER + name + ' '
    label = name.lower()
    rows = []
    for line in text.splitlines():
        offset = line.find(marker)
        if offset < 0:
            continue
        try:
            value = json.loads(line[offset + len(marker):])
        except json.JSONDecodeError:
            issues.append('Malformed pinned items ' + label + ' JSON')
            continue
        if not isinstance(value, dict):
            issues.append('Pinned items ' + label + ' must be a JSON object')
            continue
        rows.append(value)
    return rows


def _item_signature(value):
    if not isinstance(value, str) or not value:
        return False
    parsed = []
    for entry in value.split('|'):
        item_id, separator, full_type = entry.partition(':')
        if not separator or not item_id.isdigit() or not full_type:
            return False
        parsed.append((int(item_id), entry))
    return len(parsed) == 6 and len({item_id for item_id, _ in parsed}) == 6 and parsed == sorted(parsed)


def _verify_scene(row, issues, expected_item_count=None):
    if row.get('status') != 'passed':
        issues.append('Pinned items scene ' + str(row.get('scene')) + ' ' +
                      str(row.get('status')) + ': ' + str(row.get('reason', '')))
    if (not isinstance(row.get('truckId'), (str, int)) or not str(row.get('truckId')).isdigit()
            or not isinstance(row.get('containerType'), str) or not row['containerType']
            or not isinstance(row.get('rowOrder'), list) or not row['rowOrder']
            or any(not isinstance(item, str) or not item for item in row['rowOrder'])
            or row['rowOrder'][0] != row.get('expectedFirst', row.get('target'))
            or type(row.get('targetTypeCount')) is not int or row['targetTypeCount'] < 1
            or row.get('selectedPreserved') is not True
            or type(row.get('itemCountBefore')) is not int or row['itemCountBefore'] <= 0
            or type(row.get('itemCountAfter')) is not int or row['itemCountAfter'] <= 0
            or row['itemCountBefore'] != row['itemCountAfter']
            or expected_item_count is not None and row['itemCountBefore'] != expected_item_count):
        issues.append('Invalid container identity, row order, target or item conservation: ' + str(row.get('scene')))
    if row.get('scene') == 'startup-order' and (
            any(not isinstance(row.get(key), str) or not row[key]
                for key in ('activeClass', 'comparatorIdentity', 'comparatorName'))
            or any(key not in row for key in ('searchState', 'searchCategoryState', 'searchModeState',
                                              'toolkitCategoryState', 'toolkitTagState', 'toolkitTagRuleActive'))):
        issues.append('Missing cold-start inventory class, comparator or filter state evidence')
    if row.get('scene') == 'clean-category-filter' and (
            not isinstance(row.get('filterCategory'), str) or not row['filterCategory']
            or type(row.get('filteredTypeCount')) is not int or row['filteredTypeCount'] < 2
            or not isinstance(row.get('rowOrder'), list)
            or len(row.get('rowOrder', [])) != row.get('filteredTypeCount')
            or row.get('target') != 'Base.Screwdriver' or row.get('targetTypeCount') != 2):
        issues.append('Category filter did not retain multiple types or duplicate pinned items')
    if row.get('scene') == 'clean-search-match' and (
            not isinstance(row.get('searchText'), str) or not row['searchText']
            or type(row.get('matchingTypeCount')) is not int or row['matchingTypeCount'] < 2
            or not isinstance(row.get('rowOrder'), list)
            or row.get('matchingTypeCount') > len(row.get('rowOrder', []))
            or row.get('allRowsMatch') is not True):
        issues.append('Search did not preserve multiple matching-first rows')
    if row.get('scene') == 'organized-item-pin' and (
            row.get('provider') != 'organizedCategories_core' or row.get('organizedPinned') is not True):
        issues.append('Organized Categories toolbar pin did not pin the selected item')
    if row.get('scene') == 'category-split' and (
            row.get('provider') != 'BetterContainers' or row.get('splitRows') != 2
            or not isinstance(row.get('splitCategories'), list)
            or len(row.get('splitCategories', [])) != 2
            or not isinstance(row.get('rowCategories'), list) or not row.get('rowCategories')
            or row.get('rowCategories')[0] != row.get('expectedFirstCategory')):
        issues.append('Organized Categories did not split duplicate items into two rows')


def _verify_sp(root, selection, issues):
    text = (Path(root) / 'client1-launch.log').read_text(errors='replace')
    records = _records(text, 'RESULT', issues)
    if [row.get('scene') for row in records] != expected_scenes(selection):
        issues.append('Missing, duplicate or out-of-order pinned items scenes')
    for row in records:
        _verify_scene(row, issues)
    if not complete(selection, 'client1', text) or MARKER + 'FAIL ' in text:
        issues.append('Missing pinned items completion or fatal fixture marker')
    return {'outcomes': [{'actor': 'client1', 'case': 'trunk',
                          'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}],
            'evidence': {'scenes': records,
                         'limits': ['Callback-driven UI checks; no physical input. CleanUI vanilla mode has no supported search path.']}}


def _verify_mp(root, selection, issues):
    root = Path(root)
    expected = expected_scenes(selection)
    logs, scene_map, replica_map, peer_map = {}, {}, {}, {}
    outcomes = []
    for role in ('client1', 'client2'):
        path = root / (role + '-launch.log')
        if not path.is_file():
            issues.append('Missing ' + role + ' Host client log')
            logs[role], scene_map[role] = '', []
            outcomes.append({'actor': role, 'case': 'trunk', 'status': 'failed', 'reason': 'Missing client log'})
            continue
        text = path.read_text(errors='replace')
        logs[role] = text
        records = _records(text, 'RESULT', issues)
        scene_map[role] = records
        if [row.get('scene') for row in records] != expected:
            issues.append(role + ' missing, duplicate or out-of-order pinned-items scenes')
        for row in records:
            _verify_scene(row, issues, expected_item_count=6)
            if row.get('actor') != role or type(row.get('onlineId')) is not int or row.get('onlineId') < 0:
                issues.append(role + ' result has invalid actor or online ID')
            if row.get('mp') is not True or not _item_signature(row.get('itemSignature')):
                issues.append(role + ' result lacks valid MP replica identity')
        if not complete(selection, role, text) or MARKER + 'FAIL ' in text:
            issues.append(role + ' missing pinned-items completion or has a fixture failure')
        replicas = _records(text, 'REPLICA', issues)
        peers = _records(text, 'PEER', issues)
        if len(replicas) != 1:
            issues.append(role + ' must emit exactly one replica receipt')
        else:
            replica_map[role] = replicas[0]
        if [row.get('provider') for row in peers] != ['BetterContainers', 'organizedCategories_core']:
            issues.append(role + ' must emit ordered Better Containers and Organized Categories peer receipts')
        peer_map[role] = peers
        outcomes.append({'actor': role, 'case': 'trunk', 'status': 'passed', 'reason': ''})

    server_path = root / 'server-launch.log'
    if not server_path.is_file():
        issues.append('Missing Host server log')
        server_text = ''
    else:
        server_text = server_path.read_text(errors='replace')
    if server_text.count('[STARTUP_TEST] SERVER_READY') != 1:
        issues.append('Missing or duplicate Host server readiness')
    if MARKER + 'FAIL ' in server_text:
        issues.append('Host server reported a pinned-items fixture failure')
    authority = _records(server_text, 'AUTHORITY', issues)
    phases = ['initial', 'client1-done', 'client2-done']
    if [row.get('phase') for row in authority] != phases:
        issues.append('Host authority receipts missing or out of order')
    for row in authority:
        if (not isinstance(row.get('truckId'), str) or not row['truckId'].isdigit()
                or type(row.get('itemCount')) is not int or row['itemCount'] != 6
                or not _item_signature(row.get('itemSignature'))):
            issues.append('Invalid Host authority inventory receipt')

    if len(scene_map.get('client1', [])) == len(expected) and len(scene_map.get('client2', [])) == len(expected):
        starts = [scene_map[role][0] for role in ('client1', 'client2')]
        ids = [row.get('onlineId') for row in starts]
        if any(type(value) is not int or value < 0 for value in ids) or ids[0] == ids[1]:
            issues.append('Host clients must have distinct valid online IDs')
        targets = {
            role: {
                'BetterContainers': next((row.get('target') for row in scene_map[role]
                                          if row.get('scene') == 'startup-order'), None),
                'organizedCategories_core': next((row.get('target') for row in scene_map[role]
                                                   if row.get('scene') == 'organized-item-pin'), None),
            }
            for role in ('client1', 'client2')
        }
        if any(not isinstance(target, str) or not target
               for per_provider in targets.values() for target in per_provider.values()):
            issues.append('Missing startup pin target for cross-client probe')
        truck_ids = {str(row.get('truckId')) for role in ('client1', 'client2') for row in scene_map[role]}
        signatures = {row.get('itemSignature') for role in ('client1', 'client2') for row in scene_map[role]}
        online_ids = {row.get('onlineId') for role in ('client1', 'client2') for row in scene_map[role]}
        if len(truck_ids) != 1 or len(signatures) != 1 or len(online_ids) != 2:
            issues.append('Client scene receipts changed truck, inventory identity or online ID')
        for role in ('client1', 'client2'):
            own = scene_map[role][0]
            replica, peers = replica_map.get(role, {}), peer_map.get(role, [])
            other = 'client2' if role == 'client1' else 'client1'
            if (replica.get('actor') != role or type(replica.get('onlineId')) is not int
                    or replica.get('onlineId') != own.get('onlineId')
                    or str(replica.get('truckId')) != str(own.get('truckId'))
                    or type(replica.get('itemCount')) is not int or replica.get('itemCount') != 6
                    or replica.get('itemSignature') != own.get('itemSignature')):
                issues.append(role + ' replica receipt differs from its scene identity')
            for index, provider in enumerate(('BetterContainers', 'organizedCategories_core')):
                peer = peers[index] if index < len(peers) else {}
                if (peer.get('actor') != role or peer.get('pinner') != other
                        or peer.get('provider') != provider
                        or str(peer.get('truckId')) != str(own.get('truckId'))
                        or peer.get('target') != targets.get(other, {}).get(provider)
                        or peer.get('pinAbsent') is not True
                        or peer.get('itemSignature') != own.get('itemSignature')):
                    issues.append(role + ' ' + provider + ' peer pin-absence receipt is invalid')
        for row in authority:
            if (str(row.get('truckId')) not in truck_ids
                    or row.get('itemSignature') not in signatures or row.get('itemCount') != 6):
                issues.append('Host authority identity differs from client replicas')
    else:
        issues.append('Cannot cross-check network receipts without both complete scene sets')
    if issues:
        for outcome in outcomes:
            outcome.update(status='failed', reason='; '.join(issues))
    return {'outcomes': outcomes,
            'evidence': {'scenes': scene_map, 'replicas': replica_map, 'peer_probes': peer_map,
                         'authority': authority,
                         'limits': ['Real Host with two local clients; no dedicated-server coverage.']}}


def verify(root, selection, catalog):
    issues = []
    try:
        result = (_verify_mp(root, selection, issues) if selection['kind'] == 'mp'
                  else _verify_sp(root, selection, issues))
    except OSError as error:
        issues.append(str(error))
        result = {'outcomes': [{'actor': role, 'case': 'trunk', 'status': 'failed', 'reason': str(error)}
                               for role in (('client1', 'client2') if selection['kind'] == 'mp' else ('client1',))],
                  'evidence': {'scenes': []}}
    return {'issues': issues, **result}
