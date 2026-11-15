package net.alexredby.pztoolkitjavapatches

import java.util.ArrayList
import zombie.iso.IsoGridSquare
import zombie.iso.objects.IsoDoor
import zombie.iso.objects.IsoThumpable
import zombie.iso.objects.IsoBarricade
import zombie.iso.IsoObject
import zombie.iso.IsoWorld
import zombie.iso.IsoCell
import zombie.network.GameServer
import zombie.network.ServerMap
import zombie.characters.IsoPlayer

/** Represent a barricaded door as an edge that requires destruction, not merely opening. */
object BarricadedDoorPathSupport {
    @JvmField
    val SUPPORTED = arrayOf(
        "zombie/pathfind/nativeCode/SquareUpdateTask.class" to "b7df3bfb79f2cb2d800c84565fe21f1e1f7696bcbbdff6a7d10975085105d72c",
        "zombie/pathfind/SquareUpdateTask.class" to "33e9689dfb33c9762f7a77d7cb0f8c17eca9f180e95eb6ff70b4568527f501fa",
        "zombie/iso/objects/IsoDoor.class" to "07bd820e06017aa831aa18706cf0f3af00cab0f046d804e4711e517e9c8d9019",
        "zombie/iso/objects/IsoThumpable.class" to "61893a53f89547abf25dd8459aaf1fb43051bee39866f578f3aee7f074e6c47d",
        "zombie/iso/IsoGridSquare.class" to "b8cef32a10bb76433bad174397b51f1a046be1eef47997dc1e79dd8547d726c5",
        "zombie/iso/IsoObject.class" to "7a99d06875c19ff132940d7192b414496537076e83474db0abc0cb38de6be70a",
        "zombie/iso/objects/IsoBarricade.class" to "ec42e234375fc3bfa2c8548ff284416c0235304a05bee967a37a5690110ac972",
        "zombie/iso/objects/interfaces/GridSquareEdgeElement.class" to "3cb116b623c2115e4fe80698e34e3aa366c403c36428527fbd38d0cb91fcf9d6",
        "zombie/iso/objects/GridSquareEdgeFacingDirection.class" to "e4b51f30b99d9e6edecf9a5e23ca376a0ea933c92d48fb12e490402ee0bfa5d5",
        "zombie/iso/IsoGridSquare\$1.class" to "ade21832b90dfb0d6623bb81f6506dc92b5577682569bc2aee83ea9805170992",
        "zombie/iso/IsoDirections.class" to "5108ccc19404dcb76320fc019ae8f48831bd72e88f9afc910ae0c79a58cd769f",
        "zombie/iso/IsoWorld.class" to "e17f9d3266154e7715237656612832123a9032e7bb9ff73ae7a29ecdf73374df",
        "zombie/iso/IsoCell.class" to "6c261778f1fac0c660ba8b6167b9bf5d318e8bd126378e3c1b3667c9469910ab",
        "zombie/iso/IsoChunkMap.class" to "7a64d736a95ba700afd2916ad7a93875ce39ce9390f7b1ea14197d1e90db49e4",
        "zombie/iso/IsoChunk.class" to "b069a07b79dc86d2a1133dff187fdcde904e1fe9a9d2f066b877b9ea0ea31af8",
        "zombie/network/ServerMap.class" to "a02741574b7fb941a9a63bbdd1b3c35a9ad414cabefcb17d9fd3ea16196df654",
        "zombie/network/ServerMap\$ServerCell.class" to "a8315d2d503b357a23733061ea24d44e3ac38abc1fb45dc28e359354a9d0054d",
        "zombie/iso/IsoMetaGrid.class" to "1e8b016090a41b1388f6eb06c3b63aed8e866416ad15479f0cabe76967dbf824",
        "zombie/core/math/PZMath.class" to "1108e80daab0ccb6ca30f4ac16f70daca508a7271604b73af0f88895adab3fb1",
    ).all { (path, hash) -> BytecodeSupport.supports(path, hash) }

    private const val THUMP_W = 32768L
    private const val THUMP_N = 65536L
    private const val MAX_OBJECTS = 256

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
        return try {
            val objects = safeObjects(square) ?: return bits
            if (!safeBarricades(objects)) return bits
            var corrected = bits
            for (index in objects.indices) {
                val obj = objects[index]
                // Exact native classes precede every virtual getter. Foreign subclasses
                // retain native bits without receiving an extra callback from this hook.
                if (obj?.javaClass == IsoDoor::class.java) {
                    val door = obj as IsoDoor
                    if (door.getSquare() === square && !door.isOpen() &&
                        safeOpposite() && safeBarricades(safeObjects(door.getOppositeSquare())) && door.isBarricaded()) {
                        corrected = corrected or if (door.getNorth()) THUMP_N else THUMP_W
                    }
                } else if (obj?.javaClass == IsoThumpable::class.java) {
                    val door = obj as IsoThumpable
                    if (door.getSquare() === square && door.isDoor() && !door.IsOpen() &&
                        safeOpposite() && safeBarricades(safeObjects(door.getOppositeSquare())) && door.isBarricaded()) {
                        corrected = corrected or if (door.getNorth()) THUMP_N else THUMP_W
                    }
                }
            }
            corrected
        } catch (_: RuntimeException) { bits }
    }

    private fun safeObjects(square: IsoGridSquare?): List<*>? {
        if (square == null) return emptyList<Any>() // Native barricade lookup accepts an absent opposite square.
        if (square.javaClass != IsoGridSquare::class.java) return null
        val values = square.getSpecialObjects() ?: return null
        if (values.javaClass != ArrayList::class.java || values.size > MAX_OBJECTS) return null
        return values
    }

    private fun safeBarricades(values: List<*>?): Boolean = values != null && values.all {
        it == null || it is IsoObject && (it !is IsoBarricade || it.javaClass == IsoBarricade::class.java)
    }

    // The client lookup traverses final native cell/chunk classes. Host/server
    // lookup instead enters extensible ServerMap, whose class must be checked
    // before its first virtual call. Its remaining path reads final metadata,
    // ServerCell/chunk arrays and bounded square coordinates without callbacks.
    private fun safeOpposite(): Boolean = IsoWorld.instance?.javaClass == IsoWorld::class.java &&
        IsoWorld.instance.currentCell?.javaClass == IsoCell::class.java &&
        (if (GameServer.server) ServerMap.instance?.javaClass == ServerMap::class.java
            else IsoPlayer.numPlayers in 1..4)
}
