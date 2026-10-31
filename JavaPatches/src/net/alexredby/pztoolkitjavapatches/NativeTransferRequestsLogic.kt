package net.alexredby.pztoolkitjavapatches

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.security.MessageDigest
import java.util.HexFormat
import java.util.WeakHashMap
import se.krka.kahlua.integration.expose.LuaJavaInvoker
import se.krka.kahlua.integration.expose.MultiLuaJavaInvoker
import se.krka.kahlua.integration.expose.caller.MethodCaller
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.vm.KahluaThread
import se.krka.kahlua.vm.LuaClosure
import se.krka.kahlua.vm.Prototype
import zombie.Lua.LuaManager
import zombie.characters.IsoPlayer
import zombie.inventory.ItemContainer
import zombie.network.GameClient

/** Passive direct-call evidence. Never skips, retries or modifies a native request. */
internal object NativeTransferRequestsLogic {
    @JvmField
    val SUPPORTED =
        QueueBindingHooks.SUPPORTED &&
            BytecodeSupport.supports(
                "zombie/Lua/LuaManager\$GlobalObject.class",
                "80ecbd3bd702db2f992db6cba7cb09c32d775fa6f2a3297e0460874ff5ba20c7",
            ) &&
            BytecodeSupport.supports(
                "se/krka/kahlua/integration/expose/LuaJavaInvoker.class",
                "2c431080d2ce2b94966012e982e64b6d66cd1ae67af2eccd23e163fdfea24457",
            ) &&
            BytecodeSupport.supports(
                "se/krka/kahlua/integration/expose/MultiLuaJavaInvoker.class",
                "ff446aca11076e954a84bc9a0d320d8a1939686c979d5b8ef7988842ed844155",
            ) &&
            BytecodeSupport.supports(
                "se/krka/kahlua/integration/expose/caller/MethodCaller.class",
                "511ba515b1d0e6acd1671aea0195d37e3302eb7e992c73543a5844d6a5a6d098",
            )

    private fun field(owner: Class<*>, name: String): java.lang.reflect.Field? =
        if (!SUPPORTED) null
        else
            try {
                owner.getDeclaredField(name).apply { isAccessible = true }
            } catch (_: Exception) {
                null
            }

    private val invokerCaller = field(LuaJavaInvoker::class.java, "caller")
    private val callerMethod = field(MethodCaller::class.java, "method")
    private val nativeApi =
        if (!SUPPORTED) null
        else
            try {
                LuaManager.GlobalObject::class
                    .java
                    .getMethod(
                        "createItemTransaction",
                        IsoPlayer::class.java,
                        KahluaTableImpl::class.java,
                        ItemContainer::class.java,
                        ItemContainer::class.java,
                    )
            } catch (_: Exception) {
                null
            }

    // A canonical invoker class can wrap a foreign Java method as well. Do not
    // confuse that wrapper's paused Lua frame with the native API's own entry.
    private fun canonicalApi(function: Any?): Boolean {
        val single =
            when (function?.javaClass) {
                LuaJavaInvoker::class.java -> function as LuaJavaInvoker
                MultiLuaJavaInvoker::class.java -> {
                    val values = (function as MultiLuaJavaInvoker).invokers
                    if (values.javaClass != java.util.ArrayList::class.java || values.size != 1)
                        return false
                    values[0]
                }
                else -> return false
            }
        if (single.javaClass != LuaJavaInvoker::class.java || nativeApi == null) return false
        val caller = invokerCaller?.get(single) ?: return false
        return caller.javaClass == MethodCaller::class.java &&
            callerMethod?.get(caller) == nativeApi
    }

    private val active = ThreadLocal<NativeTransferRequests.Scope>()
    private val failedObservers = WeakHashMap<LuaClosure, Boolean>()
    private const val START = "5bd3355b4c043217dbab7a860872949147b889ced24fa8ae53592cd565224a4d"
    private const val CONTINUATION =
        "b73f57fedfbec678037661cf8a0a6c969b2e73bdf93b176e7a41e13a1f7b2911"

