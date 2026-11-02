"""Opt-in execution of the world cleanup regression in installed Kahlua.

PZ_GAME/PZ_JDK select one installation; this starts a headless compiler/checker
under the shared preparation lease, never a game or GUI.
"""
import os
from pathlib import Path
import tempfile
import unittest

from tools.queue_checks import admission, preparation_process


ROOT = Path(__file__).resolve().parents[1]
HARNESS = r'''
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import org.luaj.kahluafork.compiler.FuncState;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.*;

public final class FixtureWorldCleanupChecks {
    static LuaClosure compile(String source, String name, KahluaTable env) throws Exception {
        String previous=FuncState.currentFile, previousFull=FuncState.currentfullFile;
        try {
            FuncState.currentFile=name;FuncState.currentfullFile=name;
            return LuaCompiler.loadstring(source,name,env);
        } finally { FuncState.currentFile=previous;FuncState.currentfullFile=previousFull; }
    }
    public static void main(String[] args) throws Exception {
        var platform=J2SEPlatform.getInstance();
        var env=platform.newTable();env.rawset("_G",env);
        se.krka.kahlua.stdlib.BaseLib.register(env);
        se.krka.kahlua.j2se.MathLib.register(platform,env);
        se.krka.kahlua.stdlib.RandomLib.register(platform,env);
        se.krka.kahlua.stdlib.StringLib.register(platform,env);
        se.krka.kahlua.stdlib.CoroutineLib.register(platform,env);
        se.krka.kahlua.stdlib.OsLib.register(platform,env);
        se.krka.kahlua.stdlib.TableLib.register(platform,env);
        var thread=new KahluaThread(System.out,platform,env);
        thread.debugOwnerThread=Thread.currentThread();
        try (var stream=Files.newInputStream(Path.of(args[2]))) {
            thread.call(Prototype.loadByteCode(stream,env),new Object[0]);
        }
        env.rawset("FixtureWorldCleanup",thread.call(compile(Files.readString(Path.of(args[0])),
            "QueueFixtureWorldCleanup.lua",env),new Object[0]));
        Object[] result=thread.pcall(compile(Files.readString(Path.of(args[1])),
            "test_fixture_world_cleanup.lua",env),new Object[0]);
        if (!Boolean.TRUE.equals(result[0])) throw new AssertionError(Arrays.toString(result));
        System.out.println("FIXTURE_WORLD_CLEANUP_NATIVE_PASS");
    }
}
'''


@unittest.skipUnless(os.environ.get('PZ_GAME') and os.environ.get('PZ_JDK'),
                     'PZ_GAME/PZ_JDK required for installed native Kahlua world cleanup test')
class NativeFixtureWorldCleanupTests(unittest.TestCase):
    def test_common_world_cleanup_full_regression_in_installed_kahlua(self):
        game, jdk = Path(os.environ['PZ_GAME']), Path(os.environ['PZ_JDK'])
        jar = game / 'projectzomboid.jar'
        lua = (ROOT / 'tests/test_fixture_world_cleanup.lua').read_text(encoding='utf-8')
        loader = "local W=assert(loadfile((ProjectRoot or '.')..'/tests/native_queue/support/QueueFixtureWorldCleanup.lua'))()"
        self.assertEqual(lua.count(loader), 1, 'native runner must replace only the source loader')
        # Bind the unchanged helper returned by the installed compiler. Execute
        # every Lua regression assertion without relying on a host Lua loadfile.
        lua = lua.replace(loader, 'local W=FixtureWorldCleanup', 1)
        with tempfile.TemporaryDirectory(prefix='pz-fixture-world-native-') as temporary:
            build = Path(temporary)
            source, smoke = build / 'FixtureWorldCleanupChecks.java', build / 'smoke.lua'
            source.write_text(HARNESS, encoding='utf-8')
            smoke.write_text(lua, encoding='utf-8')
            with admission.preparing(build, {'kind': 'sp'}):
                compiled = preparation_process.run([str(jdk / 'bin/javac'), '-cp', str(jar),
                    '-d', str(build), str(source)], capture_output=True, text=True, timeout=30)
                self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
                result = preparation_process.run([str(jdk / 'bin/java'), '-Djava.awt.headless=true',
                    '-cp', os.pathsep.join((str(build), str(jar))), 'FixtureWorldCleanupChecks',
                    str(ROOT / 'tests/native_queue/support/QueueFixtureWorldCleanup.lua'), str(smoke),
                    str(game / 'stdlib.lbc')], capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('FIXTURE_WORLD_CLEANUP_NATIVE_PASS', result.stdout)


if __name__ == '__main__':
    unittest.main()
