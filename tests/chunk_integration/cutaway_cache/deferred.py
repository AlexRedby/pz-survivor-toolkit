#!/usr/bin/env python3
"""Check and optionally time the test-only deferred cache without altering the prior experiment."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('immutable_cache_fixture', HERE / 'run.py')
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
sha = lambda b: hashlib.sha256(b).hexdigest()

def c2_evidence(lines, windows):
    first = min(lo for lo, hi in windows)
    result = {}
    for owner in ('PinnedCache', 'RepairedCache', 'DeferredCache'):
        hits = [line for line in lines if re.search(r'\bb\s+4\s+' + owner + r'::calculateOccludingSquares \(', line)
                and float(re.match(r'\[([0-9.]+)s\]', line)[1])*1000 < first]
        if not hits:
            raise RuntimeError('Complete non-OSR C2 operation missing before measurement: ' + owner)
        result[owner] = hits[-1]
    return dict(first_window_ms=first, methods=result)

def main():
    p = argparse.ArgumentParser(description=__doc__)
    for key in ('game', 'jdk', 'official-overlay', 'output'):
        p.add_argument('--' + key, type=Path, required=True)
    p.add_argument('--measure', action='store_true')
    args = p.parse_args()
    game, jdk, overlay, out = (getattr(args, n).resolve() for n in ('game', 'jdk', 'official_overlay', 'output'))
    command = [sys.executable, HERE / 'run.py', '--game', game, '--jdk', jdk, '--official-overlay', overlay, '--output', out]
    bootstrap = subprocess.run(list(map(str, command)), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    if bootstrap.returncode:
        raise RuntimeError('Immutable fixture bootstrap: ' + bootstrap.stdout[-5000:])
    (out / 'bootstrap.log').write_text(bootstrap.stdout)
    (out / 'result.json').rename(out / 'bootstrap-result.json')
    cp = os.pathsep.join(map(str, (out / 'classes', game / 'projectzomboid.jar', game / 'ZombieBuddy.jar')))
    compiler = [jdk / 'bin/javac', '--release', base.operation.JVM_TARGET, '-cp', cp, '-d', out / 'classes']
    java = [jdk / 'bin/java', '-Djava.awt.headless=true', '-Duser.home=' + str(out / 'home'), '-cp', cp]
    def run(cmd, label):
        result = subprocess.run(list(map(str, cmd)), cwd=out / 'work', text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
        (out / (label + '.log')).write_text(result.stdout)
        if result.returncode:
            raise RuntimeError(label + ': ' + result.stdout[-5000:])
        return result.stdout
    run([*compiler, HERE / 'DeferredGenerator.java'], 'compile-deferred-generator')
    run([*java, 'DeferredGenerator', out / 'classes'], 'deferred-holder-field')
    source = [HERE / name for name in ('DeferredCache.java', 'DeferredChecks.java', 'DeferredBenchmark.java')]
    run([*compiler, *source], 'compile-deferred')
    checked = run([*java, 'DeferredChecks'], 'deferred-checks')
    if 'DEFERRED_CHECKS_PASS' not in checked:
        raise RuntimeError('Incomplete deferred checks')
    receipt = dict(format=1, diagnostic_only=True, runtime_admitted=False, game_launched=False,
                   bootstrap_receipt_sha256=sha((out / 'bootstrap-result.json').read_bytes()),
                   sources={f.name: sha(f.read_bytes()) for f in [*source, HERE / 'DeferredGenerator.java', HERE / 'deferred.py']},
                   generated_class_sha256={str(f.relative_to(out / 'classes')): sha(f.read_bytes()) for f in (out / 'classes').rglob('*.class')},
                   checks=checked.strip().splitlines(), measurements=[], jit_overlap=[], gc_safepoint_overlap=[], c2_before_measurement=[])
    def save():
        (out / 'deferred-result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    save()
    print(checked, end='')
    if not args.measure:
        return
    sys.path.insert(0, str(base.operation.ROOT / 'tools'))
    from queue_checks import admission
    selection = {'kind': 'sp', 'clients': 1, 'suite': 'cutaway-deferred-diagnostic',
                 'resources': {'heap_mib': 512, 'native_mib': 256, 'cpu_per_instance': 2.0, 'exclusive': True}}
    runtime = {'roles': {'client1': {'cache': str(out / 'client1')}}}
    with admission.acquire(out, selection, runtime, 60) as admitted:
        (out / 'deferred-admission.json').write_text(json.dumps(admitted, indent=2) + '\n')
        for fork in range(3):
            label = 'deferred-measure-' + str(fork)
            log = run([*java, '-Xms512m', '-Xmx512m', '-Xbatch',
                       '-XX:CompileCommand=dontinline,PinnedCache::calculateOccludingSquares',
                       '-XX:CompileCommand=dontinline,RepairedCache::calculateOccludingSquares',
                       '-XX:CompileCommand=dontinline,DeferredCache::calculateOccludingSquares',
                       '-Xlog:jit+compilation=debug:file=' + str(out / (label + '-jit.log')),
                       '-Xlog:gc,safepoint:file=' + str(out / (label + '-gc.log')),
                       'DeferredBenchmark', fork], label)
            windows = []
            for line in log.splitlines():
                parts = line.split()
                if line.startswith('ROW '):
                    row = dict(fork=fork, label=parts[1], mode=int(parts[2]),
                               **dict(zip(('round', 'operations', 'wall_ns', 'cpu_ns', 'checksum'), map(int, parts[3:]), strict=True)))
                    base.operation.validate_measurement(row)
                    receipt['measurements'].append(row)
                elif line.startswith('WINDOW '):
                    windows.append(tuple(map(int, parts[1:])))
            if len(windows) != 378:
                raise RuntimeError('Incomplete deferred measured fork: ' + str(len(windows)))
            jit = (out / (label + '-jit.log')).read_text().splitlines()
            receipt['c2_before_measurement'].append(dict(fork=fork, **c2_evidence(jit, windows)))
            for line in jit:
                at = re.match(r'\[([0-9.]+)s\]', line)
                relevant = ('PinnedCache::', 'RepairedCache::', 'DeferredCache::', 'DeferredBenchmark::', 'CacheChecks::', 'ChunkLevelData::', 'FBORenderLevels::', 'IsoChunk::getGridSquare', 'IsoChunk::getSquaresForLevel', 'IsoGridSquare::getVisionMatrix')
                if at and any(name in line for name in relevant) and any(lo-1 <= float(at[1])*1000 <= hi+1 for lo, hi in windows):
                    receipt['jit_overlap'].append(dict(fork=fork, line=line))
            for line in (out / (label + '-gc.log')).read_text().splitlines():
                at = re.match(r'\[([0-9.]+)s\]', line)
                if at and any(lo-1 <= float(at[1])*1000 <= hi+1 for lo, hi in windows):
                    receipt['gc_safepoint_overlap'].append(dict(fork=fork, line=line))
            save()
    rows = receipt['measurements']
    for fork in range(3):
        for label in {r['label'] for r in rows}:
            for round in range(7):
                if len({r['checksum'] for r in rows if r['fork']==fork and r['label']==label and r['round']==round}) != 1:
                    raise RuntimeError('Deferred measured checksum mismatch')
    receipt['cpu_ns_per_32_chunk_call'] = {
        label: {str(mode): [statistics.median(r['cpu_ns']/r['operations'] for r in rows if r['label']==label and r['mode']==mode and r['fork']==fork) for fork in range(3)] for mode in (0, 2, 3)}
        for label in sorted({r['label'] for r in rows})}
    receipt['timing_clear'] = not receipt['jit_overlap'] and not receipt['gc_safepoint_overlap']
    save()
    print(json.dumps(receipt['cpu_ns_per_32_chunk_call'], indent=2))
    print('JIT_OVERLAP=' + str(len(receipt['jit_overlap'])) + ' GC_SAFEPOINT_OVERLAP=' + str(len(receipt['gc_safepoint_overlap'])))

if __name__ == '__main__':
    main()
