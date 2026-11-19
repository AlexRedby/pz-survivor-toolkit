"""Fail-closed contracts for the real producer/recovery/peer-race native fixture.

Receipt fragments below test parsers only and never constitute a native pass.
"""
import copy
from pathlib import Path
import sys
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / 'tools'))
from queue_checks import adapters
from queue_checks.adapters import generator_recovery as a


def selection(kind='sp', peer=False):
    return dict(suite=a.SUITE, kind=kind, mode='toolkit',
        cases=list(a.PEER_CASES) if peer else [case for case in a.CASES if case not in a.PEER_CASES],
        clients=2 if peer else 1, languages=['EN', 'RU'] if peer else ['EN'],
        mods=list(a.MODS), options={'mp_host': True} if kind == 'mp' else {})


def authority(case):
    output = case != 'new-primary-intent'
    return dict(case=case, authority=True, producer='ISCharacterScreen.onTrimBeard',
        type='Base.Generator', condition=73, fuel=7.5, sourceFavorite=True,
        outputFavorite=False if output else None, originalAbsent=True, decoyPresent=True,
        targetPresent=not output, ownerBothHands=case in ('auto-return', 'cancel-active', 'owner-pickup-first'),
        ownerHasRazor=case == 'peer-pickup', ownerHasReplacement=not output,
        beard='LongScruffy' if case == 'cancel-active' else 'Moustache', tailComplete=True,
        peerBothHands=case == 'peer-pickup', razorReturned=case in ('auto-return', 'cancel-active', 'owner-pickup-first'),
        razorInRoot=case not in ('auto-return', 'cancel-active', 'owner-pickup-first'), bagCanonical=True, originalId=10, razorId=11, replacementId=12,
        tailId=13, outputId=20 if output else None, ownerOnlineId=0, pickerOnlineId=1, peerStartedAt=10,
        decoyIndex=5, dropObserved=True, trimStarted=True)


def producer(case):
    kinds = ['ISInventoryTransferAction', 'ISEquipWeaponAction', 'ISTrimBeard', 'ISQueueActionsAction']
    if case != 'new-primary-intent': kinds.append('PZSurvivorToolkitGeneratorRecovery')
    if case in ('auto-return', 'cancel-active', 'owner-pickup-first'): kinds.append('ISInventoryTransferAction')
    kinds.append('ISReadABook')
    return dict(case=case, producer='ISCharacterScreen.onTrimBeard', nativeCallbacksSame=True,
        producerSameOperation=True, independentTail=True, trimProgress=True,
        canceled=case == 'cancel-active', explicitIntent=case == 'new-primary-intent',
        peerPickup=case in a.PEER_CASES, recoveryProgress=case != 'new-primary-intent',
        tailProgress=True, tailAfterCleanup=True, noP4=True,
        actions=[dict(type=kind, ref='action-' + str(i), native=True, progress=True,
            duration=300 if kind == 'ISTrimBeard' else 100 if kind == 'PZSurvivorToolkitGeneratorRecovery' else 60)
            for i, kind in enumerate(kinds)])


