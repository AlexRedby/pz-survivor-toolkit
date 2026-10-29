package net.alexredby.pztoolkitjavapatches

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.lang.ref.WeakReference
import java.nio.file.Files
import java.nio.file.Path
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.KahluaTable
import se.krka.kahlua.vm.KahluaThread
import se.krka.kahlua.vm.KahluaUtil
import se.krka.kahlua.vm.LuaClosure
import se.krka.kahlua.vm.Prototype

/** Native compiler provenance, Lua fallback boundaries, and serialization parity. */
object QueueBindingCompilerChecks {
    private const val SOURCE_DIRECTORY = "PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/"
    private val noArgs = emptyArray<Any?>()

    private fun nodes(root: Prototype): List<Prototype> =
        listOf(root) + root.prototypes.flatMap(::nodes)

    private fun nativeConstants(closure: LuaClosure): Int =
        nodes(closure.prototype).sumOf { prototype ->
            prototype.constants.count { it is JavaFunction }
        }

    private fun filename(prototype: Prototype, path: String) {
        prototype.filename = path
        prototype.prototypes.forEach { filename(it, path) }
    }

    private fun section(text: String, start: String, end: String): String {
        val first = text.indexOf(start)
        check(first >= 0) { "Missing source fixture start: $start" }
        val last = text.indexOf(end, first)
        check(last >= 0) { "Missing source fixture end: $end" }
        return text.substring(first, last)
    }

    // Test privilege only. Production exposes no arbitrary-input bind API.
    private fun bindSynthetic(text: String, path: String, environment: KahluaTable): LuaClosure? {
        val owner = QueueBindingCompiler::class.java
        val sites =
            owner.declaredMethods
                .single { it.name == "sites" && it.parameterCount == 1 }
                .apply { isAccessible = true }
                .invoke(QueueBindingCompiler, path)
        return owner.declaredMethods
            .single { it.name == "bind" && it.parameterCount == 4 }
            .apply { isAccessible = true }
            .invoke(QueueBindingCompiler, text, path, environment, sites) as LuaClosure?
    }

    private class Observations {
        var visits = 0L
        var hits = 0L
        var captures = 0L

        fun observe(closure: LuaClosure) {
            for (prototype in nodes(closure.prototype)) {
                for (index in prototype.constants.indices) {
                    val factory = prototype.constants[index] as? JavaFunction ?: continue
                    prototype.constants[index] = JavaFunction { frame, count ->
                        captures++
                        val returned = factory.call(frame, count)
                        check(returned == 1)
                        val slot = frame.top - 1
                        val checker = frame.get(slot) as JavaFunction
                        frame.set(
                            slot,
                            JavaFunction { current, arguments ->
                                visits++
                                // Direct delegation retains the actual Lua parent frame;
                                // no KahluaThread.call or extra native frame is introduced.
                                val results = checker.call(current, arguments)
                                check(results == 1)
                                if (current.get(current.top - 1) == true) hits++
                                results
                            },
                        )
                        returned
                    }
                }
            }
        }
    }

