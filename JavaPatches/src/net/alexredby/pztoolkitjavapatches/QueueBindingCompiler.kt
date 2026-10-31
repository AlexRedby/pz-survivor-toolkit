package net.alexredby.pztoolkitjavapatches

import java.io.OutputStream
import java.security.MessageDigest
import java.util.LinkedHashMap
import java.util.WeakHashMap
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.stdlib.BaseLib
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
    private const val POLICY_SHA =
        "d7ff2a26e9987a6a242f4e192d2667af391747b1f8c280d03f3a4cbde45e8e01"
    private const val CARTS_SHA = "77b199cbc0ea19e9e69261a176303b211a45531e4f4be9f453deb16f929dfba2"
    private const val PREFIX = "__PZ_PRIVATE_OWN_REFS_54d62c15_"
    private val platform = J2SEPlatform()
    private val canonicalTable =
        (platform.newTable() as KahluaTableImpl).also { TableLib.register(platform, it) }
    private val canonicalPairs =
        (canonicalTable.delegate["table"] as KahluaTableImpl).delegate["pairs"].also {
            require(it?.javaClass == TableLib::class.java)
        }
    private val canonicalIpairs =
        (canonicalTable.delegate["table"] as KahluaTableImpl).delegate["ipairs"].also {
            require(it?.javaClass == TableLib::class.java)
        }
    private val canonicalMeta =
        (platform.newTable() as KahluaTableImpl)
            .also { BaseLib.register(it) }
            .delegate["getmetatable"]

    private data class Binding(
        val owner: KahluaTableImpl,
        val expected: KahluaTableImpl,
        val keys: Array<String>,
        val values: Array<Any>,
    )

    private data class ConstantMap(
        val key: String,
        val descriptor: KahluaTableImpl,
        val map: KahluaTableImpl,
        val values: KahluaTableImpl,
        val keys: Array<String>,
        val expected: Array<Any>,
    )

    private data class ConstantTree(
        val owner: KahluaTableImpl,
        val constants: KahluaTableImpl,
        val maps: Array<ConstantMap>,
    )

    private class Token(val bindings: Array<Binding>, val tree: ConstantTree? = null)

    private data class Site(
        val key: String,
        val declaration: String,
        val declarationReplacement: String,
        val loops: String,
        val arguments: String,
        val requiredConstants: Set<String>,
        val arity: Int,
        val ownerParameters: Int = 0,
        val parametric: Int = 0,
    ) {
        val marker = PREFIX + key + "__"
        val local = "toolkitPrivateOwnRefs" + key
    }

    private val bcLoop =
        "for name, expected in pairs(proximityMethods) do if proximity[name] ~= expected then return false end end"
    private val fridgeLoop =
        """for name, callback in pairs(functions) do if owner[name] ~= callback then return false end end
        for name, captured in pairs(constants) do
            local map = captured.map
            if owner[name] ~= map or getmetatable(map) ~= nil then return false end
            for key, value in pairs(captured.values) do if map[key] ~= value then return false end end
            for key, value in pairs(map) do if captured.values[key] ~= value then return false end end
        end"""
    private val cartsLoops =
        "for name, value in pairs(methods) do if class[name] ~= value then return false,\"cart_method_changed:\"..name end end\n    for name, value in pairs(coreMethods) do if (core[name] or false) ~= value then return false,\"cart_helper_changed:\"..name end end"
    private val classLoop =
        "for name, method in pairs(methods) do if class[name] ~= method then return false end end"
    private val radioLoop =
        "for name, method in pairs(radioMethods) do if (action[name] or false) ~= method then return end end"
    private val nativeHelpersLoop =
        """for name, value in pairs(snapshot.helpers) do
        if (action[name] or false) ~= value then
            local audited = snapshot.class == ISInventoryTransferAction and name == "getNotFullFloorSquare"
                and transferFloorHelper and value == transferFloorHelper.previous
                and action[name] == transferFloorHelper.replacement
                and instanceof(action.destContainer, "ItemContainer") and action.destContainer:getType() ~= "floor"
            if not audited then return false end
        end
    end"""
    private val classLifecycleLoop =
        "for _, name in ipairs(lifecycle) do if class[name] ~= methods[name] then return false end end"
    private val nativeLifecycleLoop =
        """for _, name in ipairs(lifecycle) do
        if action[name] ~= snapshot.methods[name] and not (name == "stop" and action.Type == "ISInventoryTransferAction"
            and Toolkit.BulkActions and Toolkit.BulkActions.isGuardedTransfer(action, snapshot.methods.stop)) then return false end
    end"""
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
                "owner, functions, constants",
                setOf("TurnOffFridges", "MODULE", "AUTO_KEY"),
                3,
            ),
            Site(
                "Class",
                "local function classUnchanged(class, methods)\n",
                "local toolkitPrivateOwnRefsClass; local function classUnchanged(class, methods)\n",
                classLoop,
                "class, methods",
                setOf("pairs", "ipairs"),
                0,
                2,
                1,
            ),
            Site(
                "ClassLifecycle",
                "local function classUnchanged(class, methods)\n",
                "local toolkitPrivateOwnRefsClassLifecycle; local function classUnchanged(class, methods)\n",
                classLifecycleLoop,
                "class, methods, lifecycle, toolkitPrivateLifecycleIpairs",
                setOf("pairs", "ipairs"),
                0,
                2,
                4,
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
    private val policySites =
        listOf(
            Site(
                "Radio",
                "local function radioResources(action, projectionIndependent)\n",
                "local toolkitPrivateOwnRefsRadio; local function radioResources(action, projectionIndependent)\n",
                radioLoop,
                "action, radioMethods",
                setOf("mode", "device", "radio"),
                0,
                2,
                2,
            ),
            Site(
                "NativeHelpers",
                "local function nativeMatches(action, snapshot, observingCleanup)\n",
                "local toolkitPrivateOwnRefsNativeHelpers; local function nativeMatches(action, snapshot, observingCleanup)\n",
                nativeHelpersLoop,
                "action, toolkitPrivateExpectedHelpers, toolkitPrivateHelperPairs",
                setOf("helpers", "getNotFullFloorSquare", "isCleanupPickup"),
                0,
                3,
                3,
            ),
            Site(
                "NativeLifecycle",
                "local function nativeMatches(action, snapshot, observingCleanup)\n",
                "local toolkitPrivateOwnRefsNativeLifecycle; local function nativeMatches(action, snapshot, observingCleanup)\n",
                nativeLifecycleLoop,
                "action, snapshot, lifecycle, toolkitPrivateLifecycleIpairs",
                setOf("stop", "isGuardedTransfer", "methods"),
                0,
                3,
                5,
            ),
        )

    private fun filename(path: String) = path.replace('\\', '/').substringAfterLast('/')

    private fun sites(path: String) =
        when (filename(path)) {
            "ActionQueueCompat.lua" -> compatSites
            "ActionQueueCarts.lua" -> cartSites
            "ActionQueuePolicy.lua" -> policySites
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

    // A source-owned plain metadata tree; every value is re-read on every visit.
    private fun captureFridge(env: KahluaTableImpl, values: Array<Any?>): Token? {
        if (env.delegate["getmetatable"] !== canonicalMeta || values.size != 3) return null
        val base = capture(env, arrayOf(values[0], values[1])) ?: return null
        val owner = base.bindings.single().owner
        val constants = ordinary(values[2]) ?: return null
        if (constants.metatable != null || constants.delegate.size != 2) return null
        val maps = ArrayList<ConstantMap>()
        for ((rawKey, rawDescriptor) in constants.delegate) {
            val key = rawKey as? String ?: return null
            val descriptor = ordinary(rawDescriptor) ?: return null
            if (descriptor.metatable != null || descriptor.delegate.size != 2) return null
            val map = ordinary(descriptor.delegate["map"]) ?: return null
            val expected = ordinary(descriptor.delegate["values"]) ?: return null
            if (
                map.metatable != null ||
                    expected.metatable != null ||
                    expected.delegate.isEmpty() ||
                    expected.delegate.size > 64
            )
                return null
            val entries = expected.delegate.entries.toList()
            if (
                entries.any {
                    it.key !is String || it.value == null || (it.value as? Double)?.isNaN() == true
                }
            )
                return null
            maps.add(
                ConstantMap(
                    key,
                    descriptor,
                    map,
                    expected,
                    entries.map { it.key as String }.toTypedArray(),
                    entries.map { it.value!! }.toTypedArray(),
                ),
            )
        }
        return Token(base.bindings, ConstantTree(owner, constants, maps.toTypedArray()))
    }

    private fun treeMatches(tree: ConstantTree?, env: KahluaTableImpl): Boolean {
        if (tree == null) return true
        if (
            env.delegate["getmetatable"] !== canonicalMeta ||
                ordinary(tree.constants) !== tree.constants ||
                tree.constants.metatable != null ||
                tree.constants.delegate.size != tree.maps.size
        )
            return false
        for (captured in tree.maps) {
            if (
                tree.constants.delegate[captured.key] !== captured.descriptor ||
                    ordinary(captured.descriptor) !== captured.descriptor ||
                    captured.descriptor.metatable != null ||
                    captured.descriptor.delegate.size != 2 ||
                    captured.descriptor.delegate["map"] !== captured.map ||
                    captured.descriptor.delegate["values"] !== captured.values ||
                    tree.owner.delegate[captured.key] !== captured.map
            )
                return false
            if (
                ordinary(captured.map) !== captured.map ||
                    ordinary(captured.values) !== captured.values ||
                    captured.map.metatable != null ||
                    captured.values.metatable != null ||
                    captured.map.delegate.size != captured.keys.size ||
                    captured.values.delegate.size != captured.keys.size
            )
                return false
            for (i in captured.keys.indices) {
                val key = captured.keys[i]
                val value = captured.expected[i]
                if (captured.values.delegate[key] !== value || captured.map.delegate[key] !== value)
                    return false
            }
        }
        return true
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

    // Exact supported-jar subset: KahluaTableImpl.rawget follows the raw
    // metatable chain on ABSENT keys; tableget then resolves a raw __index entry.
    // No callbacks/native tableget/rawget are invoked. A sentinel distinguishes an
    // unsupported lookup from a supported nil result. Bounds avoid raw/meta cycles.
    private val unsupported = Any()
    private val canonicalFalse: Any = java.lang.Boolean.FALSE
    private const val LOOKUP_LIMIT = 16

    private fun rawPure(value: Any?, key: Any): Any? {
        var current = value
        repeat(LOOKUP_LIMIT) {
            val table = ordinary(current) ?: return unsupported
            if (table.delegate.containsKey(key)) return table.delegate[key]
            current = table.metatable ?: return null
        }
        return unsupported
    }

    private fun tableGetPure(value: Any?, key: String): Any? {
        var current = value
        repeat(LOOKUP_LIMIT) {
            val table = ordinary(current) ?: return unsupported
            val direct = rawPure(table, key)
            if (direct === unsupported || direct != null) return direct
            val meta = table.metatable ?: return null
            val index = rawPure(meta, "__index")
            if (index === unsupported) return unsupported
            if (index == null) return null
            if (ordinary(index) == null) return unsupported
            current = index
        }
        return unsupported
    }

    private fun dynamicMatches(owner: Any?, expectedValue: Any?, normalized: Boolean): Boolean {
        if (ordinary(owner) == null) return false
        val expected = ordinary(expectedValue) ?: return false
        if (expected.metatable != null || expected.delegate.size > 128) return false
        for (entry in expected.delegate.entries) {
            val key = entry.key as? String ?: return false
            val value = entry.value ?: return false
            if ((value as? Double)?.isNaN() == true) return false
            var actual = tableGetPure(owner, key)
            if (actual === unsupported) return false
            // KahluaUtil.boolEval checks null and the canonical FALSE reference only.
            if (normalized && (actual == null || actual === canonicalFalse)) actual = canonicalFalse
            if (actual !== value) return false
        }
        return true
    }

    private val lifecycleIndexes = Array<Any>(65) { it.toDouble() }

    private fun lifecycleMatches(
        owner: Any?,
        expectedOrSnapshot: Any?,
        fieldsValue: Any?,
        snapshot: Boolean,
    ): Boolean {
        if (ordinary(owner) == null) return false
        val fields = ordinary(fieldsValue) ?: return false
        val expected =
            if (snapshot) {
                val captured = ordinary(expectedOrSnapshot) ?: return false
                if (captured.metatable != null || !captured.delegate.containsKey("methods"))
                    return false
                ordinary(captured.delegate["methods"]) ?: return false
            } else ordinary(expectedOrSnapshot) ?: return false
        for (i in 1..64) {
            val field = rawPure(fields, lifecycleIndexes[i])
            if (field === unsupported) return false
            if (field == null) return true
            val name = field as? String ?: return false
            val actual = tableGetPure(owner, name)
            if (actual === unsupported) return false
            val value = tableGetPure(expected, name)
            if (
                value === unsupported ||
                    (actual as? Double)?.isNaN() == true ||
                    (value as? Double)?.isNaN() == true ||
                    actual !== value
            )
                return false
        }
        return false
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
                if (site.parametric == 0)
                    "if not ${site.local} then ${site.local} = (\"${site.marker}\")(${site.arguments}) end; if ${site.local}() ~= true then ${site.loops} end"
                else {
                    val prefix =
                        if (site.parametric >= 4) "local toolkitPrivateLifecycleIpairs = ipairs; "
                        else if (site.parametric == 3)
                            "local toolkitPrivateHelperPairs = pairs; local toolkitPrivateExpectedHelpers = snapshot.helpers; "
                        else ""
                    val fallback =
                        if (site.parametric >= 4)
                            site.loops.replace(
                                "ipairs(lifecycle)",
                                "toolkitPrivateLifecycleIpairs(lifecycle)",
                            )
                        else if (site.parametric == 3)
                            site.loops.replace(
                                "pairs(snapshot.helpers)",
                                "toolkitPrivateHelperPairs(toolkitPrivateExpectedHelpers)",
                            )
                        else site.loops
                    prefix +
                        "if not ${site.local} then ${site.local} = (\"${site.marker}\")() end; if ${site.local}(${site.arguments}) ~= true then $fallback end"
                }
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
                owner.numParams != site.ownerParameters ||
                    owner.isVararg ||
                    owner.prototypes.isNotEmpty() ||
                    !owner.constants.toSet().containsAll(site.requiredConstants)
            )
                return null
            pending.add(Triple(site, owner, index))
        }
        if (pending.map { it.second to it.third }.toSet().size != sites.size) return null
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
                val token =
                    if (authentic && site.parametric == 0) {
                        val values = Array(count) { frame.get(it) }
                        if (site.key == "Fridge") captureFridge(env, values)
                        else capture(env, values)
                    } else null
                val checker = JavaFunction { current, n ->
                    val actual = current.coroutine.getParentNoAssert(1)?.closure
                    val provenance =
                        authentic &&
                            caller != null &&
                            actual === caller &&
                            actual.prototype === owner &&
                            actual.env === env &&
                            trusted(env)
                    val same =
                        provenance &&
                            when {
                                site.parametric == 0 ->
                                    n == 0 && matches(token) && treeMatches(token?.tree, env)
                                site.parametric >= 4 ->
                                    n == 4 &&
                                        env.delegate["ipairs"] === canonicalIpairs &&
                                        current.get(3) === canonicalIpairs &&
                                        lifecycleMatches(
                                            current.get(0),
                                            current.get(1),
                                            current.get(2),
                                            site.parametric == 5,
                                        )
                                else ->
                                    n == (if (site.parametric == 3) 3 else 2) &&
                                        (site.parametric != 3 ||
                                            current.get(2) === canonicalPairs) &&
                                        dynamicMatches(
                                            current.get(0),
                                            current.get(1),
                                            site.parametric >= 2,
                                        )
                            }
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
                "ActionQueuePolicy.lua" -> POLICY_SHA
                else -> null
            }
        if (!enabled || selected == null || sha(text) != expected)
            return LuaCompiler.loadstring(text, path, environment)
        return bind(text, path, environment, selected)
            ?: LuaCompiler.loadstring(text, path, environment)
    }
}
