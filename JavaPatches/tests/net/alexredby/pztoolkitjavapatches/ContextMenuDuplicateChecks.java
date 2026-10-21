package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Files;
import java.nio.file.Path;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaThread;

public final class ContextMenuDuplicateChecks {
    public static void main(String[] args) throws Exception {
        var root = Path.of(System.getProperty("pz.test.project"));
        var platform = new J2SEPlatform();
        var environment = platform.newEnvironment();
        var thread = new KahluaThread(platform, environment);
        thread.debugOwnerThread = Thread.currentThread();
        try (var reader = Files.newBufferedReader(root.resolve(
                "PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ContextMenuDuplicates.lua"))) {
            environment.rawset("TestContextMenuDuplicates", thread.call(
                    LuaCompiler.loadis(reader, "ContextMenuDuplicates.lua", environment), new Object[]{}));
        }
        // Java maps equate empty lists, while Lua compares these userdata by identity.
        environment.rawset("TestUserdataA", new java.util.ArrayList<>());
        environment.rawset("TestUserdataB", new java.util.ArrayList<>());
        try (var reader = Files.newBufferedReader(root.resolve("tests/test_context_menu_duplicates.lua"))) {
            thread.call(LuaCompiler.loadis(reader, "test_context_menu_duplicates.lua", environment), new Object[]{});
        }
        System.out.println("CONTEXT_MENU_DUPLICATE_CHECKS_PASS (same Lua helper and vectors in native Kahlua)");
        System.exit(0);
    }
}
