package zombie.core

import java.lang.reflect.Field
import java.nio.ByteBuffer
import java.util.ArrayList
import java.util.HashMap
import me.zed_0xff.zombie_buddy.Accessor
import net.alexredby.pztoolkitjavapatches.ActionAcknowledgementLogic
import net.alexredby.pztoolkitjavapatches.ActionAcknowledgements
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.KahluaTable
import sun.misc.Unsafe
import zombie.GameTime
import zombie.Lua.LuaManager
import zombie.characters.IsoPlayer
import zombie.characters.CharacterTimedActions.LuaTimedActionNew
import zombie.core.network.ByteBufferReader
import zombie.core.network.ByteBufferWriter
import zombie.core.raknet.UdpConnection
import zombie.core.raknet.UdpEngine
import zombie.iso.IsoCell
import zombie.iso.IsoWorld
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.PacketTypes
import zombie.network.TableNetworkUtils

object ActionAcknowledgementChecks {
    private lateinit var unsafe: Unsafe
    private const val ID: Byte = -126

    class Player : IsoPlayer(null) {
        override fun getPrimaryHandItem(): zombie.inventory.InventoryItem? = null
        override fun isCurrentState(state: zombie.ai.State?): Boolean = false
    }

    class Connection : UdpConnection(null, 0, 0) {
        lateinit var bytes: ByteBuffer
        lateinit var messages: ArrayList<KahluaTable>
        lateinit var order: ArrayList<String>
        var fail = false
        var canceled = 0
        override fun isFullyConnected(): Boolean = true
        override fun startPacket(): ByteBufferWriter {
            bytes.clear()
            return ByteBufferWriter(bytes)
        }
        override fun cancelPacket() { canceled++ }
        override fun endPacket(priority: Int, reliability: Int, channel: Byte) {
            require(reliability == 3 && channel.toInt() == 1, "receipt/native action lost ordered channel 1")
            bytes.flip()
            val reader = ByteBufferReader(bytes)
            reader.getByte()
            val type = reader.getShort()
            if (type == PacketTypes.PacketType.ClientCommand.id) {
                val module = reader.getUTF()
                val command = reader.getUTF()
                if (fail && module == "PZSurvivorToolkitActions") throw IllegalStateException("fixture receipt transport unavailable")
                require(command == "State" && reader.getBoolean(), "invalid receipt envelope")
                val data = LuaManager.platform.newTable()
                try {
                    TableNetworkUtils.load(data, reader)
                } catch (error: Exception) {
                    throw AssertionError(error)
                }
                require(module == "PZSurvivorToolkitActions" || module == "PZSurvivorToolkitBuild", "unknown receipt module")
                order.add("$module:${data.rawget("state")}")
                if (module == "PZSurvivorToolkitActions") messages.add(data)
            } else {
                require(type == PacketTypes.PacketType.BuildAction.id || type == PacketTypes.PacketType.NetTimedAction.id,
                    "unexpected native packet")
                reader.getByte()
                order.add("native:${reader.getEnum(Transaction.TransactionState::class.java)}")
            }
        }
    }

    class Build : BuildAction() {
        var performed = 0
        override fun getDuration(): Float = 10000f
        override fun perform(): Boolean { performed++; return super.perform() }
    }

