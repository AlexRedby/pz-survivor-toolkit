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
    val SUPPORTED =
        BytecodeSupport.supports(
            "zombie/Lua/LuaManager.class",
            "8613349b0e0fdb663fc16ef4397ca60ef7135925fa6116f92d958ea97d09eb32",
        ) &&
            BytecodeSupport.supports(
                "zombie/Lua/LuaManager\$GlobalObject.class",
                "675c3dad3479ec4e6bf8d0f6aa41aeb2ffcf5570df17d3ac07eab99508221059",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/IsoMetaGrid.class",
                "1e8b016090a41b1388f6eb06c3b63aed8e866416ad15479f0cabe76967dbf824",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/zones/Zone.class",
                "41faa20ceed9764ba0aa32d8fa81f0329d40a1f5da575beb65601e077346e91c",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/objects/IsoMannequin.class",
                "cb7fedda40ac535f0cc7a615fb960d467e193ef3a333e7a0d2f1eeb68ab660e8",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/objects/IsoMannequin\$MannequinZone.class",
                "851d79d504b63729a371e6da1068b141a511e4c594e38e388e0f7fb0829eab9d",
            )

    private const val FILE = "media/maps/Muldraugh, KY/objects.lua"
    private const val HASH = "5b629dad9d595a5cbb3e2062414e3c64cff687880be96155a7d64f2f30d35687"
    private const val HANDLER = "media/lua/server/metazones/metazoneHandler.lua"
    private const val HANDLER_HASH =
        "c8cbc5c52a32405d2822d2601af4227afb5149937c372cd22916a7faba5ff6ba"
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
        if (supported && FILE == file && LuaManager.env != null) LuaManager.env.rawget("objects")
        else null

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
        return count == 7 &&
            "" == row.rawget("name") &&
            "Mannequin" == row.rawget("type") &&
            java.lang.Double.valueOf(13583.0).equals(row.rawget("x")) &&
            java.lang.Double.valueOf(1299.0).equals(row.rawget("y")) &&
            java.lang.Double.valueOf(0.0).equals(row.rawget("z")) &&
            java.lang.Double.valueOf(1.0).equals(row.rawget("width")) &&
            java.lang.Double.valueOf(1.0).equals(row.rawget("height"))
    }

    @JvmStatic
    fun registered(grid: IsoMetaGrid?, properties: KahluaTable?, result: Zone?) {
        if (
            properties != null &&
                pending.remove(properties) &&
                properties.isEmpty() &&
                result is MannequinZone &&
                result.x == 13583 &&
                result.y == 1299 &&
                result.z == 0 &&
                result.w == 1 &&
                result.h == 1 &&
                noOverrides(result)
        ) {
            repaired.add(result)
            println(
                "[PZToolkitJavaPatches] Registered native mannequin zone without overrides at 13583, 1299, 0",
            )
        }
        if (repaired.isEmpty()) return
        val cell = (grid ?: throw NullPointerException()).getCellData(53, 5) ?: return
        val zones = cell.mannequinZones
        // Native lookup uses the first containing zone; this no-override row must never hide a
        // custom zone.
        for (i in zones.size - 1 downTo 0) {
            val zone = zones[i]
            if (repaired.contains(zone) && noOverrides(zone)) {
                zones.removeAt(i)
                zones.add(zone)
            }
        }
    }

    private fun noOverrides(zone: MannequinZone): Boolean =
        zone.female == -1 &&
            zone.dir == null &&
            zone.mannequinScript == null &&
            zone.outfit == null &&
            zone.skin == null &&
            zone.pose == null
}
