package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import java.io.BufferedReader
import java.io.StringReader
import java.security.MessageDigest
import java.util.HexFormat
import java.util.LinkedHashMap
import me.zed_0xff.zombie_buddy.Exposer
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.KahluaThread
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.LuaClosure
import se.krka.kahlua.vm.Prototype
import se.krka.kahlua.vm.UpValue
import zombie.Lua.KahluaNumberConverter
import zombie.Lua.LuaManager
import zombie.Lua.LuaEventManager

/** Full selected sources are compiled, never copied snippets. Capture-cell
 * fixtures below use their actual prototypes; they do not execute mod startup.
 */
object HandEventRecipeSourceChecks {
    private fun table() = KahluaTableImpl(LinkedHashMap<Any, Any?>())
    private val noArgs = emptyArray<Any?>()

    private fun filename(prototype: Prototype, name: String) {
        prototype.filename = name
        prototype.prototypes.forEach { filename(it, name) }
    }

    private fun source(variable: String, sha: String): String {
        val path = System.getenv(variable)?.let(Path::of) ?: error("Set $variable to the selected mod source")
        return sourcePath(path, sha, variable)
    }

    private fun sourcePath(path: Path, sha: String, label: String): String {
        check(Files.isRegularFile(path)) { "Selected source is missing: $label" }
        val bytes = Files.readAllBytes(path)
        check(HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)) == sha) {
            "Selected source changed: $label"
        }
        return String(bytes, Charsets.UTF_8)
    }

    private fun adler(text: String): Long {
        var a = 1L
        var b = 0L
        // Same UTF-16 units and readLine normalization as SourceProof.
        for (line in text.lineSequence().toList().let { if (text.endsWith("\n")) it.dropLast(1) else it }) {
            for (unit in line.removeSuffix("\r") + "\n") {
                a = (a + unit.code) % 65521
                b = (b + a) % 65521
            }
        }
        return b * 65536 + a
    }

    private fun closureSite(root: Prototype, pc: Int, child: Int, register: Int, bindings: IntArray) {
        val word = root.code[pc]
        check(word and 63 == 36 && word ushr 14 == child && word ushr 6 and 255 == register) {
            "Selected source closure site changed: $pc"
        }
        check(root.prototypes[child].numUpvalues == bindings.size)
        for (slot in bindings.indices) {
            val binding = root.code[pc + slot + 1]
            check(binding and 63 == 0 && binding ushr 23 == bindings[slot]) {
                "Selected source capture binding changed: $pc/$slot"
            }
        }
    }

    @JvmStatic fun main(args: Array<String>) {
        val snowSource = source("PZ_TEST_SNOW_SOURCE", "8176c7cb67d3a59304f4a2170c883a3038f723faf59ff174078f8c424a8e38c3")
        val neatSource = source("PZ_TEST_NEAT_EQUIPPED_SOURCE", "8d9415b491d408315eaa6d82077e9b30d477da73fa97e244e4d97f9d4dc18bea")
        val cartsSource = source("PZ_TEST_CART_HOLDER_SOURCE", "d46ea39f3d4aee569bb87d3241d464eb77552faae505e3adfb742f4991117fe7")
        val fishingSource = sourcePath(Path.of("media/lua/client/Fishing/FishingHandler.lua"),
            "6975228698ab3219b4dec4838b6171ecad7645e6c49265b894f8c76d6b4b02cf", "FishingHandler.lua")
        check(LuaCaptureFacts.SUPPORTED) { "Native capture facts unsupported" }
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = LuaManager.platform.newEnvironment()
        val converters = KahluaConverterManager()
        KahluaNumberConverter.install(converters)
        LuaManager.exposer = LuaManager.Exposer(converters, LuaManager.platform, LuaManager.env)
        Exposer.addClassWithGlobalLuaMethod(LuaCaptureFacts::class.java)
        Exposer.addClassWithGlobalLuaMethod(QueueEquipEventRegistry::class.java)
        Exposer.afterExposeAll()
        val thread = KahluaThread(LuaManager.platform, LuaManager.env).apply { debugOwnerThread = Thread.currentThread() }
        LuaManager.thread = thread
        fun run(text: String) = thread.call(LuaCompiler.loadstring(text, "hand-recipe-check", LuaManager.env), noArgs)
        fun compile(text: String, name: String) = LuaCompiler.loadstring(text, name, LuaManager.env).prototype.also { filename(it, name) }
        val snow = compile(snowSource, "ISnow_CharSnow.lua")
        val neat = compile(neatSource, "NEQ_HideEquipped.lua")
        val carts = compile(cartsSource, "HolderRegistry.lua")
        val fishing = compile(fishingSource, "FishingHandler.lua")
        // Native compiler creation instructions prove the slot interpretation.
        // Snow: root r54=swapped, r98=releaseItems, r149=onEquipChange.
        closureSite(snow, 477, 52, 98, intArrayOf(54, 56, 70))
        closureSite(snow, 729, 80, 149, intArrayOf(98))
        // Neat: root r0=State, r2=H, r3=characterPane.
        closureSite(neat, 20, 0, 3, intArrayOf())
        closureSite(neat, 21, 1, 4, intArrayOf(0, 3))
        closureSite(neat, 53, 10, 14, intArrayOf(0, 2))
        // Carts: root r0=HolderRegistry, r1=holders. Child 12 is specifically
        // the anonymous closure at the OnEquipPrimary.Add creation site.
        closureSite(carts, 26, 3, 6, intArrayOf(1))
        closureSite(carts, 74, 12, 7, intArrayOf(0))
        // Fishing calls public global helpers, with no private captures.
        closureSite(fishing, 24, 1, 1, intArrayOf())
        closureSite(fishing, 35, 2, 1, intArrayOf())
        closureSite(fishing, 39, 3, 1, intArrayOf())
        check(snowSource.contains("local swapped = {}") && snowSource.contains("Events.OnEquipPrimary.Add(onEquipChange)"))
        check(neatSource.contains("Events.OnEquipPrimary.Add(onEquipmentChanged)"))
        check(cartsSource.contains("Events.OnEquipPrimary.Add(function(character, item)\n        HolderRegistry.handleEquipPrimary(character, item)"))

        val project = Path.of(System.getProperty("pz.test.project"))
        val modulePath = project.resolve("PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueHandEventRecipes.lua")
        val recipes = thread.call(LuaClosure(compile(Files.readString(modulePath), "ActionQueueHandEventRecipes.lua"), LuaManager.env), noArgs) as KahluaTableImpl
        fun factory(name: String, vararg values: Any?): Any? = thread.call(recipes.delegate[name], values)
        fun match(callback: LuaClosure, recipe: Any?): Any? = thread.call(LuaManager.env.rawget("toolkitLuaCaptureFactsMatch"), arrayOf(callback, recipe))
        fun cell(value: Any?) = UpValue(null, 0).apply { setValue(value) }
        fun captured(prototype: Prototype, vararg values: Any?): LuaClosure {
            check(prototype.numUpvalues == values.size)
            return LuaClosure(prototype, LuaManager.env).apply {
                for (index in values.indices) upvalues[index] = cell(values[index])
            }
        }
        for ((kind, text) in listOf("snow" to snowSource, "neat" to neatSource, "carts" to cartsSource, "fishing" to fishingSource)) {
            val metadata = factory("source", kind) as KahluaTableImpl
            check((metadata.delegate["adler"] as Double).toLong() == adler(text))
            metadata.delegate["adler"] = 0.0
            check(((factory("source", kind) as KahluaTableImpl).delegate["adler"] as Double).toLong() == adler(text))
        }
        check(factory("source", "unknown") == null)

        val swapped = table()
        val release = captured(snow.prototypes[52], swapped, table(), "unused setItemStage capture")
        val onSnow = captured(snow.prototypes[80], release)
        val snowRecipe = factory("snow")
        check(match(onSnow, snowRecipe) == true)
        swapped.delegate[table()] = false
        check(match(onSnow, snowRecipe) == false) { "Nonempty swapped became absent" }
        swapped.delegate.clear()
        val detached = swapped
        val fresh = table()
        release.upvalues[0].setValue(fresh)
        detached.delegate[table()] = true
        check(match(onSnow, snowRecipe) == true) { "Detached swapped retained authority" }
        fresh.delegate[table()] = true
        check(match(onSnow, snowRecipe) == false) { "Live swapped capture was cached" }
        fresh.delegate.clear()
        val releaseWord = release.prototype.code[0]
        release.prototype.code[0] = releaseWord xor 64
        check(match(onSnow, snowRecipe) != true) { "Nested releaseItems fingerprint was cached" }
        release.prototype.code[0] = releaseWord
        check(match(onSnow, snowRecipe) == true)

        val state = table()
        val hide = table()
        val onNeat = captured(neat.prototypes[10], state, hide)
        val neatRecipe = factory("neat", state, hide)
        check(match(onNeat, neatRecipe) == true)
        onNeat.upvalues[0].setValue(table())
        check(match(onNeat, neatRecipe) == false) { "Unrelated State module passed identity" }
        onNeat.upvalues[0].setValue(state)
        onNeat.upvalues[1].setValue(table())
        check(match(onNeat, neatRecipe) == false) { "Unrelated H module passed identity" }
        onNeat.upvalues[1].setValue(hide)
        val pane = captured(neat.prototypes[0])
        val refresh = captured(neat.prototypes[1], state, pane)
        check(match(refresh, factory("neatRefresh", state)) == true)
        refresh.upvalues[1].setValue(onNeat)
        check(match(refresh, factory("neatRefresh", state)) != true)

        val holder = table()
        val onCarts = captured(carts.prototypes[12], holder)
        val cartsRecipe = factory("carts", holder)
        check(match(onCarts, cartsRecipe) == true)
        onCarts.upvalues[0].setValue(table())
        check(match(onCarts, cartsRecipe) == false) { "Foreign captured HolderRegistry passed identity" }
        onCarts.upvalues[0].setValue(holder)
        val holders = table()
        val holderKey = captured(carts.prototypes[3], holders)
        holder.delegate["isHolderKey"] = holderKey
        val emptyHolderRecipe = factory("cartsHoldersEmpty")
        check(match(onCarts, emptyHolderRecipe) == true)
        val key = 17.0
        val keyRecipe = factory("cartsHolderKey", key)
        check(match(holderKey, keyRecipe) == true)
        holders.delegate[key] = false
        check(match(holderKey, keyRecipe) == false) { "Non-nil holder entry became absent" }
        check(match(onCarts, emptyHolderRecipe) == false) { "Nested holders were not inspected" }
        holders.delegate[key] = null
        check(match(holderKey, keyRecipe) == false) { "Malformed explicit-null holder entry became absent" }
        holders.delegate.remove(key)
        check(match(holderKey, keyRecipe) == true)
        holderKey.upvalues[0].setValue(table())
        holders.delegate[key] = true
        check(match(holderKey, keyRecipe) == true) { "Detached holders retained authority" }
        check(match(onCarts, emptyHolderRecipe) == true)
        holder.delegate["isHolderKey"] = onCarts
        check(match(onCarts, emptyHolderRecipe) != true) { "Wrong holder predicate retained authority" }
        // Execute only the tiny native Fishing declaration/registration chunk.
        // Registration doubles retain callbacks; no handler or actor getter runs.
        val registered = LinkedHashMap<String, Any?>()
        val events = table()
        for (name in listOf("OnGameStart", "OnEquipPrimary")) {
            val event = table()
            event.delegate["Add"] = JavaFunction { frame, count ->
                check(count == 1 && registered.put(name, frame.get(0)) == null)
                0
            }
            events.delegate[name] = event
        }
        LuaManager.env.rawset("Events", events)
        LuaManager.env.rawset("Fishing", null)
        thread.call(LuaClosure(fishing, LuaManager.env), noArgs)
        val fishingModule = LuaManager.env.rawget("Fishing") as KahluaTableImpl
        val fishingHandler = fishingModule.delegate["Handler"] as KahluaTableImpl
        val onFishing = fishingHandler.delegate["onEquipPrimary"] as LuaClosure
        val handleFishing = fishingHandler.delegate["handleFishing"] as LuaClosure
        val validFishing = fishingHandler.delegate["isFishingValid"] as LuaClosure
        check(registered["OnEquipPrimary"] === onFishing)
        check(onFishing.prototype === fishing.prototypes[1] && handleFishing.prototype === fishing.prototypes[2]
            && validFishing.prototype === fishing.prototypes[3])
        check(match(onFishing, factory("fishing")) == true)
        check(match(handleFishing, factory("fishingHandle")) == true)
        check(match(validFishing, factory("fishingValid")) == true)
        check(onFishing.prototype.constants.contentEquals(arrayOf("isLocal", "Fishing", "Handler", "handleFishing")))
        check("isFishingValid" in handleFishing.prototype.constants)
        check((factory("source", "fishing") as KahluaTableImpl).delegate["mod"] == null)
        // End-to-end opt-in observation: real Lua composition and SourceProof,
        // real named event registry, actual-source prototype/cell fixtures.
        LuaManager.exposer.exposeGlobalClassFunction(LuaManager.env, QueueLeafTransferFacts::class.java,
            QueueLeafTransferFacts::class.java.getMethod("luaMetatableMatches", Any::class.java, Any::class.java), "toolkitLuaMetatableMatches")
        LuaManager.exposer.exposeGlobalClassFunction(LuaManager.env, LuaManager.GlobalObject::class.java,
            LuaManager.GlobalObject::class.java.getMethod("getFilenameOfClosure", LuaClosure::class.java), "getFilenameOfClosure")
        var opens = 0
        var closes = 0
        var corruptSnow = false
        var duringOpen: (() -> Unit)? = null
        fun reader(text: String): KahluaTableImpl {
            opens++
            val input = BufferedReader(StringReader(text))
            return table().apply {
                delegate["readLine"] = JavaFunction { frame, _ -> frame.push(input.readLine()); 1 }
                delegate["close"] = JavaFunction { _, _ -> closes++; input.close(); 0 }
            }
        }
        LuaManager.env.rawset("getModFileReader", JavaFunction { frame, count ->
            check(count == 3 && frame.get(2) == false)
            val kind = when (frame.get(0)) {
                "ImmersiveSnow" -> "snow"
                "NeatUI_Equipment" -> "neat"
                "SaucedCarts" -> "carts"
                else -> error("Unexpected source reader mod")
            }
            val metadata = factory("source", kind) as KahluaTableImpl
            check(frame.get(1) == metadata.delegate["path"])
            duringOpen?.also { duringOpen = null; it() }
            val text = when (kind) { "snow" -> snowSource + if (corruptSnow) "\n-- changed" else ""; "neat" -> neatSource; else -> cartsSource }
            frame.push(reader(text)); 1
        })
        LuaManager.env.rawset("getGameFilesInput", JavaFunction { frame, count ->
            check(count == 1 && frame.get(0) == "media/lua/client/Fishing/FishingHandler.lua")
            frame.push(reader(fishingSource)); 1
        })
        run("PZSurvivorToolkit={}")
        val luaRoot = project.resolve("PZSurvivorToolkit/42/media/lua")
        val modules = LinkedHashMap<String, Any?>()
        fun loadModule(name: String, relative: String): Any? {
            val file = luaRoot.resolve(relative)
            return thread.call(LuaClosure(compile(Files.readString(file), file.fileName.toString()), LuaManager.env), noArgs).also { modules[name] = it }
        }
        LuaManager.env.rawset("require", JavaFunction { frame, count ->
            check(count == 1 && modules.containsKey(frame.get(0))) { "Unexpected require ${frame.get(0)}" }
            frame.push(modules[frame.get(0)]); 1
        })
        loadModule("PZSurvivorToolkit/SourceProof", "shared/PZSurvivorToolkit/SourceProof.lua")
        modules["PZSurvivorToolkit/ActionQueueHandEventRecipes"] = recipes
        val handEvents = loadModule("PZSurvivorToolkit/ActionQueueHandEvents", "client/PZSurvivorToolkit/ActionQueueHandEvents.lua") as KahluaTableImpl
        fun newFacts() = loadModule("PZSurvivorToolkit/ActionQueueHandEffectFacts", "client/PZSurvivorToolkit/ActionQueueHandEffectFacts.lua") as KahluaTableImpl
        LuaManager.env.rawset("NEQ_State", state)
        LuaManager.env.rawset("NEQ_HideEquipped", hide)
        state.delegate["hideEquipped"] = false
        hide.delegate["refreshFor"] = refresh
        refresh.upvalues[1].setValue(pane)
        holder.delegate["isHolderKey"] = holderKey
        val liveHolders = holderKey.upvalues[0].getValue() as KahluaTableImpl
        liveHolders.delegate.clear()
        LuaEventManager.Reset()
        LuaEventManager.register(LuaManager.platform, LuaManager.env)
        val primary = LuaEventManager.AddEvent("OnEquipPrimary")
        val secondary = LuaEventManager.AddEvent("OnEquipSecondary")
        primary.callbacks.addAll(listOf(onSnow, onNeat, onCarts, onFishing))
        secondary.callbacks.addAll(listOf(onSnow, onNeat))
        fun snapshot() = thread.call(handEvents.delegate["registeredCallbacks"], noArgs) as KahluaTableImpl
        var effects = newFacts()
        val actor = table().apply { delegate["getPrimaryHandItem"] = JavaFunction { _, _ -> error("Actor getter executed") } }
        fun observe(snapshot: Any? = snapshot()): KahluaTableImpl? = thread.call(effects.delegate["observe"], arrayOf(actor, snapshot)) as KahluaTableImpl?
        fun fact(result: KahluaTableImpl, profile: String, name: String): Any? {
            val rows = result.delegate["callbacks"] as KahluaTableImpl
            val row = rows.delegate.values.map { it as KahluaTableImpl }.first { it.delegate["profile"] == profile }
            return (row.delegate["facts"] as KahluaTableImpl).delegate[name]
        }
        val observed = checkNotNull(observe()) { "Real source composition returned unknown" }
        check(observed.delegate["status"] == "observed" && observed.delegate["effectComplete"] == false)
        check(fact(observed, "snow", "swappedEmpty") == true && fact(observed, "carts", "holderQueryTableEmpty") == true)
        check(fact(observed, "neat", "captureBindingsMatch") == true && fact(observed, "neat", "hideEquipped") == false)
        check(fact(observed, "fishing", "managerTableEmpty") == true)
        fresh.delegate[table()] = true
        liveHolders.delegate[17.0] = false
        (fishingModule.delegate["ManagerInstances"] as KahluaTableImpl).delegate[0.0] = table()
        state.delegate["hideEquipped"] = true
        val changed = checkNotNull(observe())
        check(fact(changed, "snow", "swappedEmpty") == false && fact(changed, "carts", "holderQueryTableEmpty") == false)
        check(fact(changed, "fishing", "managerTableEmpty") == false && fact(changed, "neat", "hideEquipped") == true)
        release.upvalues[0].setValue(table())
        check(fact(checkNotNull(observe()), "snow", "swappedEmpty") == true)
        val unknown = run("return function() error('Unknown callback executed') end") as LuaClosure
        unknown.prototype.filename = "UnreviewedHandHandler.lua"
        val stale = snapshot()
        primary.callbacks.add(unknown)
        check(observe(stale) == null) { "Stale registry snapshot retained observation authority" }
        val partial = checkNotNull(observe())
        check(partial.delegate["status"] == "partial" && partial.delegate["effectComplete"] == false)
        primary.callbacks.remove(unknown)
        corruptSnow = true
        effects = newFacts()
        check(checkNotNull(observe()).delegate["status"] == "partial") { "Changed source bytes passed source pin" }
        corruptSnow = false
        effects = newFacts()
        val beforeReaderReentry = snapshot()
        duringOpen = { primary.callbacks.add(unknown) }
        check(observe(beforeReaderReentry) == null) { "Reader reentry hid registry mutation" }
        primary.callbacks.remove(unknown)
        check(opens == closes) { "End-to-end source reader leaked" }
        // No gameplay callbacks are executed by these checks or by matching.
        run("assert(toolkitLuaCaptureFactsApiMatches(toolkitLuaCaptureFactsMatch))")
        println("HAND_EVENT_RECIPE_SOURCE_CHECKS_PASS selected_sources=true native_compile=true root_capture_bindings=true capture_cell_fixtures=true opt_in_composition=true native_registry=true third_party_startup_executed=false fishing_declarations=true gameplay_callbacks_executed=false")
    }
}
