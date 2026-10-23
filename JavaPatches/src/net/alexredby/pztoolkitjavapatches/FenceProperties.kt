package net.alexredby.pztoolkitjavapatches

import zombie.core.TilePropertyAliasMap
import zombie.core.properties.PropertyContainer
import zombie.iso.SpriteDetails.IsoFlagType
import zombie.iso.sprite.IsoSpriteManager

object FenceProperties {
    @JvmStatic
    fun tilesLoaded(manager: IsoSpriteManager?, supported: Boolean): Int {
        if (!supported || manager == null) return 0
        val aliases = TilePropertyAliasMap.instance
        val property = aliases.getIDFromPropertyName("FenceTypeLow")
        if (
            property < 0 ||
                "Wood" !=
                    aliases.getPropertyValueString(
                        property,
                        aliases.getIDFromPropertyValue(property, "Wood"),
                    )
        )
            return 0
        var corrected = 0
        for (tile in intArrayOf(48, 49)) {
            val name = "carpentry_02_$tile"
            val sprite = manager.namedMap[name]
            if (sprite != null && name == sprite.name && stock(sprite.getProperties(), tile)) {
                // B42.21 omitted the level-three metadata present on both lower wooden fence
                // levels.
                sprite.getProperties().set("FenceTypeLow", "Wood")
                corrected++
            }
        }
        return corrected
    }

    private fun stock(properties: PropertyContainer, tile: Int): Boolean {
        val west = tile == 48
        val expected =
            mapOf(
                "CanScrap" to "",
                "CloseSneakBonus" to "1000",
                "HitByCar" to "",
                "IsPaintable" to "",
                "Material" to "Wood",
                "Material2" to "Nails",
                "PaintingType" to "crates",
                "ScrapSize" to "Small",
                "SnowTile" to "object_snow_overlay_01_${if (west) 252 else 253}",
                (if (west) "WallWTrans" else "WallNTrans") to "",
            )
        if (
            properties.propertyNames.size != expected.size + 1 ||
                "WoodFenceLvl3" != properties.get("EntityScriptName") ||
                !properties.propertyNames.containsAll(expected.keys)
        )
            return false
        for ((key, value) in expected) if (value != properties.get(key)) return false
        return properties.flagsList ==
            if (west)
                listOf(
                    IsoFlagType.collideW,
                    IsoFlagType.transparentW,
                    IsoFlagType.cutW,
                    IsoFlagType.HoppableW,
                    IsoFlagType.canPathW,
                    IsoFlagType.WallWTrans,
                    IsoFlagType.EntityScript,
                )
            else
                listOf(
                    IsoFlagType.collideN,
                    IsoFlagType.transparentN,
                    IsoFlagType.cutN,
                    IsoFlagType.HoppableN,
                    IsoFlagType.canPathN,
                    IsoFlagType.WallNTrans,
                    IsoFlagType.EntityScript,
                )
    }
}
