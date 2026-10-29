#!/usr/bin/env python3
"""Extract and check the B42.21 cutaway full operation; optional bounded CPU diagnostic."""
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
import zipfile

SOURCE = Path(__file__).resolve().parent
ROOT = SOURCE.parents[2]
_build_spec = importlib.util.spec_from_file_location('cutaway_operation_project_build', ROOT / 'JavaPatches/build.py')
_build = importlib.util.module_from_spec(_build_spec)
_build_spec.loader.exec_module(_build)
JVM_TARGET = _build.JVM_TARGET
GUARDS = {
    'zombie/iso/fboRenderChunk/FBORenderCutaways$ChunkLevelData.class': '74c56b18cbd63d3bf8411f82af7f10541b3f6eb6d1dc98213fd7bae114a86936',
    'zombie/iso/IsoChunk.class': '5048becc3f46f746686513d4dcadb137e6e11bfd44617075f41923b3db11650a',
    'zombie/iso/IsoGridSquare.class': 'e8192f87d88da607abe0293228c84efbd822ed4ac0a331102c030bc3eeaba467',
}
OFFICIAL = '8770006d03831a61bf844e4c6ce7a1c3ad864c4cf7894de120636c9712f620b8'
sha = lambda b: hashlib.sha256(b).hexdigest()


