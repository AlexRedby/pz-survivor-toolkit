package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Files;
import java.nio.file.Path;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaThread;

public final class UITextFitChecks {
    public static void main(String[] args) throws Exception {
        var root = Path.of(System.getProperty("pz.test.project"));
        var platform = new J2SEPlatform();
        var environment = platform.newEnvironment();
        var thread = new KahluaThread(platform, environment);
        thread.debugOwnerThread = Thread.currentThread();
        thread.call(LuaCompiler.loadstring("require=function() end; PZSurvivorToolkit={}",
                "bootstrap", environment), new Object[]{});
        try (var reader = Files.newBufferedReader(root.resolve(
                "PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/UIStyle.lua"))) {
            environment.rawset("TestUIStyle", thread.call(
                    LuaCompiler.loadis(reader, "UIStyle.lua", environment), new Object[]{}));
        }
        // Kahlua's compiler corrupts non-ASCII literals; game labels arrive from Java intact.
        environment.rawset("TestNbsp", "\u00a0");
        environment.rawset("TestEmoji", "😀");
        environment.rawset("TestAccent", "é");
        environment.rawset("TestCyrillic", "Ж");
        environment.rawset("TestCjk", "洗");
        try (var reader = Files.newBufferedReader(root.resolve("tests/test_ui_text_fit.lua"))) {
            thread.call(LuaCompiler.loadis(reader, "test_ui_text_fit.lua", environment), new Object[]{});
        }
        System.out.println("UI_TEXT_FIT_CHECKS_PASS (same Lua helper and vectors in native UTF16 Kahlua)");
        System.exit(0);
    }
}
