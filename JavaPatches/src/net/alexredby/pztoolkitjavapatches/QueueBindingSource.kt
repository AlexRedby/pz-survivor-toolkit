package net.alexredby.pztoolkitjavapatches

import java.io.IOException
import java.io.Reader
import java.io.StringReader
import java.nio.file.Files
import java.nio.file.Path
import java.util.Locale
import java.util.Objects
import zombie.ZomboidFileSystem
import zombie.gameStates.ChooseGameInfo

/** Native RunLua provenance and bounded Reader capture; owns no reader or VM environment. */
internal object QueueBindingSource {
    const val MAX_SOURCE_CHARS = 1024 * 1024
    private const val MOD_ID = "PZSurvivorToolkit"

    enum class Module(val compilerName: String) {
        COMPAT("ActionQueueCompat.lua"),
        CARTS("ActionQueueCarts.lua");

        val target: String
            get() = "media/lua/client/PZSurvivorToolkit/$compilerName"
    }

    class Scope internal constructor(internal val module: Module?, internal val file: String?) {
        internal var claimed = false
    }

    data class Prepared(val reader: Reader, val text: String?, val module: Module?)

    private val loading = ThreadLocal<Scope>()

    /** Each native RunLua, including unrelated/cached/nested loads, gets a new scope. */
    @JvmStatic
    fun begin(file: String?, supported: Boolean): Scope? {
        val previous = loading.get()
        val normalized = file?.replace('\\', '/')
        val module =
            if (supported && normalized != null)
                Module.entries.firstOrNull {
                    (normalized == it.target || normalized.endsWith("/" + it.target)) &&
                        provider(it, normalized)
                }
            else null
        loading.set(Scope(module, normalized))
        return previous
    }

    @JvmStatic
    fun end(previous: Scope?) {
        if (previous == null) loading.remove() else loading.set(previous)
    }

    private fun provider(module: Module, file: String): Boolean =
        try {
            val files = ZomboidFileSystem.instance
            if (files.ignoreActiveFileMap.get() == true || !files.modIDs.contains(MOD_ID)) false
            else {
                val version = ChooseGameInfo.getModDetails(MOD_ID)?.versionDir
                val active = files.activeFileMap[module.target.lowercase(Locale.ENGLISH)]
                if (version == null || active == null) false
                else {
                    val expected = Path.of(version).resolve(module.target)
                    val selected = Path.of(active)
                    val resolved = Path.of(files.getString(file))
                    Files.isRegularFile(expected) &&
                        Files.isRegularFile(selected) &&
                        Files.isSameFile(expected, selected) &&
                        Files.isSameFile(expected, resolved)
                }
            }
        } catch (_: IOException) {
            false
        } catch (_: RuntimeException) {
            false
        }

    /** First matching Reader owns the claim, even if capture throws. No reader/text enters TLS. */
    @JvmStatic
    @Throws(IOException::class)
    fun prepare(reader: Reader, name: String?, supported: Boolean): Prepared {
        val scope = loading.get()
        val module = scope?.module
        if (
            !supported ||
                scope == null ||
                module == null ||
                scope.claimed ||
                name != module.compilerName
        )
            return Prepared(reader, null, null)
        scope.claimed = true
        // Recheck native selection in case callbacks changed it since RunLua entry.
        if (!provider(module, scope.file!!)) return Prepared(reader, null, null)
        val source = StringBuilder()
        val buffer = CharArray(8192)
        while (source.length <= MAX_SOURCE_CHARS) {
            val count =
                reader.read(buffer, 0, minOf(buffer.size, MAX_SOURCE_CHARS + 1 - source.length))
            if (count < 0) {
                val text = source.toString()
                return Prepared(StringReader(text), text, module)
            }
            if (count == 0) {
                val next = reader.read()
                if (next < 0) {
                    val text = source.toString()
                    return Prepared(StringReader(text), text, module)
                }
                source.append(next.toChar())
            } else source.append(buffer, 0, count)
        }
        return Prepared(ReplayReader(source.toString(), reader), null, module)
    }

    /** Borrowed tail: native RunLua's original BufferedReader remains its only closing owner. */
    private class ReplayReader(prefix: String, private val tail: Reader) : Reader() {
        private val prefix = StringReader(prefix)
        private var prefixDone = false
        private var closed = false

        override fun read(buffer: CharArray, offset: Int, length: Int): Int {
            Objects.checkFromIndexSize(offset, length, buffer.size)
            if (closed) throw IOException("Reader closed")
            if (length == 0) return 0
            if (!prefixDone) {
                val count = prefix.read(buffer, offset, length)
                if (count >= 0) return count
                prefixDone = true
            }
            return tail.read(buffer, offset, length)
        }

        override fun close() {
            closed = true
            prefix.close()
        } // never close borrowed original reader
    }
}