def validate_measurement(row):
    for name in ('operations', 'wall_ns', 'cpu_ns'):
        if row[name] <= 0:
            raise RuntimeError('CPU measurement requires positive ' + name + ': ' + str(row[name]))
    return row


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('game', 'jdk', 'output', 'official-overlay'):
        p.add_argument('--' + name, type=Path, required=True)
    p.add_argument('--measure', action='store_true')
    args = p.parse_args()
    game, jdk, out, overlay = [getattr(args, n).resolve() for n in ('game', 'jdk', 'output', 'official_overlay')]
    if out.exists() or out == game or game in out.parents:
        p.error('Output must be new and outside the installed game')
    if JVM_TARGET != '25':
        p.error('Recheck this pinned B42.21 experiment before changing the project JVM target')
    version = subprocess.run([str(jdk / 'bin/java'), '-version'], text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)
    major = re.search(r'version \"(\d+)', version.stdout)
    if version.returncode or major is None or int(major[1]) < int(JVM_TARGET):
        p.error('JDK ' + JVM_TARGET + '+ is required')
    native, buddy = game / 'projectzomboid.jar', game / 'ZombieBuddy.jar'
    with zipfile.ZipFile(native) as z:
        for name, digest in GUARDS.items():
            if sha(z.read(name)) != digest:
                p.error('Native resource changed: ' + name)
    with zipfile.ZipFile(overlay) as z:
        if sha(z.read('zombie/iso/fboRenderChunk/FBORenderCutaways$ChunkLevelData.class')) != OFFICIAL:
            p.error('Official ChunkLevelData changed')
    out.mkdir(parents=True)
    for name in ('classes', 'source', 'work', 'home', 'client1'):
        (out / name).mkdir()
    cp = os.pathsep.join(map(str, (out / 'classes', native, buddy)))
    receipt = dict(format=1, diagnostic_only=True, jvm_target=JVM_TARGET, native_guards=GUARDS, official_chunkleveldata=OFFICIAL,
                   sources={f.name: sha(f.read_bytes()) for f in SOURCE.iterdir() if f.is_file()},
                   timing_qualified=False, measurements=[], jit_overlap=[])
    def run(command, label):
        r = subprocess.run(list(map(str, command)), cwd=out / 'work', text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240)
        (out / (label + '.log')).write_text(r.stdout)
        if r.returncode:
            raise RuntimeError(label + ': ' + r.stdout[-5000:])
        return r.stdout
    receipt['java_version'] = run([jdk / 'bin/java', '-version'], 'java-version').strip()
    for f in SOURCE.glob('*.java'):
        (out / 'source' / f.name).write_bytes(f.read_bytes())
    run([jdk / 'bin/javac', '--release', JVM_TARGET, '-cp', cp, '-d', out / 'classes', SOURCE / 'CutawayGenerator.java'], 'compile-generator')
    run([jdk / 'bin/java', '-cp', cp, 'CutawayGenerator', native, out / 'classes', JVM_TARGET, 'CutawayOperation'], 'extract-native')
    run([jdk / 'bin/java', '-cp', cp, 'CutawayGenerator', overlay, out / 'classes', JVM_TARGET, 'OfficialCutawayOperation'], 'extract-official')
    receipt['scanner_class_major'] = int.from_bytes((out / 'classes/CutawayOperation.class').read_bytes()[6:8], 'big')
    if receipt['scanner_class_major'] != 44 + int(JVM_TARGET):
        raise RuntimeError('Generated scanner JVM target differs from the project target')
    receipt['scanner_sha256'] = sha((out / 'classes/CutawayOperation.class').read_bytes())
    run([jdk / 'bin/javac', '--release', JVM_TARGET, '-cp', cp, '-d', out / 'classes', SOURCE / 'CutawayChecks.java'], 'compile-checks')
    base = [jdk / 'bin/java', '-Xms256m', '-Xmx256m', '-Xbatch', '-Djava.awt.headless=true',
            '-Duser.home=' + str(out / 'home'), '-cp', cp]
    run([*base, 'CutawayChecks'], 'correctness')
    run([*base, 'CutawayChecks', 'check-cpu-guard'], 'cpu-timer-guard')
    receipt['correctness_passed'] = True
    def save():
        (out / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    save()
    if args.measure:
        sys.path.insert(0, str(ROOT / 'tools'))
        from queue_checks import admission
        selection = {'kind': 'sp', 'clients': 1, 'suite': 'cutaway-operation-diagnostic',
                     'resources': {'heap_mib': 256, 'native_mib': 256, 'cpu_per_instance': 2.0, 'exclusive': True}}
        runtime = {'roles': {'client1': {'cache': str(out / 'client1')}}}
        with admission.acquire(out, selection, runtime, 60) as admitted:
            (out / 'admission.json').write_text(json.dumps(admitted, indent=2) + '\n')
            for fork in range(3):
                label = 'measure-' + str(fork)
                log = run([*base, '-XX:CompileCommand=dontinline,OfficialCutawayOperation::stock',
                           '-XX:CompileCommand=dontinline,OfficialCutawayOperation::reduced',
                           '-Xlog:jit+compilation=debug:file=' + str(out / (label + '-jit.log')),
                           '-Xlog:gc,safepoint:file=' + str(out / (label + '-gc.log')),
                           'CutawayChecks', 'reverse' if fork % 2 else 'forward'], label)
                windows=[]
                for line in log.splitlines():
                    parts=line.split()
                    if line.startswith('ROW '):
                        receipt['measurements'].append(validate_measurement(dict(fork=fork, mode=parts[1], label=parts[2],
                            **dict(zip(('round', 'operations', 'wall_ns', 'cpu_ns', 'checksum'), map(int, parts[3:]), strict=True)))))
                    elif line.startswith('WINDOW '):
                        windows.append(tuple(map(int, parts[1:])))
                current = [r for r in receipt['measurements'] if r['fork'] == fork]
                if len(windows) != 84 or len(current) != 84 or 'CUTAWAY_CHECKS_PASS' not in log:
                    raise RuntimeError('Incomplete fork: ' + label)
                for line in (out / (label + '-jit.log')).read_text().splitlines():
                    at=re.match(r'\[([0-9.]+)s\]', line)
                    if at and any(k in line for k in ('CutawayChecks::', 'CutawayOperation::', 'OfficialCutawayOperation::', 'ChunkLevelData::', 'IsoChunk::getGridSquare', 'IsoChunk::getSquaresForLevel', 'IsoGridSquare::getVisionMatrix')):
                        if any(a-1 <= float(at[1])*1000 <= b+1 for a,b in windows):
                            receipt['jit_overlap'].append(dict(fork=fork, line=line))
                jit = (out / (label + '-jit.log')).read_text().splitlines()
                for method in ('stock', 'reduced'):
                    compiled = [line for line in jit if re.search(r'\bb\s+4\s+OfficialCutawayOperation::' + method + r' \(', line)
                                and float(re.match(r'\[([0-9.]+)s\]', line)[1]) * 1000 < min(w[0] for w in windows)]
                    if not compiled:
                        raise RuntimeError('Full operation did not reach C2 before measurement: ' + method)
                save()
        rows=receipt['measurements']; pairs=[]
        for label in sorted({r['label'] for r in rows}):
            deltas=[]
            for fork in range(3):
                values={m:statistics.median(r['cpu_ns']/r['operations'] for r in rows
                    if r['label']==label and r['fork']==fork and r['mode']==m) for m in ('stock','reduced')}
                deltas.append(100*(values['reduced']/values['stock']-1))
                pairs.append(dict(label=label,fork=fork,cpu_ns_per_scan=values,delta_percent=deltas[-1]))
        checksums = {label: {r['checksum'] for r in rows if r['label'] == label}
                     for label in {r['label'] for r in rows}}
        if any(len(sums) != 1 for sums in checksums.values()):
            raise RuntimeError('Fixture checksum differs across modes or forks')
        receipt.update(paired=pairs, fixture_checksums={k: sorted(v) for k, v in checksums.items()},
                       timing_qualified=not receipt['jit_overlap'])
        save()
    print('CUTAWAY_OPERATION_PASS ' + str(out / 'result.json'))

if __name__ == '__main__':
    main()
