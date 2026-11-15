package net.alexredby.pztoolkitjavapatches

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.security.MessageDigest
import java.util.HexFormat
import java.util.IdentityHashMap
import se.krka.kahlua.vm.Prototype

/** Pure structural hashes; no actor/request/network subsystem initialization. */
internal object LuaPrototypeFingerprint {
    private fun digest(prototype: Prototype, children: List<String>?): String {
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
                is Boolean -> { out.writeByte(1);out.writeBoolean(constant) }
                is Double -> { out.writeByte(2);out.writeLong(java.lang.Double.doubleToRawLongBits(constant)) }
                is String -> { out.writeByte(3);out.writeUTF(constant) }
                else -> return "unsupported"
            }
            out.writeInt(prototype.prototypes.size)
            if (children == null && prototype.prototypes.isNotEmpty()) return "unsupported"
            for (child in children.orEmpty()) out.writeUTF(child)
        }
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes.toByteArray()))
    }

    // Existing leaf fingerprints remain byte-for-byte compatible.
    fun leaf(prototype: Prototype): String = digest(prototype, null)

    /** Bounded public metadata, including every child body, with cycle rejection. */
    fun tree(prototype: Prototype): String {
        val active = IdentityHashMap<Prototype, Boolean>()
        var nodes = 0;var words = 0;var strings = 0
        fun visit(value: Prototype, depth: Int): String {
            if (depth > 16 || ++nodes > 256 || active.put(value, true) != null) return "unsupported"
            try {
                if (value.numParams !in 0..255 || value.numUpvalues !in 0..256 || value.maxStacksize !in 1..255 ||
                    value.code.isEmpty() || value.code.size > 65536 || value.constants.size > 4096 || value.prototypes.size > 256) return "unsupported"
                words += value.code.size;if (words > 262144) return "unsupported"
                for (constant in value.constants) when (constant) {
                    null, is Boolean, is Double -> Unit
                    is String -> { strings += constant.length;if (constant.length > 16384 || strings > 1048576) return "unsupported" }
                    else -> return "unsupported"
                }
                val children = ArrayList<String>()
                for (child in value.prototypes) {
                    val hash = visit(child, depth + 1)
                    if (hash == "unsupported") return hash
                    children.add(hash)
                }
                return digest(value, children)
            } finally { active.remove(value) }
        }
        return visit(prototype, 0)
    }
}
