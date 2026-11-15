"""A failed bank preserves only complete, ordered, independently checked cases."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

from tests import test_queue_wring_clothing as fixtures
from tests.test_queue_wring_return_controls import a, capture, control_sample
from tests.test_queue_wring_unavailable import unavailable_capture, unavailable_sample
from queue_checks.adapters import wring_clothing_verifier as verifier


def raw(marker, value):
    return a.PREFIX + marker + ' ' + json.dumps(value)


def event(value):
    return '[QUEUE_CHECK] ' + json.dumps(value)


def payload(line, marker):
    return json.loads(line.split(a.PREFIX + marker + ' ', 1)[1])


def case_capture(result):
    row, selection, ids, verified = copy.deepcopy(result)
    if ids.get('returnControl') == 'unavailable':
        return unavailable_capture(result)
    if 'restoration' in row:
        return capture(result)
    case = ids['case']; kind = selection['kind']; mode = selection['mode']
    row.update(suite='wring-clothing', event='case', id=case, actor='client1', kind=kind, mode=mode)
    authority = [raw('PREPARED', ids)]
    if row.get('authorityBaseline') is not None:
        authority.append(raw('WEAR_BASELINE', row['authorityBaseline']))
    authority.append(raw('VERIFIED', verified))
    if 'capacityProfile' in row:
        authority.append(raw('PROFILE_CLEANED', row['capacityProfile']['cleanupServer']))
    client = [raw('CLIENT_PLACEMENT', dict(case=case, proof=row['clientPlacement']))]
    if 'capacityProfile' in row:
        client.append(raw('CAPACITY_PROFILE', row['capacityProfile']['measurement']))
    if kind == 'sp': client += authority
    client.append(event(row))
    return selection, client, authority


def case_lines(lines):
    result = []
    for line in lines:
        if line.startswith('[QUEUE_CHECK] ') and json.loads(line.split(' ', 1)[1]).get('event') != 'case':
            continue
        if not line.startswith(a.PREFIX + 'COMPLETE '): result.append(line)
    return result


def bank(results, *, suffix=None, completion=False):
    """Keep real fixture DTOs; truncate only the final case's observations."""
    captures = [case_capture(result) for result in results]
    cases = [result[2]['case'] for result in results]
    selection = dict(captures[0][0], cases=cases)
    setup = dict(suite='wring-clothing', event='setup', cases=cases, queueEnabled=selection['mode'] == 'toolkit',
                 nativeDurations=True, adapterInstalled=True)
    client = [event(setup)]; authority = []
    for index, (_, source_client, source_authority) in enumerate(captures):
        local = case_lines(source_client)
        server = source_authority[:]
        if suffix is not None and index == len(captures) - 1:
            def keep(line):
                if line.startswith('[QUEUE_CHECK] '): return False
                if suffix == 'before-prepare': return False
                if line.startswith(a.PREFIX + 'VERIFIED ') or line.startswith(a.PREFIX + 'PROFILE_CLEANED '): return False
                if line.startswith(a.PREFIX + 'RESTORATION '):
                    return suffix == 'body' and payload(line, 'RESTORATION')['point'] != 'final'
                if line.startswith(a.PREFIX + 'CAPACITY_LOST ') or line.startswith(a.PREFIX + 'SOURCE_LOST '):
                    return suffix == 'body'
                return True
            local = [line for line in local if keep(line)]
            server = [line for line in server if keep(line)]
            local.append(event(dict(suite='wring-clothing', event='case', id=cases[index], actor='client1',
                                    kind=selection['kind'], mode=selection['mode'], status='failed',
                                    phase='prepared', reason='fixture setup did not complete')))
        client += local; authority += server
    if completion:
        client += [event(dict(suite='wring-clothing', event='complete', cases=cases,
                              performed=len(cases), failed=0, skipped=0)), raw('COMPLETE', dict(cases=cases))]
    return selection, client, authority


def run_capture(captured):
    selection, client, authority = captured
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        (root / 'client1-launch.log').write_text('\n'.join(client))
        (root / 'server-launch.log').write_text('\n'.join(authority))
        return verifier.verify(root, selection, {})


def ordinary_bank(kind='sp', mode='toolkit', **options):
    return bank([control_sample(kind, mode, 'keep'), control_sample(kind, mode, 'full')], **options)


