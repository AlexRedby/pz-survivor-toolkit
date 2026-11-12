package net.alexredby.pztoolkitjavapatches

import java.util.IdentityHashMap
import se.krka.kahlua.integration.annotations.LuaMethod
import se.krka.kahlua.vm.LuaClosure
import se.krka.kahlua.j2se.KahluaTableImpl
import zombie.Lua.LuaManager
import zombie.characters.IsoPlayer

/** Read-only, fresh facts about supplied-source closures. This grants no registry/edit authority. */
object LuaCaptureFacts {
    @JvmField internal val SUPPORTED = LuaFactApi.SUPPORTED && arrayOf(
        "se/krka/kahlua/vm/UpValue.class" to "505d77406e1d50884bec438e37afd1ec0a37f4431b649744a96add479a897745",
        "se/krka/kahlua/vm/Prototype.class" to "5e31f0809512e9cfbc9a8fff5a932e35cdc7f1ebb4a0ea146a2f9a207a23fcf4",
        "zombie/characters/IsoPlayer.class" to "3f1c4634d3a8e7e36baf4b33f76cf7ef79d88c3351bd0eb2a6a6bb34c2d9858f",
        "zombie/characters/IsoGameCharacter.class" to "29040e19c3e420499f73bc0ea0d5b86d7f7d38655acdc13d0107df736eb54c0b",
        "zombie/iso/IsoMovingObject.class" to "7e6e84fe9d3cb264e8d8e682d91e0abe919d481b7349d17b997e8a78f2293a5f",
        "zombie/iso/IsoObject.class" to "22387ecf47c1cf9aac192466de6298067f27584160c76a72baee38c6ad36dff2",
    ).all { (path, hash) -> BytecodeSupport.supports(path, hash) }

    private val readMethod = LuaCaptureFacts::class.java.getMethod("match", Any::class.java, Any::class.java)
    private val checkMethod = LuaCaptureFacts::class.java.getMethod("apiMatches", Any::class.java)
    // Only immutable class metadata is retained, never a key or captured value.
    private val identityKeyTypes = if (!SUPPORTED) emptySet() else
        listOf(KahluaTableImpl::class.java, LuaClosure::class.java, IsoPlayer::class.java).filterTo(HashSet()) { type ->
            try {
                // Check the complete inheritance chain without invoking its methods.
                type.getMethod("hashCode").declaringClass == Any::class.java &&
                    type.getMethod("equals", Any::class.java).declaringClass == Any::class.java
            } catch (_: Exception) { false } catch (_: LinkageError) { false }
        }

    @JvmStatic @LuaMethod(name = "toolkitLuaCaptureFactsApiMatches", global = true)
    fun apiMatches(helper: Any?): Boolean = try {
        SUPPORTED && LuaFactApi.entry("toolkitLuaCaptureFactsApiMatches", checkMethod, arrayOf(helper)) &&
            LuaFactApi.canonical(helper, readMethod) &&
            LuaFactApi.plain(LuaManager.env)?.delegate?.get("toolkitLuaCaptureFactsMatch") === helper
    } catch (_: Exception) { false } catch (_: AssertionError) { false }

    @JvmStatic @LuaMethod(name = "toolkitLuaCaptureFactsMatch", global = true)
    fun match(callback: Any?, recipe: Any?): Boolean? = try {
        if (!SUPPORTED || !LuaFactApi.entry("toolkitLuaCaptureFactsMatch", readMethod, arrayOf(callback, recipe))) null
        else {
            // Parse every nested schema before observing any capture. A false predicate
            // must never hide a malformed/unsupported sibling or nested recipe.
            val parsed = Parser().recipe(recipe, 0)
            if (parsed == null) null else observe(callback, parsed, IdentityHashMap(), 0)
        }
    } catch (_: Exception) { null } catch (_: AssertionError) { null }

    private class Recipe(val hash: String, val parameters: Int, val upvalues: Int, val rules: List<Rule>)
    private class Rule(val slot: Int, val predicate: Predicate)
    private sealed class Predicate {
        object Empty : Predicate()
        class Absent(val key: Any) : Predicate()
        class Identity(val value: Any) : Predicate()
        class Closure(val recipe: Recipe) : Predicate()
        class Field(val key: String, val predicate: Predicate) : Predicate()
    }

