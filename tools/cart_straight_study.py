"""Sample native cart walking for an offline Blender comparison.

This module does not author leg keys or install an animation. ``straight_frames``
returns actor/model-space matrices in the Blender bone basis used by
cart_clip_blender, plus separate actor world transforms. Its local-space mixer
uses normalized quaternion interpolation; the held chest is an approximation of
the runtime masks and the caller must still fit the hands to the cart.
"""
from bisect import bisect_right
import hashlib
import json
import math
from pathlib import Path

import cart_clip_blender as bridge


ROOT = Path(__file__).resolve().parents[1]


def straight_frames(neutral, names, parents, duration=3.2, candidate=True):
    """Return ``frames``, ``worlds``, ``traces`` and descriptive ``settings``.

    The baseline blends .8 native Walk with .2 native Idle at rate 1.04.
    The candidate retains a full native step at rate .832. Both use the same
    nominal extracted-root speed. No acceleration, stop, foot locking or new
    footstep timing is introduced. ``neutral`` contains actor/model-space
    Blender bone matrices, as in shopping_cart_turn_study.py.
    """
    from mathutils import Matrix, Quaternion, Vector

    if not math.isfinite(duration) or duration <= 0:
        raise ValueError('Straight study duration must be positive and finite')
    if list(names) != bridge.parent_order(parents) or set(neutral) != set(names):
        raise ValueError('Expected the complete original parent-ordered Bob hierarchy')
    fps = 60
    sources = {}
    for suffix in ('walk', 'idle'):
        path = ROOT / f'assets/animations/cart_pivot_{suffix}.json'
        content = path.read_bytes()
        samples = json.loads(content)
        bridge.validate_samples(samples, parents)
        times = [row['time'] for row in samples]
        local_rows = []
        model_rows = []
        for row in samples:
            models = {
                name: Matrix(bridge.matrix_rows(bridge.native_to_blender(row['bones'][name])))
                for name in names
            }
            model_rows.append(models)
            local_rows.append({
                name: ((models[parents[name]].inverted() @ models[name])
                       if parents[name] else models[name]).decompose()
                for name in names
            })
        sources[suffix] = dict(path=path, sha256=hashlib.sha256(content).hexdigest(),
                               times=times, local=local_rows, models=model_rows,
                               samples=samples)
    loop = sources['walk']['times'][-1]
    if abs(sources['idle']['times'][-1] - loop) > 1e-6:
        raise ValueError('Expected matching native Walk and Idle cycle durations')

    def nlerp(a, b, weight):
        # AnimationTrack's short-arc normalized linear interpolation, not slerp.
        sign = -1 if a.dot(b) < 0 else 1
        return Quaternion(tuple((1-weight)*a[i] + weight*sign*b[i] for i in range(4))).normalized()

    def blend(a, b, weight):
        return (a[0].lerp(b[0], weight), nlerp(a[1], b[1], weight), a[2].lerp(b[2], weight))

    def at(source, time):
        times = source['times']
        high = min(len(times)-1, max(1, bisect_right(times, time)))
        low = high-1
        weight = (time-times[low])/(times[high]-times[low])
        return {name: blend(source['local'][low][name], source['local'][high][name], weight)
                for name in names}

    neutral_local = {
        name: ((neutral[parents[name]].inverted() @ neutral[name])
               if parents[name] else neutral[name]).decompose()
        for name in names
    }

    def held_chest(name):
        current = name
        while current:
            if current == 'Bip01_Spine1':
                return True
            current = parents[current]
        return name in ('Bip01_Prop1', 'Bip01_Prop2')

    held = {name for name in names if held_chest(name)}
    # Native thighs branch from Spine. Keep that ancestor sampled, otherwise a
    # frozen chest would change the native legs during local-to-model FK.
    if any(name in held for name in ('Bip01_Spine', 'Bip01_L_Thigh', 'Bip01_R_Thigh')):
        raise ValueError('Held chest selection unexpectedly contains lower-body bones')

    # Translation_Data has its own oriented frame. Its displacement magnitude
    # gives the extraction budget; use low-foot motion to establish actor-forward
    # sign instead of applying that frame's vector as an actor-space direction.
    deferred = sources['walk']['samples']
    start = Vector(deferred[0]['bones']['Translation_Data'][12:15])
    end = Vector(deferred[-1]['bones']['Translation_Data'][12:15])
    stride = (end-start).length
    if stride <= 0:
        raise ValueError('Native Walk has no deferred translation')
    low_foot_velocities = []
    direction_evidence = {}
    for side in ('L', 'R'):
        bone = f'Bip01_{side}_Foot'
        rows = sources['walk']['models']
        heights = sorted(row[bone].translation.z for row in rows)
        threshold = heights[len(heights)//4]
        velocities = []
        for index in range(1, len(rows)):
            a, b = rows[index-1][bone].translation, rows[index][bone].translation
            if a.z <= threshold and b.z <= threshold:
                dt = sources['walk']['times'][index]-sources['walk']['times'][index-1]
                velocities.append((b.y-a.y)/dt)
        if not velocities:
            raise ValueError(f'Cannot establish walking direction from {side} foot')
        ordered = sorted(velocities)
        median = ordered[len(ordered)//2]
        direction_evidence[side] = dict(low_height_threshold=threshold,
                                        low_foot_y_velocity_median=median,
                                        samples=len(velocities))
        low_foot_velocities.append(median)
    if not all(value < -1e-5 for value in low_foot_velocities):
        raise ValueError('Expected both low feet to move backward along Blender -Y')

    walk_weight = 1.0 if candidate else .8
    rate = .8*1.04 if candidate else 1.04
    speed = stride/loop*.8*1.04
    frames, worlds, traces = [], [], []
    frame_times = [frame/fps for frame in range(math.floor(duration*fps)+1)]
    if duration-frame_times[-1] > 1e-9:
        frame_times.append(duration)
    for time in frame_times:
        phase = (time*rate) % loop
        walk = at(sources['walk'], phase)
        idle = at(sources['idle'], phase)
        models = {}
        for name in names:
            components = (neutral_local[name] if name in held else
                          blend(idle[name], walk[name], walk_weight))
            local = Matrix.LocRotScale(*components)
            models[name] = models[parents[name]] @ local if parents[name] else local
        world = Matrix.Translation((0, speed*time, 0))
        frames.append((time, models))
        worlds.append(world)
        traces.append(dict(time=time, heading=0., world=bridge.column_matrix(world),
                           feet={side: bridge.column_matrix(world @ models[f'Bip01_{side}_Foot'])
                                 for side in ('L', 'R')},
                           support={'L': None, 'R': None}, left_weight=.5))
    foot_ranges = {}
    for side in ('L', 'R'):
        positions = [poses[f'Bip01_{side}_Foot'].translation for _, poses in frames]
        foot_ranges[side] = {
            axis: [min(point[index] for point in positions), max(point[index] for point in positions)]
            for index, axis in enumerate(('x', 'y', 'z'))
        }
    settings = dict(
        schema='cart-straight-study-v1', motion='walk' if candidate else 'walk-baseline',
        scope='Offline steady native-gait comparison; not a runtime-ready animation.',
        source_clip='cart_pivot_walk.json',
        sources={key: dict(path=str(value['path']), sha256=value['sha256'])
                 for key, value in sources.items()},
        duration_seconds=duration, fps=fps, native_cycle_seconds=loop,
        playback_rate=rate, walk_weight=walk_weight, idle_weight=1-walk_weight,
        cycle_seconds=loop/rate, cycles=duration*rate/loop,
        deferred_distance_per_full_native_cycle=stride,
        nominal_root_speed=speed, nominal_root_distance=speed*duration,
        units='native model/deferred-root units; no conversion to metres asserted',
        actor_forward_blender=[0, 1, 0], direction_evidence=direction_evidence,
        actor_local_foot_ranges=foot_ranges,
        held_neutral_local_bones=sorted(held),
        limitations=[
            'Dense source poses are locally decomposed and nlerp-resampled, not replayed by the native mixer.',
            'Neutral Spine1 descendants approximate the held mask; sampled Spine remains the native leg ancestor.',
            'The caller must fit hands to the cart after sampling.',
            'Support and load transfer are unclassified; no exact planted-foot or zero-slip claim.',
            'Actor translation is uniform nominal extracted motion; collisions and gait transitions are absent.',
            'Baseline models .8 Walk/.2 Idle with synchronized phases, not every live animation layer.',
        ],
    )
    return dict(frames=frames, worlds=worlds, traces=traces, settings=settings)
