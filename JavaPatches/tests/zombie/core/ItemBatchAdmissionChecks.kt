package zombie.core

import java.lang.reflect.Field
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentLinkedQueue
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.Loader
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.ItemBatchAdmission
import net.bytebuddy.jar.asm.ClassReader
import net.bytebuddy.jar.asm.ClassVisitor
import net.bytebuddy.jar.asm.ClassWriter
import net.bytebuddy.jar.asm.MethodVisitor
import net.bytebuddy.jar.asm.Opcodes
import sun.misc.Unsafe
import zombie.characters.IsoPlayer
import zombie.core.network.ByteBufferReader
import zombie.core.network.ByteBufferWriter
import zombie.core.raknet.UdpConnection
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.inventory.types.InventoryContainer
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.PacketTypes
import zombie.network.ServerOptions
import zombie.network.fields.ContainerID
import zombie.network.fields.character.PlayerID
import zombie.network.packets.ItemTransactionPacket
import zombie.scripting.objects.CharacterTrait

/** Exercises native packet validation and native capacity checks, with no copied capacity algorithm. */
object ItemBatchAdmissionChecks {
    private lateinit var unsafe: Unsafe
    private lateinit var transactions: ConcurrentLinkedQueue<Transaction>
    private lateinit var player: Player
    private lateinit var connection: Connection
    private var nextItem = 1000
    private var nextPacket: Byte = 10

    class Player : IsoPlayer(null) {
        override fun hasTrait(trait: CharacterTrait?) = false
        override fun isWearingAwkwardGloves() = false
    }

    class Item : InventoryItem("Base", "BatchProbe", "BatchProbe", "") {
        var probeWeight = 0f
        var onWeight: (() -> Unit)? = null
        override fun getUnequippedWeight(): Float {
            val callback = onWeight
            onWeight = null
            callback?.invoke()
            return probeWeight
        }
        override fun getWeight() = probeWeight
        override fun getActualWeight() = probeWeight
        override fun getType() = "BatchProbe"
        override fun getCategory() = "BatchProbe"
    }

    class Connection : UdpConnection(null, 0, 0) {
        lateinit var bytes: ByteBuffer
        var replies = 0
        var replied: Transaction.TransactionState? = null
        var expected: ItemTransactionPacket? = null
        override fun startPacket(): ByteBufferWriter {
            bytes.clear()
            return ByteBufferWriter(bytes)
        }
        override fun endPacket(priority: Int, reliability: Int, channel: Byte) {
            bytes.flip()
            val reader = ByteBufferReader(bytes)
            require(reader.getByte() == 134.toByte() && reader.getShort() == PacketTypes.PacketType.ItemTransaction.getId(),
                "wrong reply framing")
            val id = reader.getByte()
            replied = reader.getEnum(Transaction.TransactionState::class.java)
            val packet = expected ?: throw AssertionError("missing reply packet")
            require(id == packet.id, "reply transaction id changed")
            if (replied == Transaction.TransactionState.Reject) require(!bytes.hasRemaining(), "Reject gained partial-entry payload")
            val written = ByteBuffer.allocate(1024)
            packet.write(ByteBufferWriter(written))
            written.flip()
            bytes.position(3)
            require(bytes == written, "reply changed native packet serialization")
            replies++
        }
    }

    private fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun field(type: Class<*>, name: String): Field =
        type.getDeclaredField(name).apply { isAccessible = true }

    private fun item(source: ItemContainer, weight: Float): Item =
        (unsafe.allocateInstance(Item::class.java) as Item).apply {
            probeWeight = weight
            setID(nextItem++)
            setContainer(source)
            source.items.add(this)
        }

    private fun container(capacity: Int): ItemContainer = ItemContainer().apply {
        type = "crate"
        this.capacity = capacity
    }

