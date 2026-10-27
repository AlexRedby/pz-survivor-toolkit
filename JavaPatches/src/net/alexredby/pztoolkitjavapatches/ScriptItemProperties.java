package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.scripting.objects.Item;

/** Read native item-script properties without creating an inventory item. */
public final class ScriptItemProperties {
    static final boolean SUPPORTED = BytecodeSupport.supports("zombie/scripting/objects/Item.class",
        "9e6a2f7fe48cc66843fea06b4821063d7cc6a73eaba0de8ee51d0a15c373202e");
    private static final Field BANDAGE_POWER = floatField("bandagePower");
    private static final Field ALCOHOL_POWER = floatField("alcoholPower");

    private static Field floatField(String name) {
        if (!SUPPORTED) return null;
        try {
            Field field = Item.class.getDeclaredField(name);
            return field.getType() == float.class && field.trySetAccessible() ? field : null;
        } catch (ReflectiveOperationException | RuntimeException unavailable) {
            return null;
        }
    }

    private static Float readFloat(Item script, Field field, boolean supported) {
        if (!supported || script == null || field == null) return null;
        try {
            return field.getFloat(script);
        } catch (IllegalAccessException unavailable) {
            return null;
        }
    }

    @LuaMethod(name="toolkitScriptBandagePower", global=true)
    public static Float bandagePower(Item script) { return readBandagePower(script, SUPPORTED); }

    static Float readBandagePower(Item script, boolean supported) {
        return readFloat(script, BANDAGE_POWER, supported);
    }

    @LuaMethod(name="toolkitScriptAlcoholPower", global=true)
    public static Float alcoholPower(Item script) { return readAlcoholPower(script, SUPPORTED); }

    static Float readAlcoholPower(Item script, boolean supported) {
        return readFloat(script, ALCOHOL_POWER, supported);
    }

    @LuaMethod(name="toolkitScriptCanBeEquipped", global=true)
    public static boolean canBeEquipped(Item script) {
        return read(script, SUPPORTED);
    }

    static boolean read(Item script, boolean supported) {
        return supported && script != null && script.canBeEquipped != null;
    }

    @LuaMethod(name="toolkitScriptCanBeWrite", global=true)
    public static Boolean canBeWrite(Item script) {
        return readCanBeWrite(script, SUPPORTED);
    }

    static Boolean readCanBeWrite(Item script, boolean supported) {
        return supported && script != null ? Boolean.valueOf(script.canBeWrite) : null;
    }

    @LuaMethod(name="toolkitScriptHasEatMenu", global=true)
    public static Boolean hasEatMenu(Item script) {
        return readHasEatMenu(script, SUPPORTED);
    }

    static Boolean readHasEatMenu(Item script, boolean supported) {
        if (!supported || script == null) return null;
        return script.customContextMenu == null || "Eat".equals(script.customContextMenu);
    }

    private ScriptItemProperties() {}
}
