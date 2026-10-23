package net.alexredby.pztoolkitjavapatches

import java.util.concurrent.ConcurrentLinkedQueue
import me.zed_0xff.zombie_buddy.Accessor
import zombie.core.ActionManager
import zombie.core.Transaction
import zombie.core.Transaction.TransactionState
import zombie.core.TransactionManager
import zombie.core.raknet.UdpConnection
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.fields.character.PlayerID
import zombie.network.packets.ItemTransactionPacket

internal object QueueManagersLogic {
    @JvmField
    val ITEM_SUPPORTED = BytecodeSupport.supports("zombie/core/TransactionManager.class",
        "4a0f649f5e55edd13eff7d6788934fbec49e0073901609e1c12731fc47d7481d") &&
        BytecodeSupport.supports("zombie/core/Transaction.class",
            "107b0a554cc46d1015398ff283a2e48faf02efbc44adf12854f66394ee2487b6") &&
        BytecodeSupport.supports("zombie/network/packets/ItemTransactionPacket.class",
            "41608a6690d16cb0ac202a4a3196b2b0851dadb935bca2b1d9a0a3e501791e83") &&
        BytecodeSupport.supports("zombie/core/raknet/UdpConnection.class",
            "9c9bb471ff0c3dccdd0e52a3bb3c770327d02f0ad262187f950e660b2730e763")

    @JvmField
    val ACTION_SUPPORTED = BytecodeSupport.supports("zombie/core/ActionManager.class",
        "3e85655f0d287837b17164d2ee4cecb7067ab419ffbe8ce1adb36bd7d54b202f") &&
        BytecodeSupport.supports("zombie/core/Action.class",
            "4a2fe6aaf0cf73235279946e930b40489ec44859aff64cc19d97976bcc75610d")

    @JvmStatic
    fun beginReject(packet: ItemTransactionPacket?, connection: UdpConnection?, scopes: ThreadLocal<QueueManagers.RejectScope>): QueueManagers.RejectScope? {
        if (!ITEM_SUPPORTED || !GameServer.server || GameClient.client ||
            Accessor.tryGet<TransactionState>(packet, "state", null) != TransactionState.Reject) return null
        return QueueManagers.RejectScope(connection, scopes.get()).also { scopes.set(it) }
    }

    @JvmStatic
    fun endReject(scope: QueueManagers.RejectScope?, scopes: ThreadLocal<QueueManagers.RejectScope>) {
        if (scope == null) return
        if (scope.previous == null) scopes.remove() else scopes.set(scope.previous)
    }

    @JvmStatic
    fun removeOwned(id: Byte, scopes: ThreadLocal<QueueManagers.RejectScope>): Boolean {
        val scope = scopes.get()
        if (!ITEM_SUPPORTED || scope == null) return false
        val transactions = Accessor.tryGet<ConcurrentLinkedQueue<Transaction>>(TransactionManager::class.java, "transactions", null)
        transactions?.removeIf { transaction ->
            val candidate = Accessor.tryGet<Byte>(transaction, "id", null)
            val owner = Accessor.tryGet<PlayerID>(transaction, "playerId", null)
            // Reject omits the player on the wire; only the receiving connection can establish ownership.
            candidate != null && candidate == id && scope.connection != null && owner != null &&
                scope.connection.havePlayer(owner.getPlayer())
        }
        return true
    }

    @JvmStatic
    fun hasAction(owner: PlayerID?, id: Byte): Boolean {
        val actions = Accessor.tryGet<ConcurrentLinkedQueue<*>>(ActionManager::class.java, "actions", null) ?: return false
        for (action in actions) {
            val candidate = Accessor.tryGet<Byte>(action, "id", null)
            val player = Accessor.tryGet<PlayerID>(action, "playerId", null)
            if (candidate != null && candidate == id && player != null &&
                player.getID() == (owner ?: throw NullPointerException()).getID()) return true
        }
        return false
    }
}
