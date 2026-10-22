"""Live native-LBS body preview for a cart_clip_blender authoring armature.

Call build_preview(rig, Path('MaleBody.x')) inside Blender. The returned mesh
uses ordinary saved constraints and an Armature modifier; no frame handlers or
baked shape keys are needed. The authoring skeleton and its action are untouched.
"""
from dataclasses import dataclass
import json
import math
from pathlib import Path
import re

import cart_clip_blender as bridge


@dataclass(frozen=True)
class SkinWeights:
    indices: tuple
    weights: tuple
    offset: tuple


@dataclass(frozen=True)
class BodyMesh:
    vertices: tuple
    faces: tuple
    skin: dict


_NUMBER = r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?'
_COMMENTS = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/')


def _without_comments(text):
    return _COMMENTS.sub(lambda m: m[0] if m[0].startswith('"') else ' ', text)


def _block(text, opening):
    """Find a balanced .x block, ignoring braces in quoted strings."""
    depth = 1
    for token in re.finditer(r'"(?:\\.|[^"\\])*"|[{}]', text[opening + 1:]):
        if token[0] == '{':
            depth += 1
        elif token[0] == '}':
            depth -= 1
            if not depth:
                return text[opening + 1:opening + 1 + token.start()]
    raise ValueError('unterminated .x block')


def _mesh_children(text):
    position = 0
    supported = {'MeshNormals', 'MeshMaterialList', 'MeshTextureCoords', 'XSkinMeshHeader', 'SkinWeights'}
    while position < len(text):
        position += re.match(r'[\s;,]*', text[position:]).end()
        if position == len(text):
            return
        match = re.match(r'([A-Za-z_]\w*)(?:\s+[A-Za-z_]\w*)?\s*\{', text[position:])
        if match is None or match[1] not in supported:
            raise ValueError('unexpected values or unsupported native body Mesh child')
        opening = position + match.end() - 1
        contents = _block(text, opening)
        yield match[1], contents
        position = opening + len(contents) + 2


class _Values:
    def __init__(self, text):
        self.text = text
        self.position = 0

    def _skip(self):
        match = re.match(r'[\s;,]*', self.text[self.position:])
        self.position += match.end()

    def number(self, integer=False):
        self._skip()
        match = re.match(_NUMBER, self.text[self.position:])
        if match is None:
            raise ValueError('missing numeric .x value')
        self.position += match.end()
        value = float(match[0])
        if not math.isfinite(value) or integer and (not match[0].isdigit()):
            raise ValueError('invalid .x number or integer index/count')
        return int(value) if integer else value

    def count(self, maximum):
        value = self.number(integer=True)
        if not 1 <= value <= maximum:
            raise ValueError('unsupported .x count')
        return value

    def name(self):
        self._skip()
        match = re.match(r'"([A-Za-z_][A-Za-z_0-9]*)"', self.text[self.position:])
        if match is None:
            raise ValueError('expected a quoted native bone name')
        self.position += match.end()
        return match[1]

    def end(self):
        self._skip()
        if self.position != len(self.text):
            raise ValueError('unexpected values in SkinWeights')


def parse_body(text, bone_names=None):
    """Read the single triangulated, fully weighted native text-.x body mesh.

    Offsets are the original column-major SkinWeights matrices. In particular,
    MAKE_LEFT_HANDED does not require an additional reflection of these points.
    """
    if not text.startswith('xof 0303txt '):
        raise ValueError('expected native text .x 0303 format')
    text = _without_comments(text)
    meshes = list(re.finditer(r'\bMesh\s+[A-Za-z_]\w*\s*\{', text))
    if len(meshes) != 1:
        raise ValueError('expected exactly one named native body Mesh')
    mesh = _block(text, meshes[0].end() - 1)
    values = _Values(mesh)
    count = values.count(100000)
    vertices = tuple(tuple(values.number() for _ in range(3)) for _ in range(count))
    face_count = values.count(200000)
    faces = []
    for _ in range(face_count):
        if values.number(integer=True) != 3:
            raise ValueError('native body faces must be triangles')
        face = tuple(values.number(integer=True) for _ in range(3))
        if len(set(face)) != 3 or any(index >= count for index in face):
            raise ValueError('invalid native body face vertex index')
        faces.append(face)
    skin = {}
    totals = [0.0] * count
    remainder = mesh[values.position:]
    for kind, contents in _mesh_children(remainder):
        if kind != 'SkinWeights':
            continue
        weights = _Values(contents)
        name = weights.name()
        if name in skin or bone_names is not None and name not in bone_names:
            raise ValueError(f'duplicate or unknown skin bone {name}')
        # Native MaleBody includes a zero-influence BackPack offset block.
        length = weights.number(integer=True)
        if length > count:
            raise ValueError(f'invalid skin influence count for {name}')
        indices = tuple(weights.number(integer=True) for _ in range(length))
        if len(set(indices)) != length or any(index >= count for index in indices):
            raise ValueError(f'invalid skin vertex indices for {name}')
        amounts = tuple(weights.number() for _ in range(length))
        if any(not 0 <= weight <= 1 for weight in amounts):
            raise ValueError(f'invalid skin weights for {name}')
        offset = tuple(weights.number() for _ in range(16))
        weights.end()
        bridge.baker.validate_matrix(list(offset), f'skin offset {name}')
        skin[name] = SkinWeights(indices, amounts, offset)
        for index, weight in zip(indices, amounts):
            totals[index] += weight
    if not skin or any(abs(total - 1) > 1e-5 for total in totals):
        raise ValueError('every body vertex must have native skin weights summing to one')
    return BodyMesh(vertices, tuple(faces), skin)


def transform_point(matrix, point):
    return tuple(sum(matrix[col * 4 + row] * point[col] for col in range(3)) + matrix[12 + row]
                 for row in range(3))


