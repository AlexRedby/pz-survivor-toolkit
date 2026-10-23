package zombie.core

import java.lang.reflect.Field
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentLinkedQueue
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.QueueManagers
import sun.misc.Unsafe
import zombie.characters.IsoPlayer
import zombie.core.network.ByteBufferReader
import zombie.core.network.ByteBufferWriter
import zombie.core.raknet.UdpConnection
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.fields.character.PlayerID
import zombie.network.packets.ItemTransactionPacket

object QueueManagerChecks {
    private const val ID: Byte = -126
    private lateinit var unsafe: Unsafe
    private lateinit var transactions: ConcurrentLinkedQueue<Transaction>
    private lateinit var actions: ConcurrentLinkedQueue<Action>

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

    private class Probe : Action() {
        override fun getDescription() = "queue-manager-check"

        override fun getDuration() = 1f

        override fun start() {}

        override fun stop() {}

        override fun isValid() = true

        override fun update() {}

        override fun perform() = true

        override fun isUsingTimeout() = false
    }

    private fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun field(type: Class<*>, name: String): Field =
        type.getDeclaredField(name).apply { isAccessible = true }

    private fun player(id: Short): IsoPlayer =
        (unsafe.allocateInstance(IsoPlayer::class.java) as IsoPlayer).apply {
            onlineId = id
        }

    private fun connection(vararg players: IsoPlayer): Connection =
        (unsafe.allocateInstance(Connection::class.java) as Connection).apply {
            this.players = arrayOf(*players)
            bytes = ByteBuffer.allocate(1024)
        }

    private fun owner(target: PlayerID, player: IsoPlayer) {
        target.setID(player.onlineId)
        require(Accessor.trySet(target, "player", player), "fixture owner")
    }

    private fun transaction(player: IsoPlayer?, id: Byte): ItemTransactionPacket =
        ItemTransactionPacket().apply {
            this.id = id
            state = Transaction.TransactionState.Accept
            if (player != null) owner(playerId, player)
            TransactionManager.add(this)
        }

    private fun action(player: IsoPlayer, id: Byte, state: Transaction.TransactionState): Probe =
        Probe().apply {
            this.id = id
            this.state = state
            owner(playerId, player)
            ActionManager.add(this)
        }

    private fun reject(id: Byte, connection: Connection?): ItemTransactionPacket {
        val bytes = ByteBuffer.allocate(2)
        val writer = ByteBufferWriter(bytes)
        writer.putByte(id)
        writer.putEnum(Transaction.TransactionState.Reject)
        bytes.flip()
        return ItemTransactionPacket().apply {
            parse(ByteBufferReader(bytes), connection)
            require(
                !bytes.hasRemaining() && playerId.getPlayer() == null && entries.isEmpty(),
                "Reject must contain only the native byte id and state",
            )
            require(isConsistent(connection), "native Reject consistency changed")
        }
    }

