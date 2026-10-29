#!/usr/bin/env python3
"""Extract and check the B42.21 fog object prefix; optional bounded CPU diagnostic."""
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
_build_spec = importlib.util.spec_from_file_location('fog_operation_project_build', ROOT / 'JavaPatches/build.py')
_build = importlib.util.module_from_spec(_build_spec)
_build_spec.loader.exec_module(_build)
JVM_TARGET = _build.JVM_TARGET
GUARDS = {
    'zombie/iso/fboRenderChunk/FBORenderCell.class': 'd5c46201d60cff36397ee46c56b53dbaee6e26e8733836f27bf56ad871eedf94',
    'zombie/iso/IsoObject.class': '22387ecf47c1cf9aac192466de6298067f27584160c76a72baee38c6ad36dff2',
    'zombie/iso/fboRenderChunk/ObjectRenderInfo.class': '6d5a5f038841efc875b9f9e29d7dbdba4eb8ac0547adb00d3775bbbd4aa2abbd',
}
OFFICIAL = '646ef5e25432f02a1d0e00848585fb450985bf89887519a458f0f07271350748'
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
        if sha(z.read('zombie/iso/fboRenderChunk/FBORenderCell.class')) != OFFICIAL:
            p.error('Official FBORenderCell changed')
    out.mkdir(parents=True)
    for name in ('classes', 'official-classes', 'source', 'work', 'home', 'client1'):
        (out / name).mkdir()
    cp = os.pathsep.join(map(str, (out / 'classes', native, buddy)))
    receipt = dict(format=1, diagnostic_only=True, jvm_target=JVM_TARGET, native_guards=GUARDS, official_fborendercell=OFFICIAL,
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
    run([jdk / 'bin/javac', '--release', JVM_TARGET, '-cp', cp, '-d', out / 'classes', SOURCE / 'FogScanGenerator.java'], 'compile-generator')
    run([jdk / 'bin/java', '-cp', cp, 'FogScanGenerator', native, out / 'classes', JVM_TARGET], 'extract-native')
    run([jdk / 'bin/java', '-cp', cp, 'FogScanGenerator', overlay, out / 'official-classes', JVM_TARGET], 'extract-official')
    if (out / 'classes/FogObjectScan.class').read_bytes() != (out / 'official-classes/FogObjectScan.class').read_bytes():
        raise RuntimeError('Native and official object prefixes differ')
    receipt['scanner_class_major'] = int.from_bytes((out / 'classes/FogObjectScan.class').read_bytes()[6:8], 'big')
    if receipt['scanner_class_major'] != 44 + int(JVM_TARGET):
        raise RuntimeError('Generated scanner JVM target differs from the project target')
    receipt['scanner_sha256'] = sha((out / 'classes/FogObjectScan.class').read_bytes())
    run([jdk / 'bin/javac', '--release', JVM_TARGET, '-cp', cp, '-d', out / 'classes', SOURCE / 'FogOperationChecks.java'], 'compile-checks')
    base = [jdk / 'bin/java', '-Xms256m', '-Xmx256m', '-Xbatch', '-Djava.awt.headless=true',
            '-Duser.home=' + str(out / 'home'), '-cp', cp]
    run([*base, 'FogOperationChecks'], 'correctness')
    run([*base, 'FogOperationChecks', 'check-cpu-guard'], 'cpu-timer-guard')
    receipt['correctness_passed'] = True
    def save():
        (out / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    save()
    if args.measure:
        sys.path.insert(0, str(ROOT / 'tools'))
        from queue_checks import admission
        selection = {'kind': 'sp', 'clients': 1, 'suite': 'fog-operation-diagnostic',
                     'resources': {'heap_mib': 256, 'native_mib': 256, 'cpu_per_instance': 2.0, 'exclusive': True}}
        runtime = {'roles': {'client1': {'cache': str(out / 'client1')}}}
        with admission.acquire(out, selection, runtime, 60) as admitted:
            (out / 'admission.json').write_text(json.dumps(admitted, indent=2) + '\n')
            for fork in range(5):
                label = 'measure-' + str(fork)
                log = run([*base, '-XX:CompileCommand=dontinline,FogObjectScan::stock',
                           '-XX:CompileCommand=dontinline,FogObjectScan::unrolled',
                           '-Xlog:jit+compilation=debug:file=' + str(out / (label + '-jit.log')),
                           '-Xlog:gc,safepoint:file=' + str(out / (label + '-gc.log')),
                           'FogOperationChecks', 'reverse' if fork % 2 else 'forward'], label)
                windows=[]
                for line in log.splitlines():
                    parts=line.split()
                    if line.startswith('ROW '):
                        receipt['measurements'].append(validate_measurement(dict(fork=fork, mode=parts[1], label=parts[2],
                            **dict(zip(('round', 'operations', 'wall_ns', 'cpu_ns', 'checksum'), map(int, parts[3:]), strict=True)))))
                    elif line.startswith('WINDOW '):
                        windows.append(tuple(map(int, parts[1:])))
                current = [r for r in receipt['measurements'] if r['fork'] == fork]
                if len(windows) != 98 or len(current) != 98 or 'FOG_OPERATION_CHECKS_PASS' not in log:
                    raise RuntimeError('Incomplete fork: ' + label)
                for line in (out / (label + '-jit.log')).read_text().splitlines():
                    at=re.match(r'\[([0-9.]+)s\]', line)
                    if at and any(k in line for k in ('FogOperationChecks::', 'FogObjectScan::', 'IsoObject::getRenderInfo')):
                        if any(a-1 <= float(at[1])*1000 <= b+1 for a,b in windows):
                            receipt['jit_overlap'].append(dict(fork=fork, line=line))
                save()
        rows=receipt['measurements']; pairs=[]
        for label in sorted({r['label'] for r in rows}):
            deltas=[]
            for fork in range(5):
                values={m:statistics.median(r['cpu_ns']/r['operations'] for r in rows
                    if r['label']==label and r['fork']==fork and r['mode']==m) for m in ('stock','unrolled')}
                deltas.append(100*(values['unrolled']/values['stock']-1))
                pairs.append(dict(label=label,fork=fork,cpu_ns_per_scan=values,delta_percent=deltas[-1]))
        checksums = {label: {r['checksum'] for r in rows if r['label'] == label}
                     for label in {r['label'] for r in rows}}
        if any(len(sums) != 1 for sums in checksums.values()):
            raise RuntimeError('Fixture checksum differs across modes or forks')
        receipt.update(paired=pairs, fixture_checksums={k: sorted(v) for k, v in checksums.items()},
                       timing_qualified=not receipt['jit_overlap'])
        save()
    print('FOG_OPERATION_PASS ' + str(out / 'result.json'))

if __name__ == '__main__':
    main()
