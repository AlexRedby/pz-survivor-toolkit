package zombie.basements;

import java.lang.reflect.Method;
import java.nio.BufferUnderflowException;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.function.Consumer;
import me.zed_0xff.zombie_buddy.PatchEngine;
import net.alexredby.pztoolkitjavapatches.BasementHallKey;
import net.alexredby.pztoolkitjavapatches.Main;
import zombie.ZomboidFileSystem;
import zombie.core.Core;
import zombie.iso.*;
import zombie.iso.areas.IsoBuilding;
import zombie.iso.areas.IsoRoom;
import static zombie.basements.BasementRoomLookupChecks.flags;
import static zombie.basements.BasementRoomLookupChecks.field;
import static zombie.basements.BasementRoomLookupChecks.require;

public final class BasementHallKeyChecks {
    static final int CX = 41, CY = 37;
    static final String HEADER = "media/maps/Muldraugh, KY/41_37.lotheader";
    static final String ACCESS = "media/basement_access/ba_exterior_north_westside_13.pzby";
    static final long ORIGINAL = BasementHallKey.ORIGINAL_KEY, SPLIT = BasementHallKey.HALL_KEY;

    static RoomDef room(long id, String name, int x, int y) {
        var room = new RoomDef(id, name);
        room.rects.add(new RoomDef.RoomRect(x, y, 1, 4));
        room.CalculateBounds(); room.metaId = room.calculateMetaID(CX, CY);
        return room;
    }
    static Object state(RoomDef room) {
        return List.of(room.id, room.name, room.level, room.x, room.y, room.x2, room.y2, room.area,
            room.building, new ArrayList<>(room.rects), new ArrayList<>(room.objects), flags(room));
    }
    static void invoke(Object owner, String name, Class<?>[] types, Object... args) throws Exception {
        Method method = owner.getClass().getDeclaredMethod(name, types);
        method.setAccessible(true); method.invoke(owner, args);
    }
    static void reindex(Object owner, IsoMetaCell cell) throws Exception {
        invoke(owner, "recalculateBuildingAndRoomIDs", new Class<?>[]{IsoMetaCell.class}, cell);
    }

