package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.characterTextures.BloodClothingType;
import zombie.core.skinnedmodel.visual.ItemVisual;
import zombie.inventory.InventoryItem;
import zombie.inventory.types.Clothing;
import zombie.inventory.types.InventoryContainer;

/** Read native laundry stains without getVisual's lazy allocation and randomization. */
public final class ItemLaundryProperties {
    static final boolean SUPPORTED = BytecodeSupport.supports("zombie/inventory/InventoryItem.class",
        "b45d4438636509d992aaa7b7505ef8323cd898947efc27bf1f7e762951d6643d")
        && BytecodeSupport.supports("zombie/core/skinnedmodel/visual/ItemVisual.class",
        "eeea202e9991aa5f67bd8c1ee53115a3ade92631faed7160c1b445ca8cf2dca9")
        && BytecodeSupport.supports("zombie/characterTextures/BloodClothingType.class",
        "9a4961974009416de6229ff5befbe2853b8359f808baf0ca2605e71eed4ff283");
    private static final Field VISUAL = visualField();

    private static Field visualField() {
        if (!SUPPORTED) return null;
        try {
            var field = InventoryItem.class.getDeclaredField("visual");
            return field.getType() == ItemVisual.class && field.trySetAccessible() ? field : null;
        } catch (ReflectiveOperationException | RuntimeException unavailable) {
            return null;
        }
    }

    @LuaMethod(name="toolkitItemLaundryDirty", global=true)
    public static Boolean dirty(InventoryItem item) { return read(item, SUPPORTED); }

    static Boolean read(InventoryItem item, boolean supported) {
        if (!supported || item == null || VISUAL == null) return null;
        // Unknown subclasses may override the native predicates or coverage.
        if (item.getClass() != Clothing.class && item.getClass() != InventoryContainer.class) return null;
        try {
            var types = item.getBloodClothingType();
            if (types == null || types.isEmpty()) return false;
            var parts = BloodClothingType.getCoveredParts(types);
            if (parts == null || parts.isEmpty()) return false;
            var visual = (ItemVisual) VISUAL.get(item);
            // A native new ItemVisual has no blood/dirt arrays; initializing its
            // randomized appearance cannot add stains. Leave the null field intact.
            if (visual == null) return false;
            for (var part : parts) {
                if (visual.getBlood(part) > 0 || visual.getDirt(part) > 0) return true;
            }
            return false;
        } catch (IllegalAccessException | RuntimeException unavailable) {
            return null;
        }
    }

    private ItemLaundryProperties() {}
}
