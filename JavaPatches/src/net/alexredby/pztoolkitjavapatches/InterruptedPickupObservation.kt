package net.alexredby.pztoolkitjavapatches

import java.util.WeakHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.Patch
import se.krka.kahlua.integration.annotations.LuaMethod
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.vm.KahluaThread
import zombie.Lua.LuaManager
import zombie.characters.CharacterTimedActions.LuaTimedActionNew
import zombie.characters.IsoPlayer
import zombie.core.Transaction
import zombie.core.TransactionManager
import zombie.core.raknet.UdpConnection
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.network.GameClient
import zombie.network.fields.ContainerID
import zombie.network.fields.character.ConnectionPlayer
import zombie.network.packets.ItemTransactionPacket

/** Watches only explicitly enrolled singleton pickups; never changes native packets or state. */
object InterruptedPickupObservation {
    private const val LIFETIME_NS = 30_000_000_000L
    private const val MAX_WATCHES = 32
    @JvmField val SUPPORTED = NativeTransferRequestsLogic.SUPPORTED &&
        BytecodeSupport.supports("zombie/network/fields/ContainerID.class", "3123bde915f47f58fa81fb0f49fc1768efcb4db45749fe0d97c4c52dbc731bc0") &&
        BytecodeSupport.supports("zombie/characters/CharacterTimedActions/LuaTimedActionNew.class", "020a9e5c22b25bdffca7f396612d420e9cea6f78f7432015ac146f19728ac1a6")

    class Watch internal constructor(
        internal val actor: IsoPlayer, internal val action: KahluaTableImpl,
        internal val native: LuaTimedActionNew, internal val env: KahluaTableImpl,
        internal val thread: KahluaThread, internal val connection: UdpConnection,
        internal val transaction: Byte, internal val item: Int,
        internal val source: ContainerID, internal val destination: ContainerID,
        internal val deadline: Long,
    ) {
        internal var confirmed = false
        internal var released = false
    }
    private val lock = Any()
    // Values must not retain Watch/action: an action may itself hold its receipt.
    private val watches = WeakHashMap<InterruptedPickupReceipt, Boolean>()
    @Volatile private var watching = false

    private fun direct(value: Any?): KahluaTableImpl? =
        (value as? KahluaTableImpl)?.takeIf { it.javaClass == KahluaTableImpl::class.java &&
            it.rewriteTable == null && it.delegate.javaClass == java.util.LinkedHashMap::class.java }
    private fun plain(value: Any?): KahluaTableImpl? = direct(value)?.takeIf { it.metatable == null }
    private fun field(owner: Any, name: String): Any? = Accessor.tryGet<Any>(owner, name, null)
    private fun viable(watch: Watch, now: Long): Boolean = !watch.released && now < watch.deadline &&
        GameClient.client && GameClient.connection === watch.connection && LuaManager.env === watch.env &&
        NativeTransferRequestsLogic.uniqueWire(watch.connection, watch.transaction)
    private fun prune(now: Long) {
        watches.keys.removeIf { !viable(it.watch, now) }
        watching = watches.isNotEmpty()
    }
    private fun expose(env: KahluaTableImpl): Boolean {
        val exposer = LuaManager.exposer ?: return false
        val klass = InterruptedPickupReceipt::class.java
        val mapped = exposer.typeMap[klass.simpleName]
        if (mapped != null && mapped !== klass) return false
        if (!exposer.isExposed(klass)) { exposer.setExposed(klass); exposer.exposeLikeJava(klass, env) }
        exposer.typeMap[klass.simpleName] = klass
        return true
    }

