package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.util.Collections
import java.util.HexFormat
import java.util.WeakHashMap
import zombie.Lua.LuaManager
import zombie.ZomboidFileSystem
import zombie.iso.BuildingDef
import zombie.iso.BuildingID
import zombie.iso.IsoWorld
import zombie.iso.RoomDef
import zombie.iso.RoomID

internal object BasementHallKeyLogic {
    @JvmField
    val SUPPORTED =
        BasementRoomLookup.SUPPORTED &&
            BytecodeSupport.supports(
                "zombie/buildingRooms/BREBuilding.class",
                "77d5710d7b102532e080c556a87439d3d827cf4c8a05fc5cd7e37c90175c83de",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/areas/isoregion/metagrid/WorldRegionToMetaGrid.class",
                "635174f093618dac7ec320b3884780b847d1332d03b3c07b3221f2b899728b20",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/LightingJNI.class",
                "3938fd1336a64403ae52a3a1552fcdff3a3c54f1a0360c6ee35512c2f9b7e5e7",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/fboRenderChunk/FBORenderCell.class",
                "d5c46201d60cff36397ee46c56b53dbaee6e26e8733836f27bf56ad871eedf94",
            )

    private const val HEADER = "media/maps/Muldraugh, KY/41_37.lotheader"
    private const val HEADER_HASH =
        "05cd36a09eb5f0e999b1def16d78dfa6510bee557eca0ef1d3fe209f5b41313e"
    private const val ACCESS = "media/basement_access/ba_exterior_north_westside_13.pzby"
    private const val ACCESS_HASH =
        "706ac77ce0c3d5daa653f1932b8674313340606324f9bffd75fbd194573d5ae3"
    private val separated =
        Collections.synchronizedSet(Collections.newSetFromMap(WeakHashMap<RoomDef, Boolean>()))

    @JvmStatic
    fun beforeMerge(incoming: BuildingDef?, receiving: BuildingDef?, supported: Boolean): Boolean {
        if (
            !supported ||
                incoming == null ||
                receiving == null ||
                incoming === receiving ||
                incoming.isUserDefined() ||
                receiving.isUserDefined() ||
                receiving.id != BuildingID.makeID(41, 37, 16) ||
                incoming.rooms.size != 1 ||
                incoming.emptyoutside.isNotEmpty()
        )
            return false
        val access = incoming.rooms[0]
        if (access.id != 0L || access.building !== incoming || !hall(access)) return false
        val cell = IsoWorld.instance.metaGrid.getCellData(41, 37)
        if (
            cell == null ||
                cell.info == null ||
                receiving !in cell.buildings ||
                cell.roomList.size <= 107 ||
                cell.roomByMetaId.containsKey(BasementHallKey.HALL_KEY)
        )
            return false
        val original = cell.roomList[107]
        if (
            original === access ||
                !hall(original) ||
                original.building !== receiving ||
                original.id != RoomID.makeID(41, 37, 107) ||
                original.metaId != BasementHallKey.ORIGINAL_KEY ||
                original !in receiving.rooms ||
                cell.rooms[original.id] !== original ||
                cell.roomByMetaId.get(BasementHallKey.ORIGINAL_KEY) !== original
        )
            return false
        var originals = 0
        for (room in cell.roomList) {
            if (room.metaId == BasementHallKey.HALL_KEY) return false
            if (room.metaId == BasementHallKey.ORIGINAL_KEY) originals++
        }
        if (originals != 1 || !stockSources()) return false
        // Keep legacy records routed to the access hall, exactly as the native loader did.
        cell.roomByMetaId.remove(BasementHallKey.ORIGINAL_KEY)
        original.metaId = BasementHallKey.HALL_KEY
        cell.roomByMetaId.put(BasementHallKey.HALL_KEY, original)
        separated.add(original)
        println(
            "[PZToolkitJavaPatches] Basement hall key separated: original=107, key=${BasementHallKey.HALL_KEY}, accessKey=${BasementHallKey.ORIGINAL_KEY}",
        )
        return true
    }

    @JvmStatic
    fun calculated(
        room: RoomDef?,
        cellX: Int,
        cellY: Int,
        nativeKey: Long,
        supported: Boolean,
    ): Long {
        if (!supported || room == null || room !in separated) return nativeKey
        val cell =
            IsoWorld.instance.metaGrid.getCellData(cellX, cellY)
                ?: throw IllegalStateException(
                    "Cannot resolve the separated basement hall's destination cell",
                )
        val occupied = cell.roomByMetaId.get(BasementHallKey.HALL_KEY)
        if (cell.roomByMetaId.containsKey(BasementHallKey.HALL_KEY) && occupied !== room) {
            throw IllegalStateException("Refusing to overwrite an occupied basement hall key")
        }
        for (other in cell.roomList) {
            if (other !== room && other.metaId == BasementHallKey.HALL_KEY) {
                throw IllegalStateException("Refusing a duplicate separated basement hall key")
            }
        }
        // Admission is source-guarded; later edits must not silently replace the saved identity.
        return BasementHallKey.HALL_KEY
    }

    private fun hall(room: RoomDef?): Boolean {
        if (
            room == null ||
                room.userDefined ||
                room.name != "hall" ||
                room.level != 0 ||
                room.rects.size != 1 ||
                room.x != 10707 ||
                room.y != 9484 ||
                room.x2 != 10708 ||
                room.y2 != 9488 ||
                room.area != 4
        )
            return false
        val rect = room.rects[0]
        return rect.x == 10707 && rect.y == 9484 && rect.getW() == 1 && rect.getH() == 4
    }

    private fun stockSources(): Boolean {
        val maps = LuaManager.GlobalObject.getLotDirectories()
        if (maps.size != 1 || maps[0] != "Muldraugh, KY") return false
        return try {
            matches(HEADER, HEADER_HASH) && matches(ACCESS, ACCESS_HASH)
        } catch (error: Exception) {
            System.err.println("[PZToolkitJavaPatches] Kept native basement hall key: $error")
            false
        }
    }

    private fun matches(file: String, expected: String): Boolean {
        val bytes = Files.readAllBytes(Path.of(ZomboidFileSystem.instance.getString(file)))
        return expected ==
            HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes))
    }
}
