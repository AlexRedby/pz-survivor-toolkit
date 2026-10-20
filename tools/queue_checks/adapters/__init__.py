"""Suite-specific setup and evidence checks around the shared native lifecycle."""
from collections import Counter
from importlib import import_module

MODULES = {'vehicle-lights': 'vehicle_lights', 'vehicle-doors': 'vehicle_doors', 'fitness': 'fitness', 'vehicle-wishlist': 'vehicle_wishlist', 'pinned-items': 'pinned_items', 'startup': 'startup', 'basement-hall': 'basement_hall', 'fire': 'fire', 'engine': 'engine', 'engine-peers': 'engine', 'craft': 'craft', 'equipment': 'equipment', 'animal-fixes': 'animal_fixes', 'crafting-plans': 'craft_wishlist', 'shared-wishlist': 'craft_wishlist',
           'craft-ui': 'craft_ui', 'fluid': 'fluid', 'food': 'food', 'inventory-grab': 'inventory_grab', 'forge': 'forge',
           'container-configuration': 'container_configuration',
           'smart-deposit': 'auxiliary',
           'inventory-tooltips': 'auxiliary',
           'video-recording': 'auxiliary', 'item-tags': 'auxiliary', 'inventory-presentation': 'auxiliary', 'quartermaster-presets': 'quartermaster', 'quartermaster-transfers': 'quartermaster', 'quartermaster-distribution': 'quartermaster_distribution', 'quartermaster-crafting': 'quartermaster_crafting', 'animal-trailer': 'auxiliary',
           'wooden_cart_motion': 'carts', 'wooden_cart_multiplayer': 'carts',
           'shelf-book-tv': 'shelf_book_tv'}


def get(suite):
    if suite == 'health' or suite not in MODULES:
        return None
    return import_module('.' + MODULES[suite], __name__)


def definitions():
    result = {}
    for name in dict.fromkeys(MODULES.values()):
        result.update(import_module('.' + name, __name__).definitions())
    return result


def roles(selection, server=True):
    clients = ['client' + str(i + 1) for i in range(selection.get('clients', 2 if selection['kind'] == 'mp' else 1))]
    return (['server'] if server and selection['kind'] == 'mp' else []) + clients


def functional(root, selection, catalog):
    try:
        value = get(selection['suite']).verify(root, selection, catalog)
    except Exception as error:  # A verifier failure must not hide the full native log audit.
        value = {'issues': ['Suite verifier ' + type(error).__name__ + ': ' + str(error)], 'outcomes': [
            {'actor': role, 'case': case, 'status': 'failed', 'reason': str(error)}
            for role in roles(selection, False) for case in selection['cases']]}
    issues, outcomes = list(value['issues']), value['outcomes']
    expected = [(role, case) for role in roles(selection, False) for case in selection['cases']]
    if [(row.get('actor'), row.get('case')) for row in outcomes] != expected:
        issues.append('Adapter outcomes missing, duplicated or out of order')
    specs = {case['id']: case for case in catalog['suites'][selection['suite']]['cases']}
    coverage, clients = [], {}
    for role in roles(selection, False):
        counts = Counter()
        for row in outcomes:
            if row.get('actor') != role:
                continue
            identifier, status = row.get('case'), row.get('status')
            if identifier not in specs or status not in ('passed', 'failed', 'skipped', 'captured'):
                issues.append(role + ': unknown case/status'); continue
            spec = specs[identifier]
            if selection['kind'] not in spec['kinds'] or selection['mode'] not in spec.get('modes', ['toolkit', 'native']):
                issues.append(role + ': unsupported kind/mode')
            if status == 'skipped' and not row.get('reason'):
                issues.append(role + ': skip without reason')
            if status == 'captured' and spec['capability'] != 'capture':
                issues.append(role + ': capture cannot replace a functional pass')
            counts[status] += 1
            coverage.append(dict(row, suite=selection['suite'], kind=selection['kind'], mode=selection['mode'],
                                 producer=spec['producer'], capability=spec['capability']))
        if counts['failed']:
            issues.append(role + ': failed scenarios')
        clients[role] = dict(counts)
        path = root / (role + '-launch.log')
        text = path.read_text(errors='replace') if path.is_file() else ''
        for marker in ('VOICE_DISABLED', 'DISPLAY_READY', 'PREFLIGHT_COMPLETE',
                       'NATIVE_CONNECTED' if selection['kind'] == 'mp' else 'TRUE_SP'):
            if '[QUEUE_TEST] ' + marker not in text:
                issues.append(role + ': missing readiness marker ' + marker)
    status = 'failed' if issues else 'captured' if any(row['status'] == 'captured' for row in coverage) else 'passed'
    return {'status': status, 'issues': issues, 'clients': clients, 'evidence': value.get('evidence')}, coverage