    private fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }
    private fun field(type: Class<*>, name: String): Field = type.getDeclaredField(name).apply { isAccessible = true }

    private fun connection(): Connection {
        val result = unsafe.allocateInstance(Connection::class.java) as Connection
        result.bytes = ByteBuffer.allocate(8192)
        result.messages = ArrayList()
        result.order = ArrayList()
        require(Accessor.trySet(result, "limits", HashMap<Any, Any>()), "fixture connection packet limits")
        return result
    }

    private fun player(id: Short, address: Long): IsoPlayer {
        val result = unsafe.allocateInstance(Player::class.java) as IsoPlayer
        result.onlineId = id
        require(Accessor.trySet(result, "ecsComponentMap", HashMap<Any, Any>()), "fixture player components")
        GameServer.PlayerToAddressMap.put(result, address)
        return result
    }

    private fun identify(action: Action, player: IsoPlayer) {
        action.id = ID
        action.state = Transaction.TransactionState.Request
        action.playerId.setID(player.onlineId)
        require(Accessor.trySet(action.playerId, "player", player), "fixture owner")
    }

    private fun timed(player: IsoPlayer, succeeds: Boolean): NetTimedAction {
        val action = NetTimedAction()
        identify(action, player)
        action.type = "ToolkitAckProbe"
        val code = "return {performed=0, stopped=0, getDuration=function(self) return 10000 end, " +
            "adjustMaxTime=function(self,duration) return duration+0 end, " +
            "serverStop=function(self) self.stopped=self.stopped+1 end, " +
            "complete=function(self) self.performed=self.performed+1 return $succeeds end}"
        action.action = LuaManager.thread.call(LuaCompiler.loadstring(code, "ToolkitAckProbe", LuaManager.env), null, null, null) as KahluaTable
        return action
    }

    private fun build(player: IsoPlayer): Build = Build().apply {
        identify(this, player)
        item = LuaManager.platform.newTable()
    }

    private fun nativeClientAction(player: IsoPlayer, custom: Boolean, type: String): LuaTimedActionNew {
        val action = unsafe.allocateInstance(LuaTimedActionNew::class.java) as LuaTimedActionNew
        val table = LuaManager.thread.call(LuaCompiler.loadstring(
            "return {Type='$type', start=function(self) self.transactionId=-126 end, " +
                "name='ack-client', getDuration=function(self) return 10000 end, isUsingTimeout=function(self) return true end}",
            "ToolkitClientAckProbe", LuaManager.env), null, null, null) as KahluaTable
        val metatable = LuaManager.platform.newTable()
        metatable.rawset("Type", type)
        metatable.rawset("new", LuaCompiler.loadstring("return nil", "new", LuaManager.env))
        table.metatable = metatable
        require(Accessor.trySet(action, "table", table) && Accessor.trySet(action, "chr", player) &&
            Accessor.trySet(action, "useCustomRemoteTimedActionSync", custom) &&
            Accessor.trySet(action, "playerId", zombie.network.fields.character.PlayerID()), "fixture native Lua action")
        return action
    }

    private fun start(action: Action) {
        ActionManager.start(action)
        action.state = Transaction.TransactionState.Accept
    }

    private fun last(connection: Connection, state: String): KahluaTable {
        require(connection.messages.isNotEmpty(), "missing $state receipt")
        val data = connection.messages.last()
        require(state == data.rawget("state"), "wrong terminal state: ${data.rawget("state")}")
        require(1.0.equals(data.rawget("protocol")) && data.rawget("player") is Double && ID.toDouble().equals(data.rawget("transaction")),
            "invalid native wire identity")
        val token = data.rawget("token")
        require(token is String && token.length == 36, "missing UUID identity")
        return data
    }

    private fun settle(action: Action) { action.endTime = 0; ActionManager.update() }
    private fun sameToken(started: KahluaTable, terminal: KahluaTable) {
        require(started.rawget("token") == terminal.rawget("token"), "terminal changed action token")
    }
    private fun ordered(connection: Connection, nativeState: String, receipt: String) {
        require(connection.order.lastIndexOf("native:$nativeState") < connection.order.lastIndexOf("PZSurvivorToolkitActions:$receipt") &&
            connection.order.contains("native:$nativeState"), "receipt preceded native outcome")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        unsafe = field(Unsafe::class.java, "theUnsafe").get(null) as Unsafe
        GameTime.setInstance(GameTime())
        LuaManager.platform = J2SEPlatform(); LuaManager.env = LuaManager.platform.newTable()
        LuaManager.env.rawset("Events", LuaManager.platform.newTable())
        LuaManager.thread = se.krka.kahlua.vm.KahluaThread(LuaManager.platform, LuaManager.env)
        LuaManager.thread.debugOwnerThread = Thread.currentThread()
        LuaManager.caller = se.krka.kahlua.integration.LuaCaller(se.krka.kahlua.converter.KahluaConverterManager())
        IsoWorld.instance.currentCell = unsafe.allocateInstance(IsoCell::class.java) as IsoCell
        require(Accessor.trySet(zombie.network.ServerMap.instance, "grid", unsafe.allocateInstance(zombie.iso.IsoMetaGrid::class.java)), "fixture grid")
        val first = connection()
        val second = connection()
        val engine = unsafe.allocateInstance(UdpEngine::class.java) as UdpEngine
        field(UdpEngine::class.java, "connectionMap").set(engine, HashMap(mapOf(1L to first, 2L to second)))
        GameServer.udpEngine = engine; GameServer.server = true; GameClient.client = false
        val player = player(19.toShort(), 1L)
        val other = player(20.toShort(), 2L)

        val baseline = timed(player, true); start(baseline); settle(baseline)
        require(1.0.equals(baseline.action.rawget("performed")) && first.messages.isEmpty(), "original native completion/receipt baseline changed")
        val baselineStop = timed(player, true); start(baselineStop); ActionManager.stop(baselineStop)
        require(1.0.equals(baselineStop.action.rawget("stopped")) && first.messages.isEmpty(), "original native cancellation baseline changed")
        GameServer.server = false; GameClient.client = true
        val baselineClient = nativeClientAction(player, true, "ISBuildAction"); baselineClient.start()
        require(baselineClient.getTable().rawget("toolkitNativeTransaction") == null, "unpatched client gained transaction proof")
        GameServer.server = true; GameClient.client = false
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", ActionAcknowledgementChecks::class.java.classLoader)
        require(ActionAcknowledgements.SUPPORTED, "unsupported native acknowledgement targets")

        val completed = timed(player, true); start(completed)
        var started = last(first, "started")
        require("ToolkitAckProbe" == started.rawget("kind") && 19.0.equals(started.rawget("player")), "wrong action type/owner")
        var count = first.messages.size; ActionAcknowledgements.started(completed)
        require(first.messages.size == count, "duplicate start emitted a token")
        settle(completed); sameToken(started, last(first, "completed")); ordered(first, "Done", "completed")
        count = first.messages.size; ActionManager.stop(completed); ActionManager.update()
        require(first.messages.size == count && 1.0.equals(completed.action.rawget("performed")), "completion-before-cancel replayed effects or receipts")

        val canceled = timed(player, true)
        val foreign = timed(other, true)
        start(canceled); started = last(first, "started"); start(foreign)
        require(started.rawget("token") != last(second, "started").rawget("token"), "different owners reused token")
        ActionManager.stop(canceled); sameToken(started, last(first, "canceled"))
        count = first.messages.size; ActionManager.stop(canceled); canceled.endTime = 0; ActionManager.update()
        require(first.messages.size == count && 0.0.equals(canceled.action.rawget("performed")) &&
            1.0.equals(canceled.action.rawget("stopped")), "cancel-before-update executed or duplicated cancellation")
        require(foreign.state == Transaction.TransactionState.Accept && second.messages.size == 1, "same byte id canceled another owner")
        ActionManager.stop(foreign); last(second, "canceled")
        val quietCancel = timed(player, true); start(quietCancel); started = last(first, "started")
        ActionManager.remove(quietCancel.playerId, quietCancel.id, false)
        sameToken(started, last(first, "canceled"))
        require(1.0.equals(quietCancel.action.rawget("stopped")), "server remove(false) did not preserve native stop")

        val reused = timed(player, false); start(reused)
        val reusedStart = last(first, "started")
        require(reusedStart.rawget("token") != started.rawget("token"), "reused byte id inherited old token")
        settle(reused); sameToken(reusedStart, last(first, "rejected")); ordered(first, "Reject", "rejected")
        require(1.0.equals(reused.action.rawget("performed")), "native Lua complete(false) not executed")

        val building = build(player); start(building); started = last(first, "started")
        require("build" == started.rawget("kind"), "build receipt used generic Lua type")
        settle(building); sameToken(started, last(first, "completed"))
        require(building.performed == 1, "build receipt bypassed native perform"); ordered(first, "Done", "completed")
        val stoppedBuild = build(player); start(stoppedBuild); started = last(first, "started")
        ActionManager.stop(stoppedBuild); sameToken(started, last(first, "canceled"))

        count = first.messages.size; GameServer.server = false
        val local = timed(player, true); start(local); ActionManager.stop(local)
        require(first.messages.size == count, "single-player emitted multiplayer permission receipts")
        GameClient.client = true; ActionAcknowledgements.started(timed(player, true))
        require(first.messages.size == count, "client emitted server receipt")
        GameClient.client = false; GameServer.server = true
        first.fail = true
        val transportFailure = timed(player, true); start(transportFailure); settle(transportFailure)
        require(transportFailure.state == Transaction.TransactionState.Done && 1.0.equals(transportFailure.action.rawget("performed")),
            "receipt transport failure interrupted native action lifecycle")
        first.fail = false
        require((field(ActionAcknowledgementLogic::class.java, "tokens").get(null) as Map<*, *>).isEmpty(), "terminal actions retained acknowledgement tokens")
        GameServer.server = false; GameClient.client = true; GameClient.connection = first
        val clientBuild = nativeClientAction(player, true, "ISBuildAction"); clientBuild.start()
        require(ID.toDouble().equals(clientBuild.getTable().rawget("toolkitNativeTransaction")) &&
            "build" == clientBuild.getTable().rawget("toolkitNativeKind"), "woven native client start did not bind custom build id")
        val unknownCustom = nativeClientAction(player, true, "OtherCustomAction"); unknownCustom.start()
        require(unknownCustom.getTable().rawget("toolkitNativeTransaction") == null, "unsupported custom synchronizer gained proof")
        val standard = nativeClientAction(player, false, "ToolkitAckProbe"); standard.start()
        val nativeId = Accessor.tryGet<Byte>(standard, "transactionId", null)
        require(nativeId != null && nativeId.toInt() != 0 && nativeId.toDouble().equals(standard.getTable().rawget("toolkitNativeTransaction")) &&
            "ToolkitAckProbe" == standard.getTable().rawget("toolkitNativeKind"), "woven standard start did not bind native manager id/type: native=" +
            "$nativeId, proof=${standard.getTable().rawget("toolkitNativeTransaction")}, kind=${standard.getTable().rawget("toolkitNativeKind")}")
        println("ACTION_ACKNOWLEDGEMENT_CHECKS_PASS (native Lua completion true/false, build, cancellation races, duplicate/reused IDs, owner isolation, ordered wire, role guards, transport failure)")
    }
}
