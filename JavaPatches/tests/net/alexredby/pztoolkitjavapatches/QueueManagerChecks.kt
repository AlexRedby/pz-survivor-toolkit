package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentLinkedQueue
import sun.misc.Unsafe
import zombie.characters.IsoPlayer
import zombie.core.ActionManager
import zombie.core.NetTimedAction
import zombie.core.Transaction
import zombie.core.Transaction.TransactionState
import zombie.core.TransactionManager
import zombie.core.network.ByteBufferReader
import zombie.core.network.ByteBufferWriter
import zombie.core.raknet.UdpConnection
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.fields.character.ConnectionPlayer
import zombie.network.packets.ItemTransactionPacket

/** Exercise the original signed engine; no Toolkit patch is applied by this check. */
object QueueManagerChecks {
    private const val ID: Byte = -126
    private lateinit var unsafe: Unsafe
    private lateinit var transactions: ConcurrentLinkedQueue<Transaction>
    private lateinit var actions: ConcurrentLinkedQueue<Any>
    private val actionType = Class.forName("zombie.core.Action")

    class Connection : UdpConnection(null, 0, 0) {
        var replies = 0
        lateinit var bytes: ByteBuffer

        override fun startPacket(): ByteBufferWriter {
            bytes.clear()
            return ByteBufferWriter(bytes)
        }

        override fun endPacket(priority: Int, reliability: Int, channel: Byte) {
            replies++
        }
    }

