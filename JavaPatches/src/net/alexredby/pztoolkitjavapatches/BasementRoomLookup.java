package net.alexredby.pztoolkitjavapatches;

import java.util.ArrayList;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.iso.BuildingDef;
import zombie.iso.BuildingID;
import zombie.iso.IsoMetaCell;
import zombie.iso.IsoWorld;
import zombie.iso.RoomDef;

public final class BasementRoomLookup {
    public static final boolean SUPPORTED = BytecodeSupport.supports("zombie/basements/Basements.class",
            "769908ad1fdab2fb667d41943fde29e91b2148d365e5993117601c07c854380c")
        && BytecodeSupport.supports("zombie/iso/BuildingID.class",
            "cfb8cb7815a84b5b6b4dc9743df585bb8d14959acd7c23850a9ec62a084c3ed1")
        && BytecodeSupport.supports("zombie/iso/RoomID.class",
            "d3d5bb425c94b2b6b5f03cd1d47fc82c079984563d4a9e6857c64b3809a2d52d")
        && BytecodeSupport.supports("zombie/iso/BuildingDef.class",
            "b1374ab72a3b7668afb554c22e9a4374841613f028712f3f98bf7a461d10faf1")
        && BytecodeSupport.supports("zombie/iso/RoomDef.class",
            "7cf340ad83010a27bb41a7b576d934c795b3a855118fc683ae80dfa02d8be989")
        && BytecodeSupport.supports("zombie/iso/IsoMetaCell.class",
            "ccf99cd2b176b079da51f31a74ae9408b45255a328f6d1ab6fe536600226cdee")
        && BytecodeSupport.supports("zombie/iso/IsoMetaGrid.class",
            "cdd50bb0a393c766d25c9dcbc5f7e929d7e10a6b9c9b95e22c3bae94b3b5b1f9");

    private BasementRoomLookup() { }

    public static void prepare() {
        if (SUPPORTED) zombie.basements.Basements.class.getName();
    }

    public static final class State {
        private final long buildingID;
        private final ArrayList<RoomDef> rooms = new ArrayList<>();
        private State(long buildingID) { this.buildingID = buildingID; }
    }

    public static State beforeMerge(BuildingDef receiving, boolean supported) {
        if (!supported || receiving == null) return null;
        IsoMetaCell source = IsoWorld.instance.metaGrid.getCellData(BuildingID.getCellX(receiving.id), BuildingID.getCellY(receiving.id));
        if (source == null || !source.buildings.contains(receiving)) return null;
        State state = new State(receiving.id);
        capture(source, receiving.rooms, state);
        capture(source, receiving.emptyoutside, state);
        return state;
    }

    private static void capture(IsoMetaCell source, ArrayList<RoomDef> rooms, State state) {
        for (RoomDef room : rooms) {
            if (!room.userDefined && source.roomByMetaId.get(room.metaId) == room
                && source.rooms.get(room.id) == room && source.roomList.contains(room)) state.rooms.add(room);
        }
    }

    public static int repair(BuildingDef receiving, State previous, boolean supported) {
        if (!supported || receiving == null || previous == null) return 0;
        int cellX = BuildingID.getCellX(receiving.id), cellY = BuildingID.getCellY(receiving.id);
        if (BuildingID.isSameCell(previous.buildingID, cellX, cellY)) return 0;
        IsoMetaCell cell = IsoWorld.instance.metaGrid.getCellData(cellX, cellY);
        if (cell == null || !cell.buildings.contains(receiving)) return 0;
        int corrected = 0;
        for (RoomDef room : previous.rooms) {
            if (room.userDefined || cell.roomByMetaId.containsKey(room.metaId) || cell.rooms.get(room.id) != room
                || !cell.roomList.contains(room) || room.building != receiving
                || (!receiving.rooms.contains(room) && !receiving.emptyoutside.contains(room))) continue;
            int matches = 0;
            for (RoomDef candidate : cell.roomList) if (candidate.metaId == room.metaId) matches++;
            // A missing index cannot determine the owner of colliding persistent IDs.
            if (matches != 1) continue;
            cell.roomByMetaId.put(room.metaId, room);
            corrected++;
        }
        if (corrected > 0) System.out.println("[PZToolkitJavaPatches] Basement room lookup repaired: cell="
            + cellX + "," + cellY + ", corrected=" + corrected);
        return corrected;
    }

    @Patch(className="zombie.basements.Basements", methodName="mergeBuildings", strictMatch=true)
    public static class NativeBasementRoomLookup {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) zombie.iso.BuildingDef incoming,
                                 @Patch.Argument(1) zombie.iso.BuildingDef receiving,
                                 @Patch.Local("toolkitPreviousBuildingID") BasementRoomLookup.State previous) {
            BasementHallKey.beforeMerge(incoming, receiving, BasementHallKey.SUPPORTED);
            previous = BasementRoomLookup.beforeMerge(receiving, BasementRoomLookup.SUPPORTED);
        }

        @Patch.OnExit
        public static void exit(@Patch.Argument(0) zombie.iso.BuildingDef incoming,
                                @Patch.Argument(1) zombie.iso.BuildingDef receiving,
                                @Patch.Local("toolkitPreviousBuildingID") BasementRoomLookup.State previous) {
            BasementRoomLookup.repair(receiving, previous, BasementRoomLookup.SUPPORTED);
        }
    }
}