    private fun trustChecks(root: Path, compat: String, carts: String) {
        val platform = J2SEPlatform()
        val environment = platform.newEnvironment() as KahluaTableImpl
        val thread =
            KahluaThread(platform, environment).apply { debugOwnerThread = Thread.currentThread() }
        zombie.Lua.LuaManager.env = environment
        for ((text, path, expected) in
            listOf(
                Triple(compat, "ActionQueueCompat.lua", 2),
                Triple(carts, "ActionQueueCarts.lua", 1),
            )) {
            check(
                nativeConstants(QueueBindingCompiler.compile(text, path, environment, true)) ==
                    expected,
            )
            check(
                nativeConstants(QueueBindingCompiler.compile(text, path, environment, false)) == 0,
            )
            check(
                nativeConstants(
                    QueueBindingCompiler.compile(
                        text + "\n-- unknown input",
                        path,
                        environment,
                        true,
                    ),
                ) == 0,
            )
            check(
                nativeConstants(
                    QueueBindingCompiler.compile(text, "Foreign.lua", environment, true),
                ) == 0,
            )
        }
        val bc =
            section(
                compat,
                "    containerHelpersUnchanged = function()\n",
                "\n    local policy = Toolkit.ActionQueuePolicy",
            )
        val fridge =
            section(
                compat,
                "    local function helpersUnchanged()\n        if TurnOffFridges ~= owner",
                "\n    local replacement = transferMethods()",
            )
        val compatFixture =
            "local helpers,staleVehicle,proximity,proximityMethods,owner,functions,constants,module,autoKey,priorGuard=...\n" +
                "local containerHelpersUnchanged\n$bc\n$fridge\nreturn containerHelpersUnchanged,helpersUnchanged"
        val cartGuard =
            section(carts, "local function unchanged()\n", "\nlocal function transferUnchanged()")
        val cartFixture =
            "local trusted,trustFailure,Toolkit,Carts,involvesCart,isTransfer,capacitySafe,class,core,network,approvedPerform,compat,approvePerform,methods,coreMethods,sendToServer=...\n" +
                "$cartGuard\nreturn unchanged"
        val observations = Observations()
        fun fixture(text: String, path: String, enabled: Boolean): LuaClosure {
            val closure =
                if (enabled) {
                    checkNotNull(bindSynthetic(text, path, environment)).also(observations::observe)
                } else LuaCompiler.loadstring(text, path, environment)
            filename(closure.prototype, path)
            return closure
        }
        environment.rawset("BaseCompat", fixture(compatFixture, "ActionQueueCompat.lua", false))
        environment.rawset("OwnedCompat", fixture(compatFixture, "ActionQueueCompat.lua", true))
        environment.rawset("BaseCarts", fixture(cartFixture, "ActionQueueCarts.lua", false))
        environment.rawset("OwnedCarts", fixture(cartFixture, "ActionQueueCarts.lua", true))
        check(
            bindSynthetic(
                "local containerHelpersUnchanged\n$bc\nreturn containerHelpersUnchanged",
                "ActionQueueCompat.lua",
                environment,
            ) == null,
        ) {
            "Partial Compat input acquired a partially bound native factory"
        }
        val functionMeta = platform.newTable()
        KahluaUtil.getClassMetatables(platform, environment)
            .rawset(LuaClosure::class.java, functionMeta)
        environment.rawset("FunctionMeta", functionMeta)
        environment.rawset(
            "NativeChecks",
            JavaFunction { frame, _ ->
                frame.push(observations.visits.toDouble())
                1
            },
        )
        environment.rawset(
            "NativeHits",
            JavaFunction { frame, _ ->
                frame.push(observations.hits.toDouble())
                1
            },
        )
        environment.rawset(
            "NativeCaptures",
            JavaFunction { frame, _ ->
                frame.push(observations.captures.toDouble())
                1
            },
        )
        environment.rawset(
            "NativeFilename",
            JavaFunction { frame, _ ->
                frame.push((frame.get(0) as LuaClosure).prototype.filename)
                1
            },
        )
        environment.rawset(
            "NativeFirstLine",
            JavaFunction { frame, _ ->
                frame.push((frame.get(0) as LuaClosure).prototype.lines[0].toDouble())
                1
            },
        )
        environment.rawset(
            "CloneSamePrototype",
            JavaFunction { frame, _ ->
                val original = frame.get(0) as LuaClosure
                val clone = LuaClosure(original.prototype, original.env)
                for (index in clone.upvalues.indices) clone.upvalues[index] =
                    original.upvalues[index]
                frame.push(clone)
                1
            },
        )
        environment.rawset(
            "SetDebug",
            JavaFunction { frame, _ ->
                zombie.core.Core.debug = frame.get(0) == true
                0
            },
        )
        environment.rawset(
            "Emit",
            JavaFunction { frame, _ ->
                println(frame.get(0))
                0
            },
        )
        environment.rawset("ForeignDelegate", KahluaTableImpl(java.util.HashMap()))
        val path =
            root.resolve(
                "JavaPatches/tests/net/alexredby/pztoolkitjavapatches/QueueBindingCompilerChecks.lua",
            )
        val script = LuaCompiler.loadstring(Files.readString(path), path.toString(), environment)
        filename(script.prototype, path.toString())
        try {
            val outcome = thread.pcall(script, noArgs)
            check(outcome[0] == true) { outcome.drop(1).joinToString("\n") }
            check(environment.delegate["QueueBindingCompilerTrustPassed"] == true)
        } finally {
            zombie.core.Core.debug = false
        }
    }

    private data class Decode(val status: String, val redump: ByteArray? = null)

    private fun dumped(prototype: Prototype): ByteArray =
        ByteArrayOutputStream().also(prototype::dump).toByteArray()

    private fun decode(bytes: ByteArray, environment: KahluaTable): Decode {
        val loaded =
            try {
                Prototype.loadByteCode(ByteArrayInputStream(bytes), environment)
            } catch (error: Exception) {
                return Decode(error.javaClass.name + ":" + error.message)
            }
        check(
            nodes(loaded.prototype).none { prototype ->
                prototype.constants.any { it is JavaFunction }
            },
        )
        val unknown = ByteArrayOutputStream()
        check(!QueueBindingCompiler.dumpOriginal(loaded.prototype, unknown) && unknown.size() == 0)
        return Decode("success", dumped(loaded.prototype))
    }

