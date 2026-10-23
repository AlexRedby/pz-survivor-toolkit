package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.KahluaTable
import se.krka.kahlua.vm.KahluaThread
import se.krka.kahlua.vm.LuaClosure
import se.krka.kahlua.vm.Prototype

/** Executes the same source-based Lua regressions with the game's table semantics. */
object DrinkFluidCompletionChecks {
    @JvmStatic
    fun filename(prototype: Prototype, path: String?) {
        prototype.filename = path
        for (child in prototype.prototypes) filename(child, path)
    }

    @JvmStatic
    fun compile(text: String?, path: String?, environment: KahluaTable?): LuaClosure {
        val closure = LuaCompiler.loadstring(text, path, environment)
        filename(closure.prototype, path)
        return closure
    }

    @JvmStatic
    fun main(args: Array<String>) {
        val root = Path.of(System.getProperty("pz.test.project"))
        val platform = J2SEPlatform()
        val environment = platform.newEnvironment()
        val thread = KahluaThread(platform, environment)
        thread.debugOwnerThread = Thread.currentThread()
        environment.rawset("ProjectRoot", root.toString())
        environment.rawset("NativeActionRoot", Path.of("media/lua").toAbsolutePath().toString())
        environment.rawset(
            "NativeReadText",
            JavaFunction { frame, _ ->
                try {
                    frame.push(Files.readString(Path.of(frame.get(0) as String?)))
                    1
                } catch (error: Exception) {
                    throw RuntimeException(error)
                }
            },
        )
        environment.rawset(
            "NativeFilenameOfClosure",
            JavaFunction { frame, _ ->
                val closure = frame.get(0)
                frame.push(if (closure is LuaClosure) closure.prototype.filename else null)
                1
            },
        )
        environment.rawset(
            "loadstring",
            JavaFunction { frame, count ->
                try {
                    frame.push(
                        compile(
                            frame.get(0) as String?,
                            if (count > 1) frame.get(1) as String? else "=(loadstring)",
                            environment,
                        ),
                    )
                    1
                } catch (error: Exception) {
                    throw RuntimeException(error)
                }
            },
        )
        environment.rawset(
            "loadfile",
            JavaFunction { frame, _ ->
                try {
                    val path = frame.get(0) as String?
                    frame.push(compile(Files.readString(Path.of(path)), path, environment))
                    1
                } catch (error: Exception) {
                    throw RuntimeException(error)
                }
            },
        )
        val path = root.resolve("tests/test_drink_fluid_boundary.lua")
        thread.call(
            compile(Files.readString(path), path.toString(), environment),
            emptyArray<Any?>(),
        )
        if (!true.equals(environment.rawget("TestDrinkFluidBoundaryPassed"))) {
            throw AssertionError("Drink boundary vectors did not reach their completion marker")
        }
        println("DRINK_FLUID_COMPLETION_CHECKS_PASS (shared boundary vectors in native Kahlua)")
        kotlin.system.exitProcess(0)
    }
}