    static final class Fixture {
        final IsoMetaGrid grid = IsoWorld.instance.metaGrid;
        final IsoMetaCell cell = new IsoMetaCell(CX, CY);
        final BuildingDef receiving = new BuildingDef(), incoming = new BuildingDef();
        final RoomDef original, access = room(0, "hall", 10707, 9484);
        final IsoRoom cachedRoom = new IsoRoom();
        final IsoBuilding cachedBuilding = new IsoBuilding();
        final IsoChunk receipt = new IsoChunk((IsoCell)null);
        Fixture() throws Exception {
            grid.minX = grid.maxX = CX; grid.minY = grid.maxY = CY;
            field(grid, "grid", new IsoMetaCell[][]{{cell}}); field(grid, "width", 1); field(grid, "height", 1);
            cell.info = new LotHeader(CX, CY);
            for (int i = 0; i < 108; i++) {
                RoomDef room = room(RoomID.makeID(CX, CY, i), i == 107 ? "hall" : "unrelated",
                    i == 107 ? 10707 : 10720 + (i % 10) * 2, i == 107 ? 9484 : 9500 + (i / 10) * 5);
                cell.roomList.add(room); cell.rooms.put(room.id, room); cell.roomByMetaId.put(room.metaId, room);
            }
            original = cell.roomList.get(107);
            require(original.metaId == ORIGINAL && access.metaId == ORIGINAL, "stock collision geometry differs");
            require(original.x2 == 10708 && original.y2 == 9488 && original.area == 4, "native hall bounds differ");
            for (int i = 0; i < 16; i++) {
                var prefix = new BuildingDef(); prefix.id = BuildingID.makeID(CX, CY, i); cell.buildings.add(prefix);
            }
            receiving.id = BuildingID.makeID(CX, CY, 16); original.building = receiving;
            receiving.rooms.add(original); receiving.CalculateBounds(new ArrayList<>());
            receiving.metaId = receiving.calculateMetaID(CX, CY);
            cell.buildings.add(receiving); cell.buildingByMetaId.put(receiving.metaId, receiving);
            access.building = incoming; incoming.rooms.add(access); incoming.CalculateBounds(new ArrayList<>());
            cachedRoom.def = original; cachedBuilding.def = receiving;
            cell.isoRooms.put(original.id, cachedRoom); cell.isoBuildings.put(receiving.id, cachedBuilding);
            receipt.addSpawnedRoom(original.id);
        }
        void split() {
            var rooms = new ArrayList<>(cell.roomList); var runtime = new HashMap<>(cell.rooms);
            var buildings = new ArrayList<>(cell.buildings);
            var buildingIndex = new gnu.trove.map.hash.TLongObjectHashMap<>(cell.buildingByMetaId);
            var roomCache = new HashMap<>(cell.isoRooms); var buildingCache = new HashMap<>(cell.isoBuildings);
            Object before = state(original), accessBefore = state(access);
            require(BasementHallKey.beforeMerge(incoming, receiving, true), "stock hall was not split");
            require(cell.roomList.equals(rooms) && cell.rooms.equals(runtime) && cell.buildings.equals(buildings)
                && cell.buildingByMetaId.equals(buildingIndex) && cell.isoRooms.equals(roomCache)
                && cell.isoBuildings.equals(buildingCache) && before.equals(state(original)) && accessBefore.equals(state(access)),
                "split changed IDs/layout/owner/caches/flags");
            require(original.metaId == SPLIT && cell.roomByMetaId.get(SPLIT) == original
                && !cell.roomByMetaId.containsKey(ORIGINAL) && access.metaId == ORIGINAL, "wrong premerge routing");
            require(receipt.isSpawnedRoom(original.id), "split invalidated spawn receipt");
            require(!BasementHallKey.beforeMerge(incoming, receiving, true), "split was not idempotent");
        }
        void merge() throws Exception {
            var before = cell.roomList.stream().mapToLong(room -> room.id).toArray();
            Object unchanged = state(original);
            invoke(new Basements(), "mergeBuildings", new Class<?>[]{BuildingDef.class, BuildingDef.class}, incoming, receiving);
            require(cell.roomList.size() == 109 && cell.roomList.get(107) == original && cell.roomList.get(108) == access,
                "native merge replaced/skipped/aliased a room");
            for (int i = 0; i < before.length; i++) require(cell.roomList.get(i).id == before[i], "existing runtime ID shifted");
            require(access.id == RoomID.makeID(CX, CY, 108) && access.building == receiving
                && receiving.id == BuildingID.makeID(CX, CY, 16) && receiving.rooms.equals(List.of(original, access)),
                "native merged IDs/owner changed");
            require(unchanged.equals(state(original)) && cell.isoRooms.get(original.id) == cachedRoom
                && cell.isoBuildings.get(receiving.id) == cachedBuilding && receipt.isSpawnedRoom(original.id),
                "native merge lost original state/cache/receipt");
            require(cell.roomByMetaId.get(ORIGINAL) == access, "legacy records no longer route to access hall");
        }
        ByteBuffer save() {
            ByteBuffer bytes = ByteBuffer.allocate(32768); grid.savePart(bytes, 0, false); bytes.flip(); return bytes;
        }
        void load(ByteBuffer saved) {
            ByteBuffer bytes = saved.duplicate(); int count = bytes.getInt(24); bytes.position(0); bytes.limit(28 + count * 10);
            try { grid.load(bytes); throw new AssertionError("room section did not end at building count"); }
            catch (BufferUnderflowException expected) {
                require(bytes.position() == bytes.limit(), "unexpected native room-load boundary");
            }
        }
    }
    static Fixture merged(boolean split) throws Exception {
        var fixture = new Fixture(); if (split) fixture.split(); fixture.merge(); return fixture;
    }

    static void roundTrips() throws Exception {
        for (int hall = 0; hall < 16; hall++) for (int access = 0; access < 16; access++) {
            var nativeFixture = merged(false); flags(nativeFixture.original, hall); flags(nativeFixture.access, access);
            ByteBuffer legacy = nativeFixture.save(); flags(nativeFixture.original, 0); flags(nativeFixture.access, 0);
            nativeFixture.load(legacy); int nativeHall = flags(nativeFixture.original), nativeAccess = flags(nativeFixture.access);
            var split = merged(true); split.load(legacy);
            require(flags(split.original) == nativeHall && flags(split.access) == nativeAccess,
                "legacy native flag routing differs for " + hall + "/" + access);
            flags(split.original, hall); flags(split.access, access);
            for (int pass = 0; pass < 2; pass++) {
                ByteBuffer saved = split.save(); split = merged(true); split.load(saved);
                require(flags(split.original) == hall && flags(split.access) == access,
                    "independent flags lost after reconstruction, pass=" + pass);
            }
        }
        var split = merged(true); flags(split.original, 1); flags(split.access, 14);
        ByteBuffer saved = split.save(); var downgrade = merged(false); downgrade.load(saved);
        require(flags(downgrade.original) == 0 && flags(downgrade.access) == 14,
            "unpatched downgrade/save dependency no longer reproduced");
    }

