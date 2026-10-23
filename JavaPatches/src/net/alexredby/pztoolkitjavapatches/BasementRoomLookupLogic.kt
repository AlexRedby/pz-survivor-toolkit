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
            "769908ad1fdab2fb667d41943fde29e91b2148d365e5993117601c07c854380c",
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
                "b1374ab72a3b7668afb554c22e9a4374841613f028712f3f98bf7a461d10faf1",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/RoomDef.class",
                "7cf340ad83010a27bb41a7b576d934c795b3a855118fc683ae80dfa02d8be989",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/IsoMetaCell.class",
                "ccf99cd2b176b079da51f31a74ae9408b45255a328f6d1ab6fe536600226cdee",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/IsoMetaGrid.class",
                "cdd50bb0a393c766d25c9dcbc5f7e929d7e10a6b9c9b95e22c3bae94b3b5b1f9",
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
