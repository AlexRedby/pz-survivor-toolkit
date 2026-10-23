package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Accessor
import se.krka.kahlua.vm.KahluaTable
import zombie.Lua.LuaManager
import zombie.characters.CharacterTimedActions.BaseAction
import zombie.characters.CharacterTimedActions.LuaTimedActionNew
import zombie.characters.IsoPlayer
import zombie.core.ActionManager
import zombie.network.GameClient
import zombie.network.fields.character.PlayerID

object ActionCompletion {
    private val current = ThreadLocal<Scope>()

    /** Let the original engine settle a paid remote action whose target was already replicated. */
    @JvmStatic
    fun restoreNativeCompletion(
        nativeAction: LuaTimedActionNew?,
        valid: Boolean,
        supported: Boolean,
    ): Boolean {
        if (valid || !supported || !GameClient.client || !QueueManagers.ACTION_SUPPORTED)
            return valid
        val native = nativeAction ?: return false
        val player = native.chr as? IsoPlayer ?: return false
        if (
            native.forceStop ||
                !(native as BaseAction).started ||
                !Accessor.tryGet<Boolean>(native, "started", false) ||
                Accessor.tryGet<Boolean>(native, "useCustomRemoteTimedActionSync", true) ||
                player.isDead ||
                !player.isLocalPlayer
        )
            return false
        val actions = player.getCharacterActions() ?: return false
        if (actions.isEmpty() || actions[0] !== native) return false
        val owner = Accessor.tryGet<PlayerID>(native, "playerId", null) ?: return false
        val id = Accessor.tryGet<Byte>(native, "transactionId", null) ?: return false
        if (
            id.toInt() == 0 ||
                owner.getPlayer() !== player ||
                owner.getID() != player.onlineId ||
                !QueueManagers.hasAction(owner, id) ||
                !ActionManager.isDone(owner, id)
        )
            return false
        val toolkit = LuaManager.env?.rawget("PZSurvivorToolkit") as? KahluaTable ?: return false
        val lifecycle = toolkit.rawget("ActionQueueLifecycle") as? KahluaTable ?: return false
        val allow = lifecycle.rawget("allowNativeCompletion") ?: return false
        val result = LuaManager.caller.pcall(LuaManager.thread, allow, native.getTable(), native)
        if (
            result.size < 2 ||
                !true.equals(result[0]) ||
                !true.equals(result[1]) ||
                native.forceStop ||
                actions.isEmpty() ||
                actions[0] !== native ||
                !QueueManagers.hasAction(owner, id) ||
                !ActionManager.isDone(owner, id)
        )
            return false
        // Returning true alone would run Lua update before the engine notices Done. That final
        // update may invalidate a consumed target or forceStop, discarding the queued continuation.
        native.forceComplete()
        return true
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
