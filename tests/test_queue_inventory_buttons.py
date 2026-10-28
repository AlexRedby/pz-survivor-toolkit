import copy
import json
import unittest

from tools.queue_checks.adapters import base_walking_profile as profile


class ButtonExperimentChecks(unittest.TestCase):
    def setUp(self):
        self.row = dict(kind='inventory-button-checks', playerNum=0, clock='baseWalkingExperimentClockMs',
            callsPerBatch=256, rounds=5, warmupPerMode=8, totalCalls=2560, restoreConflicts=0, sourceLimit=128,
            defaultSources={key: '/game/media/lua/client/ISUI/ISUIElement.lua'
                            for key in ('setX', 'setY', 'getKeepOnScreen', 'onResize')},
            timingMethod='sum of complete refreshBackpacks callback intervals; guard branch/counters included; assertions outside timing',
            itemIdentityCheck='before probe, after each warmup/mode batch, and cleanup; geometry/UI identities before and after every callback',
            guardedButtons=1, checks={key: True for key in
                ('orderedIdentities', 'geometry', 'parentsAndChildren', 'selection', 'restored')},
            limits={key: False for key in ('movement', 'resize', 'nestedReentry', 'remoteMutation',
                'classHooks', 'paneHooks', 'inventoryMutation', 'worldMutation')},
            workload=dict(buttons=1, pooledButtons=0, sources={'1': dict(button='button', container='source',
                kind='floor', items=2, luaParent='panel', nativeParent='nativePanel',
                geometry=dict(x=4, y=4, width=32, height=32))}), batches={})
        self.row['limits'].update(testOnly=True, assumesGeometryMirror=True, discoveryAndEventsUnchanged=True)
        order = ('candidate', 'control', 'control', 'candidate', 'candidate',
                 'control', 'control', 'candidate', 'candidate', 'control')
        for index, mode in enumerate(order, 1):
            candidate = mode == 'candidate'
            self.row['batches'][str(index)] = dict(mode=mode, round=(index+1)//2, calls=256,
                elapsedMs=300.25 if candidate else 310.5, calledSetters=0 if candidate else 512,
                skippedSetters=512 if candidate else 0, modelUnchanged=True, geometryMatched=True)

    def text(self):
        return profile.PREFIX + 'INVENTORY_BUTTON_CHECKS ' + json.dumps(self.row)

    def test_floating_durations_and_no_speedup_requirement(self):
        self.assertEqual(profile._button_checks(self.text())['median_batch_ms'],
                         dict(candidate=300.25, control=310.5))
        for batch in self.row['batches'].values():
            if batch['mode'] == 'candidate':
                batch['elapsedMs'] = 400.0
        self.assertEqual(profile._button_checks(self.text())['median_batch_ms']['candidate'], 400.0)

    def test_missing_or_duplicate_receipt_fails(self):
        for text in ('', self.text() + '\n' + self.text()):
            with self.assertRaisesRegex(ValueError, 'unique'):
                profile._button_checks(text)

    def test_unproven_model_or_scope_cannot_pass(self):
        original = copy.deepcopy(self.row)
        for section, key, value in (('checks', 'restored', False), ('checks', 'parentsAndChildren', False),
                                   ('limits', 'assumesGeometryMirror', False), ('limits', 'resize', True)):
            self.row = copy.deepcopy(original)
            self.row[section][key] = value
            with self.assertRaises(ValueError):
                profile._button_checks(self.text())

    def test_missing_identity_or_geometry_fails(self):
        self.row['workload']['sources']['1']['geometry']['x'] = float('nan')
        with self.assertRaisesRegex(ValueError, 'source witness'):
            profile._button_checks(self.text())
        self.row['workload']['sources'] = {}
        with self.assertRaisesRegex(ValueError, 'identities'):
            profile._button_checks(self.text())

    def test_missing_batch_changed_counter_or_geometry_fails(self):
        original = copy.deepcopy(self.row)
        for key, value in (('calledSetters', 1), ('skippedSetters', 0), ('geometryMatched', False),
                           ('elapsedMs', float('inf')), ('calls', 255)):
            self.row = copy.deepcopy(original)
            self.row['batches']['1'][key] = value
            with self.assertRaises(ValueError):
                profile._button_checks(self.text())
        self.row = original
        del self.row['batches']['1']
        with self.assertRaisesRegex(ValueError, 'batches missing'):
            profile._button_checks(self.text())


if __name__ == '__main__':
    unittest.main()
