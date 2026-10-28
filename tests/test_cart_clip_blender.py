"""Native/Blender basis, parent-local pose composition and authoring boundaries."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
spec=importlib.util.spec_from_file_location('cart_clip_blender',ROOT/'tools/cart_clip_blender.py')
bridge=importlib.util.module_from_spec(spec);spec.loader.exec_module(bridge)
baker=bridge.baker


def fixture():
    children='\n'.join(f'Frame Bone_{index} {{}}' for index in range(42))
    return ('xof 0303txt 0032\n'
            f'Frame Dummy01 {{ Frame Bip01 {{ {children} }} }}\n'
            'Frame Translation_Data {}\nFrame Body { Mesh BodyMesh {} }\n'
            'AnimTicksPerSecond {4800;}\nAnimationSet Bob_Idle {}\n')


def samples():
    _,parents=baker.template_parts(fixture())
    return [dict(time=time,bones={name:bridge.IDENTITY.copy() for name in parents}) for time in (0,.5,1)]


class CartClipBlenderTests(unittest.TestCase):
    def assertMatrix(self,actual,expected):
        for actual,value in zip(actual,expected):
            self.assertAlmostEqual(actual,value,places=7)

    def test_native_model_and_bone_axes_are_independent_and_roundtrip(self):
        native=bridge.IDENTITY.copy();native[12:15]=[2,3,4]
        converted=bridge.native_to_blender(native)
        self.assertEqual(converted[12:15],[2,-4,3])
        # Blender bone +Y follows the native limb's +X; native +Y still becomes world +Z.
        self.assertEqual(converted[4:7],[1,0,0])
        self.assertEqual(converted[0:3],[0,0,-1])
        self.assertMatrix(bridge.blender_to_native(converted),native)
        rotated=[0,1,0,0, -1,0,0,0, 0,0,1,0, 2,3,4,1]
        self.assertMatrix(bridge.blender_to_native(bridge.native_to_blender(rotated)),rotated)
        self.assertMatrix(bridge.column_matrix(bridge.matrix_rows(rotated)),rotated)

    def test_edit_bone_rest_and_parent_pose_reconstruct_native_model_pose(self):
        rest_parent=[0,1,0,0, -1,0,0,0, 0,0,1,0, 2,3,4,1]
        rest_child=baker.multiply(rest_parent,[1,0,0,0, 0,0,1,0, 0,-1,0,0, 0,2,0,1])
        pose_parent=[1,0,0,0, 0,0,1,0, 0,-1,0,0, 4,1,2,1]
        pose_child=baker.multiply(pose_parent,[0,1,0,0, -1,0,0,0, 0,0,1,0, 1,3,2,1])
        rp,rc,pp,pc=map(bridge.native_to_blender,(rest_parent,rest_child,pose_parent,pose_child))
        root_basis=bridge.pose_basis(rp,None,None,pp)
        self.assertMatrix(bridge.blender_to_native(baker.multiply(rp,root_basis)),pose_parent)
        child_basis=bridge.pose_basis(rc,rp,pp,pc)
        reconstructed=baker.multiply(pp,baker.multiply(baker.inverse_rigid(rp),baker.multiply(rc,child_basis)))
        self.assertMatrix(bridge.blender_to_native(reconstructed),pose_child)
        self.assertMatrix(bridge.pose_basis(rc,rp,rp,rc),bridge.IDENTITY)

    def test_preserves_original_timestamps_and_native_translation_parent(self):
        data=samples();_,parents=baker.template_parts(fixture())
        metadata=bridge.metadata_for(parents,data)
        bridge.validate_metadata(json.loads(json.dumps(metadata)))
        self.assertEqual(metadata['times'],[0,.5,1])
        self.assertEqual(metadata['frames'],[1,31,61])
        self.assertEqual(metadata['parents']['Translation_Data'],'Dummy01')
        # Arbitrary native timestamps are retained separately from actual float32 keys.
        times=[0,.1234567,.2345678]
        frames=bridge.sample_frames(times)
        self.assertNotEqual(frames[1],1+60*times[1])
        self.assertTrue(all(a<b for a,b in zip(frames,frames[1:])))
        with self.assertRaises(ValueError):
            bridge.sample_frames([0,59.999999,60])

    def test_rejects_scaled_missing_or_malformed_native_samples_and_metadata(self):
        _,parents=baker.template_parts(fixture())
        for element,value in ((0,2),(0,-1),(1,.1),(15,float('nan'))):
            data=samples();data[1]['bones']['Bip01'][element]=value
            with self.subTest(element=element,value=value),self.assertRaises(ValueError):
                bridge.metadata_for(parents,data)
        data=samples();del data[1]['bones']['Bip01']
        with self.assertRaises(ValueError):bridge.metadata_for(parents,data)
        for times in ((0,),(.1,.2),(0,0),(0,float('nan')),(0,61),(0,True)):
            data=[dict(samples()[0],time=time) for time in times]
            with self.subTest(times=times),self.assertRaises(ValueError):bridge.metadata_for(parents,data)
        metadata=bridge.metadata_for(parents,samples());metadata['frames'][1]+=1
        with self.assertRaises(ValueError):bridge.validate_metadata(metadata)
        malformed=parents.copy();malformed['Bip01']='Bone_0'
        with self.assertRaises(ValueError):bridge.parent_order(malformed)

    def test_export_retains_new_and_moved_keys_without_reinserting_removed_times(self):
        _,parents=baker.template_parts(fixture())
        metadata=bridge.metadata_for(parents,samples())
        exported=bridge.export_metadata(metadata,[1,16,41,61])
        self.assertEqual(exported['times'],[0,.25,2/3,1])
        self.assertNotIn(.5,exported['times'])
        self.assertEqual(metadata['times'],[0,.5,1])
        awkward=[dict(samples()[0],time=t) for t in (0,.1234567,1)]
        metadata=bridge.metadata_for(parents,awkward)
        self.assertEqual(bridge.export_metadata(metadata,metadata['frames'])['times'],[0,.1234567,1])
        for frames in ([0,61],[2,61],[1],[1,3602]):
            with self.subTest(frames=frames),self.assertRaises(ValueError):
                bridge.export_metadata(metadata,frames)

    def test_real_repository_pose_samples_pass_the_same_rigid_contract(self):
        for path in (ROOT/'assets/animations').glob('*.json'):
            data=json.loads(path.read_text())
            # The source template supplies hierarchy in Blender; its bone names match these delivered clips.
            names=list(data[0]['bones']);parents={name:None if name=='Dummy01' else 'Dummy01' for name in names}
            with self.subTest(path=path.name):
                bridge.validate_samples(data,parents)
                self.assertEqual(len(bridge.sample_frames([sample['time'] for sample in data])),len(data))

    def test_cli_rejects_source_overwrite_before_loading_blender(self):
        script=ROOT/'tools/cart_clip_blender.py'
        with tempfile.TemporaryDirectory() as directory:
            source=Path(directory)/'source.json';source.write_text('unchanged')
            result=subprocess.run([sys.executable,str(script),'export','--input',str(source),
                                   '--output',str(source)],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('output must differ',result.stderr)
            self.assertEqual(source.read_text(),'unchanged')

    def test_script_locates_its_baker_when_runner_omits_the_script_search_path(self):
        result=subprocess.run([sys.executable,'-I',str(ROOT/'tools/cart_clip_blender.py'),'--help'],
                              capture_output=True,text=True,cwd=tempfile.gettempdir())
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('import',result.stdout)


if __name__=='__main__':
    unittest.main()
