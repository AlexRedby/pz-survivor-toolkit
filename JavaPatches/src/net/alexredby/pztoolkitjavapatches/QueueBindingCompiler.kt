package net.alexredby.pztoolkitjavapatches

import java.io.OutputStream
import java.security.MessageDigest
import java.util.LinkedHashMap
import java.util.WeakHashMap
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.stdlib.TableLib
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.KahluaTable
import se.krka.kahlua.vm.LuaClosure
import se.krka.kahlua.vm.Prototype

/** Accelerate only exact source-owned metadata loops; uncertain reads remain ordinary Lua. */
internal object QueueBindingCompiler {
    // Values are separately compiled original bytecode only: no native constants,
    // closures, environments, token/checker objects or references to weak keys.
    private val serializationOriginals = WeakHashMap<Prototype, Prototype>()

    @JvmStatic
    @Throws(java.io.IOException::class)
    fun dumpOriginal(prototype: Prototype, output: OutputStream): Boolean {
        val original =
            synchronized(serializationOriginals) { serializationOriginals[prototype] }
                ?: return false
        original.dump(output)
        return true
    }

    private const val COMPAT_SHA =
        "3496266dbb36ab39b9103859d00f4ffab8102082d2ced324897bd95459323713"
    private const val CARTS_SHA = "77b199cbc0ea19e9e69261a176303b211a45531e4f4be9f453deb16f929dfba2"
    private const val PREFIX = "__PZ_PRIVATE_OWN_REFS_54d62c15_"
    private val platform = J2SEPlatform()
    private val canonicalTable =
        (platform.newTable() as KahluaTableImpl).also { TableLib.register(platform, it) }
    private val canonicalPairs =
        (canonicalTable.delegate["table"] as KahluaTableImpl).delegate["pairs"].also {
            require(it?.javaClass == TableLib::class.java)
        }

    private data class Binding(
        val owner: KahluaTableImpl,
        val expected: KahluaTableImpl,
        val keys: Array<String>,
        val values: Array<Any>,
    )

    private class Token(val bindings: Array<Binding>)

    private data class Site(
        val key: String,
        val declaration: String,
        val declarationReplacement: String,
        val loops: String,
        val arguments: String,
        val requiredConstants: Set<String>,
        val arity: Int,
    ) {
        val marker = PREFIX + key + "__"
        val local = "toolkitPrivateOwnRefs" + key
    }

    private val bcLoop =
        "for name, expected in pairs(proximityMethods) do if proximity[name] ~= expected then return false end end"
    private val fridgeLoop =
        "for name, callback in pairs(functions) do if owner[name] ~= callback then return false end end"
    private val cartsLoops =
        "for name, value in pairs(methods) do if class[name] ~= value then return false,\"cart_method_changed:\"..name end end\n    for name, value in pairs(coreMethods) do if (core[name] or false) ~= value then return false,\"cart_helper_changed:\"..name end end"
    private val compatSites =
        listOf(
            Site(
                "BC",
                "    containerHelpersUnchanged = function()\n",
                "    local toolkitPrivateOwnRefsBC; containerHelpersUnchanged = function()\n",
                bcLoop,
                "proximity, proximityMethods",
                setOf("EURY_CONTAINERS", "isStaleVehicleContainer"),
                2,
            ),
            Site(
                "Fridge",
                "    local function helpersUnchanged()\n        if TurnOffFridges ~= owner",
                "    local toolkitPrivateOwnRefsFridge; local function helpersUnchanged()\n        if TurnOffFridges ~= owner",
                fridgeLoop,
                "owner, functions",
                setOf("TurnOffFridges", "MODULE", "AUTO_KEY"),
                2,
            ),
        )
    private val cartSites =
        listOf(
            Site(
                "Carts",
                "local function unchanged()\n",
                "local toolkitPrivateOwnRefsCarts; local function unchanged()\n",
                cartsLoops,
                "class, methods, core, coreMethods",
                setOf("owner_changed", "container_delegate_changed", "network_helper_changed"),
                4,
            ),
        )