    static void rejected(String label, Consumer<Fixture> change) throws Exception {
        var fixture = new Fixture(); change.accept(fixture);
        long before = fixture.original.metaId;
        var index = new gnu.trove.map.hash.TLongObjectHashMap<>(fixture.cell.roomByMetaId);
        require(!BasementHallKey.beforeMerge(fixture.incoming, fixture.receiving, true), "unguarded split: " + label);
        require(fixture.original.metaId == before && fixture.cell.roomByMetaId.equals(index), "rejected split mutated: " + label);
    }
    static void changedAsset(String asset, boolean missing) throws Exception {
        Path modified = Files.createTempFile("pz-hall-key-negative-", ".bin");
        var files = ZomboidFileSystem.instance.activeFileMap; String key = asset.toLowerCase(Locale.ENGLISH);
        String previous = files.put(key, modified.toString());
        try {
            if (missing) Files.delete(modified); else Files.writeString(modified, "modified native source");
            require(ZomboidFileSystem.instance.getString(asset).equals(modified.toString()), "asset override inactive");
            rejected(asset + (missing ? " missing" : " changed"), fixture -> {});
        } finally {
            if (previous == null) files.remove(key); else files.put(key, previous);
            Files.deleteIfExists(modified);
        }
    }
    static void calculationRefused(Fixture fixture, int cellX, int cellY, String label) {
        Object before = state(fixture.original), accessBefore = state(fixture.access);
        long key = fixture.original.metaId, accessKey = fixture.access.metaId;
        var index = new gnu.trove.map.hash.TLongObjectHashMap<>(fixture.cell.roomByMetaId);
        try {
            BasementHallKey.calculated(fixture.original, cellX, cellY, ORIGINAL, true);
            throw new AssertionError("calculation did not refuse: " + label);
        } catch (IllegalStateException expected) {
            require(key == fixture.original.metaId && before.equals(state(fixture.original))
                && accessKey == fixture.access.metaId && accessBefore.equals(state(fixture.access))
                && fixture.cell.roomByMetaId.equals(index), "refused calculation mutated state: " + label);
        }
    }
    static void guards() throws Exception {
        var fixture = new Fixture();
        require(!BasementHallKey.beforeMerge(fixture.incoming, fixture.receiving, false), "unsupported split");
        require(!BasementHallKey.beforeMerge(null, fixture.receiving, true)
            && !BasementHallKey.beforeMerge(fixture.incoming, null, true)
            && !BasementHallKey.beforeMerge(fixture.receiving, fixture.receiving, true), "invalid buildings accepted");
        rejected("different cell", f -> f.receiving.id = BuildingID.makeID(40, CY, 16));
        rejected("different building", f -> f.receiving.id = BuildingID.makeID(CX, CY, 15));
        rejected("custom incoming", f -> f.incoming.setUserDefined(true));
        rejected("custom receiving", f -> f.receiving.setUserDefined(true));
        rejected("custom room", f -> f.original.userDefined = true);
        rejected("extra incoming", f -> f.incoming.rooms.add(room(1, "other", 10710, 9490)));
        rejected("incoming outside", f -> f.incoming.emptyoutside.add(room(1, "emptyoutside", 10710, 9490)));
        rejected("incoming ID", f -> f.access.id = 1);
        rejected("incoming owner", f -> f.access.building = f.receiving);
        rejected("name", f -> f.original.name = "custom");
        rejected("level", f -> f.original.level = 1);
        rejected("bounds", f -> f.original.x2++);
        rejected("rectangle", f -> f.original.rects.add(new RoomDef.RoomRect(10707, 9484, 1, 4)));
        rejected("wrong original ID", f -> f.original.id++);
        rejected("wrong original key", f -> f.original.metaId++);
        rejected("missing header", f -> f.cell.info = null);
        rejected("unregistered building", f -> f.cell.buildings.remove(f.receiving));
        rejected("runtime index", f -> f.cell.rooms.remove(f.original.id));
        rejected("persistent index", f -> f.cell.roomByMetaId.remove(ORIGINAL));
        rejected("occupied index", f -> f.cell.roomByMetaId.put(SPLIT, f.access));
        rejected("occupied null entry", f -> f.cell.roomByMetaId.put(SPLIT, null));
        rejected("occupied list", f -> f.cell.roomList.get(0).metaId = SPLIT);
        rejected("duplicate native key", f -> f.cell.roomList.get(0).metaId = ORIGINAL);
        Core.gameMap = "Muldraugh, KY;Custom";
        try { rejected("additional map", f -> {}); } finally { Core.gameMap = "Muldraugh, KY"; }
        for (String asset : List.of(HEADER, ACCESS)) { changedAsset(asset, false); changedAsset(asset, true); }

        fixture = new Fixture(); fixture.split();
        require(BasementHallKey.calculated(fixture.original, CX, CY, ORIGINAL, true) == SPLIT, "marked hall key lost");
        fixture.cell.roomByMetaId.remove(SPLIT);
        require(BasementHallKey.calculated(fixture.original, CX, CY, ORIGINAL, true) == SPLIT, "unoccupied marked key lost");
        fixture.cell.roomByMetaId.put(SPLIT, null);
        calculationRefused(fixture, CX, CY, "occupied null entry");
        fixture.cell.roomByMetaId.remove(SPLIT);
        require(BasementHallKey.calculated(fixture.access, CX, CY, ORIGINAL, true) == ORIGINAL, "access key changed");
        require(BasementHallKey.calculated(fixture.original, CX, CY, ORIGINAL, false) == ORIGINAL, "unsupported retention");
        calculationRefused(fixture, CX + 1, CY, "missing destination cell");
        require(BasementHallKey.calculated(fixture.original, CX, CY, 123, true) == SPLIT, "assigned key followed changed native key");
        fixture.original.metaId = 0;
        require(BasementHallKey.calculated(fixture.original, CX, CY, ORIGINAL, true) == SPLIT,
            "adopted identity lost its assigned key after native/editor marker reset");
        fixture.original.metaId = SPLIT;
        RoomDef unregistered = room(0, "hall", 10707, 9484); unregistered.building = fixture.receiving; unregistered.metaId = SPLIT;
        require(BasementHallKey.calculated(unregistered, CX, CY, ORIGINAL, true) == ORIGINAL,
            "manually marked unregistered room adopted");
        unregistered.userDefined = true;
        require(BasementHallKey.calculated(unregistered, CX, CY, 123, true) == 123, "unregistered custom room changed");
        fixture.original.userDefined = true;
        fixture.receiving.setUserDefined(true); fixture.original.name = "custom";
        fixture.original.rects.clear(); fixture.original.rects.add(new RoomDef.RoomRect(10708, 9485, 2, 5));
        fixture.original.CalculateBounds();
        require(BasementHallKey.calculated(fixture.original, CX, CY, 123, true) == SPLIT,
            "adopted room lost its assigned key after name/shape/custom edits");
        fixture.cell.roomByMetaId.put(SPLIT, fixture.access);
        calculationRefused(fixture, CX, CY, "occupied index");
        fixture.cell.roomByMetaId.remove(SPLIT); fixture.cell.roomList.get(0).metaId = SPLIT;
        calculationRefused(fixture, CX, CY, "unindexed occupied key");
        fixture.cell.roomList.get(0).metaId = 0;
        var destination = new IsoMetaCell(CX + 1, CY); destination.info = new LotHeader(CX + 1, CY);
        fixture.grid.maxX = CX + 1;
        field(fixture.grid, "grid", new IsoMetaCell[][]{{fixture.cell}, {destination}}); field(fixture.grid, "width", 2);
        require(BasementHallKey.calculated(fixture.original, CX + 1, CY, 123, true) == SPLIT,
            "adopted room lost its assigned key in an existing destination cell");
    }