    private fun entry(item: Item, destination: ItemContainer): Transaction.TransactionEntry =
        Transaction.TransactionEntry(item.getID()).apply {
            sourceId.containerType = ContainerID.ContainerType.ObjectContainer
            destinationId.containerType = ContainerID.ContainerType.ObjectContainer
            field(ContainerID::class.java, "container").set(sourceId, item.getContainer())
            field(ContainerID::class.java, "container").set(destinationId, destination)
        }

    private fun packet(vararg entries: Transaction.TransactionEntry): ItemTransactionPacket = ItemTransactionPacket().apply {
        id = nextPacket++
        state = Transaction.TransactionState.Request
        setDuration(1000)
        this.entries.addAll(entries.toList())
        playerId.setID(player.onlineId)
        field(PlayerID::class.java, "player").set(playerId, player)
    }

    private fun process(packet: ItemTransactionPacket, expected: Transaction.TransactionState, queued: Int) {
        val replies = connection.replies
        val previous = connection.expected
        connection.expected = packet
        val entries = ArrayList(packet.entries)
        try {
            packet.processServer(PacketTypes.PacketType.ItemTransaction, connection)
        } finally {
            connection.expected = previous
        }
        require(packet.entries == entries, "admission changed request membership")
        require(packet.state == expected && connection.replied == expected && connection.replies == replies + 1,
            "request did not receive exactly one native $expected reply")
        require(transactions.size == queued && (packet in transactions) == (expected == Transaction.TransactionState.Accept),
            "request admission changed native queue unexpectedly")
    }

    private fun unchanged(source: ItemContainer, destination: ItemContainer, vararg items: Item) {
        require(source.items == items.toList() && destination.items.isEmpty(), "admission mutated world inventories")
        for (item in items) require(item.getContainer() === source, "admission moved an item")
    }

    private fun overflow(patched: Boolean) {
        transactions.clear()
        val source = container(100)
        val destination = container(5)
        val a = item(source, 3f)
        val b = item(source, 3f)
        require(TransactionManager.isConsistent(a.getID(), null, source, destination, null, null, player) == 0.toByte() &&
            TransactionManager.isConsistent(b.getID(), null, source, destination, null, null, player) == 0.toByte(),
            "overflow fixture does not fit one item at a time")
        if (patched) {
            a.onWeight = {
                require(Accessor.tryGet<ThreadLocal<*>>(ItemBatchAdmission::class.java, "requests", null).get() != null,
                    "Request scope absent")
            }
            b.onWeight = { require(ItemBatchAdmission.reservations(transactions).hasNext(), "second item prefix absent") }
        }
        val request = packet(entry(a, destination), entry(b, destination))
        if (patched) {
            val scope = ItemBatchAdmission.beginRequest(request)
            require(scope != null, "eligible request refused scope")
            ItemBatchAdmission.endRequest(scope)
        }
        process(request, if (patched) Transaction.TransactionState.Reject else Transaction.TransactionState.Accept, if (patched) 0 else 1)
        unchanged(source, destination, a, b)
    }

    private fun reservedOverflow() {
        transactions.clear()
        val source = container(100)
        val destination = container(8)
        val reservedItem = item(source, 3f)
        val a = item(source, 3f)
        val b = item(source, 3f)
        val reserved = packet(entry(reservedItem, destination))
        reserved.state = Transaction.TransactionState.Accept
        reserved.playerId.setID(20)
        val competitor = unsafe.allocateInstance(Player::class.java) as Player
        competitor.onlineId = 20
        field(PlayerID::class.java, "player").set(reserved.playerId, competitor)
        transactions.add(reserved)
        process(packet(entry(a, destination), entry(b, destination)), Transaction.TransactionState.Reject, 1)
        require(transactions.peek() === reserved && reserved.state == Transaction.TransactionState.Accept, "existing reservation was mutated")
        unchanged(source, destination, reservedItem, a, b)
    }

