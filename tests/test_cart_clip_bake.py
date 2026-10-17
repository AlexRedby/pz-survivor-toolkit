"""Rigid parent-local conversion, .x handedness and malformed capture rejection."""
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'tools/cart_clip_bake.py'
spec = importlib.util.spec_from_file_location('cart_clip_bake', SCRIPT)
baker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(baker)
IDENTITY = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


def fixture():
    children = '\n'.join(f'Frame Bone_{i} {{}}' for i in range(42))
    return ('xof 0303txt 0032\n'
            'template Frame { <3d82ab46-62da-11cf-ab39-0020af71e433> [...] }\n'
            'Material _03_-_Default { TextureFilename { "vanilla-body.png"; } }\n'
            f'Frame Dummy01 {{ Frame Bip01 {{ {children} }} }}\n'
            'Frame Translation_Data {}\n'
            'Frame Body { Mesh VanillaBody { 617; Material NestedOld { TextureFilename { "keep{mesh}.png"; } } } }\n'
            'AnimTicksPerSecond {4800;}\n'
            'AnimationSet Bob_Idle { Animation { { Bip01 } AnimationKey {0;0;} } }\n'
            'AnimationSet OtherOldClip {}\n')


def samples():
    names = baker.template_parts(fixture())[1]
    return [{'time': time, 'bones': {name: IDENTITY.copy() for name in names}}
            for time in (0, .5, 1)]


def read_keys(source, bone):
    body = re.search(r'Animation\s*{\s*{\s*' + bone + r'\s*}\s*AnimationKey\s*{(.*?)\n  }', source, re.S)[1]
    return [(int(tick), [float(value) for value in values.split(',')])
            for tick, values in re.findall(r'(\d+);16;([^;]+);;', body)]


