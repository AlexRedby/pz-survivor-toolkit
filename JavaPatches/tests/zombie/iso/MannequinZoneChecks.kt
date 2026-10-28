package zombie.iso

import java.io.StringReader
import java.lang.reflect.Method
import java.lang.reflect.Modifier
import java.nio.file.Files
import java.nio.file.Path
import java.util.LinkedHashMap
import java.util.Locale
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.MannequinZoneData
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.KahluaTable
import se.krka.kahlua.vm.KahluaThread
import sun.misc.Unsafe
import zombie.Lua.LuaManager
import zombie.core.Core
import zombie.iso.objects.IsoMannequin
import zombie.iso.sprite.IsoSprite
import zombie.iso.zones.Zone

object MannequinZoneChecks {
    private const val FILE = "media/maps/Muldraugh, KY/objects.lua"

    private fun require(condition: Boolean, message: String) {
        if (!condition) throw AssertionError(message)
    }

    private fun table(): KahluaTableImpl = KahluaTableImpl(LinkedHashMap<Any, Any>())

    private fun set(instance: Any, type: Class<*>, name: String, value: Any?) {
        val field = type.getDeclaredField(name).apply { isAccessible = true }
        field.set(instance, value)
    }

    private fun grid(): IsoMetaGrid {
        val grid = IsoMetaGrid()
        grid.minX = 53
        grid.maxX = 53
        grid.minY = 5
        grid.maxY = 5
        set(grid, IsoMetaGrid::class.java, "width", 1)
        set(grid, IsoMetaGrid::class.java, "height", 1)
        set(grid, IsoMetaGrid::class.java, "grid", arrayOf(arrayOf(IsoMetaCell(53, 5))))
        return grid
    }

    private fun loadSource(source: String): KahluaTable {
        val closure = LuaCompiler.loadis(StringReader(source), FILE, LuaManager.env)
        KahluaThread(LuaManager.platform, LuaManager.env).call(closure, null, null, null)
        return findRow()
    }

    private fun findRow(): KahluaTable {
        val objects = LuaManager.env.rawget("objects") as KahluaTable
        val entries = objects.iterator()
        while (entries.advance()) {
            val row = entries.value as KahluaTable
            if (
                java.lang.Double.valueOf(13583.0).equals(row.rawget("x")) &&
                    java.lang.Double.valueOf(1299.0).equals(row.rawget("y")) &&
                    "Mannequin" == row.rawget("type")
            )
                return row
        }
        throw AssertionError("Native mannequin row absent")
    }

    private fun register(grid: IsoMetaGrid, properties: KahluaTable?, patched: Boolean): Zone? {
        val result = grid.registerMannequinZone("", "Mannequin", 13583, 1299, 0, 1, 1, properties)
        if (patched) MannequinZoneData.registered(grid, properties, result)
        return result
    }

    private fun snapshot(instance: IsoMannequin): Map<String, Any?> {
        val result = LinkedHashMap<String, Any?>()
        for (field in IsoMannequin::class.java.declaredFields) if (
            !Modifier.isStatic(field.modifiers)
        ) {
            field.isAccessible = true
            result[field.name] = field.get(instance)
        }
        val dir = IsoObject::class.java.getDeclaredField("dir").apply { isAccessible = true }
        result["direction"] = dir.get(instance)
        return result
    }

    private fun repair(source: String): KahluaTable {
        val row = loadSource(source)
        MannequinZoneData.loaded(FILE, null, true)
        require(row.rawget("properties") is KahluaTable, "Native row not normalized")
        val properties = row.rawget("properties") as KahluaTable
        require(properties.isEmpty(), "Appearance properties invented")
        return properties
    }

    private fun changedAsset(row: KahluaTable, file: String) {
        val modified = Files.createTempFile("pz-mannequin-negative-", ".lua")
        val key = file.lowercase(Locale.ENGLISH)
        val files = zombie.ZomboidFileSystem.instance.activeFileMap
        val previous = files.put(key, modified.toString())
        try {
            Files.writeString(modified, "-- modified asset")
            require(
                zombie.ZomboidFileSystem.instance.getString(file) == modified.toString(),
                "Asset override fixture not active",
            )
            MannequinZoneData.loaded(FILE, null, true)
            require(row.rawget("properties") == null, "Modified asset normalized: $file")
        } finally {
            if (previous == null) files.remove(key) else files.put(key, previous)
            Files.delete(modified)
        }
    }

