package net.alexredby.pztoolkitjavapatches

import java.io.BufferedOutputStream
import java.io.Closeable
import java.io.IOException
import java.nio.charset.StandardCharsets.UTF_8
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import java.nio.file.StandardCopyOption.REPLACE_EXISTING
import java.nio.file.StandardOpenOption.APPEND
import java.nio.file.StandardOpenOption.CREATE
import java.nio.file.StandardOpenOption.WRITE

/** One append-only stream; caller owns synchronization and reports failures. */
internal class VehicleTraceFile(val path: Path, private val maxBytes: Long = MAX_BYTES) :
    Closeable {
    companion object {
        const val MAX_BYTES = 5L * 1024 * 1024
        const val BACKUPS = 4
    }

    private var output: BufferedOutputStream? = null
    private var bytes = 0L

    init {
        require(maxBytes > 0)
        Files.createDirectories(path.parent)
        for (index in 0..BACKUPS) {
            val candidate = if (index == 0) path else backup(index)
            if (
                Files.exists(candidate, NOFOLLOW_LINKS) &&
                    !Files.isRegularFile(candidate, NOFOLLOW_LINKS)
            )
                throw IOException("Trace output is not a regular file: $candidate")
            if (Files.exists(candidate) && Files.size(candidate) > maxBytes)
                throw IOException("Existing trace file exceeds rotation limit: $candidate")
        }
        open()
    }

    private fun backup(index: Int): Path = path.resolveSibling("${path.fileName}.$index")

    private fun open() {
        bytes = if (Files.exists(path)) Files.size(path) else 0L
        output = BufferedOutputStream(Files.newOutputStream(path, CREATE, WRITE, APPEND))
    }

    fun write(line: String) {
        val data = (line + "\n").toByteArray(UTF_8)
        if (data.size.toLong() > maxBytes) throw IOException("Trace record exceeds rotation limit")
        if (output == null) throw IOException("Trace output is closed")
        if (bytes + data.size > maxBytes) {
            close()
            Files.deleteIfExists(backup(BACKUPS))
            for (index in BACKUPS - 1 downTo 1) {
                if (Files.exists(backup(index)))
                    Files.move(backup(index), backup(index + 1), REPLACE_EXISTING)
            }
            if (Files.exists(path)) Files.move(path, backup(1), REPLACE_EXISTING)
            open()
        }
        output!!.write(data)
        output!!.flush()
        bytes += data.size
    }

    override fun close() {
        val stream = output
        output = null
        stream?.close()
    }
}
