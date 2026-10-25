import java.io.ByteArrayOutputStream
import java.io.PrintStream
import java.lang.ref.WeakReference
import java.nio.ByteBuffer
import java.util.UUID
import net.alexredby.cartlab.ActionAdmission
import net.alexredby.cartlab.ActionAdmission.ActionAdmissionRecord
import net.alexredby.cartlab.ActionAdmission.ActionAdmissionScope
import net.alexredby.cartlab.LeaseControl
import net.alexredby.pztoolkitjavapatches.ActionAcknowledgements
import se.krka.kahlua.vm.KahluaTable
import zombie.Lua.LuaManager
import zombie.characters.IsoPlayer
import zombie.core.NetTimedAction
import zombie.core.Transaction.TransactionState
import zombie.core.network.ByteBufferReader
import zombie.core.network.ByteBufferWriter
import zombie.core.raknet.UdpConnection
import zombie.core.raknet.UdpEngine
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.PacketTypes
import zombie.network.TableNetworkUtils

/** Native action observations must serialize missing tokens and keep refusal absorbing. */
object ActionAdmissionCheck {
    class Owner : IsoPlayer(null, null, 0, 0, 0) {
        override fun getOnlineID(): Short = 7

        override fun isDead(): Boolean = false
    }

    class Connection : UdpConnection(null, 1L, 0) {
        lateinit var bytes: ByteBuffer
        lateinit var receipts: MutableList<KahluaTable>

        override fun startPacket(): ByteBufferWriter {
            bytes.clear()
            return ByteBufferWriter(bytes)
        }

        override fun endPacket(priority: Int, reliability: Int, channel: Byte) {
            ensure(reliability == 3 && channel.toInt() == 1, "Native receipt lost ordered channel")
            bytes.flip()
            val reader = ByteBufferReader(bytes)
            reader.getByte()
            ensure(
                reader.getShort() == PacketTypes.PacketType.ClientCommand.getId() &&
                    reader.getUTF() == "PZSurvivorToolkitActions" &&
                    reader.getUTF() == "State" &&
                    reader.getBoolean(),
                "Production acknowledgement changed native envelope",
            )
            val receipt = LuaManager.platform.newTable()
            TableNetworkUtils.load(receipt, reader)
            receipts.add(receipt)
        }

        override fun cancelPacket() {
            throw AssertionError("Production native acknowledgement transport failed")
        }
    }

    class Engine : UdpEngine(0, 0, 1, null, false) {
        lateinit var connection: Connection

        override fun getActiveConnection(guid: Long): UdpConnection? =
            if (guid == 1L) connection else null
    }

    private fun field(owner: Class<*>, name: String) =
        owner.getDeclaredField(name).apply { isAccessible = true }

    @Suppress("UNCHECKED_CAST")
    private fun publishedTokenCheck() {
        ensure(ActionAcknowledgements.SUPPORTED, "Native acknowledgement target is unsupported")
        val unsafe = field(sun.misc.Unsafe::class.java, "theUnsafe").get(null) as sun.misc.Unsafe
        val owner =
            (unsafe.allocateInstance(Owner::class.java) as Owner).also {
                it.onlineId = 7
                it.playerIndex = 0
            }
        val connection =
            (unsafe.allocateInstance(Connection::class.java) as Connection).also {
                it.bytes = ByteBuffer.allocate(8192)
                it.receipts = mutableListOf()
            }
        val engine =
            (unsafe.allocateInstance(Engine::class.java) as Engine).also {
                it.connection = connection
            }
        val oldEngine = GameServer.udpEngine
        val previousAddress = GameServer.PlayerToAddressMap.put(owner, 1L)
        val actionOwner = Class.forName("zombie.core.Action")
        val playerField = field(actionOwner, "playerId")
        val idField = field(actionOwner, "id")
        val stateField = field(actionOwner, "state")
        fun nativeAction(id: Byte): NetTimedAction =
            NetTimedAction().also {
                it.type = "ToolkitWoodCartDrop"
                it.action = LuaManager.platform.newTable()
                idField.setByte(it, id)
                stateField.set(it, TransactionState.Request)
                val player = playerField.get(it) as zombie.network.fields.character.PlayerID
                player.setID(owner.onlineId)
                field(player.javaClass, "player").set(player, owner)
            }
        val action = nativeAction(1)
        val unrelated = nativeAction(2)
        val transport =
            LeaseControl.LeaseTransport(
                WeakReference(engine),
                WeakReference(connection),
                1L,
                1L,
                PacketTypes.PacketType.NetTimedAction.getId().toInt(),
            )
        val record =
            ActionAdmissionRecord().also {
                it.action = WeakReference(action)
                it.table = WeakReference(action.action)
                it.actor = WeakReference(owner)
                it.connection = WeakReference(connection)
                it.item = WeakReference(null)
                it.world = WeakReference(null)
                it.transport = transport
                it.kind = action.type
            }
        // This diagnostic scope supplies no native source authority or accepted binding.
        val scope =
            ActionAdmissionScope(
                null,
                ActionAdmission.ActionAdmissionParsed(
                    LeaseControl.LeaseCommandIngress(1L, transport),
                    1L,
                ),
                connection,
                null,
            )
        scope.starts.add(record)
        val scopes =
            field(ActionAdmission::class.java, "actionAdmissionScope").get(null)
                as ThreadLocal<ActionAdmissionScope>
        val previous = scopes.get()
        try {
            GameServer.udpEngine = engine
            scopes.set(scope)
            // The real synchronized production facade publishes the UUID and invokes the advice.
            ActionAcknowledgements.started(action)
            ensure(!ActionAdmission.actionAdmissionFailed, "Published-token observer failed")
            ensure(
                connection.receipts.size == 1,
                "Production start did not emit one native receipt",
            )
            val receipt = connection.receipts.single()
            val token = receipt.rawget("token") as? String
            ensure(
                token != null && UUID.fromString(token).toString() == token,
                "Production native receipt has no UUID token",
            )
            ensure(
                receipt.rawget("state") == "started" &&
                    receipt.rawget("player") == 7.0 &&
                    receipt.rawget("transaction") == 1.0 &&
                    record.token == token &&
                    record.pendingLogged &&
                    record.stage == "pending" &&
                    !record.accepted &&
                    !record.sourceValidated &&
                    !record.admittedBindingValid,
                "Admission did not observe the exact published token without granting authority",
            )
            ActionAcknowledgements.started(action)
            ensure(
                connection.receipts.size == 1 && record.token == token,
                "Repeated production start replaced the exact action token",
            )
            ActionAcknowledgements.started(unrelated)
            ensure(
                connection.receipts.size == 2 &&
                    connection.receipts.last().rawget("token") != token &&
                    record.token == token,
                "Another native action's token was attributed to this action",
            )
        } finally {
            if (previous == null) scopes.remove() else scopes.set(previous)
            stateField.set(action, TransactionState.Done)
            stateField.set(unrelated, TransactionState.Done)
            ActionAcknowledgements.settled(java.util.ArrayList(listOf(action, unrelated)), false)
            GameServer.udpEngine = oldEngine
            if (previousAddress == null) GameServer.PlayerToAddressMap.remove(owner)
            else GameServer.PlayerToAddressMap.put(owner, previousAddress)
        }
    }

