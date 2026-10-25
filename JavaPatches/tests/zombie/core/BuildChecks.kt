package zombie.core

import java.nio.ByteBuffer
import java.util.ArrayList
import java.util.HashMap
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.BuildAcknowledgements
import net.alexredby.pztoolkitjavapatches.BytecodeSupport
import net.alexredby.pztoolkitjavapatches.Main
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.vm.KahluaTable
import sun.misc.Unsafe
import zombie.GameTime
import zombie.Lua.LuaManager
import zombie.characters.IsoPlayer
import zombie.core.network.ByteBufferReader
import zombie.core.network.ByteBufferWriter
import zombie.core.raknet.UdpConnection
import zombie.core.raknet.UdpEngine
import zombie.inventory.InventoryItem
import zombie.iso.IsoCell
import zombie.iso.IsoWorld
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.TableNetworkUtils
import zombie.network.packets.GeneralActionPacket

object BuildChecks {
    private lateinit var unsafe: Unsafe
    private lateinit var connection: Connection

    class Player : IsoPlayer(null) {
        override fun getPrimaryHandItem(): InventoryItem? = null
    }

    class Connection : UdpConnection(null, 0, 0) {
        lateinit var bytes: ByteBuffer
        lateinit var messages: ArrayList<KahluaTable>

        override fun startPacket(): ByteBufferWriter {
            bytes.clear()
            return ByteBufferWriter(bytes)
        }

        override fun isFullyConnected(): Boolean = false

        override fun endPacket(priority: Int, reliability: Int, channel: Byte) {
            require(
                reliability == 3 && channel.toInt() == 1,
                "acknowledgements must share native build ordering",
            )
            bytes.flip()
            val reader = ByteBufferReader(bytes)
            reader.getByte()
            reader.getShort()
            val module = reader.getUTF()
            val command = reader.getUTF()
            if (module == "PZSurvivorToolkitActions") return
            if (module != "PZSurvivorToolkitBuild" || command != "State")
                throw AssertionError("unexpected command $module/$command")
            if (!reader.getBoolean()) throw AssertionError("missing payload")
            val data = LuaManager.platform.newTable()
            try {
                TableNetworkUtils.load(data, reader)
            } catch (error: Exception) {
                throw AssertionError(error)
            }
            messages.add(data)
        }
    }

    class Build : BuildAction() {
        var performed = 0

        override fun getDuration(): Float = 10000f

        // Count only native scheduled completion; the actual BuildAction.perform remains woven.
        override fun perform(): Boolean {
            performed++
            return super.perform()
        }
    }

    private fun set(owner: Any, name: String, value: Any?) {
        val field = owner.javaClass.getDeclaredField(name).apply { isAccessible = true }
        field.set(owner, value)
    }

    private fun require(condition: Boolean, message: String) {
        if (!condition) throw AssertionError(message)
    }

    private fun build(player: IsoPlayer, id: Byte): Build {
        val action = Build()
        action.playerId.setID(player.onlineId)
        require(Accessor.trySet(action.playerId, "player", player), "fixture owner")
        action.id = id
        action.item = LuaManager.platform.newTable()
        ActionManager.start(action)
        action.state = Transaction.TransactionState.Accept
        return action
    }

