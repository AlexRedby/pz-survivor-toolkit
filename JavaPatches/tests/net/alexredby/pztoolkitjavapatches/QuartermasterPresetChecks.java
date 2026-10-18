package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaThread;

public final class QuartermasterPresetChecks {
    public static void main(String[] args) throws Exception {
        var root = Path.of(System.getProperty("pz.test.project"));
        var platform = new J2SEPlatform();
        var env = platform.newEnvironment();
        var thread = new KahluaThread(platform, env);
        thread.debugOwnerThread = Thread.currentThread();
        var modules = new HashMap<String, Object>();
        env.rawset("require", (JavaFunction)(frame, count) -> {
            Object module = modules.get((String)frame.get(0));
            if (module == null) throw new AssertionError("Unexpected module: " + frame.get(0));
            return frame.push(module);
        });
        for (String name : new String[]{"SourceProof", "TextFile", "QuartermasterPresetCodec", "QuartermasterPresetStorage"}) {
            try (var reader = Files.newBufferedReader(root.resolve(
                    "PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/" + name + ".lua"))) {
                modules.put("PZSurvivorToolkit/" + name,
                    thread.call(LuaCompiler.loadis(reader, name + ".lua", env), new Object[]{}));
            }
        }
        env.rawset("TestPresetCodec", modules.get("PZSurvivorToolkit/QuartermasterPresetCodec"));
        env.rawset("TestPresetStorage", modules.get("PZSurvivorToolkit/QuartermasterPresetStorage"));
        // Reader data is intact Java UTF16; the native compiler corrupts non-ASCII literals.
        env.rawset("TestPresetName", "Кладовая \"еда\" \\ 食料 😀\nnext\t" + (char)0 + "7");
        env.rawset("TestPresetOwner", "Игрок 😀");
        env.rawset("TestPresetItem", "Base.Тест");
        for (String name : new String[]{"test_quartermaster_preset_codec", "test_quartermaster_preset_storage"}) {
            try (var reader = Files.newBufferedReader(root.resolve("tests/" + name + ".lua"))) {
                thread.call(LuaCompiler.loadis(reader, name + ".lua", env), new Object[]{});
            }
        }
        System.out.println("QUARTERMASTER_PRESET_CHECKS_PASS (strict codec, UTF16 Unicode and snapshot fault recovery in Kahlua)");
        System.exit(0);
    }
}
