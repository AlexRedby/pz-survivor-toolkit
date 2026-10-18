package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.Collections;
import java.util.HexFormat;
import java.util.Set;
import java.util.WeakHashMap;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;
import zombie.iso.BuildingDef;
import zombie.iso.BuildingID;
import zombie.iso.IsoMetaCell;
import zombie.iso.IsoWorld;
import zombie.iso.RoomDef;
import zombie.iso.RoomID;

public final class BasementHallKey {
    public static final long ORIGINAL_KEY = 786643L;
    public static final long HALL_KEY = 0x505A0000000C00D3L;
    private static final String HEADER = "media/maps/Muldraugh, KY/41_37.lotheader";
    private static final String HEADER_HASH = "05cd36a09eb5f0e999b1def16d78dfa6510bee557eca0ef1d3fe209f5b41313e";
    private static final String ACCESS = "media/basement_access/ba_exterior_north_westside_13.pzby";
    private static final String ACCESS_HASH = "706ac77ce0c3d5daa653f1932b8674313340606324f9bffd75fbd194573d5ae3";
    private static final Set<RoomDef> separated = Collections.synchronizedSet(
        Collections.newSetFromMap(new WeakHashMap<>()));

    private BasementHallKey() { }

    public static boolean beforeMerge(BuildingDef incoming, BuildingDef receiving, boolean supported) {
        if (!supported || incoming == null || receiving == null || incoming == receiving
            || incoming.isUserDefined() || receiving.isUserDefined()
            || receiving.id != BuildingID.makeID(41, 37, 16)
            || incoming.rooms.size() != 1 || !incoming.emptyoutside.isEmpty()) return false;
        RoomDef access = incoming.rooms.get(0);
        if (access.id != 0 || access.building != incoming || !hall(access)) return false;
        IsoMetaCell cell = IsoWorld.instance.metaGrid.getCellData(41, 37);
        if (cell == null || cell.info == null || !cell.buildings.contains(receiving)
            || cell.roomList.size() <= 107 || cell.roomByMetaId.containsKey(HALL_KEY)) return false;
        RoomDef original = cell.roomList.get(107);
        if (original == access || !hall(original) || original.building != receiving
            || original.id != RoomID.makeID(41, 37, 107) || original.metaId != ORIGINAL_KEY
            || !receiving.rooms.contains(original) || cell.rooms.get(original.id) != original
            || cell.roomByMetaId.get(ORIGINAL_KEY) != original) return false;
        int originals = 0;
        for (RoomDef room : cell.roomList) {
            if (room.metaId == HALL_KEY) return false;
            if (room.metaId == ORIGINAL_KEY) originals++;
        }
        if (originals != 1 || !stockSources()) return false;
        // Keep legacy records routed to the access hall, exactly as the native loader did.
        cell.roomByMetaId.remove(ORIGINAL_KEY);
        original.metaId = HALL_KEY;
        cell.roomByMetaId.put(HALL_KEY, original);
        separated.add(original);
        System.out.println("[PZToolkitJavaPatches] Basement hall key separated: original=107, key=" + HALL_KEY
            + ", accessKey=" + ORIGINAL_KEY);
        return true;
    }

    public static long calculated(RoomDef room, int cellX, int cellY, long nativeKey, boolean supported) {
        if (!supported || room == null || !separated.contains(room)) return nativeKey;
        IsoMetaCell cell = IsoWorld.instance.metaGrid.getCellData(cellX, cellY);
        if (cell == null) throw new IllegalStateException("Cannot resolve the separated basement hall's destination cell");
        RoomDef occupied = cell.roomByMetaId.get(HALL_KEY);
        if (cell.roomByMetaId.containsKey(HALL_KEY) && occupied != room)
            throw new IllegalStateException("Refusing to overwrite an occupied basement hall key");
        for (RoomDef other : cell.roomList)
            if (other != room && other.metaId == HALL_KEY)
                throw new IllegalStateException("Refusing a duplicate separated basement hall key");
        // Admission is source-guarded; later edits must not silently replace the saved identity.
        return HALL_KEY;
    }

    private static boolean hall(RoomDef room) {
        if (room == null || room.userDefined || !"hall".equals(room.name) || room.level != 0
            || room.rects.size() != 1 || room.x != 10707 || room.y != 9484
            || room.x2 != 10708 || room.y2 != 9488 || room.area != 4) return false;
        var rect = room.rects.get(0);
        return rect.x == 10707 && rect.y == 9484 && rect.getW() == 1 && rect.getH() == 4;
    }

    private static boolean stockSources() {
        var maps = LuaManager.GlobalObject.getLotDirectories();
        if (maps.size() != 1 || !"Muldraugh, KY".equals(maps.get(0))) return false;
        try {
            return matches(HEADER, HEADER_HASH) && matches(ACCESS, ACCESS_HASH);
        } catch (Exception error) {
            System.err.println("[PZToolkitJavaPatches] Kept native basement hall key: " + error);
            return false;
        }
    }

    private static boolean matches(String file, String expected) throws Exception {
        byte[] bytes = Files.readAllBytes(Path.of(ZomboidFileSystem.instance.getString(file)));
        return expected.equals(HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)));
    }
}
