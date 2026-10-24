package net.alexredby.cartlab

import se.krka.kahlua.integration.annotations.LuaMethod
import zombie.characters.IsoPlayer
import zombie.core.ActionManager
import zombie.core.NetTimedAction
import zombie.core.Transaction.TransactionState
import zombie.network.fields.character.PlayerID

/** Owned destructive fixture input, separately gated from the read-only admission observer. */
object ActionInvalidation {
    @JvmStatic fun initialize() = Unit

    @JvmStatic
    @LuaMethod(name = "cartActionInvalidationStop", global = true)
    fun stop(player: IsoPlayer?, token: String?, epoch: Double): Boolean {
        check(System.getenv("PZ_CART_ACTION_INVALIDATION") == "true") {
            "Explicit action invalidation fixture required"
        }
        check(ActionAdmission.ACTION_ADMISSION && !ActionAdmission.actionAdmissionFailed)
        check(player != null && LeaseControl.leaseControlValidatedServerScope() != null)
        val source = LeaseControl.cartLeaseSource(player)
        check(source != null && ActionAdmission.actionAdmissionRegistered(player, source)) {
            "Exact native owner source required"
        }
        val row = checkNotNull(ActionAdmission.cartActionAdmission(player))
        check(token != null && row.rawget("token") == token && row.rawget("actionEpoch") == epoch)
        check(row.rawget("stage") == "terminal" && row.rawget("reason") == "item-invalid")
        check(row.rawget("accepted") == true && row.rawget("admittedBindingValid") == true)
        check(row.rawget("nativeBindingValid") == false && row.rawget("nativeState") == "Accept")
        val actions = ActionManager::class.java.getDeclaredField("actions").apply { isAccessible = true }
            .get(null) as Collection<*>
        check(actions.size <= 4096)
        val matches = actions.filterIsInstance<NetTimedAction>().filter {
            NativeTime.nativeTimeIdentity(it, false).toDouble() == epoch
        }
        val action = matches.single()
        fun field(name: String): Any? = Class.forName("zombie.core.Action")
            .getDeclaredField(name).apply { isAccessible = true }.get(action)
        check(action.type == "ToolkitWoodCartPickup")
        check((field("playerId") as PlayerID).getPlayer() === player)
        check((field("id") as Byte).toDouble() == row.rawget("transaction"))
        check(field("state") == TransactionState.Accept)
        check(NativeTime.nativeTimeIdentity(action.action, false).toDouble() == row.rawget("tableEpoch"))
        // The real native stop owns cancellation, serverStop, queue removal and its owner receipt.
        // Its parameter type zombie.core.Action is package-private even though stop is public.
        ActionManager::class.java.getDeclaredMethod("stop", Class.forName("zombie.core.Action"))
            .apply { isAccessible = true }.invoke(null, action)
        check(actions.none { it === action })
        val after = checkNotNull(ActionAdmission.cartActionAdmission(player))
        check(after.rawget("token") == token && after.rawget("stage") == "terminal")
        check(after.rawget("reason") == "item-invalid" && after.rawget("nativeBindingValid") == false)
        return true
    }
}
