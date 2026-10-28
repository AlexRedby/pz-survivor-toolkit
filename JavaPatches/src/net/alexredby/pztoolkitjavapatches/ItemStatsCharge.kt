package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Patch
import zombie.inventory.InventoryItem
import zombie.network.packets.ItemStatsPacket

/** Preserve exact drainable charge after the shared native packet receiver succeeds. */
object ItemStatsCharge {
    @JvmField val SUPPORTED = ItemStatsChargeLogic.supported

    @JvmStatic
    fun restore(packet: ItemStatsPacket?, item: InventoryItem?, supported: Boolean) {
        ItemStatsChargeLogic.restore(packet, item, supported)
    }

    @Patch(
        className = "zombie.network.packets.ItemStatsPacket",
        methodName = "applyItemStats",
        warmUp = true,
        strictMatch = true,
    )
    object Applied {
        @JvmStatic
        @Patch.OnExit
        fun exit(@Patch.This packet: ItemStatsPacket?, @Patch.Argument(0) item: InventoryItem?) {
            // DrainableComboItem is final and its setter only updates uses/weight.
            // Other successfully applied native fields and all error paths stay native.
            restore(packet, item, SUPPORTED)
        }
    }
}
