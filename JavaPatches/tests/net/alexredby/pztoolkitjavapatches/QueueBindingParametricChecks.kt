package net.alexredby.pztoolkitjavapatches

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

/** Native table lookup and complete lifecycle-loop fallbacks; no shipping test API. */
object QueueBindingParametricChecks {
    private fun nodes(prototype: Prototype): List<Prototype> =
        listOf(prototype) + prototype.prototypes.flatMap(::nodes)

    private fun constants(closure: LuaClosure): Int =
        nodes(closure.prototype).sumOf { p -> p.constants.count { it is JavaFunction } }

    private fun filename(prototype: Prototype, path: String) {
        prototype.filename = path
        prototype.prototypes.forEach { filename(it, path) }
    }

    private fun section(text: String, start: String, end: String): String {
        val first = text.indexOf(start)
        check(first >= 0) { "Missing fixture start: $start" }
        val last = text.indexOf(end, first)
        check(last >= 0) { "Missing fixture end: $end" }
        return text.substring(first, last)
    }

    // Explicit test privilege; arbitrary input is not a production compiler API.
    private fun bindSynthetic(text: String, path: String, environment: KahluaTable): LuaClosure? {
        val type = QueueBindingCompiler::class.java
        val selected =
            type.declaredMethods
                .single { it.name == "sites" && it.parameterCount == 1 }
                .apply { isAccessible = true }
                .invoke(QueueBindingCompiler, path)
        return type.declaredMethods
            .single { it.name == "bind" && it.parameterCount == 4 }
            .apply { isAccessible = true }
            .invoke(QueueBindingCompiler, text, path, environment, selected) as LuaClosure?
    }

    private class Observations {
        private data class Counts(var visits: Long = 0, var hits: Long = 0, var captures: Long = 0)

        private val counts = mutableMapOf<String, Counts>()
        private val lifecycleKeys = setOf("ClassLifecycle", "NativeLifecycle")
        val visits: Long
            get() = counts.values.sumOf { it.visits }

        val captures: Long
            get() = counts.values.sumOf { it.captures }

        val hits: Long
            get() = counts.filterKeys { it !in lifecycleKeys }.values.sumOf { it.hits }

        val lifecycleHits: Long
            get() = counts.filterKeys { it in lifecycleKeys }.values.sumOf { it.hits }

        fun observe(closure: LuaClosure) {
            for (prototype in nodes(closure.prototype)) for (index in prototype.constants.indices) {
                val factory = prototype.constants[index] as? JavaFunction ?: continue
                // Inspect only the factory's compiler-owned Site. Store its string
                // label and counters, never owner/map arguments or a VM environment.
                val site =
                    factory.javaClass.declaredFields
                        .map {
                            it.isAccessible = true
                            it.get(factory)
                        }
                        .single { it?.javaClass?.simpleName == "Site" }!!
                val key =
                    site.javaClass
                        .getDeclaredMethod("getKey")
                        .apply { isAccessible = true }
                        .invoke(site) as String
                check(
                    key in
                        setOf(
                            "BC",
                            "Fridge",
                            "Carts",
                            "Class",
                            "Radio",
                            "NativeHelpers",
                            "ClassLifecycle",
                            "NativeLifecycle",
                        ),
                )
                val observation = counts.getOrPut(key) { Counts() }
                prototype.constants[index] = JavaFunction { frame, count ->
                    observation.captures++
                    val result = factory.call(frame, count)
                    check(result == 1)
                    val slot = frame.top - 1
                    val checker = frame.get(slot) as JavaFunction
                    frame.set(
                        slot,
                        JavaFunction { current, arguments ->
                            observation.visits++
                            // Direct call retains the same native frame and actual Lua
                            // caller: instrumentation must not create another C boundary.
                            val returned = checker.call(current, arguments)
                            check(returned == 1)
                            if (current.get(current.top - 1) == true) observation.hits++
                            returned
                        },
                    )
                    result
                }
            }
        }
    }

