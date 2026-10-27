package net.alexredby.pztoolkitjavapatches;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.scripting.objects.Item;

/** Read native item-script properties without creating an inventory item. */
public final class ScriptItemProperties {
    static final boolean SUPPORTED = BytecodeSupport.supports("zombie/scripting/objects/Item.class",
        "9e6a2f7fe48cc66843fea06b4821063d7cc6a73eaba0de8ee51d0a15c373202e");

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

    private ScriptItemProperties() {}
}
