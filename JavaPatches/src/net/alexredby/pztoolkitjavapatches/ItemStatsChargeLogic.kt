package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field
import zombie.inventory.InventoryItem
import zombie.inventory.types.DrainableComboItem
import zombie.network.packets.ItemStatsPacket

internal object ItemStatsChargeLogic {
    private class Fields(val uses: Field, val usedDelta: Field)

    private val fields = load()
    @JvmField val supported = fields != null

    private fun field(name: String, type: Class<*>): Field =
        ItemStatsPacket::class.java.getDeclaredField(name).apply {
            if (this.type != type) throw NoSuchFieldException("$name type")
            isAccessible = true
        }

    private fun load(): Fields? {
        if (
            !BytecodeSupport.supports(
                "zombie/network/packets/ItemStatsPacket.class",
                "a553efea09930272533fb4c8155ccc464069f7c6577996b1bbde35531925c3a7",
            ) ||
                !BytecodeSupport.supports(
                    "zombie/inventory/types/DrainableComboItem.class",
                    "d5b4926058d77e6f889339ccffb4c8996fd1a93cdd49aec3786fd631b8ba51ea",
                )
        )
            return null
        try {
            return Fields(field("uses", Integer.TYPE), field("usedDelta", java.lang.Float.TYPE))
        } catch (error: ReflectiveOperationException) {
            disabled(error)
        } catch (error: RuntimeException) {
            disabled(error)
        }
        return null
    }

    private fun disabled(error: Exception) {
        System.err.println("[PZToolkitJavaPatches] Disabled item-stat charge: $error")
    }

    @JvmStatic
    fun restore(packet: ItemStatsPacket?, item: InventoryItem?, supported: Boolean) {
        val fields = fields
        if (!supported || fields == null || packet == null || item !is DrainableComboItem) return
        val useDelta = item.useDelta
        if (!useDelta.isFinite() || useDelta <= 0f || useDelta > 1f) return
        val reciprocal = 1f / useDelta
        if (!reciprocal.isFinite()) return
        val maximum = item.maxUses
        if (maximum <= 0) return
        // Native setCurrentUsesFloat(1) rounds, while getMaxUses floors. Preserve
        // legitimate rounded-full items such as Battery143 with maxUses142.
        val upperBound = maxOf(maximum, Math.round(reciprocal))
        try {
            val uses = fields.uses.getInt(packet)
            val usedDelta = fields.usedDelta.getFloat(packet)
            if (uses < 0 || uses > upperBound || !usedDelta.isFinite()) return
            // setData writes both fields from the same item. Unknown/inconsistent
            // payloads retain native handling; never turn arbitrary integers into charge.
            if (usedDelta != uses.toFloat() * useDelta) return
            if (item.currentUses != uses) item.setCurrentUses(uses)
        } catch (error: IllegalAccessException) {
            throw IllegalStateException(
                "Validated item-stat charge fields became inaccessible",
                error,
            )
        }
    }
}
