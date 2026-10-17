#!/usr/bin/env python3
"""Bake final native Bob model-space poses into a text .x skeletal clip.

Input is a JSON array of {"time": seconds, "bones": {name: [16 floats]}}.
Matrices use JOML column-major order, after native MAKE_LEFT_HANDED import.
Use Bob_Idle.x as the template; import the result with scale=1 and no rotation
modifier, as native .x assets do. Only rigid poses are supported.
"""
import argparse
import json
from pathlib import Path
import re


TICKS_PER_SECOND = 1_000_000
MAX_SAMPLES = 3601
MAX_DURATION = 60
IDENTIFIER = r'[A-Za-z_][A-Za-z_0-9]*'
TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/|[{}]', re.S)
HEADER = re.compile(r'\b(Frame|AnimationSet|AnimTicksPerSecond|Material)\s+(?:([A-Za-z_][A-Za-z_0-9-]*)\s*)?\{')
# AnimationOnly still requires a skinned mesh; this authored carrier is never rendered.
CARRIER = '''Frame Body {
 Mesh AnimationCarrier {
  3;
  0.000000;0.000000;0.000000;,
  0.001000;0.000000;0.000000;,
  0.000000;0.001000;0.000000;;
  1;
  3;0,1,2;;
  SkinWeights {
   "Dummy01";
   3;
   0,1,2;
   1.000000,1.000000,1.000000;
   1.000000,0.000000,0.000000,0.000000,0.000000,1.000000,0.000000,0.000000,0.000000,0.000000,1.000000,0.000000,0.000000,0.000000,0.000000,1.000000;;
  }
 }
}'''


def template_parts(source):
    """Keep the Bob skeleton, replacing vanilla geometry with an authored carrier."""
    if not source.startswith('xof 0303txt 0032'):
        raise ValueError('template must be a text xof 0303txt 0032 file')
    # Ignore strings/comments when finding object headers and matching braces.
    clean = TOKEN.sub(lambda m: m[0] if m[0] in ('{', '}') else ' ' * len(m[0]), source)
    stack, ends = [], {}
    for token in re.finditer(r'[{}]', clean):
        if token[0] == '{':
            stack.append(token.start())
        elif stack:
            ends[stack.pop()] = token.end()
        else:
            raise ValueError('unbalanced template braces')
    if stack:
        raise ValueError('unbalanced template braces')
    frames, animations, ticks, materials = [], [], [], []
    body = None
    for match in HEADER.finditer(clean):
        if re.search(r'\btemplate\s*$', clean[:match.start()]):
            continue
        end = ends[match.end() - 1]
        kind, name = match.groups()
        if kind == 'Frame':
            if name is None:
                raise ValueError('unnamed skeleton frame')
            parent = next((f[0] for f in reversed(frames) if f[2] > match.start()), None)
            frames.append((name, parent, end))
            if name == 'Body':
                body = (match.start(), end)
        elif kind == 'AnimationSet':
            animations.append((match.start(), end))
        elif kind == 'Material':
            materials.append((match.start(), end))
        else:
            ticks.append((match.start(), end))
    bones = {name: parent for name, parent, _ in frames if name != 'Body'}
    if (body is None or len(frames) != 46 or len(bones) != 45 or
            bones.get('Bip01') != 'Dummy01' or
            'Dummy01' not in bones or bones['Dummy01'] is not None or
            'Translation_Data' not in bones or bones['Translation_Data'] is not None or
            any(parent is not None and parent not in bones for parent in bones.values())):
        raise ValueError('template must contain the 45-bone Bob skeleton and Body mesh frame')
    if len(ticks) != 1 or not animations:
        raise ValueError('template must contain one tick rate and at least one AnimationSet')
    # ImportedSkeleton attaches this sibling .x frame to the native root bone.
    bones['Translation_Data'] = 'Dummy01'
    spans = [(a, b, '') for a, b in animations] + [(*ticks[0], f'AnimTicksPerSecond {{\n {TICKS_PER_SECOND};\n}}')]
    spans.append((*body, CARRIER))
    spans.extend((start, end, '') for start, end in materials
                 if not body[0] <= start < body[1])
    for start, end, replacement in sorted(spans, reverse=True):
        source = source[:start] + replacement + source[end:]
    return source, bones


def multiply(a, b):
    return [sum(a[k * 4 + row] * b[col * 4 + k] for k in range(4))
            for col in range(4) for row in range(4)]


