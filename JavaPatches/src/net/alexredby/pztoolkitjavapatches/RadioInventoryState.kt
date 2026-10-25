package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Patch
import zombie.core.network.ByteBufferReader
import zombie.core.raknet.UdpConnection
import zombie.inventory.types.Radio
import zombie.network.GameServer

/** Complete B42.21's missing inventory-radio off route using the native state decoder/relay. */
object RadioInventoryState {
    @JvmField
    val SUPPORTED =
        BytecodeSupport.supports(
            "zombie/network/GameServer.class",
            "308ee5247dc8bba4df2283d40d753c6839497767b9342a4adeea60e7c08cfacc",
        ) &&
            BytecodeSupport.supports(
                "zombie/radio/devices/DeviceData.class",
                "492af532cddfe49908a5f479e2749b8dc08334a6b661ab81eb81892926cdb102",
            ) &&
            BytecodeSupport.supports(
                "zombie/inventory/ItemContainer.class",
                "a2ac7dd6235f91255dc57b91419a2c8609bdb105214cddf7fb445b70507b6f96",
            )

    @JvmStatic
    fun receive(
        reader: ByteBufferReader?,
        connection: UdpConnection?,
        supported: Boolean,
    ): Boolean {
        if (
            !supported ||
                !GameServer.server ||
                reader == null ||
                connection == null ||
                !connection.isFullyConnected ||
                GameServer.udpEngine == null
        )
            return false
        val buffer = reader.bb
        if (buffer.remaining() != 10) return false
        // Client route: inventory, local player index, unheld selector, item ID, state, false.
        // Probe without changing the caller's position, mark, limit or byte order.
        val probe = buffer.duplicate().order(buffer.order())
        if (probe.get().toInt() != 0) return false
        val index = probe.get().toInt()
        if (index !in 0..3 || probe.get().toInt() != 0) return false
        val id = probe.int
        if (probe.short.toInt() != 0 || probe.get().toInt() != 0) return false
        val player = GameServer.getPlayerFromConnection(connection, index) ?: return false
        if (GameServer.getConnectionFromPlayer(player) !== connection) return false
        val root = player.inventory ?: return false
        if (root.parent !== player) return false
        val radio = root.getItemWithID(id) as? Radio ?: return false
        if (
            radio.container !== root ||
                player.primaryHandItem === radio ||
                player.secondaryHandItem === radio
        )
            return false
        val data = radio.deviceData ?: return false
        if (data.parent !== radio) return false

        // All validation precedes mutation. Reuse native off semantics and its relay excluding
        // the origin; do not fall through into the outer parser after consuming any payload.
        buffer.position(buffer.position() + 7)
        try {
            data.receiveDeviceDataStatePacket(reader, connection)
        } catch (error: Exception) {
            System.out.print(error.message) // Same exception policy as the native held-radio path.
        }
        return true
    }

    @Patch(
        className = "zombie.network.GameServer",
        methodName = "receiveRadioDeviceDataState",
        warmUp = true,
        strictMatch = true,
    )
    object Received {
        @JvmStatic
        @Patch.OnEnter(skipOn = true)
        fun enter(
            @Patch.Argument(0) reader: ByteBufferReader?,
            @Patch.Argument(1) connection: UdpConnection?,
        ): Boolean = receive(reader, connection, SUPPORTED)
    }
}
