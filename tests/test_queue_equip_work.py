"""Opt-in native Equip work evidence and its deliberately limited UI/timing scope."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

from tests.test_queue_magazine_unload_equip import evidence
from queue_checks.adapters import magazine_unload_equip_verifier as verifier
from queue_checks.adapters import magazine_unload as adapter


def metrics(stage, positive=True):
    value = dict(schema=1, stage=stage, active=True, elapsedMs=1000,
                 allocatedBytesAvailable=True, allocatedBytes=2048, openDepth=1, discardedOpen=1,
                 droppedCalls=0, droppedPaths=0, diagnostic='', sourcePathCount=0, depthCapacity=256, pathCapacity=128,
                 timer='relative-System.nanoTime', source='disposable-jvm-probe',
                 threadScope='mark-caller-Java-thread; controls-bind-originating-Kahlua-thread',
                 timingScope='completed-advice-intervals; inclusive-is-nonadditive; self-excludes-nested-instrumented-intervals',
                 sourceScope='media/lua-relative-source-open-attempts; no-reader-wrapping-or-byte-count',
                 overheadCorrected=False, perCallScopeAllocation=False, overhead='uncorrected observer work',
                 inactiveHookOverhead='unmarked advice still checks ownership',
                 adviceOrderLimit='Event-trigger-interval-may-exclude-sibling-advice; dispatch-helper-intervals-reported-separately',
                 retention='primitive-stats-and-immutable-source-strings; no-Event-closure-action-arguments')
    for hook in verifier.WORK_HOOKS:
        observed = positive or hook in ('dispatchEnter', 'dispatchExit', 'eventTrigger')
        value.update({hook + 'Calls': 2 if hook == 'eventTrigger' else int(observed),
                      hook + 'Completed': int(observed), hook + 'InclusiveNs': 100 if observed else 0,
                      hook + 'SelfNs': 80 if observed else 0, hook + 'MaxNs': 100 if observed else 0,
                      hook + 'Observed': observed, hook + 'SignatureAvailable': True, hook + 'Signature': hook + '(native arguments)'})
    return value


def workload(kind='sp', mode='toolkit'):
    toolkit = mode == 'toolkit'
    value = dict(schema=1, input='programmatic-native-widget-handlers', osEventRouting=False,
                 pointerGettersReplaced=False, requestsFocus=False, renderer='native-UIManager', observerReleased=True, phases=[])
    names = verifier.WORK_PHASES if toolkit else verifier.WORK_NATIVE_PHASES
    for name in names:
        phase = dict(name=name, metrics=metrics(name, positive=kind == 'sp' and toolkit))
        sustained = name in ('idle-visible', 'steady-move', 'steady-cancel', 'changing-drag', 'queue-disabled')
        if sustained or name == 'first-drag':
            phase['ticks'] = dict(count=4 if sustained else 0, totalMs=40 if sustained else 0, maxMs=10 if sustained else 0)
            draws = 8 if sustained and toolkit else 0
            phase['panel'] = dict(draws=draws, drawMs=2 if draws else 0, maxDrawMs=0.5 if draws else 0,
                                  previewRebuilds=2 if name in ('steady-move', 'steady-cancel', 'changing-drag') else 0)
        value['phases'].append(phase)
    if toolkit:
        value['cold'] = dict(pressMs=1, releaseMs=2, committed=kind == 'sp', nativeHitTesting=True,
                             scope='first-timed-widget-gesture-not-OS-routing',
                             sourceScope='first-family-enqueue-and-gesture-not-filesystem-cold')
        value['cancel'] = dict(pressMs=1, releaseMs=2, committed=kind == 'sp', nativeHitTesting=True,
                               metrics=metrics('cancel-click', positive=kind == 'sp'))
    return value


def work_evidence(segment='reorder-two', kind='sp', mode='toolkit'):
    values = evidence(segment, kind, mode)
    row, selection, prepared, _ = values
    selection['options'] = dict(equip_workload=True)
    if segment == 'reorder-two':
        for ids in (row['ids'], prepared): ids['items']['front']['initialPages'] = ids['items']['front']['pages'] - 2
        for field in ('pages', 'characterPages'): row['input']['books']['front'][field] -= 1
        row['workload'] = workload(kind, mode)
    return values


class EquipWorkTests(unittest.TestCase):
    def test_optional_receipts_preserve_default_and_unrelated_segments(self):
        for kind in ('sp', 'mp'):
            for mode in ('toolkit', 'native'):
                for segment in verifier.SEGMENTS:
                    with self.subTest(kind=kind, mode=mode, segment=segment):
                        self.assertEqual([], verifier.check_segment(*evidence(segment, kind, mode)))
                        if kind == 'sp': self.assertEqual([], verifier.check_segment(*work_evidence(segment, kind, mode)))
                        else: self.assertTrue(verifier.check_segment(*work_evidence(segment, kind, mode)), 'Host work profile exceeded SP scope')
        values = evidence(); values[0]['workload'] = workload()
        self.assertTrue(verifier.check_segment(*values), 'unselected measurement receipt gained coverage')
        values = work_evidence('cancel'); values[0]['workload'] = workload()
        self.assertTrue(verifier.check_segment(*values), 'shared result must appear only on first segment')

    def test_complete_group_forwards_measurements_without_changing_authority_coverage(self):
        for kind in ('sp',):
            for mode in ('toolkit', 'native'):
                selection = dict(kind=kind, mode=mode, cases=['equip-edit'], options=dict(equip_workload=True))
                client = ['[QUEUE_TEST] ' + name for name in ('VOICE_DISABLED', 'DISPLAY_READY', 'PREFLIGHT_COMPLETE',
                          'TRUE_SP' if kind == 'sp' else 'NATIVE_CONNECTED')]
                authority = ['[STARTUP_TEST] SERVER_READY']; group = []
                for segment in verifier.SEGMENTS:
                    row, _, prepared, final = work_evidence(segment, kind, mode); group.append(row)
                    client.append(verifier.PREFIX + 'CLIENT_PLACEMENT ' + json.dumps(dict(case='equip-edit', segment=segment, proof=row['clientPlacement'])))
                    authority.extend([verifier.PREFIX + 'PREPARED ' + json.dumps(prepared), verifier.PREFIX + 'VERIFIED ' + json.dumps(final)])
                events = [dict(event='setup', cases=['equip-edit'], segments=verifier.SEGMENTS, queueEnabled=mode == 'toolkit', nativeDurations=True),
                          dict(event='case', id='equip-edit', status='passed', actor='client1', kind=kind, mode=mode, segments=group, queueIdle=True, tidyQuiescent=True),
                          dict(event='complete', cases=['equip-edit'], performed=1, failed=0, skipped=0)]
                client.extend('[QUEUE_CHECK] ' + json.dumps(dict(event, suite='magazine-unload')) for event in events)
                client.append(adapter.PREFIX + 'COMPLETE ' + json.dumps(dict(cases=['equip-edit'])))
                if kind == 'sp': client.extend(authority)
                with tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary); (root / 'client1-launch.log').write_text('\n'.join(client))
                    (root / 'server-launch.log').write_text('\n'.join(authority))
                    result = adapter.verify(root, selection, {})
                    self.assertEqual([], result['issues'], (kind, mode))
                    self.assertIs(result['outcomes'][0]['outcome']['pendingEditsVerified'], kind == 'sp' and mode == 'toolkit')
                    self.assertIs(result['evidence']['workload']['performanceVerdict'], False)
                    self.assertIn('completed advice intervals', result['evidence']['workload']['timing'])

    def test_baseline_profile_is_explicit_boolean_sp_work_only(self):
        selection = dict(kind='sp', mode='toolkit', cases=['equip-edit'], clients=1, languages=['EN'], mods=adapter.MODS, options={})
        for options in ({}, dict(equip_workload=False), dict(equip_workload=True),
                        dict(equip_workload=True, equip_workload_baseline=True),
                        dict(equip_workload=True, equip_workload_baseline=False), dict(equip_workload_baseline=False)):
            adapter.validate(dict(selection, options=options))
        for options in (dict(equip_workload_baseline=True), dict(equip_workload=False, equip_workload_baseline=True),
                        dict(equip_workload=True, equip_workload_baseline=1), dict(equip_workload=True, equip_workload_baseline=None),
                        dict(equip_workload=True, equip_workload_baseline='true')):
            with self.subTest(options=options), self.assertRaises(ValueError): adapter.validate(dict(selection, options=options))
        with self.assertRaises(ValueError): adapter.validate(dict(selection, cases=['direct'], options=dict(equip_workload=True, equip_workload_baseline=True)))
        for mode in ('toolkit', 'native'):
            host = dict(selection, kind='mp', mode=mode, options=dict(mp_host=True))
            adapter.validate(host)
            with self.assertRaises(ValueError): adapter.validate(dict(host, options=dict(mp_host=True, equip_workload=True)))

    def test_initial_pages_are_exact_opt_in_front_only(self):
        for change in ('missing', 'wrong-value', 'bool', 'tail', 'input-pages', 'input-character-pages'):
            values = work_evidence(); row, _, prepared, _ = values
            for ids in (row['ids'], prepared):
                if change == 'missing': ids['items']['front'].pop('initialPages')
                elif change == 'wrong-value': ids['items']['front']['initialPages'] -= 1
                elif change == 'bool': ids['items']['front']['initialPages'] = True
                elif change == 'tail': ids['items']['tail']['initialPages'] = 99
            if change.startswith('input-'): row['input']['books']['front']['characterPages' if change.endswith('character-pages') else 'pages'] += 1
            with self.subTest(change=change): self.assertTrue(verifier.check_segment(*values))
        values = evidence()
        for ids in (values[0]['ids'], values[2]): ids['items']['front']['initialPages'] = 98
        self.assertTrue(verifier.check_segment(*values), 'default seed must remain pages minus one')
        for field in ('pages', 'characterPages'):
            values = evidence(); values[0]['input']['books']['tail'][field] -= 1
            self.assertTrue(verifier.check_segment(*values), 'default reader progress was not checked')

    def test_native_widget_scope_has_no_physical_input_or_global_performance_claim(self):
        selection = dict(kind='sp', mode='toolkit')
        summary = verifier.check_workload(workload(), selection)
        self.assertIs(summary['performanceVerdict'], False)
        self.assertGreater(summary['openIntervalsAtSnapshots'], 0)
        self.assertGreater(summary['discardedAtPhaseBoundaries'], 0)
        for field, invalid in (('osEventRouting', True), ('pointerGettersReplaced', True), ('requestsFocus', True),
                               ('renderer', 'direct-widget-call'), ('input', 'physical-mouse'), ('schema', True), ('observerReleased', False)):
            value = workload(); value[field] = invalid
            with self.subTest(field=field), self.assertRaises(ValueError): verifier.check_workload(value, selection)
        for field, invalid in (('scope', 'filesystem-cold-physical-gesture'), ('sourceScope', 'filesystem-cold'), ('nativeHitTesting', False)):
            value = workload(); value['cold'][field] = invalid
            with self.subTest(field=field), self.assertRaises(ValueError): verifier.check_workload(value, selection)

    def test_missing_phases_panels_previews_and_cancel_cannot_be_accepted(self):
        selection = dict(kind='sp', mode='toolkit')
        for change in ('missing-work', 'missing-phase', 'phase-order', 'missing-panel', 'no-draws', 'no-ticks',
                       'no-preview', 'idle-preview', 'missing-cancel', 'stage-mismatch', 'missing-metric', 'missing-release'):
            value = workload()
            if change == 'missing-work': value = None
            elif change == 'missing-phase': value['phases'].pop()
            elif change == 'phase-order': value['phases'][2:4] = reversed(value['phases'][2:4])
            elif change == 'missing-panel': value['phases'][2].pop('panel')
            elif change == 'no-draws': value['phases'][2]['panel'] = dict(draws=0, drawMs=0, maxDrawMs=0, previewRebuilds=0)
            elif change == 'no-ticks': value['phases'][2]['ticks'] = dict(count=0, totalMs=0, maxMs=0)
            elif change == 'no-preview': value['phases'][3]['panel']['previewRebuilds'] = 0
            elif change == 'idle-preview': value['phases'][2]['panel']['previewRebuilds'] = 1
            elif change == 'missing-cancel': value.pop('cancel')
            elif change == 'stage-mismatch': value['phases'][0]['metrics']['stage'] = 'unmarked'
            elif change == 'missing-release': value.pop('observerReleased')
            else: value['phases'][0]['metrics'].pop('eventTriggerObserved')
            with self.subTest(change=change), self.assertRaises(ValueError): verifier.check_workload(value, selection)

    def test_signatures_do_not_prove_actual_hook_observation_or_sp_authority(self):
        for hook in ('captureMatch', 'fingerprintTree', 'registryMatches', 'dispatchEnter', 'dispatchExit', 'eventTrigger'):
            value = workload()
            for metric in [phase['metrics'] for phase in value['phases']] + [value['cancel']['metrics']]:
                metric.update({hook + 'Calls': 0, hook + 'Completed': 0, hook + 'InclusiveNs': 0, hook + 'SelfNs': 0,
                               hook + 'MaxNs': 0, hook + 'Observed': False, hook + 'SignatureAvailable': True})
            with self.subTest(hook=hook), self.assertRaises(ValueError): verifier.check_workload(value, dict(kind='sp', mode='toolkit'))
        self.assertIs(verifier.check_workload(workload(mode='native'), dict(kind='sp', mode='native'))['performanceVerdict'], False)
        for mode in ('toolkit', 'native'):
            with self.assertRaises(ValueError): verifier.check_workload(workload('mp', mode), dict(kind='mp', mode=mode))
        for kind, expected in (('sp', False), ('mp', True)):
            value = workload(kind); value['cold']['committed'] = expected
            with self.assertRaises(ValueError): verifier.check_workload(value, dict(kind=kind, mode='toolkit'))
            value = workload(kind); value['cancel']['committed'] = expected
            with self.assertRaises(ValueError): verifier.check_workload(value, dict(kind=kind, mode='toolkit'))

    def test_finite_metrics_and_bounded_complete_observation_without_latency_budget(self):
        for field, invalid in (('elapsedMs', float('inf')), ('allocatedBytes', float('nan')), ('openDepth', -1),
                               ('discardedOpen', 257), ('droppedCalls', 1), ('droppedPaths', 1), ('diagnostic', 'stack-mismatch'),
                               ('captureMatchCalls', True), ('captureMatchCompleted', 4), ('captureMatchSelfNs', 101),
                               ('eventTriggerObserved', False), ('captureMatchSignatureAvailable', False), ('timingScope', 'whole-native-event')):
            value = workload(); value['phases'][0]['metrics'][field] = invalid
            with self.subTest(field=field), self.assertRaises(ValueError): verifier.check_workload(value, dict(kind='sp', mode='toolkit'))
        value = workload(); value['cold']['pressMs'] = 1000000; value['cold']['releaseMs'] = 0
        for phase in value['phases']: phase['metrics']['allocatedBytesAvailable'] = False; phase['metrics']['allocatedBytes'] = -1
        self.assertIs(verifier.check_workload(value, dict(kind='sp', mode='toolkit'))['performanceVerdict'], False)
        native = workload(mode='native'); native['phases'][1]['panel']['draws'] = 1
        with self.assertRaises(ValueError): verifier.check_workload(native, dict(kind='sp', mode='native'))

    def test_source_paths_are_bounded_relative_attempts_not_reader_or_filesystem_proof(self):
        value = workload(); metric = value['phases'][0]['metrics']
        metric.update(sourcePathCount=1, source1Mod='ExampleMod', source1Path='media/lua/client/Example.lua', source1Count=1)
        verifier.check_workload(value, dict(kind='sp', mode='toolkit'))
        for field, invalid in (('source1Path', '/private/local.lua'), ('source1Path', 'media/lua/../private.lua'),
                               ('source1Count', 0), ('sourcePathCount', 129), ('sourceScope', 'reader-bytes-filesystem-cold')):
            changed = copy.deepcopy(value); changed['phases'][0]['metrics'][field] = invalid
            with self.subTest(field=field, invalid=invalid), self.assertRaises(ValueError):
                verifier.check_workload(changed, dict(kind='sp', mode='toolkit'))


if __name__ == '__main__': unittest.main()
