package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.iso.BuildingDef;
import zombie.iso.RoomDef;

public final class BasementHallKey {
    public static final boolean SUPPORTED = BasementHallKeyLogic.SUPPORTED;

    public static final long ORIGINAL_KEY = 786643L;
    public static final long HALL_KEY = 0x505A0000000C00D3L;
    private BasementHallKey() { }

    public static void prepare() {
        if (SUPPORTED) zombie.iso.RoomDef.class.getName();
    }

    public static boolean beforeMerge(BuildingDef incoming, BuildingDef receiving, boolean supported) {
        return BasementHallKeyLogic.beforeMerge(incoming, receiving, supported);
    }

    public static long calculated(RoomDef room, int cellX, int cellY, long nativeKey, boolean supported) {
        return BasementHallKeyLogic.calculated(room, cellX, cellY, nativeKey, supported);
    }

    @Patch(className="zombie.iso.RoomDef", methodName="calculateMetaID", strictMatch=true)
    public static class NativeBasementHallKey {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.iso.RoomDef room, @Patch.Argument(0) int cellX,
                                @Patch.Argument(1) int cellY, @Patch.Return(readOnly=false) long result) {
            result = BasementHallKey.calculated(room, cellX, cellY, result, BasementHallKey.SUPPORTED);
        }
    }
}
