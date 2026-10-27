package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.KahluaThread
import se.krka.kahlua.vm.LuaClosure
import zombie.Lua.LuaManager

/** Qualifies the shared WMI restoration vectors against the game's Kahlua runtime. */
object WashWaterRuleChecks {
    @JvmStatic
    fun main(args: Array<String>) {
        val root = Path.of(System.getProperty("pz.test.project"))
        val workshop =
            System.getProperty("pz.test.workshop")
                ?: System.getenv("PZ_TEST_WORKSHOP")
                ?: throw IllegalArgumentException(
                    "Pass -Dpz.test.workshop or PZ_TEST_WORKSHOP with the Workshop content root",
                )
        val platform = J2SEPlatform()
        val environment = platform.newEnvironment()
        val thread = KahluaThread(platform, environment)
        thread.debugOwnerThread = Thread.currentThread()
        // Native error(table) formatting consults the game's LuaManager globals.
        LuaManager.platform = platform
        LuaManager.env = environment
        LuaManager.thread = thread
        environment.rawset("ProjectRoot", root.toString())
        environment.rawset("NativeActionRoot", Path.of("media/lua").toAbsolutePath().toString())
        environment.rawset("NativeWishlistWorkshopRoot", Path.of(workshop).toAbsolutePath().toString())
        environment.rawset(
            "NativeReadText",
            JavaFunction { frame, _ ->
                frame.push(Files.readString(Path.of(frame.get(0) as String)))
                1
            },
        )
        environment.rawset(
            "NativeFilenameOfClosure",
            JavaFunction { frame, _ ->
                val callback = frame.get(0)
                frame.push(if (callback is LuaClosure) callback.prototype.filename else null)
                1
            },
        )
        environment.rawset(
            "loadstring",
            JavaFunction { frame, count ->
                frame.push(
                    DrinkFluidCompletionChecks.compile(
                        frame.get(0) as String?,
                        if (count > 1) frame.get(1) as String? else "=(loadstring)",
                        environment,
                    ),
                )
                1
            },
        )
        environment.rawset(
            "loadfile",
            JavaFunction { frame, _ ->
                val path = Path.of(frame.get(0) as String)
                frame.push(
                    DrinkFluidCompletionChecks.compile(
                        Files.readString(path),
                        path.toString(),
                        environment,
                    ),
                )
                1
            },
        )
        val path = root.resolve("tests/test_wash_water_rule.lua")
        thread.call(
            DrinkFluidCompletionChecks.compile(Files.readString(path), path.toString(), environment),
            emptyArray<Any?>(),
        )
        check(true.equals(environment.rawget("TestWashWaterRulePassed"))) {
            "Wash water restoration vectors did not reach their completion marker"
        }
        println("WASH_WATER_RULE_CHECKS_PASS (same source-based restoration vectors in native Kahlua)")
        kotlin.system.exitProcess(0)
    }
}
