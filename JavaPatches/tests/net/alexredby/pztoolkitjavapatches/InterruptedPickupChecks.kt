package net.alexredby.pztoolkitjavapatches

import java.nio.ByteBuffer
import java.util.Stack
import java.util.concurrent.ConcurrentLinkedQueue
import me.zed_0xff.zombie_buddy.Exposer
import me.zed_0xff.zombie_buddy.PatchEngine
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.vm.KahluaThread
import sun.misc.Unsafe
import zombie.Lua.LuaManager
import zombie.characters.CharacterTimedActions.BaseAction
import zombie.characters.CharacterTimedActions.LuaTimedActionNew
import zombie.characters.IsoPlayer
import zombie.core.Transaction
import zombie.core.TransactionManager
import zombie.core.network.ByteBufferWriter
import zombie.core.raknet.UdpConnection
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.PacketTypes
import zombie.network.fields.ContainerID
import zombie.network.fields.character.ConnectionPlayer
import zombie.network.packets.ItemTransactionPacket

/** Real native singleton registration, removal and incoming processClient advice. No game window. */
object InterruptedPickupChecks {
    private val unsafe = Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null) as Unsafe
    private fun field(type: Class<*>, name: String) = type.getDeclaredField(name).apply { isAccessible = true }
    private fun table() = LuaManager.platform.newTable() as KahluaTableImpl
    class Player : IsoPlayer(null) {
        lateinit var root: ItemContainer
        lateinit var actions: Stack<BaseAction>
        override fun getInventory() = root
        override fun getCharacterActions() = actions
        override fun isDead() = false
    }
    class Connection : UdpConnection(null, 0, 0) {
        lateinit var bytes: ByteBuffer
        override fun startPacket() = ByteBufferWriter(bytes.apply { clear() })
        override fun isLimitExceeded(type: PacketTypes.PacketType) = false
        override fun endPacket(priority: Int, reliability: Int, channel: Byte) {}
    }
    @Suppress("UNCHECKED_CAST")
    @JvmStatic fun main(args: Array<String>) {
        zombie.ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"))
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = LuaManager.platform.newEnvironment()
        LuaManager.exposer = LuaManager.Exposer(KahluaConverterManager(), LuaManager.platform, LuaManager.env)
        LuaManager.thread = KahluaThread(LuaManager.platform, LuaManager.env).apply { debugOwnerThread = Thread.currentThread() }
        GameClient.client = true
        GameClient.connection = null
        GameServer.server = false
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", javaClass.classLoader)
        Exposer.afterExposeAll()
        check(InterruptedPickupObservation.SUPPORTED)
        check(LuaManager.env.rawget("pzWatchInterruptedPickup") != null) { "Lua API was not exposed" }
        val transactions = field(TransactionManager::class.java, "transactions").get(null) as ConcurrentLinkedQueue<Transaction>
        fun player(id: Short, index: Int) = (unsafe.allocateInstance(Player::class.java) as Player).apply {
            onlineId = id; actions = Stack(); root = ItemContainer("inventory", null, this)
            field(IsoPlayer::class.java, "playerIndex").setInt(this, index)
            IsoPlayer.players[index] = this
        }
        val actor = player(81, 0)
        val other = player(82, 1)
        IsoPlayer.numPlayers = 2
        val source = other.root
        val destination = actor.root
        val item = (unsafe.allocateInstance(InventoryItem::class.java) as InventoryItem).apply { setID(517); setContainer(source) }
        val transferClass = table()
        LuaManager.env.rawset("ISInventoryTransferAction", transferClass)
        fun connection() = (unsafe.allocateInstance(Connection::class.java) as Connection).apply {
            bytes = ByteBuffer.allocate(4096); GameClient.connection = this; transactions.clear(); actor.actions.clear()
        }
        fun packet(id: Int, state: Transaction.TransactionState = Transaction.TransactionState.Accept): ItemTransactionPacket {
            field(Transaction::class.java, "lastId").setByte(null, id.toByte())
            return ItemTransactionPacket().apply {
                set(actor, listOf(item), source, destination, null, zombie.iso.IsoDirections.N, 0f, 0f, 0f)
                setState(state)
            }
        }
        fun action(packet: ItemTransactionPacket): KahluaTableImpl {
            val value = table().apply { metatable = transferClass }
            val native = unsafe.allocateInstance(LuaTimedActionNew::class.java) as LuaTimedActionNew
            field(LuaTimedActionNew::class.java, "table").set(native, value)
            native.chr = actor; actor.actions.add(native)
            val items = table().apply { rawset(1.0, item) }
            val group = table().apply { rawset("items", items) }
            val groups = table().apply { rawset(1.0, group) }
            for ((key, entry) in mapOf("character" to actor, "action" to native, "srcContainer" to source,
                "destContainer" to destination, "item" to item, "transactionId" to field(Transaction::class.java, "id").getByte(packet).toDouble(),
                "queueList" to groups)) value.rawset(key, entry)
            TransactionManager.add(packet)
            return value
        }
        fun reply(id: Int, owner: IsoPlayer = actor, routeSource: ItemContainer = source,
                  routeDestination: ItemContainer = destination, itemId: Int = item.id): ItemTransactionPacket {
            // Populate a received object without allocating another outgoing byte.
            val value = ItemTransactionPacket()
            field(Transaction::class.java, "id").setByte(value, id.toByte())
            value.setState(Transaction.TransactionState.Done)
            (field(Transaction::class.java, "player").get(value) as ConnectionPlayer).set(owner)
            val entryClass = Class.forName("zombie.core.Transaction\$TransactionEntry")
            val entry = entryClass.getDeclaredConstructor(Integer::class.java).apply { isAccessible = true }.newInstance(itemId)
            (field(entryClass, "sourceId").get(entry) as ContainerID).set(routeSource)
            (field(entryClass, "destinationId").get(entry) as ContainerID).set(routeDestination)
            (field(Transaction::class.java, "entries").get(value) as MutableList<Any>).add(entry)
            return value
        }
        var wire = connection()
        var native = packet(71)
        var current = action(native)
        val called = LuaManager.thread.pcall(LuaManager.env.rawget("pzWatchInterruptedPickup"), arrayOf<Any?>(current))
        check(called.firstOrNull() == true) { "Lua watcher invocation failed" }
        val receipt = called.getOrNull(1) as? InterruptedPickupReceipt ?: error("exact registered pickup was declined")
        check(!receipt.isConfirmed() && !receipt.isExpired())
        check(InterruptedPickupObservation.watch(current) == null) { "duplicate watch minted another episode" }
        TransactionManager.removeItemTransaction(71, true)
        actor.actions.clear()
        check(transactions.isEmpty() && TransactionManager.isDone(71) && TransactionManager.isRejected(71))
        check(!receipt.isConfirmed()) { "absent transaction fabricated confirmation" }
        reply(71, other).processClient(wire)
        reply(71, routeSource = destination, routeDestination = source).processClient(wire)
        reply(71, itemId = item.id + 1).processClient(wire)
        val reject = reply(71).apply { setState(Transaction.TransactionState.Reject) }
        reject.processClient(wire)
        check(!receipt.isConfirmed()) { "foreign/route/item/reject response confirmed the pickup" }
        reply(71).processClient(wire)
        check(receipt.isConfirmed() && transactions.isEmpty()) { "late exact Done was lost or replayed native registration" }
        receipt.release()
        check(receipt.isExpired() && !receipt.isConfirmed())

        wire = connection(); native = packet(72, Transaction.TransactionState.Done); current = action(native)
        val completed = InterruptedPickupObservation.watch(current) ?: error("already Done declined")
        check(completed.isConfirmed()); completed.release()

        wire = connection(); native = packet(73); current = action(native)
        val reused = InterruptedPickupObservation.watch(current) ?: error("reuse fixture declined")
        TransactionManager.removeItemTransaction(73, false)
        packet(73)
        reply(73).processClient(wire)
        check(!reused.isConfirmed() && reused.isExpired()) { "reused byte accepted old Done" }

        connection(); native = packet(74); current = action(native)
        val disconnected = InterruptedPickupObservation.watch(current) ?: error("disconnect fixture declined")
        wire = connection(); reply(74).processClient(wire)
        check(!disconnected.isConfirmed() && disconnected.isExpired())

        connection(); native = packet(75); current = action(native)
        transactions.clear()
        check(InterruptedPickupObservation.watch(current) == null) { "unregistered action acquired authority" }

        connection(); native = packet(76); current = action(native)
        val expired = InterruptedPickupObservation.watch(current) ?: error("expiry fixture declined")
        field(InterruptedPickupObservation.Watch::class.java, "deadline").setLong(expired.watch, 0)
        reply(76).processClient(GameClient.connection)
        check(expired.isExpired() && !expired.isConfirmed()) { "expired watch consumed late Done" }

        connection(); native = packet(77, Transaction.TransactionState.Reject); current = action(native)
        check(InterruptedPickupObservation.watch(current) == null) { "already rejected pickup acquired a watch" }
        connection(); native = packet(78); current = action(native)
        TransactionManager.add(native)
        check(InterruptedPickupObservation.watch(current) == null) { "duplicate registration acquired authority" }

        connection(); native = packet(79); current = action(native)
        val groups = current.rawget("queueList") as KahluaTableImpl
        groups.rawset(2.0, groups.rawget(1.0))
        check(InterruptedPickupObservation.watch(current) == null) { "multi-group transfer acquired singleton authority" }

        wire = connection()
        val direct = ItemTransactionPacket()
        field(Transaction::class.java, "id").setByte(direct, 80)
        TransactionManager.add(direct)
        check(NativeTransferRequestsLogic.uniqueWire(wire, 80))
        TransactionManager.add(direct)
        check(!NativeTransferRequestsLogic.uniqueWire(wire, 80)) { "direct add fabricated a set/add pairing" }
        wire = connection()
        val mutated = packet(81)
        packet(82)
        field(Transaction::class.java, "id").setByte(mutated, 82)
        TransactionManager.add(mutated)
        check(!NativeTransferRequestsLogic.uniqueWire(wire, 82)) { "mutated byte borrowed another allocation's pairing" }
        println("INTERRUPTED_PICKUP_CHECKS_PASS late_Done=true exact_route=true retirement_unchanged=true byte_reuse_denied=true")
    }
}
