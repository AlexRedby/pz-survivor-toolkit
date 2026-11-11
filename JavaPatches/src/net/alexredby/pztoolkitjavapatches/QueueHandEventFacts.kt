package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Method
import java.util.ArrayList
import java.util.LinkedHashMap
import se.krka.kahlua.integration.annotations.LuaMethod
import se.krka.kahlua.integration.expose.LuaJavaInvoker
import se.krka.kahlua.integration.expose.MultiLuaJavaInvoker
import se.krka.kahlua.integration.expose.caller.MethodCaller
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.vm.LuaClosure
import zombie.Lua.LuaManager
import zombie.characters.IsoPlayer

/** A fresh negative fact about the selected WPANC capture, never an event/edit certificate. */
object QueueHandEventFacts {
    @JvmField internal val SUPPORTED = arrayOf(
        "se/krka/kahlua/vm/LuaCallFrame.class" to "7d910d19d1008b2427f4e1409e6c0eb1f8c40e32132fce176b5123ae27192e30",
        "zombie/characters/IsoPlayer.class" to "3f1c4634d3a8e7e36baf4b33f76cf7ef79d88c3351bd0eb2a6a6bb34c2d9858f",
        "zombie/characters/IsoGameCharacter.class" to "29040e19c3e420499f73bc0ea0d5b86d7f7d38655acdc13d0107df736eb54c0b",
        "zombie/iso/IsoMovingObject.class" to "7e6e84fe9d3cb264e8d8e682d91e0abe919d481b7349d17b997e8a78f2293a5f",
        "zombie/iso/IsoObject.class" to "22387ecf47c1cf9aac192466de6298067f27584160c76a72baee38c6ad36dff2",
        "se/krka/kahlua/vm/UpValue.class" to "505d77406e1d50884bec438e37afd1ec0a37f4431b649744a96add479a897745",
        "se/krka/kahlua/vm/LuaClosure.class" to "92acfa5288c7bc6ab568a180140c20c5186b723ec2b38adafb2ef807b955b0cd",
        "se/krka/kahlua/vm/Prototype.class" to "5e31f0809512e9cfbc9a8fff5a932e35cdc7f1ebb4a0ea146a2f9a207a23fcf4",
        "se/krka/kahlua/vm/Coroutine.class" to "b0ecb5f6f004ed43e356d5177403fee4b190e58f659709cc34b9bc89beb6dfa4",
        "se/krka/kahlua/vm/KahluaThread.class" to "25f4c0dea91800dcb3fadd3d482ed5f7d5cf17908bf167afd308b85c99856bb6",
        "se/krka/kahlua/j2se/KahluaTableImpl.class" to "101df1481366f976f76c037094e29f5ad21c71f5026dc3d0693f25d68b1c79f7",
        "se/krka/kahlua/integration/expose/LuaJavaInvoker.class" to "2c431080d2ce2b94966012e982e64b6d66cd1ae67af2eccd23e163fdfea24457",
        "se/krka/kahlua/integration/expose/MultiLuaJavaInvoker.class" to "ff446aca11076e954a84bc9a0d320d8a1939686c979d5b8ef7988842ed844155",
        "se/krka/kahlua/integration/expose/caller/MethodCaller.class" to "511ba515b1d0e6acd1671aea0195d37e3302eb7e992c73543a5844d6a5a6d098",
    ).all { (path, hash) -> BytecodeSupport.supports(path, hash) }

    // Native compiler output from the selected R5_AimState.lua. The source creation
    // sites bind primary/secondary slot 3 and markUpdated slot 0 to root register 9.
    internal const val PRIMARY = "120f5a9ca69ede731c33fab5f38d2a46f5c6d9aa2c92b198eeb2a9346e83698a"
    internal const val SECONDARY = "1790ecf60c6036ad702cfc9f0c4a08f5cf510d97128d26b3a804f7d5520465c8"
    internal const val UPDATED = "e61143b702c849ba70423e19d4397d280381b9efaca325c735e11b5a995b5922"
    private val readMethod = QueueHandEventFacts::class.java.getMethod("trackingAbsent", Any::class.java, Any::class.java, Any::class.java, Any::class.java)
    private val checkMethod = QueueHandEventFacts::class.java.getMethod("apiMatches", Any::class.java)
    private val invokerCaller = field(LuaJavaInvoker::class.java, "caller")
    private val callerMethod = field(MethodCaller::class.java, "method")
    private fun field(type: Class<*>, name: String) = if (!SUPPORTED) null else try {
        type.getDeclaredField(name).apply { isAccessible = true }
    } catch (_: Exception) { null }

