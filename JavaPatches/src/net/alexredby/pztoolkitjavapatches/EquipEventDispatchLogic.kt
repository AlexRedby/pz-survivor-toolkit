package net.alexredby.pztoolkitjavapatches

import java.util.ArrayList
import java.util.HashMap
import java.util.IdentityHashMap
import zombie.characters.IsoPlayer
import zombie.characters.IsoGameCharacter
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.inventory.types.ComboItem
import zombie.inventory.types.HandWeapon
import zombie.entity.GameEntity
import zombie.entity.ComponentContainer
import zombie.entity.Component
import zombie.entity.ComponentType
import zombie.entity.components.script.EntityScriptInfo
import zombie.entity.util.Array as EntityArray
import zombie.scripting.objects.Item
import zombie.scripting.objects.ItemTag
import se.krka.kahlua.integration.annotations.LuaMethod
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.stdlib.BaseLib
import se.krka.kahlua.stdlib.TableLib
import se.krka.kahlua.vm.KahluaTable
import se.krka.kahlua.vm.KahluaThread
import zombie.Lua.Event
import zombie.Lua.LuaEventManager
import zombie.Lua.LuaManager

/** Synchronous owner-thread observation, never a future event or Host guarantee. */
object EquipEventDispatchLogic {
    @JvmField internal val SUPPORTED = LuaFactApi.SUPPORTED && arrayOf(
        "zombie/Lua/LuaEventManager.class" to "9706f17e9b5e095a0e24230dc944de5d552fa62c997214636c4deb4957cf354b",
        "zombie/Lua/Event.class" to "cf4b0ba953b8f965fbcacb73ebb5d1a173dc3ed140656e15b90ad932eff0e952",
        "zombie/Lua/LuaEventManager\$QueuedEvent.class" to "6ada9cc02c9adbfc6862b2d64d04f39743e401c1fe9d02aca96c694ef0329096",
        "se/krka/kahlua/stdlib/BaseLib.class" to "03816f584acbe2ef78e167f3e7ef4773865adc5a68c7ee9732cfa7ba81f4a927",
        "se/krka/kahlua/stdlib/TableLib.class" to "97c294f5c050c48b901315eaa737f0d12587185554923d01e5c9f25602e51156",
        "zombie/Lua/LuaManager\$GlobalObject.class" to "80ecbd3bd702db2f992db6cba7cb09c32d775fa6f2a3297e0460874ff5ba20c7",
        "zombie/characters/IsoPlayer.class" to "3f1c4634d3a8e7e36baf4b33f76cf7ef79d88c3351bd0eb2a6a6bb34c2d9858f",
        "zombie/characters/IsoGameCharacter.class" to "29040e19c3e420499f73bc0ea0d5b86d7f7d38655acdc13d0107df736eb54c0b",
        "zombie/inventory/InventoryItem.class" to "48f01be16d1ef1b76e37638fac6e25ca4eb285ad38ab2f462caa5597318c7f9d",
        "zombie/inventory/ItemContainer.class" to "a2ac7dd6235f91255dc57b91419a2c8609bdb105214cddf7fb445b70507b6f96",
        "zombie/inventory/types/ComboItem.class" to "161277cc8fab2aa4c4bbf634a237f28cdb5a583565df36612159ef3bd4e129d1",
        "zombie/inventory/types/HandWeapon.class" to "2d1d3266cd03730fc8af8bfc631eea37a8e07708ceb6fe7b376d2b0e5f4174e4",
        "zombie/entity/GameEntity.class" to "fb46c896c05e72b5f951943b1adfac580a57ae709a6f496b77aa954b6a1886ee",
        "zombie/entity/GameEntityManager.class" to "679953e42c73179cf083a40af5c1d67de67452519dace5efa517369c974a9775",
        "zombie/entity/ComponentContainer.class" to "6ba2f3b49445833274f35b4745c646f001d26203a961c8bd903f25d05bf70829",
        "zombie/entity/Component.class" to "8702b1a682853b883c2aaa30c71112b31238f9b4968d91bf61617fc99b2c9159",
        "zombie/entity/ComponentType.class" to "28f3d346c47a0b1804c7258659587c0f415eef3d510d6cd67c50d2ff291ebcda",
        "zombie/entity/components/script/EntityScriptInfo.class" to "40419e1c378099bd748567b008f161c2c0cb0f7aa75c9e844c1946314de64ad6",
        "zombie/scripting/objects/Item.class" to "9e6a2f7fe48cc66843fea06b4821063d7cc6a73eaba0de8ee51d0a15c373202e",
        "zombie/scripting/objects/ItemTag.class" to "616d4da81f7ea23f6a4cfafb27a240e21d26f5670506c11372cd56636007c825",
        "zombie/entity/util/Array.class" to "6718d3b4862df6d39ba431c41945b40379c5222354f60d3d798aa1793504e990",
    ).all { (path, hash) -> BytecodeSupport.supports(path, hash) }
    private fun field(type: Class<*>, name: String) = if (!SUPPORTED) null else try {
        type.getDeclaredField(name).apply { isAccessible = true }
    } catch (_: Exception) { null }
    private val eventMap = field(LuaEventManager::class.java, "EventMap")
    private val queued = field(LuaEventManager::class.java, "QueuedEvents")
    private val idleMethod = EquipEventDispatchLogic::class.java.getMethod("idle")
    private val globalsMethod = EquipEventDispatchLogic::class.java.getMethod("globalsTrusted")
    private val quietMethod = EquipEventDispatchLogic::class.java.getMethod("nativeQuiet", Any::class.java, Any::class.java)
    private val preparedQuietMethod = EquipEventDispatchLogic::class.java.getMethod("nativePreparedQuiet", Any::class.java, Any::class.java, Any::class.java)
    private val checkMethod = EquipEventDispatchLogic::class.java.getMethod("apiMatches", Any::class.java)
    private class State(var thread: KahluaThread? = null, var env: KahluaTableImpl? = null,
                        var depth: Int = 0, var broken: Boolean = false, var level: Int = 0) {
        val slots = arrayOfNulls<Scope>(64)
    }
    class Scope internal constructor(internal val stateIdentity: Any, internal val slot: Int) {
        internal var depth = 0
        internal var counted = false
        internal var owner: Thread? = null
        internal var event: Event? = null
        internal var name: String? = null
        internal var active = false
        internal fun clear() { event=null; name=null; owner=null; active=false }
    }
    private val states = ThreadLocal.withInitial { State() }

