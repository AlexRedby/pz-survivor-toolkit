package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.iso.IsoGridSquare;

/** Represent a barricaded door as an edge that requires destruction, not merely opening. */
public final class BarricadedDoorPaths {
    public static final boolean SUPPORTED = BarricadedDoorPathSupport.SUPPORTED;

    private BarricadedDoorPaths() { }

    public static void prepare() throws ClassNotFoundException {
        BarricadedDoorPathSupport.prepare();
    }

    public static long correct(IsoGridSquare square, long bits, boolean supported) {
        return BarricadedDoorPathSupport.correct(square, bits, supported);
    }

    @Patch(className="zombie.pathfind.nativeCode.SquareUpdateTask", methodName="getBits", strictMatch=true)
    public static class NativeDoorEdges {
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) IsoGridSquare square, @Patch.Return(readOnly=false) long bits) {
            bits = correct(square, bits, SUPPORTED);
        }
    }

    @Patch(className="zombie.pathfind.SquareUpdateTask", methodName="getBits", strictMatch=true)
    public static class JavaDoorEdges {
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) IsoGridSquare square, @Patch.Return(readOnly=false) int bits) {
            bits = (int)correct(square, bits, SUPPORTED);
        }
    }
}
