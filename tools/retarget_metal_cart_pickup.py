#!/usr/bin/env python3
"""Generate the metal pickup from editable wood poses using the current mixed JVM grip solver.

Run from any directory, after building the current Java/Kotlin patches:
  python3 tools/retarget_metal_cart_pickup.py --game GAME_JAVA --jdk JDK25
Use --check to reproduce both committed outputs without writing them. This is an
MP-independent offline asset operation; it does not start or install the game.
"""
import argparse
import copy
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

import cart_clip_bake as baker

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from JavaPatches.build import require_current_patch_jar

CLIP = 'Toolkit_MetalCart_Pickup'
HINGE_DEGREES = 65
EXTRA_CROUCH = .05
# Source wood ground-held translation versus the measured metal pair.
CENTER_SHIFT_X = (.216849 - .21714664) - (-.005859375 + .0060535767)


def smooth(t):
    t = max(0, min(1, t))
    return t * t * t * (10 + t * (-15 + 6 * t))


def hinge(time):
    crouch = smooth(time / .44)
    lift = smooth((time - .48) / .52)
    return crouch * (1 - lift * lift)


def descendant(name, ancestor, parents):
    while name is not None:
        if name == ancestor:
            return True
        name = parents[name]
    return False


def upper_body(name, parents):
    while name is not None:
        if name in ('Bip01_L_Thigh', 'Bip01_R_Thigh'):
            return False
        if name == 'Bip01_Spine':
            return True
        name = parents[name]
    return False


def pivot_x(point, angle):
    c, s = math.cos(angle), math.sin(angle)
    x, y, z = point
    return [1, 0, 0, 0, 0, c, s, 0, 0, -s, c, 0,
            0, y - c * y + s * z, z - s * y - c * z, 1]


def torso_poses(samples, parents):
    """Retain the accepted foot targets while lowering the body to grounded metal handles."""
    result = copy.deepcopy(samples)
    for sample in result:
        amount = math.radians(60 - HINGE_DEGREES) * hinge(sample['time'])
        if not amount:
            continue
        poses = sample['bones']
        change = pivot_x(poses['Bip01_Spine'][12:15], amount)
        for bone in poses:
            if upper_body(bone, parents):
                poses[bone] = baker.multiply(change, poses[bone])
        # bendTransitionTorso counterrotates arms at the shoulder. Undo the same
        # fraction before re-solving, rather than moving an old IK hand rigidly.
        for side in ('L', 'R'):
            upper = f'Bip01_{side}_UpperArm'
            hang = pivot_x(poses[upper][12:15], -amount)
            for bone in poses:
                if descendant(bone, upper, parents):
                    poses[bone] = baker.multiply(hang, poses[bone])
    for sample in result:
        lift = smooth((sample['time'] - .48) / .52)
        balance = smooth(sample['time'] / .44) * math.sqrt(1 - lift)
        center = smooth(sample['time'] / .10) * (1 - lift)
        for pose in sample['bones'].values():
            pose[12] += CENTER_SHIFT_X * center
            pose[13] -= EXTRA_CROUCH * balance
    return result


def solve(samples, parents, game, jdk, patch_jar):
    require_current_patch_jar(patch_jar, ROOT / 'JavaPatches')
    names = list(parents)
    classpath = os.pathsep.join(str(p) for p in (patch_jar, game / 'projectzomboid.jar', game / 'ZombieBuddy.jar'))
    with tempfile.TemporaryDirectory(prefix='cart-metal-retarget-') as directory:
        work = Path(directory)
        subprocess.run([str(jdk / 'bin/javac'), '--release', '17', '-cp', classpath,
                        '-d', str(work), str(ROOT / 'tools/CartMetalPickupRetarget.java')], check=True)
        with (work / 'input.bin').open('wb') as stream:
            stream.write(struct.pack('>ii', 0x434d5052, len(names)))
            for name in names:
                encoded = name.encode('ascii')
                stream.write(struct.pack('>H', len(encoded)) + encoded)
                stream.write(struct.pack('>i', -1 if parents[name] is None else names.index(parents[name])))
            stream.write(struct.pack('>i', len(samples)))
            for sample in samples:
                stream.write(struct.pack('>d', sample['time']))
                for name in names:
                    stream.write(struct.pack('>16d', *sample['bones'][name]))
        subprocess.run([str(jdk / 'bin/java'), '-Djava.awt.headless=true', f'-Djava.library.path={game}', '-cp',
                        os.pathsep.join((str(work), classpath)),
                        'net.alexredby.pztoolkitjavapatches.CartMetalPickupRetarget',
                        str(work / 'input.bin'), str(work / 'output.bin'),
                        str(game / 'media/anims_X/Bob/Bob_Idle.x')], check=True)
        data = (work / 'output.bin').read_bytes()
    count, = struct.unpack_from('>i', data)
    if count != len(samples) or len(data) != 4 + count * len(names) * 64:
        raise ValueError('unexpected runtime solver output')
    offset = 4
    result = copy.deepcopy(samples)
    for sample in result:
        for name in names:
            matrix = list(struct.unpack_from('>16f', data, offset))
            offset += 64
            # Keep editable torso values exact; current runtime IK restores planted
            # feet and solves the rigid leg and arm chains.
            if (any(descendant(name, f'Bip01_{s}_Thigh', parents) for s in ('L', 'R')) and sample['time'] < 1
                    or sample['time'] > 0 and any(descendant(name, f'Bip01_{s}_Clavicle', parents) for s in ('L', 'R'))):
                sample['bones'][name] = matrix
    return result