    // Fresh structural hashing avoids granting provenance from filenames or a
    // mutable prototype cache. Only the two bounded stock bodies are eligible.
    internal fun fingerprint(prototype: Prototype): String {
        val bytes = ByteArrayOutputStream()
        DataOutputStream(bytes).use { out ->
            out.writeInt(prototype.numParams)
            out.writeBoolean(prototype.isVararg)
            out.writeInt(prototype.numUpvalues)
            out.writeInt(prototype.maxStacksize)
            out.writeInt(prototype.code.size)
            for (word in prototype.code) out.writeInt(word)
            out.writeInt(prototype.constants.size)
            for (constant in prototype.constants) when (constant) {
                null -> out.writeByte(0)
                is Boolean -> {
                    out.writeByte(1)
                    out.writeBoolean(constant)
                }
                is Double -> {
                    out.writeByte(2)
                    out.writeLong(java.lang.Double.doubleToRawLongBits(constant))
                }
                is String -> {
                    out.writeByte(3)
                    out.writeUTF(constant)
                }
                else -> return "unsupported"
            }
            out.writeInt(prototype.prototypes.size)
            if (prototype.prototypes.isNotEmpty()) return "unsupported"
        }
        return HexFormat.of()
            .formatHex(MessageDigest.getInstance("SHA-256").digest(bytes.toByteArray()))
    }

    private fun direct(value: Any?): KahluaTableImpl? {
        if (value?.javaClass != KahluaTableImpl::class.java) return null
        val table = value as KahluaTableImpl
        return table.takeIf {
            it.rewriteTable == null && it.delegate.javaClass == java.util.LinkedHashMap::class.java
        }
    }

    private fun plain(value: Any?): KahluaTableImpl? =
        direct(value)?.takeIf { it.metatable == null }

    private fun nativeCaller(
        thread: KahluaThread,
        env: KahluaTableImpl,
        actor: IsoPlayer?,
        items: KahluaTableImpl?,
        source: ItemContainer?,
        destination: ItemContainer?,
    ): Pair<KahluaTableImpl, String>? {
        val coroutine = thread.currentCoroutine ?: return null
        val api = coroutine.currentCallFrame() ?: return null
        if (
            !canonicalApi(api.javaFunction) ||
                api.javaFunction !== env.delegate["createItemTransaction"] ||
                api.nArguments != 4 ||
                api.get(0) !== actor ||
                api.get(1) !== items ||
                api.get(2) !== source ||
                api.get(3) !== destination
        )
            return null
        val caller = coroutine.getParentNoAssert(1) ?: return null
        val closure = caller.closure ?: return null
        val prototype = closure.prototype
        if (
            closure.env !== env ||
                closure.upvalues.isNotEmpty() ||
                prototype.numParams != 1 ||
                prototype.isVararg ||
                prototype.numUpvalues != 0 ||
                prototype.code.size > 768 ||
                prototype.constants.size > 128 ||
                prototype.prototypes.isNotEmpty() ||
                prototype.filename?.replace('\\', '/')?.substringAfterLast('/') !=
                    "ISInventoryTransferAction.lua"
        )
            return null
        var characters = 0
        for (constant in prototype.constants) {
            if (constant is String) {
                if (constant.length > 4096 - characters) return null
                characters += constant.length
            }
        }
        val boundary =
            when (fingerprint(prototype)) {
                START -> "start"
                CONTINUATION -> "continuation"
                else -> return null
            }
        val action = direct(caller.get(0)) ?: return null
        if (plain(items) == null) return null
        if (
            action.delegate["character"] !== actor ||
                action.delegate["srcContainer"] !== source ||
                action.delegate["destContainer"] !== destination ||
                actor == null ||
                items == null ||
                source == null ||
                destination == null ||
                source === destination
        )
            return null
        return action to boundary
    }

    private fun exposeReceipt(env: KahluaTableImpl): Boolean {
        val exposer = LuaManager.exposer ?: return false
        val receiptClass = NativeTransferRequestReceipt::class.java
        val mapped = exposer.typeMap[receiptClass.simpleName]
        if (mapped != null && mapped !== receiptClass) return false
        if (!exposer.isExposed(receiptClass)) {
            exposer.setExposed(receiptClass)
            exposer.exposeLikeJava(receiptClass, env)
        }
        exposer.typeMap[receiptClass.simpleName] = receiptClass
        return true
    }