    // These are format guards for untrusted plain data, not runtime eligibility limits.
    private const val MAX_DEPTH = 16
    private const val MAX_NODES = 1024
    private const val MAX_CAPTURES = 256
    private fun ownStringValue(table: KahluaTableImpl, key: String): Any? {
        // Map.get can reorder an access-order LinkedHashMap. String equality
        // against a String entry key also avoids arbitrary foreign key methods.
        for (entry in table.delegate.entries) if (entry.key is String && key == entry.key) return entry.value
        return null
    }
    private class Parser {
        private val active = IdentityHashMap<KahluaTableImpl, Boolean>()
        private var nodes = 0
        private fun enter(value: Any?, depth: Int): KahluaTableImpl? {
            if (depth > MAX_DEPTH || ++nodes > MAX_NODES) return null
            val table = LuaFactApi.plain(value) ?: return null
            return if (active.put(table, true) == null) table else null
        }
        private fun keys(table: KahluaTableImpl, expected: Set<String>): Boolean =
            table.delegate.size == expected.size && table.delegate.keys.all { it is String && it in expected }
        private fun integer(value: Any?, maximum: Int): Int? {
            if (value !is Double || !value.isFinite() || value < 0 || value > maximum || value != value.toInt().toDouble()) return null
            return value.toInt()
        }
        fun recipe(value: Any?, depth: Int): Recipe? {
            val table = enter(value, depth) ?: return null
            try {
                if (!keys(table, setOf("fingerprint", "parameters", "upvalues", "captures"))) return null
                val hash = ownStringValue(table, "fingerprint") as? String ?: return null
                if (hash.length != 64 || hash.any { it !in '0'..'9' && it !in 'a'..'f' }) return null
                val parameters = integer(ownStringValue(table, "parameters"), 255) ?: return null
                val upvalues = integer(ownStringValue(table, "upvalues"), MAX_CAPTURES) ?: return null
                val captures = enter(ownStringValue(table, "captures"), depth + 1) ?: return null
                try {
                    val count = captures.delegate.size
                    if (count > MAX_CAPTURES || captures.delegate.keys.any {
                        val index = integer(it, count)
                        index == null || index == 0
                    }) return null
                    val rules = ArrayList<Rule>()
                    for (entry in captures.delegate.entries) {
                        val rule = enter(entry.value, depth + 2) ?: return null
                        try {
                            if (rule.delegate.size !in 2..4) return null
                            val slot = integer(ownStringValue(rule, "slot"), MAX_CAPTURES - 1) ?: return null
                            if (slot >= upvalues) return null
                            rules.add(Rule(slot, predicate(rule, depth + 2, true) ?: return null))
                        } finally { active.remove(rule) }
                    }
                    return Recipe(hash, parameters, upvalues, rules)
                } finally { active.remove(captures) }
            } finally { active.remove(table) }
        }
        private fun predicate(table: KahluaTableImpl, depth: Int, slot: Boolean): Predicate? {
            if (table.delegate.size !in (if (slot) 2..4 else 1..3)) return null
            val test = ownStringValue(table, "test") as? String ?: return null
            val base = if (slot) setOf("slot", "test") else setOf("test")
            return when (test) {
                "empty-table" -> if (keys(table, base)) Predicate.Empty else null
                "absent-entry" -> {
                    val key = ownStringValue(table, "key")
                    if (keys(table, base + "key") && safeKey(key)) Predicate.Absent(key!!) else null
                }
                "identity" -> {
                    val value = ownStringValue(table, "value")
                    // This predicate proves an opaque alias. Scalar equality has
                    // different semantics and is deliberately outside this format.
                    if (keys(table, base + "value") && value != null && value !is String &&
                        value !is Number && value !is Boolean && value !is Char) Predicate.Identity(value) else null
                }
                "closure" -> if (keys(table, base + "recipe")) {
                    recipe(ownStringValue(table, "recipe"), depth + 1)?.let { Predicate.Closure(it) }
                } else null
                "field" -> {
                    val key = ownStringValue(table, "key") as? String
                    if (!keys(table, base + setOf("key", "predicate")) || key == null || key.length > 16384) null
                    else {
                        val nested = enter(ownStringValue(table, "predicate"), depth + 1) ?: return null
                        try { predicate(nested, depth + 1, false)?.let { Predicate.Field(key, it) } }
                        finally { active.remove(nested) }
                    }
                }
                else -> null
            }
        }
    }

    /** Exact identity-hash classes and final scalars only; no foreign hashCode/equals. */
    private fun safeKey(value: Any?): Boolean {
        val type = value?.javaClass ?: return false
        return when (type) {
            String::class.java, Boolean::class.javaObjectType -> true
            Double::class.javaObjectType -> (value as Double).isFinite()
            else -> type in identityKeyTypes
        }
    }

    private fun observe(value: Any?, recipe: Recipe, active: IdentityHashMap<LuaClosure, Boolean>, depth: Int): Boolean? {
        if (depth > MAX_DEPTH || value?.javaClass != LuaClosure::class.java) return null
        val closure = value as LuaClosure
        if (closure.env !== LuaManager.env || active.put(closure, true) != null) return null
        try {
            val p = closure.prototype
            if (p.numParams != recipe.parameters || p.isVararg || p.numUpvalues != recipe.upvalues ||
                closure.upvalues.size != recipe.upvalues || closure.upvalues.any { it == null } ||
                p.maxStacksize !in 1..255 || p.code.size !in 1..65536 || p.constants.size > 4096 ||
                p.prototypes.isNotEmpty()) return null
            var textSize = 0
            for (constant in p.constants) when (constant) {
                null, is Boolean, is Double -> Unit
                is String -> {
                    if (constant.length > 16384) return null
                    textSize += constant.length
                    if (textSize > 1048576) return null
                }
                else -> return null
            }
            if (LuaPrototypeFingerprint.leaf(p) != recipe.hash) return null
            var result = true
            var unknown = false
            for (rule in recipe.rules) {
                val fact = predicate(closure.upvalues[rule.slot].getValue(), rule.predicate, active, depth)
                if (fact == null) unknown = true else if (!fact) result = false
            }
            return if (unknown) null else result
        } finally { active.remove(closure) }
    }

    private fun predicate(value: Any?, predicate: Predicate, active: IdentityHashMap<LuaClosure, Boolean>, depth: Int): Boolean? = when (predicate) {
        Predicate.Empty -> LuaFactApi.plain(value)?.delegate?.isEmpty()
        is Predicate.Absent -> LuaFactApi.plain(value)?.let { !it.delegate.containsKey(predicate.key) }
        is Predicate.Identity -> value === predicate.value
        is Predicate.Closure -> observe(value, predicate.recipe, active, depth + 1)
        is Predicate.Field -> {
            val table = LuaFactApi.plain(value)
            if (table == null || depth >= MAX_DEPTH) null
            else {
                val field = ownStringValue(table, predicate.key)
                if (field == null) null else predicate(field, predicate.predicate, active, depth + 1)
            }
        }
    }
}
