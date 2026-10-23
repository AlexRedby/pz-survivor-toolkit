package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.KahluaThread

object ContextMenuDuplicateChecks {
    @JvmStatic
    fun main(args: Array<String>) {
        val root = Path.of(System.getProperty("pz.test.project"))
        val platform = J2SEPlatform()
        val environment = platform.newEnvironment()
        val thread = KahluaThread(platform, environment)
        thread.debugOwnerThread = Thread.currentThread()
        Files.newBufferedReader(
                root.resolve(
                    "PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ContextMenuDuplicates.lua",
                ),
            )
            .use { reader ->
                environment.rawset(
                    "TestContextMenuDuplicates",
                    thread.call(
                        LuaCompiler.loadis(reader, "ContextMenuDuplicates.lua", environment),
                        emptyArray<Any?>(),
                    ),
                )
            }
        // Java maps equate empty lists, while Lua compares these userdata by identity.
        environment.rawset("TestUserdataA", java.util.ArrayList<Any?>())
        environment.rawset("TestUserdataB", java.util.ArrayList<Any?>())
        Files.newBufferedReader(root.resolve("tests/test_context_menu_duplicates.lua")).use { reader
            ->
            thread.call(
                LuaCompiler.loadis(reader, "test_context_menu_duplicates.lua", environment),
                emptyArray<Any?>(),
            )
        }
        System.out.println(
            "CONTEXT_MENU_DUPLICATE_CHECKS_PASS (same Lua helper and vectors in native Kahlua)",
        )
        kotlin.system.exitProcess(0)
    }
}
