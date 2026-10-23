package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.KahluaThread

/** Runs the shipped Lua model and its shared text vectors in the game's UTF-16 Kahlua. */
object ManifestModelChecks {
    @JvmStatic
    fun main(args: Array<String>) {
        val root = Path.of(System.getProperty("pz.test.project"))
        val platform = J2SEPlatform()
        val environment = platform.newEnvironment()
        val thread = KahluaThread(platform, environment)
        thread.debugOwnerThread = Thread.currentThread()
        thread.call(
            LuaCompiler.loadstring(
                "require=function() return {prepareItem=function() end} end; PZSurvivorToolkit={}",
                "bootstrap",
                environment,
            ),
            emptyArray<Any?>(),
        )
        Files.newBufferedReader(
                root.resolve(
                    "PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ManifestModel.lua",
                ),
            )
            .use { reader ->
                environment.rawset(
                    "TestManifestModel",
                    thread.call(
                        LuaCompiler.loadis(reader, "ManifestModel.lua", environment),
                        emptyArray<Any?>(),
                    ),
                )
            }
        environment.rawset("TestAccent", "é")
        environment.rawset("TestCyrillic", "Ж")
        environment.rawset("TestCjk", "洗")
        environment.rawset("TestEmoji", "🧟")
        environment.rawset("TestNbsp", "\u00a0")
        Files.newBufferedReader(root.resolve("tests/test_manifest_model.lua")).use { reader ->
            thread.call(
                LuaCompiler.loadis(reader, "test_manifest_model.lua", environment),
                emptyArray<Any?>(),
            )
        }
        System.out.println(
            "MANIFEST_MODEL_CHECKS_PASS (same Lua model and vectors in native UTF16 Kahlua)",
        )
        kotlin.system.exitProcess(0)
    }
}
