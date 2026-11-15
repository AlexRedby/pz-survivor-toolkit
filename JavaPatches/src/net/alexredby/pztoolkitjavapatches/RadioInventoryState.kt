package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Patch
import zombie.core.network.ByteBufferReader
import zombie.core.raknet.UdpConnection
import zombie.inventory.types.Radio
import zombie.network.GameServer

/** Complete the native missing inventory-radio off route using the native state decoder/relay. */
object RadioInventoryState {
    @JvmField
    val SUPPORTED =
        BytecodeSupport.supports(
            "zombie/network/GameServer.class",
            "efc98251a41d4d56a1d5ebd944e0c8a2bfa15270dabfd307107e59191f2ededf",
        ) &&
            BytecodeSupport.supports(
                "zombie/radio/devices/DeviceData.class",
                "6c8825dbc39b2a7508a903dd3ef381bbb3dbd9b96f89398d9deeaddde0162bed",
            ) &&
            BytecodeSupport.supports(
                "zombie/inventory/ItemContainer.class",
                "19ffefbabfc16ce3b40feb557189c4fbecdb752aa2c96e3daa8b8ec0542185d3",
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
