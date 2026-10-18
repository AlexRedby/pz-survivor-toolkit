package net.alexredby.pztoolkitjavapatches;

import java.util.List;
import java.util.Map;
import zombie.core.TilePropertyAliasMap;
import zombie.core.properties.PropertyContainer;
import zombie.iso.SpriteDetails.IsoFlagType;
import zombie.iso.sprite.IsoSpriteManager;

public final class FenceProperties {
    private FenceProperties() { }

    public static int tilesLoaded(IsoSpriteManager manager, boolean supported) {
        if (!supported || manager == null) return 0;
        var aliases = TilePropertyAliasMap.instance;
        int property = aliases.getIDFromPropertyName("FenceTypeLow");
        if (property < 0 || !"Wood".equals(aliases.getPropertyValueString(property,
            aliases.getIDFromPropertyValue(property, "Wood")))) return 0;
        int corrected = 0;
        for (int tile : new int[]{48, 49}) {
            String name = "carpentry_02_" + tile;
            var sprite = manager.namedMap.get(name);
            if (sprite != null && name.equals(sprite.name) && stock(sprite.getProperties(), tile)) {
                // B42.21 omitted the level-three metadata present on both lower wooden fence levels.
                sprite.getProperties().set("FenceTypeLow", "Wood");
                corrected++;
            }
        }
        return corrected;
    }

    private static boolean stock(PropertyContainer properties, int tile) {
        boolean west = tile == 48;
        var expected = Map.of("CanScrap", "", "CloseSneakBonus", "1000", "HitByCar", "",
            "IsPaintable", "", "Material", "Wood", "Material2", "Nails", "PaintingType", "crates",
            "ScrapSize", "Small", "SnowTile", "object_snow_overlay_01_" + (west ? 252 : 253),
            west ? "WallWTrans" : "WallNTrans", "");
        if (properties.getPropertyNames().size() != expected.size() + 1
            || !"WoodFenceLvl3".equals(properties.get("EntityScriptName"))
            || !properties.getPropertyNames().containsAll(expected.keySet())) return false;
        for (var entry : expected.entrySet())
            if (!entry.getValue().equals(properties.get(entry.getKey()))) return false;
        return properties.getFlagsList().equals(west
            ? List.of(IsoFlagType.collideW, IsoFlagType.transparentW, IsoFlagType.cutW,
                IsoFlagType.HoppableW, IsoFlagType.canPathW, IsoFlagType.WallWTrans, IsoFlagType.EntityScript)
            : List.of(IsoFlagType.collideN, IsoFlagType.transparentN, IsoFlagType.cutN,
                IsoFlagType.HoppableN, IsoFlagType.canPathN, IsoFlagType.WallNTrans, IsoFlagType.EntityScript));
    }
}
