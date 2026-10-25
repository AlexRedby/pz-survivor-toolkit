#!/usr/bin/env python3
"""Bake shopping turns from native walking, preserving its knees, foot roll and body motion.

Run inside Blender with --background --python tools/generate_shopping_walk_turn.py --
--game GAME_JAVA. This authors cosmetic actor-local clips and never installs them.
"""
import argparse
from bisect import bisect_right
import copy
import hashlib
import json
import math
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cart_clip_blender as bridge
from cart_blender_preview import parse_body
from cart_turn_clearance import check_clearance

ROOT = Path(__file__).resolve().parents[1]
FPS = 60
PERIOD = .8
FRAME_COUNT = 48
SOURCE = 'assets/animations/cart_pivot_walk.json'
CANONICAL = 'assets/animations/cart_pivot_idle.json'


def require(value, message):
    if not value:
        raise ValueError(message)


def generate(template, source, canonical, source_digest, canonical_digest, side, abduction_degrees=0.):
    from mathutils import Matrix, Quaternion, Vector

    _, parents = bridge.baker.template_parts(template)
    names = bridge.parent_order(parents)
    bridge.validate_samples(source, parents)
    bridge.validate_samples(canonical, parents)
    base = canonical[0]['bones']
    neutral = {name: Matrix(bridge.matrix_rows(base[name])) for name in names}
    neutral_local = {
        name: neutral[parents[name]].inverted() @ neutral[name]
        if parents[name] else neutral[name]
        for name in names
    }
    times = [row['time'] for row in source]
    duration = times[-1]
    require(duration > 0, 'Native walk has no duration')
    locals_by_frame = []
    for row in source:
        model = {name: Matrix(bridge.matrix_rows(row['bones'][name])) for name in names}
        locals_by_frame.append({
            name: (model[parents[name]].inverted() @ model[name]
                   if parents[name] else model[name]).decompose()
            for name in names
        })

    def descendants(root):
        result = set()
        for name in names:
            current = name
            while current:
                if current == root:
                    result.add(name)
                    break
                current = parents[current]
        return result

    pelvis_descendants = descendants('Bip01_Pelvis')
    chest_descendants = descendants('Bip01_Spine1')
    leg_descendants = {side: descendants(f'Bip01_{side}_Thigh') for side in ('L', 'R')}
    foot_descendants = {side: descendants(f'Bip01_{side}_Foot') for side in ('L', 'R')}
    sign = -1 if side == 'left' else 1 if side == 'right' else 0
    pelvis_degrees = sign * 25.
    chest_degrees = sign * 8.

    def nlerp(a, b, weight):
        sign = -1 if a.dot(b) < 0 else 1
        return Quaternion(tuple((1 - weight) * a[i] + weight * sign * b[i]
                                for i in range(4))).normalized()

    def turn(model, root, descendants, degrees):
        center = model[root].translation.copy()
        change = (Matrix.Translation(center)
                  @ Matrix.Rotation(math.radians(degrees), 4, 'Y')
                  @ Matrix.Translation(-center))
        for name in descendants:
            model[name] = change @ model[name]

    samples = []
    for frame in range(FRAME_COUNT):
        phase = frame / FRAME_COUNT
        time = ((phase + .5) % 1.) * duration
        high = min(len(times) - 1, max(1, bisect_right(times, time)))
        low = high - 1
        weight = (time - times[low]) / (times[high] - times[low])
        model = {}
        for name in names:
            if name not in pelvis_descendants:
                model[name] = neutral[name].copy()
                continue
            a = locals_by_frame[low][name]
            b = locals_by_frame[high][name]
            location = a[0].lerp(b[0], weight)
            # Native gait clips collapse unskinned end markers; retain the actor's offsets.
            if name.endswith('Nub') and location.length_squared < 1e-12:
                location = neutral_local[name].translation.copy()
            if name != 'Bip01_Pelvis':
                canonical_length = neutral_local[name].translation.length
                if canonical_length > 0:
                    require(location.length_squared >= 1e-12,
                            f'{name}: native walk collapses an anatomical joint')
                    location.normalize()
                    location *= canonical_length
            # Native AnimationTrack poses use unit joint scale. Retarget offsets to
            # the canonical actor just as the runtime's length-preserving sampler does.
            local = Matrix.LocRotScale(location, nlerp(a[1], b[1], weight), Vector((1, 1, 1)))
            parent = parents[name]
            model[name] = model[parent] @ local if parent else local
        for leg_side in ('L', 'R'):
            hip = f'Bip01_{leg_side}_Thigh'
            foot = f'Bip01_{leg_side}_Foot'
            desired_foot_rotation = model[foot].to_3x3()
            center = model[hip].translation.copy()
            leg_angle = math.radians(abduction_degrees * (1 if leg_side == 'L' else -1))
            change = (Matrix.Translation(center) @ Matrix.Rotation(leg_angle, 4, 'Z')
                      @ Matrix.Translation(-center))
            for name in leg_descendants[leg_side]:
                model[name] = change @ model[name]
            # Keep native foot pitch/roll and local toe articulation at the displaced ankle.
            center = model[foot].translation.copy()
            restore = (Matrix.Translation(center)
                       @ (desired_foot_rotation @ model[foot].to_3x3().inverted()).to_4x4()
                       @ Matrix.Translation(-center))
            for name in foot_descendants[leg_side]:
                model[name] = restore @ model[name]
        turn(model, 'Bip01_Pelvis', pelvis_descendants, pelvis_degrees)
        turn(model, 'Bip01_Spine1', chest_descendants, chest_degrees - pelvis_degrees)
        bones = {name: bridge.column_matrix(model[name]) for name in names}
        for name in names:
            if name not in pelvis_descendants:
                bones[name] = copy.deepcopy(base[name])
        samples.append(dict(time=frame / FPS, bones=bones))
    samples.append(dict(time=PERIOD, bones=copy.deepcopy(samples[0]['bones'])))
    samples[0]['metadata'] = dict(
        schema='shopping-turn-native-walk-v2', coordinate_space='native actor-local',
        direction='straight' if side == 'walk' else side, period_seconds=PERIOD, fps=FPS,
        canonical_phase='left foot swings first', source_phase_offset=.5,
        source=dict(path=SOURCE, sha256=source_digest),
        canonical_pose=dict(path=CANONICAL, sha256=canonical_digest),
        pelvis_yaw_degrees=pelvis_degrees, chest_yaw_degrees=chest_degrees,
        leg_abduction_degrees=abduction_degrees,
        foot_orientation='native pitch/roll and toe articulation retained before turn yaw',
        joint_translation_policy='canonical local lengths; native sampled directions; free pelvis bob',
        local_scale_policy='unit; native runtime discards scale',
        root_motion='none; all branches outside Pelvis retain exact canonical matrices',
        hand_fit='runtime CartGrip; native arm motion retained in source',
    )
    bridge.validate_samples(samples, parents)
    require(samples[0]['bones'] == samples[-1]['bones'], 'Native walk loop does not close')
    require(all(row['bones'][name] == base[name]
                for row in samples for name in names if name not in pelvis_descendants),
            'Canonical root or attachment branch changed')
    return samples


