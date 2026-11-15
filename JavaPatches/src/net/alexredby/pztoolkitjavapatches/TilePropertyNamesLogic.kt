package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Accessor
import zombie.core.properties.IsoPropertyType

internal object TilePropertyNamesLogic {
    @JvmField
    val SUPPORTED =
        BytecodeSupport.supports(
            "zombie/core/properties/IsoPropertyType.class",
            "c713a1a7b47b8f0cd920742967e7a94f738fa935b57952a5ce9bcdc8f1e23217",
        ) &&
            BytecodeSupport.supports(
                "zombie/core/TilePropertyAliasMap.class",
                "05124f3536bc2026fb29d5f7369dc0d809d1a725477d4733a1e0e827911a0a80",
            )

    @JvmStatic
    fun accepts(name: String?, supported: Boolean): Boolean {
        if (!supported || name == null) return false
        if (name != "WindowShape") return false
        val types =
            Accessor.tryGet<Map<*, *>>(IsoPropertyType::class.java, "BY_NAME", null) ?: return false
        // Preserve typed aliases installed by another mod, and fail closed if access fails.
        return types[name] == null
    }
}
