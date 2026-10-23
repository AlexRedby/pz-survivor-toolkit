package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Accessor
import zombie.core.properties.IsoPropertyType

internal object TilePropertyNamesLogic {
    @JvmField
    val SUPPORTED = BytecodeSupport.supports("zombie/core/properties/IsoPropertyType.class",
        "7e7deb55cc8a949a4cab6cf93e0cabef01090229154203730f758526c948ebd3") &&
        BytecodeSupport.supports("zombie/core/TilePropertyAliasMap.class",
            "05124f3536bc2026fb29d5f7369dc0d809d1a725477d4733a1e0e827911a0a80")

    @JvmStatic
    fun accepts(name: String?, supported: Boolean): Boolean {
        if (!supported || name == null) return false
        when (name) {
            "ladderW", "ladderN", "ladderE", "ladderS", "WindowShape" -> Unit
            else -> return false
        }
        val types = Accessor.tryGet<Map<*, *>>(IsoPropertyType::class.java, "BY_NAME", null) ?: return false
        // Preserve typed aliases installed by another mod, and fail closed if access fails.
        return types[name] == null
    }
}