    private fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }
    private fun field(type: Class<*>, name: String): Field =
        type.getDeclaredField(name).apply { isAccessible = true }
    private fun player(id: Short): IsoPlayer =
        (unsafe.allocateInstance(IsoPlayer::class.java) as IsoPlayer).apply { onlineId = id }
    private fun connection(vararg players: IsoPlayer): Connection =
        (unsafe.allocateInstance(Connection::class.java) as Connection).apply {
            this.players = arrayOf(*players)
            bytes = ByteBuffer.allocate(1024)
        }
    private fun owner(packet: Transaction): ConnectionPlayer =
        field(Transaction::class.java, "player").get(packet) as ConnectionPlayer
    @Suppress("UNCHECKED_CAST")
    private fun entries(packet: Transaction): MutableList<Any> =
        field(Transaction::class.java, "entries").get(packet) as MutableList<Any>
    private fun state(packet: Transaction): TransactionState =
        field(Transaction::class.java, "state").get(packet) as TransactionState
    private fun transaction(player: IsoPlayer?, id: Byte): ItemTransactionPacket =
        ItemTransactionPacket().apply {
            field(Transaction::class.java, "id").setByte(this, id)
            setState(TransactionState.Accept)
            owner(this).set(player)
            TransactionManager.add(this)
        }
    private fun action(player: IsoPlayer?, id: Byte, state: TransactionState): NetTimedAction =
        NetTimedAction().apply {
            field(actionType, "id").setByte(this, id)
            field(actionType, "state").set(this, state)
            (field(actionType, "player").get(this) as ConnectionPlayer).set(player)
            actions.add(this)
        }
    private fun actionState(action: NetTimedAction, state: TransactionState) {
        field(actionType, "state").set(action, state)
    }
    private fun reject(id: Byte, connection: Connection?): ItemTransactionPacket {
        val bytes = ByteBuffer.allocate(2)
        val writer = ByteBufferWriter(bytes)
        writer.putByte(id)
        writer.putEnum(TransactionState.Reject)
        bytes.flip()
        return ItemTransactionPacket().apply {
            parse(ByteBufferReader(bytes), connection)
            require(!bytes.hasRemaining() && owner(this).getPlayer() == null && entries(this).isEmpty(),
                "Reject must contain only the native byte id and state")
            require(isConsistent(connection), "native Reject consistency changed")
        }
    }

    private fun itemChecks(first: IsoPlayer, second: IsoPlayer, split: IsoPlayer) {
        val firstConnection = connection(first, split)
        val secondConnection = connection(second)
        // Equal online IDs do not grant another physical connection ownership.
        val attacker = connection(player(first.onlineId))
        val own = transaction(first, ID)
        val other = transaction(second, ID)
        val splitOwn = transaction(split, ID)
        val orphan = transaction(null, ID)
        val differentId = transaction(first, 127)
        val incoming = reject(ID, attacker)
        owner(incoming).set(first)
        incoming.processServer(null, attacker)
        require(transactions.size == 5, "spoofed owner or online ID canceled a foreign transaction")
        try {
            reject(ID, null).processServer(null, null)
            throw AssertionError("native missing-connection boundary changed")
        } catch (_: NullPointerException) {}
        require(transactions.size == 5, "missing connection canceled a transaction")
        reject(111, firstConnection).processServer(null, firstConnection)
        require(transactions.size == 5, "unknown byte id canceled a transaction")
        reject(ID, firstConnection).processServer(null, firstConnection)
        require(own !in transactions && splitOwn !in transactions, "owned/split-screen cancellation failed")
        require(other in transactions && orphan in transactions && differentId in transactions,
            "owned cancellation removed a foreign, ownerless or different-id transaction")
        reject(ID, firstConnection).processServer(null, firstConnection)
        require(transactions.size == 3, "duplicate Reject canceled an unrelated transaction")
        val invalid = reject(ID, firstConnection)
        val entryType = Transaction::class.java.declaredClasses.single { it.simpleName == "TransactionEntry" }
        entries(invalid).add(entryType.getDeclaredConstructor(Int::class.javaObjectType)
            .apply { isAccessible = true }.newInstance(null as Any?))
        try {
            invalid.processServer(null, firstConnection)
            throw AssertionError("native validation failure disappeared")
        } catch (_: NullPointerException) {}
        require(transactions.size == 3, "invalid packet reached removal")
        for (state in arrayOf(TransactionState.Accept, TransactionState.Done)) {
            val packet = ItemTransactionPacket()
            field(Transaction::class.java, "id").setByte(packet, ID)
            packet.setState(state)
            packet.processServer(null, firstConnection)
            require(state(packet) == state && transactions.size == 3, "non-Reject packet removed transactions")
        }
        val request = ItemTransactionPacket()
        field(Transaction::class.java, "id").setByte(request, ID)
        request.setState(TransactionState.Request)
        request.processServer(null, firstConnection)
        require(state(request) == TransactionState.Reject && firstConnection.replies == 1 && transactions.size == 3,
            "native invalid-Request rejection/reply changed")
        // The boolean overload is local-client cleanup. Server packets use the connection overload.
        TransactionManager.removeItemTransaction(ID, true)
        require(transactions.size == 3, "local cleanup removed server-owned transactions")
        reject(ID, secondConnection).processServer(null, secondConnection)
        require(other !in transactions && orphan in transactions && differentId in transactions,
            "second connection ownership changed")
        GameServer.server = false
        GameClient.client = true
        transaction(first, ID)
        transaction(second, ID)
        TransactionManager.removeItemTransaction(ID, false)
        require(transactions.size == 1 && differentId in transactions, "local client cleanup semantics changed")
        GameClient.client = false
        GameServer.server = true
        transactions.clear()
    }

    private fun actionChecks(first: IsoPlayer, second: IsoPlayer) {
        require(!ActionManager.isDone(first, ID), "empty queue reported completion")
        action(second, ID, TransactionState.Done)
        action(null, ID, TransactionState.Done)
        require(!ActionManager.isDone(first, ID), "foreign or ownerless action reported completion")
        require(!ActionManager.isDone(null, ID), "missing owner reported completion")
        val pending = action(first, ID, TransactionState.Accept)
        require(!ActionManager.isDone(first, ID), "pending action reported completion")
        actionState(pending, TransactionState.Done)
        require(ActionManager.isDone(first, ID), "completed action lost completion")
        val sameOnlineId = player(first.onlineId)
        require(ActionManager.isDone(sameOnlineId, ID), "native online-owner matching changed")
        require(ActionManager.getAction(ID, first) === pending && ActionManager.getAction(ID, sameOnlineId) === pending,
            "native owned action lookup changed")
        val duplicate = action(first, ID, TransactionState.Request)
        require(!ActionManager.isDone(first, ID), "mixed duplicate states lost native all-match semantics")
        actionState(duplicate, TransactionState.Done)
        require(ActionManager.isDone(first, ID), "all completed matching actions failed")
        actions.remove(pending)
        actions.remove(duplicate)
        require(!ActionManager.isDone(first, ID), "removed matching action reported completion")
        require(ActionManager.getAction(ID, first) == null, "foreign action escaped owned lookup")
        action(first, 127, TransactionState.Done)
        require(!ActionManager.isDone(first, ID), "different byte id reported completion")
        require(ActionManager.isDone(first, 127), "signed/positive byte id lookup changed")
        actions.clear()
    }

    @JvmStatic
    @Suppress("UNCHECKED_CAST")
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        unsafe = field(Unsafe::class.java, "theUnsafe").get(null) as Unsafe
        transactions = field(TransactionManager::class.java, "transactions").get(null) as ConcurrentLinkedQueue<Transaction>
        actions = field(ActionManager::class.java, "actions").get(null) as ConcurrentLinkedQueue<Any>
        transactions.clear()
        actions.clear()
        require(QueueManagerSupport.ITEM_SUPPORTED && QueueManagerSupport.ACTION_SUPPORTED, "unsupported native managers")
        GameServer.server = true
        GameClient.client = false
        val first = player(19)
        val second = player(20)
        itemChecks(first, second, player(21))
        actionChecks(first, second)
        println("QUEUE_MANAGER_CHECKS_PASS (original engine; native Reject wire/connection ownership, split screen, owner spoofing, byte ids, validation, non-Reject/local cleanup, nonempty all-match completion)")
    }
}
