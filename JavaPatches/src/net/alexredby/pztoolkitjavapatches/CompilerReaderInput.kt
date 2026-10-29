package net.alexredby.pztoolkitjavapatches

import java.io.IOException
import java.io.Reader
import java.io.StringReader
import java.util.Objects

/** Bounded compiler read-ahead; the native loader remains the original Reader's closing owner. */
internal object CompilerReaderInput {
    data class Captured(val reader: Reader, val text: String?)

    @JvmStatic
    fun capture(reader: Reader, maxChars: Int): Captured {
        require(maxChars >= 0 && maxChars < Int.MAX_VALUE)
        val source = StringBuilder()
        val buffer = CharArray(8192)
        try {
            while (source.length <= maxChars) {
                val count = reader.read(buffer, 0, minOf(buffer.size, maxChars + 1 - source.length))
                if (count < 0) {
                    val text = source.toString()
                    return Captured(StringReader(text), text)
                }
                if (count == 0) {
                    val next = reader.read()
                    if (next < 0) {
                        val text = source.toString()
                        return Captured(StringReader(text), text)
                    }
                    source.append(next.toChar())
                } else source.append(buffer, 0, count)
            }
        } catch (failure: IOException) {
            // The native lexer must encounter the failure in source order: it may reject
            // earlier syntax without reaching IO, or handle a reached failure as native EOF.
            return Captured(ReplayReader(source.toString(), reader, failure), null)
        }
        return Captured(ReplayReader(source.toString(), reader), null)
    }

    private class ReplayReader(
        prefix: String,
        private val tail: Reader,
        private var pendingFailure: IOException? = null,
    ) : Reader() {
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
            pendingFailure?.let { failure ->
                pendingFailure = null
                throw failure
            }
            return tail.read(buffer, offset, length)
        }

        override fun close() {
            closed = true
            prefix.close()
        } // borrowed tail is closed only by native RunLua's original BufferedReader
    }
}
