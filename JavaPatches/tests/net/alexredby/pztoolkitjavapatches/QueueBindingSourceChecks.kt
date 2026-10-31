package net.alexredby.pztoolkitjavapatches

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.Reader
import java.io.StringReader
import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.atomic.AtomicReference
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.LuaClosure
import se.krka.kahlua.vm.Prototype
import zombie.ZomboidFileSystem
import zombie.gameStates.ChooseGameInfo

object QueueBindingSourceChecks {
    private var assertions = 0
    private const val SOURCE_LIMIT = 1024 * 1024

    private fun <T> withRunLua(file: String?, supported: Boolean, action: () -> T): T {
        val previous = QueueBindingSource.begin(file, supported)
        try {
            return action()
        } finally {
            QueueBindingSource.end(previous)
        }
    }

    private fun verify(value: Boolean, message: String) {
        assertions++
        check(value) { message }
    }

    private class OwnedReader(private val text: String, private val zeros: Boolean = false) :
        Reader() {
        var position = 0
        var closes = 0
        var zeroNext = zeros

        override fun read(buffer: CharArray, offset: Int, length: Int): Int {
            if (length == 0) return 0
            if (zeroNext) {
                zeroNext = false
                return 0
            }
            if (position == text.length) return -1
            val count = minOf(length, text.length - position)
            text.toCharArray(buffer, offset, position, position + count)
            position += count
            zeroNext = zeros
            return count
        }

        override fun read(): Int = if (position == text.length) -1 else text[position++].code

        override fun close() {
            closes++
        }
    }

    private val bomb =
        object : Reader() {
            override fun read(b: CharArray, o: Int, n: Int): Int = error("unowned reader consumed")

            override fun close() = error("unowned reader closed")
        }

    private fun scope(): Any? {
        val field = QueueBindingSource::class.java.getDeclaredField("loading")
        field.isAccessible = true
        return (field.get(null) as ThreadLocal<*>).get()
    }

    private fun factoryCount(p: Prototype): Int =
        p.constants.count { it is JavaFunction } + p.prototypes.sumOf { factoryCount(it) }

    private fun expectedFactoryCount(module: QueueBindingSource.Module): Int =
        when (module) {
            QueueBindingSource.Module.COMPAT -> 4
            QueueBindingSource.Module.CARTS -> 1
            QueueBindingSource.Module.POLICY -> 3
        }

    private fun dump(c: LuaClosure): ByteArray =
        ByteArrayOutputStream().also { c.prototype.dump(it) }.toByteArray()

    private fun unowned(
        file: String?,
        name: String?,
        nativeSupported: Boolean = true,
        compilerSupported: Boolean = true,
    ) {
        withRunLua(file, nativeSupported) {
            val p = QueueBindingSource.prepare(bomb, name, compilerSupported)
            verify(
                p.reader === bomb && p.text == null && p.module == null,
                "unexpected claim $file / $name",
            )
        }
        verify(scope() == null, "scope leaked")
    }

    private class DelayedFailureStream(private val source: String) : java.io.InputStream() {
        val failure = IOException("delayed fixture IO")
        var position = 0
        var failures = 0
        var closes = 0

        private fun failIfReached() {
            if (position >= 8192 && failures == 0) {
                failures++
                throw failure
            }
        }

        override fun read(): Int {
            failIfReached()
            return if (position == source.length) -1 else source[position++].code
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            if (length == 0) return 0
            failIfReached()
            if (position == source.length) return -1
            val count =
                minOf(
                    length,
                    source.length - position,
                    if (failures == 0) 8192 - position else Int.MAX_VALUE,
                )
            for (index in 0 until count) buffer[offset + index] = source[position++].code.toByte()
            return count
        }

        override fun close() {
            closes++
        }
    }

    private data class CompilerObservation(
        val closure: LuaClosure?,
        val failure: Throwable?,
        val ioDiagnostic: Boolean,
    )