    private fun weakArguments(
        environment: KahluaTable,
        thread: KahluaThread,
    ): List<WeakReference<Any>> {
        val code =
            "RetainedParamGuard=ParamClassFactory({});local owner,expected={},{};local f=function()end;owner.helper=f;expected.helper=f;assert(RetainedParamGuard(owner,expected));return {owner,expected}"
        val result =
            thread.call(
                LuaCompiler.loadstring(code, "argument-gc", environment),
                emptyArray<Any?>(),
            ) as KahluaTableImpl
        return listOf(WeakReference(result.delegate[1.0]!!), WeakReference(result.delegate[2.0]!!))
    }

    @JvmStatic
    fun main(args: Array<String>) {
        val root = Path.of(System.getProperty("pz.test.project"))
        val platform = J2SEPlatform()
        val env = platform.newEnvironment() as KahluaTableImpl
        val thread = KahluaThread(platform, env).apply { debugOwnerThread = Thread.currentThread() }
        zombie.Lua.LuaManager.env = env
        val observations = Observations()
        val sources =
            listOf(
                    "ActionQueueCompat.lua" to 4,
                    "ActionQueueCarts.lua" to 1,
                    "ActionQueuePolicy.lua" to 3,
                )
                .associate { (file, count) ->
                    file to
                        (Files.readString(
                            root.resolve(
                                "PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/$file",
                            ),
                        ) to count)
                }
        for ((path, source) in sources) {
            val (text, expected) = source
            check(constants(QueueBindingCompiler.compile(text, path, env, true)) == expected)
            check(constants(QueueBindingCompiler.compile(text, path, env, false)) == 0)
            check(
                constants(QueueBindingCompiler.compile(text + "\n-- changed", path, env, true)) ==
                    0,
            )
            check(constants(QueueBindingCompiler.compile(text, "Foreign.lua", env, true)) == 0)
        }
        val compat = sources.getValue("ActionQueueCompat.lua").first
        val policy = sources.getValue("ActionQueuePolicy.lua").first
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
        val classGuard =
            section(compat, "local function classUnchanged(class, methods)\n", "\n-- BulkActions")
        val classFixture =
            "local lifecycle=...\nlocal containerHelpersUnchanged\n$bc\n$fridge\n$classGuard\nreturn classUnchanged"
        val callbacks =
            section(
                policy,
                "local function callbacksSafe(action)\n",
                "\nlocal function nativeMatches(",
            )
        val matches =
            section(
                policy,
                "local function nativeMatches(action, snapshot, observingCleanup)\n",
                "\n-- Reuse the installed",
            )
        val radio =
            section(
                policy,
                "local function radioResources(action, projectionIndependent)\n",
                "\nlocal function dryItem(",
            )
        val policyFixture =
            "local radioModes,radioMethods,lifecycle,resources,EditAdapters,Toolkit,ISInventoryTransferAction,transferFloorHelper,instanceof,transferHelpersMatch,ordinaryTransfer=...\n$callbacks\n$matches\n$radio\nreturn radioResources,nativeMatches"
        fun fixture(text: String, path: String, enabled: Boolean): LuaClosure {
            val c =
                if (enabled)
                    checkNotNull(bindSynthetic(text, path, env)).also(observations::observe)
                else LuaCompiler.loadstring(text, path, env)
            check(constants(c) == if (enabled) if (path == "ActionQueueCompat.lua") 4 else 3 else 0)
            filename(c.prototype, path)
            return c
        }
        env.rawset("OriginalClassFactory", fixture(classFixture, "ActionQueueCompat.lua", false))
        env.rawset("ParamClassFactory", fixture(classFixture, "ActionQueueCompat.lua", true))
        env.rawset("OriginalPolicyFactory", fixture(policyFixture, "ActionQueuePolicy.lua", false))
        env.rawset("ParamPolicyFactory", fixture(policyFixture, "ActionQueuePolicy.lua", true))
        val meta = platform.newTable()
        KahluaUtil.getClassMetatables(platform, env).rawset(LuaClosure::class.java, meta)
        env.rawset("FunctionMeta", meta)
        env.rawset(
            "Hits",
            JavaFunction { f, _ ->
                f.push((observations.hits).toDouble())
                1
            },
        )
        env.rawset(
            "LifeHits",
            JavaFunction { f, _ ->
                f.push(observations.lifecycleHits.toDouble())
                1
            },
        )
        env.rawset(
            "Visits",
            JavaFunction { f, _ ->
                f.push(observations.visits.toDouble())
                1
            },
        )
        env.rawset(
            "Captures",
            JavaFunction { f, _ ->
                f.push(observations.captures.toDouble())
                1
            },
        )
        env.rawset(
            "Emit",
            JavaFunction { f, _ ->
                println(f.get(0))
                0
            },
        )
        env.rawset(
            "Clock",
            JavaFunction { f, _ ->
                f.push(System.nanoTime().toDouble())
                1
            },
        )
        env.rawset(
            "SetDebug",
            JavaFunction { f, _ ->
                zombie.core.Core.debug = f.get(0) == true
                0
            },
        )
        env.rawset(
            "CloneSamePrototype",
            JavaFunction { f, _ ->
                val original = f.get(0) as LuaClosure
                val copy = LuaClosure(original.prototype, original.env)
                for (i in copy.upvalues.indices) copy.upvalues[i] = original.upvalues[i]
                f.push(copy)
                1
            },
        )
        env.rawset("ForeignTable", KahluaTableImpl(java.util.HashMap()))
        val rewritten = platform.newTable() as KahluaTableImpl
        rewritten.setRewriteTable(platform.newTable())
        env.rawset("Rewritten", rewritten)
        env.rawset("UnknownOwner", Any())
        // valueOf(false) would return the canonical singleton and miss the native
        // boolEval reference-identity edge this fixture deliberately exercises.
        @Suppress("DEPRECATION", "PLATFORM_CLASS_MAPPED_TO_KOTLIN")
        val nonCanonicalFalse = java.lang.Boolean(false)
        env.rawset("NonCanonicalFalse", nonCanonicalFalse)
        env.rawset("FloatNaN", java.lang.Float.valueOf(Float.NaN))
        val lookup =
            QueueBindingCompiler::class
                .java
                .getDeclaredMethod("tableGetPure", Any::class.java, String::class.java)
                .apply { isAccessible = true }
        val unsupported =
            QueueBindingCompiler::class
                .java
                .getDeclaredField("unsupported")
                .apply { isAccessible = true }
                .get(QueueBindingCompiler)
        env.rawset(
            "ProbePureLookup",
            JavaFunction { f, _ ->
                val result = lookup.invoke(QueueBindingCompiler, f.get(0), f.get(1) as String)
                f.push(result !== unsupported)
                f.push(if (result === unsupported) null else result)
                2
            },
        )
        val probe =
            LuaCompiler.loadstring(
                Files.readString(
                    root.resolve(
                        "JavaPatches/tests/net/alexredby/pztoolkitjavapatches/QueueBindingParametricChecks.lua",
                    ),
                ),
                "parametric-probe",
                env,
            )
        filename(probe.prototype, "parametric-probe")
        try {
            val result = thread.pcall(probe, emptyArray<Any?>())
            check(result[0] == true) { result.drop(1).joinToString("\n") }
            check(env.delegate["QueueBindingParametricChecksPassed"] == true)
        } finally {
            zombie.core.Core.debug = false
        }

        val weak = weakArguments(env, thread)
        check(env.delegate["RetainedParamGuard"] is LuaClosure)
        for (attempt in 0 until 30) {
            if (weak.all { it.get() == null }) break
            System.gc()
            Thread.sleep(10)
        }
        check(weak.all { it.get() == null }) {
            "Retained checker kept its owner or expected-map arguments"
        }
        check(env.delegate["RetainedParamGuard"] is LuaClosure)
        println(
            "QUEUE_BINDING_PARAMETRIC_CHECKS_PASS (42 causal cases, module gates and retained-checker argument GC)",
        )
        kotlin.system.exitProcess(0)
    }
}
