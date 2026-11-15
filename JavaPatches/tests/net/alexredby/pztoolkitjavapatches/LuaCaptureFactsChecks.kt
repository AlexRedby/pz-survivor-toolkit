package net.alexredby.pztoolkitjavapatches

import java.util.LinkedHashMap
import me.zed_0xff.zombie_buddy.Exposer
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.integration.expose.LuaJavaInvoker
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.KahluaThread
import se.krka.kahlua.vm.LuaClosure
import sun.misc.Unsafe
import zombie.Lua.KahluaNumberConverter
import zombie.Lua.LuaManager
import zombie.characters.IsoPlayer

/** Real native compiler/cells/invokers, with no observed Lua callback execution. */
object LuaCaptureFactsChecks {
    private fun table(vararg entries: Pair<Any, Any?>) = KahluaTableImpl(LinkedHashMap<Any, Any?>().apply { putAll(entries) })
    private fun array(vararg values: Any?) = table(*values.mapIndexed { i, value -> (i + 1).toDouble() as Any to value }.toTypedArray())
    private fun rule(slot: Int, test: String, vararg fields: Pair<Any, Any?>) =
        table("slot" to slot.toDouble(), "test" to test, *fields)
    private fun recipe(closure: LuaClosure, vararg rules: KahluaTableImpl) = table(
        "fingerprint" to LuaPrototypeFingerprint.tree(closure.prototype),
        "parameters" to closure.prototype.numParams.toDouble(), "upvalues" to closure.prototype.numUpvalues.toDouble(),
        "captures" to array(*rules))
    @JvmStatic fun forwarding(a: Any?, b: Any?): Boolean? = LuaCaptureFacts.match(a, b)
    @JvmStatic fun foreign(a: Any?, b: Any?): Boolean = error("foreign invoker executed")
    private class Bomb {
        var armed = false
        override fun hashCode(): Int { check(!armed) { "foreign hashCode executed" }; return "safe".hashCode() }
        override fun equals(other: Any?): Boolean = error("foreign equals executed")
        override fun toString(): String = error("foreign toString executed")
    }

