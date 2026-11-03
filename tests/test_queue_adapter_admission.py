"""Adapter selection admission stays independent of files and native tool imports."""
from contextlib import ExitStack
from copy import deepcopy
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import (
    auxiliary, base_walking_profile, basement_hall, carts, vehicle_lights, vehicle_pose,
)


class AdapterAdmissionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        paths = {key: str(root / key) for key in ('ffmpeg', 'ffprobe', 'patch_jar', 'mesh_fbx')}
        basic = dict(kind='sp', mode='toolkit', clients=1, languages=['EN'], options=paths)

        def selection(suite, cases, mods, **changes):
            return dict(deepcopy(basic), suite=suite, cases=cases, mods=list(mods), **changes)

        self.selections = [
            (auxiliary, selection('video-recording', ['captures'],
                                  ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'])),
            (auxiliary, selection('animal-trailer', ['equipment-fixed'],
                                  ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'], kind='mp')),
            (base_walking_profile, selection('base-walking-profile', ['walk'], base_walking_profile.REQUIRED,
                kind='mp', resources={'exclusive': True}, options=dict(mp_host=True,
                    world_template=str(root / 'world'), pack_lock=str(root / 'pack.json'),
                    external_sandbox_path=str(root / 'SandboxVars.lua')))),
            (basement_hall, selection('basement-hall', ['fresh'], basement_hall.MODS)),
            (vehicle_lights, selection('vehicle-lights', ['road'],
                                       vehicle_lights.definitions()['vehicle-lights']['default_mods'])),
            (vehicle_pose, selection('vehicle-pose', ['transitions'],
                ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'],
                options=dict(paths, vehicle_pose_capture=True))),
        ]
        candidate_sources = {key: str(root / key) for key in ('PZSurvivorToolkit', 'PZToolkitJavaPatches')}
        self.cart_sp = selection(carts.SP, ['reverse'], carts.MODS,
            languages=['RU'], options=dict(paths, mod_sources=candidate_sources))
        self.cart_mp = selection(carts.MP, ['owner_observer_motion'], carts.MODS,
            kind='mp', clients=2, languages=['EN', 'RU'],
            options=dict(paths, mod_sources=candidate_sources, mp_host=True, cart_wall_exit='left'))
        shopping = deepcopy(self.cart_sp)
        shopping.update(cases=['repeat'])
        shopping['options'].update(cart_variant='shopping-cart',
            cart_mesh_fbx={'ShoppingCartModel': str(root / 'shopping.fbx')})
        self.selections.extend((carts, value) for value in (self.cart_sp, self.cart_mp, shopping))

    def source_free(self):
        stack = ExitStack()
        self.addCleanup(stack.close)
        for method in ('stat', 'lstat', 'resolve', 'is_file', 'is_dir', 'is_symlink', 'open'):
            stack.enter_context(patch.object(Path, method, side_effect=AssertionError('filesystem admission')))
        stack.enter_context(patch.object(os, 'access', side_effect=AssertionError('executable admission')))
        stack.enter_context(patch.object(carts.importlib, 'import_module',
                                        side_effect=AssertionError('native tool import during admission')))
        return stack

    def test_all_mixed_adapters_admit_structural_selections_without_inputs(self):
        with self.source_free():
            for adapter, selected in self.selections:
                with self.subTest(suite=selected['suite'], cases=selected['cases']):
                    before = deepcopy(selected)
                    adapter.validate_selection(selected)
                    self.assertEqual(before, selected)

    def test_full_validation_still_refuses_missing_inputs(self):
        for adapter, selected in self.selections:
            with self.subTest(suite=selected['suite'], cases=selected['cases']):
                with self.assertRaises((OSError, ValueError)):
                    adapter.validate(selected)

    def test_structural_admission_rejects_relative_required_paths(self):
        with self.source_free():
            for adapter, selected in self.selections:
                invalid = deepcopy(selected)
                key = ('external_sandbox_path' if adapter is base_walking_profile else
                       'patch_jar' if selected['suite'] == 'animal-trailer' else 'ffmpeg')
                invalid['options'][key] = 'relative-input'
                with self.subTest(suite=selected['suite'], cases=selected['cases']):
                    with self.assertRaisesRegex(ValueError, 'absolute'):
                        adapter.validate_selection(invalid)

    def test_cart_full_validation_retains_numpy_requirement_for_both_analyzers(self):
        for selected in (self.cart_sp, self.cart_mp):
            with self.subTest(suite=selected['suite']), \
                    patch.object(Path, 'is_dir', return_value=True), \
                    patch.object(carts, '_path', return_value=Path('/declared-input')), \
                    patch.object(carts.importlib, 'import_module', side_effect=ImportError) as imported:
                carts.validate_selection(selected)
                imported.assert_not_called()
                with self.assertRaisesRegex(ValueError, 'working NumPy'):
                    carts.validate(selected)
                imported.assert_called_once_with('numpy')

    def test_full_validation_keeps_structural_and_exclusive_guards(self):
        with self.source_free():
            for adapter, selected in self.selections:
                invalid = deepcopy(selected)
                invalid['kind'] = 'unsupported'
                with self.subTest(suite=selected['suite'], cases=selected['cases']):
                    with self.assertRaises(ValueError):
                        adapter.validate(invalid)
            selected = deepcopy(next(value for adapter, value in self.selections
                                     if adapter is base_walking_profile))
            selected['resources']['exclusive'] = False
            with self.assertRaisesRegex(ValueError, 'resources.exclusive=true'):
                base_walking_profile.validate_selection(selected)

    def test_kotlin_home_shape_is_rejected_before_tool_resolution(self):
        with self.source_free(), patch.object(carts, 'resolve_kotlin_home',
                                             side_effect=AssertionError('Kotlin resolution')):
            for value in ('', False, 42, [], {}):
                selected = deepcopy(self.cart_sp)
                selected['options']['kotlin_home'] = value
                with self.subTest(value=value):
                    for validate in (carts.validate_selection, carts.preflight):
                        with self.assertRaisesRegex(ValueError, 'nonempty distribution path'):
                            validate(selected)
            for value in (None, '/declared-kotlin-distribution', 'relative-distribution'):
                selected = deepcopy(self.cart_sp)
                selected['options']['kotlin_home'] = value
                carts.validate_selection(selected)


if __name__ == '__main__':
    unittest.main()
