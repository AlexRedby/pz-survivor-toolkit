package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.vm.KahluaTable;
import zombie.iso.IsoMetaGrid;
import zombie.iso.zones.Zone;

/** Java entry points retain the state monitor and advice-local write-back. */
public final class MannequinZoneData {
    public static final boolean SUPPORTED = MannequinZoneDataLogic.SUPPORTED;

    private MannequinZoneData() { }

    public static void prepare() { MannequinZoneDataLogic.prepare(); }

    public static synchronized void loaded(String file, Object previousObjects, boolean supported) {
        MannequinZoneDataLogic.loaded(file, previousObjects, supported);
    }

    public static synchronized void registered(IsoMetaGrid grid, KahluaTable properties, Zone result) {
        MannequinZoneDataLogic.registered(grid, properties, result);
    }

    @Patch(className="zombie.Lua.LuaManager", methodName="RunLua", strictMatch=true)
    public static class NativeMannequinZoneData {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) String file, @Patch.Argument(1) boolean rewrite,
                                 @Patch.Local("toolkitPreviousObjects") Object previous) {
            previous = MannequinZoneDataLogic.previous(file, MannequinZoneData.SUPPORTED);
        }

        @Patch.OnExit
        public static void exit(@Patch.Argument(0) String file, @Patch.Argument(1) boolean rewrite,
                                @Patch.Local("toolkitPreviousObjects") Object previous) {
            MannequinZoneData.loaded(file, previous, MannequinZoneData.SUPPORTED);
        }
    }

    @Patch(className="zombie.iso.IsoMetaGrid", methodName="registerMannequinZone", strictMatch=true)
    public static class NativeMannequinZonePriority {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.iso.IsoMetaGrid grid,
                                @Patch.Argument(0) String name, @Patch.Argument(1) String type,
                                @Patch.Argument(2) int x, @Patch.Argument(3) int y, @Patch.Argument(4) int z,
                                @Patch.Argument(5) int width, @Patch.Argument(6) int height,
                                @Patch.Argument(7) se.krka.kahlua.vm.KahluaTable properties,
                                @Patch.Return zombie.iso.zones.Zone zone) {
            MannequinZoneData.registered(grid, properties, zone);
        }
    }
}
