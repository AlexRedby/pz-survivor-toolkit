"""Offline evidence checks. Never attaches an agent or launches Project Zomboid."""
import argparse
import os
from pathlib import Path
import py_compile
import subprocess
import tempfile
import numpy as np
import actual_mesh
from clearance_geometry import separation, skin

HERE = Path(__file__).resolve().parent


def geometry():
    actual_mesh.self_check()
    cube = np.array([[0., 0, 0], [1, 1, 1]])
    assert separation(cube, cube + [2, 0, 0]) == 1
    assert separation(cube, cube + .5) < 0
    native = np.eye(4)
    native[:3, 3] = [2, 3, 4]
    mesh = (1, [('test', np.array([0]), np.array([1.]), np.array([[1., 1, 1, 1]]))], {}, [])
    row = {'bones': {'test': native.T.reshape(-1).tolist()}}
    np.testing.assert_allclose(skin(row, mesh), [[3, 4, 5]])
    row['bones'].clear()
    try:
        skin(row, mesh)
    except KeyError:
        pass
    else:
        raise AssertionError('Missing native bones must not become a false PASS')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-java-dir', type=Path)
    parser.add_argument('--jdk', type=Path)
    parser.add_argument('--toolkit-classes', type=Path, help='Compiled candidate JavaPatches classes; no binaries are supplied here')
    args = parser.parse_args()
    geometry()
    with tempfile.TemporaryDirectory(prefix='wood-evidence-check-') as temp:
        output = Path(temp)
        for path in HERE.glob('*.py'):
            py_compile.compile(str(path), cfile=str(output / (path.name + 'c')), doraise=True)
        print('PYTHON_EVIDENCE_CHECK_PASS (syntax, triangle crossing/containment/coplanarity/distance, AABB and native skin matrices)')
        supplied = [args.game_java_dir, args.jdk, args.toolkit_classes]
        if not any(supplied):
            print('JAVA_EVIDENCE_CHECK_SKIPPED (supply --game-java-dir, --jdk, --toolkit-classes); live=NOT_RUN')
            return
        assert all(supplied), 'Supply all three Java dependency paths'
        dependencies = [args.game_java_dir / 'projectzomboid.jar', args.game_java_dir / 'ZombieBuddy.jar', args.toolkit_classes]
        assert all(path.exists() for path in dependencies), 'Missing compile dependency'
        compiler, java = args.jdk / 'bin/javac', args.jdk / 'bin/java'
        classpath = os.pathsep.join(map(str, dependencies))
        subprocess.run([str(compiler), '--release', '17', '-cp', classpath, '-d', str(output), *map(str, HERE.glob('*.java'))], check=True)
        runtime = os.pathsep.join([str(output), classpath])
        for check in ['WoodenWheelProbeCheck', 'GripPoseProbeCheck', 'ClearanceProbeCheck']:
            subprocess.run([str(java), '--enable-native-access=ALL-UNNAMED', '-cp', runtime, check], check=True)
        print('JAVA_EVIDENCE_CHECK_PASS (compile and offline probe checks); live=NOT_RUN')


if __name__ == '__main__':
    main()
