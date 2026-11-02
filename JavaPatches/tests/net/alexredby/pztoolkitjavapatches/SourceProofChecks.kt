package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.KahluaThread

object SourceProofChecks {
    @JvmStatic
    fun main(args: Array<String>) {
        val root = Path.of(System.getProperty("pz.test.project"))
        val platform = J2SEPlatform()
        val environment = platform.newEnvironment()
        val thread =
            KahluaThread(platform, environment).apply {
                debugOwnerThread = Thread.currentThread()
            }
        val matches = JavaFunction { frame, count ->
            frame.push(QueueLeafTransferFacts.luaMetatableMatches(frame.get(0), if (count > 1) frame.get(1) else null))
            1
        }
        environment.rawset("NativeMetatableMatches", matches)
        environment.rawset("toolkitLuaMetatableMatches", matches)
        val owner = platform.newTable() as KahluaTableImpl
        val parent = platform.newTable() as KahluaTableImpl
        val replacement = platform.newTable() as KahluaTableImpl
        var callbacks = 0
        replacement.rawset("__metatable", parent)
        replacement.rawset("__index", JavaFunction { _, _ ->
            callbacks++
            error("Metatable identity must not invoke Lua or inherited callbacks")
        })
        check(QueueLeafTransferFacts.luaMetatableMatches(owner, null))
        owner.metatable = parent
        check(QueueLeafTransferFacts.luaMetatableMatches(owner, parent))
        check(!QueueLeafTransferFacts.luaMetatableMatches(owner, null))
        owner.metatable = replacement
        environment.rawset("TestProtectedOwner", owner)
        environment.rawset("TestVisibleParent", parent)
        val visible = LuaCompiler.loadis(
            "return getmetatable(TestProtectedOwner)==TestVisibleParent".reader(),
            "=(protected metatable diagnostic)", environment,
        )
        check(thread.call(visible, emptyArray<Any?>()) == true) { "Protected parent fixture is not concealed" }
        check(!QueueLeafTransferFacts.luaMetatableMatches(owner, parent)) { "Protected replacement escaped actual-parent proof" }
        check(QueueLeafTransferFacts.luaMetatableMatches(owner, replacement))
        owner.setRewriteTable(platform.newTable())
        check(!QueueLeafTransferFacts.luaMetatableMatches(owner, replacement)) { "Rewritten owner was accepted" }
        owner.setRewriteTable(null)
        replacement.setRewriteTable(platform.newTable())
        check(!QueueLeafTransferFacts.luaMetatableMatches(owner, replacement)) { "Rewritten expected parent was accepted" }
        replacement.setRewriteTable(null)
        check(!QueueLeafTransferFacts.luaMetatableMatches(Any(), null))
        check(!QueueLeafTransferFacts.luaMetatableMatches(owner, Any()))
        check(!QueueLeafTransferFacts.luaMetatableMatches(KahluaTableImpl(java.util.HashMap()), null))
        check(callbacks == 0)
        environment.rawset("TestProtectedOwner", null)
        environment.rawset("TestVisibleParent", null)
        Files.newBufferedReader(
                root.resolve(
                    "PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua",
                ),
            )
            .use { reader ->
                val loader = LuaCompiler.loadis(reader, "SourceProof.lua", environment)
                environment.rawset("TestLoadSourceProof", loader)
                environment.rawset("TestSourceProof", thread.call(loader, emptyArray<Any?>()))
            }
        // Kahlua's compiler truncates non-ASCII literals; reader strings arrive from Java intact.
        environment.rawset("TestUnicodeA", "A洗😀é")
        environment.rawset("TestUnicodeB", "第二行")
        Files.newBufferedReader(root.resolve("tests/test_source_proof.lua")).use { reader ->
            thread.call(
                LuaCompiler.loadis(reader, "test_source_proof.lua", environment),
                emptyArray<Any?>(),
            )
        }
        println("SOURCE_PROOF_CHECKS_PASS (same Lua module and vectors in native UTF16 Kahlua)")
        kotlin.system.exitProcess(0)
    }
}
