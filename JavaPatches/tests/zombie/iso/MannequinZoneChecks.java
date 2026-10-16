package zombie.iso;

import java.io.StringReader;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.Map;
import net.alexredby.pztoolkitjavapatches.MannequinZoneData;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.j2se.KahluaTableImpl;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;
import zombie.Lua.LuaManager;
import zombie.core.Core;
import zombie.iso.objects.IsoMannequin;
import zombie.iso.objects.IsoMannequin.MannequinZone;
import zombie.iso.sprite.IsoSprite;
import zombie.iso.zones.Zone;

public final class MannequinZoneChecks {
    static final String FILE = "media/maps/Muldraugh, KY/objects.lua";
    static void require(boolean condition, String message) { if (!condition) throw new AssertionError(message); }
    static KahluaTableImpl table() { return new KahluaTableImpl(new LinkedHashMap<>()); }
    static void set(Object object, Class<?> type, String name, Object value) throws Exception {
        Field field = type.getDeclaredField(name); field.setAccessible(true); field.set(object, value);
    }
    static IsoMetaGrid grid() throws Exception {
        var grid = new IsoMetaGrid(); grid.minX = grid.maxX = 53; grid.minY = grid.maxY = 5;
        set(grid, IsoMetaGrid.class, "width", 1); set(grid, IsoMetaGrid.class, "height", 1);
        set(grid, IsoMetaGrid.class, "grid", new IsoMetaCell[][]{{new IsoMetaCell(53, 5)}});
        return grid;
    }
    static KahluaTable loadSource(String source) throws Exception {
        var closure = LuaCompiler.loadis(new StringReader(source), FILE, LuaManager.env);
        new KahluaThread(LuaManager.platform, LuaManager.env).call(closure, null, null, null);
        return findRow();
    }
    static KahluaTable findRow() {
        var objects = (KahluaTable)LuaManager.env.rawget("objects");
        var entries = objects.iterator();
        while (entries.advance()) {
            var row = (KahluaTable)entries.getValue();
            if (Double.valueOf(13583).equals(row.rawget("x")) && Double.valueOf(1299).equals(row.rawget("y"))
                && "Mannequin".equals(row.rawget("type"))) return row;
        }
        throw new AssertionError("Native mannequin row absent");
    }
    static Zone register(IsoMetaGrid grid, KahluaTable properties, boolean patched) {
        Zone result = grid.registerMannequinZone("", "Mannequin", 13583, 1299, 0, 1, 1, properties);
        if (patched) MannequinZoneData.registered(grid, properties, result);
        return result;
    }
    static Map<String, Object> snapshot(IsoMannequin object) throws Exception {
        var result = new LinkedHashMap<String, Object>();
        for (Field field : IsoMannequin.class.getDeclaredFields()) if (!Modifier.isStatic(field.getModifiers())) {
            field.setAccessible(true); result.put(field.getName(), field.get(object));
        }
        Field dir = IsoObject.class.getDeclaredField("dir"); dir.setAccessible(true); result.put("direction", dir.get(object));
        return result;
    }
    static KahluaTable repair(String source) throws Exception {
        var row = loadSource(source); MannequinZoneData.loaded(FILE, null, true);
        require(row.rawget("properties") instanceof KahluaTable, "Native row not normalized");
        var properties = (KahluaTable)row.rawget("properties");
        require(properties.isEmpty(), "Appearance properties invented");
        return properties;
    }
    static void changedAsset(KahluaTable row, String file) throws Exception {
        Path modified = Files.createTempFile("pz-mannequin-negative-", ".lua");
        String key = file.toLowerCase(java.util.Locale.ENGLISH);
        var files = zombie.ZomboidFileSystem.instance.activeFileMap;
        String previous = files.put(key, modified.toString());
        try {
            Files.writeString(modified, "-- modified asset");
            require(zombie.ZomboidFileSystem.instance.getString(file).equals(modified.toString()), "Asset override fixture not active");
            MannequinZoneData.loaded(FILE, null, true);
            require(row.rawget("properties") == null, "Modified asset normalized: " + file);
        } finally {
            if (previous == null) files.remove(key); else files.put(key, previous);
            Files.delete(modified);
        }
    }