def verify_native(clip, game, jdk, patch_jar):
    """Catch double acquisition and restart overreach between native animation keys."""
    require_current_patch_jar(patch_jar, ROOT / 'JavaPatches')
    classpath = os.pathsep.join(str(p) for p in (patch_jar, game / 'projectzomboid.jar', game / 'ZombieBuddy.jar'))
    with tempfile.TemporaryDirectory(prefix='cart-metal-replay-') as directory:
        work = Path(directory)
        candidate = work / f'{CLIP}.x'
        candidate.write_text(clip)
        subprocess.run([str(jdk / 'bin/javac'), '--release', '17', '-cp', classpath,
                        '-d', str(work), str(ROOT / 'tools/CartMetalPickupReplay.java')], check=True)
        subprocess.run([str(jdk / 'bin/java'), '-Djava.awt.headless=true',
                        f'-Djava.library.path={game}', '-cp', os.pathsep.join((str(work), classpath)),
                        'net.alexredby.pztoolkitjavapatches.CartMetalPickupReplay', str(candidate)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', required=True, type=Path, help='directory containing game and ZombieBuddy JARs')
    parser.add_argument('--jdk', required=True, type=Path, help='JDK25 or newer')
    parser.add_argument('--patch-jar', type=Path, default=ROOT / 'JavaPatches/build/PZToolkitJavaPatches/42/media/java/PZToolkitJavaPatches.jar')
    parser.add_argument('--source', type=Path, default=ROOT / 'assets/animations/wood_cart_pickup.json')
    parser.add_argument('--template', type=Path, default=ROOT / 'PZSurvivorToolkit/42/media/anims_X/Bob/Toolkit_WoodCart_Pickup.x')
    parser.add_argument('--output-json', type=Path, default=ROOT / 'assets/animations/metal_cart_pickup.json')
    parser.add_argument('--output-x', type=Path, default=ROOT / f'PZSurvivorToolkit/42/media/anims_X/Bob/{CLIP}.x')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if ({args.output_json.resolve(), args.output_x.resolve()} & {args.source.resolve(), args.template.resolve()}
            or args.output_json.resolve() == args.output_x.resolve()):
        parser.error('outputs must differ from inputs and each other')
    try:
        source = json.loads(args.source.read_text())
        template = args.template.read_text()
        _, parents = baker.template_parts(template)
        if len(source) != 36 or source[0]['time'] != 0 or source[-1]['time'] != 1:
            raise ValueError('expected the current36-sample one-second wood pickup source')
        # Validate original poses before invoking any compiler or writing output.
        baker.bake(template, source, CLIP)
        poses = solve(torso_poses(source, parents), parents, args.game, args.jdk, args.patch_jar)
        outputs = {args.output_json: json.dumps(poses, separators=(',', ':')) + '\n',
                   args.output_x: baker.bake(template, poses, CLIP)}
        verify_native(outputs[args.output_x], args.game, args.jdk, args.patch_jar)
        for path, content in outputs.items():
            if args.check:
                if path.read_text() != content:
                    raise ValueError(f'generated output differs: {path}')
            else:
                path.write_text(content)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.error(str(error))
    print(f'METAL_PICKUP_{"REPRODUCED" if args.check else "GENERATED"} samples={len(poses)} hinge={HINGE_DEGREES} extraCrouch={EXTRA_CROUCH} runtimeIK=true')


if __name__ == '__main__':
    main()
