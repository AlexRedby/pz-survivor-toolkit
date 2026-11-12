package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Method
import java.util.ArrayList
import java.util.HashMap
import java.util.LinkedHashMap
import se.krka.kahlua.integration.annotations.LuaMethod
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.vm.LuaClosure
import zombie.Lua.Event
import zombie.Lua.LuaEventManager
import zombie.Lua.LuaManager

/** Current named native registry equality only; this grants no future dispatch/edit authority. */
object QueueEquipEventRegistry {
    @JvmField internal val SUPPORTED = LuaFactApi.SUPPORTED && arrayOf(
        "zombie/Lua/LuaEventManager.class" to "9706f17e9b5e095a0e24230dc944de5d552fa62c997214636c4deb4957cf354b",
        "zombie/Lua/Event.class" to "cf4b0ba953b8f965fbcacb73ebb5d1a173dc3ed140656e15b90ad932eff0e952",
        "zombie/Lua/LuaEventManager\$QueuedEvent.class" to "6ada9cc02c9adbfc6862b2d64d04f39743e401c1fe9d02aca96c694ef0329096",
    ).all { (path, hash) -> BytecodeSupport.supports(path, hash) }
    private val readMethod = QueueEquipEventRegistry::class.java.getMethod("callbacksMatch", Any::class.java, Any::class.java)
    private val snapshotMethod = QueueEquipEventRegistry::class.java.getMethod("callbacks")
    private val checkMethod = QueueEquipEventRegistry::class.java.getMethod("apiMatches", Any::class.java)
    private val eventMap = field(LuaEventManager::class.java, "EventMap")
    private fun field(type: Class<*>, name: String) = if (!SUPPORTED) null else try {
        type.getDeclaredField(name).apply { isAccessible = true }
    } catch (_: Exception) { null }

    private fun plain(value: Any?): KahluaTableImpl? = LuaFactApi.plain(value)
    private fun canonical(function: Any?, method: Method): Boolean = SUPPORTED && LuaFactApi.canonical(function, method)
    private fun entry(name: String, method: Method, args: Array<Any?>): Boolean =
        SUPPORTED && LuaFactApi.entry(name, method, args)
    @JvmStatic @LuaMethod(name = "toolkitEquipEventRegistryApiMatches", global = true)
    fun apiMatches(function: Any?): Boolean = try {
        entry("toolkitEquipEventRegistryApiMatches", checkMethod, arrayOf(function))
            && ((canonical(function, readMethod)
                && plain(LuaManager.env)?.delegate?.get("toolkitEquipEventCallbacksMatch") === function)
                || (canonical(function, snapshotMethod)
                && plain(LuaManager.env)?.delegate?.get("toolkitEquipEventCallbacks") === function))
    } catch (_: Exception) { false } catch (_: AssertionError) { false }

    /** Fresh arrays of closure identities; neither native list nor captured state escapes. */
    @JvmStatic @LuaMethod(name = "toolkitEquipEventCallbacks", global = true)
    fun callbacks(): KahluaTableImpl? = try {
        if (!entry("toolkitEquipEventCallbacks", snapshotMethod, emptyArray())) null
        else {
            val map = eventMap?.get(null)
            if (map?.javaClass != HashMap::class.java) null else synchronized(map) {
                val registry = map as HashMap<*, *>
                val p = copy(registry["OnEquipPrimary"])
                val s = copy(registry["OnEquipSecondary"])
                if (p == null || s == null) null else KahluaTableImpl(LinkedHashMap<Any, Any?>()).apply {
                    delegate["primary"] = p
                    delegate["secondary"] = s
                }
            }
        }
    } catch (_: Exception) { null } catch (_: AssertionError) { null }

    private fun copy(value: Any?): KahluaTableImpl? {
        if (value?.javaClass != Event::class.java) return null
        val callbacks = (value as Event).callbacks
        if (callbacks.javaClass != ArrayList::class.java) return null
        val result = KahluaTableImpl(LinkedHashMap<Any, Any?>())
        for (index in callbacks.indices) {
            val callback: Any? = callbacks[index]
            if (callback?.javaClass != LuaClosure::class.java || (callback as LuaClosure).env !== LuaManager.env) return null
            result.delegate[(index + 1).toDouble()] = callback
        }
        return result
    }

    @JvmStatic @LuaMethod(name = "toolkitEquipEventCallbacksMatch", global = true)
    fun callbacksMatch(primary: Any?, secondary: Any?): Boolean? = try {
        if (!entry("toolkitEquipEventCallbacksMatch", readMethod, arrayOf(primary, secondary))) null
        else {
            val p = array(primary)
            val s = array(secondary)
            val map = eventMap?.get(null)
            if (p == null || s == null || map?.javaClass != HashMap::class.java) null
            else synchronized(map) {
                // Native checkEvent(name) selects precisely EventMap[name], and Event.trigger
                // walks that Event's callbacks in order. EventList is not dispatch authority.
                // Read the live map each call, without checkEvent/AddEvent or copying all events.
                val registry = map as HashMap<*, *>
                val pm = matches(registry["OnEquipPrimary"], p)
                val sm = matches(registry["OnEquipSecondary"], s)
                if (pm == null || sm == null) null else pm && sm
                // Off-thread triggerEvent queues an Event identity, which can outlive a map
                // replacement. This observation says nothing about already queued or active
                // dispatches, subsequent mutations, or callback outcomes.
            }
        }
    } catch (_: Exception) { null } catch (_: AssertionError) { null }

    private fun array(value: Any?): KahluaTableImpl? {
        val table = plain(value) ?: return null
        val size = table.delegate.size
        for ((key, callback) in table.delegate) {
            if (key?.javaClass != Double::class.javaObjectType) return null
            val index = key as Double
            if (!index.isFinite() || index < 1 || index > size || index != index.toInt().toDouble()
                || callback?.javaClass != LuaClosure::class.java || (callback as LuaClosure).env !== LuaManager.env) return null
        }
        return table
    }
    private fun matches(value: Any?, supplied: KahluaTableImpl): Boolean? {
        if (value?.javaClass != Event::class.java) return null
        val callbacks = (value as Event).callbacks
        if (callbacks.javaClass != ArrayList::class.java) return null
        var equal = callbacks.size == supplied.delegate.size
        for (index in callbacks.indices) {
            val callback: Any? = callbacks[index]
            if (callback?.javaClass != LuaClosure::class.java || (callback as LuaClosure).env !== LuaManager.env) return null
            if (callback !== supplied.delegate[(index + 1).toDouble()]) equal = false
        }
        return equal
    }
}
