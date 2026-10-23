package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.KahluaThread

object SourceProofChecks {
    @JvmStatic
    fun main(args: Array<String>) {
        val root = Path.of(System.getProperty("pz.test.project"))
        val platform = J2SEPlatform()
        val environment = platform.newEnvironment()
        val thread = KahluaThread(platform, environment).apply {
            debugOwnerThread = Thread.currentThread()
        }
        Files.newBufferedReader(root.resolve(
            "PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua")).use { reader ->
            val loader = LuaCompiler.loadis(reader, "SourceProof.lua", environment)
            environment.rawset("TestLoadSourceProof", loader)
            environment.rawset("TestSourceProof", thread.call(loader, emptyArray<Any?>()))
        }
        // Kahlua's compiler truncates non-ASCII literals; reader strings arrive from Java intact.
        environment.rawset("TestUnicodeA", "A洗😀é")
        environment.rawset("TestUnicodeB", "第二行")
        Files.newBufferedReader(root.resolve("tests/test_source_proof.lua")).use { reader ->
            thread.call(LuaCompiler.loadis(reader, "test_source_proof.lua", environment), emptyArray<Any?>())
        }
        println("SOURCE_PROOF_CHECKS_PASS (same Lua module and vectors in native UTF16 Kahlua)")
        kotlin.system.exitProcess(0)
    }
}