    /** Only the woven Event.trigger entry calls this; no callbacks are invoked here.
     * Native Event.trigger ignores its environment parameter and calls through
     * LuaManager.thread, so that actual owner/environment determines the scope. */
    @JvmStatic fun enter(event: Event, @Suppress("UNUSED_PARAMETER") environment: KahluaTable?): Scope? = try {
        val thread = LuaManager.thread
        val env = LuaFactApi.plain(LuaManager.env)
        if (!SUPPORTED || thread == null || env == null || thread.environment !== env
            || thread.debugOwnerThread !== Thread.currentThread() || event.javaClass != Event::class.java) null
        else {
            val state = states.get()
            if (state.thread !== thread || state.env !== env) {
                if (state.level != 0) state.broken = true
                else { state.thread = thread; state.env = env; state.broken = false }
            }
            if (state.level >= state.slots.size) { state.broken=true;null }
            else {
                val slot=state.level
                // One allocation per reached nesting depth; warmed dispatches
                // reuse these fixed slots without retaining retired events.
                val scope=state.slots[slot] ?: Scope(state,slot).also { state.slots[slot]=it }
                scope.depth=state.depth
                scope.counted=event.name == "OnEquipPrimary" || event.name == "OnEquipSecondary"
                scope.owner=Thread.currentThread()
                scope.event=event
                scope.name=event.name
                scope.active=true
                state.level++
                if (scope.counted) state.depth++
                scope
            }
        }
    } catch (_: Exception) { null } catch (_: AssertionError) { null }

    @JvmStatic fun exit(scope: Scope?) {
        if (scope == null) return
        val state = states.get()
        if (scope.owner !== Thread.currentThread() || scope.stateIdentity !== state || !scope.active
            || state.level != scope.slot+1 || state.slots[scope.slot] !== scope
            || state.depth != scope.depth + if (scope.counted) 1 else 0) {
            state.broken = true
            scope.clear()
            return
        }
        state.depth = scope.depth
        state.level = scope.slot
        scope.clear()
    }
    private fun owner(): State? {
        if (!SUPPORTED) return null
        val thread = LuaManager.thread ?: return null
        val env = LuaFactApi.plain(LuaManager.env) ?: return null
        if (thread.debugOwnerThread !== Thread.currentThread() || thread.environment !== env) return null
        return states.get().takeIf { !it.broken && it.thread === thread && it.env === env }
    }
    private fun queuedEmpty(list: Any): Boolean = synchronized(list) { (list as ArrayList<*>).isEmpty() }
    @JvmStatic @LuaMethod(name="toolkitEquipEventDispatchIdle", global=true)
    fun idle(): Boolean? = try {
        if (!SUPPORTED || !LuaFactApi.entry("toolkitEquipEventDispatchIdle", idleMethod, emptyArray())) null
        else owner()?.let { state ->
            val list = queued?.get(null)
            if (list?.javaClass != ArrayList::class.java) null
            else if (state.depth != 0 || Thread.holdsLock(list) || !queuedEmpty(list)) false
            else {
                val map = eventMap?.get(null)
                if (map?.javaClass != HashMap::class.java) null
                else synchronized(map) {
                    val registry = map as HashMap<*, *>
                    // Event.name is mutable but the native registry key selects
                    // dispatch. Validate active identities, not just that label.
                    // No EventMap monitor is taken while QueuedEvents is held:
                    // native queued dispatch keeps that list nonempty until exit.
                    var safe = state.level in 0..state.slots.size
                    var index=0
                    while (index < state.level && safe) {
                        val active=state.slots[index]
                        val event=active?.event
                        if (active == null || !active.active || event == null || active.name == null || event.name != active.name
                            || registry[active.name] !== event
                            || registry["OnEquipPrimary"] === event
                            || registry["OnEquipSecondary"] === event) safe = false
                        index++
                    }
                    safe && queuedEmpty(list)
                }
            }
        }
    } catch (_: Exception) { null } catch (_: AssertionError) { null }

