package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.Collections;
import java.util.HexFormat;
import java.util.Set;
import java.util.WeakHashMap;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;
import zombie.iso.IsoMetaGrid;
import zombie.iso.objects.IsoMannequin.MannequinZone;
import zombie.iso.zones.Zone;

public final class MannequinZoneData {
    public static final boolean SUPPORTED = BytecodeSupport.supports("zombie/Lua/LuaManager.class",
            "dcaad0082ca27a15550c7d0a6e14b3aeb71f634a14f32123dec620df180c646d")
        && BytecodeSupport.supports("zombie/Lua/LuaManager$GlobalObject.class",
            "80ecbd3bd702db2f992db6cba7cb09c32d775fa6f2a3297e0460874ff5ba20c7")
        && BytecodeSupport.supports("zombie/iso/IsoMetaGrid.class",
            "cdd50bb0a393c766d25c9dcbc5f7e929d7e10a6b9c9b95e22c3bae94b3b5b1f9")
        && BytecodeSupport.supports("zombie/iso/zones/Zone.class",
            "41faa20ceed9764ba0aa32d8fa81f0329d40a1f5da575beb65601e077346e91c")
        && BytecodeSupport.supports("zombie/iso/objects/IsoMannequin.class",
            "158b696a5ff5ee99e7c60cbd17d7055b6d7c9afbc5c1595e34f2fbcb4feef5e1")
        && BytecodeSupport.supports("zombie/iso/objects/IsoMannequin$MannequinZone.class",
            "34d053c48f0522dbeb73f69daa45683c0feb1ff2181b83ef6d8dcfd53aa3848d");

    private static final String FILE = "media/maps/Muldraugh, KY/objects.lua";
    private static final String HASH = "bb2af79f1814265f9ad65bc9b55b0c723cc5a372d92ccc65aae3ffc9acf29572";
    private static final String HANDLER = "media/lua/server/metazones/metazoneHandler.lua";
    private static final String HANDLER_HASH = "c8cbc5c52a32405d2822d2601af4227afb5149937c372cd22916a7faba5ff6ba";
    private static final Set<KahluaTable> pending = Collections.newSetFromMap(new WeakHashMap<>());
    private static final Set<MannequinZone> repaired = Collections.newSetFromMap(new WeakHashMap<>());

    private MannequinZoneData() { }

    public static void prepare() {
        if (SUPPORTED) {
            zombie.Lua.LuaManager.class.getName();
            zombie.iso.IsoMetaGrid.class.getName();
        }
    }

    public static synchronized void loaded(String file, Object previousObjects, boolean supported) {
        if (!supported || !FILE.equals(file) || LuaManager.env == null) return;
        Object currentObjects = LuaManager.env.rawget("objects");
        if (currentObjects == previousObjects || !(currentObjects instanceof KahluaTable objects)) return;
        var directories = LuaManager.GlobalObject.getLotDirectories();
        if (directories.size() != 1 || !directories.get(0).equals("Muldraugh, KY")) return;
        try {
            if (!matches(FILE, HASH) || !matches(HANDLER, HANDLER_HASH)) return;
        } catch (Exception error) {
            System.err.println("[PZToolkitJavaPatches] Kept native mannequin data: " + error);
            return;
        }
        KahluaTable found = null;
        var entries = objects.iterator();
        while (entries.advance()) {
            if (!(entries.getValue() instanceof KahluaTable row) || !exactRow(row)) continue;
            if (found != null) return;
            found = row;
        }
        if (found == null) return;
        KahluaTable properties = LuaManager.platform.newTable();
        pending.add(properties);
        found.rawset("properties", properties);
    }

    private static boolean matches(String file, String hash) throws Exception {
        byte[] bytes = Files.readAllBytes(Path.of(ZomboidFileSystem.instance.getString(file)));
        return hash.equals(HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)));
    }

    private static boolean exactRow(KahluaTable row) {
        int count = 0;
        var fields = row.iterator();
        while (fields.advance()) count++;
        return count == 7 && "".equals(row.rawget("name")) && "Mannequin".equals(row.rawget("type"))
            && Double.valueOf(13583).equals(row.rawget("x")) && Double.valueOf(1299).equals(row.rawget("y"))
            && Double.valueOf(0).equals(row.rawget("z")) && Double.valueOf(1).equals(row.rawget("width"))
            && Double.valueOf(1).equals(row.rawget("height"));
    }

    public static synchronized void registered(IsoMetaGrid grid, KahluaTable properties, Zone result) {
        if (properties != null && pending.remove(properties) && properties.isEmpty()
            && result instanceof MannequinZone zone && zone.x == 13583 && zone.y == 1299 && zone.z == 0
            && zone.w == 1 && zone.h == 1 && noOverrides(zone)) {
            repaired.add(zone);
            System.out.println("[PZToolkitJavaPatches] Registered native mannequin zone without overrides at 13583, 1299, 0");
        }
        if (repaired.isEmpty()) return;
        var cell = grid.getCellData(53, 5);
        if (cell == null) return;
        var zones = cell.mannequinZones;
        // Native lookup uses the first containing zone; this no-override row must never hide a custom zone.
        for (int i = zones.size() - 1; i >= 0; i--) {
            var zone = zones.get(i);
            if (repaired.contains(zone) && noOverrides(zone)) {
                zones.remove(i);
                zones.add(zone);
            }
        }
    }

    private static boolean noOverrides(MannequinZone zone) {
        return zone.female == -1 && zone.dir == null && zone.mannequinScript == null
            && zone.outfit == null && zone.skin == null && zone.pose == null;
    }

    @Patch(className="zombie.Lua.LuaManager", methodName="RunLua", strictMatch=true)
    public static class NativeMannequinZoneData {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) String file, @Patch.Argument(1) boolean rewrite,
                                 @Patch.Local("toolkitPreviousObjects") Object previous) {
            if (MannequinZoneData.SUPPORTED && "media/maps/Muldraugh, KY/objects.lua".equals(file)
                && zombie.Lua.LuaManager.env != null) previous = zombie.Lua.LuaManager.env.rawget("objects");
        }

        @Patch.OnExit
        public static void exit(@Patch.Argument(0) String file, @Patch.Argument(1) boolean rewrite,
                                @Patch.Local("toolkitPreviousObjects") Object previous) {
            MannequinZoneData.loaded(file, previous, MannequinZoneData.SUPPORTED);
        }
    }

    @Patch(className="zombie.iso.IsoMetaGrid", methodName="registerMannequinZone", strictMatch=true)
    public static class NativeMannequinZonePriority {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.iso.IsoMetaGrid grid,
                                @Patch.Argument(0) String name, @Patch.Argument(1) String type,
                                @Patch.Argument(2) int x, @Patch.Argument(3) int y, @Patch.Argument(4) int z,
                                @Patch.Argument(5) int width, @Patch.Argument(6) int height,
                                @Patch.Argument(7) se.krka.kahlua.vm.KahluaTable properties,
                                @Patch.Return zombie.iso.zones.Zone zone) {
            MannequinZoneData.registered(grid, properties, zone);
        }
    }
}
