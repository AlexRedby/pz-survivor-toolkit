package net.alexredby.pztoolkitjavapatches

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.security.MessageDigest
import java.util.HexFormat
import se.krka.kahlua.vm.Prototype

/** Pure structural hash; no transaction, actor or network subsystem initialization.
 * Callers must prove bounded source shapes before using this leaf-only format.
 */
internal object LuaPrototypeFingerprint {
    fun leaf(prototype: Prototype): String {
        val bytes = ByteArrayOutputStream()
        DataOutputStream(bytes).use { out ->
            out.writeInt(prototype.numParams)
            out.writeBoolean(prototype.isVararg)
            out.writeInt(prototype.numUpvalues)
            out.writeInt(prototype.maxStacksize)
            out.writeInt(prototype.code.size)
            for (word in prototype.code) out.writeInt(word)
            out.writeInt(prototype.constants.size)
            for (constant in prototype.constants) when (constant) {
                null -> out.writeByte(0)
                is Boolean -> {
                    out.writeByte(1)
                    out.writeBoolean(constant)
                }
                is Double -> {
                    out.writeByte(2)
                    out.writeLong(java.lang.Double.doubleToRawLongBits(constant))
                }
                is String -> {
                    out.writeByte(3)
                    out.writeUTF(constant)
                }
                else -> return "unsupported"
            }
            out.writeInt(prototype.prototypes.size)
            if (prototype.prototypes.isNotEmpty()) return "unsupported"
        }
        return HexFormat.of()
            .formatHex(MessageDigest.getInstance("SHA-256").digest(bytes.toByteArray()))
    }
}