def main(args):
    template = (args.game / 'media/anims_X/Bob/Bob_Idle.x').read_text()
    source_bytes = (ROOT / SOURCE).read_bytes()
    canonical_bytes = (ROOT / CANONICAL).read_bytes()
    source = json.loads(source_bytes)
    canonical = json.loads(canonical_bytes)
    source_digest = hashlib.sha256(source_bytes).hexdigest()
    canonical_digest = hashlib.sha256(canonical_bytes).hexdigest()
    trousers = parse_body(
        (args.game / 'media/models_X/Skinned/Clothes/Bob_Trousers.x').read_text(),
        mesh_name='Bob_Trousers',
    )
    prepared = []
    report = {}
    # Use the smallest shared correction that clears actual native trouser geometry.
    # Never lower the crossing, ankle-order or segment-distance requirements.
    for abduction_degrees in (2., 3., 4.):
        candidates = {}
        report = {}
        for side in ('walk', 'left', 'right'):
            samples = generate(template, source, canonical, source_digest, canonical_digest,
                               side, abduction_degrees)
            clearance = check_clearance(samples, trousers, gait='staggered')
            candidates[side] = samples
            report[side] = dict(metadata=samples[0]['metadata'], clearance=clearance)
        if all(result['clearance']['passed'] for result in report.values()):
            break
        print('NATIVE_WALK_ABDUCTION_REJECTED', abduction_degrees,
              json.dumps({side: result['clearance'] for side, result in report.items()}), flush=True)
    require(all(result['clearance']['passed'] for result in report.values()),
            'Native walk failed opposite-leg clearance at every supported mild abduction')
    for side, samples in candidates.items():
        clip_name = 'Toolkit_ShoppingWalk' if side == 'walk' else 'Toolkit_ShoppingTurn_' + side.title()
        source_name = 'shopping_walk' if side == 'walk' else f'shopping_turn_{side}'
        native = bridge.baker.bake(template, samples, clip_name)
        prepared.extend((
            (args.output / f'assets/animations/{source_name}.json',
             json.dumps(samples, separators=(',', ':')) + '\n'),
            (args.output / f'PZSurvivorToolkit/42/media/anims_X/Bob/{clip_name}.x', native),
        ))
    for path, content in prepared:
        if args.check:
            require(path.read_text() == content, f'{path}: differs from native walk generator')
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
    print(json.dumps(report, indent=2), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', type=Path, required=True, help='supported game Java directory')
    parser.add_argument('--output', type=Path, default=ROOT, help='project root for generated assets')
    parser.add_argument('--check', action='store_true', help='verify deterministic output; never write')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    main(args)