    static void nativeHandler(String source, IsoMetaGrid grid) throws Exception {
        int[] errors = {0}, registrations = {0};
        var luaLog = table();
        luaLog.rawset("error", (se.krka.kahlua.vm.JavaFunction)(frame, count) -> {
            require(frame.get(1).toString().contains("Mannequin zone missing properties"), "Unexpected native diagnostic");
            errors[0]++; return 0;
        });
        var debug = table(); debug.rawset("Lua", luaLog); LuaManager.env.rawset("DebugType", debug);
        var world = table();
        world.rawset("registerMannequinZone", (se.krka.kahlua.vm.JavaFunction)(frame, count) -> {
            register(grid, (KahluaTable)frame.get(8), true); registrations[0]++; return 0;
        });
        LuaManager.env.rawset("getWorld", (se.krka.kahlua.vm.JavaFunction)(frame, count) -> { frame.push(world); return 1; });
        String handler = Files.readString(Path.of("media/lua/server/metazones/metazoneHandler.lua"));
        handler = handler.substring(0, handler.indexOf("local function handleRoomTone")) + "\nreturn handleMannequinZone";
        var thread = new KahluaThread(LuaManager.platform, LuaManager.env);
        Object function = thread.call(LuaCompiler.loadis(new StringReader(handler), "native-handler", LuaManager.env), null, null, null);
        thread.call(function, FILE, loadSource(source), null);
        require(errors[0] == 1 && registrations[0] == 0, "Original malformed zone did not retain native error");
        repair(source); thread.call(function, FILE, findRow(), null);
        require(errors[0] == 1 && registrations[0] == 1, "Normalized row did not use native registration");
        var unknown = loadSource(source); unknown.rawset("x", 13584d); MannequinZoneData.loaded(FILE, null, true);
        thread.call(function, FILE, unknown, null);
        require(errors[0] == 2 && registrations[0] == 1, "Unknown malformed zone diagnostic suppressed");
        grid.getCellData(53, 5).mannequinZones.clear();
    }

    static void woven(IsoMetaGrid grid, IsoMannequin mannequin, Method fromZone) throws Exception {
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", MannequinZoneChecks.class.getClassLoader());
        require(net.alexredby.pztoolkitjavapatches.Main.MANNEQUIN_SUPPORTED, "Native engine hashes changed");
        LuaManager.thread = new KahluaThread(LuaManager.platform, LuaManager.env);
        LuaManager.thread.debugOwnerThread = Thread.currentThread();
        LuaManager.caller = new se.krka.kahlua.integration.LuaCaller(new se.krka.kahlua.converter.KahluaConverterManager());
        LuaManager.loaded.remove(FILE); LuaManager.env.rawset("objects", table());
        LuaManager.RunLua(FILE, true);
        KahluaTable properties = (KahluaTable)findRow().rawget("properties");
        require(properties != null && properties.isEmpty(), "Actual RunLua overload not normalized");
        var zones = grid.getCellData(53, 5).mannequinZones; zones.clear();
        Zone repaired = register(grid, properties, false);
        var custom = table(); custom.rawset("Outfit", "CostumeWizard");
        Zone later = register(grid, custom, false);
        require(zones.get(0) == later && zones.get(1) == repaired, "Actual registration hook masked later custom zone");
        set(mannequin, IsoMannequin.class, "outfit", null); fromZone.invoke(mannequin);
        require("CostumeWizard".equals(snapshot(mannequin).get("outfit")), "Woven native zone application changed custom outfit");
        var stale = table(); stale.rawset("name", ""); stale.rawset("type", "Mannequin");
        stale.rawset("x", 13583d); stale.rawset("y", 1299d); stale.rawset("z", 0d); stale.rawset("width", 1d); stale.rawset("height", 1d);
        var objects = table(); objects.rawset(1, stale); LuaManager.env.rawset("objects", objects);
        LuaManager.RunLua(FILE, true);
        require(stale.rawget("properties") == null, "Cached real RunLua changed stale custom row");
    }

    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init();
        LuaManager.platform = new J2SEPlatform(); LuaManager.env = table();
        zombie.ZomboidFileSystem.instance.base.set(Path.of(".").toFile());
        Core.gameMap = "Muldraugh, KY";
        var grid = grid();
        Field unsafeField = sun.misc.Unsafe.class.getDeclaredField("theUnsafe"); unsafeField.setAccessible(true);
        var world = (IsoWorld)((sun.misc.Unsafe)unsafeField.get(null)).allocateInstance(IsoWorld.class);
        set(world, IsoWorld.class, "metaGrid", grid); IsoWorld.instance = world;
        String source = Files.readString(Path.of(FILE));
        var row = loadSource(source); MannequinZoneData.loaded(FILE, null, false);
        require(row.rawget("properties") == null, "Unsupported engine normalized");
        MannequinZoneData.loaded("media/maps/Custom/objects.lua", null, true);
        require(row.rawget("properties") == null, "Custom file normalized");
        MannequinZoneData.loaded(FILE, LuaManager.env.rawget("objects"), true);
        require(row.rawget("properties") == null, "Cached load normalized stale objects");
        changedAsset(row, FILE);
        changedAsset(row, "media/lua/server/metazones/metazoneHandler.lua");
        row.rawset("extra", true); MannequinZoneData.loaded(FILE, null, true);
        require(row.rawget("properties") == null, "Changed row normalized");
        row.rawset("extra", null); Core.gameMap = "Muldraugh, KY;Custom";
        MannequinZoneData.loaded(FILE, null, true);
        require(row.rawget("properties") == null, "Custom map set normalized");
        Core.gameMap = "Muldraugh, KY";