    private fun nativeHandler(source: String, grid: IsoMetaGrid) {
        val errors = intArrayOf(0)
        val registrations = intArrayOf(0)
        val luaLog = table()
        luaLog.rawset(
            "error",
            JavaFunction { frame, _ ->
                require(
                    frame.get(1).toString().contains("Mannequin zone missing properties"),
                    "Unexpected native diagnostic",
                )
                errors[0]++
                0
            },
        )
        val debug = table()
        debug.rawset("Lua", luaLog)
        LuaManager.env.rawset("DebugType", debug)
        val world = table()
        world.rawset(
            "registerMannequinZone",
            JavaFunction { frame, _ ->
                register(grid, frame.get(8) as KahluaTable?, true)
                registrations[0]++
                0
            },
        )
        LuaManager.env.rawset(
            "getWorld",
            JavaFunction { frame, _ ->
                frame.push(world)
                1
            },
        )
        var handler = Files.readString(Path.of("media/lua/server/metazones/metazoneHandler.lua"))
        handler =
            handler.substring(0, handler.indexOf("local function handleRoomTone")) +
                "\nreturn handleMannequinZone"
        val thread = KahluaThread(LuaManager.platform, LuaManager.env)
        val function =
            thread.call(
                LuaCompiler.loadis(StringReader(handler), "native-handler", LuaManager.env),
                null,
                null,
                null,
            )
        thread.call(function, FILE, loadSource(source), null)
        require(
            errors[0] == 1 && registrations[0] == 0,
            "Original malformed zone did not retain native error",
        )
        repair(source)
        thread.call(function, FILE, findRow(), null)
        require(
            errors[0] == 1 && registrations[0] == 1,
            "Normalized row did not use native registration",
        )
        val unknown = loadSource(source)
        unknown.rawset("x", 13584.0)
        MannequinZoneData.loaded(FILE, null, true)
        thread.call(function, FILE, unknown, null)
        require(
            errors[0] == 2 && registrations[0] == 1,
            "Unknown malformed zone diagnostic suppressed",
        )
        grid.getCellData(53, 5).mannequinZones.clear()
    }

