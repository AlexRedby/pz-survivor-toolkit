#!/usr/bin/env python3
"""Prove pinned cutawayFast cache divergences using full bytecode methods and native dirty APIs."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import statistics
import re
import sys
import zipfile

HERE = Path(__file__).resolve().parent
OPERATION = HERE.parent / 'cutaway_operation'
spec = importlib.util.spec_from_file_location('cutaway_operation_fixture', OPERATION / 'run.py')
operation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(operation)
GUARDS = {**operation.GUARDS,
    'zombie/iso/fboRenderChunk/FBORenderCutaways$BuildingsToCollapse.class': 'c36df2fc1ffcac1e3e31916e7ea437758ba1da0b427092e80b26c1b58776db7d',
    'zombie/iso/fboRenderChunk/FBORenderCutaways$PerPlayerData.class': '2e9a33eb9c1d55a59c440a522c7c0f7529d6dfecd7b6f9978a7d556de468c055',
    'zombie/iso/fboRenderChunk/FBORenderLevels$ZoomInfo.class': '2d8c055bbf52a3fdb3fb1c5f3e4774e8d3bad7976afd38c6ac4fe24fe850bb60',
    'zombie/iso/fboRenderChunk/FBORenderLevels$NLevels.class': 'ff812dbf1730894211e5f24deed52ba1ef854d190b8155eb2f1cc4fa4289f62b',
    'zombie/iso/fboRenderChunk/FBORenderLevels.class': '2a9a7521cdf59f27eb5711390baa8a3ce2c34e52215d021a6c1212e95c3cecee',
    'zombie/iso/fboRenderChunk/FBORenderCutaways.class': '9f44080e7858af88c858235939a7bfc2b3c792ee64b69c763568f1ecc6d6ce03',
}
PINNED = '646ef5e25432f02a1d0e00848585fb450985bf89887519a458f0f07271350748'
sha = lambda b: hashlib.sha256(b).hexdigest()


def validate_c2(jit, windows):
    first = min(lo for lo, hi in windows)
    evidence = {}
    for owner in ('PinnedCache', 'RepairedCache'):
        compiled = [line for line in jit if re.search(r'\bb\s+4\s+' + owner + r'::calculateOccludingSquares \(', line)
                    and float(re.match(r'\[([0-9.]+)s\]', line)[1]) * 1000 < first]
        if not compiled:
            raise RuntimeError('Full operation did not reach C2 before measurement: ' + owner)
        evidence[owner] = compiled[-1]
    return dict(first_window_ms=first, methods=evidence)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for key in ('game', 'jdk', 'official-overlay', 'output'):
        p.add_argument('--' + key, type=Path, required=True)
    p.add_argument('--measure', action='store_true')
    args = p.parse_args()
    game, jdk, overlay, out = (getattr(args, n).resolve() for n in ('game', 'jdk', 'official_overlay', 'output'))
    if out.exists() or out == game or game in out.parents:
        p.error('Output must be new and outside installed game')
    if operation.JVM_TARGET != '25':
        p.error('Requalify the pinned B42.21 extraction before changing JVM target')
    native, buddy = game / 'projectzomboid.jar', game / 'ZombieBuddy.jar'
    with zipfile.ZipFile(native) as z:
        for name, digest in GUARDS.items():
            if sha(z.read(name)) != digest:
                p.error('Native resource changed: ' + name)
    with zipfile.ZipFile(overlay) as z:
        for name, digest in {'zombie/iso/fboRenderChunk/FBORenderCell.class': PINNED,
                             'zombie/iso/fboRenderChunk/FBORenderCutaways$ChunkLevelData.class': operation.OFFICIAL}.items():
            if sha(z.read(name)) != digest:
                p.error('Pinned resource changed: ' + name)
    out.mkdir(parents=True)
    for name in ('classes', 'work', 'home', 'client1'):
        (out / name).mkdir()
    cp = os.pathsep.join(map(str, (out / 'classes', native, buddy)))
    def run(cmd, name):
        r = subprocess.run(list(map(str, cmd)), cwd=out / 'work', text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
        (out / (name + '.log')).write_text(r.stdout)
        if r.returncode:
            raise RuntimeError(name + ': ' + r.stdout[-5000:])
        return r.stdout
    compiler = [jdk / 'bin/javac', '--release', operation.JVM_TARGET, '-cp', cp, '-d', out / 'classes']
    run([*compiler, HERE / 'CacheGenerator.java', OPERATION / 'CutawayGenerator.java'], 'compile-extractors')
    java = [jdk / 'bin/java', '-Djava.awt.headless=true', '-Duser.home=' + str(out / 'home'), '-cp', cp]
    run([*java, 'CacheGenerator', overlay, out / 'classes', native], 'extract-pinned')
    run([*java, 'CutawayGenerator', native, out / 'classes', operation.JVM_TARGET, 'CutawayOperation'], 'extract-native')
    run([*java, 'CutawayGenerator', overlay, out / 'classes', operation.JVM_TARGET, 'OfficialCutawayOperation'], 'extract-official')
    run([*compiler, OPERATION / 'CutawayChecks.java', HERE / 'CacheChecks.java', HERE / 'RepairedCache.java', HERE / 'CacheBenchmark.java'], 'compile-checks')
    result = run([*java, 'CacheChecks'], 'correctness')
    if 'CACHE_CHECKS_PASS' not in result:
        raise RuntimeError('Missing complete result')
    receipt = dict(format=1, diagnostic_only=True, correctness_divergence_proved=True,
                   performance_measured=False, game_launched=False, repaired_semantics_passed='REPAIRED_CACHE_EQUIVALENT' in result, native_guards=GUARDS, pinned_cell_sha256=PINNED,
                   infrastructure_substitutions=['holder classes for private caller fields', 'additive native IsoChunk holder field for cache state, without native method changes',
                       'constant enabled=true, configurable cutawayFast, zoom=1', 'fixture cutaway-data lookup', 'overlapped-invalidation recording sink'],
                   native_methods=['shouldRenderBuildingSquare', 'calculateOccludingSquares', 'FBORenderLevels.invalidateLevel/clearDirty/isDirty'],
                   sources={f.name: sha(f.read_bytes()) for f in (HERE / 'CacheGenerator.java', HERE / 'CacheChecks.java', HERE / 'RepairedCache.java', HERE / 'CacheBenchmark.java', HERE / 'run.py', OPERATION / 'CutawayGenerator.java', OPERATION / 'CutawayChecks.java')},
                   result=result.strip().splitlines())
    receipt['generated_class_sha256'] = {str(f.relative_to(out / 'classes')): sha(f.read_bytes()) for f in (out / 'classes').rglob('*.class')}
    (out / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(result, end='')
    if not args.measure:
        return
    sys.path.insert(0, str(operation.ROOT / 'tools'))
    from queue_checks import admission
    selection = {'kind': 'sp', 'clients': 1, 'suite': 'cutaway-cache-diagnostic',
                 'resources': {'heap_mib': 512, 'native_mib': 256, 'cpu_per_instance': 2.0, 'exclusive': True}}
    runtime = {'roles': {'client1': {'cache': str(out / 'client1')}}}
    receipt['measurements'], receipt['jit_overlap'], receipt['gc_safepoint_overlap'], receipt['c2_before_measurement'] = [], [], [], []
    with admission.acquire(out, selection, runtime, 60) as admitted:
        (out / 'admission.json').write_text(json.dumps(admitted, indent=2) + '\n')
        for fork in range(3):
            label = 'measure-' + str(fork)
            log = run([*java, '-Xms512m', '-Xmx512m', '-Xbatch',
                       '-XX:CompileCommand=dontinline,PinnedCache::calculateOccludingSquares',
                       '-XX:CompileCommand=dontinline,RepairedCache::calculateOccludingSquares',
                       '-Xlog:jit+compilation=debug:file=' + str(out / (label + '-jit.log')),
                       '-Xlog:gc,safepoint:file=' + str(out / (label + '-gc.log')),
                       'CacheBenchmark', fork], label)
            windows = []
            for line in log.splitlines():
                parts = line.split()
                if line.startswith('ROW '):
                    row = dict(fork=fork, label=parts[1], mode=int(parts[2]),
                               **dict(zip(('round', 'operations', 'wall_ns', 'cpu_ns', 'checksum'), map(int, parts[3:]), strict=True)))
                    operation.validate_measurement(row)
                    receipt['measurements'].append(row)
                elif line.startswith('WINDOW '):
                    windows.append(tuple(map(int, parts[1:])))
            if len(windows) != 189:
                raise RuntimeError('Incomplete measured fork')
            jit = (out / (label + '-jit.log')).read_text().splitlines()
            receipt['c2_before_measurement'].append(dict(fork=fork, **validate_c2(jit, windows)))
            relevant = ('PinnedCache::', 'RepairedCache::', 'CacheChecks::', 'CacheBenchmark::', 'ChunkLevelData::', 'FBORenderLevels::', 'IsoChunk::getGridSquare', 'IsoChunk::getSquaresForLevel', 'IsoGridSquare::getVisionMatrix')
            for line in jit:
                at = re.match(r'\[([0-9.]+)s\]', line)
                if at and any(name in line for name in relevant) and any(lo-1 <= float(at[1])*1000 <= hi+1 for lo, hi in windows):
                    receipt['jit_overlap'].append(dict(fork=fork, line=line))
            for line in (out / (label + '-gc.log')).read_text().splitlines():
                at = re.match(r'\[([0-9.]+)s\]', line)
                if at and any(lo-1 <= float(at[1])*1000 <= hi+1 for lo, hi in windows):
                    receipt['gc_safepoint_overlap'].append(dict(fork=fork, line=line))
            (out / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    rows = receipt['measurements']
    for fork in range(3):
        for label in {r['label'] for r in rows}:
            for round in range(7):
                checksums = {r['checksum'] for r in rows if r['fork']==fork and r['label']==label and r['round']==round}
                if len(checksums) != 1:
                    raise RuntimeError('Measured checksum mismatch')
    receipt['diagnostic_cpu_ns_per_world'] = {
        label: {str(mode): [statistics.median(r['cpu_ns']/r['operations'] for r in rows if r['label']==label and r['mode']==mode and r['fork']==fork) for fork in range(3)] for mode in range(3)}
        for label in sorted({r['label'] for r in rows})}
    receipt['performance_measured'] = True
    receipt['timing_qualified'] = not receipt['jit_overlap'] and not receipt['gc_safepoint_overlap']
    (out / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt['diagnostic_cpu_ns_per_world'], indent=2))
    print('JIT_OVERLAP=' + str(len(receipt['jit_overlap'])))
    print('GC_SAFEPOINT_OVERLAP=' + str(len(receipt['gc_safepoint_overlap'])))

if __name__ == '__main__':
    main()
