package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Patch
import zombie.core.network.ByteBufferReader
import zombie.network.IConnection
import zombie.network.packets.ItemStatsPacket

/** Restore omitted wire values before the connection's cached packet is parsed again. */
object ItemStatsDefaults {
    @JvmField val SUPPORTED = ItemStatsDefaultLogic.supported

    @JvmStatic
    fun reset(packet: ItemStatsPacket?, supported: Boolean) {
        ItemStatsDefaultLogic.reset(packet, supported)
    }

    @Patch(
        className = "zombie.network.packets.ItemStatsPacket",
        methodName = "parse",
        warmUp = true,
        strictMatch = true,
    )
    object Parsed {
        @JvmStatic
        @Patch.OnEnter
        fun enter(
            @Patch.This packet: ItemStatsPacket?,
            @Patch.Argument(0) reader: ByteBufferReader?,
            @Patch.Argument(1) connection: IConnection?,
        ) {
            reset(packet, SUPPORTED)
        }
    }
}