    @JvmStatic fun main(args: Array<String>) {
        check(LuaCaptureFacts.SUPPORTED)
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = LuaManager.platform.newEnvironment()
        val converters = KahluaConverterManager(); KahluaNumberConverter.install(converters)
        LuaManager.exposer = LuaManager.Exposer(converters, LuaManager.platform, LuaManager.env)
        Exposer.addClassWithGlobalLuaMethod(LuaCaptureFacts::class.java); Exposer.afterExposeAll()
        val thread = KahluaThread(LuaManager.platform, LuaManager.env).apply { debugOwnerThread = Thread.currentThread() }
        LuaManager.thread = thread
        fun run(text: String): Any? = thread.call(LuaCompiler.loadstring(text, "capture-facts-check", LuaManager.env), emptyArray<Any?>())
        val fixtures = run("""
            calls=0
            local state={}
            local marker={}
            local inner=function(actor) calls=calls+1;return state[actor] end
            local callback=function(actor) calls=calls+1;if marker then return inner(actor) end end
            local registry={fn=inner}
            local outer=function(actor) calls=calls+1;return registry.fn(actor) end
            return {state=state,marker=marker,inner=inner,callback=callback,outer=outer,registry=registry,
                rebind=function(value) state=value end}
        """.trimIndent()) as KahluaTableImpl
        val inner = fixtures.delegate["inner"] as LuaClosure
        val callback = fixtures.delegate["callback"] as LuaClosure
        val outer = fixtures.delegate["outer"] as LuaClosure
        val state = fixtures.delegate["state"] as KahluaTableImpl
        val marker = fixtures.delegate["marker"] as KahluaTableImpl
        val registry = fixtures.delegate["registry"] as KahluaTableImpl
        fun slot(closure: LuaClosure, value: Any) = closure.upvalues.indexOfFirst { it.getValue() === value }.also { check(it >= 0) }
        val stateSlot = slot(inner, state)
        val markerSlot = slot(callback, marker)
        val innerSlot = slot(callback, inner)
        val registrySlot = slot(outer, registry)
        val helper = LuaManager.env.rawget("toolkitLuaCaptureFactsMatch")
        val checker = LuaManager.env.rawget("toolkitLuaCaptureFactsApiMatches")
        check(helper is LuaJavaInvoker && checker is LuaJavaInvoker)
        fun read(closure: Any? = inner, spec: Any? = recipe(inner, rule(stateSlot, "empty-table"))): Any? =
            thread.call(helper, arrayOf(closure, spec)).also { check(it == null || it is Boolean) { "Mutable capture escaped" } }
        val empty = recipe(inner, rule(stateSlot, "empty-table"))
        check(thread.call(checker, arrayOf(helper)) == true && read() == true)
        val unsafe = Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null) as Unsafe
        val player = unsafe.allocateInstance(IsoPlayer::class.java) as IsoPlayer
        val absent = recipe(inner, rule(stateSlot, "absent-entry", "key" to player))
        check(read(spec = absent) == true)
        state.delegate[player] = false
        check(read(spec = empty) == false && read(spec = absent) == false)
        state.delegate[player] = null
        check(read(spec = absent) == false) { "Explicit malformed null map entry was treated as absent" }
        state.delegate.remove(player)
        for (key in listOf<Any>("safe", 3.0, false, marker, inner)) {
            val spec = recipe(inner, rule(stateSlot, "absent-entry", "key" to key))
            check(read(spec = spec) == true)
            state.delegate[key] = marker
            check(read(spec = spec) == false)
            state.delegate.remove(key)
        }
        for (key in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY)) {
            check(read(spec = recipe(inner, rule(stateSlot, "absent-entry", "key" to key))) == null)
        }
        for (scalar in listOf<Any>("scalar", 3.0, false, 3, 'x')) {
            check(read(spec = recipe(inner, rule(stateSlot, "identity", "value" to scalar))) == null)
        }
        val nested = recipe(callback, rule(markerSlot, "identity", "value" to marker), rule(innerSlot, "closure", "recipe" to empty))
        check(read(callback, nested) == true)
        val field = recipe(outer, rule(registrySlot, "field", "key" to "fn",
            "predicate" to table("test" to "closure", "recipe" to empty)))
        check(read(outer, field) == true)
        val orderedInputs = ArrayList<KahluaTableImpl>()
        fun accessOrderSchema(value: KahluaTableImpl): KahluaTableImpl {
            val copy = KahluaTableImpl(LinkedHashMap<Any, Any?>(16, 0.75f, true))
            for (entry in value.delegate.entries.toList().asReversed()) {
                copy.delegate[entry.key] = if (entry.value is KahluaTableImpl) accessOrderSchema(entry.value as KahluaTableImpl) else entry.value
            }
            orderedInputs.add(copy)
            return copy
        }
        val orderedSpec = accessOrderSchema(recipe(outer, rule(registrySlot, "field", "key" to "fn",
            "predicate" to table("test" to "closure", "recipe" to recipe(inner,
                rule(stateSlot, "empty-table"), rule(stateSlot, "absent-entry", "key" to "safe"))))))
        val schemaOrders = orderedInputs.map { it.delegate.keys.toList() }
        check(read(outer, orderedSpec) == true)
        check(orderedInputs.map { it.delegate.keys.toList() } == schemaOrders) {
            "Observation reordered supplied recipe, captures, rule or predicate maps"
        }
        val fieldBomb = Bomb()
        val ordered = KahluaTableImpl(LinkedHashMap<Any, Any?>(16, 0.75f, true).apply {
            put(fieldBomb, marker); put("fn", inner); put("other", marker)
        })
        fieldBomb.armed = true
        val registryCell = outer.upvalues[registrySlot]
        registryCell.setValue(ordered)
        val order = ordered.delegate.keys.toList()
        check(read(outer, field) == true && ordered.delegate.keys.toList() == order) {
            "Field observation reordered an access-order captured map"
        }
        registryCell.setValue(registry)
        registry.delegate.remove("fn"); check(read(outer, field) == null); registry.delegate["fn"] = inner
        registry.metatable = table(); check(read(outer, field) == null); registry.metatable = null
        registry.setRewriteTable(table()); check(read(outer, field) == null); registry.setRewriteTable(null)

        // The real Lua rebind closes over the same UpValue, and every query reads it anew.
        val fresh = table()
        thread.call(fixtures.delegate["rebind"], arrayOf(fresh))
        state.delegate[player] = marker
        check(read(spec = absent) == true && read(callback, nested) == true)
        fresh.delegate[player] = marker; check(read(spec = absent) == false)
        fresh.delegate.remove(player)
        val cell = inner.upvalues[stateSlot]
        cell.setValue("bad"); check(read(spec = empty) == null); cell.setValue(fresh)
        for (bad in listOf(KahluaTableImpl(HashMap<Any, Any?>()), table().apply { metatable = table() },
            table().apply { setRewriteTable(table()) })) {
            cell.setValue(bad); check(read(spec = empty) == null)
        }
        cell.setValue(fresh)
        val bomb = Bomb()
        fresh.delegate[bomb] = marker; bomb.armed = true
        check(read(spec = recipe(inner, rule(stateSlot, "absent-entry", "key" to "safe"))) == true)
        check(read(spec = recipe(inner, rule(stateSlot, "absent-entry", "key" to bomb))) == null)
        check(read(spec = recipe(inner, rule(stateSlot, "identity", "value" to bomb))) == false)
        cell.setValue(bomb)
        check(read(spec = recipe(inner, rule(stateSlot, "identity", "value" to bomb))) == true)
        cell.setValue(fresh)
        bomb.armed = false; fresh.delegate.remove(bomb)

        // Neither a false sibling nor a false parent can mask malformed nested data.
        val wrongIdentity = rule(markerSlot, "identity", "value" to fresh)
        val invalidNested = recipe(inner, rule(stateSlot, "empty-table")).apply { delegate["unknown"] = true }
        check(read(callback, recipe(callback, wrongIdentity, rule(innerSlot, "closure", "recipe" to invalidNested))) == null)
        cell.setValue("unsupported")
        check(read(callback, recipe(callback, wrongIdentity, rule(innerSlot, "closure", "recipe" to empty))) == null)
        cell.setValue(fresh)
        check(read(callback, recipe(callback, wrongIdentity, rule(innerSlot, "closure", "recipe" to empty))) == false)
        val missingNested = table("test" to "field", "key" to "missing", "predicate" to table("test" to "invalid"))
        check(read(outer, recipe(outer, rule(registrySlot, "field", "key" to "missing", "predicate" to missingNested))) == null)

        fun badRecipe(mutator: (KahluaTableImpl) -> Unit) {
            val spec = recipe(inner, rule(stateSlot, "empty-table")); mutator(spec); check(read(spec = spec) == null)
        }
        badRecipe { it.metatable = table() }
        badRecipe { it.setRewriteTable(table()) }
        badRecipe { it.delegate["extra"] = true }
        badRecipe { it.delegate.remove("parameters") }
        badRecipe { it.delegate["fingerprint"] = "A".repeat(64) }
        badRecipe { it.delegate["parameters"] = 0.5 }
        badRecipe { it.delegate["upvalues"] = Double.NaN }
        badRecipe { it.delegate["captures"] = array(*Array(257) { rule(stateSlot, "empty-table") }) }
        badRecipe { it.delegate["captures"] = table(2.0 to rule(stateSlot, "empty-table")) }
        badRecipe { it.delegate["captures"] = table("1" to rule(stateSlot, "empty-table")) }
        badRecipe { it.delegate["captures"] = array(rule(-1, "empty-table")) }
        badRecipe { it.delegate["captures"] = array(rule(inner.upvalues.size, "empty-table")) }
        badRecipe { it.delegate["captures"] = array(rule(stateSlot, "empty-table", "key" to "unexpected")) }
        badRecipe { it.delegate["captures"] = array(rule(stateSlot, "identity", "value" to null)) }
        badRecipe { it.delegate["captures"] = array(rule(stateSlot, "empty-table").apply { metatable = table() }) }
        badRecipe { spec -> spec.delegate["captures"] = array(rule(stateSlot, "closure", "recipe" to spec)) }
        val predicateCycle = table("test" to "field", "key" to "fn")
        predicateCycle.delegate["predicate"] = predicateCycle
        check(read(outer, recipe(outer, rule(registrySlot, "field", "key" to "fn", "predicate" to predicateCycle))) == null)
        var deep: KahluaTableImpl = table("test" to "empty-table")
        repeat(20) { deep = table("test" to "field", "key" to "x", "predicate" to deep) }
        check(read(outer, recipe(outer, rule(registrySlot, "field", "key" to "fn", "predicate" to deep))) == null)

        // One query must relate opaque values AND the actual live UpValue cells.
        // Distinct cells containing the same empty table are not a shared state owner.
        val aliases = run("""
            local a={};local b=a
            local first=function() return a end
            local second=function() return b end
            return {first=first,second=second,root=function() return first(),second() end}
        """.trimIndent()) as KahluaTableImpl
        val first = aliases.delegate["first"] as LuaClosure
        val second = aliases.delegate["second"] as LuaClosure
        val aliasRoot = aliases.delegate["root"] as LuaClosure
        val firstSlot = slot(aliasRoot, first); val secondSlot = slot(aliasRoot, second)
        fun aliasRecipe(label: String) = recipe(aliasRoot,
            rule(firstSlot,"closure","recipe" to recipe(first,rule(0,"empty-table",label to "state"))),
            rule(secondSlot,"closure","recipe" to recipe(second,rule(0,"empty-table",label to "state"))))
        check(read(aliasRoot,aliasRecipe("bind")) == true)
        check(read(aliasRoot,aliasRecipe("cell")) == false)
        val separate = second.upvalues[0]
        second.upvalues[0] = first.upvalues[0]
        check(read(aliasRoot,aliasRecipe("cell")) == true)
        second.upvalues[0] = separate
        separate.setValue(table())
        check(read(aliasRoot,aliasRecipe("bind")) == false)
        for (label in listOf("", "bad name", "x".repeat(65))) {
            check(read(first, recipe(first,rule(0,"empty-table","cell" to label))) == null)
        }
        val treeClosure = run("return function(x) return function() return x end end") as LuaClosure
        val treeSpec = recipe(treeClosure)
        check(LuaPrototypeFingerprint.leaf(treeClosure.prototype) == "unsupported")
        check(read(treeClosure,treeSpec) == true)
        val child = treeClosure.prototype.prototypes[0]
        val childCode = child.code[0]; child.code[0] = childCode xor 64
        check(read(treeClosure,treeSpec) == null); child.code[0] = childCode
        val children = child.prototypes
        child.prototypes = arrayOf(treeClosure.prototype)
        check(read(treeClosure,treeSpec) == null); child.prototypes = children
        check(read(treeClosure,treeSpec) == true)
        check(LuaPrototypeFingerprint.tree(inner.prototype) == LuaPrototypeFingerprint.leaf(inner.prototype))

        // Public prototype arrays and loaded closure environments are never cached.
        val code = inner.prototype.code[0]
        inner.prototype.code[0] = code xor 64; check(read(spec = empty) == null); inner.prototype.code[0] = code
        val instructions = inner.prototype.code
        inner.prototype.code = IntArray(65537); check(read(spec = empty) == null); inner.prototype.code = instructions
        inner.prototype.isVararg = true; check(read(spec = empty) == null); inner.prototype.isVararg = false
        val constants = inner.prototype.constants
        inner.prototype.constants = arrayOf(Bomb()); check(read(spec = empty) == null)
        inner.prototype.constants = arrayOf("x".repeat(16385)); check(read(spec = empty) == null)
        inner.prototype.constants = constants
        val childPrototypes = inner.prototype.prototypes
        inner.prototype.prototypes = arrayOf(callback.prototype); check(read(spec = empty) == null)
        inner.prototype.prototypes = childPrototypes
        val upvalue = inner.upvalues[stateSlot]
        inner.upvalues[stateSlot] = null; check(read(spec = empty) == null); inner.upvalues[stateSlot] = upvalue
        val foreignClosure = run("local state={};return function(actor) return not state[actor] end") as LuaClosure
        check(read(foreignClosure, empty) == null)
        val env = inner.env
        inner.env = table(); check(read(spec = empty) == null && read(callback, nested) == null); inner.env = env
        check(read(spec = empty) == true)
        check(read(null, empty) == null && read(table(), empty) == null)

        check(LuaCaptureFacts.match(inner, empty) == null && !LuaCaptureFacts.apiMatches(helper))
        check(thread.pcall(helper, arrayOf(inner))[0] == false)
        check(thread.pcall(helper, arrayOf(inner, empty, marker))[0] == false)
        thread.debugOwnerThread = null; check(read(spec = empty) == null)
        thread.debugOwnerThread = Thread.currentThread()
        var foreignResult: Boolean? = true
        Thread { foreignResult = LuaCaptureFacts.match(inner, empty) }.apply { start(); join() }
        check(foreignResult == null)
        val originalThread = LuaManager.thread
        LuaManager.thread = KahluaThread(LuaManager.platform, table()).apply { debugOwnerThread = Thread.currentThread() }
        check(read(spec = empty) == null); LuaManager.thread = originalThread
        val global = LuaManager.env as KahluaTableImpl
        global.metatable = table(); check(read(spec = empty) == null); global.metatable = null
        global.setRewriteTable(table()); check(read(spec = empty) == null); global.setRewriteTable(null)
        run("original=toolkitLuaCaptureFactsMatch;toolkitLuaCaptureFactsMatch=function(...) calls=calls+1;return original(...) end")
        check(read(spec = empty) == null && thread.call(checker, arrayOf(helper)) == false)
        global.delegate["toolkitLuaCaptureFactsMatch"] = helper
        for (name in listOf("foreign", "forwarding")) {
            global.delegate.remove("foreignAPI")
            LuaManager.exposer.exposeGlobalClassFunction(LuaManager.env, LuaCaptureFactsChecks::class.java,
                LuaCaptureFactsChecks::class.java.getMethod(name, Any::class.java, Any::class.java), "foreignAPI")
            val foreign = global.delegate["foreignAPI"]
            check(thread.call(checker, arrayOf(foreign)) == false)
            if (name == "forwarding") check(thread.call(foreign, arrayOf(inner, empty)) == null)
        }
        check(read(spec = empty) == true && LuaManager.env.rawget("calls") == 0.0)
        println("LUA_CAPTURE_FACTS_CHECKS_PASS native_closures=true fresh_captures=true callback_free=true authority=false")
    }
}
