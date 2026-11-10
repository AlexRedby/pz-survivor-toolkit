"""Health placement claims require independent centered witnesses and admission order."""
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import health_placement


def centered_proof(target, mode='local'):
    actual = dict(x=target['x'] + .5, y=target['y'] + .5, z=target['z'],
                  square=dict(target), currentSquare=dict(target))
    if mode == 'local':
        actual.update(queued=0, timed=False, moving=False, hasPath=False, deferredX=0, deferredY=0)
    return dict(mode=mode, target=dict(target), actual=actual, teleports=int(mode == 'local'),
                centered=True, centers=int(mode == 'local'), stableMs=500,
                quietMs=500 if mode == 'local' else 0, elapsedMs=1100)


def health_logs(selection, specs, events):
    """Build process-local synthetic evidence without inventing shared timestamps."""
    roles = list(events)
    authority = 'client1' if selection['kind'] == 'sp' else 'server'
    lines = {role: [] for role in {*roles, authority}}
    origin = dict(x=12, y=34, z=0)
    east = dict(origin, x=13)

    def raw(role, marker, row):
        lines[role].append(health_placement.PREFIX + marker + ' ' + json.dumps(row))

    def event(role, row):
        lines[role].append('[QUEUE_CHECK] ' + json.dumps(row))

    def round_(phase, doctor):
        targets = {'client1': origin} if phase == 'setup' else {doctor: origin}
        if selection['kind'] == 'mp' and (phase == 'setup' or specs[phase]['producer'] != 'inventory'):
            targets['client2' if doctor in ('setup', 'client1') else 'client1'] = east
        row = dict(phase=phase, doctor=doctor, targets=targets)
        raw(authority, 'LAYOUT', row)
        for actor, target in targets.items():
            own = centered_proof(target)
            base = dict(phase=phase, doctor=doctor, actor=actor, target=target)
            raw(actor, 'CLIENT_PLACEMENT', dict(base, proof=own))
            raw(authority, 'AUTHORITY_PLACEMENT', dict(base, proof=centered_proof(target, 'replica')
                if selection['kind'] == 'mp' else own, clientProof=own))
        raw(authority, 'PREPARED', row)
        if phase != 'setup':
            raw(doctor, 'ADMITTED', dict(row, actor=doctor))
            patient = doctor if selection['kind'] == 'sp' or specs[phase]['producer'] == 'inventory' else next(actor for actor in roles if actor != doctor)
            lines[authority].append('[QUEUE_TEST] HEALTH_AUTH_RECEIPT ' + doctor + ' phase=' + phase
                                    + ' ok=true patient=' + patient + ' error=nil')

    for role in roles:
        for value in events[role]:
            if value['event'] == 'setup':
                event(role, value)
    round_('setup', 'setup')
    for role in roles:
        for value in events[role]:
            if value['event'] == 'case':
                if value['status'] != 'skipped':
                    round_(value['id'], role)
                event(role, value)
        for value in events[role]:
            if value['event'] == 'complete':
                event(role, value)
    return {role: '\n'.join(rows) + '\n' for role, rows in lines.items()}


