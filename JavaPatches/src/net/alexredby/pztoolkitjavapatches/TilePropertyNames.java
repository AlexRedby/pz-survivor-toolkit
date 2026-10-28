package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.properties.IsoPropertyType;

@Patch(className="zombie.core.properties.IsoPropertyType", methodName="lookupOrDefaultStr", warmUp=true, strictMatch=true)
public final class TilePropertyNames {
    public static final boolean SUPPORTED = TilePropertyNamesLogic.SUPPORTED;

    private TilePropertyNames() { }

    public static void prepare() {
        if (SUPPORTED) IsoPropertyType.values();
    }

    public static boolean accepts(String name, boolean supported) {
        return TilePropertyNamesLogic.accepts(name, supported);
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
