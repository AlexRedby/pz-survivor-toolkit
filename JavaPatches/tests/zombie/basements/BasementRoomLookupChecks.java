package zombie.basements;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.BufferUnderflowException;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import me.zed_0xff.zombie_buddy.PatchEngine;
import net.alexredby.pztoolkitjavapatches.BasementRoomLookup;
import net.alexredby.pztoolkitjavapatches.Main;
import zombie.iso.*;
import zombie.iso.areas.IsoBuilding;
import zombie.iso.areas.IsoRoom;

public final class BasementRoomLookupChecks {
    static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    static void field(Object object, String name, Object value) throws Exception {
        Field field = object.getClass().getDeclaredField(name); field.setAccessible(true); field.set(object, value);
    }
    static RoomDef room(int index, String name, int z, int[]... rectangles) {
        var room = new RoomDef(RoomID.makeID(25, 34, index), name); room.level = z;
        for (int[] rect : rectangles) room.rects.add(new RoomDef.RoomRect(rect[0], rect[1], rect[2], rect[3]));
        room.CalculateBounds(); room.metaId = room.calculateMetaID(25, 34);
        return room;
    }
    static void flags(RoomDef room, int flags) {
        room.setExplored((flags & 1) != 0); room.lightsActive = (flags & 2) != 0;
        room.doneSpawn = (flags & 4) != 0; room.setRoofFixed((flags & 8) != 0);
    }
    static int flags(RoomDef room) {
        return (room.explored ? 1 : 0) | (room.lightsActive ? 2 : 0)
            | (room.doneSpawn ? 4 : 0) | (room.isRoofFixed() ? 8 : 0);
    }
    static ByteBuffer save(IsoMetaGrid grid) {
        ByteBuffer bytes = ByteBuffer.allocate(4096); grid.savePart(bytes, 0, false); bytes.flip(); return bytes;
    }
    static void loadRoomSection(IsoMetaGrid grid, ByteBuffer bytes) {
        int count = bytes.getInt(24); bytes.position(0); bytes.limit(28 + count * 10);
        try { grid.load(bytes); throw new AssertionError("room section did not end at building count"); }
        catch (BufferUnderflowException expected) {
            require(bytes.position() == bytes.limit(), "unexpected native load boundary");
        }
    }
    static final class Fixture {
        final IsoMetaGrid grid = IsoWorld.instance.metaGrid;
        final IsoMetaCell destination = new IsoMetaCell(25, 33), source = new IsoMetaCell(25, 34);
        final BuildingDef receiving = new BuildingDef(), incoming = new BuildingDef();
        final long previousID = BuildingID.makeID(25, 34, 4);
        final BasementRoomLookup.State previous;
        final ArrayList<RoomDef> moved = new ArrayList<>();
        Fixture(boolean outside) throws Exception { this(outside, -1); }
        Fixture(boolean outside, int missingSourceIndex) throws Exception { this(outside, missingSourceIndex, false); }
        Fixture(boolean outside, int missingSourceIndex, boolean woven) throws Exception {
            grid.minX = grid.maxX = 25; grid.minY = 33; grid.maxY = 34;
            destination.info = new LotHeader(25, 33); source.info = new LotHeader(25, 34);
            field(grid, "grid", new IsoMetaCell[][]{{destination, source}}); field(grid, "width", 1); field(grid, "height", 2);
            RoomDef prefix = room(0, "other-basement", -2, new int[]{6600,8500,2,2});
            prefix.id = RoomID.makeID(25, 33, 0); prefix.metaId = prefix.calculateMetaID(25, 33);
            destination.roomList.add(prefix); destination.rooms.put(prefix.id, prefix); destination.roomByMetaId.put(prefix.metaId, prefix);
            receiving.id = previousID;
            moved.add(room(8, "livingroom", 0, new int[]{6631,8704,7,3}, new int[]{6631,8707,9,2},
                new int[]{6636,8709,4,3}, new int[]{6634,8712,5,2}));
            moved.add(room(9, "bathroom", 0, new int[]{6634,8709,2,3}));
            moved.add(room(10, "bedroom", 0, new int[]{6631,8709,3,4}));
            moved.add(room(11, "bedroom", 0, new int[]{6634,8714,5,3}));
            receiving.rooms.addAll(moved);
            if (outside) { RoomDef extra = room(12, "emptyoutside", 0, new int[]{6640,8704,1,1});
                receiving.emptyoutside.add(extra); moved.add(extra); }
            for (RoomDef room : moved) room.building = receiving;
            receiving.CalculateBounds(new ArrayList<>()); receiving.metaId = receiving.calculateMetaID(25, 34);
            source.buildings.add(receiving); source.buildingByMetaId.put(receiving.metaId, receiving);
            for (RoomDef room : moved) {
                source.roomList.add(room); source.rooms.put(room.id, room); source.roomByMetaId.put(room.metaId, room);
            }
            if (missingSourceIndex >= 0) source.roomByMetaId.remove(moved.get(missingSourceIndex).metaId);
            previous = BasementRoomLookup.beforeMerge(receiving, true);
            RoomDef basement = room(0, "hunterstorage", -1, new int[]{6632,8703,7,5}, new int[]{6632,8708,6,6});
            basement.building = incoming; incoming.rooms.add(basement); incoming.CalculateBounds(new ArrayList<>());
            Method merge = Basements.class.getDeclaredMethod("mergeBuildings", BuildingDef.class, BuildingDef.class);
            merge.setAccessible(true); merge.invoke(new Basements(), incoming, receiving);
            require(BuildingID.getCellY(receiving.id) == 33, "native building did not cross cell boundary");
            for (RoomDef room : moved) require(destination.roomList.contains(room) && destination.rooms.get(room.id) == room
                && (woven && moved.indexOf(room) != missingSourceIndex ? destination.roomByMetaId.get(room.metaId) == room
                    : !destination.roomByMetaId.containsKey(room.metaId)) && !source.roomList.contains(room)
                && !source.roomByMetaId.containsKey(room.metaId), "native cross-cell omission not reproduced");
            require(destination.roomByMetaId.get(basement.metaId) == basement, "native incoming room index changed");
            require(moved.get(0).metaId == 231 && moved.get(1).metaId == 327914 && moved.get(2).metaId == 327911
                && moved.get(3).metaId == 655594, "actual header room IDs changed");
        }
    }
    static void roundTrips() throws Exception {
        for (int state = 0; state < 16; state++) {
            var fixture = new Fixture(false); var cell = fixture.destination;
            for (int i = 0; i < fixture.moved.size(); i++) flags(fixture.moved.get(i), state ^ i);
            var beforeSave = save(fixture.grid); var roomList = new ArrayList<>(cell.roomList);
            long[] allRoomIDs = cell.roomList.stream().mapToLong(room -> room.id).toArray();
            var runtimeRooms = new HashMap<>(cell.rooms); var buildings = new ArrayList<>(cell.buildings);
            var buildingIndex = new gnu.trove.map.hash.TLongObjectHashMap<>(cell.buildingByMetaId);
            var cachedRoom = new IsoRoom(); cachedRoom.def = fixture.moved.get(0);
            cell.isoRooms.put(cachedRoom.def.id, cachedRoom);
            var cachedBuilding = new IsoBuilding(); cachedBuilding.def = fixture.receiving;
            cell.isoBuildings.put(fixture.receiving.id, cachedBuilding);
            var roomCache = new HashMap<>(cell.isoRooms); var buildingCache = new HashMap<>(cell.isoBuildings);
            var chunk = new IsoChunk((IsoCell)null);
            for (RoomDef room : fixture.moved) chunk.addSpawnedRoom(room.id);
            long[] roomIDs = fixture.moved.stream().mapToLong(room -> room.id).toArray();
            var roomState = new ArrayList<>();
            for (RoomDef room : fixture.moved) roomState.add(List.of(room.metaId, room.name, room.level, room.x, room.y,
                room.x2, room.y2, room.area, room.building, new ArrayList<>(room.rects), new ArrayList<>(room.objects), flags(room)));
            require(BasementRoomLookup.repair(fixture.receiving, fixture.previous, true) == 4, "wrong repair count");
            require(cell.roomList.equals(roomList) && cell.rooms.equals(runtimeRooms) && cell.buildings.equals(buildings)
                && cell.buildingByMetaId.equals(buildingIndex) && cell.isoRooms.equals(roomCache)
                && cell.isoBuildings.equals(buildingCache), "repair changed native layout/IDs/caches");
            require(java.util.Arrays.equals(allRoomIDs, cell.roomList.stream().mapToLong(room -> room.id).toArray()),
                "repair shifted another room's runtime ID");
            for (int i = 0; i < fixture.moved.size(); i++) {
                RoomDef room = fixture.moved.get(i);
                require(room.id == roomIDs[i] && chunk.isSpawnedRoom(room.id), "repair invalidated native spawn receipt");
                require(roomState.get(i).equals(List.of(room.metaId, room.name, room.level, room.x, room.y,
                    room.x2, room.y2, room.area, room.building, new ArrayList<>(room.rects), new ArrayList<>(room.objects), flags(room))),
                    "repair changed room metadata/state");
                require(cell.roomByMetaId.get(room.metaId) == room, "moved room not indexed");
            }
            require(beforeSave.equals(save(fixture.grid)), "repair changed serialized bytes");
            require(BasementRoomLookup.repair(fixture.receiving, fixture.previous, true) == 0, "repair not idempotent");
            for (RoomDef room : fixture.moved) flags(room, 0);
            loadRoomSection(fixture.grid, beforeSave);
            for (int i = 0; i < fixture.moved.size(); i++) require(flags(fixture.moved.get(i)) == (state ^ i),
                "native old-format room flags not restored");
        }
    }
    static void guards() throws Exception {
        var fixture = new Fixture(false); var cell = fixture.destination;
        require(BasementRoomLookup.repair(fixture.receiving, fixture.previous, false) == 0 && cell.roomByMetaId.size() == 2,
            "unsupported native bytecode modified");
        require(BasementRoomLookup.beforeMerge(fixture.receiving, false) == null, "unsupported snapshot created");
        require(BasementRoomLookup.repair(fixture.receiving, BasementRoomLookup.beforeMerge(fixture.receiving, true), true) == 0
            && cell.roomByMetaId.size() == 2,
            "same-cell missing index modified");
        RoomDef collision = room(90, "hall", 0, new int[]{6631,8704,1,1}); collision.metaId = fixture.moved.get(0).metaId;
        cell.roomList.add(collision); cell.rooms.put(collision.id, collision);
        flags(fixture.moved.get(0), 1); flags(collision, 14);
        RoomDef existing = room(91, "custom", 0, new int[]{6640,8704,1,1});
        cell.roomByMetaId.put(fixture.moved.get(1).metaId, existing);
        cell.roomList.remove(fixture.moved.get(2));
        cell.rooms.put(fixture.moved.get(3).id, existing);
        var beforeIndex = new gnu.trove.map.hash.TLongObjectHashMap<>(cell.roomByMetaId);
        require(BasementRoomLookup.repair(fixture.receiving, fixture.previous, true) == 0
            && cell.roomByMetaId.equals(beforeIndex) && flags(fixture.moved.get(0)) == 1 && flags(collision) == 14,
            "ambiguous/existing/mismatched room was assigned or flags merged");
        fixture = new Fixture(false);
        for (RoomDef room : fixture.moved) room.userDefined = true;
        require(BasementRoomLookup.repair(fixture.receiving, fixture.previous, true) == 0
            && fixture.destination.roomByMetaId.size() == 2, "custom user-defined room modified");
        fixture = new Fixture(false, 0);
        require(BasementRoomLookup.repair(fixture.receiving, fixture.previous, true) == 3
            && !fixture.destination.roomByMetaId.containsKey(fixture.moved.get(0).metaId), "prior missing source index created");
        fixture = new Fixture(true);
        require(BasementRoomLookup.repair(fixture.receiving, fixture.previous, true) == 5,
            "moved emptyoutside room omitted");
    }
    static void woven() throws Exception {
        Main.main(new String[0]);
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", BasementRoomLookupChecks.class.getClassLoader());
        for (int role = 0; role < 3; role++) {
            zombie.network.GameServer.server = role == 1; zombie.network.GameClient.client = role == 2;
            var fixture = new Fixture(false, -1, true);
            require(fixture.destination.roomByMetaId.size() == 6, "woven native merge did not restore exactly4 entries");
            for (int i = 0; i < fixture.moved.size(); i++) flags(fixture.moved.get(i), 15 ^ i);
            var bytes = save(fixture.grid);
            for (RoomDef room : fixture.moved) flags(room, 0);
            loadRoomSection(fixture.grid, bytes);
            for (int i = 0; i < fixture.moved.size(); i++) require(flags(fixture.moved.get(i)) == (15 ^ i),
                "woven old-format flags lost for role=" + role);
        }
        zombie.network.GameServer.server = false; zombie.network.GameClient.client = false;
        var missing = new Fixture(false, 0, true);
        require(missing.destination.roomByMetaId.size() == 5
            && !missing.destination.roomByMetaId.containsKey(missing.moved.get(0).metaId),
            "woven merge created a deliberately missing source index");
    }
    public static void main(String[] args) throws Exception {
        String cache = System.getProperty("pz.test.cache");
        if (cache != null) zombie.ZomboidFileSystem.instance.setCacheDir(cache);
        zombie.core.random.RandStandard.INSTANCE.init();
        roundTrips(); guards();
        woven();
        System.out.println("BASEMENT_ROOM_LOOKUP_CHECKS_PASS (native cross-cell omission, missing-only repair, all16 flags,"
            + " byte-identical save, IDs/layout/caches/spawn receipts, unsupported/same-cell/custom/collision guards, emptyoutside, woven SP/server/client)");
    }
}