class WringCompletedPrefixTests(unittest.TestCase):
    def assert_prefix(self, result, cases, selected, *, cleanup='not-required'):
        self.assertTrue(result['issues'], 'an incomplete or failed bank must stay failed')
        prefix = result['evidence']['completedPrefix']
        self.assertEqual(cases, prefix['cases'])
        self.assertEqual(selected[len(cases):], prefix['uncompletedCases'])
        self.assertEqual([dict(case=case, queueIdle=True, authorityVerified=True, profileCleanup=cleanup) for case in cases],
                         prefix['boundaries'])
        self.assertIsInstance(prefix['qualification'], str)
        self.assertTrue(prefix['qualification'])
        self.assertNotIn(prefix['qualification'].lower(), ('passed', 'accepted', 'qualified'))
        self.assertEqual(selected, [row['case'] for row in result['outcomes']])
        for index, row in enumerate(result['outcomes']):
            if index < len(cases):
                self.assertEqual('passed', row['status'])
                self.assertTrue(row['outcome']['effectsVerified'])
                self.assertTrue(row['outcome']['serverAuthorityVerified'])
            else:
                self.assertEqual('failed', row['status'])
                self.assertTrue(row['reason'])
                self.assertTrue({'effectsVerified', 'serverAuthorityVerified', 'pendingEditsVerified',
                                 'tailCompleted', 'tailSemanticsVerified'} <= row['outcome'].keys())
                self.assertTrue(all(value is False for value in row['outcome'].values()), row)

    def assert_closed(self, result):
        self.assertTrue(result['issues'])
        self.assertEqual([], result.get('evidence', {}).get('completedPrefix', {}).get('cases', []))
        self.assertFalse(any(row.get('status') == 'passed' for row in result['outcomes']))

    def test_sp_and_host_preserve_passed_prefix_before_incomplete_setup_or_body(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for suffix in ('before-prepare', 'prepared', 'body'):
                    with self.subTest(kind=kind, mode=mode, suffix=suffix):
                        captured = ordinary_bank(kind, mode, suffix=suffix)
                        self.assert_prefix(run_capture(captured), ['worn-bag-keep'], captured[0]['cases'])

    def test_missing_footer_preserves_every_complete_case_but_not_bank_success(self):
        for kind in ('sp', 'mp'):
            captured = ordinary_bank(kind)
            self.assert_prefix(run_capture(captured), captured[0]['cases'], captured[0]['cases'])

    def test_common_report_keeps_failed_session_and_provenance_gates(self):
        from queue_checks import adapters, report
        selection, client, authority = ordinary_bank('sp', suffix='prepared')
        selection = dict(selection, suite='wring-clothing', clients=1)
        catalog = dict(suites=a.definitions())
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'client1-launch.log').write_text('\n'.join(client))
            (root / 'server-launch.log').write_text('\n'.join(authority))
            functional, coverage = adapters.functional(root, selection, catalog)
        self.assertEqual('failed', functional['status'])
        self.assertEqual(['worn-bag-keep'], functional['evidence']['completedPrefix']['cases'])
        self.assertEqual('passed', coverage[0]['status'])
        for status, provenance in (('failed', True), ('passed', False)):
            recorded = dict(status=status, coverage=coverage, selection=selection,
                            functional=dict(functional, status='passed'), provenance=dict(verified=provenance),
                            execution=dict(status='completed'))
            matrix = report._case_matrix(catalog, [recorded])
            row = next(row for row in matrix['rows'] if row.get('case') == 'worn-bag-keep'
                       and row.get('kind') == 'sp' and row.get('mode') == 'toolkit')
            self.assertEqual('failed', row['status'])

    def test_prefix_checker_uses_current_source_instead_of_cached_module(self):
        import sys
        from types import ModuleType
        from unittest.mock import patch
        cached = ModuleType('queue_checks.adapters.wring_clothing_session')
        def stale(*args):
            raise AssertionError('cached verifier helper executed')
        cached.verify_streams = stale
        captured = ordinary_bank('sp', suffix='body')
        with patch.dict(sys.modules, {cached.__name__: cached}):
            self.assert_prefix(run_capture(captured), ['worn-bag-keep'], captured[0]['cases'])

    def test_one_missing_terminal_channel_keeps_only_case_evidence(self):
        for kind in ('sp', 'mp'):
            for channel in ('structured', 'raw'):
                captured = ordinary_bank(kind, completion=True)
                marker = '[QUEUE_CHECK] ' if channel == 'structured' else a.PREFIX + 'COMPLETE '
                captured[1][:] = [line for line in captured[1] if not
                                  (line.startswith(marker) and (channel == 'raw' or json.loads(line.split(' ', 1)[1]).get('event') == 'complete'))]
                self.assert_prefix(run_capture(captured), captured[0]['cases'], captured[0]['cases'])

    def test_complete_bank_still_requires_matching_final_headers_and_footers(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                captured = ordinary_bank(kind, mode, completion=True)
                result = run_capture(captured)
                self.assertEqual([], result['issues'])
                self.assertTrue(all(row['status'] == 'passed' for row in result['outcomes']))
                for mutation in ('bad-count', 'bad-raw-cases', 'duplicate-end', 'duplicate-raw-end'):
                    changed = copy.deepcopy(captured); client = changed[1]
                    if mutation == 'bad-count':
                        value = json.loads(client[-2].split(' ', 1)[1]); value['performed'] -= 1
                        client[-2] = event(value)
                    elif mutation == 'bad-raw-cases': client[-1] = raw('COMPLETE', dict(cases=changed[0]['cases'][:1]))
                    elif mutation == 'duplicate-end': client.insert(-1, client[-2])
                    else: client.append(client[-1])
                    self.assert_closed(run_capture(changed))
        self.assert_closed(run_capture(ordinary_bank('mp', suffix='prepared', completion=True)))

    def test_semantic_rejection_stops_prefix_and_never_salvages_later_passed_row(self):
        for bad_index in (0, 1):
            results = [control_sample('mp', control='keep'), control_sample('mp', control='full')]
            results[bad_index][0]['commands'][0]['progress'] = False
            captured = bank(results)
            expected = [] if bad_index == 0 else ['worn-bag-keep']
            self.assert_prefix(run_capture(captured), expected, captured[0]['cases'])

    def test_missing_or_reordered_authority_cannot_qualify_completed_client_row(self):
        for kind in ('sp', 'mp'):
            for mutation in ('missing-verified', 'missing-prepared', 'wrong-case', 'out-of-order'):
                captured = ordinary_bank(kind, suffix='prepared'); selection, client, authority = captured
                stream = client if kind == 'sp' else authority
                prepared = next(i for i, line in enumerate(stream) if line.startswith(a.PREFIX + 'PREPARED '))
                verified = next(i for i, line in enumerate(stream) if line.startswith(a.PREFIX + 'VERIFIED '))
                if mutation == 'missing-verified': stream.pop(verified)
                elif mutation == 'missing-prepared': stream.pop(prepared)
                elif mutation == 'wrong-case':
                    value = payload(stream[verified], 'VERIFIED'); value['case'] = selection['cases'][1]
                    stream[verified] = raw('VERIFIED', value)
                else: stream[prepared], stream[verified] = stream[verified], stream[prepared]
                self.assert_closed(run_capture(captured))

    def test_late_duplicate_authority_or_restoration_is_not_hidden_by_prefix_trimming(self):
        for kind in ('sp', 'mp'):
            for marker in ('PREPARED', 'VERIFIED', 'RESTORATION'):
                captured = ordinary_bank(kind, suffix='body'); _, client, authority = captured
                stream = client if kind == 'sp' or marker == 'RESTORATION' else authority
                stream.append(next(line for line in stream if line.startswith(a.PREFIX + marker + ' ')))
                self.assert_closed(run_capture(captured))

    def test_restoration_mismatch_and_cross_case_interleaving_fail_closed(self):
        for mutation in ('mismatch', 'interleave'):
            captured = ordinary_bank('mp', suffix='body'); _, client, _ = captured
            index = next(i for i, line in enumerate(client) if line.startswith(a.PREFIX + 'RESTORATION '))
            if mutation == 'mismatch':
                value = payload(client[index], 'RESTORATION'); value['plannedTransfers'] += 1
                client[index] = raw('RESTORATION', value)
            else:
                later = next(i for i, line in enumerate(client) if line.startswith(a.PREFIX + 'RESTORATION ')
                             and payload(line, 'RESTORATION')['case'] == captured[0]['cases'][1])
                client.insert(index + 1, client.pop(later))
            self.assert_closed(run_capture(captured))

    def test_client_frame_cannot_start_before_setup_or_previous_terminal_case(self):
        for mutation in ('placement-before-setup', 'next-placement-before-close'):
            with self.subTest(mutation=mutation):
                captured = ordinary_bank('mp', suffix='prepared'); _, client, _ = captured
                if mutation == 'placement-before-setup':
                    index = next(i for i, line in enumerate(client) if line.startswith(a.PREFIX + 'CLIENT_PLACEMENT '))
                    client.insert(0, client.pop(index))
                else:
                    placement = next(i for i, line in enumerate(client) if line.startswith(a.PREFIX + 'CLIENT_PLACEMENT ')
                                     and payload(line, 'CLIENT_PLACEMENT')['case'] == captured[0]['cases'][1])
                    line = client.pop(placement)
                    closing = next(i for i, value in enumerate(client) if value.startswith('[QUEUE_CHECK] ')
                                   and json.loads(value.split(' ', 1)[1]).get('event') == 'case')
                    client.insert(closing, line)
                self.assert_closed(run_capture(captured))

    def test_truncated_known_marker_and_error_before_later_pass_do_not_qualify_prefix(self):
        captured = ordinary_bank('mp', suffix='prepared')
        captured[1].append(a.PREFIX + 'VERIFIED ')
        self.assert_closed(run_capture(captured))
        captured = ordinary_bank('mp')
        client = captured[1]
        position = next(i for i, line in enumerate(client) if line.startswith('[QUEUE_CHECK] ')
                        and json.loads(line.split(' ', 1)[1]).get('event') == 'case')
        client.insert(position + 1, event(dict(suite='wring-clothing', event='error', reason='fixture error')))
        self.assert_closed(run_capture(captured))

    def test_bad_setup_malformed_json_and_case_order_cannot_create_a_prefix(self):
        for mutation in ('wrong-setup', 'duplicate-setup', 'bad-event-json', 'bad-raw-json', 'case-order'):
            captured = ordinary_bank(suffix='prepared'); selection, client, _ = captured
            if mutation == 'wrong-setup':
                value = json.loads(client[0].split(' ', 1)[1]); value['cases'] = selection['cases'][:1]
                client[0] = event(value)
            elif mutation == 'duplicate-setup': client.append(client[0])
            elif mutation == 'bad-event-json': client.append('[QUEUE_CHECK] {')
            elif mutation == 'bad-raw-json': client.append(a.PREFIX + 'VERIFIED {')
            else:
                index = next(i for i, line in enumerate(client) if line.startswith('[QUEUE_CHECK] ')
                             and json.loads(line.split(' ', 1)[1]).get('event') == 'case')
                value = json.loads(client[index].split(' ', 1)[1]); value['id'] = selection['cases'][1]
                client[index] = event(value)
            self.assert_closed(run_capture(captured))

    def test_special_control_requires_exact_independent_authority_on_both_host_streams(self):
        for control in ('full', 'unavailable'):
            first = control_sample('mp', control='full') if control == 'full' else unavailable_sample('mp')
            captured = bank([first, control_sample('mp', control='intent')], suffix='prepared')
            self.assert_prefix(run_capture(captured), [first[2]['case']], captured[0]['cases'])
            marker = 'CAPACITY_LOST' if control == 'full' else 'SOURCE_LOST'
            for side in (1, 2):
                changed = copy.deepcopy(captured)
                stream = changed[side]; index = next(i for i, line in enumerate(stream) if line.startswith(a.PREFIX + marker + ' '))
                value = payload(stream[index], marker); value['itemId'] = -1
                stream[index] = raw(marker, value)
                self.assert_closed(run_capture(changed))

    def test_profile_prefix_requires_authority_cleanup_after_verified(self):
        for kind in ('sp', 'mp'):
            first = fixtures.capacity_profile_evidence(kind, 'toolkit')
            captured = bank([first, fixtures.evidence(kind, 'toolkit', 'world')], suffix='prepared')
            self.assert_prefix(run_capture(captured), ['worn-bag'], captured[0]['cases'], cleanup='verified')
            for mutation in ('missing', 'early', 'late', 'duplicate'):
                changed = copy.deepcopy(captured); stream = changed[1] if kind == 'sp' else changed[2]
                index = next(i for i, line in enumerate(stream) if line.startswith(a.PREFIX + 'PROFILE_CLEANED '))
                line = stream.pop(index)
                if mutation == 'early':
                    position = next(i for i, value in enumerate(stream) if value.startswith(a.PREFIX + 'VERIFIED '))
                    stream.insert(position, line)
                elif mutation == 'late': stream.append(line)
                elif mutation == 'duplicate': stream[index:index] = [line, line]
                self.assert_closed(run_capture(changed))


if __name__ == '__main__':
    unittest.main()
