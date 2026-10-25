from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1] / 'tools'
sys.path.insert(0, str(TOOLS))
import cart_blender_preview as preview


IDENTITY = '1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1'


def fixture(weights=None, vertices='0;0;0;,1;0;0;,0;1;0;;', faces='3;0,1,2;;'):
    if weights is None:
        weights = f'SkinWeights {{ "Bone"; 3; 0,1,2; 1,1,1; {IDENTITY};; }}'
    return f'xof 0303txt 0032\nMesh Body {{ 3; {vertices} 1; {faces} {weights} }}'


class NativeBodyParserTest(unittest.TestCase):
    def test_multimesh_clothing_requires_explicit_exact_mesh(self):
        text=fixture()+fixture(vertices='2;0;0;,3;0;0;,2;1;0;;').split('\n',1)[1].replace('Mesh Body','Mesh Shorts')
        with self.assertRaises(ValueError):preview.parse_body(text)
        self.assertEqual(preview.parse_body(text,mesh_name='Body').vertices[0],(0,0,0))
        self.assertEqual(preview.parse_body(text,mesh_name='Shorts').vertices[0],(2,0,0))
        with self.assertRaises(ValueError):preview.parse_body(text,mesh_name='Missing')
    def test_reads_raw_model_points_and_column_major_offsets(self):
        offset = ','.join(IDENTITY.split(',')[:12] + ['2', '3', '4', '1'])
        body = preview.parse_body(fixture(f'SkinWeights {{ "Bone"; 3; 0,1,2; 1,1,1; {offset};; }}'), {'Bone'})
        self.assertEqual(body.faces, ((0, 1, 2),))
        self.assertEqual(body.vertices[1], (1, 0, 0))
        self.assertEqual(body.skin['Bone'].offset[12:15], (2, 3, 4))
        points = preview.skin_vertices(body, {'Bone': preview.bridge.IDENTITY})
        self.assertEqual(points[1], [3, -4, 3])

    def test_mixed_weights_are_preserved_without_normalizing(self):
        a = f'SkinWeights {{ "A"; 3; 0,1,2; .25,.25,.25; {IDENTITY};; }}'
        b = f'SkinWeights {{ "B"; 3; 0,1,2; .75,.75,.75; {IDENTITY};; }}'
        body = preview.parse_body(fixture(a+b))
        self.assertEqual(body.skin['A'].weights, (.25, .25, .25))

    def test_native_zero_influence_and_zero_weight_entries_are_valid(self):
        empty = f'SkinWeights {{ "Unused"; 0; ; ; {IDENTITY};; }}'
        zero = f'SkinWeights {{ "Zero"; 1; 0; 0; {IDENTITY};; }}'
        native = f'SkinWeights {{ "Bone"; 3; 0,1,2; 1,1,1; {IDENTITY};; }}'
        body = preview.parse_body(fixture(empty+zero+native))
        self.assertEqual(body.skin['Unused'].indices, ())
        self.assertEqual(body.skin['Zero'].weights, (0,))

    def test_missing_or_incomplete_weights_rejected(self):
        for weights in ('', f'SkinWeights {{ "Bone"; 2; 0,1; 1,1; {IDENTITY};; }}',
                        f'SkinWeights {{ "Bone"; 3; 0,1,2; .9,1,1; {IDENTITY};; }}'):
            with self.subTest(weights=weights), self.assertRaises(ValueError):
                preview.parse_body(fixture(weights))

    def test_invalid_faces_rejected(self):
        for faces in ('3;0,1,3;;', '3;0,0,1;;', '3;-1,1,2;;', '4;0,1,2,0;;', '3;0,1.5,2;;'):
            with self.subTest(faces=faces), self.assertRaises(ValueError):
                preview.parse_body(fixture(faces=faces))

    def test_invalid_skin_indices_weights_and_duplicates_rejected(self):
        for indices, amounts in (('0,1,3', '1,1,1'), ('0,0,2', '1,1,1'),
                                 ('0,1,2', '-1,1,1'), ('0,1,2', 'nan,1,1'),
                                 ('0,1,2', '1.1,1,1')):
            with self.subTest(indices=indices, amounts=amounts), self.assertRaises(ValueError):
                preview.parse_body(fixture(f'SkinWeights {{ "Bone"; 3; {indices}; {amounts}; {IDENTITY};; }}'))
        skin = f'SkinWeights {{ "Bone"; 3; 0,1,2; .5,.5,.5; {IDENTITY};; }}'
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            preview.parse_body(fixture(skin+skin))
        with self.assertRaisesRegex(ValueError, 'unknown'):
            preview.parse_body(fixture(), {'DifferentBone'})

    def test_invalid_offsets_rejected(self):
        offsets = (IDENTITY.replace('1,0,0,0', '2,0,0,0', 1),
                   IDENTITY.replace('1,0,0,0', '-1,0,0,0', 1),
                   IDENTITY.replace('1,0,0,0', '1,0,0,1', 1),
                   '1,0,0', IDENTITY + ',1')
        for offset in offsets:
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                preview.parse_body(fixture(f'SkinWeights {{ "Bone"; 3; 0,1,2; 1,1,1; {offset};; }}'))

    def test_truncated_binary_and_multiple_meshes_rejected(self):
        for text in (fixture()[:-1], fixture().replace('txt', 'bin'), fixture() + 'Mesh Other { }',
                     fixture().replace('SkinWeights', '1; SkinWeights', 1),
                     fixture().replace('Mesh Body { 3;', 'Mesh Body { 100001;')):
            with self.subTest(text=text), self.assertRaises(ValueError):
                preview.parse_body(text)

    def test_template_and_comment_blocks_not_parsed_as_meshes(self):
        text = fixture().replace('Mesh Body', 'template Mesh { DWORD x; }\n// Mesh Fake {\n/* SkinWeights { } */\nMesh Body')
        self.assertEqual(len(preview.parse_body(text).vertices), 3)


if __name__ == '__main__':
    unittest.main()
