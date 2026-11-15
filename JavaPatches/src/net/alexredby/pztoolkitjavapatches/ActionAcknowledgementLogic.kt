package net.alexredby.pztoolkitjavapatches

import java.util.ArrayList
import java.util.UUID
import java.util.WeakHashMap
import me.zed_0xff.zombie_buddy.Accessor
import zombie.Lua.LuaManager
import zombie.characters.CharacterTimedActions.LuaTimedActionNew
import zombie.characters.IsoPlayer
import zombie.core.BuildAction
import zombie.core.NetTimedAction
import zombie.core.Transaction.TransactionState
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.PacketTypes
import zombie.network.TableNetworkUtils
import zombie.network.fields.character.ConnectionPlayer

/** Called under the original ActionAcknowledgements class monitor by its Java entry points. */
internal object ActionAcknowledgementLogic {
    @JvmField
    val supported =
        Main.BUILD_SUPPORTED &&
            BytecodeSupport.supports(
                "zombie/core/NetTimedAction.class",
                "d4a3046eeaec409977a756c6ea80b0676229274684012ad51210559ebfcb1090",
            ) &&
            BytecodeSupport.supports(
                "zombie/characters/CharacterTimedActions/LuaTimedActionNew.class",
                "020a9e5c22b25bdffca7f396612d420e9cea6f78f7432015ac146f19728ac1a6",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/packets/NetTimedActionPacket.class",
                "9cb604c83db6c649df060cf3228b475163aebb1232a8926deaf13a5b3d2394bc",
            )
    private val tokens = WeakHashMap<Any, String>()

    @JvmStatic
    fun started(action: Any?) {
        if (
            !supported ||
                !GameServer.server ||
                (action !is BuildAction && action !is NetTimedAction) ||
                tokens.containsKey(action)
        )
            return
        val token = UUID.randomUUID().toString()
        tokens[action] = token
        send(action, token, "started")
    }

    @JvmStatic
    fun pending(): ArrayList<Any>? =
        if (supported && GameServer.server) ArrayList(tokens.keys) else null

    @JvmStatic
    fun settled(before: ArrayList<Any>?, removed: Boolean) {
        if (before == null || !GameServer.server) return
        for (action in before) {
            val state = Accessor.tryGet<TransactionState>(action, "state", null)
            val outcome =
                when {
                    state == TransactionState.Done -> "completed"
                    state == TransactionState.Reject -> "rejected"
                    removed -> "canceled"
                    else -> continue
                }
            val token = tokens.remove(action)
            if (token != null) send(action, token, outcome)
        }
    }

    @JvmStatic
    fun removing(player: IsoPlayer?, id: Byte): ArrayList<Any>? {
        if (!supported || !GameServer.server || player == null) return null
        val result = ArrayList<Any>()
        for (action in tokens.keys) {
            val owner = Accessor.tryGet<ConnectionPlayer>(action, "player", null)?.getPlayer()
            val transaction = Accessor.tryGet<Byte>(action, "id", null)
            if (
                owner != null &&
                    owner.onlineId == player.onlineId &&
                    transaction != null &&
                    transaction == id
            )
                result.add(action)
        }
        return result
    }

    private fun send(action: Any, token: String, state: String) {
        val owner = Accessor.tryGet<ConnectionPlayer>(action, "player", null)
        val transaction = Accessor.tryGet<Byte>(action, "id", null)
        if (
            owner == null ||
                owner.getPlayer() == null ||
                transaction == null ||
                transaction.toInt() == 0
        )
            return
        val connection = GameServer.getConnectionFromPlayer(owner.getPlayer()) ?: return
        val args = LuaManager.platform.newTable()
        args.rawset("protocol", 1.0)
        args.rawset("player", owner.getPlayer().onlineId.toDouble())
        args.rawset("transaction", transaction.toDouble())
        args.rawset("token", token)
        args.rawset("state", state)
        args.rawset("kind", if (action is BuildAction) "build" else (action as NetTimedAction).type)
        try {
            val writer = connection.startPacket()
            PacketTypes.PacketType.ClientCommand.doPacket(writer)
            writer.putUTF("PZSurvivorToolkitActions")
            writer.putUTF("State")
            writer.putBoolean(true)
            TableNetworkUtils.save(args, writer)
            // Native Accept/Done and these receipts share reliable ordered channel 1.
            connection.endPacket(1, 3, 1.toByte())
        } catch (error: Exception) {
            connection.cancelPacket()
            System.err.println("[PZToolkitJavaPatches] Cannot send action acknowledgement: $error")
        }
    }

    @JvmStatic
    fun bind(nativeAction: LuaTimedActionNew?) {
        if (!supported || !GameClient.client) return
        val native = nativeAction ?: throw NullPointerException()
        val action = native.getTable()
        val custom = Accessor.tryGet<Boolean>(native, "useCustomRemoteTimedActionSync", true)
        val type = action.rawget("Type")
        val transaction =
            if (custom) action.rawget("transactionId")
            else Accessor.tryGet<Byte>(native, "transactionId", null)
        val id = transaction as? Number ?: return
        if (id.toByte().toInt() == 0 || (custom && "ISBuildAction" != type)) return
        action.rawset("toolkitNativeTransaction", id.toByte().toDouble())
        action.rawset("toolkitNativeKind", if (custom) "build" else type)
    }
}