    static void woven() throws Exception {
        Main.main(new String[0]); require(BasementHallKey.SUPPORTED, "native bytecode is unsupported");
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", BasementHallKeyChecks.class.getClassLoader());
        for (int role = 0; role < 3; role++) {
            zombie.network.GameServer.server = role == 1; zombie.network.GameClient.client = role == 2;
            zombie.network.GameServer.gameMap = zombie.network.GameClient.gameMap = Core.gameMap = "Muldraugh, KY";
            var fixture = merged(false);
            require(fixture.original.metaId == SPLIT && fixture.cell.roomByMetaId.get(SPLIT) == fixture.original,
                "woven merge did not split stock hall, role=" + role);
            require(fixture.original.calculateMetaID(CX, CY) == SPLIT && fixture.access.calculateMetaID(CX, CY) == ORIGINAL,
                "woven calculateMetaID lost original/access distinction");
            flags(fixture.original, 1); flags(fixture.access, 14); ByteBuffer saved = fixture.save();
            fixture = merged(false); fixture.load(saved);
            require(flags(fixture.original) == 1 && flags(fixture.access) == 14, "woven reconstructed save lost flags");
            RoomDef tail = room(0, "unrelated", 10707, 9490); tail.building = fixture.receiving;
            invoke(new Basements(), "mergeRoomsOntoMetaCell", new Class<?>[]{ArrayList.class, IsoMetaCell.class},
                new ArrayList<>(List.of(tail)), fixture.cell);
            require(tail.id == RoomID.makeID(CX, CY, 109), "later room ID shifted by split");
            reindex(new Basements(), fixture.cell);
            require(fixture.original.id == RoomID.makeID(CX, CY, 107) && fixture.original.calculateMetaID(CX, CY) == SPLIT
                && fixture.cell.isoRooms.get(fixture.original.id) == fixture.cachedRoom && fixture.receipt.isSpawnedRoom(fixture.original.id),
                "native reindex lost room/cache/receipt");
        }
        zombie.network.GameServer.server = false; zombie.network.GameClient.client = false;
        var fixture = merged(false);
        flags(fixture.original, 1); flags(fixture.access, 14);
        fixture.original.name = "edited-hall";
        fixture.original.rects.clear(); fixture.original.rects.add(new RoomDef.RoomRect(10708, 9485, 2, 5));
        fixture.original.CalculateBounds();
        fixture.cell.roomList.remove(fixture.original); fixture.cell.rooms.remove(fixture.original.id);
        fixture.cell.roomByMetaId.remove(SPLIT); fixture.cell.isoRooms.clear();
        var regions = new zombie.iso.areas.isoregion.metagrid.WorldRegionToMetaGrid();
        reindex(regions, fixture.cell);
        invoke(new zombie.buildingRooms.BREBuilding(), "mergeRoomsOntoMetaCell",
            new Class<?>[]{ArrayList.class, IsoMetaCell.class}, new ArrayList<>(List.of(fixture.original)), fixture.cell);
        reindex(regions, fixture.cell);
        require(fixture.original.id == RoomID.makeID(CX, CY, 108) && fixture.original.metaId == SPLIT
            && fixture.cell.roomByMetaId.get(SPLIT) == fixture.original && fixture.cell.roomByMetaId.get(ORIGINAL) == fixture.access
            && fixture.cell.rooms.get(fixture.original.id) == fixture.original && fixture.original.building == fixture.receiving
            && fixture.original.calculateMetaID(CX, CY) == SPLIT && flags(fixture.original) == 1 && flags(fixture.access) == 14,
            "edited BRE re-add/WorldRegion reindex lost assigned key, access routing, identity or independent states");
        ByteBuffer edited = fixture.save(); flags(fixture.original, 0); flags(fixture.access, 0); fixture.load(edited);
        require(flags(fixture.original) == 1 && flags(fixture.access) == 14,
            "edited/remerged original and access states did not independently reload");
    }
    public static void main(String[] args) throws Exception {
        String cache = System.getProperty("pz.test.cache");
        if (cache != null) ZomboidFileSystem.instance.setCacheDir(cache);
        ZomboidFileSystem.instance.base.set(Path.of(".").toFile()); Core.gameMap = "Muldraugh, KY";
        zombie.core.random.RandStandard.INSTANCE.init();
        roundTrips(); guards(); woven();
        System.out.println("BASEMENT_HALL_KEY_CHECKS_PASS (all256 legacy flag pairs,512 reconstructed split-save roundtrips,"
            + " downgrade dependency,IDs/layout/owner/caches/spawn receipts,source/map/custom/collision guards,"
            + " woven SP/server/client,registered identity retention,explicit collision refusal,edited BRE re-add/WorldRegion reindex; no UI/render coverage)");
    }
}