def inverse_rigid(matrix):
    inverse = [matrix[row * 4 + col] if row < 3 and col < 3 else 0.0
               for col in range(4) for row in range(4)]
    inverse[15] = 1.0
    inverse[12:15] = [-sum(inverse[k * 4 + row] * matrix[12 + k] for k in range(3))
                      for row in range(3)]
    return inverse


def validate_matrix(matrix, label):
    if (not isinstance(matrix, list) or len(matrix) != 16 or
            any(type(value) not in (float, int) or not -3.4028234e38 <= value <= 3.4028234e38
                for value in matrix)):
        raise ValueError(f'{label}: expected 16 finite native float numbers')
    if any(abs(matrix[i] - expected) > 1e-5 for i, expected in ((3, 0), (7, 0), (11, 0), (15, 1))):
        raise ValueError(f'{label}: expected affine matrix')
    for col in range(3):
        for other in range(3):
            dot = sum(matrix[col * 4 + row] * matrix[other * 4 + row] for row in range(3))
            if abs(dot - (col == other)) > 1e-3:
                raise ValueError(f'{label}: scale/shear is unsupported')
    a, b, c = (matrix[i:i + 3] for i in (0, 4, 8))
    determinant = (a[0] * (b[1] * c[2] - b[2] * c[1]) -
                   b[0] * (a[1] * c[2] - a[2] * c[1]) +
                   c[0] * (a[1] * b[2] - a[2] * b[1]))
    if determinant < 0:
        raise ValueError(f'{label}: reflected pose is unsupported')


def bake(source, samples, name):
    if not isinstance(name, str) or not re.fullmatch(IDENTIFIER, name) or len(name) > 80:
        raise ValueError('clip name must be an ASCII identifier of at most 80 characters')
    source, parents = template_parts(source)
    if not isinstance(samples, list) or not 2 <= len(samples) <= MAX_SAMPLES:
        raise ValueError(f'expected 2..{MAX_SAMPLES} samples')
    keys = {bone: [] for bone in parents}
    previous_time, previous_tick = -1, -1
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict) or 'time' not in sample or 'bones' not in sample:
            raise ValueError(f'sample {index}: expected time and bones')
        time, matrices = sample['time'], sample['bones']
        if (type(time) not in (int, float) or (index == 0 and time != 0) or
                not previous_time < time <= MAX_DURATION):
            raise ValueError(f'sample {index}: time must start at zero, increase, and be <= {MAX_DURATION}s')
        tick = round(time * TICKS_PER_SECOND)
        if tick <= previous_tick:
            raise ValueError(f'sample {index}: times collide at microsecond precision')
        previous_time, previous_tick = time, tick
        if not isinstance(matrices, dict) or matrices.keys() != parents.keys():
            raise ValueError(f'sample {index}: bone names must exactly match all 45 template bones')
        for bone, matrix in matrices.items():
            validate_matrix(matrix, f'sample {index} bone {bone}')
        for bone, parent in parents.items():
            local = matrices[bone] if parent is None else multiply(inverse_rigid(matrices[parent]), matrices[bone])
            validate_matrix(local, f'sample {index} local bone {bone}')
            # X's implicit handedness conversion cancels MAKE_LEFT_HANDED.
            # The shipped native parser requires decimal float tokens.
            values = ','.join(format(value, '.9f') for value in local)
            keys[bone].append(f'   {tick};16;{values};;')
    animation = [f'AnimationSet {name} {{']
    for bone, rows in keys.items():
        animation.extend((' Animation {', f'  {{ {bone} }}', '  AnimationKey {',
                          '   4;', f'   {len(rows)};', ',\n'.join(rows) + ';', '  }', ' }'))
    animation.append('}')
    source = '\n'.join(line.rstrip() for line in source.splitlines())
    return source.rstrip() + '\n\n' + '\n'.join(animation) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--template', required=True, type=Path)
    parser.add_argument('--input', required=True, type=Path, help='JSON pose sample array')
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--name', required=True, help='new native clip identifier')
    args = parser.parse_args()
    if args.output.resolve() in (args.template.resolve(), args.input.resolve()):
        parser.error('output must differ from template and input')
    try:
        result = bake(args.template.read_text(), json.loads(args.input.read_text()), args.name)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    args.output.write_text(result)


if __name__ == '__main__':
    main()
