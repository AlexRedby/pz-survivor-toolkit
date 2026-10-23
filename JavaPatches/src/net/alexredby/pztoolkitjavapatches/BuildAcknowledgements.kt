package net.alexredby.pztoolkitjavapatches

import java.util.UUID
import java.util.WeakHashMap
import me.zed_0xff.zombie_buddy.Accessor
import zombie.Lua.LuaManager
import zombie.core.BuildAction
import zombie.network.GameServer
import zombie.network.PacketTypes
import zombie.network.TableNetworkUtils
import zombie.network.fields.character.PlayerID

object BuildAcknowledgements {
    private val tokens = WeakHashMap<BuildAction?, String>()

    @JvmStatic
    @Synchronized
    fun started(action: BuildAction?) {
        val token = UUID.randomUUID().toString()
        tokens[action] = token
        send(action, token, "started")
    }

    @JvmStatic
    @Synchronized
    fun settled(action: BuildAction?, state: String?) {
        val token = tokens.remove(action)
        if (token != null) send(action, token, state)
    }

    private fun send(action: BuildAction?, token: String, state: String?) {
        val owner = Accessor.tryGet<PlayerID>(action, "playerId", null)
        val transaction = Accessor.tryGet<Byte>(action, "id", null)
        if (owner == null || owner.player == null || transaction == null || transaction.toInt() == 0) return
        val args = LuaManager.platform.newTable()
        args.rawset("player", owner.id.toDouble())
        args.rawset("transaction", transaction.toDouble())
        args.rawset("token", token)
        args.rawset("state", state)
        val connection = GameServer.getConnectionFromPlayer(owner.player) ?: return
        try {
            val writer = connection.startPacket()
            PacketTypes.PacketType.ClientCommand.doPacket(writer)
            writer.putUTF("PZSurvivorToolkitBuild")
            writer.putUTF("State")
            writer.putBoolean(true)
            TableNetworkUtils.save(args, writer)
            // Share BuildAction's ordered channel so an old start cannot attach to a reused byte ID.
            connection.endPacket(1, 3, 1.toByte())
        } catch (error: Exception) {
            connection.cancelPacket()
            throw IllegalStateException("Cannot send build acknowledgement", error)
        }
    }
}