class GeneratorRecoveryTests(unittest.TestCase):
    def test_native_bank_supports_batched_sp_host_and_separate_real_peer(self):
        self.assertIs(adapters.get(a.SUITE), a)
        for kind in ('sp', 'mp'):
            a.validate(selection(kind))
        a.validate(selection('mp', peer=True))
        self.assertEqual([row['id'] for row in a.definitions()[a.SUITE]['cases']], a.CASES)

    def test_refuses_wrong_provider_mixed_peer_saved_world_and_wrong_topology(self):
        for mutate in [lambda s: s['mods'].append('P4TidyUpMeister'),
                       lambda s: s.update(cases=a.CASES),
                       lambda s: s.update(clients=2),
                       lambda s: s.update(cases=list(reversed(a.CASES[:-1]))),
                       lambda s: s['options'].update(world_template='old-world'),
                       lambda s: s.update(mode='native')]:
            row = selection(); mutate(row)
            with self.assertRaises(ValueError): a.validate(row)
        for mutate in [lambda s: s.update(kind='sp'), lambda s: s.update(clients=1),
                       lambda s: s['options'].pop('mp_host'), lambda s: s.update(languages=['EN'])]:
            row = selection('mp', peer=True); mutate(row)
            with self.assertRaises(ValueError): a.validate(row)

    def test_authority_requires_new_native_output_favorite_loss_and_exact_hands(self):
        for case in a.CASES:
            row = authority(case)
            self.assertEqual(a.result_errors(row, case, 'mp'), [])
            for key in ('condition', 'fuel', 'sourceFavorite', 'originalAbsent', 'decoyPresent',
                        'targetPresent', 'ownerBothHands', 'ownerHasRazor', 'tailComplete'):
                bad = copy.deepcopy(row); bad[key] = not bad[key]
                self.assertTrue(a.result_errors(bad, case, 'mp'), (case, key))
            if case != 'new-primary-intent':
                for mutate in [lambda r: r.update(outputId=r['originalId']),
                               lambda r: r.update(outputFavorite=True),
                               lambda r: r.pop('outputId')]:
                    bad = copy.deepcopy(row); mutate(bad)
                    self.assertTrue(a.result_errors(bad, case, 'mp'))
        row = authority('peer-pickup'); row['pickerOnlineId'] = row['ownerOnlineId']
        self.assertTrue(a.result_errors(row, 'peer-pickup', 'mp'))

    def test_readonly_target_observation_does_not_qualify_as_auto_recovery(self):
        for case in a.CASES:
            row = producer(case)
            self.assertEqual(a.evidence_errors(row, case), [])
            for key in ('nativeCallbacksSame', 'producerSameOperation', 'independentTail',
                        'trimProgress', 'recoveryProgress', 'tailProgress', 'tailAfterCleanup', 'noP4'):
                bad = copy.deepcopy(row); bad[key] = not bad[key]
                self.assertTrue(a.evidence_errors(bad, case), (case, key))
            if case != 'new-primary-intent':
                bad = copy.deepcopy(row)
                bad['actions'] = [action for action in bad['actions'] if action['type'] != 'PZSurvivorToolkitGeneratorRecovery']
                self.assertTrue(a.evidence_errors(bad, case))
                bad = copy.deepcopy(row)
                next(action for action in bad['actions'] if action['type'] == 'PZSurvivorToolkitGeneratorRecovery')['progress'] = False
                self.assertTrue(a.evidence_errors(bad, case))

    def test_auto_wire_contract_is_bound_to_exact_seeded_generator_and_borrowed_tool(self):
        evidence = producer('auto-return'); result = authority('auto-return')
        for action in evidence['actions']:
            if action['type'] == 'PZSurvivorToolkitGeneratorRecovery':
                action.update(sourceID=result['originalId'], toolID=result['razorId'], episode=1)
            if action['type'] == 'ISInventoryTransferAction': action['itemId'] = result['razorId']
        self.assertEqual(a.binding_errors(evidence, result), [])
        for key in ('sourceID', 'toolID', 'episode'):
            bad = copy.deepcopy(evidence)
            next(action for action in bad['actions'] if action['type'] == 'PZSurvivorToolkitGeneratorRecovery')[key] = 0
            self.assertTrue(a.binding_errors(bad, result), key)
        bad = copy.deepcopy(evidence)
        next(action for action in bad['actions'] if action['type'] == 'ISInventoryTransferAction')['itemId'] = result['originalId']
        self.assertTrue(a.binding_errors(bad, result))

    def test_absent_logs_cannot_pass_and_completion_rejects_duplicates(self):
        value = selection('mp', peer=True); value['cases'] = ['peer-pickup']
        with tempfile.TemporaryDirectory() as directory:
            result = a.verify(Path(directory), value, {})
        self.assertTrue(result['issues'])
        self.assertTrue(all(row['status'] == 'failed' for row in result['outcomes']))
        text = a.PREFIX + 'COMPLETE {"cases":["peer-pickup"]}\n'
        self.assertTrue(a.complete(value, 'client2', text))
        self.assertFalse(a.complete(value, 'client2', text + text))

    def test_opposite_live_pickup_orderings_require_native_overlap_and_correct_winner(self):
        for case, owner, peer in [
            ('peer-pickup', dict(recoveryStartedAt=20, recoveryProgressAt=21, recoveryFinishedAt=40),
             dict(startedAt=10, finishedAt=30, outputHeld=True)),
            ('owner-pickup-first', dict(recoveryStartedAt=10, recoveryProgressAt=11, recoveryFinishedAt=30),
             dict(startedAt=20, finishedAt=40, outputHeld=False))]:
            peer.update(case=case, type='ISTakeGenerator', duration=100, progress=True, native=True, normalProducer=True, progressDelta=0.01)
            self.assertEqual(a.peer_errors(peer, owner), [])
            bad = dict(peer, outputHeld=not peer['outputHeld'])
            self.assertTrue(a.peer_errors(bad, owner))
            bad = dict(peer, startedAt=owner['recoveryFinishedAt'] + 1)
            self.assertTrue(a.peer_errors(bad, owner))
            bad = dict(peer, progress=False)
            self.assertTrue(a.peer_errors(bad, owner))

    def test_fixture_uses_normal_producers_without_installing_or_completing_actions(self):
        client = (PROJECT / 'tests/native_queue/generator-recovery/client/ZZGeneratorRecovery.lua').read_text()
        self.assertIn('ISCharacterScreen.onTrimBeard(player,ids.targetBeard)', client)
        self.assertIn('ISInventoryPaneContextMenu.readItem', client)
        self.assertIn('peerAction=ISTakeGenerator:new(player,target)', client)
        self.assertNotIn('Razor.install(', client)
        self.assertNotIn(':complete(', client)
        self.assertIn('normal mod startup failed to install grooming restoration', client)
