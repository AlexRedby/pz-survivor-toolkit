package zombie.radio.devices

import java.nio.ByteBuffer
import java.nio.ByteOrder
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.RadioInventoryState
import sun.misc.Unsafe
import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.core.network.ByteBufferReader
import zombie.core.network.ByteBufferWriter
import zombie.core.raknet.UdpConnection
import zombie.core.raknet.UdpEngine
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.inventory.types.Radio
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.PacketTypes

/** Real native writer, original dropped packet, woven parser and native origin-excluding relay. */
object RadioInventoryStateChecks {
    class Connection : UdpConnection(null, 0, 0) {
        lateinit var output: ByteBuffer
        lateinit var packets: MutableList<ByteArray>
        var starts = 0
        var cancelled = 0

        override fun startPacket(): ByteBufferWriter {
            starts++
            output = ByteBuffer.allocate(128)
            return ByteBufferWriter(output)
        }

        override fun endPacket(priority: Int, reliability: Int, channel: Byte) {
            packets.add(output.array().copyOf(output.position()))
        }

        override fun cancelPacket() {
            cancelled++
        }

        override fun isLimitExceeded(type: PacketTypes.PacketType?): Boolean = false
    }

    private lateinit var unsafe: Unsafe
    private lateinit var player: IsoPlayer
    private lateinit var root: ItemContainer
    private lateinit var radio: Radio
    private lateinit var data: DeviceData
    private lateinit var origin: Connection
    private lateinit var peer: Connection

    private fun require(value: Boolean, reason: String) {
        if (!value) throw AssertionError(reason)
    }

    private fun set(target: Any, type: Class<*>, name: String, value: Any?) {
        type.getDeclaredField(name).apply { isAccessible = true }.set(target, value)
    }

    private fun connection(): Connection =
        (unsafe.allocateInstance(Connection::class.java) as Connection).apply {
            packets = ArrayList()
            set(this, UdpConnection::class.java, "fullyConnected", true)
            set(this, UdpConnection::class.java, "players", arrayOfNulls<IsoPlayer>(4))
        }

    private fun held(primary: Boolean, value: InventoryItem?) {
        set(
            player,
            IsoGameCharacter::class.java,
            if (primary) "leftHandItem" else "rightHandItem",
            value,
        )
    }

    private fun input(
        payload: ByteArray,
        order: ByteOrder = ByteOrder.BIG_ENDIAN,
    ): ByteBufferReader {
        val buffer = ByteBuffer.allocate(payload.size + 12).order(order)
        buffer.position(5)
        buffer.put(payload).flip().position(5)
        buffer.mark()
        return ByteBufferReader(buffer)
    }

    private fun declined(payload: ByteArray, reason: String, supported: Boolean = true) {
        data.isTurnedOn = true
        val reader = input(payload)
        val before = reader.bb.array().clone()
        val limit = reader.bb.limit()
        val sent = peer.packets.size
        require(!RadioInventoryState.receive(reader, origin, supported), reason)
        require(
            reader.bb.position() == 5 &&
                reader.bb.limit() == limit &&
                reader.bb.order() == ByteOrder.BIG_ENDIAN &&
                reader.bb.array().contentEquals(before),
            "$reason: buffer changed",
        )
        reader.bb.reset()
        require(
            reader.bb.position() == 5 && data.isTurnedOn && peer.packets.size == sent,
            "$reason: effects or mark changed",
        )
    }

    private fun wire(): ByteArray {
        // Invoke the actual native private writer, including its inventory/hand routing decision.
        GameServer.server = false
        GameClient.client = true
        data.isTurnedOn = false
        DeviceData::class
            .java
            .getDeclaredMethod(
                "sendDeviceDataStatePacket",
                UdpConnection::class.java,
                java.lang.Short.TYPE,
            )
            .apply { isAccessible = true }
            .invoke(data, origin, 0.toShort())
        val result = origin.packets.single()
        require(result.size == 13, "native off writer layout changed")
        origin.packets.clear()
        GameServer.server = true
        GameClient.client = false
        data.isTurnedOn = true
        return result.copyOfRange(3, result.size)
    }

    private fun assertRelay() {
        require(origin.packets.isEmpty(), "native relay echoed to source connection")
        val packet = peer.packets.single()
        val decoded = ByteBuffer.wrap(packet)
        require(
            decoded.get().toInt() and 255 == 134 &&
                decoded.short == PacketTypes.PacketType.RadioDeviceDataState.id,
            "native relay header changed",
        )
        require(
            decoded.get().toInt() == 0 &&
                decoded.short == player.onlineId &&
                decoded.get().toInt() == 0 &&
                decoded.int == radio.id &&
                decoded.short.toInt() == 0 &&
                decoded.get().toInt() == 0 &&
                !decoded.hasRemaining(),
            "native server relay did not preserve exact owner/item/off state",
        )
        peer.packets.clear()
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        unsafe =
            Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null)
                as Unsafe
        player = unsafe.allocateInstance(IsoPlayer::class.java) as IsoPlayer
        player.onlineId = 17
        player.playerIndex = 2
        root = ItemContainer().apply { parent = player }
        set(player, IsoGameCharacter::class.java, "inventory", root)
        radio = unsafe.allocateInstance(Radio::class.java) as Radio
        radio.id = 1234567
        radio.container = root
        root.items.add(radio)
        data = DeviceData(radio)
        radio.deviceData = data
        origin = connection()
        peer = connection()
        origin.players[2] = player
        val engine = unsafe.allocateInstance(UdpEngine::class.java) as UdpEngine
        set(engine, UdpEngine::class.java, "connectionMap", hashMapOf(42L to origin))
        set(engine, UdpEngine::class.java, "connections", arrayListOf(origin, peer))
        GameServer.udpEngine = engine
        GameServer.PlayerToAddressMap[player] = 42L
        val off = wire()
        require(RadioInventoryState.SUPPORTED, "unsupported B42.21 radio baseline")
        val original = input(off)
        GameServer.receiveRadioDeviceDataState(original, origin, 999)
        require(
            data.isTurnedOn && original.bb.position() == 8 && peer.packets.isEmpty(),
            "original server did not reproduce the lost unheld off packet",
        )

