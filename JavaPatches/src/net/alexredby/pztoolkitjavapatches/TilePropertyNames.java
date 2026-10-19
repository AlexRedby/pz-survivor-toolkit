package net.alexredby.pztoolkitjavapatches;

import java.util.Map;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.properties.IsoPropertyType;

@Patch(className="zombie.core.properties.IsoPropertyType", methodName="lookupOrDefaultStr", warmUp=true, strictMatch=true)
public final class TilePropertyNames {
    public static final boolean SUPPORTED = BytecodeSupport.supports("zombie/core/properties/IsoPropertyType.class",
        "7e7deb55cc8a949a4cab6cf93e0cabef01090229154203730f758526c948ebd3")
        && BytecodeSupport.supports("zombie/core/TilePropertyAliasMap.class",
            "05124f3536bc2026fb29d5f7369dc0d809d1a725477d4733a1e0e827911a0a80");

    private TilePropertyNames() { }

    public static void prepare() {
        if (SUPPORTED) IsoPropertyType.values();
    }

    public static boolean accepts(String name, boolean supported) {
        if (!supported || name == null || !(name.equals("ladderW") || name.equals("ladderN")
            || name.equals("ladderE") || name.equals("ladderS") || name.equals("WindowShape"))) return false;
        var types = Accessor.tryGet(IsoPropertyType.class, "BY_NAME", (Map<?, ?>)null);
        // Preserve typed aliases installed by another mod, and fail closed if access fails.
        return types != null && types.get(name) == null;
    }

    @Patch.OnEnter(skipOn=true)
    public static boolean enter(@Patch.Argument(0) String name,
                                @Patch.Local("toolkitStringProperty") String fallback) {
        if (!accepts(name, TilePropertyNames.SUPPORTED)) return false;
        // Shipped tile definitions use these string properties without enum entries.
        fallback = name;
        return true;
    }

    @Patch.OnExit
    public static void exit(@Patch.Local("toolkitStringProperty") String fallback,
                            @Patch.Return(readOnly=false) String result) {
        if (fallback != null) result = fallback;
    }
}
