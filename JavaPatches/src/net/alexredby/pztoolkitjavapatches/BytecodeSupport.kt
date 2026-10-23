package net.alexredby.pztoolkitjavapatches

import java.security.MessageDigest
import java.util.HexFormat

/** Checks the installed class bytes without loading or initializing the game class. */
object BytecodeSupport {
    @JvmStatic
    fun supports(resource: String?, expected: String?): Boolean = try {
        BytecodeSupport::class.java.classLoader.getResourceAsStream(resource).use { stream ->
            if (stream == null) {
                false
            } else {
                val checksum = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(stream.readAllBytes()))
                // Java evaluates the digest before dereferencing a nullable expected checksum.
                (expected ?: throw NullPointerException()).equals(checksum)
            }
        }
    } catch (error: Exception) {
        System.err.println("[PZToolkitJavaPatches] Disabled: cannot check $resource: $error")
        false
    }
}
