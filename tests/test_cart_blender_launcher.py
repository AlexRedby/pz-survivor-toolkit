"""Preparation from a clone with explicit, non-Steam external input paths."""
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import cart_blender as workflow


class PortablePreparationTests(unittest.TestCase):
    def test_explicit_cart_needs_no_steam_library_or_codex_files(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory).resolve();project=base/'fresh clone';game=base/'custom game';jdk=base/'jdk';blender=base/'Blender';cart=base/'cart.fbx'
            for p in (project/'assets/animations/wood_cart_pickup.json',game/'projectzomboid.jar',game/'media/anims_X/Bob/Bob_Idle.x',game/'media/models_X/Skinned/MaleBody.x',workflow.jdk_binary(jdk,'java'),workflow.jdk_binary(jdk,'javac'),blender,cart):
                p.parent.mkdir(parents=True,exist_ok=True);p.write_text('[]')
            args=SimpleNamespace(clip='wood_cart_pickup',game=game,jdk=jdk,blender=blender,duration=None,female=False,cart_fbx=cart,workshop=None,output=None)
            with patch.object(workflow,'ROOT',project),patch.object(workflow,'run') as run,redirect_stdout(io.StringIO()):
                output=workflow.prepare(args)
                scene=output/'scene.blend';scene.write_text('user edits')
                with self.assertRaises(FileExistsError):workflow.prepare(args)
            self.assertEqual(output,project/'build/blender/wood_cart_pickup')
            self.assertEqual(scene.read_text(),'user edits')
            config=json.loads((output/'workspace.json').read_text())
            self.assertEqual(config['cart']['path'],str(cart))
            self.assertEqual(config['source'],str(project/'assets/animations/wood_cart_pickup.json'))
            self.assertEqual(run.call_count,1)
            self.assertFalse((project/'.codex').exists())

    def test_every_advertised_preset_has_a_repository_source_and_matching_clip(self):
        presets=json.loads(workflow.PRESETS.read_text())
        for name,preset in presets.items():
            with self.subTest(clip=name):
                self.assertTrue((ROOT/'assets/animations'/f'{name}.json').is_file())
                runtime=ROOT/'PZSurvivorToolkit/42/media/anims_X/Bob'/(preset['clip_name']+'.x')
                self.assertIn('AnimationSet '+preset['clip_name']+' {',runtime.read_text())


if __name__=='__main__':unittest.main()