    private fun fitting() {
        transactions.clear()
        val source = container(100)
        val destination = container(6)
        val a = item(source, 3f)
        val b = item(source, 3f)
        process(packet(entry(a, destination), entry(b, destination)), Transaction.TransactionState.Accept, 1)
        unchanged(source, destination, a, b)
        transactions.clear()
        val other = container(3)
        process(packet(entry(a, destination), entry(b, other)), Transaction.TransactionState.Accept, 1)
        require(other.items.isEmpty(), "independent destination changed")
        unchanged(source, destination, a, b)
    }

    private fun bag() {
        transactions.clear()
        val source = container(100)
        val destination = container(8)
        val bag = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        val script = unsafe.allocateInstance(zombie.scripting.objects.Item::class.java) as zombie.scripting.objects.Item
        script.maxItemSize = 5f
        field(InventoryItem::class.java, "scriptItem").set(bag, script)
        destination.inventoryContainer = bag
        val a = item(source, 4f)
        val b = item(source, 4f)
        require(destination.hasRoomFor(player, a) && destination.hasRoomFor(player, b) && !destination.hasRoomFor(player, 8f),
            "bag fixture does not distinguish item size from batch weight")
        process(packet(entry(a, destination), entry(b, destination)), Transaction.TransactionState.Accept, 1)
        unchanged(source, destination, a, b)
    }

    private fun nativeRules() {
        transactions.clear()
        val source = container(100)
        val destination = container(100)
        val a = item(source, 1f)
        val b = item(source, 1f)
        destination.setOnlyAcceptCategory("Food")
        process(packet(entry(a, destination), entry(b, destination)), Transaction.TransactionState.Reject, 0)
        destination.setOnlyAcceptCategory(null)
        val missing = Transaction.TransactionEntry(12345)
        missing.sourceId.containerType = ContainerID.ContainerType.ObjectContainer
        missing.destinationId.containerType = ContainerID.ContainerType.ObjectContainer
        field(ContainerID::class.java, "container").set(missing.sourceId, source)
        field(ContainerID::class.java, "container").set(missing.destinationId, destination)
        process(packet(entry(a, destination), missing), Transaction.TransactionState.Reject, 0)
        val single = container(1)
        process(packet(entry(a, single)), Transaction.TransactionState.Accept, 1)
        unchanged(source, destination, a, b)
        require(single.items.isEmpty(), "single request moved item")
    }

    private fun clean() {
        for (name in arrayOf("requests", "checks")) {
            require((field(ItemBatchAdmission::class.java, name).get(null) as ThreadLocal<*>).get() == null, "$name scope leaked")
        }
    }

    private fun unchecked(action: () -> Unit) {
        try {
            action()
        } catch (failure: Exception) {
            throw RuntimeException(failure)
        }
    }

    private fun changed(bytes: ByteArray, method: String): ByteArray {
        val reader = ClassReader(bytes)
        val writer = ClassWriter(reader, 0)
        reader.accept(object : ClassVisitor(Opcodes.ASM9, writer) {
            override fun visitMethod(access: Int, name: String?, descriptor: String?, signature: String?, exceptions: Array<out String>?): MethodVisitor? {
                val visitor = super.visitMethod(access, name, descriptor, signature, exceptions)
                if (name != method) return visitor
                return object : MethodVisitor(Opcodes.ASM9, visitor) {
                    override fun visitCode() {
                        super.visitCode()
                        super.visitInsn(Opcodes.NOP)
                    }
                }
            }
        }, 0)
        return writer.toByteArray()
    }

