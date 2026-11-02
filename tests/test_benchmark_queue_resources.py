"""Isolated command, provenance and failure tests; no JVM/game process is launched."""
import argparse
from contextlib import contextmanager
import copy
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import traceback
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('benchmark_queue_resources', ROOT / 'tools/benchmark_queue_resources.py')
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)


class QueueResourceBenchmarkTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.project, self.game, self.jdk, self.kotlin = (self.root / name for name in ('project', 'game', 'jdk', 'kotlin'))
        for relative, text in [(b.HOST, 'development host'), (b.BANK, 'QueueResourceBenchmarkPassed=true'),
                               (Path('tools/benchmark_queue_resources.py'), 'development runner'),
                               (Path('JavaPatches/build.py'), (ROOT / 'JavaPatches/build.py').read_text())]:
            path = self.project / relative; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(text)
        for relative in (b.TIMING_JAVA, *b.TIMING_TOOLS):
            path = self.project / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text((ROOT / relative).read_text())
        for path in (self.game / 'projectzomboid.jar', self.game / 'ZombieBuddy.jar', self.jdk / 'bin/java', self.jdk / 'bin/javac'):
            path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(b'local-only-input')
        self.build = b.load_build(self.project)
        for name in ('kotlin-compiler.jar', 'kotlin-stdlib.jar'):
            path = self.kotlin / 'lib' / name; path.parent.mkdir(parents=True, exist_ok=True)
            with ZipFile(path, 'w') as archive:
                archive.writestr('META-INF/MANIFEST.MF', 'Implementation-Version: ' + self.build.KOTLIN_VERSION + '\n')
        for name in ('LICENSE.txt', 'NOTICE.txt', 'COPYRIGHT.txt'):
            path = self.kotlin / 'license' / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text('local license')
        self.args = argparse.Namespace(game=self.game, jdk=self.jdk, kotlin_home=self.kotlin, output=self.root / 'report', samples=7, warmup=2, timeout=30.0, resource_wait=0)
        self.calls = []
        self.tokens = []
        for context in (
                patch.object(b.timing.admission, 'STATE', self.root / 'state'),
                patch.object(b.timing.admission, 'LEGACY_LOCK', self.root / 'legacy.lock'),
                patch.object(b.timing.admission.host, 'sample', return_value={
                    'total_memory': 16 * 1024**3, 'available_memory': 12 * 1024**3, 'cpu_count': 8, 'processes': []}),
                patch.object(b.timing.admission.shutil, 'disk_usage', return_value=SimpleNamespace(free=100 * 1024**3)),
                # The runner is an in-process test double. Actual descendant PID
                # ownership is qualified by the separate registration/JVM tests.
                patch.object(b.timing, '_owned_pid', side_effect=lambda pid, owner: pid == os.getpid())):
            context.start()
            self.addCleanup(context.stop)

    def events(self):
        return [dict(event='environment', scope='native-kahlua-cpu-only', gui=False, allocatedBytesAvailable=True, samples=7, warmup=2, sections=list(b.SECTIONS), maxSteps=1000),
                dict(event='gc', phase='before', collectors=[]),
                dict(event='source', scope='project', path=b.BANK.as_posix(), sha256=b.digest(self.project / b.BANK)),
                dict(event='sample', label='quote"\n\\\u0000', value=dict(ns=1.25, count=7, text='тест', unavailable=None)),
                dict(event='gc', phase='after', collectors=[]),
                dict(event='bank', status='passed', marker=b.MARKER, emitted=1, samples=7, warmup=2, sections=list(b.SECTIONS), maxSteps=1000)]

    def runner(self, events=None, fail=None, timeout=None, after_runtime=None, version='openjdk version "25.0.1"', register=True):
        def run(command, **kwargs):
            self.calls.append((command, kwargs.copy()))
            self.assertFalse(kwargs['check']); self.assertTrue(kwargs['text']); self.assertGreater(kwargs['timeout'], 0)
            label = ('version' if command[-1] == '-version' else 'compile' if '-jar' in command
                     else 'admission-compile' if command[0].endswith('javac') else 'runtime')
            if timeout == label:
                kwargs['stderr'].write('partial timeout log\n'); raise subprocess.TimeoutExpired(command, kwargs['timeout'])
            if label == 'version': kwargs['stderr'].write(version + '\n')
            elif label in ('compile', 'admission-compile'): kwargs['stdout'].write('minimal host compile\n')
            else:
                admission = None
                if register:
                    properties = dict(part[2:].split('=', 1) for part in command if part.startswith('-D') and '=' in part)
                    self.tokens.append(properties['pz.timing.token'])
                    with socket.create_connection(('127.0.0.1', int(properties['pz.timing.port'])), timeout=2) as client:
                        client.sendall(('PZ_TIMING_V1\t%s\t%s\t%d\n' % (
                            properties['pz.timing.token'], b.MAIN_CLASS, os.getpid())).encode())
                        reply = client.makefile('r').readline().rstrip('\n').split('\t')
                    self.assertEqual(reply[0], 'PZ_TIMING_OK')
                    admission = reply[1]
                    kwargs['stdout'].write('TIMING_ADMISSION %s %s pid=%d\n' % (admission, b.MAIN_CLASS, os.getpid()))
                kwargs['stdout'].write('ordinary harness print retained\n')
                for event in copy.deepcopy(self.events() if events is None else events):
                    if event['event'] == 'environment' and admission is not None:
                        event.setdefault('admission', admission)
                    kwargs['stdout'].write(json.dumps(event) + '\n')
                if after_runtime: after_runtime()
            return subprocess.CompletedProcess(command, 3 if fail == label else 0)
        return run

    def manifest(self): return json.loads((self.args.output / 'manifest.json').read_text())

    def test_compiles_minimal_host_and_guard_and_runs_registered_external_kahlua(self):
        result = b.run_benchmark(self.args, project=self.project, runner=self.runner())
        self.assertEqual(result['status'], 'passed'); self.assertEqual(result['emitted'], 1)
        self.assertEqual(len(self.calls), 4)
        guard_command = self.calls[1][0]
        self.assertEqual([part for part in guard_command if part.endswith('.java')], [str(self.project / b.TIMING_JAVA)])
        compile_command, compile_kw = self.calls[2]; runtime_command, runtime_kw = self.calls[3]
        self.assertEqual([part for part in compile_command if part.endswith(('.java', '.kt'))], [str(self.project / b.HOST)])
        self.assertIn(str(self.kotlin / 'lib/kotlin-compiler.jar'), compile_command)
        self.assertIn('-jvm-target', compile_command); self.assertIn(self.build.JVM_TARGET, compile_command)
        self.assertIn('-Djava.awt.headless=true', runtime_command); self.assertEqual(runtime_command[-1], b.MAIN_CLASS)
        self.assertIn('-Dpz.benchmark.samples=7', runtime_command); self.assertIn('-Dpz.benchmark.warmup=2', runtime_command)
        self.assertIn('-Dpz.benchmark.sections=component,edit,model,weights', runtime_command)
        self.assertIn('-Dpz.benchmark.maxSteps=1000', runtime_command)
        self.assertEqual(result['parameters']['sections'], list(b.SECTIONS)); self.assertEqual(result['parameters']['maxSteps'], 1000)
        self.assertEqual(runtime_kw['cwd'], str(self.game)); self.assertEqual(compile_kw['cwd'], str(self.args.output))
        self.assertFalse(any('build.py' in part or '-javaagent' in part for command, _ in self.calls for part in command))
        self.assertTrue((self.args.output / result['classes']).is_dir())
        self.assertEqual(result['executedSources'][0]['sha256'], b.digest(self.project / b.BANK))
        self.assertEqual(json.loads((self.args.output / 'results.jsonl').read_text().splitlines()[3])['value']['text'], 'тест')
        self.assertIn('ordinary harness print', (self.args.output / 'runtime-stdout.log').read_text())
        self.assertEqual(result['scope'], 'native-kahlua-cpu-only')
        self.assertTrue(result['timing']['attested'])
        self.assertTrue(result['timing']['admission']['exclusive'])
        for token in self.tokens:
            self.assertNotIn(token, json.dumps(result))
        self.assertEqual(b.timing.admission.status()['timing'], [])
        self.assertIn('no selected-pack UI/Host', result['limits'][0])

    def test_failures_preserve_report_and_do_not_run_later_stages(self):
        for failed, expected_calls in [('version', 1), ('admission-compile', 2), ('compile', 3), ('runtime', 4)]:
            with self.subTest(stage=failed):
                self.args.output = self.root / ('failure-' + failed); self.calls.clear()
                with self.assertRaises(b.BenchmarkFailure): b.run_benchmark(self.args, project=self.project, runner=self.runner(fail=failed))
                self.assertEqual(self.manifest()['status'], 'failed'); self.assertEqual(len(self.calls), expected_calls)
                self.assertTrue((self.args.output / (('java-version' if failed == 'version' else failed) + '-stderr.log')).exists())

    def test_hard_total_deadline_and_timeout_are_reported(self):
        with self.assertRaises(b.BenchmarkFailure): b.run_benchmark(self.args, project=self.project, runner=self.runner(timeout='compile'))
        self.assertTrue(self.manifest()['timedOut']); self.assertEqual(self.manifest()['status'], 'failed')
        self.assertIn('partial timeout log', (self.args.output / 'compile-stderr.log').read_text())
        self.assertLessEqual(self.calls[-1][1]['timeout'], self.calls[0][1]['timeout'])

    def test_missing_wrong_duplicate_marker_and_no_results_fail_even_exit_zero(self):
        modifications = [lambda e: e.pop(), lambda e: e[-1].update(marker='wrong'), lambda e: e.append(copy.deepcopy(e[-1])),
                         lambda e: e.pop(3), lambda e: e[-1].update(emitted=2), lambda e: e[-1].update(status='failed'),
                         lambda e: e[-1].update(samples=99)]
        for index, mutate in enumerate(modifications):
            events = self.events(); mutate(events); self.args.output = self.root / ('invalid-' + str(index))
            with self.subTest(index=index), self.assertRaises(b.BenchmarkFailure): b.run_benchmark(self.args, project=self.project, runner=self.runner(events))
            self.assertEqual(self.manifest()['status'], 'failed')

    def test_unavailable_allocations_are_explicit_not_zero(self):
        events = self.events(); events[0].update(allocatedBytesAvailable=False, allocatedBytesUnavailableReason='unsupported JVM')
        b.run_benchmark(self.args, project=self.project, runner=self.runner(events))
        self.args.output = self.root / 'ambiguous-allocation'; events[0].pop('allocatedBytesUnavailableReason')
        with self.assertRaises(b.BenchmarkFailure): b.run_benchmark(self.args, project=self.project, runner=self.runner(events))

    def test_executed_source_hashes_and_static_inputs_are_sealed(self):
        cases = [lambda: (self.project / b.BANK).write_text('changed after execution'),
                 lambda: (self.project / b.HOST).write_text('changed during execution')]
        for index, mutate in enumerate(cases):
            self.args.output = self.root / ('changed-' + str(index)); events = self.events()
            with self.subTest(index=index), self.assertRaises(b.BenchmarkFailure): b.run_benchmark(self.args, project=self.project, runner=self.runner(events, after_runtime=mutate))
            self.assertEqual(self.manifest()['status'], 'failed')

    def test_invalid_source_provenance_and_gc_are_rejected(self):
        mutations = [lambda e: e[2].update(path='../escape'), lambda e: e[2].update(sha256='0' * 64),
                     lambda e: e.insert(3, copy.deepcopy(e[2])), lambda e: e[2].update(scope='unknown'),
                     lambda e: e.pop(4), lambda e: e[0].update(gui=True)]
        for index, mutate in enumerate(mutations):
            self.args.output = self.root / ('provenance-' + str(index)); events = self.events(); mutate(events)
            with self.subTest(index=index), self.assertRaises(b.BenchmarkFailure): b.run_benchmark(self.args, project=self.project, runner=self.runner(events))

    def test_fresh_output_and_existing_inputs_required(self):
        self.args.output.mkdir()
        with self.assertRaises(b.BenchmarkFailure): b.run_benchmark(self.args, project=self.project, runner=self.runner())
        self.assertEqual(self.calls, [])
        self.args.output = self.root / 'another'; (self.game / 'projectzomboid.jar').unlink()
        with self.assertRaises(b.BenchmarkFailure): b.run_benchmark(self.args, project=self.project, runner=self.runner())
        self.assertFalse(self.args.output.exists())

    def test_old_jdk_cannot_compile_game_classes(self):
        with self.assertRaises(b.BenchmarkFailure): b.run_benchmark(self.args, project=self.project, runner=self.runner(version='openjdk version "21.0.2"'))
        self.assertEqual(len(self.calls), 1); self.assertEqual(self.manifest()['status'], 'failed')

    def test_cli_requires_explicit_local_toolchains_and_bounded_parameters(self):
        parsed = b.parser().parse_args(['--game', str(self.game), '--jdk', str(self.jdk), '--kotlin-home', str(self.kotlin), '--output', str(self.args.output)])
        self.assertEqual((parsed.samples, parsed.warmup, parsed.timeout, parsed.section, parsed.max_steps), (30, 5, 180, None, 1000))
        for field, value in [('samples', 0), ('samples', 100001), ('warmup', -1), ('timeout', float('inf')), ('timeout', 0)]:
            args = copy.copy(self.args); setattr(args, field, value)
            with self.subTest(field=field), self.assertRaises(b.BenchmarkFailure): b.run_benchmark(args, project=self.project, runner=self.runner())
        self.args.output = self.game / 'unsafe-report'
        with self.assertRaises(b.BenchmarkFailure): b.run_benchmark(self.args, project=self.project, runner=self.runner())

    def test_targeted_sections_and_step_limit_propagate_without_stress_defaults(self):
        cli = ['--game', str(self.game), '--jdk', str(self.jdk), '--kotlin-home', str(self.kotlin),
               '--output', str(self.args.output), '--section', 'component', '--section', 'edit', '--max-steps', '200']
        parsed = b.parser().parse_args(cli)
        self.assertEqual(parsed.section, ['component', 'edit']); self.assertEqual(parsed.max_steps, 200)
        self.args.section, self.args.max_steps = parsed.section, parsed.max_steps
        events = self.events()
        for event in (events[0], events[-1]): event.update(sections=['component', 'edit'], maxSteps=200)
        result = b.run_benchmark(self.args, project=self.project, runner=self.runner(events))
        command = self.calls[-1][0]
        self.assertIn('-Dpz.benchmark.sections=component,edit', command)
        self.assertIn('-Dpz.benchmark.maxSteps=200', command)
        self.assertNotIn('-Dpz.benchmark.maxSteps=1000', command)
        self.assertEqual(result['parameters']['sections'], ['component', 'edit'])
        self.assertEqual(result['parameters']['maxSteps'], 200)

    def test_selection_metadata_must_match_both_environment_and_bank(self):
        self.args.section, self.args.max_steps = ['component', 'edit'], 200
        for index, (target, field, value) in enumerate((
                (0, 'sections', list(b.SECTIONS)), (-1, 'sections', list(b.SECTIONS)),
                (0, 'sections', ['edit', 'component']), (-1, 'sections', ['component']),
                (0, 'maxSteps', 1000), (-1, 'maxSteps', 50),
                (0, 'sections', None), (-1, 'maxSteps', None))):
            events = self.events()
            for event in (events[0], events[-1]): event.update(sections=['component', 'edit'], maxSteps=200)
            events[target][field] = value
            self.args.output = self.root / ('selection-mismatch-' + str(index))
            with self.subTest(target=target, field=field, value=value), self.assertRaises(b.BenchmarkFailure):
                b.run_benchmark(self.args, project=self.project, runner=self.runner(events))
            self.assertEqual(self.manifest()['status'], 'failed')

    def test_invalid_or_duplicate_selections_reject_before_creating_report(self):
        for sections, steps in (([], 200), (['component', 'component'], 200), (['unknown'], 200),
                                ('component', 200), (['weights'], 201), (['model'], True)):
            args = copy.copy(self.args); args.section, args.max_steps = sections, steps
            with self.subTest(sections=sections, steps=steps), self.assertRaises(b.BenchmarkFailure):
                b.run_benchmark(args, project=self.project, runner=self.runner())
            self.assertFalse(args.output.exists())
        self.assertEqual(self.calls, [])

    def test_jsonl_parser_rejects_nonfinite_and_malformed_results(self):
        for text in ('{"event":"sample","value":NaN}', '{"event":', '{}'):
            with self.subTest(text=text), self.assertRaises(b.BenchmarkFailure): b.parse_events(text)
        self.assertEqual(b.parse_events('harness text\n{"event":"sample","label":"a\\n\\\"","value":null}')[0]['label'], 'a\n"')

    def test_unregistered_or_wrong_registration_cannot_qualify_a_bank(self):
        for index, registered in enumerate((False, True)):
            self.args.output = self.root / ('unregistered-' + str(index))
            events = self.events()
            if registered:
                events[0]['admission'] = '0' * 32
            with self.subTest(registered=registered), self.assertRaises(b.BenchmarkFailure):
                b.run_benchmark(self.args, project=self.project, runner=self.runner(events, register=registered))
            self.assertEqual(self.manifest()['status'], 'failed')
            self.assertEqual(b.timing.admission.status()['timing'], [])

    def test_exclusive_peer_prevents_jvm_measurement_and_preserves_failed_manifest(self):
        with b.timing.admission.preparing(self.root / 'peer', {'kind': 'sp', 'resources': {'exclusive': True}}, wait=0):
            with self.assertRaisesRegex(b.BenchmarkFailure, 'exclusive'):
                b.run_benchmark(self.args, project=self.project, runner=self.runner())
        self.assertEqual(len(self.calls), 3)
        self.assertEqual(self.manifest()['status'], 'failed')
        self.assertFalse((self.args.output / 'runtime-stdout.log').exists())

    def test_resource_wait_is_not_charged_to_execution_timeout(self):
        self.args.timeout = 1
        acquire = b.timing.acquire
        @contextmanager
        def delayed(*args, **kwargs):
            time.sleep(1.1)
            with acquire(*args, **kwargs) as registration:
                yield registration
        with patch.object(b.timing, 'acquire', side_effect=delayed):
            result = b.run_benchmark(self.args, project=self.project, runner=self.runner())
        self.assertEqual(result['status'], 'passed')
        self.assertGreater(self.calls[-1][1]['timeout'], 0)

    def test_runtime_timeout_never_exposes_registration_token(self):
        with self.assertRaises(b.BenchmarkFailure) as failure:
            b.run_benchmark(self.args, project=self.project, runner=self.runner(timeout='runtime'))
        token = next(part.split('=', 1)[1] for part in self.calls[-1][0] if part.startswith('-Dpz.timing.token='))
        self.assertNotIn(token, ''.join(traceback.format_exception(failure.exception)))
        self.assertNotIn(token, json.dumps(self.manifest()))
        self.assertEqual(b.timing.admission.status()['timing'], [])


if __name__ == '__main__': unittest.main()
