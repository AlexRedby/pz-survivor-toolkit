package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import me.zed_0xff.zombie_buddy.Accessor;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.characters.IsoGameCharacter;
import zombie.network.GameClient;

/** Read the authoritative native cooldown without reconstructing its random starting value. */
public final class MedicineCooldown {
    static final boolean SUPPORTED = BytecodeSupport.supports("zombie/characters/IsoGameCharacter.class",
        "29040e19c3e420499f73bc0ea0d5b86d7f7d38655acdc13d0107df736eb54c0b");
    private static final Field TIMER = SUPPORTED
        ? Accessor.findField(IsoGameCharacter.class, "effectiveEdibleBuffTimer") : null;

    @LuaMethod(name="toolkitMedicineCooldown", global=true)
    public static Double cooldown(IsoGameCharacter character) {
        return read(character, SUPPORTED);
    }

    static Double read(IsoGameCharacter character, boolean supported) {
        if (!supported || GameClient.client || character == null || TIMER == null) return null;
        Float value = Accessor.tryGet(character, TIMER, (Float)null);
        return value != null && Float.isFinite(value) && value >= 0 ? value.doubleValue() : null;
    }

    private MedicineCooldown() {}
}