    // Warm metadata while the request owner loads, before gameplay requests.
    // No callbacks, actor state or new constructible Lua object is introduced.
    @JvmStatic
    fun prepareLibrary(file: String?): Boolean {
        if (
            file == null ||
                !(file.endsWith("/PZSurvivorToolkit/ActionQueueTransferRequests.lua") ||
                    file.endsWith("\\PZSurvivorToolkit\\ActionQueueTransferRequests.lua"))
        )
            return false
        if (!SUPPORTED) return false
        val thread = LuaManager.thread ?: return false
        if (thread.debugOwnerThread !== Thread.currentThread()) return false
        return exposeReceipt(plain(LuaManager.env) ?: return false)
    }

    @JvmStatic
    fun begin(
        actor: IsoPlayer?,
        items: KahluaTableImpl?,
        source: ItemContainer?,
        destination: ItemContainer?,
    ): NativeTransferRequests.Scope? {
        val previous = active.get()
        // A foreign nested native call masks its parent's receipt as well.
        if (previous != null) {
            previous.receipt?.nested = true
            active.remove()
        }
        val mask =
            if (previous == null) null else NativeTransferRequests.Scope(previous, null, null, null)
        try {
            if (!SUPPORTED || !GameClient.client) return mask
            val thread = LuaManager.thread ?: return mask
            if (thread.debugOwnerThread !== Thread.currentThread()) return mask
            val env = plain(LuaManager.env) ?: return mask
            val toolkit = plain(env.delegate["PZSurvivorToolkit"]) ?: return mask
            val owner = plain(toolkit.delegate["ActionQueueTransferRequests"]) ?: return mask
            val pending = plain(owner.delegate["pending"]) ?: return mask
            if (actor == null || pending.delegate[actor] == null) return mask
            val observer = owner.delegate["observe"] as? LuaClosure ?: return mask
            if (
                observer.env !== env ||
                    observer.prototype.filename?.replace('\\', '/')?.substringAfterLast('/') !=
                        "ActionQueueTransferRequests.lua" ||
                    failedObservers[observer] == true
            )
                return mask
            val (action, boundary) =
                nativeCaller(thread, env, actor, items, source, destination) ?: return mask
            if (pending.delegate[actor] !== action) return mask
            if (!exposeReceipt(env)) return mask
            val receipt =
                NativeTransferRequestReceipt.create(
                    action,
                    actor,
                    items,
                    source,
                    destination,
                    boundary,
                )
            val scope = NativeTransferRequests.Scope(previous, receipt, thread, observer)
            active.set(scope)
            notify(scope)
            return scope
        } catch (_: Throwable) {
            active.remove()
            return mask
        }
    }

    private fun notify(scope: NativeTransferRequests.Scope) {
        val observer = scope.observer ?: return
        if (failedObservers[observer] == true) return
        // Kahlua may reuse this argument array for Boolean success results.
        // A Receipt[] would throw ArrayStoreException after a successful callback.
        val result = scope.thread.pcall(observer, arrayOf<Any?>(scope.receipt))
        if (result.isEmpty() || result[0] != true) failedObservers[observer] = true
    }

    @JvmStatic
    fun end(scope: NativeTransferRequests.Scope?, result: Byte, failure: Throwable?) {
        if (scope == null) return
        try {
            val receipt = scope.receipt
            if (
                active.get() === scope &&
                    receipt != null &&
                    LuaManager.thread === scope.thread &&
                    scope.thread.debugOwnerThread === Thread.currentThread() &&
                    LuaManager.env === scope.observer.env
            ) {
                receipt.phase = if (failure == null) "submitted" else "failed"
                receipt.transaction = result
                receipt.claimed = false
                notify(scope)
            }
        } catch (_: Throwable) {
            // Observer failures must preserve the original byte result/throwable.
        } finally {
            if (scope.previous == null) active.remove() else active.set(scope.previous)
        }
    }

    @JvmStatic
    fun current(receipt: NativeTransferRequestReceipt, action: KahluaTableImpl?): Boolean =
        active.get()?.receipt === receipt &&
            receipt.action === action &&
            LuaManager.thread === active.get()?.thread

    @JvmStatic
    fun claim(receipt: NativeTransferRequestReceipt, action: KahluaTableImpl?): Boolean {
        if (!current(receipt, action) || receipt.claimed) return false
        receipt.claimed = true
        return true
    }
}
