"""Native DirectX skinning and calibrated wooden-shaft geometry, without game imports."""
import json
import re
from pathlib import Path
import numpy as np


def model(game, female, pants=False):
    directory = game / 'media/models_X/Skinned'
    name = 'FemaleBody.x' if female else 'MaleBody.x'
    if pants:
        directory /= 'Clothes'
        name = 'Kate_Trousers.x' if female else 'Bob_Trousers.x'
    text = (directory / name).read_text()
    meshes = list(re.finditer(r'Mesh \w+ \{', text))
    if len(meshes) > 1:
        text = text[:meshes[1].start()]
    match = re.search(r'Mesh \w+ \{\s+(\d+);(.*)', text, re.S)
    count = int(match[1])
    lines = match[2].splitlines()
    vertices = np.array([list(map(float, line.split(';')[:3])) for line in lines[1:count+1]])
    vertices = np.c_[vertices, np.ones(count)]
    rest = '\n'.join(lines[count+1:])
    face_count = int(rest.split(';')[0])
    faces = np.array([list(map(int, value.split(','))) for value in re.findall(r'3;([0-9,]+);', rest)[:face_count]])
    assert len(faces) == face_count, 'Expected triangulated native DirectX mesh'
    parts, total = [], np.zeros(count)
    regions = {'hip': np.zeros(count, bool), 'belly': np.zeros(count, bool)}
    for name, size, data in re.findall(r'SkinWeights \{\s+"([^"]+)";\s+(\d+);(.*?)\}', text, re.S):
        values = np.array([float(x) for x in re.findall(r'-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?', data)])
        size = int(size)
        ids, weights = values[:size].astype(int), values[size:2*size]
        offset = values[2*size:2*size+16].reshape(4, 4).T
        parts.append((name, ids, weights, vertices[ids] @ offset.T))
        total[ids] += weights
        if name in ('Bip01_Spine', 'Bip01_Pelvis'):
            regions['hip'][ids[weights > 0]] = True
        if name == 'Bip01_Spine1':
            regions['belly'][ids[weights > 0]] = True
    assert len(parts) and np.any(total > 0), 'Missing skin weights'
    assert np.max(abs(total[total > 0] - 1)) < 1e-4
    if not pants:
        assert np.all(total > 0), 'Unweighted body vertices'
    return count, parts, regions, faces


def skin(row, mesh):
    count, parts, _, _ = mesh
    result = np.zeros((count, 3))
    bones = {name: np.asarray(value).reshape(4, 4).T for name, value in row['bones'].items()}
    for name, ids, weights, points in parts:
        if len(ids):
            result[ids] += (points @ bones[name].T)[:, :3] * weights[:, None]
    assert np.isfinite(result).all(), 'Nonfinite skinned body'
    return result


def shafts(path):
    vertices = np.frombuffer(path.read_bytes(), dtype='<f4').reshape(-1, 8)[:, :3].astype(float)
    assert len(vertices) and np.isfinite(vertices).all(), 'Invalid native vertex buffer'
    points = {}
    for side, sign in [('L', 1), ('R', -1)]:
        selected = vertices[(vertices[:, 1] > .003) & (vertices[:, 0] * sign > 0)]
        assert len(selected), 'Missing calibrated shaft vertices'
        points[side] = np.c_[selected, np.ones(len(selected))]
    return vertices, points


def separation(a, b):
    """Positive AABB gap proves separation; overlap remains inconclusive."""
    return float(np.maximum(b.min(0)-a.max(0), a.min(0)-b.max(0)).max())


def rows(path):
    with path.open() as source:
        for line in source:
            row = json.loads(line)
            assert type(row['female']) is bool
            assert np.isfinite(np.asarray(row['cart'], dtype=float)).all()
            yield row


def write_json(path, value):
    with path.open('x') as output:
        json.dump(value, output, indent=2, allow_nan=False)
        output.write('\n')
