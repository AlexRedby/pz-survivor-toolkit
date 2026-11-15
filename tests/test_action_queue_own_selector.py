"""Actual Java compiler output and the own-intent UI selector source contract.

Set PZ_GAME, PZ_JDK, PZ_CLEANUI_PANE and PZ_P4_SOURCE for the installed-source check.
The native compiler only compiles Lua; gameplay runs in the existing offline model.
"""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PROBE = r'''
import java.io.StringReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.Prototype;
public final class OwnSelectorCompilerProbe {
    private static void inspect(Prototype value) {
        if (value.name.equals("getActualItems") || value.name.equals("CleanUI_updateCollapsedFoodStackAge"))
            System.out.println(value.name + "=" + value.lines[0]);
        if (value.prototypes != null) for (Prototype child : value.prototypes) inspect(child);
    }
    public static void main(String[] args) throws Exception {
        String original = Files.readString(Path.of(args[0]));
        Class<?> owner = Class.forName("net.alexredby.pztoolkitjavapatches.CleanUIFoodAge");
        String transformed = (String)owner.getMethod("transformSource", String.class).invoke(null, original);
        String digest = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
            .digest(transformed.getBytes(StandardCharsets.UTF_8)));
        if (transformed.equals(original) || !digest.equals(owner.getField("OUTPUT_SHA256").get(null)))
            throw new AssertionError("actual reviewed CleanUI compiler transform was not exercised");
        Files.writeString(Path.of(args[1]), transformed);
        LuaCompiler.rewriteEvents = false;
        inspect(LuaCompiler.loadis(new StringReader(transformed), args[0], null).prototype);
    }
}
'''


class OwnSelectorCompiler(unittest.TestCase):
    def test_actual_transformed_selector_retires_only_its_prior_native_loan(self):
        inputs = [os.environ.get(name) for name in ('PZ_GAME', 'PZ_JDK', 'PZ_CLEANUI_PANE', 'PZ_P4_SOURCE')]
        if not all(inputs):
            self.skipTest('Set PZ_GAME, PZ_JDK, PZ_CLEANUI_PANE and PZ_P4_SOURCE for actual compiler inputs')
        from lupa.lua51 import LuaRuntime
        game, jdk, pane, p4 = map(Path, inputs)
        jar = game / 'projectzomboid.jar'
        patches = ROOT / 'JavaPatches/build/PZToolkitJavaPatches/42/media/java/PZToolkitJavaPatches.jar'
        self.assertTrue(patches.is_file(), 'Build Java Patches before testing its actual compiler transform')
        with tempfile.TemporaryDirectory(prefix='pz-own-selector-') as directory:
            temporary = Path(directory)
            source = temporary / 'OwnSelectorCompilerProbe.java'
            source.write_text(PROBE)
            classpath = os.pathsep.join(map(str, (jar, patches)))
            subprocess.run([str(jdk / 'bin/javac'), '-cp', classpath, '-d', str(temporary), str(source)],
                           check=True, capture_output=True, text=True, timeout=60)
            output = temporary / 'compiled-pane.lua'
            result = subprocess.run([str(jdk / 'bin/java'), '-cp', str(temporary) + os.pathsep + classpath,
                                     'OwnSelectorCompilerProbe', str(pane), str(output)],
                                    check=True, capture_output=True, text=True, timeout=60)
            self.assertIn('getActualItems=3775', result.stdout.splitlines())
            self.assertIn('CleanUI_updateCollapsedFoodStackAge=867', result.stdout.splitlines())
            self.assertEqual('a0e001a7de8cd908c1e0e95d06e551bfb8f9cc4dac7f12ed74becfd8c2cb1a74',
                             hashlib.sha256(output.read_bytes()).hexdigest())
            lua = LuaRuntime()
            values = lua.globals()
            values.ProjectRoot = str(ROOT)
            values.NativeActionRoot = str(game / 'media/lua')
            values.NativeP4TidySource = str(p4)
            values.CleanUIInventoryPaneSource = pane.read_text()
            values.CleanUIInventoryContextMenuSource = (pane.parent / 'ISInventoryPaneContextMenu.lua').read_text()
            values.CleanUIInventoryPaneCompiledSource = output.read_text()
            lua.execute((ROOT / 'tests/test_action_queue_restoration_composition.lua').read_text())
            values.InvalidCompilerNamespaceSource = output.read_text().replace(
                'CleanUI_ToolkitFoodAge = {\n    protocol = 1,',
                'CleanUI_ToolkitFoodAge = {\n    protocol = 2,', 1)
            self.assertNotEqual(values.CleanUIInventoryPaneCompiledSource, values.InvalidCompilerNamespaceSource)
            lua.execute('''
                local create=assert(loadfile(ProjectRoot..'/tests/support/borrowing_composition.lua'))()
                local f=create(false,{p4=false,carried=true,cleanUISelectorSource=CleanUIInventoryPaneSource,
                    cleanUIContextSource=CleanUIInventoryContextMenuSource,
                    cleanUISelectorCompiledSource=InvalidCompilerNamespaceSource})
                f.env.ISInventoryPaneContextMenu.onWringClothing({f.garment(714,f.inventory)},0)
                assert(not f.env.PZSurvivorToolkit.ActionQueueTidyIntent.status(),
                    'transformed selector role alone accepted an unknown compiler namespace')
            ''')


if __name__ == '__main__':
    unittest.main()
