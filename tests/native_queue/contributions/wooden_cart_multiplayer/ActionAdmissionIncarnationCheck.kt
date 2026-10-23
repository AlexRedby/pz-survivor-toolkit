package zombie.core

import java.lang.ref.WeakReference
import java.nio.ByteBuffer
import java.nio.file.Files
import java.nio.file.Path
import java.util.UUID
import me.zed_0xff.zombie_buddy.Accessor
import net.alexredby.cartlab.ActionAdmission
import net.alexredby.cartlab.ActionInvalidation
import net.alexredby.cartlab.LeaseControl
import net.alexredby.cartlab.NativeTime
import net.alexredby.pztoolkitjavapatches.ActionAcknowledgements
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.KahluaTable
import zombie.Lua.LuaManager
import zombie.characters.IsoPlayer
import zombie.core.ActionManager
import zombie.core.NetTimedAction
import zombie.core.Transaction.TransactionState
import zombie.core.network.ByteBufferReader
import zombie.core.network.ByteBufferWriter
import zombie.core.raknet.UdpConnection
import zombie.core.raknet.UdpEngine
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.PacketTypes
import zombie.network.TableNetworkUtils

/** Composed native model: real action lifecycle and receipts, explicitly supplied ingress scope. */
object ActionAdmissionIncarnationCheck {
    private const val TRANSACTION: Byte = -128
    private lateinit var unsafe: sun.misc.Unsafe
    private var ingressGeneration = 0L

    class Owner : IsoPlayer(null, null, 0, 0, 0) {
        lateinit var cart: InventoryItem
        lateinit var bag: ItemContainer

        override fun getOnlineID(): Short = onlineId
        override fun isDead(): Boolean = false
        override fun getInventory(): ItemContainer = bag
        override fun getPrimaryHandItem(): InventoryItem = cart
        override fun getSecondaryHandItem(): InventoryItem = cart
        override fun isCurrentState(state: zombie.ai.State?): Boolean = false
    }

    class Item : InventoryItem("SaucedWheelbarrow", "WheelbarrowWood", "WheelbarrowWood", "Item_WheelbarrowWood") {
        override fun getFullType(): String = "SaucedWheelbarrow.WheelbarrowWood"
    }

    class Connection : UdpConnection(null, 1L, 0) {
        lateinit var bytes: ByteBuffer
        lateinit var receipts: MutableList<KahluaTable>
        lateinit var order: MutableList<String>
        var guid = 1L

        override fun getConnectedGUID(): Long = guid
        override fun isFullyConnected(): Boolean = true

        override fun startPacket(): ByteBufferWriter {
            bytes.clear()
            return ByteBufferWriter(bytes)
        }

        override fun endPacket(priority: Int, reliability: Int, channel: Byte) {
            ensure(reliability == 3 && channel.toInt() == 1, "Native outcome/receipt lost ordered channel 1")
            bytes.flip()
            val reader = ByteBufferReader(bytes)
            reader.getByte()
            when (reader.getShort()) {
                PacketTypes.PacketType.ClientCommand.id -> {
                    ensure(
                        reader.getUTF() == "PZSurvivorToolkitActions" &&
                            reader.getUTF() == "State" && reader.getBoolean(),
                        "Unexpected receipt envelope",
                    )
                    val receipt = LuaManager.platform.newTable()
                    TableNetworkUtils.load(receipt, reader)
                    receipts.add(receipt)
                    order.add("receipt:${receipt.rawget("state")}")
                }
                PacketTypes.PacketType.NetTimedAction.id -> {
                    ensure(reader.getByte() == TRANSACTION, "Native packet changed signed transaction")
                    order.add("native:${reader.getEnum(TransactionState::class.java)}")
                }
                else -> throw AssertionError("Unexpected native packet")
            }
        }

        override fun cancelPacket() = throw AssertionError("Native receipt transport failed")
    }

    class Engine : UdpEngine(0, 0, 1, null, false) {
        lateinit var connection: Connection
        var foreign: Connection? = null
        override fun getActiveConnection(guid: Long): UdpConnection? = when (guid) {
            1L -> connection
            2L -> foreign
            else -> null
        }
    }