    private fun ensure(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    @JvmStatic
    fun main(args: Array<String>) {
        ensure(
            ActionAdmission.ACTION_ADMISSION && LeaseControl.LEASE_CONTROL,
            "Admission regression requires the native observation flags",
        )
        val server = GameServer.server
        val client = GameClient.client
        val output = System.out
        val bytes = ByteArrayOutputStream()
        val capture = PrintStream(bytes, true, Charsets.UTF_8)
        try {
            GameServer.server = true
            GameClient.client = false
            val action =
                NetTimedAction().also {
                    it.type = "ToolkitWoodCartDrop"
                    it.action = se.krka.kahlua.j2se.J2SEPlatform.getInstance().newTable()
                }
            val state =
                Class.forName("zombie.core.Action").getDeclaredField("state").apply {
                    isAccessible = true
                }
            state.set(action, TransactionState.Request)
            val record =
                ActionAdmissionRecord().also {
                    it.action = WeakReference(action)
                    it.table = WeakReference(action.action)
                    it.actor = WeakReference(null)
                    it.connection = WeakReference(null)
                    it.item = WeakReference(null)
                    it.world = WeakReference(null)
                    it.transport =
                        LeaseControl.LeaseTransport(
                            WeakReference<UdpEngine>(null),
                            WeakReference<UdpConnection>(null),
                            1L,
                            1L,
                            PacketTypes.PacketType.NetTimedAction.getId().toInt(),
                        )
                    it.kind = action.type
                }
            val scope = ActionAdmissionScope(null, null, null, null)
            scope.starts.add(record)
            System.setOut(capture)
            ActionAdmission.actionAdmissionProcessExit(scope, null)
            ensure(
                !ActionAdmission.actionAdmissionFailed,
                "Pending null token disabled native observation: $bytes",
            )
            ensure(
                record.pendingLogged &&
                    record.stage == "terminal" &&
                    !record.accepted &&
                    !record.sourceValidated &&
                    !record.admittedBindingValid &&
                    record.reason == "admission-refused:token-unobserved" &&
                    record.token == null &&
                    record.bindingRefusal == null,
                "Missing native source/token acquired authority or changed refusal",
            )
            val rows =
                bytes
                    .toString(Charsets.UTF_8)
                    .lineSequence()
                    .filter {
                        it.startsWith("[CART_ADMISSION] ")
                    }
                    .toList()
            ensure(rows.size == 2, "Pending/refusal observations were not both emitted: $bytes")
            ensure(
                rows[0].startsWith("[CART_ADMISSION] {\"event\":\"pending\",") &&
                    rows[1].startsWith("[CART_ADMISSION] {\"event\":\"retired\",") &&
                    rows.all {
                        it.contains("\"token\":null,") &&
                            it.contains("\"tokenObserved\":false,") &&
                            it.contains("\"accepted\":false,") &&
                            it.contains("\"nativeState\":\"Request\",")
                    },
                "Native pending/refusal JSON lost nullable token or scalar types: $bytes",
            )
            // A later native state/token cannot revive an observation already refused.
            state.set(action, TransactionState.Accept)
            record.token = "later-token"
            ActionAdmission.actionAdmissionProcessExit(scope, null)
            ensure(
                !ActionAdmission.actionAdmissionFailed &&
                    record.stage == "terminal" &&
                    !record.accepted &&
                    !record.admittedBindingValid &&
                    bytes.toString(Charsets.UTF_8).lineSequence().count {
                        it.startsWith("[CART_ADMISSION] ")
                    } == 2,
                "Later native Accept/token revived a refused observation",
            )
            publishedTokenCheck()
        } finally {
            System.setOut(output)
            capture.close()
            GameServer.server = server
            GameClient.client = client
        }
        println(
            "ACTION_ADMISSION_CHECK_PASS nativeAction=true pendingNullToken=true refusalAbsorbing=true nativePublishedToken=true exactAction=true",
        )
    }
}
