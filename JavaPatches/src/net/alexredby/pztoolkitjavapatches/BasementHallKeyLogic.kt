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
                "01b33c6144a3fbb3b5c1b9f388048109181eb3713c74ca2e654ed391a20423a6",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/areas/isoregion/metagrid/WorldRegionToMetaGrid.class",
                "44579db93d88b04291263916ea27dde88c8bd8e07224d27972ee8217c8ef341d",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/LightingJNI.class",
                "4c9103b4d2979520b2ee5ea013f5f62870d2789d777d3a205b4b04f91830b245",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/fboRenderChunk/FBORenderCell.class",
                "d12b00c73914dd6fb96c4bf18b961cc4f811c896691e823e55e79cda3e6b0244",
            )

    private const val HEADER = "media/maps/Muldraugh, KY/41_37.lotheader"
    private const val HEADER_HASH =
        "29cd9faefb134de510242c55cfceb4fb2f54101069deb1dffb8fe906202257cf"
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
                cell.roomList.size <= 106 ||
                cell.roomByMetaId.containsKey(BasementHallKey.HALL_KEY)
        )
            return false
        val original = cell.roomList[106]
        if (
            original === access ||
                !hall(original) ||
                original.building !== receiving ||
                original.id != RoomID.makeID(41, 37, 106) ||
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
            "[PZToolkitJavaPatches] Basement hall key separated: original=106, key=${BasementHallKey.HALL_KEY}, accessKey=${BasementHallKey.ORIGINAL_KEY}",
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
