package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field
import zombie.network.packets.ItemStatsPacket

internal object ItemStatsDefaultLogic {
    private class Fields(
        val floats: Array<Field>,
        val integers: Array<Field>,
        val poisonDetectionLevel: Field,
    )

    private val fields = load()
    @JvmField val supported = fields != null

    private fun fields(type: Class<*>, vararg names: String): Array<Field> =
        Array(names.size) { index ->
            ItemStatsPacket::class.java.getDeclaredField(names[index]).apply {
                if (this.type != type) throw NoSuchFieldException("${names[index]} type")
                isAccessible = true
            }
        }

    private fun load(): Fields? {
        if (
            !BytecodeSupport.supports(
                "zombie/network/packets/ItemStatsPacket.class",
                "1b2cd2f150e418d8266cdee8ab671210f8676bf9fd02f596eb5265f1389eaa8a",
            )
        )
            return null
        try {
            return Fields(
                fields(
                    java.lang.Float.TYPE,
                    "cookingTime",
                    "minutesToCook",
                    "minutesToBurn",
                    "hungChange",
                    "calories",
                    "proteins",
                    "lipids",
                    "carbohydrates",
                    "thirstChange",
                    "painReduction",
                    "endChange",
                    "stressChange",
                    "fatigueChange",
                    "unhappyChange",
                    "boredomChange",
                    "baseHunger",
                ),
                fields(Integer.TYPE, "fluReduction", "foodSicknessChange", "fertilizedTime"),
                fields(Integer.TYPE, "poisonDetectionLevel")[0],
            )
        } catch (error: ReflectiveOperationException) {
            disabled(error)
        } catch (error: RuntimeException) {
            disabled(error)
        }
        return null
    }

    private fun disabled(error: Exception) {
        System.err.println("[PZToolkitJavaPatches] Disabled item-stat defaults: $error")
    }

    @JvmStatic
    fun reset(packet: ItemStatsPacket?, supported: Boolean) {
        val fields = fields
        if (!supported || fields == null || packet == null) return
        try {
            for (field in fields.floats) field.setFloat(packet, 0f)
            for (field in fields.integers) field.setInt(packet, 0)
            // The writer omits -1 here, unlike the Java default of a fresh packet.
            fields.poisonDetectionLevel.setInt(packet, -1)
        } catch (error: IllegalAccessException) {
            throw IllegalStateException("Validated item-stat fields became inaccessible", error)
        }
    }
}