    private class Standard(val type: Class<*>, val name: String, val index: Int, val constant: String) {
        private val slot = field(type, "index")
        private val names = field(type, "names")
        private val functions = field(type, "functions")
        private val number = field(type, constant)
        fun matches(value: Any?): Boolean {
            if (value?.javaClass != type || slot?.getInt(value) != index || number?.getInt(null) != index) return false
            val labels = names?.get(null) as? Array<*> ?: return false
            val values = functions?.get(null) as? Array<*> ?: return false
            return index in labels.indices && index in values.indices && labels[index] == name && values[index] === value
        }
    }
    private val standards = arrayOf(
        Standard(BaseLib::class.java,"pcall",0,"PCALL"), Standard(BaseLib::class.java,"select",2,"SELECT"),
        Standard(BaseLib::class.java,"type",3,"TYPE"), Standard(BaseLib::class.java,"tostring",4,"TOSTRING"),
        Standard(TableLib::class.java,"pairs",4,"PAIRS"), Standard(TableLib::class.java,"ipairs",7,"IPAIRS"),
    )
    private val nativeMethods = arrayOf(
        "instanceof" to LuaManager.GlobalObject::class.java.getMethod("instof",Any::class.java,String::class.java),
        "getPlayer" to LuaManager.GlobalObject::class.java.getMethod("getPlayer"),
        "getSpecificPlayer" to LuaManager.GlobalObject::class.java.getMethod("getSpecificPlayer",Int::class.javaPrimitiveType),
        "isMultiplayer" to LuaManager.GlobalObject::class.java.getMethod("isMultiplayer"),
        "isClient" to LuaManager.GlobalObject::class.java.getMethod("isClient"),
        "isServer" to LuaManager.GlobalObject::class.java.getMethod("isServer"),
        "getClassSimpleName" to LuaManager.GlobalObject::class.java.getMethod("getClassSimpleName",Any::class.java),
    )
    /** Read exact dispatcher metadata only; never invoke any supplied/global function. */
    @JvmStatic @LuaMethod(name="toolkitEquipGlobalsTrusted", global=true)
    fun globalsTrusted(): Boolean = try {
        if (!SUPPORTED || !LuaFactApi.entry("toolkitEquipGlobalsTrusted",globalsMethod,emptyArray())) false
        else {
            val env = LuaFactApi.plain(LuaManager.env)
            env != null && LuaFactApi.plain(env.delegate["ItemTag"])?.delegate?.get("FISHING_ROD") === ItemTag.FISHING_ROD
                && standards.all { it.matches(env.delegate[it.name]) }
                && nativeMethods.all { (name,method) -> LuaFactApi.canonical(env.delegate[name],method) }
        }
    } catch (_: Exception) { false } catch (_: AssertionError) { false }

