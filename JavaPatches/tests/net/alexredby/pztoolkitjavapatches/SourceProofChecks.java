package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Files;
import java.nio.file.Path;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaThread;

public final class SourceProofChecks {
    public static void main(String[] args) throws Exception {
        var root = Path.of(System.getProperty("pz.test.project"));
        var platform = new J2SEPlatform();
        var environment = platform.newEnvironment();
        var thread = new KahluaThread(platform, environment);
        thread.debugOwnerThread = Thread.currentThread();
        try (var reader = Files.newBufferedReader(root.resolve(
                "PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/SourceProof.lua"))) {
            environment.rawset("TestSourceProof", thread.call(
                LuaCompiler.loadis(reader, "SourceProof.lua", environment), new Object[]{}));
        }
        // Kahlua's compiler truncates non-ASCII literals; reader strings arrive from Java intact.
        environment.rawset("TestUnicodeA", "A洗😀é");
        environment.rawset("TestUnicodeB", "第二行");
        try (var reader = Files.newBufferedReader(root.resolve("tests/test_source_proof.lua"))) {
            thread.call(LuaCompiler.loadis(reader, "test_source_proof.lua", environment), new Object[]{});
        }
        System.out.println("SOURCE_PROOF_CHECKS_PASS (same Lua module and vectors in native UTF16 Kahlua)");
        System.exit(0);
    }
}