def skin_vertices(body, native_models):
    """Independent direct native LBS reference, returned in Blender model basis."""
    result = [[0.0, 0.0, 0.0] for _ in body.vertices]
    for name, skin in body.skin.items():
        matrix = bridge.baker.multiply(bridge.MODEL_BASIS,
                 bridge.baker.multiply(native_models[name], skin.offset))
        for index, weight in zip(skin.indices, skin.weights):
            point = transform_point(matrix, body.vertices[index])
            for axis in range(3):
                result[index][axis] += weight * point[axis]
    return result


def _region(name):
    if 'Head' in name or 'Neck' in name:
        return 0
    if any(part in name for part in ('Thigh', 'Calf', 'Foot', 'Toe')):
        return 2
    if any(part in name for part in ('Arm', 'Hand', 'Finger', 'Clavicle')):
        return 3
    return 1


def build_preview(rig, body_path: Path):
    """Attach an editable live-skinned body; return the new Blender mesh object.

    Requires an untransformed authoring rig created by cart_clip_blender. Its
    collection gains one body and one hidden deform armature. Delete the body
    and its modifier's armature to remove this preview. No source asset changes.
    """
    bpy, Matrix = bridge.blender_api()
    if rig.type != 'ARMATURE' or bridge.PROPERTY not in rig:
        raise ValueError('expected a cart authoring armature')
    metadata = json.loads(rig[bridge.PROPERTY])
    bridge.validate_metadata(metadata)
    parents = metadata['parents']
    order = bridge.parent_order(parents)
    if set(rig.data.bones.keys()) != set(parents):
        raise ValueError('authoring bone names changed')
    for name, parent in parents.items():
        bone = rig.data.bones[name]
        if (bone.parent.name if bone.parent else None) != parent:
            raise ValueError(f'authoring parent changed for {name}')
    if max(abs(a-b) for a,b in zip(bridge.column_matrix(rig.matrix_world), bridge.IDENTITY)) > 1e-6:
        raise ValueError('authoring rig object transform must remain identity')
    body = parse_body(Path(body_path).read_text(), parents)
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        raise ValueError('attach the preview in Object mode')
    active = bpy.context.view_layer.objects.active
    selected = list(bpy.context.selected_objects)
    collection = rig.users_collection[0]
    armature = bpy.data.armatures.new('CartPreviewBindSkeleton')
    deform = bpy.data.objects.new('CartPreviewDeform', armature)
    collection.objects.link(deform)
    try:
        for obj in selected:
            obj.select_set(False)
        deform.select_set(True)
        bpy.context.view_layer.objects.active = deform
        bpy.ops.object.mode_set(mode='EDIT')
        for name in order:
            bone = armature.edit_bones.new(name)
            bone.length = .04
            # Weighted bind rest must exactly invert the supplied offset, even
            # its text rounding. Unweighted bones only carry the hierarchy;
            # their POSE constraints also replace the complete model matrix.
            if name in body.skin:
                offset = Matrix(bridge.matrix_rows(body.skin[name].offset))
                native_rest = bridge.column_matrix(offset.inverted())
                bone.matrix = Matrix(bridge.matrix_rows(bridge.native_to_blender(native_rest)))
            else:
                bone.matrix = rig.data.bones[name].matrix_local.copy()
            if parents[name] is not None:
                bone.parent = armature.edit_bones[parents[name]]
                bone.use_connect = False
        bpy.ops.object.mode_set(mode='OBJECT')
        for name in order:
            constraint = deform.pose.bones[name].constraints.new('COPY_TRANSFORMS')
            constraint.target = rig
            constraint.subtarget = name
            constraint.target_space = 'POSE'
            constraint.owner_space = 'POSE'
            constraint.mix_mode = 'REPLACE'
        mesh = bpy.data.meshes.new('CartPreviewBody')
        mesh.from_pydata([transform_point(bridge.MODEL_BASIS, point) for point in body.vertices], [], body.faces)
        mesh.update()
        obj = bpy.data.objects.new('CartPreviewBody', mesh)
        collection.objects.link(obj)
        obj['pz_cart_preview_source'] = str(Path(body_path).resolve())
        obj['pz_cart_preview_rig'] = rig.name
        for name, skin in body.skin.items():
            group = obj.vertex_groups.new(name=name)
            for index, weight in zip(skin.indices, skin.weights):
                group.add([index], weight, 'REPLACE')
        modifier = obj.modifiers.new('Native linear skinning', 'ARMATURE')
        modifier.object = deform
        modifier.use_deform_preserve_volume = False
        modifier.use_vertex_groups = True
        modifier.use_bone_envelopes = False
        colors = ((.59,.65,.69,1), (.075,.27,.32,1), (.08,.14,.23,1), (.47,.55,.6,1))
        for name, color in zip(('Head', 'Torso', 'Legs', 'Arms'), colors):
            material = bpy.data.materials.new('CartPreview ' + name)
            material.diffuse_color = color
            mesh.materials.append(material)
        regions = [[0.0] * 4 for _ in body.vertices]
        for name, skin in body.skin.items():
            for index, weight in zip(skin.indices, skin.weights):
                regions[index][_region(name)] += weight
        for polygon, face in zip(mesh.polygons, body.faces):
            polygon.material_index = max(range(4), key=lambda r: sum(regions[index][r] for index in face))
            polygon.use_smooth = True
        deform.hide_render = True
        # Per-view-layer hiding preserves modifier/constraint depsgraph updates.
        # hide_viewport would disable this armature instead of just its drawing.
        deform.hide_set(True)
        bpy.context.view_layer.update()
        return obj
    finally:
        if bpy.context.object and bpy.context.object.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')
        deform.select_set(False)
        for obj in selected:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = active
