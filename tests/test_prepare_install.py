"""The prepared set is complete, isolated and replaced only after success."""

import os
import shutil
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import package_mod, prepare_install


class PrepareInstall(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        for name in prepare_install.MOD_IDS[:1]:
            shutil.copytree(ROOT / name, self.root / name)
        self.patch = self.root / "JavaPatches/build/PZToolkitJavaPatches"
        (self.patch / "common").mkdir(parents=True)
        self.jar = self.patch / "42/media/java/PZToolkitJavaPatches.jar"
        self.jar.parent.mkdir(parents=True)
        self.jar.write_bytes(b"built patch")
        self.fontjar = self.patch / "42/media/bootstrap/PZToolkitFonts.jar"
        self.fontjar.parent.mkdir(parents=True)
        self.fontjar.write_bytes(b"built early font bootstrap")
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
            "[loader](JavaPatches/README.md#server-loader) "
            "[controls](docs/FEATURES.md#controls) [changes](CHANGELOG.md)\n", encoding="utf-8")
        (self.root / "JavaPatches/README.md").write_text(
            "[install](../MOD_INSTALL.md#prepare-once) "
            "[regressions](../docs/development/JAVA.md#java-development) "
            "[fixture](../tests/native_queue/contributions/video-recording/README.md) "
            "[version](build.py) [changes](../CHANGELOG.md#toolkit-java-patches)\n",
            encoding="utf-8")
        (self.root / "JavaPatches/start-host.ps1").write_text("# Windows launcher\n")
        command = self.root / "JavaPatches/start-host.command"
        command.write_text("#!/bin/bash\n# macOS launcher\n")
        command.chmod(0o755)
        self.output = self.root / "dist/SurvivorQoL"
        self.output.mkdir(parents=True)
        self.sentinel = self.output / "previous.txt"
        self.sentinel.write_text("previous prepared set")
        self.addCleanup(patch.stopall)
        self.build = patch.object(prepare_install.subprocess, "run").start()

    def test_utf8_bom_metadata_is_accepted_and_preserved_in_prepared_files(self):
        files = [self.root / prepare_install.INI_NAME, self.root / 'PZSurvivorToolkit/42/mod.info',
                 self.patch / '42/mod.info']
        for path in files:
            path.write_text(path.read_text(), encoding='utf-8-sig')
        result = prepare_install.prepare(self.root)
        self.build.assert_called_once()
        for source, target in zip(files, [result / 'Server' / prepare_install.INI_NAME,
                                         result / 'mods/PZSurvivorToolkit/42/mod.info',
                                         result / 'mods/PZToolkitJavaPatches/42/mod.info']):
            self.assertEqual(source.read_bytes(), target.read_bytes())

    def test_missing_files_in_an_external_copy_produce_validation_errors(self):
        mod = self.root / 'PZSurvivorToolkit'
        (mod / '42/media/lua/shared/PZSurvivorToolkit.lua').unlink()
        (mod / '42/mod.info').unlink()
        errors = package_mod.validate(mod)
        self.assertEqual(2, len(errors))
        self.assertTrue(all('required file is missing' in error for error in errors), errors)
        with self.assertRaisesRegex(ValueError, 'PZSurvivorToolkit/42/mod.info'):
            prepare_install.prepare(self.root)
        self.build.assert_not_called()
        self.assertEqual(self.sentinel.read_text(), 'previous prepared set')

    def test_crlf_owned_lua_is_rejected_without_changing_source_or_publication(self):
        mod = self.root / 'PZSurvivorToolkit'
        source = mod / '42/media/lua/client/PZSurvivorToolkit/ActionQueueCarts.lua'
        crlf = source.read_bytes().replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
        source.write_bytes(crlf)
        errors = package_mod.validate(mod)
        self.assertEqual(1, len(errors))
        self.assertIn('owned Lua source must use LF line endings', errors[0])
        with self.assertRaisesRegex(ValueError, 'owned Lua source must use LF line endings'):
            prepare_install.prepare(self.root)
        archive = self.root / 'dist/toolkit.zip'
        with self.assertRaisesRegex(ValueError, 'owned Lua source must use LF line endings'):
            package_mod.package(archive, mod)
        self.assertEqual(source.read_bytes(), crlf)
        self.assertEqual(self.sentinel.read_text(), 'previous prepared set')
        self.assertFalse(archive.exists())
        self.build.assert_not_called()

    def test_kotlin_home_is_forwarded_as_an_absolute_path(self):
        kotlin_home = Path('compiler folder/kotlinc')
        prepare_install.prepare(self.root, kotlin_home=kotlin_home)
        self.build.assert_called_once_with(
            [sys.executable, str(self.root / 'JavaPatches/build.py'),
             '--kotlin-home', str(kotlin_home.resolve())], cwd=self.root, check=True)

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
            source = self.patch if name == prepare_install.MOD_IDS[1] else self.root / name
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
                         "[loader](JavaPatches/README.md#server-loader) "
                         "[controls](https://github.com/AlexRedby/pz-survivor-toolkit/blob/main/docs/FEATURES.md#controls) "
                         "[changes](https://github.com/AlexRedby/pz-survivor-toolkit/blob/main/CHANGELOG.md)\n")
        self.assertEqual((result / "JavaPatches/README.md").read_text(encoding="utf-8"),
                         "[install](../MOD_INSTALL.md#prepare-once) "
                         "[regressions](https://github.com/AlexRedby/pz-survivor-toolkit/blob/main/docs/development/JAVA.md#java-development) "
                         "[fixture](https://github.com/AlexRedby/pz-survivor-toolkit/blob/main/tests/native_queue/contributions/video-recording/README.md) "
                         "[version](https://github.com/AlexRedby/pz-survivor-toolkit/blob/main/JavaPatches/build.py) "
                         "[changes](https://github.com/AlexRedby/pz-survivor-toolkit/blob/main/CHANGELOG.md#toolkit-java-patches)\n")
        self.assertFalse(self.sentinel.exists())

    def test_default_build_arguments_and_no_build_or_third_party_artifact_spill(self):
        for name in ("ZombieBuddy.jar", "projectzomboid.jar", "NativeChecks.log", "Main.class", "archive.zip"):
            (self.root / "JavaPatches/build" / name).write_bytes(b"must stay outside bundle")
        prepare_install.prepare(self.root)
        self.build.assert_called_once_with(
            [sys.executable, str(self.root / "JavaPatches/build.py")], cwd=self.root, check=True)
        paths = [path for path in self.output.rglob("*") if path.is_file()]
        self.assertEqual(sorted(path.name for path in paths if path.suffix == ".jar"),
                         ["PZToolkitFonts.jar", "PZToolkitJavaPatches.jar"])
        self.assertFalse(any(path.suffix in (".class", ".log", ".zip") for path in paths))

    def test_prepared_and_archived_animation_directories_match_without_changing_sources(self):
        mod = self.root / 'PZSurvivorToolkit'
        directories = [Path(layer) / 'media' / name for layer in ('common', '42')
                       for name in ('AnimSets', 'actiongroups')]
        before = {str(path.relative_to(mod)): path.read_bytes() for path in mod.rglob('*') if path.is_file()}
        prepare_install.prepare(self.root)
        for relative in directories:
            self.assertTrue((self.output / 'mods/PZSurvivorToolkit' / relative).is_dir(), str(relative))
        archive = self.root / 'toolkit.zip'
        package_mod.package(archive, mod)
        extracted = self.root / 'extracted'
        with zipfile.ZipFile(archive) as bundle:
            for relative in directories:
                self.assertTrue(bundle.getinfo('PZSurvivorToolkit/' + relative.as_posix() + '/').is_dir())
            self.assertFalse(any(Path(name).name == '.gitkeep' for name in bundle.namelist()))
            bundle.extractall(extracted)
        for relative in directories:
            self.assertTrue((extracted / 'PZSurvivorToolkit' / relative).is_dir(), str(relative))
        self.assertFalse(list(extracted.rglob('.gitkeep')))
        self.assertEqual(before, {str(path.relative_to(mod)): path.read_bytes()
                                  for path in mod.rglob('*') if path.is_file()})

    def test_missing_required_empty_animation_directory_rejects_before_build(self):
        mod = self.root / 'PZSurvivorToolkit'
        missing = mod / 'common/media/actiongroups'
        shutil.rmtree(missing)
        errors = package_mod.validate(mod)
        self.assertTrue(any('common/media/actiongroups' in error for error in errors), errors)
        with self.assertRaisesRegex(ValueError, 'common/media/actiongroups'):
            prepare_install.prepare(self.root)
        self.build.assert_not_called()
        self.assertEqual(self.sentinel.read_text(), 'previous prepared set')
        self.assertEqual(list((self.root / 'dist').iterdir()), [self.output])

    def test_invalid_selected_mod_ids_reject_before_build_without_changing_output(self):
        mods = 'ZombieBuddy;' + ';'.join(prepare_install.MOD_IDS)
        for invalid in (mods + ';ZombieBuddy', mods + ';', ';' + mods,
                        mods.replace(';', ';;', 1), mods + ';../OtherMod', mods + ';.',
                        mods.replace('PZSurvivorToolkit', ' PZSurvivorToolkit'),
                        mods.replace('PZSurvivorToolkit', 'PZSurvivorToolkit ')):
            with self.subTest(mods=invalid):
                (self.root / prepare_install.INI_NAME).write_text('Mods=' + invalid + '\n')
                with self.assertRaises(ValueError):
                    prepare_install.prepare(self.root)
                self.build.assert_not_called()
                self.assertEqual(self.sentinel.read_text(), 'previous prepared set')
                self.assertEqual(list(self.output.rglob('*')), [self.sentinel])
                self.assertEqual(list((self.root / 'dist').iterdir()), [self.output])

    def test_relative_inputs_are_resolved_from_caller_before_build_changes_cwd(self):
        caller = self.root / 'build caller'
        caller.mkdir()
        previous = Path.cwd()
        try:
            os.chdir(caller)
            result = prepare_install.prepare(Path('..'), Path('game folder'), Path('jdk folder'))
        finally:
            os.chdir(previous)
        self.assertEqual(self.output.resolve(), result)
        self.build.assert_called_once_with(
            [sys.executable, str(self.root.resolve() / 'JavaPatches/build.py'),
             '--game', str(caller.resolve() / 'game folder'), '--jdk', str(caller.resolve() / 'jdk folder')],
            cwd=self.root.resolve(), check=True)

    def test_shipped_guides_only_link_to_shipped_files_or_external_sources(self):
        for name in ("MOD_INSTALL.md", "JavaPatches/README.md"):
            shutil.copyfile(ROOT / name, self.root / name)
        prepare_install.prepare(self.root)
        for name in ("MOD_INSTALL.md", "JavaPatches/README.md"):
            guide = self.output / name
            for target in re.findall(r'\]\(([^)]+)\)', guide.read_text(encoding="utf-8")):
                if target.startswith(("https://", "#")):
                    continue
                with self.subTest(guide=name, target=target):
                    self.assertTrue((guide.parent / target.split("#", 1)[0]).is_file(), target)

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
        with self.assertRaisesRegex(ValueError, "symbolic link in mod source"):
            prepare_install.prepare(self.root)
        self.assertEqual(self.sentinel.read_text(), "previous prepared set")

    def test_source_links_are_rejected_before_replacing_prepared_set(self):
        outside = self.root / "external"
        outside.mkdir()
        sentinel = outside / "private.txt"
        sentinel.write_text("synthetic external sentinel")
        for source in (self.root / "PZSurvivorToolkit", self.patch):
            for target in (sentinel, outside, outside / "missing"):
                with self.subTest(source=source, target=target):
                    link = source / "42/external"
                    link.symlink_to(target, target_is_directory=target == outside)
                    self.build.reset_mock()
                    try:
                        with self.assertRaisesRegex(ValueError, "symbolic link in mod source"):
                            prepare_install.prepare(self.root)
                        if source != self.patch:
                            self.build.assert_not_called()
                        self.assertEqual(self.sentinel.read_text(), "previous prepared set")
                        self.assertEqual(list((self.root / "dist").iterdir()), [self.output])
                        self.assertEqual(sentinel.read_text(), "synthetic external sentinel")
                    finally:
                        link.unlink()

    def test_packaging_rejects_source_links_without_overwriting_archive(self):
        mod = self.root / "PZSurvivorToolkit"
        output = self.root / "previous.zip"
        output.write_bytes(b"previous archive")
        for target in (self.sentinel, self.output, self.root / "missing"):
            with self.subTest(target=target):
                link = mod / "42/external"
                link.symlink_to(target, target_is_directory=target == self.output)
                try:
                    self.assertTrue(package_mod.validate(mod))
                    with self.assertRaisesRegex(ValueError, "symbolic link in mod source"):
                        package_mod.package(output, mod)
                    self.assertEqual(output.read_bytes(), b"previous archive")
                finally:
                    link.unlink()
        package_mod.package(output, mod)
        with zipfile.ZipFile(output) as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(archive.read("PZSurvivorToolkit/42/mod.info"), (mod / "42/mod.info").read_bytes())

    def test_symlink_mod_roots_are_rejected(self):
        for source in (self.root / "PZSurvivorToolkit", self.patch):
            with self.subTest(source=source):
                original = source.with_name(source.name + "-original")
                source.rename(original)
                source.symlink_to(original, target_is_directory=True)
                try:
                    with self.assertRaisesRegex(ValueError, "symbolic link in mod source"):
                        prepare_install.prepare(self.root)
                    self.assertEqual(self.sentinel.read_text(), "previous prepared set")
                finally:
                    source.unlink()
                    original.rename(source)

    def test_archive_failure_preserves_previous_output_and_removes_staging(self):
        mod = self.root / "PZSurvivorToolkit"
        output = self.root / "archives/previous.zip"
        output.parent.mkdir()
        output.write_bytes(b"previous archive")
        close = zipfile.ZipFile.close

        def fail_close(archive):
            active = archive.fp is not None
            close(archive)
            if active:
                raise OSError("close failed")

        for existing in (True, False):
            if not existing:
                output.unlink()
            for failure in (patch.object(zipfile.ZipFile, "write", side_effect=OSError("write failed")),
                            patch.object(zipfile.ZipFile, "close", fail_close),
                            patch.object(Path, "replace", side_effect=OSError("replace failed"))):
                with self.subTest(existing=existing, failure=failure), failure:
                    with self.assertRaises(OSError):
                        package_mod.package(output, mod)
                    self.assertEqual(output.exists(), existing)
                    if existing:
                        self.assertEqual(output.read_bytes(), b"previous archive")
                    self.assertEqual(list(output.parent.iterdir()), [output] if existing else [])
        package_mod.package(output, mod)
        with zipfile.ZipFile(output) as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(archive.read("PZSurvivorToolkit/42/mod.info"), (mod / "42/mod.info").read_bytes())
        self.assertEqual(list(output.parent.iterdir()), [output])

    def test_archive_refuses_output_links_and_source_paths_before_writing(self):
        mod = self.root / "PZSurvivorToolkit"
        output = self.root / "archive.zip"
        sentinel = self.root / "outside.zip"
        sentinel.write_bytes(b"outside sentinel")
        for target in (sentinel, self.root / "missing.zip"):
            with self.subTest(target=target):
                output.symlink_to(target)
                try:
                    with self.assertRaisesRegex(ValueError, "regular file"):
                        package_mod.package(output, mod)
                    self.assertTrue(output.is_symlink())
                    self.assertEqual(sentinel.read_bytes(), b"outside sentinel")
                    self.assertFalse((self.root / "missing.zip").exists())
                finally:
                    output.unlink()
        info = mod / "42/mod.info"
        before = info.read_bytes()
        for destination in (info, mod / "archive.zip", mod / "new/sub/archive.zip"):
            with self.subTest(destination=destination):
                with self.assertRaisesRegex(ValueError, "outside the mod source"):
                    package_mod.package(destination, mod)
                self.assertEqual(info.read_bytes(), before)
                self.assertFalse((mod / "new").exists())
                self.assertFalse((mod / "archive.zip").exists())

    def test_archive_cli_reports_output_failure_without_success_message(self):
        from contextlib import redirect_stdout
        from io import StringIO
        output = StringIO()
        with patch.object(sys, "argv", ["package_mod.py", "--output", str(self.root / "archive.zip")]), \
                patch.object(package_mod, "package", side_effect=OSError("archive write failed")), redirect_stdout(output):
            self.assertEqual(package_mod.main(), 1)
        self.assertIn("ERROR: archive write failed", output.getvalue())
        self.assertNotIn("OK: wrote", output.getvalue())

    def test_ini_requires_every_local_mod_without_local_workshop_entries(self):
        for invalid in (
            "Mods=PZSurvivorToolkit\nWorkshopItems=123\n",
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

    def test_adapter_order_is_checked_before_build_and_preserves_previous_set(self):
        for before, after in (('CleanUI', 'PZSurvivorToolkit'),
                              ('PZSurvivorToolkit', 'EURY_CONTAINERS'),
                              ('PZSurvivorToolkit', 'MPFastForward'),
                              ('ZombieBuddy', 'PZToolkitJavaPatches'),
                              ('RealisticDash', 'Navigator')):
            with self.subTest(before=before, after=after):
                ordered = list(dict.fromkeys([after, before, *prepare_install.MOD_IDS]))
                (self.root / prepare_install.INI_NAME).write_text('Mods=' + ';'.join(ordered) + '\n')
                with self.assertRaisesRegex(ValueError, f'load order requires {before} before {after}'):
                    prepare_install.prepare(self.root)
                self.assertEqual(self.sentinel.read_text(), 'previous prepared set')
        self.build.assert_not_called()

    def test_absent_optional_mods_and_unrelated_order_remain_allowed(self):
        for mods in (list(reversed(prepare_install.MOD_IDS)),
                     ['PZSurvivorToolkit', 'MoodleFramework', 'PZToolkitJavaPatches']):
            with self.subTest(mods=mods):
                (self.root / prepare_install.INI_NAME).write_text('Mods=' + ';'.join(mods) + '\n')
                prepare_install.prepare(self.root)
        self.assertEqual(2, self.build.call_count)

    def test_full_workshop_selection_publishes_only_owned_mods_without_external_inputs(self):
        shutil.copyfile(ROOT / prepare_install.INI_NAME, self.root / prepare_install.INI_NAME)
        for name in ('CleanUI', 'NewMusic', 'damnlib'):
            stale = self.output / 'mods' / name / 'old-override.lua'
            stale.parent.mkdir(parents=True)
            stale.write_text('stale private third-party copy')
            (self.output / (name.lower() + '-source-patch.json')).write_text('stale provenance')
        result = prepare_install.prepare(self.root)
        self.assertEqual(set(prepare_install.MOD_IDS),
                         {path.name for path in (result / 'mods').iterdir()})
        self.assertFalse(list(result.glob('*-source-patch.json')))
        self.assertEqual((ROOT / prepare_install.INI_NAME).read_bytes(),
                         (result / 'Server' / prepare_install.INI_NAME).read_bytes())
        self.build.assert_called_once()
        self.assertFalse(self.sentinel.exists())

    def test_full_workshop_selection_failure_keeps_previous_publication(self):
        shutil.copyfile(ROOT / prepare_install.INI_NAME, self.root / prepare_install.INI_NAME)
        for name in ('CleanUI', 'NewMusic', 'damnlib'):
            stale = self.output / 'mods' / name / 'old-override.lua'
            stale.parent.mkdir(parents=True)
            stale.write_text('previous published bytes')
        before = {path.relative_to(self.output): path.read_bytes()
                  for path in self.output.rglob('*') if path.is_file()}
        self.build.side_effect = subprocess.CalledProcessError(1, ['build'])
        with self.assertRaises(subprocess.CalledProcessError):
            prepare_install.prepare(self.root)
        self.assertEqual(before, {path.relative_to(self.output): path.read_bytes()
                                 for path in self.output.rglob('*') if path.is_file()})
        self.assertEqual([self.output], list((self.root / 'dist').iterdir()))

    def test_rerun_removes_stale_prepared_files_and_preserves_other_dist_outputs(self):
        sibling = self.root / "dist/unrelated.zip"
        sibling.write_bytes(b"unrelated output")
        prepare_install.prepare(self.root)
        stale = self.output / "mods/PZSurvivorWishlist/obsolete.lua"
        stale.parent.mkdir(parents=True)
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
