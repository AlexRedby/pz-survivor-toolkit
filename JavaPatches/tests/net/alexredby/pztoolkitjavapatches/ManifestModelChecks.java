package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Files;
import java.nio.file.Path;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaThread;

/** Runs the shipped Lua model and its shared text vectors in the game's UTF-16 Kahlua. */
public final class ManifestModelChecks {
    public static void main(String[] args) throws Exception {
        var root = Path.of(System.getProperty("pz.test.project"));
        var platform = new J2SEPlatform();
        var environment = platform.newEnvironment();
        var thread = new KahluaThread(platform, environment);
        thread.debugOwnerThread = Thread.currentThread();
        thread.call(LuaCompiler.loadstring(
                "require=function() return {prepareItem=function() end} end; PZSurvivorToolkit={}",
                "bootstrap", environment), new Object[]{});
        try (var reader = Files.newBufferedReader(root.resolve(
                "PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ManifestModel.lua"))) {
            environment.rawset("TestManifestModel", thread.call(
                    LuaCompiler.loadis(reader, "ManifestModel.lua", environment), new Object[]{}));
        }
        environment.rawset("TestAccent", "é");
        environment.rawset("TestCyrillic", "Ж");
        environment.rawset("TestCjk", "洗");
        environment.rawset("TestEmoji", "🧟");
        environment.rawset("TestNbsp", "\u00a0");
        try (var reader = Files.newBufferedReader(root.resolve("tests/test_manifest_model.lua"))) {
            thread.call(LuaCompiler.loadis(reader, "test_manifest_model.lua", environment), new Object[]{});
        }
        System.out.println("MANIFEST_MODEL_CHECKS_PASS (same Lua model and vectors in native UTF16 Kahlua)");
        System.exit(0);
    }
}