    private fun readerFailureChecks(env: se.krka.kahlua.vm.KahluaTable) {
        val module = QueueBindingSource.Module.COMPAT
        fun observe(source: String, scoped: Boolean): CompilerObservation {
            val stream = DelayedFailureStream(source)
            val diagnostics = ByteArrayOutputStream()
            val previousError = System.err
            var closure: LuaClosure? = null
            var failure: Throwable? = null
            System.setErr(java.io.PrintStream(diagnostics))
            try {
                java.io.BufferedReader(java.io.InputStreamReader(stream, Charsets.US_ASCII)).use {
                    reader ->
                    closure =
                        if (scoped) {
                            withRunLua(module.target, true) {
                                LuaCompiler.loadis(reader, module.compilerName, env)
                            }
                        } else LuaCompiler.loadis(reader, module.compilerName, env)
                }
            } catch (observed: IOException) {
                failure = observed
            } catch (observed: RuntimeException) {
                failure = observed
            } finally {
                System.setErr(previousError)
            }
            verify(stream.closes == 1, "delayed-error original stream close count")
            verify(scope() == null, "delayed-error native compiler scope leaked")
            val ioDiagnostic =
                diagnostics.toString().contains("java.io.IOException: delayed fixture IO")
            return CompilerObservation(closure, failure, ioDiagnostic)
        }
        for (prefix in listOf("return ]", "return 1")) {
            val source = prefix + " ".repeat(20000) + "\n"
            val ordinary = observe(source, false)
            val owned = observe(source, true)
            verify(
                ordinary.failure?.javaClass == owned.failure?.javaClass &&
                    ordinary.failure?.message == owned.failure?.message,
                "capture changed native syntax/IO failure order",
            )
            verify(
                (ordinary.closure == null) == (owned.closure == null),
                "capture changed native compilation outcome after IO",
            )
            verify(
                ordinary.ioDiagnostic == owned.ioDiagnostic,
                "capture changed native IO diagnostic reachability",
            )
            if (prefix == "return ]") {
                verify(
                    ordinary.failure is se.krka.kahlua.vm.KahluaException && !ordinary.ioDiagnostic,
                    "malformed prefix did not fail before delayed IO",
                )
            } else {
                // This native lexer logs IOException and treats it as EOF; preserve that behavior.
                verify(
                    ordinary.closure != null && ordinary.ioDiagnostic,
                    "valid prefix did not reach native IO-as-EOF handling",
                )
                verify(
                    dump(ordinary.closure!!).contentEquals(dump(owned.closure!!)),
                    "valid prefix native prototype changed after IO",
                )
            }
        }
        val source = "return 1" + " ".repeat(20000) + "\n-- unread tail\n"
        val stream = DelayedFailureStream(source)
        java.io.BufferedReader(java.io.InputStreamReader(stream, Charsets.US_ASCII)).use { original
            ->
            withRunLua(module.target, true) {
                val prepared = QueueBindingSource.prepare(original, module.compilerName, true)
                verify(
                    prepared.text == null && prepared.module == module,
                    "incomplete capture authorized compilation",
                )
                verify(
                    prepared.reader.read(CharArray(0), 0, 0) == 0,
                    "pending failure consumed by zero-length read",
                )
                val prefix = CharArray(8192)
                verify(
                    prepared.reader.read(prefix, 0, prefix.size) == prefix.size &&
                        String(prefix) == source.substring(0, prefix.size),
                    "failed capture lost prefix",
                )
                verify(
                    prepared.reader.read(CharArray(0), 0, 0) == 0,
                    "pending failure consumed at prefix boundary",
                )
                var observed: IOException? = null
                try {
                    prepared.reader.read()
                } catch (failure: IOException) {
                    observed = failure
                }
                verify(observed === stream.failure, "pending IO failure was not replayed intact")
                verify(
                    prepared.reader.read(CharArray(0), 0, 0) == 0,
                    "zero-length retry touched tail",
                )
                verify(
                    prepared.reader.readText() == source.substring(prefix.size),
                    "pending failure was repeated or tail retry lost text",
                )
                verify(stream.failures == 1, "tail retry repeated captured failure")
                prepared.reader.close()
                verify(stream.closes == 0, "error replay closed borrowed original")
                verify(
                    QueueBindingSource.prepare(bomb, module.compilerName, true).reader === bomb,
                    "incomplete capture allowed repeated claim",
                )
            }
        }
        verify(stream.closes == 1 && scope() == null, "error replay original owner/TLS cleanup")
        println(
            "QUEUE_BINDING_READER_ERROR_ORDER_PASS (native syntax before IO, reachable IO-as-EOF, pending failure once, tail retry, close once)",
        )
    }

