#!/usr/bin/env python3
"""Regenerate the source-pinned wooden-cart leg-clearance data (requires NumPy).

Run with --game GAME_JAVA_DIRECTORY --mesh Wheelbarrow_wood.fbx. Add --check
for a read-only reproducibility check. Normal Java builds consume the committed
class; neither NumPy nor Blender is a game/runtime dependency. The profiles are
native source geometry, not a claim about every rendered garment or animation.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import itertools
import json
from pathlib import Path
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
HELPERS = ROOT / "tests/native_queue/contributions/wooden_cart_motion/evidence"
sys.path.insert(0, str(HELPERS))
import clearance_geometry  # noqa: E402
from shaft_components import build_components  # noqa: E402

DEFAULT_OUTPUT = ROOT / "JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartLegClearanceData.java"
LOWER_BONES = frozenset(("Bip01_Pelvis", "Bip01_Spine", "Bip01_L_Thigh",
                         "Bip01_R_Thigh", "Bip01_L_Calf", "Bip01_R_Calf"))
# Source identity is deliberately reviewed together with the generated profile.
SKIN_SOURCES = (
    (False, False, "media/models_X/Skinned/MaleBody.x", 194010,
     "a0a7cbb3f8fb55827f4039edd04f9af28299d76ae9160484069084faca2aff01", (258, 384, 437, 17)),
    (True, False, "media/models_X/Skinned/FemaleBody.x", 200557,
     "aa78e223c06d99c7ba20ca500c304fc8540f92276430eee5074bc8a817d58039", (250, 364, 385, 13)),
    (False, True, "media/models_X/Skinned/Clothes/Bob_Trousers.x", 125195,
     "80c71058691f1276d4ec8eea3e1ee237aa9e37fe858cdec9b104fe7f7ee93b41", (186, 240, 252, 8)),
    (True, True, "media/models_X/Skinned/Clothes/Kate_Trousers.x", 104371,
     "e645fd5934f518be96251a396765ad28581eea4797bf0b3126008575f4abe02a", (186, 240, 254, 8)),
)
CART_SUFFIX = "media/models_X/weapons/2handed/Wheelbarrow_wood.fbx"
CART_BYTES = 246668
CART_SHA256 = "651c490c4a706cf42e7a6425b5ea7be4b8902f2197155c0199747f2769a95835"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def source_identity(path, expected_bytes, expected_sha):
    raw = path.read_bytes()
    require(len(raw) == expected_bytes, f"Unsupported source size: {path}")
    require(hashlib.sha256(raw).hexdigest() == expected_sha, f"Unsupported source SHA-256: {path}")


def skin_profile(game, source):
    female, trousers, suffix, size, digest, expected = source
    source_identity(game / suffix, size, digest)
    count, parts, _, faces = clearance_geometry.model(game, female, trousers)
    if not trousers:
        # Match the tracked whole-lower-body source analysis: include every
        # triangle touching a vertex influenced by one of these six bones.
        lower = np.zeros(count, dtype=bool)
        for name, ids, weights, _ in parts:
            if name in LOWER_BONES:
                lower[ids[weights > 0]] = True
        faces = faces[lower[faces].any(axis=1)]
    vertices = np.unique(faces)
    compact = np.full(count, -1, dtype=int)
    compact[vertices] = np.arange(len(vertices))
    bones, influence_vertex, influence_bone, weighted_points = [], [], [], []
    totals = np.zeros(len(vertices))
    for name, ids, weights, points in parts:
        selected = (compact[ids] >= 0) & (weights > 0)
        if not selected.any():
            continue
        require(name not in bones, "Duplicate source skin bone")
        require(np.isfinite(points[selected]).all(), "Nonfinite source bind point")
        require(np.max(abs(points[selected, 3] - 1)) < 1e-8, "Non-affine source skin offset")
        bone = len(bones)
        bones.append(name)
        for vertex, weight, point in zip(ids[selected], weights[selected], points[selected]):
            require(0 < weight <= 1, "Invalid positive source skin weight")
            index = int(compact[vertex])
            influence_vertex.append(index)
            influence_bone.append(bone)
            weighted_points.extend((*point[:3] * weight, weight))
            totals[index] += weight
    require(np.max(abs(totals - 1)) < 1e-4, "Selected source vertex is not fully weighted")
    require((len(vertices), len(faces), len(influence_vertex), len(bones)) == expected,
            f"Unexpected selected source profile counts: {suffix}")
    points32 = np.asarray(weighted_points, dtype=np.float32)
    require(np.isfinite(points32).all(), "Nonfinite float32 skin profile")
    return dict(suffix=suffix, sha256=digest, bytes=size, bones=bones,
                vertexCount=len(vertices), influenceVertex=influence_vertex,
                influenceBone=influence_bone, weightedPoints=points32.tolist(),
                triangles=compact[faces].ravel().tolist())


def kernel_fan(component):
    triangles = component["triangles"]
    signed_volume = float(np.einsum("ij,ij->i", triangles[:, 0],
                                  np.cross(triangles[:, 1], triangles[:, 2])).sum() / 6)
    require(abs(signed_volume) > 1e-20, "Degenerate closed shaft component")
    normals = np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0])
    lengths = np.linalg.norm(normals, axis=1)
    require((lengths > 1e-15).all(), "Degenerate closed shaft face")
    normals *= 1 if signed_volume > 0 else -1
    normals /= lengths[:, None]
    offsets = np.einsum("ij,ij->i", normals, triangles[:, 0])
    planes = []
    for normal, offset in zip(normals, offsets):
        if not any(np.linalg.norm(normal - old[:3]) < 1e-6 and abs(offset - old[3]) < 1e-10
                   for old in planes):
            planes.append(np.r_[normal, offset])
    planes = np.asarray(planes)
    triples = np.asarray(list(itertools.combinations(range(len(planes)), 3)))
    matrices, right = planes[triples, :3], planes[triples, 3]
    nonsingular = abs(np.linalg.det(matrices)) > 1e-10
    candidates = np.linalg.solve(matrices[nonsingular], right[nonsingular, :, None])[:, :, 0]
    feasible = candidates[(candidates @ planes[:, :3].T <= planes[:, 3] + 1e-11).all(axis=1)]
    require(len(feasible) > 0, "Closed shaft has no verified star-shaped kernel")
    kernel = feasible.mean(axis=0)
    violation = float((kernel @ planes[:, :3].T - planes[:, 3]).max())
    require(violation < -1e-8, "Shaft kernel is not strictly interior")
    tetrahedra = np.concatenate((np.tile(kernel, (len(triangles), 1, 1)), triangles), axis=1)
    signed_tetra = np.einsum("ij,ij->i", tetrahedra[:, 1] - kernel,
                            np.cross(tetrahedra[:, 2] - kernel, tetrahedra[:, 3] - kernel)) / 6
    require((signed_tetra * signed_volume > 0).all(), "Inconsistent shaft fan orientation")
    error = float(abs(abs(signed_tetra).sum() - abs(signed_volume)) / abs(signed_volume))
    require(error < 1e-10, "Shaft fan volume does not match the closed source surface")
    return tetrahedra, dict(kernelPlaneViolation=violation, relativeVolumeError=error)


def cart_profile(mesh):
    source_identity(mesh, CART_BYTES, CART_SHA256)
    vertices, components = build_components(mesh)
    footprint = np.unique(np.asarray(vertices, dtype=np.float32), axis=0)
    require(len(vertices) == 3123 and len(footprint) == 3108, "Unexpected whole-cart source vertex count")
    require(np.isfinite(footprint).all(), "Nonfinite whole-cart source vertices")
    expected = ((True, 32, 60), (True, 32, 60), (True, 24, 44),
                (True, 24, 44), (False, 16, 22), (False, 16, 22))
    require(tuple((c["closed"], len(c["vertices"]), len(c["triangles"])) for c in components) == expected,
            "Unsupported calibrated shaft/brace topology")
    primitives, checks = [], []
    for index, component in enumerate(components):
        triangles = component["triangles"]
        if component["closed"]:
            counts, winding = Counter(), Counter()
            for triangle in triangles:
                for j in range(3):
                    a = tuple(np.round(triangle[j], 10))
                    b = tuple(np.round(triangle[(j + 1) % 3], 10))
                    edge = tuple(sorted((a, b)))
                    counts[edge] += 1
                    winding[edge] += 1 if a < b else -1
            require(all(value == 2 for value in counts.values()) and not any(winding.values()),
                    "Closed shaft is not a consistently oriented edge manifold")
            pieces, check = kernel_fan(component)
            checks.append(dict(component=index, **check))
        else:
            # Preserve open brace surfaces exactly, never their convex hull.
            pieces = triangles
        primitives.extend(np.asarray(piece, dtype=np.float32).ravel().tolist() for piece in pieces)
    require(sum(len(p) == 12 for p in primitives) == 208 and sum(len(p) == 9 for p in primitives) == 44,
            "Unexpected primitive decomposition counts")
    require(all(np.isfinite(p).all() for p in primitives), "Nonfinite float32 cart profile")
    return dict(suffix=CART_SUFFIX, sha256=CART_SHA256, bytes=CART_BYTES, primitives=primitives,
                footprintPoints=footprint.ravel().tolist()), checks


def java_float(value):
    # Nine significant decimal digits round-trip a finite IEEE float32.
    value = float(np.float32(value))
    return "0f" if value == 0 else format(value, ".9g") + "f"


def array_method(name, kind, values):
    convert = java_float if kind == "float" else str
    width = 8 if kind == "float" else 16
    lines = [f"    private static {kind}[] {name}() {{", f"        return new {kind}[] {{"]
    for i in range(0, len(values), width):
        lines.append("            " + ", ".join(convert(v) for v in values[i:i + width]) + ",")
    return "\n".join((*lines, "        };", "    }", ""))


def chunked_float_method(name, values):
    # Keep every generated initializer below the JVM 64 KiB method limit.
    chunks = [values[i:i + 2048] for i in range(0, len(values), 2048)]
    methods = [array_method(f"{name}{i}", "float", chunk) for i, chunk in enumerate(chunks)]
    lines = [f"    private static float[] {name}() {{", f"        float[] result = new float[{len(values)}];"]
    offset = 0
    for i, chunk in enumerate(chunks):
        lines.append(f"        System.arraycopy({name}{i}(), 0, result, {offset}, {len(chunk)});")
        offset += len(chunk)
    lines.extend(("        return result;", "    }", ""))
    return "\n".join((*methods, *lines))


def java_source(skins, cart):
    lines = ["package net.alexredby.pztoolkitjavapatches;", "",
             "/** Generated by tools/cart_leg_clearance_profile.py; do not edit by hand.",
             " * Native source cage only; actual garment palettes and unseen poses need separate validation.",
             " */", "final class CartLegClearanceData {",
             "    record Skin(String suffix, String sha256, long bytes, String[] bones, int vertexCount,",
             "                int[] influenceVertex, int[] influenceBone, float[] weightedPoints, int[] triangles) { }",
             "    record Cart(String suffix, String sha256, long bytes, float[][] primitives, float[] footprintPoints) { }", "",
             "    // SKINS: male lower body, female lower body, Bob trousers, Kate trousers.",
             "    // Each influence stores (offsetPoint.x*w, offsetPoint.y*w, offsetPoint.z*w, w).",
             "    // Vertices and bones use compact indices; native palette names remain exact.",
             "    static final Skin[] SKINS = {"]
    for i, skin in enumerate(skins):
        lines.extend((f"        new Skin({json.dumps(skin['suffix'])},", f"            {json.dumps(skin['sha256'])}, {skin['bytes']}L,",
                      "            new String[] {" + ", ".join(json.dumps(b) for b in skin["bones"]) + "},",
                      f"            {skin['vertexCount']}, skin{i}Vertex(), skin{i}Bone(), skin{i}Points(), skin{i}Triangles()),"))
    lines.extend(("    };", "", "    // Native cart Z reflection; 208 exact fan tetrahedra and 44 open-brace triangles.",
                  f"    static final Cart WOOD = new Cart({json.dumps(cart['suffix'])},",
                  f"        {json.dumps(cart['sha256'])}, {cart['bytes']}L, woodPrimitives(), woodFootprintPoints());", "",
                  "    private CartLegClearanceData() { }", ""))
    for i, skin in enumerate(skins):
        for method, kind, key in (("Vertex", "int", "influenceVertex"), ("Bone", "int", "influenceBone"),
                                  ("Points", "float", "weightedPoints"), ("Triangles", "int", "triangles")):
            lines.append(array_method(f"skin{i}{method}", kind, skin[key]))
    lines.append("    // Every unique original FBX vertex, including wheel/tray; never a convex-hull substitute.")
    lines.append(chunked_float_method("woodFootprintPoints", cart["footprintPoints"]))
    lines.extend(("    private static float[][] woodPrimitives() {", "        return new float[][] {"))
    for primitive in cart["primitives"]:
        lines.append("            {" + ", ".join(java_float(v) for v in primitive) + "},")
    lines.extend(("        };", "    }", "}", ""))
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", required=True, type=Path, help="Directory containing native media/models_X")
    parser.add_argument("--mesh", required=True, type=Path, help="Original SaucedWheelbarrow wooden FBX")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true", help="Compare generated bytes without writing")
    args = parser.parse_args()
    try:
        skins = [skin_profile(args.game, source) for source in SKIN_SOURCES]
        cart, checks = cart_profile(args.mesh)
        generated = java_source(skins, cart)
        if args.check:
            require(args.output.is_file() and args.output.read_bytes() == generated.encode("utf-8"),
                    f"Generated data differs: {args.output}")
        else:
            args.output.write_text(generated, encoding="utf-8", newline="\n")
    except (OSError, ValueError, AssertionError, np.linalg.LinAlgError) as error:
        parser.exit(1, f"cart leg-clearance profile: {error}\n")
    print(json.dumps(dict(operation="checked" if args.check else "generated", output=str(args.output),
                          skins=[dict(suffix=s["suffix"], vertices=s["vertexCount"],
                                      triangles=len(s["triangles"]) // 3, influences=len(s["influenceVertex"]),
                                      bones=len(s["bones"])) for s in skins],
                          cart=dict(tetrahedra=208, openTriangles=44,
                                    footprintVertices=len(cart["footprintPoints"]) // 3, kernelChecks=checks)), indent=2))


if __name__ == "__main__":
    main()