    private fun ephemeral(
        platform: J2SEPlatform,
        text: String,
        path: String,
    ): List<WeakReference<Any>> {
        val environment = platform.newEnvironment()
        val closure = QueueBindingCompiler.compile(text, path, environment, true)
        check(nativeConstants(closure) > 0)
        return listOf(
            WeakReference(environment as Any),
            WeakReference(closure.prototype as Any),
            WeakReference(closure.prototype.prototypes.first() as Any),
        )
    }

    private fun serializationChecks(root: Path) {
        val platform = J2SEPlatform()
        val environment = platform.newEnvironment()
        var total = 0
        var failures = 0
        var successes = 0
        for (file in listOf("ActionQueueCompat.lua", "ActionQueueCarts.lua")) {
            val path = root.resolve(SOURCE_DIRECTORY + file)
            val text = Files.readString(path)
            val baseline = LuaCompiler.loadstring(text, path.toString(), environment)
            val candidate = QueueBindingCompiler.compile(text, path.toString(), environment, true)
            check(nativeConstants(candidate) > 0)
            val originals = nodes(baseline.prototype)
            val modified = nodes(candidate.prototype)
            check(originals.size == modified.size)
            val before = modified.map {
                Triple(it.code.copyOf(), it.constants.copyOf(), it.prototypes.copyOf())
            }
            for (index in modified.indices) {
                val expected = dumped(originals[index])
                val output = ByteArrayOutputStream()
                check(QueueBindingCompiler.dumpOriginal(modified[index], output)) {
                    "Missing nested dump mapping: $file:$index"
                }
                val actual = output.toByteArray()
                check(actual.contentEquals(expected)) {
                    "Original dump bytes changed: $file:$index"
                }
                val old = decode(expected, environment)
                val current = decode(actual, environment)
                check(old.status == current.status) {
                    "Native reload outcome changed: $file:$index"
                }
                if (old.status == "success") {
                    successes++
                    check(old.redump!!.contentEquals(current.redump!!))
                    check(old.redump.contentEquals(expected))
                } else failures++
                total++
            }
            for (index in modified.indices) {
                val (code, constants, children) = before[index]
                val node = modified[index]
                check(
                    node.code.contentEquals(code) &&
                        node.constants.indices.all { node.constants[it] === constants[it] } &&
                        node.prototypes.indices.all { node.prototypes[it] === children[it] },
                ) {
                    "Dump mutated the live tree: $file:$index"
                }
            }
            check(nativeConstants(candidate) > 0)
            val unknown = ByteArrayOutputStream()
            check(
                !QueueBindingCompiler.dumpOriginal(baseline.prototype, unknown) &&
                    unknown.size() == 0,
            )
            println("QUEUE_BINDING_SERIALIZATION_SOURCE_PASS $file nodes=${modified.size}")
        }
        // Preserve the native null-name limitation rather than normalize live or
        // original trees merely to make a stronger round-trip assertion pass.
        val simple =
            LuaCompiler.loadstring("return 17", "plain-serialization-control", environment)
                .prototype
        val simpleBytes = dumped(simple)
        check(decode(simpleBytes, environment).redump!!.contentEquals(simpleBytes))
        val nested =
            LuaCompiler.loadstring(
                    "return function() return 17 end",
                    "nested-serialization-control",
                    environment,
                )
                .prototype
        println("QUEUE_BINDING_NATIVE_NESTED_RELOAD ${decode(dumped(nested), environment).status}")
        val path = root.resolve(SOURCE_DIRECTORY + "ActionQueueCompat.lua")
        val weak = ephemeral(platform, Files.readString(path), path.toString())
        for (attempt in 0 until 30) {
            if (weak.all { it.get() == null }) break
            System.gc()
            Thread.sleep(10)
        }
        check(weak.all { it.get() == null }) {
            "Serialization mappings retained a modified prototype or its environment"
        }
        println(
            "QUEUE_BINDING_SERIALIZATION_PASS nodes=$total successfulReloads=$successes nativeBaselineErrors=$failures weakGc=true",
        )
    }

    @JvmStatic
    fun main(args: Array<String>) {
        val root = Path.of(System.getProperty("pz.test.project"))
        val compat = Files.readString(root.resolve(SOURCE_DIRECTORY + "ActionQueueCompat.lua"))
        val carts = Files.readString(root.resolve(SOURCE_DIRECTORY + "ActionQueueCarts.lua"))
        trustChecks(root, compat, carts)
        serializationChecks(root)
        println(
            "QUEUE_BINDING_COMPILER_CHECKS_PASS (native source gates, caller provenance, Lua fallbacks and dump parity)",
        )
        kotlin.system.exitProcess(0)
    }
}