    private fun ensure(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun field(type: Class<*>, name: String) = type.getDeclaredField(name).apply { isAccessible = true }

    private fun lua(code: String): Any? =
        LuaManager.thread.call(
            LuaCompiler.loadstring(code, "admission-incarnation", LuaManager.env), null, null, null,
        )

    private fun identify(action: NetTimedAction, owner: Owner, packet: Boolean = false) {
        val type = Class.forName("zombie.core.Action")
        field(type, "id").setByte(action, TRANSACTION)
        field(type, "state").set(action, TransactionState.Request)
        val player = field(type, "playerId").get(action) as zombie.network.fields.character.PlayerID
        player.setID(owner.onlineId)
        player.setPlayerIndex(if (packet) 0 else -1)
        field(player.javaClass, "player").set(player, owner)
    }

    private data class Invocation(
        val action: NetTimedAction,
        val scope: ActionAdmission.ActionAdmissionScope,
        val record: ActionAdmission.ActionAdmissionRecord,
        val started: KahluaTable,
    )

    @Suppress("UNCHECKED_CAST")
    private fun start(
        owner: Owner,
        connection: Connection,
        transport: LeaseControl.LeaseTransport,
        succeeds: Boolean,
    ): Invocation {
        val action = NetTimedAction()
        identify(action, owner)
        action.type = "ToolkitWoodCartDrop"
        action.action = lua(
            """
            return {
                performed=0, stopped=0,
                getDuration=function(self) return 10000 end,
                adjustMaxTime=function(self,d) return d+0 end,
                serverStop=function(self) self.stopped=self.stopped+1 end,
                complete=function(self) self.performed=self.performed+1 return $succeeds end
            }
            """.trimIndent(),
        ) as KahluaTable
        action.action.rawset("character", owner)
        action.action.rawset("item", owner.cart)
        action.action.rawset("netAction", action)
        val packet = zombie.network.packets.NetTimedActionPacket()
        identify(packet, owner, true)
        packet.action = action.action
        // This is a model ingress, not a claim that bytes passed native parse/processServer.
        val generation = ++ingressGeneration
        val scope = ActionAdmission.ActionAdmissionScope(
            packet,
            ActionAdmission.ActionAdmissionParsed(
                LeaseControl.LeaseCommandIngress(generation, transport), generation,
            ),
            connection,
            null,
        )
        val scopes = field(ActionAdmission::class.java, "actionAdmissionScope").get(null)
            as ThreadLocal<ActionAdmission.ActionAdmissionScope>
        scopes.set(scope)
        try {
            ActionManager.start(action)
            ensure(scope.starts.size == 1, "Actual native start advice did not create one exact observation")
            val pending = scope.starts.single()
            ensure(
                pending.stage == "pending" && !pending.accepted &&
                    !pending.admittedBindingValid && pending.token != null &&
                    pending.sourceValidated && pending.nativeBindingValid,
                "Published token/binding granted authority before native Accept",
            )
            // Native processServer performs this transition after ActionManager.start returns.
            field(Class.forName("zombie.core.Action"), "state").set(action, TransactionState.Accept)
            ActionAdmission.actionAdmissionProcessExit(scope, null)
        } finally {
            scopes.remove()
        }
        val record = scope.starts.single()
        val receipt = connection.receipts.last()
        ensure(
            record.stage == "accepted" && record.accepted && record.sourceValidated &&
                record.admittedBindingValid && record.nativeBindingValid,
            "Exact model binding was not admitted",
        )
        ensure(
            record.transaction == TRANSACTION.toInt() &&
                receipt.rawget("transaction") == TRANSACTION.toDouble() &&
                receipt.rawget("state") == "started" && receipt.rawget("token") == record.token,
            "Admission did not join the exact signed-byte native receipt",
        )
        ensure(UUID.fromString(record.token).toString() == record.token, "Production token was not a UUID")
        return Invocation(action, scope, record, receipt)
    }

    private fun checkRetired(old: Invocation, next: Invocation, reason: String) {
        val count = next.scope.starts.size
        ActionAdmission.actionAdmissionProcessExit(old.scope, null)
        ActionAdmission.actionAdmissionSweep("fixture-delayed-old-outcome")
        ensure(
            old.record.stage == "terminal" && old.record.reason == reason &&
                old.record.token == old.started.rawget("token"),
            "Retired incarnation was renewed or rewritten",
        )
        ensure(
            !ActionAdmission.actionAdmissionCanAccept(
                old.record.stage, "Accept", true, true, true, old.record.token,
            ),
            "Terminal incarnation could regain authority with otherwise valid current facts",
        )
        ensure(
            next.record.stage == "accepted" && next.record.reason == "native-accepted" &&
                next.record.token == next.started.rawget("token") &&
                next.record.nativeBindingValid && next.scope.starts.size == count,
            "Old outcome changed the current admission",
        )
    }

    private fun scenario(
        owner: Owner,
        connection: Connection,
        transport: LeaseControl.LeaseTransport,
        cancel: Boolean,
    ) {
        val old = start(owner, connection, transport, false)
        LuaManager.env.rawset("fixtureNative", old.action)
        LuaManager.env.rawset("fixtureReceipt", old.started)
        lua(
            """
            fixtureBegin(fixtureNative)
            fixtureDeliver(fixtureReceipt)
            oldAction=fixtureAction
            oldReceipt=fixtureAck.capture(oldAction)
            assert(oldReceipt and fixtureAck.state(oldAction,oldReceipt)=='started')
            """.trimIndent(),
        )
        if (cancel) ActionManager.stop(old.action)
        else {
            field(Class.forName("zombie.core.Action"), "endTime").setLong(old.action, 0L)
            ActionManager.update()
        }
        val terminal = connection.receipts.last()
        val state = if (cancel) "canceled" else "rejected"
        val reason = if (cancel) "native-remove" else "rejected"
        ensure(
            terminal.rawget("state") == state && terminal.rawget("token") == old.started.rawget("token"),
            "Native terminal did not preserve the old token",
        )
        ensure(
            old.record.stage == "terminal" && old.record.reason == reason,
            "Native Reject/cancel did not retire the accepted observation",
        )
        ensure(
            old.action.action.rawget("performed") == (if (cancel) 0.0 else 1.0) &&
                old.action.action.rawget("stopped") == (if (cancel) 1.0 else 0.0),
            "Original complete/stop effects changed",
        )
        if (!cancel) ensure(
            connection.order.indexOfLast { it == "native:Reject" } <
                connection.order.indexOfLast { it == "receipt:rejected" } &&
                connection.order.contains("native:Reject"),
            "Rejected receipt preceded native Reject",
        )
        val next = start(owner, connection, transport, true)
        ensure(
            old.action !== next.action && old.action.action !== next.action.action &&
                old.record.actionEpoch != next.record.actionEpoch &&
                old.record.tableEpoch != next.record.tableEpoch &&
                old.record.startGeneration != next.record.startGeneration &&
                old.record.token != next.record.token,
            "Reused signed byte inherited the old incarnation",
        )
        LuaManager.env.rawset("fixtureNative", next.action)
        LuaManager.env.rawset("fixtureOldTerminal", terminal)
        LuaManager.env.rawset("fixtureOldStarted", old.started)
        LuaManager.env.rawset("fixtureNewStarted", next.started)
        // Deliver original production wire tables to unchanged production Lua receipt code.
        lua(
            """
            fixtureBegin(fixtureNative)
            assert(fixtureAck.capture(oldAction)==nil)
            fixtureDeliver(fixtureOldTerminal)
            fixtureDeliver(fixtureOldTerminal)
            fixtureDeliver(fixtureOldStarted)
            assert(fixtureAck.capture(fixtureAction)==nil)
            assert(fixtureAck.observe(oldAction,oldReceipt)=='$state')
            fixtureDeliver(fixtureNewStarted)
            newReceipt=fixtureAck.capture(fixtureAction)
            assert(newReceipt and newReceipt.token==fixtureNewStarted.token)
            assert(fixtureAck.state(fixtureAction,newReceipt)=='started')
            fixtureDeliver(fixtureOldTerminal)
            fixtureDeliver(fixtureOldStarted)
            fixtureDeliver(fixtureOldTerminal)
            assert(fixtureAck.capture(fixtureAction)==newReceipt)
            assert(fixtureAck.state(fixtureAction,newReceipt)=='started')
            assert(fixtureAck.capture(oldAction)==nil and fixtureAck.state(oldAction,oldReceipt)==nil)
            """.trimIndent(),
        )
        val count = connection.receipts.size
        repeat(2) {
            ActionAcknowledgements.settled(java.util.ArrayList(listOf(old.action)), cancel)
            checkRetired(old, next, reason)
        }
        ensure(connection.receipts.size == count, "Repeated old settlement emitted another receipt")
        ensure(
            next.action.action.rawget("performed") == 0.0 && next.action.action.rawget("stopped") == 0.0,
            "Delayed old settlement executed the new action",
        )
        ActionManager.stop(next.action)
        LuaManager.env.rawset("fixtureReceipt", connection.receipts.last())
        lua(
            """
            fixtureDeliver(fixtureReceipt)
            assert(fixtureAck.state(fixtureAction,newReceipt)=='canceled')
            fixtureAck.reset(fixtureQueue)
            fixtureDeliver(fixtureOldTerminal)
            assert(fixtureAck.capture(oldAction)==nil and fixtureAck.observe(oldAction,oldReceipt)==nil)
            assert(fixtureAck.capture(fixtureAction)==nil)
            """.trimIndent(),
        )
        ensure(
            !ActionAdmission.actionAdmissionFailed && !LeaseControl.leaseControlFailed,
            "Composed check poisoned native observers",
        )
    }

    private fun foreignStop(owner: Owner, connection: Connection, transport: LeaseControl.LeaseTransport) {
        val invocation = start(owner, connection, transport, true)
        val original = owner.cart
        owner.cart = (unsafe.allocateInstance(Item::class.java) as Item).also {
            it.setID(original.getID())
            it.setContainer(owner.bag)
        }
        ActionAdmission.actionAdmissionSweep("fixture-item-replaced")
        ensure(
            invocation.record.stage == "terminal" && invocation.record.reason == "item-invalid" &&
                invocation.record.accepted && !invocation.record.nativeBindingValid,
            "Foreign-stop regression requires an accepted, invalidated action still in native queue",
        )
        val foreign = (unsafe.allocateInstance(Owner::class.java) as Owner).also {
            it.onlineId = 8
            it.playerIndex = 0
        }
        val foreignConnection = (unsafe.allocateInstance(Connection::class.java) as Connection).also {
            it.guid = 2L
            it.players = arrayOf(foreign, null, null, null)
        }
        val engine = GameServer.udpEngine as Engine
        engine.foreign = foreignConnection
        GameServer.PlayerToAddressMap.put(foreign, 2L)
        GameServer.IDToPlayerMap.put(foreign.onlineId, foreign)
        val foreignTransport = LeaseControl.LeaseTransport(
            WeakReference(engine), WeakReference(foreignConnection),
            NativeTime.nativeTimeIdentity(foreignConnection, false), 2L,
            PacketTypes.PacketType.ClientCommand.id.toInt(),
        )
        val reader = ByteBufferReader(ByteBuffer.allocate(8))
        val ingress = LeaseControl.LeaseCommandIngress(++ingressGeneration, foreignTransport)
        val previous = LeaseControl.leaseControlCallback.get()
        LeaseControl.leaseControlIngresses.put(reader, ingress)
        LeaseControl.leaseControlCallback.set(
            LeaseControl.LeaseCallbackScope(reader, ingress, foreignConnection, 0, true, previous),
        )
        val actions = field(ActionManager::class.java, "actions").get(null) as Collection<*>
        val before = actions.toList()
        val receipts = connection.receipts.size
        try {
            ensure(
                LeaseControl.leaseControlValidatedServerScope() != null &&
                    LeaseControl.cartLeaseSource(foreign) === foreignConnection &&
                    LeaseControl.cartLeaseOwnerConnection(owner) === connection &&
                    LeaseControl.cartLeaseSource(owner) == null,
                "Foreign callback must be valid while its target-owner source is absent",
            )
            val row = checkNotNull(ActionAdmission.cartActionAdmission(owner))
            ensure(
                row.rawget("token") == invocation.record.token &&
                    row.rawget("actionEpoch") == invocation.record.actionEpoch.toDouble() &&
                    row.rawget("reason") == "item-invalid" &&
                    row.rawget("nativeState") == "Accept" && actions.any { it === invocation.action },
                "Foreign stop did not target the exact retained native incarnation",
            )
            val failure = runCatching {
                ActionInvalidation.stop(owner, invocation.record.token, invocation.record.actionEpoch.toDouble())
            }.exceptionOrNull()
            ensure(
                failure is IllegalStateException && failure.message == "Exact native owner source required",
                "Foreign callback was not refused at the exact owner-source guard: $failure",
            )
            ensure(
                actions.toList() == before && connection.receipts.size == receipts &&
                    invocation.action.action.rawget("performed") == 0.0 &&
                    invocation.action.action.rawget("stopped") == 0.0 &&
                    invocation.record.reason == "item-invalid",
                "Foreign stop changed native queue, effects, receipt or absorbing retirement",
            )
        } finally {
            if (previous == null) LeaseControl.leaseControlCallback.remove()
            else LeaseControl.leaseControlCallback.set(previous)
            LeaseControl.leaseControlIngresses.remove(reader)
            owner.cart = original
            ActionManager.stop(invocation.action)
            GameServer.PlayerToAddressMap.remove(foreign)
            GameServer.IDToPlayerMap.remove(foreign.onlineId)
            engine.foreign = null
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        ensure(args.size == 1, "Supply the repository root for unchanged production Lua source")
        ensure(
            ActionAdmission.ACTION_ADMISSION && LeaseControl.LEASE_CONTROL,
            "Admission observation flags are required",
        )
        unsafe = field(sun.misc.Unsafe::class.java, "theUnsafe").get(null) as sun.misc.Unsafe
        zombie.GameTime.setInstance(zombie.GameTime())
        LuaManager.platform = se.krka.kahlua.j2se.J2SEPlatform()
        LuaManager.env = LuaManager.platform.newEnvironment()
        LuaManager.thread = se.krka.kahlua.vm.KahluaThread(LuaManager.platform, LuaManager.env)
        LuaManager.thread.debugOwnerThread = Thread.currentThread()
        LuaManager.caller = se.krka.kahlua.integration.LuaCaller(se.krka.kahlua.converter.KahluaConverterManager())
        zombie.iso.IsoWorld.instance.currentCell =
            unsafe.allocateInstance(zombie.iso.IsoCell::class.java) as zombie.iso.IsoCell
        ensure(
            Accessor.trySet(
                zombie.network.ServerMap.instance, "grid",
                unsafe.allocateInstance(zombie.iso.IsoMetaGrid::class.java),
            ),
            "Fixture native server grid",
        )
        GameServer.server = true
        GameClient.client = false
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches", ActionAdmissionIncarnationCheck::class.java.classLoader,
        )
        ensure(ActionAcknowledgements.SUPPORTED, "Production native acknowledgement target is unsupported")
        val owner = (unsafe.allocateInstance(Owner::class.java) as Owner).also {
            it.onlineId = 7
            it.playerIndex = 0
            it.bag = ItemContainer()
            it.cart = (unsafe.allocateInstance(Item::class.java) as Item).also { cart ->
                cart.setID(42)
                cart.setContainer(it.bag)
            }
            ensure(Accessor.trySet(it, "ecsComponentMap", HashMap<Any, Any>()), "Fixture owner components")
        }
        val connection = (unsafe.allocateInstance(Connection::class.java) as Connection).also {
            it.guid = 1L
            it.bytes = ByteBuffer.allocate(8192)
            it.receipts = mutableListOf()
            it.order = mutableListOf()
            it.players = arrayOf(owner, null, null, null)
            ensure(Accessor.trySet(it, "limits", HashMap<Any, Any>()), "Fixture packet limits")
        }
        val engine = (unsafe.allocateInstance(Engine::class.java) as Engine).also { it.connection = connection }
        GameServer.udpEngine = engine
        GameServer.PlayerToAddressMap.put(owner, 1L)
        GameServer.IDToPlayerMap.put(owner.onlineId, owner)
        val transport = LeaseControl.LeaseTransport(
            WeakReference(engine), WeakReference(connection),
            NativeTime.nativeTimeIdentity(connection, false), 1L,
            PacketTypes.PacketType.NetTimedAction.id.toInt(),
        )
        lua(
            """
            require=function() end
            PZSurvivorToolkit={}
            ISTimedActionQueue={queues={}}
            Events={OnServerCommand={Add=function(f) fixtureReceive=f end}}
            isClient=function() return true end
            fixtureCharacter={
                getPlayerNum=function() return 0 end,
                getOnlineID=function() return 7 end,
                isDead=function() return false end
            }
            getSpecificPlayer=function(slot) if slot==0 then return fixtureCharacter end end
            """.trimIndent(),
        )
        val source = Files.readString(
            Path.of(args[0]).resolve(
                "PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueAcknowledgements.lua",
            ),
        )
        LuaManager.env.rawset("fixtureAck", lua(source))
        lua(
            """
            fixtureQueue={queue={},toolkitOperationGeneration=1}
            ISTimedActionQueue.queues[fixtureCharacter]=fixtureQueue
            fixtureBegin=function(native)
                fixtureAction={character=fixtureCharacter,action=native,
                    toolkitNativeTransaction=-128,toolkitNativeKind='ToolkitWoodCartDrop'}
                fixtureQueue.current=fixtureAction
                fixtureQueue.queue={fixtureAction}
            end
            fixtureDeliver=function(receipt) fixtureReceive('PZSurvivorToolkitActions','State',receipt) end
            """.trimIndent(),
        )
        scenario(owner, connection, transport, false)
        scenario(owner, connection, transport, true)
        foreignStop(owner, connection, transport)
        println(
            "ACTION_ADMISSION_INCARNATION_CHECK_PASS composedModel=true nativeReject=true " +
                "nativeCancel=true signedByteReuse=true exactFreshToken=true " +
                "delayedOriginalReceipt=true historicalOnly=true retirementAbsorbing=true " +
                "foreignStopRefused=true noHostClaim=true",
        )
    }
}
