package net.alexredby.pztoolkitjavapatches

import java.lang.ref.WeakReference
import java.util.WeakHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import me.zed_0xff.zombie_buddy.Accessor
import se.krka.kahlua.vm.KahluaTable
import zombie.Lua.LuaManager
import zombie.characters.CharacterTimedActions.BaseAction
import zombie.characters.CharacterTimedActions.LuaTimedActionNew
import zombie.characters.IsoPlayer
import zombie.core.ActionManager
import zombie.core.NetTimedAction
import zombie.core.Transaction.TransactionState
import zombie.network.GameClient
import zombie.network.fields.character.PlayerID

object ActionCompletion {
    private val current = ThreadLocal<Scope>()

    // Values must not retain the native weak key through actors, Lua tables or receipts.
    private class NativeWait(transaction: NetTimedAction, val id: Byte, var doneObserved: Boolean) {
        val transaction = WeakReference(transaction)
        var deadlineNanos = System.nanoTime() + 30_000_000_000L
        var revoked = false
        var performed = false
    }

    private val waits = WeakHashMap<LuaTimedActionNew, NativeWait>()

    private class NativeState(val transaction: NetTimedAction, val id: Byte, val done: Boolean)

    /** A byte can be reused: require one exact owned standard Accept/Done transaction. */
    private fun nativeState(native: LuaTimedActionNew): NativeState? {
        val player = native.chr as? IsoPlayer ?: return null
        if (
            native.forceStop ||
                !(native as BaseAction).started ||
                !native.waitForFinished ||
                !Accessor.tryGet<Boolean>(native, "started", false) ||
                Accessor.tryGet<Boolean>(native, "useCustomRemoteTimedActionSync", true) ||
                player.isDead ||
                !player.isLocalPlayer
        )
            return null
        val actions = player.getCharacterActions() ?: return null
        if (actions.isEmpty() || actions[0] !== native) return null
        val owner = Accessor.tryGet<PlayerID>(native, "playerId", null) ?: return null
        val id = Accessor.tryGet<Byte>(native, "transactionId", null) ?: return null
        if (id.toInt() == 0 || owner.getPlayer() !== player || owner.getID() != player.onlineId)
            return null
        val transactions =
            Accessor.tryGet<ConcurrentLinkedQueue<*>>(ActionManager::class.java, "actions", null)
                ?: return null
        var found: NativeState? = null
        for (candidate in transactions) {
            val candidateId = Accessor.tryGet<Byte>(candidate, "id", null)
            val candidateOwner = Accessor.tryGet<PlayerID>(candidate, "playerId", null) ?: continue
            if (candidateId != id || candidateOwner.getID() != owner.getID()) continue
            if (
                found != null ||
                    candidate !is NetTimedAction ||
                    candidateOwner.getPlayer() !== player
            )
                return null
            val state = Accessor.tryGet<TransactionState>(candidate, "state", null)
            if (state != TransactionState.Accept && state != TransactionState.Done) return null
            found = NativeState(candidate, id, state == TransactionState.Done)
        }
        return found
    }

    private fun permitted(native: LuaTimedActionNew, name: String): Boolean {
        val toolkit = LuaManager.env?.rawget("PZSurvivorToolkit") as? KahluaTable ?: return false
        val lifecycle = toolkit.rawget("ActionQueueLifecycle") as? KahluaTable ?: return false
        val allow = lifecycle.rawget(name) ?: return false
        val result = LuaManager.caller.pcall(LuaManager.thread, allow, native.getTable(), native)
        return result.size >= 2 && true.equals(result[0]) && true.equals(result[1])
    }

    private fun unchanged(
        native: LuaTimedActionNew,
        state: NativeState,
        wait: NativeWait?,
    ): NativeState? {
        if (wait != null && (wait.revoked || System.nanoTime() - wait.deadlineNanos >= 0))
            return null
        val current = nativeState(native) ?: return null
        if (
            current.id != state.id ||
                current.transaction !== state.transaction ||
                (state.done || wait?.doneObserved == true) && !current.done
        )
            return null
        if (current.done && wait != null) wait.doneObserved = true
        return current
    }

    /** Only a genuine native start may retire the previous episode's terminal revocation. */
    @JvmStatic
    fun nativeStarted(native: LuaTimedActionNew?, supported: Boolean) {
        if (supported && native != null) waits.remove(native)
    }

    /** Let the original engine settle a paid remote action whose target was already replicated. */
    @JvmStatic
    fun restoreNativeCompletion(
        nativeAction: LuaTimedActionNew?,
        valid: Boolean,
        supported: Boolean,
    ): Boolean {
        val native = nativeAction ?: return valid
        val wait = waits[native]
        if (
            !supported ||
                !GameClient.client ||
                !QueueManagers.ACTION_SUPPORTED ||
                !ActionAcknowledgements.SUPPORTED
        ) {
            if (wait != null) wait.revoked = true
            return valid
        }
        if (wait?.performed == true) return valid
        if (valid && wait == null) return true
        if (wait?.revoked == true) return false
        val state = nativeState(native)
        if (
            state == null ||
                wait != null &&
                    (wait.id != state.id ||
                        wait.transaction.get() !== state.transaction ||
                        wait.doneObserved && !state.done ||
                        System.nanoTime() - wait.deadlineNanos >= 0)
        ) {
            if (wait != null) wait.revoked = true
            return false
        }
        if (state.done && wait != null) wait.doneObserved = true
        // Replicated effects can invalidate Lua while the native terminal packet is
        // still in flight. Accept grants only a bounded hold, never completion.
        val completed = state.done && permitted(native, "allowNativeCompletion")
        val checked = unchanged(native, state, wait)
        if (checked == null) {
            if (wait != null) wait.revoked = true
            return false
        }
        if (completed) {
            // Preserve the original perform boundary, without running the stale Lua update first.
            native.forceComplete()
            return true
        }
        val waiting = permitted(native, "allowNativeCompletionWait")
        val held = if (waiting) unchanged(native, checked, wait) else null
        if (held == null) {
            if (wait != null) wait.revoked = true
            return false
        }
        if (wait == null) waits[native] = NativeWait(state.transaction, state.id, held.done)
        return true
    }

