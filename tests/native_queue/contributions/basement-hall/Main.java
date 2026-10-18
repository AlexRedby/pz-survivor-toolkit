package net.alexredby.basementhallfixture;

import java.nio.file.Path;
import java.util.ArrayList;
import java.util.IdentityHashMap;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.GameWindow;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;
import zombie.iso.*;
import zombie.network.GameClient;
import zombie.network.GameServer;

/** Disposable live diagnostics only; no repair or room-state mutation. */
public final class Main {
    private static final long OLD_KEY = 786643L, NEW_KEY = 0x505A0000000C00D3L;
    private static final IdentityHashMap<RoomDef, Long> ids = new IdentityHashMap<>();
    private static final IdentityHashMap<RoomDef, BuildingDef> owners = new IdentityHashMap<>();
    private static ArrayList<RoomDef> layout;

    private static void require(boolean ok, String message) {
        if (!ok) throw new IllegalStateException(message);
    }

    private static void disposable() {
        String cache = System.getenv("PZ_BASEMENT_HALL_CACHE");
        require(cache != null && Path.of(cache).isAbsolute()
            && Path.of(cache).normalize().equals(Path.of(ZomboidFileSystem.instance.getCacheDir()).toAbsolutePath().normalize()),
            "Disposable runner cache required");
        require(!GameClient.client && !GameServer.server && "QueueBasementHall".equals(IsoWorld.instance.getWorld()),
            "Disposable single-player QueueBasementHall world required");
    }

    private static boolean hall(RoomDef room) {
        if (room.userDefined || room.level != 0 || !"hall".equals(room.name) || room.rects.size() != 1) return false;
        var rect = room.rects.get(0);
        return rect.x == 10707 && rect.y == 9484 && rect.w == 1 && rect.h == 4;
    }

    @LuaMethod(name="basementHallProbe", global=true)
    public static String probe(String phase, boolean nativeControl) {
        disposable();
        var grid = IsoWorld.instance.metaGrid;
        var cell = grid.getCellData(41, 37);
        require(cell != null && cell.roomList.size() > 107, "Target stock cell is not loaded");
        RoomDef base = cell.roomList.get(107), access = null;
        require(hall(base) && base.metaId == (nativeControl ? OLD_KEY : NEW_KEY),
            "Original hall persistent key differs from the selected candidate/control");
        for (RoomDef room : cell.roomList) if (room != base && hall(room)) {
            require(access == null, "More than two target hall definitions"); access = room;
        }
        require(access != null && access.metaId == OLD_KEY && access.building == base.building,
            "Access hall key or original building owner differs");
        require(base.building == cell.buildings.get(16) && BuildingID.getIndex(base.building.id) == 16,
            "Original stock building owner changed");
        require((nativeControl ? !cell.roomByMetaId.containsKey(NEW_KEY) : cell.roomByMetaId.get(NEW_KEY) == base)
            && cell.roomByMetaId.get(OLD_KEY) == access,
            "Persistent lookup points at a different room");
        for (int index = 0; index < cell.roomList.size(); index++) {
            RoomDef room = cell.roomList.get(index);
            require(room.id == RoomID.makeID(41, 37, index) && cell.rooms.get(room.id) == room
                && grid.getRoomDefByID(room.id) == room, "Native room index/ID mismatch at " + index);
            if (layout != null) require(ids.get(room) != null && ids.get(room) == room.id
                && owners.get(room) == room.building, "Room identity/owner changed during traversal");
        }
        if (layout == null) {
            layout = new ArrayList<>(cell.roomList);
            for (RoomDef room : layout) { ids.put(room, room.id); owners.put(room, room.building); }
        } else require(layout.equals(cell.roomList), "Room layout changed during traversal");
        var player = IsoPlayer.getInstance();
        var square = player.getSquare();
        require(phase.equals("surface") || phase.equals("basement") || phase.equals("returned"), "Unknown probe phase");
        require(square != null, "Actual player square is missing");
        require(square.getRoom() != null && square.getRoom().def != null, "Actual player square has no native room lookup");
        var actual = square.getRoom().def;
        require(grid.getRoomDefByID(square.getRoomID()) == actual, "Loaded square/runtime room lookup differs");
        require(square.getZ() == (phase.equals("basement") ? -1 : 0), "Player did not traverse to expected floor");
        require(phase.equals("basement") || actual == base || actual == access, "Player is outside the target hall");
        if (phase.equals("basement")) {
            BuildingDef basement = null;
            for (int y = 9485; y <= 9487; y++) {
                var stair = IsoWorld.instance.currentCell.getGridSquare(10707, y, -1);
                if (stair != null && stair.HasStairs() && stair.getRoomDef() != null) {
                    basement = stair.getRoomDef().building;
                    if (basement != null) break;
                }
            }
            require(basement != null && actual.building == basement,
                "Actual underground room does not belong to the access staircase's basement");
        }
        require(square.getCanSee(0), "Player's actual square is not visible after the render settling interval");
        return "{\"phase\":\"" + phase + "\",\"baseIndex\":107,\"accessIndex\":" + RoomID.getIndex(access.id)
            + ",\"baseKey\":\"" + Long.toHexString(base.metaId) + "\",\"accessKey\":\"" + Long.toHexString(access.metaId)
            + "\",\"ownerIndex\":16,\"stable\":true,\"x\":" + square.getX() + ",\"y\":" + square.getY()
            + ",\"z\":" + square.getZ() + ",\"squareRoomIndex\":" + RoomID.getIndex(actual.id)
            + ",\"canSee\":" + square.getCanSee(0) + ",\"nativeControl\":" + nativeControl + "}";
    }

    @LuaMethod(name="basementHallSave", global=true)
    public static void save() throws Exception {
        disposable();
        GameWindow.save(false);
    }

    public static void main(String[] args) { System.out.println("[BASEMENT_HALL] HELPER_READY"); }
}
