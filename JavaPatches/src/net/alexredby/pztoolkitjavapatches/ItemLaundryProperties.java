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
        "48f01be16d1ef1b76e37638fac6e25ca4eb285ad38ab2f462caa5597318c7f9d")
        && BytecodeSupport.supports("zombie/core/skinnedmodel/visual/ItemVisual.class",
        "78af8897986c28c5948d7ad80dbf8cf372c52bd5a32dfb720586f3716e472de6")
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
