package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.util.Collections
import java.util.HexFormat
import java.util.WeakHashMap
import se.krka.kahlua.vm.KahluaTable
import zombie.Lua.LuaManager
import zombie.ZomboidFileSystem
import zombie.iso.IsoMetaGrid
import zombie.iso.objects.IsoMannequin.MannequinZone
import zombie.iso.zones.Zone

/** Weak tracking is accessed through MannequinZoneData's synchronized Java entry points. */
object MannequinZoneDataLogic {
    @JvmField
    val SUPPORTED = BytecodeSupport.supports("zombie/Lua/LuaManager.class",
            "dcaad0082ca27a15550c7d0a6e14b3aeb71f634a14f32123dec620df180c646d")
        && BytecodeSupport.supports("zombie/Lua/LuaManager\$GlobalObject.class",
            "80ecbd3bd702db2f992db6cba7cb09c32d775fa6f2a3297e0460874ff5ba20c7")
        && BytecodeSupport.supports("zombie/iso/IsoMetaGrid.class",
            "cdd50bb0a393c766d25c9dcbc5f7e929d7e10a6b9c9b95e22c3bae94b3b5b1f9")
        && BytecodeSupport.supports("zombie/iso/zones/Zone.class",
            "41faa20ceed9764ba0aa32d8fa81f0329d40a1f5da575beb65601e077346e91c")
        && BytecodeSupport.supports("zombie/iso/objects/IsoMannequin.class",
            "158b696a5ff5ee99e7c60cbd17d7055b6d7c9afbc5c1595e34f2fbcb4feef5e1")
        && BytecodeSupport.supports("zombie/iso/objects/IsoMannequin\$MannequinZone.class",
            "34d053c48f0522dbeb73f69daa45683c0feb1ff2181b83ef6d8dcfd53aa3848d")

    private const val FILE = "media/maps/Muldraugh, KY/objects.lua"
    private const val HASH = "bb2af79f1814265f9ad65bc9b55b0c723cc5a372d92ccc65aae3ffc9acf29572"
    private const val HANDLER = "media/lua/server/metazones/metazoneHandler.lua"
    private const val HANDLER_HASH = "c8cbc5c52a32405d2822d2601af4227afb5149937c372cd22916a7faba5ff6ba"
    private val pending = Collections.newSetFromMap(WeakHashMap<KahluaTable, Boolean>())
    private val repaired = Collections.newSetFromMap(WeakHashMap<MannequinZone, Boolean>())

    @JvmStatic
    fun prepare() {
        if (SUPPORTED) {
            LuaManager::class.java.name
            IsoMetaGrid::class.java.name
        }
    }

    @JvmStatic
    fun previous(file: String?, supported: Boolean): Any? =
        if (supported && FILE == file && LuaManager.env != null) LuaManager.env.rawget("objects") else null

    @JvmStatic
    fun loaded(file: String?, previousObjects: Any?, supported: Boolean) {
        if (!supported || FILE != file || LuaManager.env == null) return
        val currentObjects = LuaManager.env.rawget("objects")
        if (currentObjects === previousObjects || currentObjects !is KahluaTable) return
        val directories = LuaManager.GlobalObject.getLotDirectories()
        if (directories.size != 1 || directories[0] != "Muldraugh, KY") return
        try {
            if (!matches(FILE, HASH) || !matches(HANDLER, HANDLER_HASH)) return
        } catch (error: Exception) {
            System.err.println("[PZToolkitJavaPatches] Kept native mannequin data: $error")
            return
        }
        var found: KahluaTable? = null
        val entries = currentObjects.iterator()
        while (entries.advance()) {
            val row = entries.value
            if (row !is KahluaTable || !exactRow(row)) continue
            if (found != null) return
            found = row
        }
        val row = found ?: return
        val properties = LuaManager.platform.newTable()
        pending.add(properties)
        row.rawset("properties", properties)
    }

    private fun matches(file: String, hash: String): Boolean {
        val bytes = Files.readAllBytes(Path.of(ZomboidFileSystem.instance.getString(file)))
        return hash == HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes))
    }

    private fun exactRow(row: KahluaTable): Boolean {
        var count = 0
        val fields = row.iterator()
        while (fields.advance()) count++
        return count == 7 && "" == row.rawget("name") && "Mannequin" == row.rawget("type")
            && java.lang.Double.valueOf(13583.0).equals(row.rawget("x"))
            && java.lang.Double.valueOf(1299.0).equals(row.rawget("y"))
            && java.lang.Double.valueOf(0.0).equals(row.rawget("z"))
            && java.lang.Double.valueOf(1.0).equals(row.rawget("width"))
            && java.lang.Double.valueOf(1.0).equals(row.rawget("height"))
    }

    @JvmStatic
    fun registered(grid: IsoMetaGrid?, properties: KahluaTable?, result: Zone?) {
        if (properties != null && pending.remove(properties) && properties.isEmpty()
            && result is MannequinZone && result.x == 13583 && result.y == 1299 && result.z == 0
            && result.w == 1 && result.h == 1 && noOverrides(result)) {
            repaired.add(result)
            println("[PZToolkitJavaPatches] Registered native mannequin zone without overrides at 13583, 1299, 0")
        }
        if (repaired.isEmpty()) return
        val cell = (grid ?: throw NullPointerException()).getCellData(53, 5) ?: return
        val zones = cell.mannequinZones
        // Native lookup uses the first containing zone; this no-override row must never hide a custom zone.
        for (i in zones.size - 1 downTo 0) {
            val zone = zones[i]
            if (repaired.contains(zone) && noOverrides(zone)) {
                zones.removeAt(i)
                zones.add(zone)
            }
        }
    }

    private fun noOverrides(zone: MannequinZone): Boolean =
        zone.female.toInt() == -1 && zone.dir == null && zone.mannequinScript == null
            && zone.outfit == null && zone.skin == null && zone.pose == null
}
