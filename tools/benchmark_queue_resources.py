#!/usr/bin/env python3
"""Opt-in CPU-only queue resource bank in the installed game's native Kahlua.

Compiles one development Kotlin host. Does not build/install Java Patches, start
Project Zomboid, initialize a UI/server, or qualify gameplay/Host latency.
"""
import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
HOST = Path('JavaPatches/tests/net/alexredby/pztoolkitjavapatches/QueueResourceBenchmark.kt')
BANK = Path('tests/benchmarks/queue_resources.lua')
MAIN_CLASS = 'net.alexredby.pztoolkitjavapatches.QueueResourceBenchmark'
MARKER = 'QUEUE_RESOURCE_BENCHMARK_BANK_PASS'
SECTIONS = ('component', 'edit', 'model', 'weights')
MAX_STEPS = (50, 200, 1000)


class BenchmarkFailure(RuntimeError):
    pass


def digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def load_build(project):
    spec = importlib.util.spec_from_file_location('_queue_resource_kotlin_build', Path(project) / 'JavaPatches/build.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    for name, help_text in (
            ('game', 'Installed game Java directory containing projectzomboid.jar and ZombieBuddy.jar'),
            ('jdk', 'Existing JDK 25+ home'), ('kotlin-home', 'Existing Kotlin distribution matching JavaPatches/build.py'),
            ('output', 'New report directory; must not already exist')):
        result.add_argument('--' + name, type=Path, required=True, help=help_text)
    result.add_argument('--samples', type=int, default=30)
    result.add_argument('--warmup', type=int, default=5)
    result.add_argument('--section', action='append', choices=SECTIONS, help='Repeat to run only selected sections; default all four')
    result.add_argument('--max-steps', type=int, choices=MAX_STEPS, default=1000, help='Largest queue size included in selected sections')
    result.add_argument('--timeout', type=float, default=180, help='Hard total deadline in seconds, including compilation')
    return result


def selections(args):
    sections = getattr(args, 'section', None)
    sections = list(SECTIONS) if sections is None else sections
    max_steps = getattr(args, 'max_steps', 1000)
    if (not isinstance(sections, list) or not sections or any(section not in SECTIONS for section in sections)
            or len(set(sections)) != len(sections)):
        raise BenchmarkFailure('Sections must be a nonempty unique list of component/edit/model/weights')
    if type(max_steps) is not int or max_steps not in MAX_STEPS:
        raise BenchmarkFailure('Max steps must be 50, 200 or 1000')
    return list(sections), max_steps


def validate(args, project):
    selections(args)
    if not 1 <= args.samples <= 100_000 or not 0 <= args.warmup <= 100_000:
        raise BenchmarkFailure('Samples must be 1..100000 and warmup 0..100000')
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        raise BenchmarkFailure('Timeout must be finite and positive')
    for field in ('game', 'jdk', 'kotlin_home', 'output'):
        setattr(args, field, Path(getattr(args, field)).expanduser().resolve())
    if args.output.exists():
        raise BenchmarkFailure('Report output must be fresh: ' + str(args.output))
    for protected in (args.game, args.jdk, args.kotlin_home):
        if args.output.is_relative_to(protected):
            raise BenchmarkFailure('Report output must be outside game/JDK/Kotlin inputs')
    for path in (args.game / 'projectzomboid.jar', args.game / 'ZombieBuddy.jar',
                 args.jdk / 'bin/java', args.jdk / 'bin/javac', project / HOST, project / BANK,
                 project / 'JavaPatches/build.py'):
        if not path.is_file():
            raise BenchmarkFailure('Required local benchmark input missing: ' + str(path))


def commands(args, project, classes, build):
    sections, max_steps = selections(args)
    jars = [args.game / 'projectzomboid.jar', args.game / 'ZombieBuddy.jar']
    stdlib = args.kotlin_home / 'lib/kotlin-stdlib.jar'
    classpath = os.pathsep.join(map(str, [stdlib, *jars]))
    compiled = []
    build.compile_kotlin(args.jdk, args.kotlin_home, classpath, classes, [project / HOST],
                         module_name='queue_resource_benchmark', run=lambda command: compiled.append(command))
    runtime = [str(args.jdk / 'bin/java'), '-Djava.awt.headless=true',
               '-Dpz.test.project=' + str(project), '-Dpz.test.game=' + str(args.game),
               '-Dpz.benchmark.samples=' + str(args.samples), '-Dpz.benchmark.warmup=' + str(args.warmup),
               '-Dpz.benchmark.sections=' + ','.join(sections), '-Dpz.benchmark.maxSteps=' + str(max_steps),
               '-Duser.home=' + str(args.output / 'jvm-home'), '-cp',
               os.pathsep.join(map(str, [classes, stdlib, *jars])), MAIN_CLASS]
    if len(compiled) != 1:
        raise BenchmarkFailure('Expected exactly one Kotlin host compile command')
    return compiled[0], runtime


