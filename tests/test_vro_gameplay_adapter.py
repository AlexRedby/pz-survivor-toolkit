"""Strict native gameplay receipts cannot pass from completion markers alone."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.queue_checks.adapters import get
from tools.queue_checks.adapters import vro_gameplay as adapter

ROOT = Path(__file__).resolve().parents[1]


def selection(kind='sp', case='bank'):
    return dict(suite=adapter.SUITE, cases=[case], kind=kind, mode='toolkit', clients=1 if kind == 'sp' else 2,
                languages=['EN'] if kind == 'sp' else ['EN', 'RU'], mods=list(adapter.MODS), options=dict(pack_lock='/tmp/fixture-pack.lock.json',
                **({'mp_host': True} if kind == 'mp' else {}),
                **({'world_template': '/tmp/fixture-world'} if case == 'reload' else {})))


def repair():
    return dict(vehicleID=100, vehicleKey='repair', partID='EngineDoor', itemID=101, itemType='Base.EngineDoor1',
        condition=40, itemCondition=40, itemMax=100, hbr=0, metal=[dict(id=id, present=True, fullType='Base.SheetMetal') for id in (104, 105)],
        torch=dict(id=102, present=True, fullType='Base.BlowTorch', uses=10),
        mask=dict(id=103, present=True, fullType='Base.WeldingMask', condition=100),
        xp=dict(Mechanics=100, MetalWelding=200), levels=dict(Mechanics=4, MetalWelding=4))


def salvage():
    return dict(vehicleID=200, vehicleKey='salvage', removed=False, torchID=202, torchPresent=True, torchUses=10,
        torchContainerType='inventory', torchInRoot=True, primaryID=202, secondaryID=-1,
        maskID=103, maskWornID=103, metalWeldingXP=201, x=100, y=110, z=0, ground=[])


def world(observed, key):
    value = dict(vehicleID=observed['vehicleID'], vehicleKey=key, removed=observed.get('removed', False), ground=copy.deepcopy(observed.get('ground', [])))
    if not value['removed']:
        value.update({name: observed.get(name, 300 if name == 'itemID' else 0 if name == 'hbr' else 100)
                      for name in ('itemID', 'condition', 'itemCondition', 'hbr')})
    return value


def phase(name, index, before, after):
    key, mode = name.split('-')
    action = dict(mode=mode, vehicleID=after['vehicleID'], vehicleKey=key, before=copy.deepcopy(before), after=copy.deepcopy(after),
                  started=True, nativeDuration=280 if key == 'repair' else 1920, cancelled=mode == 'cancel', menuCallback=True)
    action.update(dict(recipeDuration=280) if key == 'repair' else dict(sourceDuration=1920, drops=after['ground'] if mode == 'complete' else [], luaActions=0, nativeActions=0, hasPath=False))
    return dict(phase=name, index=index, before=copy.deepcopy(before), after=copy.deepcopy(after), world=world(after, key), action=action)


def actor():
    return dict(primary=202, secondary=False, x=100.5, y=110.5, z=0, total=1000,
                xp={name: dict(xp=value, level=4) for name, value in [('Mechanics', 101), ('MetalWelding', 202)]},
                worn=[dict(id=9, location='base:torso1'), dict(id=103, location='base:hat')],
                items=[dict(id=9, fullType='Base.Shirt_FormalWhite'), dict(id=102, fullType='Base.BlowTorch'),
                       dict(id=103, fullType='Base.WeldingMask'), dict(id=202, fullType='Base.BlowTorch')])


def original_actor():
    value = actor()
    value.update(primary=False, worn=[dict(id=9, location='base:torso1')],
                 items=[dict(id=9, fullType='Base.Shirt_FormalWhite')], total=0, x=90.25, y=95.75)
    value['xp'] = {name: dict(xp=0, level=0) for name in ('Mechanics', 'MetalWelding')}
    return value


def observer_actor():
    value = original_actor()
    value.update(primary=802, x=80.5, y=109.75, total=25,
                 worn=[dict(id=803, location='mod:frontpack')],
                 items=[dict(id=802, fullType='Base.Hammer'), dict(id=803, fullType='Base.Bag_GolfBag')])
    value['xp']['Mechanics'] = dict(xp=25, level=1)
    return value


def bank(kind='sp'):
    first = repair(); repaired = copy.deepcopy(first)
    repaired.update(condition=76, itemCondition=76, hbr=1, metal=[dict(id=id, present=False) for id in (104, 105)])
    repaired['torch']['uses'] = 7; repaired['xp'] = dict(Mechanics=101, MetalWelding=201)
    second = salvage(); salvaged = copy.deepcopy(second)
    salvaged.update(removed=True, torchUses=0, metalWeldingXP=202, ground=[dict(id=301, fullType='Base.ScrapMetal')])
    phases = [phase('repair-cancel', 1, first, first), phase('repair-complete', 2, first, repaired),
              phase('salvage-cancel', 3, second, second), phase('salvage-complete', 4, second, salvaged)]
    authority = 'server' if kind == 'mp' else 'client1'
    events = {role: [] for role in (['server', 'client1', 'client2'] if kind == 'mp' else ['client1'])}
    for row in phases:
        events[authority].append(('AUTHORITY_AFTER', row))
        for role in (['client1', 'client2'] if kind == 'mp' else ['client1']):
            events[role].append(('PEER', dict(role=role, phase=row['phase'], index=row['index'], world=copy.deepcopy(row['world']))))
    checkpoint = dict(retainedForReload=True, actor=actor(), original=original_actor(), worlds=dict(repair=phases[1]['world'], salvage=phases[3]['world']),
                      owned=[dict(id=102, fullType='Base.BlowTorch'), dict(id=103, fullType='Base.WeldingMask'), dict(id=104, fullType='Base.SheetMetal'),
                             dict(id=105, fullType='Base.SheetMetal'), dict(id=202, fullType='Base.BlowTorch')])
    checkpoint['clientOriginals'] = dict(client1=original_actor())
    if kind == 'mp':
        checkpoint['clientOriginals']['client2'] = observer_actor()
    events[authority].append(('CHECKPOINT', checkpoint))
    for role in (['client1', 'client2'] if kind == 'mp' else ['client1']):
        if kind == 'sp':
            events[role].append(('SAVED_RETURN', dict(case='bank', role=role, saved=True, returned=True)))
        else:
            events[role].append(('CHECKPOINT_PEER', dict(role=role, retainedForReload=True)))
        events[role].append(('COMPLETE', dict(case='bank', role=role)))
    return events


def reload_events(kind='sp'):
    seed_logs = bank(kind)
    authority = 'server' if kind == 'mp' else 'client1'
    seed = adapter._bank(seed_logs, selection(kind))
    checkpoint = seed['checkpoint']
    worlds = copy.deepcopy(checkpoint['worlds'])
    worlds['repair']['vehicleID'] = 1100  # Native wire IDs can change across saves.
    restored = dict(role='authority', actor=copy.deepcopy(checkpoint['actor']), worlds=worlds, owned=checkpoint['owned'],
        resources=dict(repairTorch=dict(id=102, fullType='Base.BlowTorch', uses=7), salvageTorch=dict(id=202, fullType='Base.BlowTorch', uses=0),
                       mask=dict(id=103, fullType='Base.WeldingMask'), metal=[dict(id=id, present=False) for id in (104, 105)]))
    absent = {key: dict(vehicleKey=key, vehicleID=value['vehicleID'], removed=True, ground=[]) for key, value in worlds.items()}
    cleanup = dict(role='authority', restored=True, actor=copy.deepcopy(checkpoint['original']),
        vehicles=dict(removed=[dict(vehicleKey='repair', installedID=101, vehicleID=1100)]),
        items=dict(removedIds=[102, 103, 202], removalCalls=3, noticeAttempts=3 if kind == 'mp' else 0, recoveries=[]),
        ground=dict(publicationAttempts=1, removedObjects=1, publicationUncertain=False, recoveries=[], states=[dict(index=0, status='removed')]), worlds=absent)
    events = {role: [] for role in seed_logs}
    events[authority].append(('RELOADED', restored))
    for role in (['client1', 'client2'] if kind == 'mp' else ['client1']):
        events[role].append(('RELOADED', dict(role=role, worlds=copy.deepcopy(worlds))))
    events[authority].append(('CLEANUP', cleanup))
    for role in (['client1', 'client2'] if kind == 'mp' else ['client1']):
        events[role].append(('CLEANUP', dict(role=role, worlds=copy.deepcopy(absent),
            actor=copy.deepcopy(checkpoint['clientOriginals'][role]), restored=True, ownedAbsent=True)))
        if kind == 'sp':
            events[role].append(('SAVED_RETURN', dict(case='reload', role=role, saved=True, returned=True)))
        events[role].append(('COMPLETE', dict(case='reload', role=role)))
    return events, seed


def logs(events):
    return {role: ''.join(adapter.MARKER + event + ' ' + json.dumps(row) + '\n' for event, row in rows) for role, rows in events.items()}


def verify(events, kind='sp', case='bank'):
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        for role, text in logs(events).items():
            (root / (role + '-launch.log')).write_text(text)
        return adapter.verify(root, selection(kind, case), {})


class VROGameplayAdapterTests(unittest.TestCase):
    def test_registered_sp_and_host_bank_require_exact_effects_and_peers(self):
        self.assertIs(get('vro-gameplay'), adapter)
        for kind in ('sp', 'mp'):
            adapter.validate(selection(kind))
            self.assertEqual([], verify(bank(kind), kind)['issues'])
        for path, value in [((0, 'after', 'condition'), 77), ((0, 'action', 'menuCallback'), False),
                            ((2, 'action', 'started'), False), ((3, 'action', 'nativeDuration'), 1),
                            ((1, 'after', 'itemID'), 999), ((3, 'after', 'torchUses'), 1),
                            ((3, 'after', 'metalWeldingXP'), 201), ((3, 'after', 'ground'), [])]:
            with self.subTest(path=path):
                events = bank(); phases = [row for event, row in events['client1'] if event == 'AUTHORITY_AFTER']
                target = phases[path[0]]
                for key in path[1:-1]:
                    target = target[key]
                target[path[-1]] = value
                self.assertTrue(verify(events)['issues'])

    def test_missing_duplicate_reordered_and_malformed_receipts_fail(self):
        for event in ('AUTHORITY_AFTER', 'PEER', 'CHECKPOINT', 'SAVED_RETURN', 'COMPLETE'):
            for mutation in ('missing', 'duplicate'):
                events = bank(); rows = events['client1']; index = next(i for i, row in enumerate(rows) if row[0] == event)
                if mutation == 'missing':
                    rows.pop(index)
                else:
                    rows.insert(index, copy.deepcopy(rows[index]))
                with self.subTest(event=event, mutation=mutation):
                    self.assertTrue(verify(events)['issues'])
        events = bank(); events['client1'].reverse(); self.assertTrue(verify(events)['issues'])
        events = bank('mp'); events['client2'][0][1]['world']['vehicleID'] = 999
        self.assertTrue(verify(events, 'mp')['issues'])
        self.assertFalse(adapter.complete(selection(), 'client1', adapter.MARKER + 'COMPLETE {bad}\n'))
        self.assertFalse(adapter.complete(selection(), 'client1', adapter.MARKER + 'COMPLETE {"case":"bank","role":"client1","role":"client1"}\n'))

    def test_checkpoint_requires_exact_peer_originals_and_matching_authority_actor(self):
        for kind in ('sp', 'mp'):
            authority = 'server' if kind == 'mp' else 'client1'
            for mutation in ('missing', 'wrong_roles', 'authority_position', 'authority_slot', 'owned_original'):
                with self.subTest(kind=kind, mutation=mutation):
                    events = bank(kind)
                    checkpoint = next(row for name, row in events[authority] if name == 'CHECKPOINT')
                    if mutation == 'missing':
                        checkpoint.pop('clientOriginals')
                    elif mutation == 'wrong_roles':
                        if kind == 'mp':
                            checkpoint['clientOriginals'].pop('client2')
                        else:
                            checkpoint['clientOriginals']['client2'] = observer_actor()
                    elif mutation == 'authority_position':
                        checkpoint['clientOriginals']['client1']['x'] += .25
                    elif mutation == 'authority_slot':
                        checkpoint['clientOriginals']['client1']['worn'][0]['location'] = 'base:back'
                    else:
                        checkpoint['clientOriginals']['client1']['items'].append(dict(id=102, fullType='Base.BlowTorch'))
                    self.assertTrue(verify(events, kind)['issues'])

    def test_boolean_numeric_spoofs_and_forwarded_markers_fail(self):
        events = bank(); events['client1'][0][1]['index'] = True
        self.assertTrue(verify(events)['issues'])
        text = logs(bank())['client1']
        self.assertFalse(adapter.complete(selection(), 'client1', 'SERVER: ' + text.replace('\n', '\nSERVER: ')))
        self.assertFalse(adapter.complete(selection(), 'client1', '[CoopMaster] ' + text.replace('\n', '\n[CoopMaster] ')))

    def test_selection_rejects_partial_pack_wrong_roles_and_unsealed_reload(self):
        for update in ({'mods': adapter.MODS[:-1]}, {'clients': 2}, {'mode': 'unknown'}, {'cases': ['bank', 'reload']},
                       {'options': {}}, {'options': dict(pack_lock='relative.json')}, {'languages': ['RU']}):
            with self.subTest(update=update), self.assertRaises(ValueError):
                adapter.validate(dict(selection(), **update))
        value = selection('mp'); value['options']['mp_host'] = False
        with self.assertRaises(ValueError):
            adapter.validate(value)

    def test_native_control_keeps_the_same_pack_roles_and_effect_requirements(self):
        for kind in ('sp', 'mp'):
            value = selection(kind)
            value['mode'] = 'native'
            adapter.validate(value)
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                for role, text in logs(bank(kind)).items():
                    (root / (role + '-launch.log')).write_text(text)
                self.assertEqual([], adapter.verify(root, value, {})['issues'])
        value = selection(case='reload'); value['options'].pop('world_template')
        with self.assertRaises(ValueError):
            adapter.validate(value)

    def test_staging_preserves_common_startup_and_owns_sp_exit_guard_reload(self):
        for kind, case in [('sp', 'bank'), ('sp', 'reload'), ('mp', 'bank')]:
            with self.subTest(kind=kind, case=case), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                runtime = {'roles': {role: {'cache': str(root / role)} for role in (['client1'] if kind == 'sp' else ['server', 'client1', 'client2'])}}
                adapter.stage(ROOT, root, None, None, selection(kind, case), {}, runtime)
                lua = root / 'client1/mods/ActionQueueTest/42/media/lua'
                startup = (lua / 'client/ZZStartup.lua').read_text()
                self.assertTrue((lua / 'shared/QueueEnergyPlacement.lua').is_file())
                self.assertIn("case='" + case + "'", (lua / 'shared/QueueVROGameplayConfig.lua').read_text())
                if kind == 'mp':
                    self.assertEqual(startup, (ROOT / 'tests/native_queue/startup/client/ZZStartup.lua').read_text())
                elif case == 'bank':
                    self.assertLess(startup.index("getFileReader('vro-gameplay-exit.txt'"), startup.index('if started and isIngameState()'))
                    self.assertIn('MainScreen.instance.createWorld=true', startup)
                else:
                    self.assertLess(startup.index("getFileReader('vro-gameplay-exit.txt'"), startup.index('if started and isIngameState()'))
                    self.assertIn("MainScreen.continueLatestSave('Sandbox','QueueStartup')", startup)
                    self.assertNotIn('MainScreen.instance.createWorld=true', startup)

    def test_reload_compares_saved_identities_paid_resources_and_cleanup_journals(self):
        for kind in ('sp', 'mp'):
            events, seed = reload_events(kind)
            with self.subTest(kind=kind), patch.object(adapter, '_seed', return_value=seed):
                self.assertEqual([], verify(events, kind, 'reload')['issues'])
        for event, path, value in [('RELOADED', ('worlds', 'repair', 'itemID'), 999),
                                    ('RELOADED', ('resources', 'repairTorch', 'uses'), 10),
                                    ('RELOADED', ('actor', 'xp', 'Mechanics', 'xp'), 0),
                                    ('CLEANUP', ('items', 'removedIds'), [102, 103]),
                                    ('CLEANUP', ('items', 'noticeAttempts'), 1),
                                    ('CLEANUP', ('ground', 'publicationUncertain'), True),
                                    ('CLEANUP', ('vehicles', 'removed'), []),
                                    ('CLEANUP', ('actor', 'x'), 90.5)]:
            events, seed = reload_events()
            row = next(row for name, row in events['client1'] if name == event and row.get('role') == 'authority')
            for key in path[:-1]:
                row = row[key]
            row[path[-1]] = value
            with self.subTest(event=event, path=path), patch.object(adapter, '_seed', return_value=seed):
                self.assertTrue(verify(events, case='reload')['issues'])

    def test_reload_rejects_missing_peer_cleanup_and_seedless_markers(self):
        events, seed = reload_events('mp')
        events['client2'] = [row for row in events['client2'] if row[0] != 'CLEANUP']
        with patch.object(adapter, '_seed', return_value=seed):
            self.assertTrue(verify(events, 'mp', 'reload')['issues'])
        events, _ = reload_events()
        self.assertTrue(verify(events, case='reload')['issues'])
        text = logs(events)['client1']
        text = '\n'.join(line for line in text.splitlines() if 'SAVED_RETURN' not in line)
        self.assertFalse(adapter.complete(selection(case='reload'), 'client1', text))

    def test_reload_requires_each_peer_actual_owned_absence_and_exact_original_actor(self):
        for kind in ('sp', 'mp'):
            for role in (['client1', 'client2'] if kind == 'mp' else ['client1']):
                for mutation in ('old_envelope', 'retained_torch', 'owned_flag', 'restored_flag',
                                 'moved_position', 'moved_original_item', 'changed_slot', 'changed_xp', 'other_actor'):
                    with self.subTest(kind=kind, role=role, mutation=mutation):
                        events, seed = reload_events(kind)
                        peer = next(row for name, row in events[role] if name == 'CLEANUP' and row['role'] == role)
                        if mutation == 'old_envelope':
                            for key in ('actor', 'restored', 'ownedAbsent'):
                                peer.pop(key)
                        elif mutation == 'retained_torch':
                            peer['actor']['items'].append(dict(id=102, fullType='Base.BlowTorch'))
                        elif mutation == 'owned_flag':
                            peer['ownedAbsent'] = False
                        elif mutation == 'restored_flag':
                            peer['restored'] = 1
                        elif mutation == 'moved_position':
                            peer['actor']['x'] += .25
                        elif mutation == 'moved_original_item':
                            peer['actor']['items'].pop()
                        elif mutation == 'changed_slot':
                            peer['actor']['worn'][0]['location'] = 'base:back'
                        elif mutation == 'changed_xp':
                            peer['actor']['xp']['Mechanics']['xp'] += 1
                        else:
                            peer['actor'] = actor()
                        with patch.object(adapter, '_seed', return_value=seed):
                            self.assertTrue(verify(events, kind, 'reload')['issues'])

    def test_reload_retains_peer_actor_evidence_and_accepts_semantic_inventory_order(self):
        events, seed = reload_events('mp')
        peer = next(row for name, row in events['client2'] if name == 'CLEANUP')
        peer['actor']['items'].reverse()
        with patch.object(adapter, '_seed', return_value=seed):
            report = verify(events, 'mp', 'reload')
        self.assertEqual([], report['issues'])
        self.assertEqual(peer, report['evidence']['peerCleanups']['client2'])
        self.assertNotEqual(seed['checkpoint']['clientOriginals']['client1'], peer['actor'])


if __name__ == '__main__':
    unittest.main()