    private fun cleanScope() {
        require(
            (field(QueueManagers::class.java, "rejectScope").get(null) as ThreadLocal<*>).get() ==
                null,
            "incoming Reject ownership leaked outside packet processing",
        )
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        unsafe = field(Unsafe::class.java, "theUnsafe").get(null) as Unsafe
        transactions =
            Accessor.tryGet<ConcurrentLinkedQueue<Transaction>>(
                TransactionManager::class.java,
                "transactions",
                null,
            ) ?: throw AssertionError("native queues inaccessible")
        actions =
            Accessor.tryGet<ConcurrentLinkedQueue<Action>>(
                ActionManager::class.java,
                "actions",
                null,
            ) ?: throw AssertionError("native queues inaccessible")
        GameServer.server = true
        GameClient.client = false
        val first = player(19)
        val second = player(20)
        val split = player(21)
        val firstConnection = connection(first, split)
        val secondConnection = connection(second)
        val attacker = connection(player(22))
        transaction(first, ID)
        transaction(second, ID)
        reject(ID, firstConnection).processServer(null, firstConnection)
        require(
            transactions.isEmpty(),
            "original engine no longer reproduces cross-owner cancellation",
        )
        val unrelated = action(second, ID, Transaction.TransactionState.Accept)
        val query = PlayerID()
        owner(query, first)
        require(
            ActionManager.isDone(query, ID),
            "original engine no longer reproduces missing-action completion",
        )
        actions.clear()
        require(
            !ActionManager.isDone(query, ID),
            "original empty-queue completion semantics changed",
        )

        PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            QueueManagerChecks::class.java.classLoader,
        )
        require(
            QueueManagers.ITEM_SUPPORTED && QueueManagers.ACTION_SUPPORTED,
            "unsupported native managers",
        )
        val own = transaction(first, ID)
        val other = transaction(second, ID)
        val splitOwn = transaction(split, ID)
        val orphan = transaction(null, ID)
        val differentId = transaction(first, 127)
        val incoming = reject(ID, attacker)
        // A populated/reused packet field cannot claim another connection's player.
        owner(incoming.playerId, first)
        incoming.processServer(null, attacker)
        require(transactions.size == 5, "unowned Reject canceled a transaction")
        reject(ID, null).processServer(null, null)
        require(transactions.size == 5, "missing connection canceled a transaction")
        reject(111, firstConnection).processServer(null, firstConnection)
        require(transactions.size == 5, "unknown id canceled a transaction")
        reject(ID, firstConnection).processServer(null, firstConnection)
        require(
            own !in transactions && splitOwn !in transactions,
            "owned/split-screen cancellation failed",
        )
        require(
            other in transactions && orphan in transactions && differentId in transactions,
            "owned cancellation removed a foreign, ownerless, or different-id transaction",
        )
        reject(ID, firstConnection).processServer(null, firstConnection)
        require(transactions.size == 3, "duplicate Reject canceled an unrelated transaction")
        cleanScope()
        val invalid = reject(ID, firstConnection)
        invalid.entries.add(Transaction.TransactionEntry(null))
        try {
            invalid.processServer(null, firstConnection)
            throw AssertionError("native validation failure disappeared")
        } catch (_: NullPointerException) {}
        require(transactions.size == 3, "invalid packet reached removal")
        cleanScope()
        for (state in
            arrayOf(Transaction.TransactionState.Accept, Transaction.TransactionState.Done)) {
            val packet = ItemTransactionPacket()
            packet.id = ID
            packet.state = state
            packet.processServer(null, firstConnection)
            require(
                packet.state == state && transactions.size == 3,
                "non-Reject packet behavior changed",
            )
            cleanScope()
        }
        val request = ItemTransactionPacket()
        request.id = ID
        request.state = Transaction.TransactionState.Request
        request.processServer(null, firstConnection)
        require(
            request.state == Transaction.TransactionState.Reject &&
                firstConnection.replies == 1 &&
                transactions.size == 3,
            "native invalid-Request rejection/reply changed",
        )
        cleanScope()
        TransactionManager.removeItemTransaction(ID, true)
        require(
            transactions.size == 1 && differentId in transactions,
            "direct server manager semantics changed or scope leaked",
        )
        GameServer.server = false
        GameClient.client = true
        transaction(first, ID)
        transaction(second, ID)
        TransactionManager.removeItemTransaction(ID, false)
        require(transactions.size == 1, "local client cleanup semantics changed")
        GameClient.client = false
        require(!ActionManager.isDone(query, ID), "empty queue reported completion")
        actions.add(unrelated)
        require(!ActionManager.isDone(query, ID), "other player's action reported completion")
        val pending = action(first, ID, Transaction.TransactionState.Accept)
        require(!ActionManager.isDone(query, ID), "pending action reported completion")
        pending.state = Transaction.TransactionState.Done
        require(ActionManager.isDone(query, ID), "completed action lost completion")
        val duplicate = action(first, ID, Transaction.TransactionState.Request)
        require(
            !ActionManager.isDone(query, ID),
            "mixed duplicate states lost native all-match semantics",
        )
        duplicate.state = Transaction.TransactionState.Done
        require(ActionManager.isDone(query, ID), "all completed matching actions failed")
        actions.remove(pending)
        actions.remove(duplicate)
        require(!ActionManager.isDone(query, ID), "removed matching action reported completion")
        action(first, 127, Transaction.TransactionState.Done)
        require(!ActionManager.isDone(query, ID), "different byte id reported completion")
        require(ActionManager.isDone(query, 127), "signed/positive id lookup changed")
        actions.clear()
        transactions.clear()
        println(
            "QUEUE_MANAGER_CHECKS_PASS (original failures, native Reject wire, connection ownership, split screen, validation, scope cleanup, non-Reject/client behavior, missing-action completion)",
        )
    }
}
