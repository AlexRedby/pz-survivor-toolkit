package zombie.iso;

import java.io.InputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.IdentityHashMap;
import zombie.basements.Basements;

public final class RoomCollisionOrderChecks {
    static final long COLLISION = 786643L;
    static final String JAR_HASH = "e1a69eb743ede60b213a0fe7f8b83d4fcab773036d256cc4543a336f3b058a33";
    static final String HEADER_HASH = "05cd36a09eb5f0e999b1def16d78dfa6510bee557eca0ef1d3fe209f5b41313e";

    static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    static void field(Object object, String name, Object value) throws Exception {
        Field field = object.getClass().getDeclaredField(name);
        field.setAccessible(true); field.set(object, value);
    }
    static String sha256(Path path) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream input = Files.newInputStream(path)) {
            byte[] bytes = new byte[65536];
            int count;
            while ((count = input.read(bytes)) != -1) digest.update(bytes, 0, count);
        }
        return HexFormat.of().formatHex(digest.digest());
    }
    static String line(ByteBuffer bytes) {
        int start = bytes.position();
        while (bytes.get() != '\n') { }
        int end = bytes.position() - 1;
        if (end > start && bytes.get(end - 1) == '\r') end--;
        return new String(bytes.array(), start, end - start, StandardCharsets.UTF_8);
    }
    static void add(IsoMetaCell cell, RoomDef room) {
        room.id = RoomID.makeID(41, 37, cell.roomList.size());
        room.metaId = room.calculateMetaID(41, 37);
        cell.roomList.add(room); cell.rooms.put(room.id, room); cell.roomByMetaId.put(room.metaId, room);
    }
    static IsoMetaCell stockHeader(byte[] header) {
        ByteBuffer bytes = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN);
        require(bytes.getInt() == 0x48544f4c && bytes.getInt() == 1, "unexpected stock lotheader format");
        int tiles = bytes.getInt();
        for (int i = 0; i < tiles; i++) line(bytes);
        require(bytes.getInt() == 8 && bytes.getInt() == 8 && bytes.getInt() == -1 && bytes.getInt() == 4,
            "unexpected stock lotheader dimensions");
        IsoMetaCell cell = new IsoMetaCell(41, 37); cell.info = new LotHeader(41, 37);
        int rooms = bytes.getInt();
        require(rooms == 303, "stock room count changed");
        for (int i = 0; i < rooms; i++) {
            RoomDef room = new RoomDef(0, line(bytes)); room.level = bytes.getInt();
            int rectangles = bytes.getInt();
            for (int j = 0; j < rectangles; j++) room.rects.add(new RoomDef.RoomRect(
                bytes.getInt() + 41 * 256, bytes.getInt() + 37 * 256, bytes.getInt(), bytes.getInt()));
            room.CalculateBounds();
            int objects = bytes.getInt();
            for (int j = 0; j < objects * 3; j++) bytes.getInt();
            add(cell, room);
        }
        int buildings = bytes.getInt();
        for (int i = 0; i < buildings; i++) {
            BuildingDef building = new BuildingDef(); building.id = BuildingID.makeID(41, 37, i);
            int count = bytes.getInt();
            for (int j = 0; j < count; j++) {
                RoomDef room = cell.roomList.get(bytes.getInt()); room.building = building;
                (room.isEmptyOutside() ? building.emptyoutside : building.rooms).add(room);
            }
            building.CalculateBounds(new ArrayList<>()); building.metaId = building.calculateMetaID(41, 37);
            cell.buildings.add(building); cell.buildingByMetaId.put(building.metaId, building);
        }
        return cell;
    }
    static RoomDef room(String name, int x, int y, int width, int height, boolean userDefined) {
        RoomDef room = new RoomDef(0, name);
        room.rects.add(new RoomDef.RoomRect(x, y, width, height)); room.CalculateBounds();
        room.userDefined = userDefined;
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
    static ByteBuffer save(IsoMetaGrid grid, boolean mode) {
        ByteBuffer bytes = ByteBuffer.allocate(20000); grid.savePart(bytes, 0, mode); bytes.flip(); return bytes;
    }
    static void unchangedIDs(IsoMetaCell cell, IdentityHashMap<RoomDef, Long> previous) {
        for (var entry : previous.entrySet()) require(entry.getKey().id == entry.getValue()
            && cell.rooms.get(entry.getValue()) == entry.getKey(), "native same-cell merge changed another room ID");
    }
    public static void main(String[] args) throws Exception {
        Path jar = Path.of("projectzomboid.jar").toRealPath();
        require(Path.of(RoomDef.class.getProtectionDomain().getCodeSource().getLocation().toURI()).toRealPath().equals(jar)
            && Path.of(Basements.class.getProtectionDomain().getCodeSource().getLocation().toURI()).toRealPath().equals(jar),
            "run from the native game Java directory with its native classes");
        require(sha256(jar).equals(JAR_HASH), "unsupported native B42.21 JAR");
        Path path = Path.of("media/maps/Muldraugh, KY/41_37.lotheader");
        byte[] header = Files.readAllBytes(path);
        require(HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(header)).equals(HEADER_HASH),
            "unsupported stock41_37 lotheader");
        String cache = System.getProperty("pz.test.cache");
        if (cache != null) zombie.ZomboidFileSystem.instance.setCacheDir(cache);
        zombie.core.random.RandStandard.INSTANCE.init();
        Method merge = Basements.class.getDeclaredMethod("mergeBuildings", BuildingDef.class, BuildingDef.class);
        merge.setAccessible(true);
        int cases = 0;
        for (int unrelated : new int[]{0, 3, 17}) {
            IsoMetaCell cell = stockHeader(header);
            RoomDef base = cell.roomList.get(107); BuildingDef owner = cell.buildings.get(16);
            require(base.building == owner && base.metaId == COLLISION && base.name.equals("hall")
                && base.level == 0 && base.rects.size() == 1 && base.x == 10707 && base.y == 9484
                && base.getW() == 1 && base.getH() == 4, "stock base hall owner/geometry changed");
            for (int i = 0; i < unrelated; i++) add(cell, room("unrelated", 41 * 256 + i, 37 * 256 + 100, 1, 1, false));
            add(cell, room("user-before", 41 * 256 + 100, 37 * 256 + 100, 1, 1, true));
            var previous = new IdentityHashMap<RoomDef, Long>();
            for (RoomDef room : cell.roomList) previous.put(room, room.id);
            IsoMetaGrid grid = IsoWorld.instance.metaGrid;
            grid.minX = grid.maxX = 41; grid.minY = grid.maxY = 37;
            field(grid, "grid", new IsoMetaCell[][]{{cell}}); field(grid, "width", 1); field(grid, "height", 1);
            // Geometry from the native saved basement access hall; this fixture does not load a saved world.
            BuildingDef accessBuilding = new BuildingDef();
            RoomDef access = room("hall", 10707, 9484, 1, 4, false);
            access.building = accessBuilding; accessBuilding.rooms.add(access); accessBuilding.CalculateBounds(new ArrayList<>());
            merge.invoke(new Basements(), accessBuilding, owner);
            unchangedIDs(cell, previous);
            require(base.id == RoomID.makeID(41, 37, 107) && cell.roomList.get(107) == base
                && cell.roomList.indexOf(access) == 304 + unrelated && access.metaId == COLLISION
                && access.building == owner && !base.userDefined && !access.userDefined, "native base/access append contract changed");
            add(cell, room("user-after", 41 * 256 + 101, 37 * 256 + 100, 1, 1, true));
            add(cell, room("unrelated-after", 41 * 256 + 102, 37 * 256 + 100, 1, 1, false));
            var serialized = cell.roomList.stream().filter(room -> !room.userDefined).toList();
            for (int a = 0; a < 16; a++) for (int b = 0; b < 16; b++) {
                flags(base, a); flags(access, b);
                ByteBuffer bytes = save(grid, false);
                require(bytes.equals(save(grid, true)), "savePart boolean changed room serialization");
                require(bytes.getInt() == 0x4d455441 && bytes.getInt() == 249, "native save header changed");
                bytes.position(24); require(bytes.getInt() == serialized.size() && serialized.size() == cell.roomList.size() - 2,
                    "native userDefined filtering changed");
                int hits = 0;
                for (RoomDef expected : serialized) {
                    long metaID = bytes.getLong(); short savedFlags = bytes.getShort();
                    require(metaID == expected.metaId && savedFlags == flags(expected), "native room order/flags changed");
                    if (metaID == COLLISION) {
                        require(expected == (hits == 0 ? base : access) && savedFlags == (hits == 0 ? a : b),
                            "native collision occurrences changed owner");
                        hits++;
                    }
                }
                require(hits == 2, "unexpected collision multiplicity");
                unchangedIDs(cell, previous); cases++;
            }
        }
        require(cases == 768, "flag/layout cases omitted");
        System.out.println("ROOM_COLLISION_ORDER_CHECKS_PASS (stock header, native same-cell merge, all256 flags,"
            + " 0/3/17 unrelated rooms, userDefined filtering, both save booleans, original room IDs)");
    }
}