def parse_events(text):
    result = []
    for line in text.splitlines():
        if not line.startswith('{'):
            continue  # Harness print output is preserved in the full stdout log.
        try:
            value = json.loads(line, parse_constant=lambda token: (_ for _ in ()).throw(ValueError(token)))
        except (ValueError, TypeError) as error:
            raise BenchmarkFailure('Malformed benchmark JSONL output: ' + str(error)) from error
        if not isinstance(value, dict) or not isinstance(value.get('event'), str):
            raise BenchmarkFailure('Benchmark JSONL record has no event')
        result.append(value)
    return result


def qualify(events, args, project):
    sections, max_steps = selections(args)
    banks = [e for e in events if e['event'] == 'bank']
    samples = [e for e in events if e['event'] == 'sample']
    environments = [e for e in events if e['event'] == 'environment']
    gc = [e for e in events if e['event'] == 'gc']
    if (len(banks) != 1 or banks[0].get('status') != 'passed' or banks[0].get('marker') != MARKER
            or not samples or type(banks[0].get('emitted')) is not int or banks[0]['emitted'] != len(samples)
            or banks[0].get('samples') != args.samples or banks[0].get('warmup') != args.warmup
            or banks[0].get('sections') != sections or banks[0].get('maxSteps') != max_steps
            or events[-1] != banks[0]):
        raise BenchmarkFailure('Native bank failed, returned without its exact BANK marker, or emitted no results')
    if (len(environments) != 1 or environments[0].get('scope') != 'native-kahlua-cpu-only'
            or environments[0].get('gui') is not False or type(environments[0].get('allocatedBytesAvailable')) is not bool
            or environments[0].get('samples') != args.samples or environments[0].get('warmup') != args.warmup
            or environments[0].get('sections') != sections or environments[0].get('maxSteps') != max_steps
            or environments[0]['allocatedBytesAvailable'] is False and not environments[0].get('allocatedBytesUnavailableReason')
            or [e.get('phase') for e in gc] != ['before', 'after']):
        raise BenchmarkFailure('Native environment, allocation availability or before/after GC evidence missing')
    if any(not isinstance(e.get('label'), str) or 'value' not in e for e in samples):
        raise BenchmarkFailure('Malformed BenchmarkEmit(label, value) result')
    sources, seen = [], set()
    for event in (e for e in events if e['event'] == 'source'):
        scope, name = event.get('scope'), event.get('path')
        if scope not in ('project', 'game', 'external') or not isinstance(name, str):
            raise BenchmarkFailure('Malformed executed-source provenance')
        relative = Path(name)
        if scope != 'external' and (relative.is_absolute() or '..' in relative.parts):
            raise BenchmarkFailure('Executed-source provenance escapes its root')
        path = (project / relative if scope == 'project' else args.game / relative if scope == 'game' else relative)
        if scope == 'external' and not path.is_absolute():
            raise BenchmarkFailure('External executed-source provenance must be absolute')
        key = (scope, name)
        if key in seen or not isinstance(event.get('sha256'), str) or not re.fullmatch('[0-9a-f]{64}', event['sha256']):
            raise BenchmarkFailure('Duplicate/malformed executed-source fingerprint')
        seen.add(key)
        if not path.is_file() or digest(path) != event['sha256']:
            raise BenchmarkFailure('Executed source changed before report sealing: ' + name)
        sources.append(dict(scope=scope, path=name, sha256=event['sha256']))
    if ('project', BANK.as_posix()) not in seen:
        raise BenchmarkFailure('Bank source fingerprint missing')
    return sources