    /** Call before native transfer.stop retires the still-registered transaction. */
    @JvmStatic @LuaMethod(name = "pzWatchInterruptedPickup", global = true)
    fun watch(value: Any?): InterruptedPickupReceipt? = try { watchNative(value) } catch (_: Throwable) { null }
    private fun watchNative(value: Any?): InterruptedPickupReceipt? {
        if (!SUPPORTED || !GameClient.client) return null
        val thread = LuaManager.thread ?: return null
        if (thread.debugOwnerThread !== Thread.currentThread()) return null
        val env = plain(LuaManager.env) ?: return null
        val connection = GameClient.connection ?: return null
        val action = direct(value) ?: return null
        if (action.metatable !== direct(env.delegate["ISInventoryTransferAction"])) return null
        val actor = action.delegate["character"] as? IsoPlayer ?: return null
        val native = action.delegate["action"] as? LuaTimedActionNew ?: return null
        val source = action.delegate["srcContainer"] as? ItemContainer ?: return null
        val destination = action.delegate["destContainer"] as? ItemContainer ?: return null
        val item = action.delegate["item"] as? InventoryItem ?: return null
        val id = (action.delegate["transactionId"] as? Double)?.takeIf { it.isFinite() && it % 1.0 == 0.0 && it >= -128 && it <= 127 && it != 0.0 }?.toInt()?.toByte() ?: return null
        if (native.table !== action || !actor.characterActions.contains(native) ||
            actor.inventory !== destination || source === destination || actor.isDead ||
            actor.playerNum !in IsoPlayer.players.indices || IsoPlayer.players[actor.playerNum] !== actor ||
            !NativeTransferRequestsLogic.uniqueWire(connection, id)) return null
        val groups = plain(action.delegate["queueList"]) ?: return null
        val group = plain(groups.delegate[1.0]) ?: return null
        val items = plain(group.delegate["items"]) ?: return null
        if (groups.delegate.size != 1 || items.delegate.size != 1 || items.delegate[1.0] !== item) return null
        val transactions = Accessor.tryGet<ConcurrentLinkedQueue<Transaction>>(TransactionManager::class.java, "transactions", null) ?: return null
        var found: Transaction? = null
        var visited = 0
        for (candidate in transactions) {
            if (++visited > 128) return null
            if (field(candidate, "id") == id) {
                if (found != null || candidate.javaClass != ItemTransactionPacket::class.java) return null
                found = candidate
            }
        }
        val transaction = found ?: return null
        val entries = field(transaction, "entries") as? List<*> ?: return null
        val entry = entries.singleOrNull()?.takeIf { it.javaClass.name == "zombie.core.Transaction\$TransactionEntry" } ?: return null
        val entryItem = field(entry, "itemId") as? Int ?: return null
        val entrySource = field(entry, "sourceId") as? ContainerID ?: return null
        val entryDestination = field(entry, "destinationId") as? ContainerID ?: return null
        val state = field(transaction, "state") as? Transaction.TransactionState ?: return null
        if ((field(transaction, "player") as? ConnectionPlayer)?.player !== actor || entryItem != item.id ||
            entrySource.container !== source || entryDestination.container !== destination ||
            state !in arrayOf(Transaction.TransactionState.Request, Transaction.TransactionState.Accept, Transaction.TransactionState.Done)) return null
        val now = System.nanoTime()
        synchronized(lock) {
            prune(now)
            // Re-entry cannot mint another observation for the same native episode.
            if (watches.keys.any { it.watch.action === action || it.watch.connection === connection && it.watch.transaction == id } ||
                watches.size >= MAX_WATCHES || !expose(env)) return null
            val routeSource = ContainerID().apply { copy(entrySource); floorXY = floorXY?.clone() }
            val routeDestination = ContainerID().apply { copy(entryDestination); floorXY = floorXY?.clone() }
            val watch = Watch(actor, action, native, env, thread, connection, id, item.id, routeSource, routeDestination, now + LIFETIME_NS)
            watch.confirmed = state == Transaction.TransactionState.Done
            val receipt = InterruptedPickupReceipt(watch)
            watches[receipt] = true
            watching = true
            return receipt
        }
    }

    @JvmStatic fun confirmed(receipt: InterruptedPickupReceipt): Boolean = synchronized(lock) {
        if (!watches.containsKey(receipt)) return false
        val watch = receipt.watch
        if (LuaManager.thread !== watch.thread || watch.thread.debugOwnerThread !== Thread.currentThread()) return false
        if (!viable(watch, System.nanoTime())) { watches.remove(receipt); watching = watches.isNotEmpty(); return false }
        watch.confirmed
    }
    @JvmStatic fun expired(receipt: InterruptedPickupReceipt): Boolean = synchronized(lock) {
        if (!watches.containsKey(receipt)) return true
        val watch = receipt.watch
        val expired = !viable(watch, System.nanoTime())
        if (expired) { watches.remove(receipt); watching = watches.isNotEmpty() }
        expired
    }
    @JvmStatic fun release(receipt: InterruptedPickupReceipt) = synchronized(lock) {
        watches.remove(receipt)
        receipt.watch.released = true
        watching = watches.isNotEmpty()
    }

    @JvmStatic fun received(packet: ItemTransactionPacket, connection: UdpConnection?) {
        if (!watching || !SUPPORTED || !GameClient.client || connection !== GameClient.connection) return
        val now = System.nanoTime()
        synchronized(lock) {
            prune(now)
            if (!watching || field(packet, "state") != Transaction.TransactionState.Done) return
            val entries = field(packet, "entries") as? List<*> ?: return
            val entry = entries.singleOrNull()?.takeIf { it.javaClass.name == "zombie.core.Transaction\$TransactionEntry" } ?: return
            val item = field(entry, "itemId") as? Int ?: return
            val source = field(entry, "sourceId") as? ContainerID ?: return
            val destination = field(entry, "destinationId") as? ContainerID ?: return
            val actor = (field(packet, "player") as? ConnectionPlayer)?.player ?: return
            val id = field(packet, "id") as? Byte ?: return
            for (receipt in watches.keys) {
                val watch = receipt.watch
                if (watch.connection === connection && watch.transaction == id && watch.actor === actor &&
                    watch.item == item && watch.source == source && watch.destination == destination) watch.confirmed = true
            }
        }
    }

    @Patch(className = "zombie.network.packets.ItemTransactionPacket", methodName = "processClient", warmUp = true, strictMatch = true)
    object ClientReply {
        @JvmStatic @Patch.OnEnter
        fun enter(@Patch.This packet: ItemTransactionPacket, @Patch.Argument(0) connection: UdpConnection?) {
            try { received(packet, connection) } catch (_: Throwable) { /* Native packet processing always continues. */ }
        }
    }
}
