package net.alexredby.pztoolkitjavapatches;

import java.util.ArrayList;
import zombie.iso.BuildingDef;
import zombie.iso.BuildingID;
import zombie.iso.IsoMetaCell;
import zombie.iso.IsoWorld;
import zombie.iso.RoomDef;

public final class BasementRoomLookup {
    private BasementRoomLookup() { }

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
}
