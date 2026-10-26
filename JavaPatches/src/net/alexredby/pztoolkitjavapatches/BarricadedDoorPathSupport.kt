package net.alexredby.pztoolkitjavapatches

import zombie.iso.IsoGridSquare
import zombie.iso.objects.IsoDoor
import zombie.iso.objects.IsoThumpable

/** Represent a barricaded door as an edge that requires destruction, not merely opening. */
object BarricadedDoorPathSupport {
    @JvmField
    val SUPPORTED =
        BytecodeSupport.supports(
            "zombie/pathfind/nativeCode/SquareUpdateTask.class",
            "fb35c89b56fbf7149798d3fbbf8d0ca5882ac7a10b80dfa55b0beb82596ece55",
        ) &&
            BytecodeSupport.supports(
                "zombie/pathfind/SquareUpdateTask.class",
                "abdc3722bd2bf8163d1d2fca25a99a6c8e47d9900c9ee41abbb5dc055329c270",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/objects/IsoDoor.class",
                "024bb36ef8a724c374ebf941b2dbf6ef3ccac4c0269ab2b8c55581a74689d929",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/objects/IsoThumpable.class",
                "cc19adbef73edbda83a56fdb727b70210278e6e4bd3c2c1def881dab804f8323",
            )

    private const val THUMP_W = 32768L
    private const val THUMP_N = 65536L

    @JvmStatic
    @Throws(ClassNotFoundException::class)
    fun prepare() {
        if (!SUPPORTED) return
        Class.forName(
            "zombie.pathfind.nativeCode.SquareUpdateTask",
            false,
            BarricadedDoorPaths::class.java.classLoader,
        )
        Class.forName(
            "zombie.pathfind.SquareUpdateTask",
            false,
            BarricadedDoorPaths::class.java.classLoader,
        )
    }

    @JvmStatic
    fun correct(square: IsoGridSquare?, bits: Long, supported: Boolean): Long {
        if (!supported || square == null) return bits
        var corrected = bits
        for (obj in square.getSpecialObjects()) {
            if (obj is IsoDoor && !obj.isOpen() && obj.isBarricaded()) {
                corrected = corrected or if (obj.getNorth()) THUMP_N else THUMP_W
            } else if (obj is IsoThumpable && obj.isDoor() && !obj.IsOpen() && obj.isBarricaded()) {
                corrected = corrected or if (obj.getNorth()) THUMP_N else THUMP_W
            }
        }
        return corrected
    }
}