    private fun weaving() {
        val nativeBytes = ItemBatchAdmissionChecks::class.java.classLoader
            .getResourceAsStream("zombie/core/TransactionManager.class").use { it.readAllBytes() }
        val woven = ItemBatchAdmission.weave(nativeBytes)
        require(woven != null && ItemBatchAdmission.weave(woven) == null, "native weave missing or applied twice")
        require(ItemBatchAdmission.weave(changed(nativeBytes, "isConsistent")) == null, "changed admission method accepted")
        require(ItemBatchAdmission.weave(changed(nativeBytes, "removeItemTransaction")) != null, "independent ownership method conflicts with admission")
        var hooks = 0
        ClassReader(woven).accept(object : ClassVisitor(Opcodes.ASM9) {
            override fun visitMethod(access: Int, name: String?, descriptor: String?, signature: String?, exceptions: Array<out String>?): MethodVisitor =
                object : MethodVisitor(Opcodes.ASM9) {
                    override fun visitMethodInsn(opcode: Int, owner: String?, method: String?, desc: String?, itf: Boolean) {
                        if (owner == "net/alexredby/pztoolkitjavapatches/ItemBatchAdmission" && method == "reservations") {
                            require(name == "isConsistent", "reservation hook escaped consistency method")
                            hooks++
                        }
                    }
                }
        }, 0)
        require(hooks == 1, "native reservation iterator was not replaced exactly once")
    }

    private fun vehicle() {
        transactions.clear()
        val source = container(100)
        val destination = container(5)
        destination.parent = unsafe.allocateInstance(zombie.vehicles.BaseVehicle::class.java) as zombie.vehicles.BaseVehicle
        destination.sourceGrid = unsafe.allocateInstance(zombie.iso.IsoGridSquare::class.java) as zombie.iso.IsoGridSquare
        val a = item(source, 3f)
        val b = item(source, 3f)
        process(packet(entry(a, destination), entry(b, destination)), Transaction.TransactionState.Reject, 0)
        unchanged(source, destination, a, b)
    }

    private fun scopeChecks() {
        transactions.clear()
        val source = container(100)
        val destination = container(5)
        val a = item(source, 3f)
        val b = item(source, 3f)
        val outer = packet(entry(a, destination), entry(b, destination))
        // Nested packet processing uses its own connection, so each caller still receives one reply.
        val nestedSource = container(100)
        val nestedDestination = container(2)
        val c = item(nestedSource, 1f)
        val d = item(nestedSource, 1f)
        val inner = packet(entry(c, nestedDestination), entry(d, nestedDestination))
        val nestedConnection = unsafe.allocateInstance(Connection::class.java) as Connection
        nestedConnection.players = connection.players
        nestedConnection.bytes = ByteBuffer.allocate(1024)
        b.onWeight = {
            unchecked {
                require(TransactionManager.isConsistent(a.getID(), null, source, destination, null, outer, player) == 0.toByte(),
                    "reentrant same-packet check inherited outer prefix")
                val previous = connection
                connection = nestedConnection
                try {
                    process(inner, Transaction.TransactionState.Accept, 1)
                } finally {
                    connection = previous
                }
            }
        }
        process(outer, Transaction.TransactionState.Reject, 1)
        clean()
        require(transactions.peek() === inner, "nested request lost its real queue membership")
        unchanged(source, destination, a, b)
        unchanged(nestedSource, nestedDestination, c, d)
        transactions.clear()
        val failing = packet(entry(a, destination), entry(b, destination))
        a.onWeight = { throw IllegalStateException("native weight failure") }
        val replies = connection.replies
        try {
            failing.processServer(PacketTypes.PacketType.ItemTransaction, connection)
            throw AssertionError("native exception swallowed")
        } catch (expected: IllegalStateException) {
            require(expected.message == "native weight failure", "wrong native exception")
        }
        require(transactions.isEmpty() && replies == connection.replies, "failed validation admitted or replied")
        clean()
        val excluded = packet(entry(a, destination), entry(b, destination))
        for (type in arrayOf(ContainerID.ContainerType.Undefined, ContainerID.ContainerType.IsoObject, ContainerID.ContainerType.Floor)) {
            excluded.entries[0].sourceId.containerType = type
            require(ItemBatchAdmission.beginRequest(excluded) == null, "special container entered batch scope")
        }
        excluded.entries[0].sourceId.containerType = ContainerID.ContainerType.ObjectContainer
        source.type = "floor"
        require(ItemBatchAdmission.beginRequest(excluded) == null, "floor entered batch scope")
        source.type = "crate"
        excluded.extra = "native-special"
        require(ItemBatchAdmission.beginRequest(excluded) == null, "special extra entered batch scope")
        clean()
    }