    private fun canonical(function: Any?, method: Method): Boolean {
        if (!SUPPORTED) return false
        val invoker = when (function?.javaClass) {
            LuaJavaInvoker::class.java -> function as LuaJavaInvoker
            MultiLuaJavaInvoker::class.java -> {
                val values = (function as MultiLuaJavaInvoker).invokers
                if (values.javaClass != ArrayList::class.java || values.size != 1) return false
                values[0]
            }
            else -> return false
        }
        if (invoker.javaClass != LuaJavaInvoker::class.java) return false
        val caller = invokerCaller?.get(invoker) ?: return false
        return caller.javaClass == MethodCaller::class.java && callerMethod?.get(caller) == method
    }
    private fun plain(value: Any?): KahluaTableImpl? {
        if (value?.javaClass != KahluaTableImpl::class.java) return null
        return (value as KahluaTableImpl).takeIf {
            it.metatable == null && it.rewriteTable == null && it.delegate.javaClass == LinkedHashMap::class.java
        }
    }
    private fun entry(name: String, method: Method, args: Array<Any?>): Boolean {
        if (!SUPPORTED) return false
        val thread = LuaManager.thread ?: return false
        if (thread.debugOwnerThread !== Thread.currentThread()) return false
        val env = plain(LuaManager.env) ?: return false
        val frame = thread.currentCoroutine?.currentCallFrame() ?: return false
        if (frame.nArguments != args.size || !canonical(frame.javaFunction, method)
            || frame.javaFunction !== env.delegate[name]) return false
        return args.indices.all { frame.get(it) === args[it] }
    }
    @JvmStatic @LuaMethod(name = "toolkitArcheryTrackingApiMatches", global = true)
    fun apiMatches(function: Any?): Boolean = try {
        entry("toolkitArcheryTrackingApiMatches", checkMethod, arrayOf(function))
            && canonical(function, readMethod)
            && plain(LuaManager.env)?.delegate?.get("toolkitArcheryTrackingAbsent") === function
    } catch (_: Exception) { false } catch (_: AssertionError) { false }

    @JvmStatic @LuaMethod(name = "toolkitArcheryTrackingAbsent", global = true)
    fun trackingAbsent(actor: Any?, primary: Any?, secondary: Any?, updated: Any?): Boolean? = try {
        if (actor?.javaClass != IsoPlayer::class.java || (primary as? LuaClosure)?.env !== LuaManager.env ||
            !entry("toolkitArcheryTrackingAbsent", readMethod, arrayOf(actor, primary, secondary, updated))) null
        else read(actor, primary, secondary, updated, SUPPORTED, true)
    } catch (_: Exception) { null } catch (_: AssertionError) { null }

    private fun closure(value: Any?, hash: String, upvalues: Int): LuaClosure? {
        val closure = value as? LuaClosure ?: return null
        val p = closure.prototype
        // Bound before hashing; do not cache proof of publicly mutable prototype arrays.
        if (p.numParams != 2 || p.isVararg || p.numUpvalues != upvalues || closure.upvalues.size != upvalues
            || p.prototypes.isNotEmpty() || p.code.size !in 1..512 || p.constants.size > 64
            || p.constants.any { it is String && it.length > 256 }
            || LuaPrototypeFingerprint.leaf(p) != hash) return null
        return closure
    }
    /** Test-only plain key seam; this cannot admit a table through the production Lua API. */
    internal fun readTestKey(key: KahluaTableImpl, primary: Any?, secondary: Any?, updated: Any?, supported: Boolean, owner: Boolean): Boolean? =
        if (plain(key) == null) null else read(key, primary, secondary, updated, supported, owner)

    private fun read(key: Any?, primary: Any?, secondary: Any?, updated: Any?, supported: Boolean, owner: Boolean): Boolean? = try {
        if (!supported || !owner || key == null) null else {
            val p = closure(primary, PRIMARY, 8)
            val s = closure(secondary, SECONDARY, 6)
            val u = closure(updated, UPDATED, 2)
            if (p == null || s == null || u == null || p.env !== s.env || p.env !== u.env) null else {
                val capture = p.upvalues[3]
                if (capture == null || capture !== s.upvalues[3] || capture !== u.upvalues[0]) null else {
                    // clearTracking replaces the table in this cell. Always read the live cell;
                    // never retain its table, actor value, or a previous negative observation.
                    val tracking = plain(capture.getValue())
                    if (tracking == null) null else !tracking.delegate.containsKey(key)
                }
            }
        }
    } catch (_: Exception) { null } catch (_: AssertionError) { null }
}