    private fun wovenChecks(
        files: ZomboidFileSystem,
        version: Path,
        texts: Map<QueueBindingSource.Module, String>,
        platform: J2SEPlatform,
        env: se.krka.kahlua.vm.KahluaTable,
    ) {
        verify(
            QueueBindingHooks.SUPPORTED,
            "installed native loader/compiler/VM bytecode unsupported",
        )
        zombie.Lua.LuaManager.platform = platform
        zombie.Lua.LuaManager.env = env
        zombie.Lua.LuaManager.thread =
            se.krka.kahlua.vm.KahluaThread(platform, env).also {
                it.debugOwnerThread = Thread.currentThread()
            }
        zombie.Lua.LuaManager.caller =
            se.krka.kahlua.integration.LuaCaller(se.krka.kahlua.converter.KahluaConverterManager())
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            QueueBindingSourceChecks::class.java.classLoader,
        )

        readerFailureChecks(env)
        fun nodes(p: Prototype): List<Prototype> = listOf(p) + p.prototypes.flatMap { nodes(it) }
        for ((module, text) in texts) {
            val ordinary = LuaCompiler.loadstring(text, module.compilerName, env)
            val originalReader = OwnedReader(text)
            originalReader.use {
                withRunLua(module.target, true) {
                    val closure = LuaCompiler.loadis(it, module.compilerName, env)
                    val expectedFactories = expectedFactoryCount(module)
                    verify(
                        factoryCount(closure.prototype) == expectedFactories,
                        "woven Reader advice did not publish native binding",
                    )
                    verify(originalReader.closes == 0, "woven compiler closed original Reader")
                    val serialized = dump(closure)
                    verify(
                        serialized.contentEquals(dump(ordinary)),
                        "woven native dump changed original bytecode",
                    )
                    // Preserve the native codec's baseline outcome, including its null-name EOF
                    // bug.
                    var baselineFailure: IOException? = null
                    var actualFailure: IOException? = null
                    val baselineReload =
                        try {
                            Prototype.loadByteCode(
                                java.io.ByteArrayInputStream(dump(ordinary)),
                                env,
                            )
                        } catch (failure: IOException) {
                            baselineFailure = failure
                            null
                        }
                    val reloaded =
                        try {
                            Prototype.loadByteCode(java.io.ByteArrayInputStream(serialized), env)
                        } catch (failure: IOException) {
                            actualFailure = failure
                            null
                        }
                    verify(
                        (baselineReload == null) == (reloaded == null) &&
                            baselineFailure?.javaClass == actualFailure?.javaClass &&
                            baselineFailure?.message == actualFailure?.message,
                        "woven dump changed native reload outcome",
                    )
                    if (reloaded != null) {
                        verify(
                            factoryCount(reloaded.prototype) == 0,
                            "serialized output retained native factories",
                        )
                    }
                    val boundNodes = nodes(closure.prototype)
                    val originalNodes = nodes(ordinary.prototype)
                    verify(boundNodes.size == originalNodes.size, "binding changed prototype tree")
                    for ((bound, baseline) in boundNodes.zip(originalNodes)) {
                        if (bound.constants.any { value -> value is JavaFunction }) {
                            val output = ByteArrayOutputStream()
                            bound.dump(output)
                            val expected = ByteArrayOutputStream()
                            baseline.dump(expected)
                            verify(
                                output.toByteArray().contentEquals(expected.toByteArray()),
                                "nested prototype dump retained native factory",
                            )
                        }
                    }
                    verify(
                        factoryCount(closure.prototype) == expectedFactories,
                        "dump changed live native binding",
                    )
                    verify(
                        QueueBindingSource.prepare(bomb, module.compilerName, true).reader === bomb,
                        "woven Reader advice left unclaimed scope",
                    )
                }
            }
            verify(originalReader.closes == 1, "woven compilation original owner close count")
            verify(scope() == null, "woven compiler source scope leaked")
        }
        val compat = QueueBindingSource.Module.COMPAT
        val carts = QueueBindingSource.Module.CARTS
        val policy = QueueBindingSource.Module.POLICY
        val policyPath = version.resolve(policy.target)
        val compatPath = version.resolve(compat.target)
        val cartsPath = version.resolve(carts.target)
        val innerName = "media/lua/client/queue-binding-source-inner.lua"
        val innerPath = version.resolve(innerName)
        Files.createDirectories(innerPath.parent)
        // Exercise an actual reviewed module through native RunLua before replacing fixture text.
        // The real Carts module deliberately returns immediately when SaucedCarts is absent.
        env.rawset("getActivatedMods", null)
        QueueBindingSourceFixture.watch(cartsPath.toString())
        val knownPath = cartsPath.toString()
        zombie.Lua.LuaManager.RunLua(knownPath, false)
        val registry = zombie.Lua.LuaManager::class.java.getDeclaredField("filenameToClosure")
        registry.isAccessible = true
        val published = (registry.get(null) as Map<*, *>)[knownPath] as? LuaClosure
        verify(
            published != null && factoryCount(published.prototype) == 1,
            "native RunLua did not publish exact Carts binding",
        )
        verify(
            factoryCount(
                LuaCompiler.loadis(StringReader(texts.getValue(carts)), carts.compilerName, env)
                    .prototype,
            ) == 0,
            "unscoped dynamic exact text acquired native binding",
        )
        val knownReader = QueueBindingSourceFixture.latest(knownPath)
        verify(
            knownReader != null && knownReader.closes == 1 && knownReader.reads > 0,
            "known native original Reader close count",
        )
        verify(scope() == null, "known native RunLua scope leaked")
        Files.writeString(innerPath, "return queueBindingInnerProbe()\n")
        Files.writeString(compatPath, "return queueBindingOuterProbe()\n")
        Files.writeString(cartsPath, "return queueBindingRewriteProbe()\n")
        Files.writeString(policyPath, "return queueBindingPolicyProbe()\n")
        files.activeFileMap[innerName] = innerPath.toString()
        for (path in listOf(compatPath, cartsPath, policyPath, innerPath)) QueueBindingSourceFixture
            .watch(
                path.toString(),
            )
        var innerCalls = 0
        var outerCalls = 0
        var rewriteCalls = 0
        var policyCalls = 0
        env.rawset(
            "queueBindingInnerProbe",
            JavaFunction { frame, _ ->
                innerCalls++
                val active = scope() as? QueueBindingSource.Scope
                verify(
                    active != null && active.module == null && !active.claimed,
                    "native nested unrelated scope inherited module",
                )
                verify(
                    QueueBindingSource.prepare(bomb, compat.compilerName, true).reader === bomb,
                    "native nested unrelated load claimed source",
                )
                val reader = QueueBindingSourceFixture.latest(innerPath.toString())
                verify(
                    reader != null && reader.closes == 1 && reader.reads > 0,
                    "native inner original Reader not closed once before execution",
                )
                frame.push(19.0)
                1
            },
        )
        env.rawset(
            "queueBindingOuterProbe",
            JavaFunction { frame, _ ->
                outerCalls++
                val active = scope() as? QueueBindingSource.Scope
                verify(
                    active != null && active.module == compat && active.claimed,
                    "native RunLua/Reader advice did not claim provider",
                )
                val reader = QueueBindingSourceFixture.latest(compatPath.toString())
                verify(
                    reader != null && reader.closes == 1 && reader.reads > 0,
                    "native original Reader not closed once before execution",
                )
                verify(
                    zombie.Lua.LuaManager.RunLua(innerName, false) == 19.0,
                    "native nested RunLua result",
                )
                verify(scope() === active, "native nested RunLua failed parent restoration")
                verify(
                    zombie.Lua.LuaManager.RunLua(innerName, false) == 19.0 && innerCalls == 1,
                    "native cached nested RunLua reread source",
                )
                verify(scope() === active, "native cached nested RunLua failed restoration")
                var failed = false
                try {
                    zombie.Lua.LuaManager.RunLua(null, false)
                } catch (_: NullPointerException) {
                    failed = true
                }
                verify(failed && scope() === active, "native throwing RunLua failed restoration")
                verify(
                    QueueBindingSource.prepare(bomb, compat.compilerName, true).reader === bomb,
                    "native callback reused claimed source",
                )
                frame.push(71.0)
                1
            },
        )
        env.rawset(
            "queueBindingPolicyProbe",
            JavaFunction { frame, _ ->
                policyCalls++
                val active = scope() as? QueueBindingSource.Scope
                verify(
                    active != null && active.module == policy && active.claimed,
                    "native Policy provider/Reader scope was not claimed",
                )
                val reader = QueueBindingSourceFixture.latest(policyPath.toString())
                verify(
                    reader != null && reader.closes == 1 && reader.reads > 0,
                    "native Policy original Reader not closed once before execution",
                )
                verify(
                    zombie.Lua.LuaManager.RunLua(innerName, false) == 19.0,
                    "native Policy nested RunLua result",
                )
                verify(scope() === active, "native Policy nested scope failed restoration")
                frame.push(97.0)
                1
            },
        )
        env.rawset(
            "queueBindingRewriteProbe",
            JavaFunction { frame, _ ->
                rewriteCalls++
                val active = scope() as? QueueBindingSource.Scope
                verify(
                    active != null && active.module == carts && active.claimed,
                    "native rewrite load did not claim own provider",
                )
                verify(LuaCompiler.rewriteEvents, "native rewrite flag not preserved")
                verify(
                    QueueBindingSourceFixture.latest(cartsPath.toString()).closes == 1,
                    "rewrite original Reader not closed once",
                )
                frame.push(83.0)
                1
            },
        )
        verify(
            zombie.Lua.LuaManager.RunLua(compat.target, false) == 71.0,
            "woven native RunLua result",
        )
        verify(scope() == null, "native RunLua scope leaked")
        val firstReader = QueueBindingSourceFixture.latest(compatPath.toString())
        verify(
            zombie.Lua.LuaManager.RunLua(compat.target, false) == 71.0 && outerCalls == 1,
            "native cached RunLua reran source",
        )
        verify(
            QueueBindingSourceFixture.latest(compatPath.toString()) === firstReader &&
                firstReader.closes == 1,
            "native cached RunLua reopened/closed source",
        )
        verify(scope() == null, "native cached RunLua scope leaked")
        verify(
            zombie.Lua.LuaManager.RunLua(carts.target, true) == 83.0 && rewriteCalls == 1,
            "native rewrite result",
        )
        verify(scope() == null, "native rewrite scope leaked")
        verify(
            zombie.Lua.LuaManager.RunLua(policy.target, false) == 97.0,
            "native Policy provider RunLua result",
        )
        val policyReader = QueueBindingSourceFixture.latest(policyPath.toString())
        verify(
            zombie.Lua.LuaManager.RunLua(policy.target, false) == 97.0 && policyCalls == 1,
            "native cached Policy RunLua reran source",
        )
        verify(
            QueueBindingSourceFixture.latest(policyPath.toString()) === policyReader &&
                policyReader.closes == 1,
            "native cached Policy RunLua reopened/closed original source",
        )
        val policyPublished =
            (registry.get(null) as Map<*, *>)[policyPath.toString()] as? LuaClosure
        verify(
            policyPublished != null && factoryCount(policyPublished.prototype) == 0,
            "native unknown Policy source acquired factory constants",
        )
        verify(scope() == null, "native Policy RunLua scope leaked")
        LuaCompiler.rewriteEvents = false
        // Fixture source files live only in the isolated native cache.
        for ((module, text) in texts) Files.writeString(version.resolve(module.target), text)
        println(
            "QUEUE_BINDING_SOURCE_WOVEN_PASS (native RunLua, Reader advice, baseline dump/reload parity, nested/cached/rewrite/throwable cleanup, original Reader closed once)",
        )
    }

    @JvmStatic
    fun main(args: Array<String>) {
        val root = Path.of(System.getProperty("pz.test.project"))
        val work = Path.of(System.getProperty("pz.test.cache"))
        val files = ZomboidFileSystem.instance
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        files.setCacheDir(work.resolve("cache").toString())
        files.init()
        val mod = work.resolve("cache/mods/PZSurvivorToolkit")
        val version = mod.resolve("42")
        Files.createDirectories(mod.resolve("common"))
        Files.createDirectories(version)
        Files.writeString(mod.resolve("common/mod.info"), "id=PZSurvivorToolkit\n")
        Files.writeString(version.resolve("mod.info"), "id=PZSurvivorToolkit\nmodversion=fixture\n")
        val texts =
            QueueBindingSource.Module.entries.associateWith {
                val source =
                    Files.readString(root.resolve("PZSurvivorToolkit/42").resolve(it.target))
                val target = version.resolve(it.target)
                Files.createDirectories(target.parent)
                Files.writeString(target, source)
                files.activeFileMap[it.target.lowercase(java.util.Locale.ENGLISH)] =
                    target.toString()
                source
            }
        files.setModIdToDir("PZSurvivorToolkit", mod.toString())
        files.modIDs.add("PZSurvivorToolkit")
        verify(
            Path.of(ChooseGameInfo.getModDetails("PZSurvivorToolkit").versionDir) == version,
            "native version directory",
        )
        val platform = J2SEPlatform()
        val env = platform.newEnvironment()
        val compat = QueueBindingSource.Module.COMPAT
        val carts = QueueBindingSource.Module.CARTS
        fun compiled(p: QueueBindingSource.Prepared, name: String): LuaClosure =
            if (p.text != null && p.module != null)
                QueueBindingCompiler.compile(p.text, p.module.compilerName, env, true)
            else LuaCompiler.loadis(p.reader, name, env)
        verify(
            QueueBindingSource.prepare(bomb, compat.compilerName, true).reader === bomb,
            "unscoped input claimed",
        )
        unowned(compat.target, compat.compilerName, false)
        unowned(compat.target, compat.compilerName, true, false)
        unowned(null, compat.compilerName)
        unowned("media/lua/client/Other/ActionQueueCompat.lua", compat.compilerName)
        unowned("media/lua/client/inner.lua", compat.compilerName)
        files.modIDs.remove("PZSurvivorToolkit")
        unowned(compat.target, compat.compilerName)
        files.modIDs.add("PZSurvivorToolkit")
        val key = compat.target.lowercase(java.util.Locale.ENGLISH)
        val selected = files.activeFileMap.remove(key)!!
        unowned(compat.target, compat.compilerName)
        unowned(version.resolve(compat.target).toString(), compat.compilerName)
        files.activeFileMap[key] = selected
        val foreign = work.resolve("foreign/ActionQueueCompat.lua")
        Files.createDirectories(foreign.parent)
        Files.writeString(foreign, texts.getValue(compat))
        files.activeFileMap[key] = foreign.toString()
        unowned(compat.target, compat.compilerName)
        unowned(version.resolve(compat.target).toString(), compat.compilerName)
        files.activeFileMap[key] = selected
        val details = ChooseGameInfo.getModDetails("PZSurvivorToolkit")
        val chosenVersion = details.versionDir
        details.versionDir = null
        unowned(compat.target, compat.compilerName)
        details.versionDir = chosenVersion
        Files.move(Path.of(selected), Path.of(selected + ".hidden"))
        unowned(compat.target, compat.compilerName)
        Files.move(Path.of(selected + ".hidden"), Path.of(selected))
        files.ignoreActiveFileMap.set(true)
        unowned(compat.target, compat.compilerName)
        unowned(selected, compat.compilerName)
        files.ignoreActiveFileMap.set(false)
        // Native provider identity, not string equality (symlink is the same underlying file).
        val alias = work.resolve("alias/ActionQueueCompat.lua")
        Files.createDirectories(alias.parent)
        Files.deleteIfExists(alias)
        Files.createSymbolicLink(alias, Path.of(selected))
        files.activeFileMap[key] = alias.toString()
        withRunLua(compat.target, true) {
            verify(
                QueueBindingSource.prepare(
                        StringReader(texts.getValue(compat)),
                        compat.compilerName,
                        true,
                    )
                    .module == compat,
                "same-file alias rejected",
            )
        }
        files.activeFileMap[key] = selected
        // A changed native mapping between begin and compiler entry cannot borrow prior approval.
        withRunLua(compat.target, true) {
            files.activeFileMap[key] = foreign.toString()
            verify(
                QueueBindingSource.prepare(bomb, compat.compilerName, true).module == null,
                "stale provider approved",
            )
            files.activeFileMap[key] = selected
            verify(
                QueueBindingSource.prepare(bomb, compat.compilerName, true).module == null,
                "failed provider claim reused",
            )
        }
        for (module in QueueBindingSource.Module.entries) {
            val moduleKey = module.target.lowercase(java.util.Locale.ENGLISH)
            val activeProvider = files.activeFileMap.remove(moduleKey)!!
            unowned(module.target, module.compilerName)
            unowned(version.resolve(module.target).toString(), module.compilerName)
            val foreignProvider = work.resolve("foreign-provider").resolve(module.compilerName)
            Files.createDirectories(foreignProvider.parent)
            Files.writeString(foreignProvider, texts.getValue(module))
            files.activeFileMap[moduleKey] = foreignProvider.toString()
            unowned(module.target, module.compilerName)
            unowned(version.resolve(module.target).toString(), module.compilerName)
            files.activeFileMap[moduleKey] = activeProvider
            files.modIDs.remove("PZSurvivorToolkit")
            unowned(module.target, module.compilerName)
            files.modIDs.add("PZSurvivorToolkit")
            unowned(module.target, module.compilerName, false)
            unowned("media/lua/client/Other/" + module.compilerName, module.compilerName)
            for (runFile in
                listOf(
                    module.target,
                    version.resolve(module.target).toString(),
                    module.target.replace('/', '\\'),
                )) {
                withRunLua(runFile, true) {
                    verify(
                        QueueBindingSource.prepare(bomb, "Wrong.lua", true).reader === bomb,
                        "wrong compiler name claimed",
                    )
                    verify(
                        QueueBindingSource.prepare(bomb, module.compilerName, false).reader ===
                            bomb,
                        "unsupported compiler claimed",
                    )
                    for (other in QueueBindingSource.Module.entries.filter { it != module }) {
                        verify(
                            QueueBindingSource.prepare(bomb, other.compilerName, true).reader ===
                                bomb,
                            "different module compiler name borrowed scope",
                        )
                    }
                    val text = texts.getValue(module)
                    val reader = OwnedReader(text)
                    reader.use {
                        val p = QueueBindingSource.prepare(reader, module.compilerName, true)
                        verify(p.module == module && p.text == text, "known capture incomplete")
                        verify(
                            factoryCount(compiled(p, module.compilerName).prototype) ==
                                expectedFactoryCount(module),
                            "exact compiler binding",
                        )
                        p.reader.close()
                        verify(reader.closes == 0, "prepared close stole original reader")
                        verify(
                            QueueBindingSource.prepare(bomb, module.compilerName, true).reader ===
                                bomb,
                            "claim reused",
                        )
                    }
                    verify(reader.closes == 1, "native-style owner close count")
                }
            }
            val unknown = texts.getValue(module) + "\n-- unknown complete source\n"
            withRunLua(module.target, true) {
                val p = QueueBindingSource.prepare(StringReader(unknown), module.compilerName, true)
                verify(
                    p.text == unknown && p.reader.readText() == unknown,
                    "unknown complete source replay changed",
                )
                val actual = compiled(p, module.compilerName)
                verify(factoryCount(actual.prototype) == 0, "unknown complete source rewritten")
                verify(
                    dump(actual)
                        .contentEquals(
                            dump(LuaCompiler.loadstring(unknown, module.compilerName, env)),
                        ),
                    "unknown native prototype changed",
                )
            }
        }
        for (length in listOf(0, 17, SOURCE_LIMIT, SOURCE_LIMIT + 1, SOURCE_LIMIT + 37)) {
            for (zeros in listOf(false, true)) {
                val source = "x".repeat(length)
                val reader = OwnedReader(source, zeros)
                reader.use {
                    withRunLua(compat.target, true) {
                        val p = QueueBindingSource.prepare(reader, compat.compilerName, true)
                        verify(p.module == compat, "capture lost module")
                        verify((p.text != null) == (length <= SOURCE_LIMIT), "capture bound")
                        if (p.text == null)
                            verify(
                                reader.position == SOURCE_LIMIT + 1,
                                "oversized reader read too far",
                            )
                        verify(
                            p.reader.read(CharArray(0), 0, 0) == 0,
                            "zero length Reader contract",
                        )
                        verify(
                            p.reader.readText() == source,
                            "zero-read/boundary prefix-tail text loss",
                        )
                        p.reader.close()
                        verify(reader.closes == 0, "capture closed original")
                    }
                }
                verify(reader.closes == 1, "original not closed once")
            }
        }
        val oversizedLua = "return 9\n--" + "x".repeat(SOURCE_LIMIT)
        val oversizedReader = OwnedReader(oversizedLua, true)
        oversizedReader.use {
            withRunLua(compat.target, true) {
                val p = QueueBindingSource.prepare(it, compat.compilerName, true)
                val actual = compiled(p, compat.compilerName)
                verify(
                    p.text == null && factoryCount(actual.prototype) == 0,
                    "oversized compiled with authorization",
                )
                verify(
                    dump(actual)
                        .contentEquals(
                            dump(LuaCompiler.loadstring(oversizedLua, compat.compilerName, env)),
                        ),
                    "oversized native compile changed",
                )
                p.reader.close()
                verify(oversizedReader.closes == 0, "oversized compiler stole close")
            }
        }
        verify(oversizedReader.closes == 1, "oversized native-style close count")
        withRunLua(compat.target, true) {
            val unicode = "return 'é \uD83D\uDE00'\r\n"
            val p =
                QueueBindingSource.prepare(OwnedReader(unicode, true), compat.compilerName, true)
            verify(
                p.text == unicode && p.reader.readText() == unicode,
                "UTF16/CRLF capture changed",
            )
        }
        withRunLua(compat.target, true) {
            val outer = scope()
            withRunLua("media/lua/client/unrelated.lua", true) {
                verify(scope() !== outer, "nested unrelated scope not isolated")
                verify(
                    QueueBindingSource.prepare(bomb, compat.compilerName, true).reader === bomb,
                    "nested unrelated inherited approval",
                )
            }
            verify(scope() === outer, "nested unrelated restoration")
            withRunLua(carts.target, true) {
                verify(
                    QueueBindingSource.prepare(bomb, compat.compilerName, true).reader === bomb,
                    "nested module claimed outer name",
                )
                verify(
                    QueueBindingSource.prepare(StringReader("return 1"), carts.compilerName, true)
                        .module == carts,
                    "nested own module claim",
                )
            }
            verify(scope() === outer, "nested matching restoration")
            val failure = IOException("fixture read failure")
            var closes = 0
            val broken =
                object : Reader() {
                    var first = true

                    override fun read(b: CharArray, o: Int, n: Int): Int {
                        if (!first) throw failure
                        first = false
                        "retu".toCharArray(b, o, 0, 4)
                        return 4
                    }

                    override fun close() {
                        closes++
                    }
                }
            try {
                withRunLua(carts.target, true) {
                    broken.use {
                        try {
                            val prepared = QueueBindingSource.prepare(it, carts.compilerName, true)
                            verify(
                                prepared.text == null,
                                "failed capture published complete source",
                            )
                            prepared.reader.readText()
                        } catch (observed: IOException) {
                            verify(
                                QueueBindingSource.prepare(bomb, carts.compilerName, true).module ==
                                    null,
                                "failed read claim reused",
                            )
                            throw observed
                        }
                    }
                }
                error("read failure swallowed")
            } catch (observed: IOException) {
                verify(observed === failure, "read failure replaced")
            }
            verify(closes == 1 && scope() === outer, "read failure close/restoration")
            var compilationFailed = false
            val invalid = OwnedReader("local = invalid")
            try {
                withRunLua(carts.target, true) {
                    invalid.use {
                        val p = QueueBindingSource.prepare(it, carts.compilerName, true)
                        try {
                            compiled(p, carts.compilerName)
                        } finally {
                            verify(invalid.closes == 0, "compiler closed original")
                        }
                    }
                }
            } catch (_: RuntimeException) {
                compilationFailed = true
            }
            verify(
                compilationFailed && invalid.closes == 1,
                "compiler failure/owner close not observed",
            )
            verify(scope() === outer, "compiler failure restoration")
            val observed = AtomicReference<Throwable?>()
            val child = Thread {
                try {
                    verify(
                        QueueBindingSource.prepare(bomb, compat.compilerName, true).reader === bomb,
                        "scope crossed threads",
                    )
                } catch (failure: Throwable) {
                    observed.set(failure)
                }
            }
            child.start()
            child.join()
            observed.get()?.let { throw it }
            verify(
                QueueBindingSource.prepare(StringReader("return 7"), compat.compilerName, true)
                    .module == compat,
                "outer claim not restored",
            )
            withRunLua("unrelated", true) {}
            verify(
                QueueBindingSource.prepare(bomb, compat.compilerName, true).reader === bomb,
                "nested exit reset claimed outer",
            )
        }
        verify(scope() == null, "final TLS leak")
        verify(
            QueueBindingSource.Scope::class.java.declaredFields.none {
                Reader::class.java.isAssignableFrom(it.type) ||
                    it.name.contains("text", true) ||
                    it.name.contains("source", true)
            },
            "scope stores reader/source",
        )
        wovenChecks(files, version, texts, platform, env)
        println(
            "QUEUE_BINDING_SOURCE_CHECKS_PASS assertions=$assertions native_provider=true known_factories=8 unknown_unchanged=true reader_bound=${SOURCE_LIMIT} nested_cleanup=true native_close_owner=true weaving=true",
        )
        kotlin.system.exitProcess(0)
    }
}