    private fun woven(grid: IsoMetaGrid, mannequin: IsoMannequin, fromZone: Method) {
        PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            MannequinZoneChecks::class.java.classLoader,
        )
        require(MannequinZoneData.SUPPORTED, "Native engine hashes changed")
        LuaManager.thread = KahluaThread(LuaManager.platform, LuaManager.env)
        LuaManager.thread.debugOwnerThread = Thread.currentThread()
        LuaManager.caller =
            se.krka.kahlua.integration.LuaCaller(se.krka.kahlua.converter.KahluaConverterManager())
        LuaManager.loaded.remove(FILE)
        LuaManager.env.rawset("objects", table())
        LuaManager.RunLua(FILE, true)
        val properties = findRow().rawget("properties") as KahluaTable?
        require(properties != null && properties.isEmpty(), "Actual RunLua overload not normalized")
        val zones = grid.getCellData(53, 5).mannequinZones
        zones.clear()
        val repaired = register(grid, properties, false)
        val custom = table()
        custom.rawset("Outfit", "CostumeWizard")
        val later = register(grid, custom, false)
        require(
            zones[0] === later && zones[1] === repaired,
            "Actual registration hook masked later custom zone",
        )
        set(mannequin, IsoMannequin::class.java, "outfit", null)
        fromZone.invoke(mannequin)
        require(
            "CostumeWizard" == snapshot(mannequin)["outfit"],
            "Woven native zone application changed custom outfit",
        )
        val stale = table()
        stale.rawset("name", "")
        stale.rawset("type", "Mannequin")
        stale.rawset("x", 13583.0)
        stale.rawset("y", 1299.0)
        stale.rawset("z", 0.0)
        stale.rawset("width", 1.0)
        stale.rawset("height", 1.0)
        val objects = table()
        objects.rawset(1, stale)
        LuaManager.env.rawset("objects", objects)
        LuaManager.RunLua(FILE, true)
        require(stale.rawget("properties") == null, "Cached real RunLua changed stale custom row")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = table()
        zombie.ZomboidFileSystem.instance.base.set(Path.of(".").toFile())
        Core.gameMap = "Muldraugh, KY"
        val grid = grid()
        val unsafeField =
            Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }
        val world =
            (unsafeField.get(null) as Unsafe).allocateInstance(IsoWorld::class.java) as IsoWorld
        set(world, IsoWorld::class.java, "metaGrid", grid)
        IsoWorld.instance = world
        val source = Files.readString(Path.of(FILE))
        val row = loadSource(source)
        MannequinZoneData.loaded(FILE, null, false)
        require(row.rawget("properties") == null, "Unsupported engine normalized")
        MannequinZoneData.loaded("media/maps/Custom/objects.lua", null, true)
        require(row.rawget("properties") == null, "Custom file normalized")
        MannequinZoneData.loaded(FILE, LuaManager.env.rawget("objects"), true)
        require(row.rawget("properties") == null, "Cached load normalized stale objects")
        changedAsset(row, FILE)
        changedAsset(row, "media/lua/server/metazones/metazoneHandler.lua")
        row.rawset("extra", true)
        MannequinZoneData.loaded(FILE, null, true)
        require(row.rawget("properties") == null, "Changed row normalized")
        row.rawset("extra", null)
        Core.gameMap = "Muldraugh, KY;Custom"
        MannequinZoneData.loaded(FILE, null, true)
        require(row.rawget("properties") == null, "Custom map set normalized")
        Core.gameMap = "Muldraugh, KY"

        val sprite = IsoSprite()
        sprite.name = "location_shop_mall_01_67"
        val square = IsoGridSquare(null, null, 13583, 1299, 0)
        val mannequin = IsoMannequin(null, square, sprite)
        square.objects.add(mannequin)
        val fromSprite =
            IsoMannequin::class.java.getDeclaredMethod("getPropertiesFromSprite").apply {
                isAccessible = true
            }
        fromSprite.invoke(mannequin)
        val fromZone =
            IsoMannequin::class.java.getDeclaredMethod("getPropertiesFromZone").apply {
                isAccessible = true
            }
        val original = snapshot(mannequin)
        fromZone.invoke(mannequin)
        require(original == snapshot(mannequin), "Empty baseline changed")
        var properties = repair(source)
        var repaired = register(grid, properties, true)
        fromZone.invoke(mannequin)
        require(original == snapshot(mannequin), "Repaired zone changed native fields")
        require(mannequin.mannequinScriptName == "FemaleWhite03", "Native sprite script changed")

        val custom = table()
        custom.rawset("Outfit", "Police_SWAT")
        val first = register(grid, custom, true)
        val zones = grid.getCellData(53, 5).mannequinZones
        require(zones[0] === first && zones[1] === repaired, "Later custom zone masked")
        fromZone.invoke(mannequin)
        require("Police_SWAT" == snapshot(mannequin)["outfit"], "Native custom outfit not applied")
        val second = register(grid, custom, true)
        require(
            zones[0] === first && zones[1] === second && zones[2] === repaired,
            "Custom order changed",
        )
        val untracked = register(grid, table(), true)
        require(zones[2] === untracked && zones[3] === repaired, "Untracked empty zone reordered")
        zones.clear()
        val earlier = register(grid, custom, true)
        repaired = register(grid, repair(source), true)
        require(zones[0] === earlier && zones[1] === repaired, "Earlier custom zone masked")

        zones.clear()
        properties = repair(source)
        properties.rawset("Outfit", "Police_SWAT")
        val changed = register(grid, properties, true)
        val after = register(grid, table(), true)
        require(
            zones[0] === changed && zones[1] === after,
            "Changed properties treated as no override",
        )
        zones.clear()
        val invalid = loadSource(source)
        invalid.rawset("x", 13584.0)
        MannequinZoneData.loaded(FILE, null, true)
        require(invalid.rawget("properties") == null, "Wrong coordinates normalized")
        nativeHandler(source, grid)
        woven(grid, mannequin, fromZone)
        println("MANNEQUIN_ZONE_CHECKS_PASS")
    }
}
