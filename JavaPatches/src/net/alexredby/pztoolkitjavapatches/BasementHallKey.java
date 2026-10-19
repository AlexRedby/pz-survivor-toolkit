package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.Collections;
import java.util.HexFormat;
import java.util.Set;
import java.util.WeakHashMap;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;
import zombie.iso.BuildingDef;
import zombie.iso.BuildingID;
import zombie.iso.IsoMetaCell;
import zombie.iso.IsoWorld;
import zombie.iso.RoomDef;
import zombie.iso.RoomID;

public final class BasementHallKey {
    public static final boolean SUPPORTED = BasementRoomLookup.SUPPORTED
        && BytecodeSupport.supports("zombie/buildingRooms/BREBuilding.class", "77d5710d7b102532e080c556a87439d3d827cf4c8a05fc5cd7e37c90175c83de")
        && BytecodeSupport.supports("zombie/iso/areas/isoregion/metagrid/WorldRegionToMetaGrid.class", "635174f093618dac7ec320b3884780b847d1332d03b3c07b3221f2b899728b20")
        && BytecodeSupport.supports("zombie/iso/LightingJNI.class", "3938fd1336a64403ae52a3a1552fcdff3a3c54f1a0360c6ee35512c2f9b7e5e7")
        && BytecodeSupport.supports("zombie/iso/fboRenderChunk/FBORenderCell.class", "d5c46201d60cff36397ee46c56b53dbaee6e26e8733836f27bf56ad871eedf94");

    public static final long ORIGINAL_KEY = 786643L;
    public static final long HALL_KEY = 0x505A0000000C00D3L;
    private static final String HEADER = "media/maps/Muldraugh, KY/41_37.lotheader";
    private static final String HEADER_HASH = "05cd36a09eb5f0e999b1def16d78dfa6510bee557eca0ef1d3fe209f5b41313e";
    private static final String ACCESS = "media/basement_access/ba_exterior_north_westside_13.pzby";
    private static final String ACCESS_HASH = "706ac77ce0c3d5daa653f1932b8674313340606324f9bffd75fbd194573d5ae3";
    private static final Set<RoomDef> separated = Collections.synchronizedSet(
        Collections.newSetFromMap(new WeakHashMap<>()));

    private BasementHallKey() { }

    public static void prepare() {
        if (SUPPORTED) zombie.iso.RoomDef.class.getName();
    }

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

    @Patch(className="zombie.iso.RoomDef", methodName="calculateMetaID", strictMatch=true)
    public static class NativeBasementHallKey {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.iso.RoomDef room, @Patch.Argument(0) int cellX,
                                @Patch.Argument(1) int cellY, @Patch.Return(readOnly=false) long result) {
            result = BasementHallKey.calculated(room, cellX, cellY, result, BasementHallKey.SUPPORTED);
        }
    }
}
