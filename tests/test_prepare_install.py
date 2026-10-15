"""The prepared set is complete, isolated and replaced only after success."""

import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import package_mod, prepare_install


class PrepareInstall(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in prepare_install.MOD_IDS[:2]:
            shutil.copytree(ROOT / name, self.root / name)
        self.patch = self.root / "JavaPatches/build/PZToolkitJavaPatches"
        (self.patch / "common").mkdir(parents=True)
        self.jar = self.patch / "42/media/java/PZToolkitJavaPatches.jar"
        self.jar.parent.mkdir(parents=True)
        self.jar.write_bytes(b"built patch")
        (self.patch / "42/mod.info").write_text(
            "id=PZToolkitJavaPatches\nversion=0.1.2\n"
            "versionMin=42.21\nversionMax=42.21\n"
            "javaJarFile=media/java/PZToolkitJavaPatches.jar\n"
        )
        (self.root / prepare_install.INI_NAME).write_text(
            "Mods=ZombieBuddy;" + ";".join(prepare_install.MOD_IDS) + "\n"
            "WorkshopItems=3619862853;3508537032\n"
        )
        (self.root / "MOD_INSTALL.md").write_text(
            "[INI](SurvivorQoL-selected.ini) [features](README.md#controls) "
            "[loader](JavaPatches/README.md#server-loader)\n", encoding="utf-8")
        (self.root / "JavaPatches/README.md").write_text("# Java installation\n", encoding="utf-8")
        (self.root / "JavaPatches/start-host.ps1").write_text("# Windows launcher\n")
        command = self.root / "JavaPatches/start-host.command"
        command.write_text("#!/bin/bash\n# macOS launcher\n")
        command.chmod(0o755)
        self.output = self.root / "dist/SurvivorQoL"
        self.output.mkdir(parents=True)
        self.sentinel = self.output / "previous.txt"
        self.sentinel.write_text("previous prepared set")
        self.addCleanup(patch.stopall)
        patch.object(package_mod, "ROOT", self.root).start()
        self.build = patch.object(prepare_install.subprocess, "run").start()

    def test_complete_set_preserves_metadata_and_builds_once_with_forwarded_options(self):
        game, jdk = self.root / "game folder", self.root / "jdk folder"
        result = prepare_install.prepare(self.root, game, jdk, check=True)
        self.assertEqual(result, self.output)
        self.build.assert_called_once_with(
            [sys.executable, str(self.root / "JavaPatches/build.py"),
             "--game", str(game), "--jdk", str(jdk), "--check"], cwd=self.root, check=True
        )
        self.assertEqual({folder.name for folder in (result / "mods").iterdir()},
                         set(prepare_install.MOD_IDS))
        for name in prepare_install.MOD_IDS:
            source = self.patch if name == prepare_install.MOD_IDS[2] else self.root / name
            self.assertEqual((result / "mods" / name / "42/mod.info").read_bytes(),
                             (source / "42/mod.info").read_bytes())
        self.assertEqual((result / "mods/PZToolkitJavaPatches/42/media/java/PZToolkitJavaPatches.jar").read_bytes(),
                         b"built patch")
        self.assertEqual((result / "Server" / prepare_install.INI_NAME).read_bytes(),
                         (self.root / prepare_install.INI_NAME).read_bytes())
        self.assertTrue((result / "start-host.ps1").is_file())
        self.assertEqual((result / "start-host.command").read_bytes(),
                         (self.root / "JavaPatches/start-host.command").read_bytes())
        self.assertEqual((result / "start-host.command").stat().st_mode & 0o777, 0o755)
        self.assertEqual((result / "MOD_INSTALL.md").read_text(encoding="utf-8"),
                         "[INI](Server/SurvivorQoL-selected.ini) "
                         "[features](https://github.com/AlexRedby/pz-survivor-toolkit/blob/main/README.md#controls) "
                         "[loader](JavaPatches/README.md#server-loader)\n")
        self.assertEqual((result / "JavaPatches/README.md").read_bytes(),
                         (self.root / "JavaPatches/README.md").read_bytes())
        self.assertFalse(self.sentinel.exists())

    def test_default_build_arguments_and_no_build_or_third_party_artifact_spill(self):
        for name in ("ZombieBuddy.jar", "projectzomboid.jar", "NativeChecks.log", "Main.class", "archive.zip"):
            (self.root / "JavaPatches/build" / name).write_bytes(b"must stay outside bundle")
        prepare_install.prepare(self.root)
        self.build.assert_called_once_with(
            [sys.executable, str(self.root / "JavaPatches/build.py")], cwd=self.root, check=True)
        paths = [path for path in self.output.rglob("*") if path.is_file()]
        self.assertEqual([path.name for path in paths if path.suffix == ".jar"],
                         ["PZToolkitJavaPatches.jar"])
        self.assertFalse(any(path.suffix in (".class", ".log", ".zip") for path in paths))

    def test_build_failure_preserves_previous_set_even_with_existing_patch(self):
        self.build.side_effect = subprocess.CalledProcessError(1, ["build.py"])
        with self.assertRaises(subprocess.CalledProcessError):
            prepare_install.prepare(self.root)
        self.assertEqual(self.sentinel.read_text(), "previous prepared set")
        self.assertEqual(list((self.root / "dist").iterdir()), [self.output])

    def test_missing_or_escaping_jar_preserves_previous_set(self):
        self.jar.unlink()
        with self.assertRaisesRegex(ValueError, "javaJarFile"):
            prepare_install.prepare(self.root)
        self.assertEqual(self.sentinel.read_text(), "previous prepared set")
        self.jar.symlink_to(self.sentinel)
        with self.assertRaisesRegex(ValueError, "javaJarFile"):
            prepare_install.prepare(self.root)
        self.assertEqual(self.sentinel.read_text(), "previous prepared set")

    def test_ini_requires_every_local_mod_without_local_workshop_entries(self):
        for invalid in (
            "Mods=PZSurvivorToolkit;PZSurvivorWishlist\nWorkshopItems=123\n",
            "Mods=" + ";".join(prepare_install.MOD_IDS) + "\nWorkshopItems=PZToolkitJavaPatches\n",
        ):
            with self.subTest(ini=invalid):
                (self.root / prepare_install.INI_NAME).write_text(invalid)
                with self.assertRaises(ValueError):
                    prepare_install.prepare(self.root)
                self.assertEqual(self.sentinel.read_text(), "previous prepared set")
        self.build.assert_not_called()

    def test_invalid_source_mod_preserves_previous_set_before_build(self):
        (self.root / "PZSurvivorToolkit/42/mod.info").write_text("id=WrongMod\n")
        with self.assertRaisesRegex(ValueError, "mod.info must declare"):
            prepare_install.prepare(self.root)
        self.build.assert_not_called()
        self.assertTrue(self.sentinel.is_file())

    def test_rerun_removes_stale_prepared_files_and_preserves_other_dist_outputs(self):
        sibling = self.root / "dist/unrelated.zip"
        sibling.write_bytes(b"unrelated output")
        prepare_install.prepare(self.root)
        stale = self.output / "mods/PZSurvivorWishlist/obsolete.lua"
        stale.write_text("removed from sources")
        prepare_install.prepare(self.root)
        self.assertFalse(stale.exists())
        self.assertEqual(sibling.read_bytes(), b"unrelated output")
        self.assertEqual({path.name for path in (self.root / "dist").iterdir()},
                         {"SurvivorQoL", "unrelated.zip"})

    def test_copy_failure_preserves_previous_output(self):
        with patch.object(prepare_install.shutil, "copy2", side_effect=OSError("copy failed")):
            with self.assertRaisesRegex(OSError, "copy failed"):
                prepare_install.prepare(self.root)
        self.assertTrue(self.sentinel.is_file())
        self.assertEqual(list((self.root / "dist").iterdir()), [self.output])

    def test_failed_final_rename_restores_previous_output(self):
        rename = Path.rename

        def fail_promotion(source, target):
            if source.name == "prepared":
                raise OSError("rename failed")
            return rename(source, target)

        with patch.object(Path, "rename", fail_promotion):
            with self.assertRaisesRegex(OSError, "rename failed"):
                prepare_install.prepare(self.root)
        self.assertEqual(self.sentinel.read_text(), "previous prepared set")
        self.assertEqual(list((self.root / "dist").iterdir()), [self.output])

    def test_failed_restore_keeps_previous_output_at_reported_path(self):
        rename = Path.rename

        def fail_promotion_and_restore(source, target):
            if source.name in ("prepared", "previous"):
                raise OSError("rename failed")
            return rename(source, target)

        with patch.object(Path, "rename", fail_promotion_and_restore):
            with self.assertRaisesRegex(OSError, "Previous prepared set is preserved at") as failure:
                prepare_install.prepare(self.root)
        saved = next((self.root / "dist").glob(".SurvivorQoL-*/previous/previous.txt"))
        self.assertEqual(saved.read_text(), "previous prepared set")
        self.assertIn(str(saved.parent), str(failure.exception))

    def test_symlink_output_is_refused_without_mutating_target(self):
        outside = self.root / "outside"
        self.output.rename(outside)
        self.output.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "regular directory"):
            prepare_install.prepare(self.root)
        self.build.assert_not_called()
        self.assertEqual((outside / "previous.txt").read_text(), "previous prepared set")


if __name__ == "__main__":
    unittest.main()