class CartClipBakeTests(unittest.TestCase):
    def test_matrix_keys_undo_parent_model_in_native_x_basis(self):
        data = samples()
        # Model-space parent rotates +90 around Z and translates; child has a
        # separate rotation/translation so using model-space keys cannot pass.
        parent = [0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 2, 3, 4, 1]
        local = [1, 0, 0, 0, 0, 0, 1, 0, 0, -1, 0, 0, 5, 6, 7, 1]
        for sample in data:
            sample['bones']['Dummy01'] = parent
            sample['bones']['Bip01'] = baker.multiply(parent, local)
            for name in sample['bones']:
                if name.startswith('Bone_'):
                    sample['bones'][name] = sample['bones']['Bip01'].copy()
        result = baker.bake(fixture(), data, 'CartLift')
        self.assertEqual([tick for tick, _ in read_keys(result, 'Bip01')], [0, 500000, 1000000])
        for name, expected in (('Dummy01', parent), ('Bip01', local), ('Bone_0', IDENTITY)):
            matrix = read_keys(result, name)[1][1]
            for actual, value in zip(matrix, expected):
                self.assertAlmostEqual(actual, value, places=7)
        self.assertEqual(baker.template_parts(fixture())[1]['Translation_Data'], 'Dummy01')
        for _, native in read_keys(result, 'Translation_Data'):
            reconstructed = baker.multiply(parent, native)
            for actual, value in zip(reconstructed, IDENTITY):
                self.assertAlmostEqual(actual, value, places=7)
        for values in re.findall(r';16;([^;]+)', result):
            self.assertTrue(all('.' in value and 'e' not in value for value in values.split(',')))

    def test_preserves_skeleton_templates_replaces_vanilla_mesh_materials_and_animation(self):
        source = fixture() + '  \n'
        result = baker.bake(source, samples(), 'CartLift')
        skeleton = source[source.index('Frame Dummy01'):source.index('Frame Body')]
        self.assertIn(skeleton, result)
        self.assertIn(source.splitlines()[1], result)
        self.assertIn(baker.CARRIER, result)
        for vanilla in ('VanillaBody', '_03_-_Default', 'NestedOld', '617;',
                        'vanilla-body.png', 'keep{mesh}.png', 'TextureFilename'):
            self.assertNotIn(vanilla, result)
        self.assertEqual(result.count('Mesh AnimationCarrier'), 1)
        self.assertIn('3;0,1,2;;', result)
        self.assertIn('"Dummy01";', result)
        self.assertNotIn('Bob_Idle', result)
        self.assertNotIn('OtherOldClip', result)
        self.assertIn('AnimTicksPerSecond {\n 1000000;\n}', result)
        self.assertEqual(result.count('AnimationSet '), 1)
        self.assertEqual(result.count('AnimationKey {'), 45)
        self.assertEqual(result.count(';16;'), 135)
        self.assertTrue(all(line == line.rstrip() for line in result.splitlines()))

    def test_requires_exact_bones_and_valid_rigid_matrices(self):
        variants = []
        missing = samples()
        del missing[0]['bones']['Bone_0']
        variants.append(missing)
        extra = samples()
        extra[0]['bones']['alien'] = IDENTITY.copy()
        variants.append(extra)
        for bad in ([1], IDENTITY[:-1] + [float('nan')], IDENTITY[:-1] + [float('inf')],
                    IDENTITY[:-1] + [True]):
            data = samples()
            data[0]['bones']['Bone_0'] = bad
            variants.append(data)
        for element, value in ((3, 1), (0, 2), (0, -1), (1, .1), (12, 10**1000)):
            data = samples()
            data[0]['bones']['Bone_0'][element] = value
            variants.append(data)
        for data in variants:
            with self.subTest(data=data[0]['bones'].get('Bone_0')):
                with self.assertRaises(ValueError):
                    baker.bake(fixture(), data, 'CartLift')
        data = samples()
        data[0]['bones']['Bip01'][12] = 3e38
        data[0]['bones']['Bone_0'][12] = -3e38
        with self.assertRaises(ValueError):
            baker.bake(fixture(), data, 'CartLift')

    def test_requires_bounded_strictly_ordered_finite_times_starting_at_zero(self):
        for times in ((0,), (.1, .2), (0, 0), (0, -.1), (0, float('nan')),
                      (0, True), (0, 61), (0, .00000001), (0, .5, .1)):
            data = samples()
            data = [dict(data[0], time=time) for time in times]
            with self.subTest(times=times), self.assertRaises(ValueError):
                baker.bake(fixture(), data, 'CartLift')
        with self.assertRaises(ValueError):
            baker.bake(fixture(), samples() * (baker.MAX_SAMPLES // 3 + 1), 'CartLift')

    def test_rejects_bad_template_or_injected_clip_name(self):
        for source in (fixture().replace('xof 0303txt', 'xof 0303bin'), fixture() + '}',
                       fixture().replace('Frame Bone_0 {}', ''),
                       fixture().replace('Frame Bone_0 {}', 'Frame Bone_1 {}'),
                       fixture().replace('Frame Body', 'Frame Bone_0'),
                       fixture().replace('AnimTicksPerSecond {4800;}', '')):
            with self.assertRaises(ValueError):
                baker.bake(source, samples(), 'CartLift')
        for name in ('', 'Cart Lift', 'Cart}\nAnimationSet Bad{', 'a' * 81, 'Тест'):
            with self.assertRaises(ValueError):
                baker.bake(fixture(), samples(), name)

    def test_cli_bad_input_cannot_truncate_output_or_overwrite_template(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            template, input_path, output = (root / name for name in ('idle.x', 'poses.json', 'new.x'))
            template.write_text(fixture())
            input_path.write_text(json.dumps(samples()))
            command = [sys.executable, str(SCRIPT), '--template', str(template), '--input', str(input_path),
                       '--name', 'CartLift', '--output']
            result = subprocess.run(command + [str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            original_output = output.read_text()
            input_path.write_text('[]')
            result = subprocess.run(command + [str(output)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_text(), original_output)
            result = subprocess.run(command + [str(template)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(template.read_text(), fixture())


if __name__ == '__main__':
    unittest.main()