        var sprite = new IsoSprite(); sprite.name = "location_shop_mall_01_67";
        var square = new IsoGridSquare(null, null, 13583, 1299, 0);
        var mannequin = new IsoMannequin(null, square, sprite); square.getObjects().add(mannequin);
        Method fromSprite = IsoMannequin.class.getDeclaredMethod("getPropertiesFromSprite"); fromSprite.setAccessible(true); fromSprite.invoke(mannequin);
        Method fromZone = IsoMannequin.class.getDeclaredMethod("getPropertiesFromZone"); fromZone.setAccessible(true);
        var original = snapshot(mannequin); fromZone.invoke(mannequin);
        require(original.equals(snapshot(mannequin)), "Empty baseline changed");
        var properties = repair(source); Zone repaired = register(grid, properties, true); fromZone.invoke(mannequin);
        require(original.equals(snapshot(mannequin)), "Repaired zone changed native fields");
        require(mannequin.getMannequinScriptName().equals("FemaleWhite03"), "Native sprite script changed");

        var custom = table(); custom.rawset("Outfit", "Police_SWAT");
        Zone first = register(grid, custom, true);
        var zones = grid.getCellData(53, 5).mannequinZones;
        require(zones.get(0) == first && zones.get(1) == repaired, "Later custom zone masked");
        fromZone.invoke(mannequin);
        require("Police_SWAT".equals(snapshot(mannequin).get("outfit")), "Native custom outfit not applied");
        Zone second = register(grid, custom, true);
        require(zones.get(0) == first && zones.get(1) == second && zones.get(2) == repaired, "Custom order changed");
        Zone untracked = register(grid, table(), true);
        require(zones.get(2) == untracked && zones.get(3) == repaired, "Untracked empty zone reordered");
        zones.clear(); Zone earlier = register(grid, custom, true);
        repaired = register(grid, repair(source), true);
        require(zones.get(0) == earlier && zones.get(1) == repaired, "Earlier custom zone masked");

        zones.clear(); properties = repair(source); properties.rawset("Outfit", "Police_SWAT");
        Zone changed = register(grid, properties, true); Zone after = register(grid, table(), true);
        require(zones.get(0) == changed && zones.get(1) == after, "Changed properties treated as no override");
        zones.clear();
        var invalid = loadSource(source); invalid.rawset("x", 13584d); MannequinZoneData.loaded(FILE, null, true);
        require(invalid.rawget("properties") == null, "Wrong coordinates normalized");
        nativeHandler(source, grid);
        woven(grid, mannequin, fromZone);
        System.out.println("MANNEQUIN_ZONE_CHECKS_PASS");
    }
}
