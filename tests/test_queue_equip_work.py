"""Opt-in native Equip work evidence and its deliberately limited UI/timing scope."""
import copy
import json
import re
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import zlib

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


class EquipReviewedSourcePreflightTests(unittest.TestCase):
    fixture_relative = Path('tests/native_queue/magazine-unload/client/QueueEquipCallbackObservation.lua')
    project = Path(__file__).resolve().parents[1]

    def candidate(self, directory):
        project = Path(directory) / 'project'; toolkit = Path(directory) / 'candidate'
        fixture = project / self.fixture_relative; fixture.parent.mkdir(parents=True)
        fixture.write_bytes((self.project / self.fixture_relative).read_bytes())
        pins = adapter._reviewed_equip_pins(fixture.read_text())
        for relative in pins:
            target = toolkit / '42/media/lua' / relative; target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((self.project / 'PZSurvivorToolkit/42/media/lua' / relative).read_bytes())
        return project, toolkit, pins

    def selection(self, baseline=False):
        return dict(kind='sp', mode='toolkit', clients=1, languages=['EN'], mods=adapter.MODS, cases=['equip-edit'],
                    options=dict(equip_workload=True, equip_workload_baseline=baseline))

    def test_current_reviewed_sources_use_effective_candidate_layers(self):
        real = dict(PZSurvivorToolkit=self.project / 'PZSurvivorToolkit')
        pins = adapter._reviewed_equip_pins((self.project / self.fixture_relative).read_text())
        self.assertEqual(pins, adapter.audit_equip_sources(self.project, self.selection(), real))
        with tempfile.TemporaryDirectory() as temporary:
            project, toolkit, pins = self.candidate(temporary)
            for relative in pins:
                common = toolkit / 'common/media/lua' / relative; common.parent.mkdir(parents=True, exist_ok=True)
                common.write_bytes(b'unselected common source\n')
            # The selected version overrides common; an unrelated legacy root is inactive.
            legacy = toolkit / 'media/lua/shared/PZSurvivorToolkit/SourceProof.lua'; legacy.parent.mkdir(parents=True)
            legacy.write_bytes(b'inactive legacy source\n')
            self.assertEqual(pins, adapter.audit_equip_sources(project, self.selection(), dict(PZSurvivorToolkit=toolkit)))
            self.assertEqual({}, adapter.audit_equip_sources(project / 'absent', dict(cases=['direct']), {}))

    def test_source_or_fixture_pin_drift_fails_before_probe_or_staging_writes(self):
        for change in ('source', 'pin', 'missing'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as temporary:
                project, toolkit, pins = self.candidate(temporary)
                relative = next(name for name in pins if name.endswith('/SourceProof.lua'))
                source = toolkit / '42/media/lua' / relative
                if change == 'source': source.write_bytes(source.read_bytes() + b'-- unreviewed candidate\n')
                elif change == 'missing': source.unlink()
                else:
                    fixture = project / self.fixture_relative
                    fixture.write_text(re.sub(r"('shared','SourceProof\.lua',)[0-9]+",
                        lambda match: match[1] + str(pins[relative] + 1), fixture.read_text(), count=1))
                output = Path(temporary) / 'not-staged'
                with mock.patch.object(adapter, 'audit_native', return_value={}), mock.patch.object(adapter, 'audit_selected', return_value={}), \
                        mock.patch.object(adapter, '_work_probe') as probe, mock.patch.object(adapter.shutil, 'copy2') as copy_file:
                    with self.assertRaisesRegex(ValueError, 'SourceProof.lua'):
                        adapter.stage(project, output, Path(temporary) / 'game', Path(temporary) / 'jdk', self.selection(),
                                      dict(PZSurvivorToolkit=toolkit), dict(roles={}))
                    probe.assert_not_called(); copy_file.assert_not_called()
                self.assertFalse(output.exists(), 'source mismatch created staging/probe artifacts')

    def test_explicit_archived_profile_uses_only_fixture_baseline_overrides(self):
        with tempfile.TemporaryDirectory() as temporary:
            project, toolkit, pins = self.candidate(temporary); fixture = project / self.fixture_relative
            text = fixture.read_text(); current, archived = {}, {}
            # Portable synthetic archived sources: no dependence on local Git history.
            # ASCII zlib Adler is an independent oracle for these LF-terminated records.
            for relative in pins:
                side, _, name = relative.split('/')
                current[relative] = ('current ' + name + '\n').encode()
                archived[relative] = ('archived ' + name + '\n').encode() if name != 'BulkActions.lua' else current[relative]
                text = re.sub(r"(\{'" + re.escape(side) + "','" + re.escape(name) + "',)[0-9]+",
                              lambda match: match[1] + str(zlib.adler32(current[relative])), text, count=1)
                if name != 'BulkActions.lua':
                    text = re.sub(r"(source\[2\]=='" + re.escape(name) + "'then adler=)[0-9]+",
                                  lambda match: match[1] + str(zlib.adler32(archived[relative])), text, count=1)
                (toolkit / '42/media/lua' / relative).write_bytes(archived[relative])
            fixture.write_text(text)
            locations = dict(PZSurvivorToolkit=toolkit)
            expected = {relative: zlib.adler32(data) for relative, data in archived.items()}
            self.assertEqual(expected, adapter.audit_equip_sources(project, self.selection(True), locations))
            with self.assertRaises(ValueError): adapter.audit_equip_sources(project, self.selection(False), locations)
            with self.assertRaises(ValueError): adapter.audit_equip_sources(project, dict(cases=['equip-edit'], options=dict(equip_workload_baseline=True)), locations)
            for relative, data in current.items(): (toolkit / '42/media/lua' / relative).write_bytes(data)
            self.assertEqual({relative: zlib.adler32(data) for relative, data in current.items()},
                             adapter.audit_equip_sources(project, self.selection(False), locations))
            with self.assertRaises(ValueError): adapter.audit_equip_sources(project, self.selection(True), locations)

    def test_closed_fixture_parser_rejects_dynamic_or_unrecognized_source_checks(self):
        text = (self.project / self.fixture_relative).read_text()
        changes = [re.sub(r"('shared','SourceProof\.lua',)[0-9]+", r"\1calculatePin()", text, count=1),
                   text.replace("'SourceProof.lua'", "'Source Proof.lua'", 1),
                   re.sub(r'then adler=[0-9]+', 'then adler=calculatePin()', text, count=1),
                   text + '\nlocal alias=sources\n',
                   text.replace("adler,'PZSurvivorToolkit',true", "adler,'DifferentMod',true", 1),
                   text.replace('config.options.equip_workload_baseline==true', 'config.options.equip_workload_baseline~=false', 1)]
        for changed in changes:
            with self.subTest(changed=changed[-80:]), self.assertRaises(ValueError): adapter._reviewed_equip_pins(changed)

    def test_reader_normalization_preserves_bom_and_unicode_separators_as_utf16_data(self):
        for raw in (b'A\nB', b'A\nB\n', b'A\r\nB\r\n', b'A\rB\r'):
            self.assertEqual(zlib.adler32(b'A\nB\n'), adapter._source_adler(raw))
        self.assertEqual(1, adapter._source_adler(b''))
        self.assertEqual(zlib.adler32(b'\n'), adapter._source_adler(b'\r\n'))
        raw = '\ufeffA\r\n\u0085\u2028\u2029😀\rZ\n\n'.encode('utf-8')
        units = [0xfeff, 65, 10, 0x85, 0x2028, 0x2029, 0xd83d, 0xde00, 10, 90, 10, 10]
        # Weighted-sum Adler oracle, independent of the rolling implementation.
        expected = ((len(units) + sum((len(units) - index) * value for index, value in enumerate(units))) % 65521) * 65536 + (1 + sum(units)) % 65521
        self.assertEqual(expected, adapter._source_adler(raw))
        self.assertNotEqual(zlib.adler32(raw), expected, 'fixture accidentally tests raw UTF8 byte Adler')
        self.assertNotEqual(adapter._source_adler(raw[3:]), expected, 'BOM was silently stripped')
        with self.assertRaisesRegex(ValueError, 'UTF8'): adapter._source_adler(b'\xed\xa0\x80')


if __name__ == '__main__': unittest.main()
