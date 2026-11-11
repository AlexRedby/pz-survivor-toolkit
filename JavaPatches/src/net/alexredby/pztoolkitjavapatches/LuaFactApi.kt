package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Method
import java.util.ArrayList
import java.util.LinkedHashMap
import se.krka.kahlua.integration.expose.LuaJavaInvoker
import se.krka.kahlua.integration.expose.MultiLuaJavaInvoker
import se.krka.kahlua.integration.expose.caller.MethodCaller
import se.krka.kahlua.j2se.KahluaTableImpl
import zombie.Lua.LuaManager

/** Shared metadata-only trust boundary. No actors, inventories or event handlers are called. */
internal object LuaFactApi {
    internal val SUPPORTED = arrayOf(
        "se/krka/kahlua/vm/LuaCallFrame.class" to "7d910d19d1008b2427f4e1409e6c0eb1f8c40e32132fce176b5123ae27192e30",
        "se/krka/kahlua/vm/LuaClosure.class" to "92acfa5288c7bc6ab568a180140c20c5186b723ec2b38adafb2ef807b955b0cd",
        "se/krka/kahlua/vm/Coroutine.class" to "b0ecb5f6f004ed43e356d5177403fee4b190e58f659709cc34b9bc89beb6dfa4",
        "se/krka/kahlua/vm/KahluaThread.class" to "25f4c0dea91800dcb3fadd3d482ed5f7d5cf17908bf167afd308b85c99856bb6",
        "se/krka/kahlua/j2se/KahluaTableImpl.class" to "101df1481366f976f76c037094e29f5ad21c71f5026dc3d0693f25d68b1c79f7",
        "se/krka/kahlua/integration/expose/LuaJavaInvoker.class" to "2c431080d2ce2b94966012e982e64b6d66cd1ae67af2eccd23e163fdfea24457",
        "se/krka/kahlua/integration/expose/MultiLuaJavaInvoker.class" to "ff446aca11076e954a84bc9a0d320d8a1939686c979d5b8ef7988842ed844155",
        "se/krka/kahlua/integration/expose/caller/MethodCaller.class" to "511ba515b1d0e6acd1671aea0195d37e3302eb7e992c73543a5844d6a5a6d098",
    ).all { (path, hash) -> BytecodeSupport.supports(path, hash) }
    private val invokerCaller = field(LuaJavaInvoker::class.java, "caller")
    private val callerMethod = field(MethodCaller::class.java, "method")
    private fun field(type: Class<*>, name: String) = if (!SUPPORTED) null else try {
        type.getDeclaredField(name).apply { isAccessible = true }
    } catch (_: Exception) { null }
    fun plain(value: Any?): KahluaTableImpl? {
        if (value?.javaClass != KahluaTableImpl::class.java) return null
        return (value as KahluaTableImpl).takeIf {
            it.metatable == null && it.rewriteTable == null && it.delegate.javaClass == LinkedHashMap::class.java
        }
    }
    fun canonical(function: Any?, method: Method): Boolean {
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
    fun entry(name: String, method: Method, args: Array<Any?>): Boolean {
        if (!SUPPORTED) return false
        val thread = LuaManager.thread ?: return false
        if (thread.debugOwnerThread !== Thread.currentThread()) return false
        val env = plain(LuaManager.env) ?: return false
        if (thread.environment !== env) return false
        val frame = thread.currentCoroutine?.currentCallFrame() ?: return false
        if (frame.nArguments != args.size || !canonical(frame.javaFunction, method)
            || frame.javaFunction !== env.delegate[name]) return false
        return args.indices.all { frame.get(it) === args[it] }
    }
}
