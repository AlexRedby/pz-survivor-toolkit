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
        val cartsCoreSource = source("PZ_TEST_CART_CORE_SOURCE", "0c87b03db334209e8ce6564c2d9bfc3919178a52f78dece4434dd8bffd8a0394")
        val cartsForceDropSource = source("PZ_TEST_CART_FORCE_DROP_SOURCE", "f5debbd982bcbf64aeaad3482be8e20e2d3889cf6fca73688f4bb924f8394cce")
        val neatStateSource = source("PZ_TEST_NEAT_STATE_SOURCE", "e2a7bc2962bebfd7903d18a23800f160f6029190c8779409b78f0d2ad1b08dc3")
        val radioSource = sourcePath(Path.of("media/lua/client/RadioCom/ISRadioWindow.lua"),
            "704976f04b887feeb22e1c05dfc8a4350f6ed1ad27156a0d905e68978cd7ecfa", "ISRadioWindow.lua")
        val radioSelectedSource = source("PZ_TEST_RADIO_SELECTED_SOURCE", "e3dd48b56f456542bc8b5b8fc6b91b363f4f03520d5dba676165c79207c6f052")
        val bowPresentationSource = source("PZ_TEST_BOW_PRESENTATION_SOURCE", "f574636154adbbc94126ac79758a8730ed6df1e6c66aa9c3dcf9f0d02e935ede")
        val archeryStateSource = source("PZ_TEST_ARCHERY_STATE_SOURCE", "b6a921504e7e5145f5c04e84ce88d3a8411cc4b23450ca2fbb2b76665c6ad1e1")
        val bowReloadSource = source("PZ_TEST_BOW_RELOAD_SOURCE", "6516ba379c1d1341576100a79f78cc16bad93be842d52086183b0c03113ea859")
        val bowDurabilitySource = source("PZ_TEST_BOW_DURABILITY_SOURCE", "86958969a17e3fb394f3627c03f9223c2c3cacd9693c2dd00acba3164add8e46")
        val archeryContractSource = source("PZ_TEST_ARCHERY_CONTRACT_SOURCE", "83d98910332b6a75f4c6794f4bc641afc241e714a6fa310f89ae9c603c601fce")
        val equipWeaponSource = sourcePath(Path.of("media/lua/shared/TimedActions/ISEquipWeaponAction.lua"),
            "5aaf0e6942d83caed3df3acae63aa10c3b77bf9618208067b81d579a6e2bf66f", "ISEquipWeaponAction.lua")
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
        val cartsCore = compile(cartsCoreSource, "Core.lua")
        val cartsForceDrop = compile(cartsForceDropSource, "ForceDropGuard.lua")
        val neatState = compile(neatStateSource, "NEQ_State.lua")
        val radio = compile(radioSource, "ISRadioWindow.lua")
        val selectedRadio = compile(radioSelectedSource, "ISRadioWindow.lua")
        val bowPresentation = compile(bowPresentationSource, "WPANC_BowPresentation.lua")
        val archeryState = compile(archeryStateSource, "R5_AimState.lua")
        val bowReload = compile(bowReloadSource, "WPANC_BowReload.lua")
        val bowDurability = compile(bowDurabilitySource, "WPANC_BowDurability.lua")
        val archeryContract = compile(archeryContractSource, "WPANC_ArcheryContract.lua")
        val equipWeapon = compile(equipWeaponSource, "ISEquipWeaponAction.lua")
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
        closureSite(carts, 17, 0, 5, intArrayOf())
        closureSite(carts, 22, 2, 6, intArrayOf(1, 2))
        closureSite(carts, 42, 7, 6, intArrayOf(0, 5))
        closureSite(carts, 50, 9, 6, intArrayOf(0))
        closureSite(carts, 26, 3, 6, intArrayOf(1))
        closureSite(carts, 74, 12, 7, intArrayOf(0))
        // Core captures native type/tostring rather than private cart registries.
        closureSite(cartsCore, 144, 7, 6, intArrayOf(0))
        closureSite(cartsCore, 151, 9, 6, intArrayOf(1))
        closureSite(cartsForceDrop, 4, 0, 1, intArrayOf())
        closureSite(cartsForceDrop.prototypes[0], 0, 0, 2, intArrayOf(0, 1))
        closureSite(neatState, 122, 25, 8, intArrayOf())
        closureSite(radio, 127, 33, 4, intArrayOf())
        closureSite(bowPresentation, 114, 10, 19, intArrayOf())
        closureSite(bowPresentation, 115, 11, 20, intArrayOf(8))
        closureSite(bowPresentation, 124, 14, 22, intArrayOf(19, 20, 0, 21, 1, 4, 3))
        closureSite(bowPresentation, 133, 15, 22, intArrayOf(19, 20, 3))
        closureSite(bowDurability, 33, 4, 9, intArrayOf(0))
        closureSite(archeryContract, 19, 1, 1, intArrayOf(0))
        closureSite(archeryState, 82, 0, 11, intArrayOf())
        closureSite(archeryState, 109, 10, 21, intArrayOf(20))
        closureSite(archeryState, 111, 11, 22, intArrayOf(3, 11, 4, 9, 21, 12, 1, 19))
        closureSite(archeryState, 120, 12, 23, intArrayOf(3, 11, 4, 9, 19, 12))
        closureSite(archeryContract, 17, 0, 1, intArrayOf())
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
        for ((kind, text) in listOf("snow" to snowSource, "neat" to neatSource, "carts" to cartsSource, "fishing" to fishingSource,
            "cartsCore" to cartsCoreSource, "cartsForceDrop" to cartsForceDropSource,
            "neatState" to neatStateSource, "radio" to radioSource, "radioSelected" to radioSelectedSource,
            "bowPresentation" to bowPresentationSource, "equipWeapon" to equipWeaponSource,
            "bowDurability" to bowDurabilitySource, "archeryContract" to archeryContractSource,
            "archeryState" to archeryStateSource, "bowReload" to bowReloadSource)) {
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
        // The complete ordinary cart transition graph observes one live module
        // and one holder cell, rather than unrelated independently empty tables.
        val getPlayerKey = captured(carts.prototypes[0])
        val unregisterKey = captured(carts.prototypes[2], table(), 0.0)
        val sharedHolders = unregisterKey.upvalues[0]
        val ordinaryHolderKey = captured(carts.prototypes[3], table()).apply { upvalues[0] = sharedHolders }
        val unregisterPlayer = captured(carts.prototypes[7], holder, getPlayerKey)
        val handlePrimary = captured(carts.prototypes[9], holder)
        holder.delegate["unregisterKey"] = unregisterKey
        holder.delegate["unregisterPlayer"] = unregisterPlayer
        holder.delegate["handleEquipPrimary"] = handlePrimary
        holder.delegate["isHolderKey"] = ordinaryHolderKey
        val ordinaryCarts = factory("cartsOrdinary")
        check(match(onCarts, ordinaryCarts) == true)
        ordinaryHolderKey.upvalues[0] = cell(table())
        check(match(onCarts, ordinaryCarts) == false) { "Independent empty holders passed shared-cell proof" }
        ordinaryHolderKey.upvalues[0] = sharedHolders
        (sharedHolders.getValue() as KahluaTableImpl).delegate[17.0] = false
        check(match(onCarts, ordinaryCarts) == false) { "Nonempty transition state was ignored" }
        sharedHolders.setValue(table())
        check(match(onCarts, ordinaryCarts) == true) { "Shared live holder rebinding was cached" }
        val foreignHolder = table().apply { delegate.putAll(holder.delegate) }
        unregisterPlayer.upvalues[0].setValue(foreignHolder)
        check(match(onCarts, ordinaryCarts) == false) { "Lookalike transition module passed alias proof" }
        unregisterPlayer.upvalues[0].setValue(holder)
        val transitionWord = unregisterKey.prototype.code[0]
        unregisterKey.prototype.code[0] = transitionWord xor 64
        check(match(onCarts, ordinaryCarts) != true) { "Transition body mutation was ignored" }
        unregisterKey.prototype.code[0] = transitionWord
        check(match(captured(neatState.prototypes[25]), factory("neatLocalPlayerNum")) == true)
        check(match(captured(radio.prototypes[33]), factory("radio")) == true)
        val selectedEquip = selectedRadio.prototypes.single { it.name == "onEquip" }
        check(match(captured(selectedEquip), factory("radio")) == true) { "Selected radio callback differs from the native ordinary-item branch" }
        check(match(captured(equipWeapon.prototypes[5]), factory("isForceDropHeavyItem")) == true)
        check(match(captured(equipWeapon.prototypes[6]), factory("forceDropNative")) == true)
        val nativeType = LuaManager.env.rawget("type")
        val isCart = captured(cartsCore.prototypes[7], nativeType)
        check(match(isCart, factory("cartsIsCart", nativeType)) == true)
        isCart.upvalues[0].setValue(onCarts)
        check(match(isCart, factory("cartsIsCart", nativeType)) == false)
        isCart.upvalues[0].setValue(nativeType)
        val contract = table()
        val durabilityIsBow = captured(bowDurability.prototypes[4], contract)
        val primitiveBow = captured(archeryContract.prototypes[1], contract)
        check(match(durabilityIsBow, factory("bowDurabilityIsBow", contract)) == true)
        check(match(primitiveBow, factory("archeryPrimitiveBow", contract)) == true)
        durabilityIsBow.upvalues[0].setValue(table())
        check(match(durabilityIsBow, factory("bowDurabilityIsBow", contract)) == false)
        durabilityIsBow.upvalues[0].setValue(contract)
        val reloadModule = table()
        val canMutatePlayer = captured(archeryState.prototypes[0])
        val markedRefresh = captured(archeryState.prototypes[10], table())
        val onArcheryPrimary = captured(archeryState.prototypes[11], contract, canMutatePlayer, reloadModule,
            table(), markedRefresh, table(), table(), table())
        val onArcherySecondary = captured(archeryState.prototypes[12], contract, canMutatePlayer, reloadModule,
            table(), table(), table())
        check(match(onArcheryPrimary, factory("archeryPrimary", contract, reloadModule)) == true)
        check(match(onArcherySecondary, factory("archerySecondary", contract, reloadModule)) == true)
        onArcheryPrimary.upvalues[2].setValue(table())
        check(match(onArcheryPrimary, factory("archeryPrimary", contract, reloadModule)) == false)
        onArcheryPrimary.upvalues[2].setValue(reloadModule)
        onArcheryPrimary.upvalues[4].setValue(onArcherySecondary)
        check(match(onArcheryPrimary, factory("archeryPrimary", contract, reloadModule)) != true)
        onArcheryPrimary.upvalues[4].setValue(markedRefresh)
        check(match(captured(archeryContract.prototypes[0]), factory("archeryPlayerCharacter")) == true)
        check(match(captured(bowReload.prototypes[0], contract), factory("bowReloadPrimitiveBow", contract)) == true)
        val nativeTostring = LuaManager.env.rawget("tostring")
        val safeIsCart = captured(cartsCore.prototypes[9], nativeTostring)
        check(match(safeIsCart, factory("cartsSafeIsCart", nativeTostring)) == true)
        val safeChild = safeIsCart.prototype.prototypes[0]
        val safeChildWord = safeChild.code[0]
        safeChild.code[0] = safeChildWord xor 64
        check(match(safeIsCart, factory("cartsSafeIsCart", nativeTostring)) != true) { "Nested classifier body was ignored" }
        safeChild.code[0] = safeChildWord
        val nativeDrop = captured(equipWeapon.prototypes[6])
        val guardedDrop = captured(cartsForceDrop.prototypes[0].prototypes[0], nativeDrop, isCart)
        check(match(guardedDrop, factory("forceDropGuard", isCart)) == true)
        check(match(captured(cartsForceDrop.prototypes[0]), factory("forceDropFactory")) == true)
        guardedDrop.upvalues[0].setValue(onCarts)
        check(match(guardedDrop, factory("forceDropGuard", isCart)) != true) { "Foreign predecessor passed delegation proof" }
        guardedDrop.upvalues[0].setValue(nativeDrop)
        guardedDrop.upvalues[1].setValue(onCarts)
        check(match(guardedDrop, factory("forceDropGuard", isCart)) == false) { "Foreign captured classifier passed identity" }
        guardedDrop.upvalues[1].setValue(isCart)
        val presentation = table()
        val durability = table()
        val localPlayer = captured(bowPresentation.prototypes[10])
        val stateForPlayer = captured(bowPresentation.prototypes[11], table())
        val presentationUpdate = captured(bowPresentation.prototypes[14], localPlayer, stateForPlayer,
            durability, table(), table(), table(), presentation)
        presentation.delegate["onPlayerUpdate"] = presentationUpdate
        val onPresentation = captured(bowPresentation.prototypes[15], localPlayer, stateForPlayer, presentation)
        val presentationRecipe = factory("bowPresentation", presentation, durability)
        check(match(onPresentation, presentationRecipe) == true)
        presentationUpdate.upvalues[1].setValue(captured(bowPresentation.prototypes[11], table()))
        check(match(onPresentation, presentationRecipe) == false) { "Independent private player state accessor passed alias proof" }
        presentationUpdate.upvalues[1].setValue(stateForPlayer)
        presentationUpdate.upvalues[2].setValue(table())
        check(match(onPresentation, presentationRecipe) == false) { "Foreign bow classifier module passed identity" }
        presentationUpdate.upvalues[2].setValue(durability)
        holder.delegate["isHolderKey"] = holderKey
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