    private fun ownership() {
        transactions.clear()
        val source = container(100)
        val destination = container(100)
        val item = item(source, 1f)
        val own = packet(entry(item, destination))
        own.state = Transaction.TransactionState.Accept
        val foreign = packet(entry(item, destination))
        foreign.id = own.id
        foreign.state = Transaction.TransactionState.Accept
        val other = unsafe.allocateInstance(Player::class.java) as Player
        other.onlineId = 20
        foreign.playerId.setID(other.onlineId)
        field(PlayerID::class.java, "player").set(foreign.playerId, other)
        transactions.add(own)
        transactions.add(foreign)
        val reject = ItemTransactionPacket()
        reject.id = own.id
        reject.state = Transaction.TransactionState.Reject
        reject.processServer(PacketTypes.PacketType.ItemTransaction, connection)
        require(transactions.size == 1 && transactions.peek() === foreign, "batch advice broke owned Reject cancellation")
        clean()
        transactions.clear()
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        unsafe = field(Unsafe::class.java, "theUnsafe").get(null) as Unsafe
        transactions = Accessor.tryGet<ConcurrentLinkedQueue<Transaction>>(TransactionManager::class.java, "transactions", null)
            ?: throw AssertionError("native reservation queue unavailable")
        player = unsafe.allocateInstance(Player::class.java) as Player
        player.onlineId = 19
        field(zombie.iso.IsoObject::class.java, "ecsComponentMap").set(player, HashMap<Any?, Any?>())
        connection = unsafe.allocateInstance(Connection::class.java) as Connection
        connection.players = arrayOf(player)
        connection.bytes = ByteBuffer.allocate(1024)
        ServerOptions.getInstance().safehouseAllowLoot.setValue(true)
        GameServer.server = true
        GameClient.client = false
        overflow(false)
        transactions.clear()
        weaving()
        if (args.firstOrNull() == "patch-first") {
            PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", ItemBatchAdmissionChecks::class.java.classLoader)
            require(!ItemBatchAdmission.install(ItemBatchAdmission.SUPPORTED), "changed transformer chain reported enabled")
            overflow(false)
            clean()
            transactions.clear()
            println("ITEM_BATCH_ADMISSION_PATCH_FIRST_PASS (changed transformation order disabled safely)")
            return
        }
        require(ItemBatchAdmission.SUPPORTED && ItemBatchAdmission.install(ItemBatchAdmission.SUPPORTED), "native batch reservation patch unsupported")
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", ItemBatchAdmissionChecks::class.java.classLoader)
        overflow(true)
        clean()
        reservedOverflow()
        clean()
        fitting()
        clean()
        bag()
        clean()
        nativeRules()
        clean()
        vehicle()
        clean()
        scopeChecks()
        ownership()
        val instrumentation = Accessor.tryGet<java.lang.instrument.Instrumentation>(Loader::class.java, "g_instrumentation", null)
            ?: throw AssertionError("agent instrumentation unavailable")
        instrumentation.retransformClasses(TransactionManager::class.java, ItemTransactionPacket::class.java)
        overflow(true)
        clean()
        transactions.clear()
        println("ITEM_BATCH_ADMISSION_CHECKS_PASS (original overflow, native whole-request Reject/Accept wire, existing reservations, exact fit, per-item bag limit, source/admission rules, vehicle, unchanged inventories, nested/reentrant/exception scopes, ownership compatibility, repeat transformation)")
    }
}