        declined(off, "unsupported version accepted", false)
        GameServer.server = false
        declined(off, "standalone accepted")
        GameServer.server = true
        for (size in 0..9) declined(off.copyOf(size), "truncated payload $size accepted")
        declined(off + 0, "trailing byte accepted")
        for ((offset, bytes) in
            listOf(
                0 to listOf(1, 2, 3),
                1 to listOf(-1, 4),
                2 to listOf(1, 2, 3),
                8 to listOf(1, 2, 10),
                9 to listOf(1, 2, -1),
            )) {
            for (byte in bytes) declined(
                off.clone().apply { this[offset] = byte.toByte() },
                "route/index/selector/state/boolean $offset/$byte accepted",
            )
        }
        declined(off.clone().apply { this[3] = 127 }, "unknown item accepted")
        set(origin, UdpConnection::class.java, "fullyConnected", false)
        declined(off, "incomplete connection accepted")
        set(origin, UdpConnection::class.java, "fullyConnected", true)
        origin.players[2] = null
        declined(off, "missing connection player accepted")
        origin.players[2] = player
        GameServer.PlayerToAddressMap.remove(player)
        declined(off, "stale connection accepted")
        GameServer.PlayerToAddressMap[player] = 42L
        val foreign = unsafe.allocateInstance(IsoPlayer::class.java) as IsoPlayer
        origin.players[2] = foreign
        declined(off, "foreign connection player accepted")
        origin.players[2] = player
        root.parent = foreign
        declined(off, "foreign root parent accepted")
        root.parent = player
        radio.container = ItemContainer()
        declined(off, "nested/foreign item container accepted")
        radio.container = root
        root.items.clear()
        declined(off, "absent root item accepted")
        val other = unsafe.allocateInstance(InventoryItem::class.java) as InventoryItem
        other.id = radio.id
        root.items.add(other)
        declined(off, "non-radio item accepted")
        root.items.clear()
        root.items.add(radio)
        data.parent = null
        declined(off, "missing device parent accepted")
        data.parent = radio
        // Native Radio.setDeviceData(null) constructs a fresh DeviceData; it cannot stay null.
        for (primary in listOf(true, false)) {
            held(primary, radio)
            declined(off, "held item accepted through unheld selector")
            held(primary, null)
        }
        require(
            !RadioInventoryState.receive(null, origin, true) &&
                !RadioInventoryState.receive(input(off), null, true),
            "null arguments accepted",
        )

        PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            RadioInventoryStateChecks::class.java.classLoader,
        )
        val patched = input(off)
        GameServer.receiveRadioDeviceDataState(patched, origin, 999)
        require(
            !data.isTurnedOn && patched.bb.position() == 15,
            "woven unheld off did not decode once",
        )
        assertRelay()
        // The subtype is in the payload, not callback arg2. Preserve nonzero buffer
        // positions/order.
        val little =
            off.clone().apply {
                val bytes = ByteBuffer.wrap(this).order(ByteOrder.LITTLE_ENDIAN)
                bytes.putInt(3, radio.id)
            }
        data.isTurnedOn = true
        val le = input(little, ByteOrder.LITTLE_ENDIAN)
        GameServer.receiveRadioDeviceDataState(le, origin, 5)
        require(
            !data.isTurnedOn && le.bb.position() == 15 && le.bb.order() == ByteOrder.LITTLE_ENDIAN,
            "woven parser assumed zero position or big endian",
        )
        assertRelay()
        // Held packets use vanilla's shorter layout and must still apply through the original body.
        for (primary in listOf(true, false)) {
            held(primary, radio)
            data.isTurnedOn = true
            val reader = input(byteArrayOf(0, 2, if (primary) 1 else 2, 0, 0, 0))
            GameServer.receiveRadioDeviceDataState(reader, origin, 0)
            require(
                !data.isTurnedOn && !reader.bb.hasRemaining(),
                "woven patch suppressed native held path",
            )
            require(peer.packets.size == 1 && origin.packets.isEmpty(), "native held relay changed")
            peer.packets.clear()
            held(primary, null)
        }
        for (payload in
            listOf(off.clone().apply { this[9] = 1 }, off.clone().apply { this[8] = 1 })) {
            data.isTurnedOn = true
            val reader = input(payload)
            GameServer.receiveRadioDeviceDataState(reader, origin, 0)
            require(
                data.isTurnedOn && reader.bb.position() == 8 && peer.packets.isEmpty(),
                "woven patch expanded the unrelated unheld state path",
            )
        }
        println(
            "RADIO_INVENTORY_STATE_CHECKS_PASS (native writer/original loss, woven off, owner/root/type/hand/payload guards, positioned buffers, native relay and held fallback)",
        )
    }
}
