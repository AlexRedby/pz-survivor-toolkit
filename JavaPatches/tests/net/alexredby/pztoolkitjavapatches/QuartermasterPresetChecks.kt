package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import java.util.HashMap
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.KahluaThread

object QuartermasterPresetChecks {
    @JvmStatic
    fun main(args: Array<String>) {
        val root = Path.of(System.getProperty("pz.test.project"))
        val platform = J2SEPlatform()
        val env = platform.newEnvironment()
        val thread = KahluaThread(platform, env)
        thread.debugOwnerThread = Thread.currentThread()
        val modules = HashMap<String, Any?>()
        env.rawset(
            "require",
            JavaFunction { frame, _ ->
                val module =
                    modules[frame.get(0) as String?]
                        ?: throw AssertionError("Unexpected module: " + frame.get(0))
                frame.push(module)
            },
        )
        for (name in
            arrayOf(
                "SourceProof",
                "TextFile",
                "QuartermasterPresetCodec",
                "QuartermasterPresetStorage",
            )) {
            Files.newBufferedReader(
                    root.resolve(
                        "PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/" + name + ".lua",
                    ),
                )
                .use { reader ->
                    modules["PZSurvivorToolkit/" + name] =
                        thread.call(
                            LuaCompiler.loadis(reader, name + ".lua", env),
                            emptyArray<Any?>(),
                        )
                }
        }
        env.rawset("TestPresetCodec", modules["PZSurvivorToolkit/QuartermasterPresetCodec"])
        env.rawset("TestPresetStorage", modules["PZSurvivorToolkit/QuartermasterPresetStorage"])
        // Reader data is intact Java UTF16; the native compiler corrupts non-ASCII literals.
        env.rawset("TestPresetName", "Кладовая \"еда\" \\ 食料 😀\nnext\t" + 0.toChar() + "7")
        env.rawset("TestPresetOwner", "Игрок 😀")
        env.rawset("TestPresetItem", "Base.Тест")
        for (name in
            arrayOf("test_quartermaster_preset_codec", "test_quartermaster_preset_storage")) {
            Files.newBufferedReader(root.resolve("tests/" + name + ".lua")).use { reader ->
                thread.call(LuaCompiler.loadis(reader, name + ".lua", env), emptyArray<Any?>())
            }
        }
        println(
            "QUARTERMASTER_PRESET_CHECKS_PASS (strict codec, UTF16 Unicode and snapshot fault recovery in Kahlua)",
        )
        kotlin.system.exitProcess(0)
    }
}