    private fun filename(path: String) = path.replace('\\', '/').substringAfterLast('/')

    private fun sites(path: String) =
        when (filename(path)) {
            "ActionQueueCompat.lua" -> compatSites
            "ActionQueueCarts.lua" -> cartSites
            else -> null
        }

    private fun sha(text: String) =
        java.util.HexFormat.of()
            .formatHex(
                MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8)),
            )

    private fun ordinary(value: Any?): KahluaTableImpl? {
        val table = value as? KahluaTableImpl ?: return null
        return table.takeIf {
            it.javaClass == KahluaTableImpl::class.java &&
                it.rewriteTable == null &&
                it.delegate.javaClass == LinkedHashMap::class.java
        }
    }

    private fun trusted(env: KahluaTableImpl): Boolean =
        !zombie.core.Core.debug &&
            ordinary(env) === env &&
            env.metatable == null &&
            env.delegate["_G"] === env &&
            env.delegate["pairs"] === canonicalPairs

    private fun capture(env: KahluaTableImpl, values: Array<Any?>): Token? {
        if (!trusted(env) || values.isEmpty() || values.size > 4 || values.size % 2 != 0)
            return null
        val bindings = ArrayList<Binding>(values.size / 2)
        var total = 0
        for (i in values.indices step 2) {
            val owner = ordinary(values[i]) ?: return null
            val expected = ordinary(values[i + 1]) ?: return null
            if (
                expected.metatable != null ||
                    expected.delegate.isEmpty() ||
                    expected.delegate.size > 64
            )
                return null
            total += expected.delegate.size
            if (total > 128) return null
            val entries = expected.delegate.entries.toList()
            // Double EQ runs before the VM's object-identity shortcut; NaN != itself.
            if (
                entries.any {
                    it.key !is String ||
                        it.value == null ||
                        (it.value as? Boolean) == false ||
                        (it.value as? Double)?.isNaN() == true
                }
            )
                return null
            bindings.add(
                Binding(
                    owner,
                    expected,
                    entries.map { it.key as String }.toTypedArray(),
                    entries.map { it.value!! }.toTypedArray(),
                ),
            )
        }
        return Token(bindings.toTypedArray())
    }

    private fun matches(token: Token?): Boolean {
        if (token == null) return false
        for (binding in token.bindings) {
            if (
                ordinary(binding.owner) !== binding.owner ||
                    ordinary(binding.expected) !== binding.expected ||
                    binding.expected.metatable != null ||
                    binding.expected.delegate.size != binding.keys.size
            )
                return false
            for (i in binding.keys.indices) {
                val key = binding.keys[i]
                val expected = binding.values[i]
                if (
                    binding.expected.delegate[key] !== expected ||
                        binding.owner.delegate[key] !== expected
                )
                    return false
            }
        }
        return true
    }

    private fun replaceOnce(text: String, old: String, new: String): String? {
        val first = text.indexOf(old)
        if (first < 0 || text.indexOf(old, first + old.length) >= 0) return null
        return text.substring(0, first) + new + text.substring(first + old.length)
    }

    private fun transform(text: String, sites: List<Site>): String? {
        if (text.contains(PREFIX) || text.contains("toolkitPrivateOwnRefs")) return null
        var result = text
        for (site in sites) {
            result =
                replaceOnce(result, site.declaration, site.declarationReplacement) ?: return null
            val guarded =
                "if not ${site.local} then ${site.local} = (\"${site.marker}\")(${site.arguments}) end; if ${site.local}() ~= true then ${site.loops} end"
            result = replaceOnce(result, site.loops, guarded) ?: return null
        }
        if (result.count { it == '\n' } != text.count { it == '\n' }) return null
        return result
    }

    private fun walk(root: Prototype): List<Prototype> = buildList {
        fun visit(p: Prototype, depth: Int) {
            require(depth <= 32 && size < 2048)
            add(p)
            for (child in p.prototypes) visit(child, depth + 1)
        }
        visit(root, 0)
    }

    private fun parallelOriginals(
        modified: Prototype,
        original: Prototype,
    ): List<Pair<Prototype, Prototype>>? {
        val result = ArrayList<Pair<Prototype, Prototype>>()
        fun visit(a: Prototype, b: Prototype, depth: Int): Boolean {
            if (
                depth > 32 ||
                    result.size >= 2048 ||
                    a.prototypes.size != b.prototypes.size ||
                    a.numParams != b.numParams ||
                    a.isVararg != b.isVararg ||
                    a.name != b.name ||
                    a.file != b.file ||
                    a.filename != b.filename
            )
                return false
            // Compiler-produced dumpable constants cannot retain a VM/environment. Do not
            // accept a foreign compiler extension that injected arbitrary native values.
            if (b.constants.any { it != null && it !is String && it !is Double && it !is Boolean })
                return false
            result.add(a to b)
            for (i in a.prototypes.indices) if (!visit(a.prototypes[i], b.prototypes[i], depth + 1))
                return false
            return true
        }
        return if (visit(modified, original, 0)) result else null
    }

    private fun bind(
        text: String,
        path: String,
        environment: KahluaTable,
        sites: List<Site>,
    ): LuaClosure? {
        val env = environment as? KahluaTableImpl ?: return null
        val transformed = transform(text, sites) ?: return null
        val compiled = LuaCompiler.loadstring(transformed, path, environment)
        val nodes = walk(compiled.prototype)
        val pending = ArrayList<Triple<Site, Prototype, Int>>()
        for (site in sites) {
            val found = nodes.flatMap { p ->
                p.constants.indices.filter { p.constants[it] == site.marker }.map { p to it }
            }
            if (found.size != 1) return null
            val (owner, index) = found.single()
            if (
                owner.numParams != 0 ||
                    owner.isVararg ||
                    owner.prototypes.isNotEmpty() ||
                    !owner.constants.toSet().containsAll(site.requiredConstants)
            )
                return null
            pending.add(Triple(site, owner, index))
        }
        if (pending.map { it.second }.toSet().size != sites.size) return null
        val original = LuaCompiler.loadstring(text, path, environment).prototype
        val originals = parallelOriginals(compiled.prototype, original) ?: return null
        for ((site, owner, _) in pending) {
            val corresponding = originals.singleOrNull { it.first === owner }?.second ?: return null
            if (
                corresponding.prototypes.isNotEmpty() ||
                    !corresponding.constants.toSet().containsAll(site.requiredConstants)
            )
                return null
        }
        // Publish only after all marker/prototype checks pass. No partially bound result escapes.
        for ((site, owner, index) in pending) {
            owner.constants[index] = JavaFunction { frame, count ->
                val caller = frame.coroutine.getParentNoAssert(1)?.closure
                val authentic =
                    count == site.arity && caller?.prototype === owner && caller.env === env
                val token = if (authentic) capture(env, Array(count) { frame.get(it) }) else null
                val checker = JavaFunction { current, n ->
                    val actual = current.coroutine.getParentNoAssert(1)?.closure
                    val same =
                        n == 0 &&
                            caller != null &&
                            actual === caller &&
                            actual.prototype === owner &&
                            actual.env === env &&
                            trusted(env) &&
                            matches(token)
                    current.push(if (same) true else null)
                    1
                }
                frame.push(checker)
                1
            }
        }
        synchronized(serializationOriginals) {
            for ((modified, baseline) in originals) serializationOriginals[modified] = baseline
        }
        return compiled
    }

    @JvmStatic
    fun compile(
        text: String,
        path: String,
        environment: KahluaTable,
        enabled: Boolean,
    ): LuaClosure {
        val selected = sites(path)
        val expected =
            when (filename(path)) {
                "ActionQueueCompat.lua" -> COMPAT_SHA
                "ActionQueueCarts.lua" -> CARTS_SHA
                else -> null
            }
        if (!enabled || selected == null || sha(text) != expected)
            return LuaCompiler.loadstring(text, path, environment)
        return bind(text, path, environment, selected)
            ?: LuaCompiler.loadstring(text, path, environment)
    }
}