    /** The original update runs Lua before checking Done; a held episode must bypass both. */
    @JvmStatic
    fun skipNativeUpdate(native: LuaTimedActionNew?, supported: Boolean): Boolean {
        if (
            !supported ||
                !GameClient.client ||
                !QueueManagers.ACTION_SUPPORTED ||
                !ActionAcknowledgements.SUPPORTED ||
                native == null ||
                waits[native] == null
        )
            return false
        if (waits[native]?.performed == true) return false
        if (!restoreNativeCompletion(native, false, supported)) native.forceStop()
        return true
    }

    /** Queue-off native callbacks still need their protected Lua result observed. */
    @JvmStatic
    fun needsNativeWaitObservation(native: LuaTimedActionNew?, supported: Boolean): Boolean {
        if (
            !supported ||
                !GameClient.client ||
                !QueueManagers.ACTION_SUPPORTED ||
                !ActionAcknowledgements.SUPPORTED ||
                native == null
        )
            return false
        val wait = waits[native] ?: return false
        return !wait.revoked && !wait.performed
    }

    @JvmStatic
    fun captureNativePerform(native: LuaTimedActionNew?, scope: Scope?) {
        if (native == null || scope == null) return
        val wait = waits[native] ?: return
        if (!wait.revoked && !wait.performed) scope.nativeWait = wait
    }

    @JvmStatic
    fun nativePerformed(native: LuaTimedActionNew?, scope: Scope?, failure: Throwable?) {
        if (native == null) return
        val wait = waits[native] ?: return
        // A nested callback can start the same native object again. Its new episode is unrelated.
        if (scope == null || scope.nativeWait !== wait) return
        if (failure != null || scope.failed) wait.revoked = true else wait.performed = true
    }

    class Scope(
        previous: Scope?,
        action: KahluaTable?,
        callback: Any?,
        finish: Any?,
        phase: String?,
    ) {
        @JvmField val previous = previous
        @JvmField val action = action
        @JvmField val callback = callback
        @JvmField val finish = finish
        @JvmField val phase = phase
        @JvmField var failed = false
        internal var nativeWait: Any? = null
    }

    @JvmStatic
    fun begin(nativeAction: LuaTimedActionNew?, phase: String?, supported: Boolean): Scope? {
        if (!supported || LuaManager.env == null) return null
        val toolkit = LuaManager.env.rawget("PZSurvivorToolkit")
        val lifecycle = if (toolkit is KahluaTable) toolkit.rawget("ActionQueueLifecycle") else null
        if (lifecycle !is KahluaTable) return null
        val begin = lifecycle.rawget("begin")
        val finish = lifecycle.rawget("finish")
        if (begin == null || finish == null) return null
        val action: KahluaTable? = (nativeAction ?: throw NullPointerException()).getTable()
        val result = LuaManager.caller.pcall(LuaManager.thread, begin, action, phase)
        if (result.size < 2 || !true.equals(result[0]) || !true.equals(result[1])) return null
        val scope =
            Scope(
                current.get(),
                action,
                (action ?: throw NullPointerException()).rawget(phase),
                finish,
                phase,
            )
        current.set(scope)
        return scope
    }

    /** Observe an exact native callback without taking ownership of Lua queue completion. */
    @JvmStatic
    fun observeOnly(nativeAction: LuaTimedActionNew?, phase: String?): Scope? {
        val action: KahluaTable? = (nativeAction ?: throw NullPointerException()).getTable()
        if (action == null || action.rawget(phase) == null) return null
        val scope = Scope(current.get(), action, action.rawget(phase), null, phase)
        current.set(scope)
        return scope
    }

    @JvmStatic
    fun observe(callback: Any?, argument: Any?, result: Array<out Any?>?) {
        val scope = current.get()
        if (
            scope != null &&
                scope.callback != null &&
                scope.callback === callback &&
                scope.action === argument &&
                (result == null ||
                    result.isEmpty() ||
                    !true.equals(result[0]) ||
                    "complete" == scope.phase && result.size > 1 && false.equals(result[1]))
        )
            scope.failed = true
    }

    @JvmStatic
    fun end(scope: Scope?, failure: Throwable?) {
        if (scope == null) return
        if (scope.previous == null) current.remove() else current.set(scope.previous)
        if (scope.finish != null)
            LuaManager.caller.pcall(
                LuaManager.thread,
                scope.finish,
                scope.action,
                scope.phase,
                failure == null && !scope.failed,
            )
    }
}
