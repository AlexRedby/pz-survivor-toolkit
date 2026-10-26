package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.KahluaThread
import se.krka.kahlua.vm.LuaClosure
import zombie.Lua.LuaManager

/** Runs the shared ownership umbrella with actual Kahlua tables, isolated by variant. */
object QueueOwnershipChecks {
    private fun runVariant(root: Path, workshop: Path, variant: String?) {
        val platform = J2SEPlatform()
        val environment = platform.newEnvironment()
        val thread = KahluaThread(platform, environment)
        thread.debugOwnerThread = Thread.currentThread()
        LuaManager.platform = platform
        LuaManager.env = environment
        LuaManager.thread = thread
        environment.rawset("ProjectRoot", root.toString())
        environment.rawset("NativeActionRoot", Path.of("media/lua").toAbsolutePath().toString())
        environment.rawset("NativeWishlistWorkshopRoot", workshop.toAbsolutePath().toString())
        System.getenv("PZ_CUSTOM_LIGHT_SWITCH_SOURCE")?.let {
            environment.rawset("CustomLightSwitchSource", it)
        }
        if (variant != null) environment.rawset(variant, true)
        environment.rawset(
            "print",
            JavaFunction { frame, count ->
                val render = environment.rawget("tostring")
                val values = (0 until count).map { index ->
                    thread.call(render, arrayOf<Any?>(frame.get(index)))
                }
                println(values.joinToString("\t") { it?.toString() ?: "nil" })
                0
            },
        )
        val readText = JavaFunction { frame, _ ->
            frame.push(Files.readString(Path.of(frame.get(0) as String)))
            1
        }
        environment.rawset("NativeReadText", readText)
        environment.rawset("NativeReadRawText", readText)
        environment.rawset(
            "NativeFileExists",
            JavaFunction { frame, _ ->
                frame.push(Files.isRegularFile(Path.of(frame.get(0) as String)))
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
            "NativeCallerSource",
            JavaFunction { frame, _ ->
                val depth = (frame.get(0) as Number).toInt()
                require(depth >= 0) { "Caller depth must be non-negative" }
                val caller = frame.coroutine.getParentNoAssert(depth)
                frame.push(caller?.closure?.prototype?.filename)
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
        thread.call(
            DrinkFluidCompletionChecks.compile(
                "function dofile(path) return assert(loadfile(path))() end",
                "=(ownership harness)",
                environment,
            ),
            emptyArray<Any?>(),
        )
        // Verify Lua-style depth against two real compiled call frames. Keep
        // both calls non-tail calls so the outer frame remains observable.
        val inner = thread.call(
            DrinkFluidCompletionChecks.compile(
                "return function() local source=NativeCallerSource(2); return source end",
                "@ownership-caller-inner.lua",
                environment,
            ),
            emptyArray<Any?>(),
        )
        environment.rawset("OwnershipCallerInner", inner)
        val outer = thread.call(
            DrinkFluidCompletionChecks.compile(
                "return function() local source=OwnershipCallerInner(); return source end",
                "@ownership-caller-outer.lua",
                environment,
            ),
            emptyArray<Any?>(),
        )
        check(thread.call(outer, emptyArray<Any?>()) == "@ownership-caller-outer.lua") {
            "Native caller-source depth did not identify the actual outer Lua frame"
        }
        environment.rawset("OwnershipCallerInner", null)
        val rawgetArity = thread.call(
            DrinkFluidCompletionChecks.compile(
                "return select('#',rawget({},'absent'))",
                "=(native rawget diagnostic)",
                environment,
            ),
            emptyArray<Any?>(),
        )
        println("QUEUE_OWNERSHIP_NATIVE_RAWGET_ARITY ${variant ?: "OwnershipLookup"} $rawgetArity")
        val path = root.resolve("tests/test_action_queue_ownership.lua")
        val result = thread.pcall(
            DrinkFluidCompletionChecks.compile(Files.readString(path), path.toString(), environment),
            emptyArray<Any?>(),
        )
        check(true.equals(result[0])) {
            "${result.getOrNull(1)}\n${result.getOrNull(2)}"
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        val root = Path.of(System.getProperty("pz.test.project"))
        val workshop =
            System.getProperty("pz.test.workshop")
                ?: System.getenv("PZ_TEST_WORKSHOP")
                ?: throw IllegalArgumentException(
                    "Pass -Dpz.test.workshop or PZ_TEST_WORKSHOP with the Workshop content root",
                )
        val variants = listOf(
            null, "OwnershipRadio", "OwnershipItems", "OwnershipMedia", "OwnershipRecovery",
            "OwnershipGenerators", "OwnershipApproach", "OwnershipHealth", "OwnershipLifecycle", "OwnershipSettlement",
        )
        val failures = mutableListOf<String>()
        for (variant in variants) {
            val label = variant ?: "OwnershipLookup"
            try {
                runVariant(root, Path.of(workshop), variant)
                println("QUEUE_OWNERSHIP_VARIANT_PASS $label")
            } catch (failure: Exception) {
                failures.add(label)
                println("QUEUE_OWNERSHIP_VARIANT_FAIL $label: ${failure.message}")
                failure.printStackTrace(System.out)
            }
        }
        check(failures.isEmpty()) { "Ownership variants failed: ${failures.joinToString()}" }
        println("QUEUE_OWNERSHIP_CHECKS_PASS (${variants.size} fresh native Kahlua environments)")
        kotlin.system.exitProcess(0)
    }
}
