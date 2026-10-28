"""Causal negative mutations for the opted-in native singleton trim recovery bank."""
import copy
import json
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import grooming_recovery as a
from queue_checks import adapters


class GroomingRecoveryTests(unittest.TestCase):
    def selection(self, kind='mp', mode='toolkit'):
        return dict(suite='grooming-recovery', cases=list(a.CASES), kind=kind, mode=mode, clients=1,
                    languages=['EN'], mods=list(a.MODS), options=dict(grooming_recovery=True, **({'mp_host': True} if kind == 'mp' else {})))

    def evidence(self, case='pending-restore', kind='mp', mode='toolkit'):
        enabled = mode == 'toolkit'
        spec = dict(case=case, mode=mode, actor=0, initialBeard='LongScruffy', targetBeard='Moustache', duration=300,
                    razor=dict(id=101, type='Base.Razor'), front=dict(id=102, type='Base.BookCarpentry1', total=220, initial=217),
                    tail=dict(id=103, type='Base.BookCooking1', total=220, initial=219))
        seed = dict(case=case, male=True,
                    items=[dict(id=spec[n]['id'], type=spec[n]['type'], container='root', condition=10, favorite=n == 'razor', count=1) for n in ('razor', 'front', 'tail')],
                    worn=[], hands=dict(primary=dict(id=101, type='Base.Razor', root=True, sameReference=True, equipParent=True, container='root'), secondary=False),
                    appearance=dict(model='Long', nonAttached=False, beardModel='LongScruffy', color=dict(r=.2, g=.4, b=.6), beardColor=dict(r=.6, g=.4, b=.2)),
                    books={n: dict(id=spec[n]['id'], type=spec[n]['type'], root=True, total=220, pages=spec[n]['initial'], characterPages=spec[n]['initial']) for n in ('front', 'tail')})
        spec['baseline'] = copy.deepcopy(seed)
        final = a.expected(spec, enabled)
        roles = ['trim', 'tail'] if case == 'active-denied' else ['front', 'trim', 'tail']
        def steps(generation, names=None):
            names = roles if names is None else names
            return [dict(role=n, type='ISTrimBeard' if n == 'trim' else 'ISQueueActionsAction' if generation else 'ISReadABook',
                         token=10 + generation * 3 + roles.index(n), itemId=spec['razor' if n == 'trim' else n]['id'],
                         allocated=n == names[0]) for n in names]
        count = 3 if enabled and case == 'pending-restore' else 1
        cancellations, recoveries = [], []
        receipt = dict(kind='ISTrimBeard', transaction=1, token='12345678-1234-1234-1234-123456789abc', state='started')
        for i in range(count):
            boundary = dict(role='trim' if case == 'active-denied' else 'front', started=True, progress=True, delta=.03 if case == 'active-denied' else .987,
                            trimUnallocated=case != 'active-denied', startedReceipt=copy.deepcopy(receipt) if kind == 'mp' and case == 'active-denied' else False)
            old_steps = steps(i)
            if i: old_steps[0]['type'] = 'ISReadABook'
            cancellations.append(dict(generation=i, entrypoint='ISTimedActionQueue.clear', steps=old_steps, before=copy.deepcopy(seed),
                                      nativeCount=1, boundary=boundary, oldTokens=[dict(id=s['token'], cancelled=True) for s in old_steps], drained=True, movementStopped=True))
            r = dict(available=False, restored=False, historyAbsent=True)
            if enabled:
                r = dict(id=i + 1, count=1 if case == 'active-denied' else 3, skipped=1 if case == 'active-denied' else 0,
                         reason='started_operation' if case == 'active-denied' else False, available=case != 'lost-tool', previewPure=True,
                         generation=i + 1, staleRejected=True, restored=case != 'lost-tool', historyAbsent=case != 'lost-tool')
                if case == 'lost-tool': r['refusedWithoutEffects'] = True
                else: r.update(duplicateRejected=True, steps=steps(i + 1, ['tail'] if case == 'active-denied' else roles))
            recoveries.append(r)
        starts = (['trim:0'] + (['tail:1'] if enabled else []) if case == 'active-denied'
                  else ['front:0'] + (['front:1', 'front:2', 'front:3', 'trim:3', 'tail:3'] if enabled and case == 'pending-restore' else []))
        names = [(n, 0) for n in roles]
        if enabled and case == 'pending-restore': names += [('trim', 1), ('trim', 2), ('trim', 3), ('front', 1), ('front', 2), ('front', 3), ('tail', 3)]
        if enabled and case == 'active-denied': names += [('tail', 1)]
        commands, acks = [], []
        for name, gen in names:
            started = name + ':' + str(gen) in starts
            command = dict(role=name, generation=gen, type='ISTrimBeard' if name == 'trim' else 'ISReadABook',
                           itemId=spec['razor' if name == 'trim' else name]['id'], token=10 + gen * 3 + roles.index(name),
                           duration=300 if name == 'trim' else 79200, started=started, progress=started,
                           cancelled=gen == 0 or case == 'pending-restore' and gen < 3, nativeSource=True, callbacksIntact=True)
            if started:
                command.update(effectiveDuration=command['duration'], nativeDurationBefore=command['duration'], nativeDurationAfter=command['duration'],
                               durationSampleBefore=10, durationSampleAfter=20, allocatedAt=20, startedAt=30, durationSamples=2, nativeRef='native:1')
            if kind == 'mp' and name == 'trim' and started:
                command['ack'] = copy.deepcopy(receipt)
                if gen == 3: command['ack']['state'] = 'completed'
                for state in (['started', 'completed'] if gen == 3 else ['started']):
                    acks.append(dict(case=case, generation=gen, kind=receipt['kind'], transaction=receipt['transaction'], token=receipt['token'], state=state))
            commands.append(command)
        row = dict(event='case', suite='grooming-recovery', id=case, actor='client1', kind=kind, mode=mode, status='passed', ids=copy.deepcopy(spec),
                   input=copy.deepcopy(seed), authorityBaseline=copy.deepcopy(seed), removed=copy.deepcopy(final) if case == 'lost-tool' else False,
                   client=copy.deepcopy(final), server=copy.deepcopy(final), commands=commands, starts=starts, cancellations=cancellations, recoveries=recoveries,
                   admission=dict(producer='ISCharacterScreen.onTrimBeard', target='Moustache', initial='LongScruffy', singleton=True,
                                  alreadyHeld=True, exactRootTool=True, preparationCount=0, sourceBound=True, queue=steps(0, roles[:-1])),
                   queueIdle=True, settleMilliseconds=1000, completionProof='sealed-native-outcome-and-authority-effects' if kind == 'mp' else 'native-authority-effects')
        return [row, spec, seed, copy.deepcopy(final) if case == 'lost-tool' else None, final, acks]

    def check(self, evidence, selection=None):
        row, spec, seed, removed, final, acks = evidence
        return a.check_case(row, row['id'], selection or self.selection(), spec, seed, removed, final, acks)

    def test_all_four_controls_three_cases(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                s = self.selection(kind, mode); a.validate(s)
                for case in a.CASES:
                    with self.subTest(kind=kind, mode=mode, case=case): self.assertEqual(self.check(self.evidence(case, kind, mode), s), [])

    def test_causal_mutations_fail_closed(self):
        mutations = {
            'wrong exact tool condition': lambda r: r['client']['items'][0].update(condition=9),
            'wrong favorite': lambda r: r['client']['items'][0].update(favorite=False),
            'tool duplicated': lambda r: r['client']['items'].append(copy.deepcopy(r['client']['items'][0])),
            'tool root drift': lambda r: r['client']['items'][0].update(container=102),
            'tool ID drift': lambda r: r['client']['items'][0].update(id=500),
            'wrong primary reference': lambda r: r['client']['hands']['primary'].update(sameReference=False),
            'wrong equip parent': lambda r: r['client']['hands']['primary'].update(equipParent=False),
            'appearance drift': lambda r: r['client']['appearance']['beardColor'].update(r=.7),
            'trim never completed': lambda r: r['client']['appearance'].update(beardModel='LongScruffy'),
            'authority effects differ': lambda r: r['server']['appearance'].update(beardModel='LongScruffy'),
            'unknown extra item': lambda r: r['client']['items'].append(dict(id=500, type='Base.Razor', container='root', condition=10, favorite=True, count=1)),
            'tail did not finish': lambda r: r['client']['books']['tail'].update(pages=219, characterPages=219),
            'menu bypass': lambda r: r['admission'].update(producer='ISTrimBeard.new'),
            'prep added': lambda r: r['admission'].update(preparationCount=1),
            'pending trim allocated': lambda r: r['recoveries'][0]['steps'][1].update(allocated=True),
            'missing repeat': lambda r: r['recoveries'].pop(1),
            'reader did not advance native time': lambda r: r['cancellations'][0]['boundary'].update(delta=217/220),
            'reader checkpoint advanced': lambda r: r['cancellations'][0]['boundary'].update(delta=218/220),
            'repeated reader boundary absent': lambda r: r['cancellations'][1].update(boundary=False),
            'native Java debt': lambda r: r['cancellations'][0].update(drained=False),
            'old token reused': lambda r: r['recoveries'][-1]['steps'][1].update(token=11),
            'intermediate token reused': lambda r: r['recoveries'][-1]['steps'][1].update(token=14),
            'old token live': lambda r: r['cancellations'][0]['oldTokens'][0].update(cancelled=False),
            'duplicate accepted': lambda r: r['recoveries'][0].update(duplicateRejected=False),
            'stale accepted': lambda r: r['recoveries'][0].update(staleRejected=False),
            'history reused': lambda r: r['recoveries'][1].update(id=1),
            'started trim omitted': lambda r: r['starts'].remove('trim:3'),
            'trim start repeated': lambda r: r['starts'].append('trim:3'),
            'native receipt omitted': lambda r: r['commands'][5].pop('ack'),
            'short native duration': lambda r: r['commands'][5].update(effectiveDuration=1),
            'native callback changed': lambda r: r['commands'][5].update(callbacksIntact=False),
            'native command duplicate': lambda r: r['commands'].append(copy.deepcopy(r['commands'][5])),
            'wrong proof claim': lambda r: r.update(completionProof='exact-server-callback-count'),
        }
        for label, mutation in mutations.items():
            with self.subTest(label=label):
                evidence = self.evidence(); mutation(evidence[0]); self.assertTrue(self.check(evidence))

    def test_raw_receipt_mutations(self):
        for mutation in (lambda rows: rows.pop(), lambda rows: rows.append(copy.deepcopy(rows[-1])), lambda rows: rows.reverse(), lambda rows: rows[0].update(token='foreign')):
            evidence = self.evidence(); mutation(evidence[-1]); self.assertTrue(self.check(evidence))

    def test_lost_tool_and_started_trim_refusals(self):
        for case, mutate in [('lost-tool', lambda r: r['recoveries'][0].update(restored=True)),
                             ('lost-tool', lambda r: r.update(removed=False)),
                             ('lost-tool', lambda r: r['client']['items'].append(copy.deepcopy(r['input']['items'][0]))),
                             ('active-denied', lambda r: r['recoveries'][0].update(count=2, skipped=0)),
                             ('active-denied', lambda r: r['recoveries'][0]['steps'].append(dict(role='trim', type='ISTrimBeard', itemId=101, token=100, allocated=False))),
                             ('active-denied', lambda r: r['cancellations'][0]['boundary'].update(startedReceipt=False)),
                             ('active-denied', lambda r: r['client']['appearance'].update(beardModel='Moustache'))]:
            with self.subTest(case=case):
                evidence = self.evidence(case); mutate(evidence[0]); self.assertTrue(self.check(evidence))

    def test_disabled_controls_never_restore(self):
        for case in a.CASES:
            evidence = self.evidence(case, mode='native'); evidence[0]['recoveries'][0]['restored'] = True
            self.assertTrue(self.check(evidence, self.selection(mode='native')))

    def test_admission_requires_ordered_opt_in_full_pack(self):
        for patch in (dict(options={}), dict(cases=list(reversed(a.CASES))), dict(cases=list(a.CASES[:2])), dict(clients=2), dict(mods=['PZSurvivorToolkit']),
                      dict(languages=['RU']), dict(options=dict(grooming_recovery=True)), dict(options=dict(grooming_recovery=True, mp_host=True, world_template='/tmp/old'))):
            with self.subTest(patch=patch):
                selection = self.selection(); selection.update(patch)
                with self.assertRaises(ValueError): a.validate(selection)

    def logs(self, kind='mp', mode='toolkit'):
        client, authority = [], []
        client.append('[QUEUE_CHECK] ' + json.dumps(dict(suite='grooming-recovery', event='setup', cases=list(a.CASES), nativeDurations=True, queueEnabled=mode == 'toolkit', blocker='native-reader-three-pages')))
        for case in a.CASES:
            evidence = self.evidence(case, kind, mode); row, spec, seed, removed, final, acks = evidence
            client.append('[QUEUE_CHECK] ' + json.dumps(row))
            for marker, value in [('PREPARED', spec), ('BASELINE', seed), ('VERIFIED', final)]: authority.append(a.PREFIX + marker + ' ' + json.dumps(value))
            if removed: authority.append(a.PREFIX + 'REMOVED ' + json.dumps(removed))
            client.extend(a.PREFIX + 'ACK ' + json.dumps(ack) for ack in acks)
        client.extend(['[QUEUE_CHECK] ' + json.dumps(dict(suite='grooming-recovery', event='complete', cases=list(a.CASES), performed=3, failed=0, skipped=0)), a.PREFIX + 'COMPLETE ' + json.dumps(dict(cases=list(a.CASES)))])
        return '\n'.join(client + (authority if kind == 'sp' else [])), '\n'.join(authority)

    def test_verify_raw_exact_order_and_unique_completion(self):
        selection = self.selection()
        client, server = self.logs()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); (root/'client1-launch.log').write_text(client); (root/'server-launch.log').write_text(server)
            self.assertEqual(a.verify(root, selection, {})['issues'], [])
            for extra in (next(v for v in client.splitlines() if a.PREFIX + 'ACK ' in v), next(v for v in client.splitlines() if a.PREFIX + 'COMPLETE ' in v)):
                (root/'client1-launch.log').write_text(client + '\n' + extra)
                self.assertTrue(a.verify(root, selection, {})['issues'])
            (root/'client1-launch.log').write_text(client)
            (root/'server-launch.log').write_text(server + '\n' + server.splitlines()[0])
            self.assertTrue(a.verify(root, selection, {})['issues'])

    def test_registered_sources_and_lua_syntax(self):
        self.assertIs(adapters.get('grooming-recovery'), a)
        sources = a.sources(ROOT, self.selection())
        self.assertIn(ROOT/'tools/queue_checks/adapters/tv_controls.py', sources)
        self.assertIn(ROOT/'tools/queue_checks/mod_selection.py', sources)
        for path in sources:
            self.assertTrue(path.is_file(), path)
        lua = [p for p in sources if 'grooming-recovery' in str(p) and p.suffix == '.lua']
        self.assertEqual(len(lua), 3)
        if not shutil.which('luajit'): self.skipTest('LuaJIT syntax compiler unavailable')
        for path in lua:
            subprocess.run(['luajit', '-b', str(path), '/dev/null'], check=True, capture_output=True)


if __name__ == '__main__': unittest.main()
