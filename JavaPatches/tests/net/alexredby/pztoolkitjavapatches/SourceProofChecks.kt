package net.alexredby.pztoolkitjavapatches

import java.io.BufferedReader
import java.io.ByteArrayInputStream
import java.io.DataInputStream
import java.io.InputStreamReader
import java.io.StringReader
import java.nio.charset.StandardCharsets
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.integration.expose.LuaJavaClassExposer
import se.krka.kahlua.vm.KahluaTable
import zombie.Lua.KahluaNumberConverter
import java.nio.file.Files
import java.nio.file.Path
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.KahluaThread

object SourceProofChecks {
    @JvmStatic
    fun main(args: Array<String>) {
        val root = Path.of(System.getProperty("pz.test.project"))
        val platform = J2SEPlatform()
        val environment = platform.newEnvironment()
        val thread =
            KahluaThread(platform, environment).apply {
                debugOwnerThread = Thread.currentThread()
            }
        val matches = JavaFunction { frame, count ->
            frame.push(QueueLeafTransferFacts.luaMetatableMatches(frame.get(0), if (count > 1) frame.get(1) else null))
            1
        }
        environment.rawset("NativeMetatableMatches", matches)
        environment.rawset("toolkitLuaMetatableMatches", matches)
        val owner = platform.newTable() as KahluaTableImpl
        val parent = platform.newTable() as KahluaTableImpl
        val replacement = platform.newTable() as KahluaTableImpl
        var callbacks = 0
        replacement.rawset("__metatable", parent)
        replacement.rawset("__index", JavaFunction { _, _ ->
            callbacks++
            error("Metatable identity must not invoke Lua or inherited callbacks")
        })
        check(QueueLeafTransferFacts.luaMetatableMatches(owner, null))
        owner.metatable = parent
        check(QueueLeafTransferFacts.luaMetatableMatches(owner, parent))
        check(!QueueLeafTransferFacts.luaMetatableMatches(owner, null))
        owner.metatable = replacement
        environment.rawset("TestProtectedOwner", owner)
        environment.rawset("TestVisibleParent", parent)
        val visible = LuaCompiler.loadis(
            "return getmetatable(TestProtectedOwner)==TestVisibleParent".reader(),
            "=(protected metatable diagnostic)", environment,
        )
        check(thread.call(visible, emptyArray<Any?>()) == true) { "Protected parent fixture is not concealed" }
        check(!QueueLeafTransferFacts.luaMetatableMatches(owner, parent)) { "Protected replacement escaped actual-parent proof" }
        check(QueueLeafTransferFacts.luaMetatableMatches(owner, replacement))
        owner.setRewriteTable(platform.newTable())
        check(!QueueLeafTransferFacts.luaMetatableMatches(owner, replacement)) { "Rewritten owner was accepted" }
        owner.setRewriteTable(null)
        replacement.setRewriteTable(platform.newTable())
        check(!QueueLeafTransferFacts.luaMetatableMatches(owner, replacement)) { "Rewritten expected parent was accepted" }
        replacement.setRewriteTable(null)
        check(!QueueLeafTransferFacts.luaMetatableMatches(Any(), null))
        check(!QueueLeafTransferFacts.luaMetatableMatches(owner, Any()))
        check(!QueueLeafTransferFacts.luaMetatableMatches(KahluaTableImpl(java.util.HashMap()), null))
        check(callbacks == 0)
        environment.rawset("TestProtectedOwner", null)
        environment.rawset("TestVisibleParent", null)
        Files.newBufferedReader(
                root.resolve(
                    "PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua",
                ),
            )
            .use { reader ->
                val loader = LuaCompiler.loadis(reader, "SourceProof.lua", environment)
                environment.rawset("TestLoadSourceProof", loader)
                environment.rawset("TestSourceProof", thread.call(loader, emptyArray<Any?>()))
            }
        // Kahlua's compiler truncates non-ASCII literals; reader strings arrive from Java intact.
        environment.rawset("TestUnicodeA", "A洗😀é")
        environment.rawset("TestUnicodeB", "第二行")
        Files.newBufferedReader(root.resolve("tests/test_source_proof.lua")).use { reader ->
            thread.call(
                LuaCompiler.loadis(reader, "test_source_proof.lua", environment),
                emptyArray<Any?>(),
            )
        }
        // Exact native reader strings matter: DataInputStream.readLine maps
        // bytes to chars, whereas BufferedReader below decodes UTF-8. Do not
        // replace either with a uniform file decoder when optimizing checksums.
        val converters = KahluaConverterManager()
        KahluaNumberConverter.install(converters)
        val exposer = object : LuaJavaClassExposer(converters, platform, environment) {
            override fun shouldExpose(type: Class<*>?): Boolean =
                type == BufferedReader::class.java || type == DataInputStream::class.java
        }
        exposer.exposeLikeJava(BufferedReader::class.java, environment)
        exposer.exposeLikeJava(DataInputStream::class.java, environment)
        val checksum = (environment.rawget("TestSourceProof") as KahluaTable).rawget("checksum")
        val texts = listOf("", "\n", "\r\n", "\r", "ASCII", "a\rb\nc\r\n", "\n\n", "\u0000",
            "\uFEFFA洗😀e\u0301", "\uD800", "\uDC00", "\uD800A")
        fun reader(text: String, mode: Int): java.io.Closeable = when (mode) {
            0 -> BufferedReader(StringReader(text))
            1 -> BufferedReader(InputStreamReader(ByteArrayInputStream(text.toByteArray(StandardCharsets.UTF_8)), StandardCharsets.UTF_8))
            else -> DataInputStream(ByteArrayInputStream(text.toByteArray(StandardCharsets.UTF_8)))
        }
        @Suppress("DEPRECATION")
        fun normalized(text: String, mode: Int): String = reader(text, mode).use { input ->
            buildString {
                while (true) {
                    val line = when (input) {
                        is BufferedReader -> input.readLine()
                        is DataInputStream -> input.readLine()
                        else -> error("reader")
                    } ?: break
                    append(line).append('\n')
                }
            }
        }
        fun expected(text: String, adler: Boolean, limit: Double): Double? {
            if (text.isNotEmpty() && text.length.toDouble() > limit) return null
            if (!adler) return text.fold(5381L) { hash, char -> (hash * 33 + char.code) and 0xffffffffL }.toDouble()
            // Independent weighted-sum Adler oracle, not the Lua recurrence.
            var a = 1L
            var b = text.length.toLong()
            for ((index, char) in text.withIndex()) {
                a += char.code
                b += (text.length - index).toLong() * char.code
            }
            return ((b % 65521) * 65536 + a % 65521).toDouble()
        }
        for (text in texts) for (mode in 0..2) {
            val units = normalized(text, mode)
            for (adler in listOf(false, true)) for (limit in listOf(-1.0, 0.0, 1.0, 1.5, 2.0, 3.0,
                units.length.toDouble(), Double.NaN, Double.POSITIVE_INFINITY)) {
                reader(text, mode).use { input ->
                    val actual = thread.call(checksum, arrayOf(input, adler, limit))
                    check(actual == expected(units, adler, limit)) { "Native reader checksum parity: mode=$mode adler=$adler limit=$limit" }
                }
            }
        }
        println("SOURCE_PROOF_CHECKS_PASS (same Lua module and vectors in native UTF16 Kahlua)")
        kotlin.system.exitProcess(0)
    }
}