class HealthPlacementTests(unittest.TestCase):
    def fixture(self, kind='mp', inventory=False, skipped=False):
        selection = dict(kind=kind, cases=['bandageApply', 'unsupported'])
        specs = {'bandageApply': {'producer': 'inventory' if inventory else 'menu'},
                 'unsupported': {'producer': 'menu'}}
        roles = ['client1'] if kind == 'sp' else ['client1', 'client2']
        events = {role: [dict(event='setup'), dict(event='case', id='bandageApply', status='skipped' if skipped else 'passed'),
                         dict(event='case', id='unsupported', status='skipped'), dict(event='complete')] for role in roles}
        return selection, specs, health_logs(selection, specs, events)

    def validate(self, selection, specs, texts):
        return health_placement.validate(selection, texts, specs)

    def rewrite(self, texts, role, marker, change, index=0):
        lines = texts[role].splitlines()
        matches = [i for i, line in enumerate(lines) if line.startswith(health_placement.PREFIX + marker + ' ')]
        position = matches[index]
        row = json.loads(lines[position].split(' ', 2)[2])
        change(row)
        lines[position] = health_placement.PREFIX + marker + ' ' + json.dumps(row)
        texts[role] = '\n'.join(lines) + '\n'

    def test_sp_mp_inventory_and_skips_pass_with_unrelated_diagnostics(self):
        for kind in ('sp', 'mp'):
            for inventory in (False, True):
                for skipped in (False, True):
                    selection, specs, texts = self.fixture(kind, inventory, skipped)
                    texts['client1'] += '[QUEUE_TEST] unrelated diagnostic\n'
                    with self.subTest(kind=kind, inventory=inventory, skipped=skipped):
                        self.validate(selection, specs, texts)

    def test_sp_real_username_can_be_empty_or_differ_from_canonical_role(self):
        selection, specs, baseline = self.fixture('sp')
        for username in ('', 'local-survivor'):
            texts = dict(baseline)
            texts['client1'] = texts['client1'].replace('HEALTH_AUTH_RECEIPT client1 ',
                'HEALTH_AUTH_RECEIPT ' + username + ' ').replace('patient=client1 ', 'patient=' + username + ' ')
            with self.subTest(username=username):
                self.validate(selection, specs, texts)
                texts['client1'] = texts['client1'].replace('patient=' + username + ' ', 'patient=someone-else ')
                with self.assertRaisesRegex(ValueError, 'SP authority actor/patient differ'):
                    self.validate(selection, specs, texts)

    def test_missing_duplicate_malformed_and_foreign_records_fail(self):
        selection, specs, baseline = self.fixture()
        for role in baseline:
            for marker in health_placement.MARKERS:
                rows = [line for line in baseline[role].splitlines() if line.startswith(health_placement.PREFIX + marker + ' ')]
                if not rows:
                    continue
                for replacement in ('', rows[0] + '\n' + rows[0], health_placement.PREFIX + marker + ' []',
                                    health_placement.PREFIX + marker + ' {', health_placement.PREFIX + 'FOREIGN {}'):
                    texts = dict(baseline)
                    texts[role] = texts[role].replace(rows[0], replacement, 1)
                    with self.subTest(role=role, marker=marker, replacement=replacement[:60]):
                        with self.assertRaises(ValueError):
                            self.validate(selection, specs, texts)
        for marker in health_placement.MARKERS:
            texts = dict(baseline)
            role = 'server' if marker in ('LAYOUT', 'PREPARED', 'AUTHORITY_PLACEMENT') else 'client1'
            self.rewrite(texts, role, marker, lambda row: row.update(extra=True))
            with self.subTest(marker=marker, fields='extra'):
                with self.assertRaises(ValueError):
                    self.validate(selection, specs, texts)

    def test_wrong_owner_roles_targets_and_unsettled_proofs_fail(self):
        selection, specs, baseline = self.fixture()
        mutations = [('client1', 'CLIENT_PLACEMENT', lambda r: r.update(actor='client2')),
                     ('client1', 'CLIENT_PLACEMENT', lambda r: r.update(actor=[])),
                     ('server', 'LAYOUT', lambda r: r.update(phase=[])),
                     ('server', 'AUTHORITY_PLACEMENT', lambda r: r['clientProof'].update(elapsedMs=1200)),
                     ('server', 'AUTHORITY_PLACEMENT', lambda r: r['proof'].update(mode='local')),
                     ('client1', 'CLIENT_PLACEMENT', lambda r: r['proof']['actual'].update(x=12)),
                     ('client1', 'CLIENT_PLACEMENT', lambda r: r['proof'].update(stableMs=499)),
                     ('server', 'LAYOUT', lambda r: r['targets']['client2'].update(x=14)),
                     ('server', 'PREPARED', lambda r: r['targets']['client1'].update(x=True)),
                     ('client1', 'ADMITTED', lambda r: r.update(doctor='client2')),
                     ('client1', 'ADMITTED', lambda r: r['targets'].pop('client2')),
                     ('server', 'LAYOUT', lambda r: r.update(phase='unsupported'))]
        for role, marker, change in mutations:
            texts = dict(baseline)
            self.rewrite(texts, role, marker, change)
            with self.subTest(role=role, marker=marker):
                with self.assertRaises(ValueError):
                    self.validate(selection, specs, texts)
        for role, marker, destination in [('client1', 'CLIENT_PLACEMENT', 'client2'),
                                           ('client1', 'ADMITTED', 'server'), ('server', 'LAYOUT', 'client1')]:
            texts = dict(baseline)
            line = next(line for line in texts[role].splitlines() if health_placement.PREFIX + marker + ' ' in line)
            texts[role] = texts[role].replace(line, '', 1)
            texts[destination] += line + '\n'
            with self.assertRaises(ValueError):
                self.validate(selection, specs, texts)

    def test_process_local_order_and_receipt_after_prepared_are_required(self):
        for kind in ('sp', 'mp'):
            selection, specs, baseline = self.fixture(kind)
            authority = 'server' if kind == 'mp' else 'client1'
            moves = [(authority, 'PREPARED', 'AUTHORITY_PLACEMENT'),
                     (authority, 'HEALTH_AUTH_RECEIPT', 'LAYOUT'),
                     ('client1', 'ADMITTED', 'CLIENT_PLACEMENT'),
                     ('client1', 'ADMITTED', '"event": "complete"')]
            for role, moving, before in moves:
                texts = dict(baseline)
                lines = texts[role].splitlines()
                line = next(row for row in lines if moving in row)
                lines.remove(line)
                position = next(i for i, row in enumerate(lines) if before in row)
                lines.insert(position, line)
                texts[role] = '\n'.join(lines) + '\n'
                with self.subTest(kind=kind, moving=moving, before=before):
                    with self.assertRaises(ValueError):
                        self.validate(selection, specs, texts)

    def test_next_round_cannot_reuse_proof_from_before_previous_case_completion(self):
        selection = dict(kind='mp', cases=['bandageApply', 'glassHands'])
        specs = {case: {'producer': 'menu'} for case in selection['cases']}
        events = {role: [dict(event='setup'),
                        *[dict(event='case', id=case, status='passed') for case in selection['cases']],
                        dict(event='complete')] for role in ('client1', 'client2')}
        texts = health_logs(selection, specs, events)
        self.validate(selection, specs, texts)
        lines = texts['client1'].splitlines()
        line = next(row for row in lines if 'CLIENT_PLACEMENT' in row and '"phase": "glassHands"' in row)
        lines.remove(line)
        position = next(i for i, row in enumerate(lines) if 'ADMITTED' in row)
        lines.insert(position, line)
        texts['client1'] = '\n'.join(lines) + '\n'
        with self.assertRaisesRegex(ValueError, 'previous native case completion'):
            self.validate(selection, specs, texts)

    def test_receipts_for_skips_and_stale_origin_later_round_fail(self):
        selection, specs, baseline = self.fixture()
        texts = dict(baseline)
        texts['server'] += '[QUEUE_TEST] HEALTH_AUTH_RECEIPT client1 phase=unsupported ok=true patient=client2 error=nil\n'
        with self.assertRaises(ValueError):
            self.validate(selection, specs, texts)
        texts = dict(baseline)
        self.rewrite(texts, 'server', 'LAYOUT', lambda row: row['targets']['client1'].update(x=99), index=1)
        with self.assertRaises(ValueError):
            self.validate(selection, specs, texts)
