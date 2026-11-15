package net.alexredby.pztoolkitjavapatches

import zombie.iso.BuildingDef
import zombie.iso.BuildingID
import zombie.iso.IsoMetaCell
import zombie.iso.IsoWorld
import zombie.iso.RoomDef

internal object BasementRoomLookupLogic {
    @JvmField
    val SUPPORTED =
        BytecodeSupport.supports(
            "zombie/basements/Basements.class",
            "295eebbd0c3361e6a92ca88dd5bd29727e875c4ae5e695d299b4ace0bf0d6773",
        ) &&
            BytecodeSupport.supports(
                "zombie/iso/BuildingID.class",
                "cfb8cb7815a84b5b6b4dc9743df585bb8d14959acd7c23850a9ec62a084c3ed1",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/RoomID.class",
                "d3d5bb425c94b2b6b5f03cd1d47fc82c079984563d4a9e6857c64b3809a2d52d",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/BuildingDef.class",
                "ee61c80790240e8a68ffb25bd368eb5651e6ef73c96818a8c75cfa86fc11f754",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/RoomDef.class",
                "762102d5004dace11705eee8b346291d239a824d6fced5d0890391ef02dd9b72",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/IsoMetaCell.class",
                "27304239cf39ecb4d7e70951c6bfbc0f42f7ffd425fc2252ed98632d9e1fb750",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/IsoMetaGrid.class",
                "1e8b016090a41b1388f6eb06c3b63aed8e866416ad15479f0cabe76967dbf824",
            )

    class Snapshot(val buildingID: Long) {
        val rooms = ArrayList<RoomDef>()
    }

    @JvmStatic
    fun beforeMerge(receiving: BuildingDef?, supported: Boolean): Snapshot? {
        if (!supported || receiving == null) return null
        val source =
            IsoWorld.instance.metaGrid.getCellData(
                BuildingID.getCellX(receiving.id),
                BuildingID.getCellY(receiving.id),
            )
        if (source == null || receiving !in source.buildings) return null
        return Snapshot(receiving.id).apply {
            capture(source, receiving.rooms, this)
            capture(source, receiving.emptyoutside, this)
        }
    }

    private fun capture(source: IsoMetaCell, rooms: ArrayList<RoomDef>, snapshot: Snapshot) {
        for (room in rooms) {
            if (
                !room.userDefined &&
                    source.roomByMetaId.get(room.metaId) === room &&
                    source.rooms[room.id] === room &&
                    room in source.roomList
            )
                snapshot.rooms.add(room)
        }
    }

    @JvmStatic
    fun repair(receiving: BuildingDef?, previous: Snapshot?, supported: Boolean): Int {
        if (!supported || receiving == null || previous == null) return 0
        val cellX = BuildingID.getCellX(receiving.id)
        val cellY = BuildingID.getCellY(receiving.id)
        if (BuildingID.isSameCell(previous.buildingID, cellX, cellY)) return 0
        val cell = IsoWorld.instance.metaGrid.getCellData(cellX, cellY)
        if (cell == null || receiving !in cell.buildings) return 0
        var corrected = 0
        for (room in previous.rooms) {
            if (
                room.userDefined ||
                    cell.roomByMetaId.containsKey(room.metaId) ||
                    cell.rooms[room.id] !== room ||
                    room !in cell.roomList ||
                    room.building !== receiving ||
                    (room !in receiving.rooms && room !in receiving.emptyoutside)
            )
                continue
            // A missing index cannot determine the owner of colliding persistent IDs.
            if (cell.roomList.count { it.metaId == room.metaId } != 1) continue
            cell.roomByMetaId.put(room.metaId, room)
            corrected++
        }
        if (corrected > 0)
            println(
                "[PZToolkitJavaPatches] Basement room lookup repaired: cell=$cellX,$cellY, corrected=$corrected",
            )
        return corrected
    }
}