    private val animalList = field(IsoPlayer::class.java,"attachedAnimals")
    private val inventory = field(IsoGameCharacter::class.java,"inventory")
    private val container = field(InventoryItem::class.java,"container")
    private val scriptItem = field(InventoryItem::class.java,"scriptItem")
    private val itemTags = field(Item::class.java,"itemTags")
    private val managed = field(GameEntity::class.java,"addedToEntityManager")
    private val components = field(GameEntity::class.java,"components")
    private val componentList = field(ComponentContainer::class.java,"componentList")
    private val componentArray = field(ComponentContainer::class.java,"componentArray")
    private val componentOwner = field(Component::class.java,"owner")
    private val componentType = field(Component::class.java,"componentType")
    private val typeId = field(ComponentType::class.java,"id")
    private fun quietEntity(item: InventoryItem): Boolean {
        if (managed?.getBoolean(item) != false) return false
        val contents = components?.get(item) ?: return components != null
        if (contents.javaClass != ComponentContainer::class.java) return false
        val list = componentList?.get(contents)
        if (list?.javaClass != EntityArray::class.java) return false
        val nativeList = list as EntityArray<*>
        if (nativeList.size == 0) return true
        if (nativeList.size != 1) return false
        val values = componentArray?.get(contents) as? Array<*> ?: return false
        val script = nativeList.items.getOrNull(0) ?: return false
        if (script.javaClass != EntityScriptInfo::class.java || componentOwner?.get(script) !== item) return false
        val type = componentType?.get(script)
        if (type !== ComponentType.Script) return false
        val id = typeId?.getShort(ComponentType.Script)?.toInt() ?: return false
        return id in values.indices && values[id] === script
    }
    /** Immediate ownership and quiet native branches only. The Lua owner
     * separately proves canonical lookup and carried-container ancestry.
     * This observes raw fields without invoking gameplay getters. */
    private fun quietItems(actor: Any?, items: Any?, source: ItemContainer?): Boolean? {
        if (actor?.javaClass != IsoPlayer::class.java) return null
        return run {
            val rows = LuaFactApi.plain(items)
            val animals = animalList?.get(actor)
            val root = inventory?.get(actor)
            if (rows == null || rows.delegate.size !in 1..3 || animals?.javaClass != ArrayList::class.java
                || root?.javaClass != ItemContainer::class.java) null
            else if (!(animals as ArrayList<*>).isEmpty()) false
            else {
                root as ItemContainer
                val location = source ?: root
                if (root.parent !== actor || root.containingItem != null
                    || location.javaClass != ItemContainer::class.java
                    || (source != null && (source.parent != null || source.containingItem == null))) null
                else {
                    val identities = IdentityHashMap<Any,Boolean>()
                    val ids = HashSet<Int>()
                    var safe: Boolean? = true
                    for ((key,item) in rows.delegate) {
                        if (key?.javaClass != Double::class.javaObjectType) { safe=null;break }
                        val index=key as Double
                        if (!index.isFinite() || index < 1 || index > rows.delegate.size || index != index.toInt().toDouble()) { safe=null;break }
                        if (item?.javaClass != ComboItem::class.java && item?.javaClass != HandWeapon::class.java) { safe=null;break }
                        item as InventoryItem
                        if (identities.put(item,true) != null || !ids.add(item.id) || item.id == -1 || container?.get(item) !== location) { safe=null;break }
                        val script=scriptItem?.get(item)
                        val tags=if (script?.javaClass == Item::class.java) itemTags?.get(script) else null
                        if (tags?.javaClass != HashSet::class.java) { safe=null;break }
                        if ((tags as HashSet<*>).contains(ItemTag.FISHING_ROD) || !quietEntity(item)) { safe=false;break }
                    }
                    safe
                }
            }
        }

    }
    @JvmStatic @LuaMethod(name="toolkitEquipNativeQuiet",global=true)
    fun nativeQuiet(actor: Any?, items: Any?): Boolean? = try {
        if (!SUPPORTED || !LuaFactApi.entry("toolkitEquipNativeQuiet",quietMethod,arrayOf(actor,items))) null
        else quietItems(actor,items,null)
    } catch (_: Exception) { null } catch (_: AssertionError) { null }

    @JvmStatic @LuaMethod(name="toolkitEquipNativePreparedQuiet",global=true)
    fun nativePreparedQuiet(actor: Any?, items: Any?, source: Any?): Boolean? = try {
        if (!SUPPORTED || !LuaFactApi.entry("toolkitEquipNativePreparedQuiet",preparedQuietMethod,arrayOf(actor,items,source))
            || source?.javaClass != ItemContainer::class.java) null
        else quietItems(actor,items,source as ItemContainer)
    } catch (_: Exception) { null } catch (_: AssertionError) { null }

    @JvmStatic @LuaMethod(name="toolkitEquipEventDispatchApiMatches", global=true)
    fun apiMatches(function: Any?): Boolean = try {
        SUPPORTED && LuaFactApi.entry("toolkitEquipEventDispatchApiMatches",checkMethod,arrayOf(function))
            && ((LuaFactApi.canonical(function,idleMethod) && LuaFactApi.plain(LuaManager.env)?.delegate?.get("toolkitEquipEventDispatchIdle") === function)
            || (LuaFactApi.canonical(function,globalsMethod) && LuaFactApi.plain(LuaManager.env)?.delegate?.get("toolkitEquipGlobalsTrusted") === function)
            || (LuaFactApi.canonical(function,quietMethod) && LuaFactApi.plain(LuaManager.env)?.delegate?.get("toolkitEquipNativeQuiet") === function)
            || (LuaFactApi.canonical(function,preparedQuietMethod) && LuaFactApi.plain(LuaManager.env)?.delegate?.get("toolkitEquipNativePreparedQuiet") === function))
    } catch (_: Exception) { false } catch (_: AssertionError) { false }
}