def run_benchmark(args, *, project=ROOT, runner=None, build=None):
    started = time.monotonic()
    project = Path(project).resolve()
    validate(args, project)
    sections, max_steps = selections(args)
    build = build or load_build(project)
    # Existing build helper validates local distribution/version/licenses and does
    # not compile runtime code, resolve packages or download anything.
    args.kotlin_home = build.kotlin_toolchain(args.kotlin_home, parser())
    args.output.mkdir(parents=True, exist_ok=False)
    classes = Path(tempfile.mkdtemp(prefix='host-', dir=args.output)) / 'classes'
    classes.mkdir()
    compile_command, runtime_command = commands(args, project, classes, build)
    inputs = [('project', str(HOST), project / HOST), ('project', str(BANK), project / BANK),
              ('project', 'tools/benchmark_queue_resources.py', project / 'tools/benchmark_queue_resources.py'),
              ('project', 'JavaPatches/build.py', project / 'JavaPatches/build.py'),
              ('game', 'projectzomboid.jar', args.game / 'projectzomboid.jar'), ('game', 'ZombieBuddy.jar', args.game / 'ZombieBuddy.jar'),
              ('kotlin', 'lib/kotlin-compiler.jar', args.kotlin_home / 'lib/kotlin-compiler.jar'),
              ('kotlin', 'lib/kotlin-stdlib.jar', args.kotlin_home / 'lib/kotlin-stdlib.jar'),
              ('jdk', 'bin/java', args.jdk / 'bin/java'), ('jdk', 'bin/javac', args.jdk / 'bin/javac')]
    manifest = dict(format=1, status='running', scope='native-kahlua-cpu-only',
                    limits=['CPU simulation in game Kahlua; no selected-pack UI/Host latency or multiplayer qualification.'],
                    parameters=dict(samples=args.samples, warmup=args.warmup, timeout=args.timeout, sections=sections, maxSteps=max_steps),
                    python=dict(version=sys.version, platform=platform.platform()),
                    inputs=[dict(scope=scope, path=name, sha256=digest(path)) for scope, name, path in inputs],
                    commands=dict(compile=compile_command, runtime=runtime_command), classes=str(classes.relative_to(args.output)))
    manifest_path = args.output / 'manifest.json'
    def save(): manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    save()
    deadline = started + args.timeout
    execute = runner or subprocess.run
    def run(command, label, cwd):
        remaining = deadline - time.monotonic()
        if remaining <= 0: raise BenchmarkFailure('Total benchmark timeout before ' + label)
        with (args.output / (label + '-stdout.log')).open('w', encoding='utf-8') as stdout, (args.output / (label + '-stderr.log')).open('w', encoding='utf-8') as stderr:
            completed = execute(command, cwd=str(cwd), stdout=stdout, stderr=stderr, text=True, timeout=remaining, check=False)
        if completed.returncode != 0:
            raise BenchmarkFailure(label + ' exited ' + str(completed.returncode) + '; inspect preserved stdout/stderr logs')
    try:
        run([str(args.jdk / 'bin/java'), '-version'], 'java-version', args.output)
        version_text = (args.output / 'java-version-stdout.log').read_text() + (args.output / 'java-version-stderr.log').read_text()
        version = re.search(r'(?:openjdk|java) version "(\d+)', version_text)
        if version is None or int(version[1]) < 25: raise BenchmarkFailure('Game classpath requires the existing JDK 25+')
        manifest['javaVersion'] = version_text.strip()
        run(compile_command, 'compile', args.output)
        run(runtime_command, 'runtime', args.game)
        events = parse_events((args.output / 'runtime-stdout.log').read_text(encoding='utf-8'))
        (args.output / 'results.jsonl').write_text(''.join(json.dumps(e, sort_keys=True, allow_nan=False) + '\n' for e in events), encoding='utf-8')
        manifest['executedSources'] = qualify(events, args, project)
        for (_, name, path), fingerprint in zip(inputs, manifest['inputs']):
            if digest(path) != fingerprint['sha256']: raise BenchmarkFailure('Benchmark input changed during execution: ' + name)
        manifest.update(status='passed', emitted=sum(e['event'] == 'sample' for e in events))
    except (BenchmarkFailure, OSError, subprocess.SubprocessError, ValueError) as error:
        manifest.update(status='failed', reason=str(error), timedOut=isinstance(error, subprocess.TimeoutExpired))
        save()
        raise BenchmarkFailure(str(error)) from error
    save()
    return manifest


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        manifest = run_benchmark(args)
    except (BenchmarkFailure, OSError) as error:
        print('Queue resource benchmark failed: ' + str(error), file=sys.stderr)
        return 1
    print('Native Kahlua CPU bank passed: ' + str(args.output / 'manifest.json'))
    print('This does not qualify selected-pack game/UI/Host performance.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
