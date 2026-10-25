package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.KahluaThread

object UITextFitChecks {
    @JvmStatic
    fun main(args: Array<String>) {
        val root = Path.of(System.getProperty("pz.test.project"))
        val platform = J2SEPlatform()
        val environment = platform.newEnvironment()
        val thread = KahluaThread(platform, environment)
        thread.debugOwnerThread = Thread.currentThread()
        thread.call(
            LuaCompiler.loadstring(
                "require=function() end; PZSurvivorToolkit={}",
                "bootstrap",
                environment,
            ),
            emptyArray<Any?>(),
        )
        Files.newBufferedReader(
                root.resolve(
                    "PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/UIStyle.lua",
                ),
            )
            .use { reader ->
                environment.rawset(
                    "TestUIStyle",
                    thread.call(
                        LuaCompiler.loadis(reader, "UIStyle.lua", environment),
                        emptyArray<Any?>(),
                    ),
                )
            }
        // Kahlua's compiler corrupts non-ASCII literals; game labels arrive from Java intact.
        environment.rawset("TestNbsp", "\u00a0")
        environment.rawset("TestEmoji", "😀")
        environment.rawset("TestAccent", "é")
        environment.rawset("TestCyrillic", "Ж")
        environment.rawset("TestCjk", "洗")
        Files.newBufferedReader(root.resolve("tests/test_ui_text_fit.lua")).use { reader ->
            thread.call(
                LuaCompiler.loadis(reader, "test_ui_text_fit.lua", environment),
                emptyArray<Any?>(),
            )
        }
        System.out.println(
            "UI_TEXT_FIT_CHECKS_PASS (same Lua helper and vectors in native UTF16 Kahlua)",
        )
        kotlin.system.exitProcess(0)
    }
}