    private fun last(state: String): KahluaTable {
        val data = connection.messages.last()
        require(state == data.rawget("state"), "expected $state got ${data.rawget("state")}")
        require(
            data.rawget("player") is Double && data.rawget("transaction") is Double,
            "wire IDs must use Lua numbers",
        )
        require(data.rawget("token") is String, "wire token must be a string")
        return data
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        var field = Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }
        unsafe = field.get(null) as Unsafe
        GameTime.setInstance(GameTime())
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = LuaManager.platform.newTable()
        LuaManager.env.rawset("Events", LuaManager.platform.newTable())
        LuaManager.thread = se.krka.kahlua.vm.KahluaThread(LuaManager.platform, LuaManager.env)
        LuaManager.thread.debugOwnerThread = Thread.currentThread()
        LuaManager.caller =
            se.krka.kahlua.integration.LuaCaller(se.krka.kahlua.converter.KahluaConverterManager())
        IsoWorld.instance.currentCell = unsafe.allocateInstance(IsoCell::class.java) as IsoCell
        require(
            Accessor.trySet(
                zombie.network.ServerMap.instance,
                "grid",
                unsafe.allocateInstance(zombie.iso.IsoMetaGrid::class.java),
            ),
            "fixture server grid",
        )
        connection = unsafe.allocateInstance(Connection::class.java) as Connection
        connection.bytes = ByteBuffer.allocate(4096)
        connection.messages = ArrayList()
        val engine = unsafe.allocateInstance(UdpEngine::class.java) as UdpEngine
        set(engine, "connectionMap", HashMap(mapOf(1L to connection)))
        GameServer.udpEngine = engine
        val player = unsafe.allocateInstance(Player::class.java) as IsoPlayer
        player.onlineId = 19
        GameServer.PlayerToAddressMap.put(player, 1L)
        GameClient.client = false
        GameServer.server = true

        val baseline = build(player, (-126).toByte())
        require(connection.messages.isEmpty(), "unpatched engine already acknowledged start")
        ActionManager.stop(baseline)
        require(connection.messages.isEmpty(), "unpatched engine already acknowledged stop")

        PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            BuildChecks::class.java.classLoader,
        )
        require(Main.BUILD_SUPPORTED, "unsupported native engine")
        val canceled = build(player, (-126).toByte())
        val started = last("started")
        require(
            started.rawget("transaction") == -126.0 && started.rawget("player") == 19.0,
            "wrong owner/id",
        )
        val otherPlayer = unsafe.allocateInstance(Player::class.java) as IsoPlayer
        otherPlayer.onlineId = 20
        val other = build(otherPlayer, (-126).toByte())
        val reject = GeneralActionPacket()
        reject.id = (-126).toByte()
        reject.playerId.copy(canceled.playerId)
        reject.state = Transaction.TransactionState.Reject
        reject.processServer(null, connection)
        var terminal = last("canceled")
        require(terminal.rawget("token") == started.rawget("token"), "stop changed token")
        var messages = connection.messages.size
        reject.processServer(null, connection)
        canceled.endTime = 0
        ActionManager.update()
        require(
            connection.messages.size == messages && canceled.performed == 0,
            "duplicate reject or late update re-completed canceled build",
        )
        require(
            other.state == Transaction.TransactionState.Accept && other.performed == 0,
            "same byte ID canceled another player's build",
        )
        ActionManager.stop(other)

        val completed = build(player, (-126).toByte())
        val secondStart = last("started")
        require(
            secondStart.rawget("token") != started.rawget("token"),
            "reused byte id reused token",
        )
        completed.endTime = 0
        ActionManager.update()
        terminal = last("completed")
        require(
            terminal.rawget("token") == secondStart.rawget("token") && completed.performed == 1,
            "completion lost identity",
        )
        messages = connection.messages.size
        reject.processServer(null, connection)
        completed.stop()
        ActionManager.update()
        require(
            connection.messages.size == messages && completed.performed == 1,
            "completed build emitted cancellation or replayed",
        )

        val untracked = Build()
        untracked.stop()
        require(connection.messages.size == messages, "untracked stop acknowledged cancellation")
        GameServer.server = false
        GameClient.client = true
        canceled.stop()
        require(connection.messages.size == messages, "client emitted server acknowledgement")
        field =
            BuildAcknowledgements::class.java.getDeclaredField("tokens").apply {
                isAccessible = true
            }
        require((field.get(null) as Map<*, *>).isEmpty(), "terminal builds retained tokens")
        require(
            !BytecodeSupport.supports("zombie/core/BuildAction.class", "unknown"),
            "unknown engine fingerprint accepted",
        )
        println(
            "BUILD_CHECKS_PASS (native reject, completion race, token cleanup, reused byte ID, wire serialization, authority guards)",
        )
    }
}
