package zombie.basements

import java.nio.BufferUnderflowException
import java.nio.ByteBuffer
import java.nio.file.Files
import java.nio.file.Path
import java.util.Locale
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.BasementHallKey
import net.alexredby.pztoolkitjavapatches.Main
import zombie.ZomboidFileSystem
import zombie.core.Core
import zombie.iso.*
import zombie.iso.areas.IsoBuilding
import zombie.iso.areas.IsoRoom
import zombie.basements.BasementRoomLookupChecks.flags
import zombie.basements.BasementRoomLookupChecks.field
import zombie.basements.BasementRoomLookupChecks.require

object BasementHallKeyChecks {
    private const val CX = 41
    private const val CY = 37
    private const val HEADER = "media/maps/Muldraugh, KY/41_37.lotheader"
    private const val ACCESS = "media/basement_access/ba_exterior_north_westside_13.pzby"
    private const val ORIGINAL = BasementHallKey.ORIGINAL_KEY
    private const val SPLIT = BasementHallKey.HALL_KEY

    private fun room(id: Long, name: String, x: Int, y: Int): RoomDef = RoomDef(id, name).apply {
        rects.add(RoomDef.RoomRect(x, y, 1, 4))
        CalculateBounds()
        metaId = calculateMetaID(CX, CY)
    }

    private fun state(room: RoomDef): List<Any?> = listOf(room.id, room.name, room.level, room.x, room.y,
        room.x2, room.y2, room.area, room.building, ArrayList(room.rects), ArrayList(room.objects), flags(room))

    private fun invoke(owner: Any, name: String, types: Array<Class<*>>, vararg args: Any?) {
        owner.javaClass.getDeclaredMethod(name, *types).apply { isAccessible = true }.invoke(owner, *args)
    }

    private fun reindex(owner: Any, cell: IsoMetaCell) {
        invoke(owner, "recalculateBuildingAndRoomIDs", arrayOf(IsoMetaCell::class.java), cell)
    }

    private class Fixture {
        val grid: IsoMetaGrid = IsoWorld.instance.metaGrid
        val cell = IsoMetaCell(CX, CY)
        val receiving = BuildingDef()
        val incoming = BuildingDef()
        val original: RoomDef
        val access = room(0, "hall", 10707, 9484)
        val cachedRoom = IsoRoom()
        val cachedBuilding = IsoBuilding()
        val receipt = IsoChunk(null as IsoCell?)

        init {
            grid.minX = CX
            grid.maxX = CX
            grid.minY = CY
            grid.maxY = CY
            field(grid, "grid", arrayOf(arrayOf(cell)))
            field(grid, "width", 1)
            field(grid, "height", 1)
            cell.info = LotHeader(CX, CY)
            for (i in 0 until 108) {
                val room = room(RoomID.makeID(CX, CY, i), if (i == 107) "hall" else "unrelated",
                    if (i == 107) 10707 else 10720 + (i % 10) * 2, if (i == 107) 9484 else 9500 + (i / 10) * 5)
                cell.roomList.add(room)
                cell.rooms[room.id] = room
                cell.roomByMetaId.put(room.metaId, room)
            }
            original = cell.roomList[107]
            require(original.metaId == ORIGINAL && access.metaId == ORIGINAL, "stock collision geometry differs")
            require(original.x2 == 10708 && original.y2 == 9488 && original.area == 4, "native hall bounds differ")
            for (i in 0 until 16) {
                val prefix = BuildingDef()
                prefix.id = BuildingID.makeID(CX, CY, i)
                cell.buildings.add(prefix)
            }
            receiving.id = BuildingID.makeID(CX, CY, 16)
            original.building = receiving
            receiving.rooms.add(original)
            receiving.CalculateBounds(ArrayList())
            receiving.metaId = receiving.calculateMetaID(CX, CY)
            cell.buildings.add(receiving)
            cell.buildingByMetaId.put(receiving.metaId, receiving)
            access.building = incoming
            incoming.rooms.add(access)
            incoming.CalculateBounds(ArrayList())
            cachedRoom.def = original
            cachedBuilding.def = receiving
            cell.isoRooms[original.id] = cachedRoom
            cell.isoBuildings[receiving.id] = cachedBuilding
            receipt.addSpawnedRoom(original.id)
        }

        fun split() {
            val rooms = ArrayList(cell.roomList)
            val runtime = HashMap(cell.rooms)
            val buildings = ArrayList(cell.buildings)
            val buildingIndex = gnu.trove.map.hash.TLongObjectHashMap(cell.buildingByMetaId)
            val roomCache = HashMap(cell.isoRooms)
            val buildingCache = HashMap(cell.isoBuildings)
            val before = state(original)
            val accessBefore = state(access)
            require(BasementHallKey.beforeMerge(incoming, receiving, true), "stock hall was not split")
            require(cell.roomList == rooms && cell.rooms == runtime && cell.buildings == buildings &&
                cell.buildingByMetaId == buildingIndex && cell.isoRooms == roomCache && cell.isoBuildings == buildingCache &&
                before == state(original) && accessBefore == state(access), "split changed IDs/layout/owner/caches/flags")
            require(original.metaId == SPLIT && cell.roomByMetaId.get(SPLIT) === original &&
                !cell.roomByMetaId.containsKey(ORIGINAL) && access.metaId == ORIGINAL, "wrong premerge routing")
            require(receipt.isSpawnedRoom(original.id), "split invalidated spawn receipt")
            require(!BasementHallKey.beforeMerge(incoming, receiving, true), "split was not idempotent")
        }

        fun merge() {
            val before = cell.roomList.map { it.id }.toLongArray()
            val unchanged = state(original)
            invoke(Basements(), "mergeBuildings", arrayOf(BuildingDef::class.java, BuildingDef::class.java), incoming, receiving)
            require(cell.roomList.size == 109 && cell.roomList[107] === original && cell.roomList[108] === access,
                "native merge replaced/skipped/aliased a room")
            for (i in before.indices) require(cell.roomList[i].id == before[i], "existing runtime ID shifted")
            require(access.id == RoomID.makeID(CX, CY, 108) && access.building === receiving &&
                receiving.id == BuildingID.makeID(CX, CY, 16) && receiving.rooms == listOf(original, access),
                "native merged IDs/owner changed")
            require(unchanged == state(original) && cell.isoRooms[original.id] === cachedRoom &&
                cell.isoBuildings[receiving.id] === cachedBuilding && receipt.isSpawnedRoom(original.id),
                "native merge lost original state/cache/receipt")
            require(cell.roomByMetaId.get(ORIGINAL) === access, "legacy records no longer route to access hall")
        }

        fun save(): ByteBuffer = ByteBuffer.allocate(32768).apply {
            grid.savePart(this, 0, false)
            flip()
        }

        fun load(saved: ByteBuffer) {
            val bytes = saved.duplicate()
            val count = bytes.getInt(24)
            bytes.position(0)
            bytes.limit(28 + count * 10)
            try {
                grid.load(bytes)
                throw AssertionError("room section did not end at building count")
            } catch (_: BufferUnderflowException) {
                require(bytes.position() == bytes.limit(), "unexpected native room-load boundary")
            }
        }
    }

    private fun merged(split: Boolean): Fixture = Fixture().apply {
        if (split) this.split()
        merge()
    }

    private fun roundTrips() {
        for (hall in 0 until 16) for (access in 0 until 16) {
            val nativeFixture = merged(false)
            flags(nativeFixture.original, hall)
            flags(nativeFixture.access, access)
            val legacy = nativeFixture.save()
            flags(nativeFixture.original, 0)
            flags(nativeFixture.access, 0)
            nativeFixture.load(legacy)
            val nativeHall = flags(nativeFixture.original)
            val nativeAccess = flags(nativeFixture.access)
            var split = merged(true)
            split.load(legacy)
            require(flags(split.original) == nativeHall && flags(split.access) == nativeAccess,
                "legacy native flag routing differs for $hall/$access")
            flags(split.original, hall)
            flags(split.access, access)
            repeat(2) { pass ->
                val saved = split.save()
                split = merged(true)
                split.load(saved)
                require(flags(split.original) == hall && flags(split.access) == access,
                    "independent flags lost after reconstruction, pass=$pass")
            }
        }
        val split = merged(true)
        flags(split.original, 1)
        flags(split.access, 14)
        val saved = split.save()
        val downgrade = merged(false)
        downgrade.load(saved)
        require(flags(downgrade.original) == 0 && flags(downgrade.access) == 14,
            "unpatched downgrade/save dependency no longer reproduced")
    }

    private fun rejected(label: String, change: (Fixture) -> Unit) {
        val fixture = Fixture()
        change(fixture)
        val before = fixture.original.metaId
        val index = gnu.trove.map.hash.TLongObjectHashMap(fixture.cell.roomByMetaId)
        require(!BasementHallKey.beforeMerge(fixture.incoming, fixture.receiving, true), "unguarded split: $label")
        require(fixture.original.metaId == before && fixture.cell.roomByMetaId == index, "rejected split mutated: $label")
    }

    private fun changedAsset(asset: String, missing: Boolean) {
        val modified = Files.createTempFile("pz-hall-key-negative-", ".bin")
        val files = ZomboidFileSystem.instance.activeFileMap
        val key = asset.lowercase(Locale.ENGLISH)
        val previous = files.put(key, modified.toString())
        try {
            if (missing) Files.delete(modified) else Files.writeString(modified, "modified native source")
            require(ZomboidFileSystem.instance.getString(asset) == modified.toString(), "asset override inactive")
            rejected(asset + if (missing) " missing" else " changed") { }
        } finally {
            if (previous == null) files.remove(key) else files[key] = previous
            Files.deleteIfExists(modified)
        }
    }

    private fun calculationRefused(fixture: Fixture, cellX: Int, cellY: Int, label: String) {
        val before = state(fixture.original)
        val accessBefore = state(fixture.access)
        val key = fixture.original.metaId
        val accessKey = fixture.access.metaId
        val index = gnu.trove.map.hash.TLongObjectHashMap(fixture.cell.roomByMetaId)
        try {
            BasementHallKey.calculated(fixture.original, cellX, cellY, ORIGINAL, true)
            throw AssertionError("calculation did not refuse: $label")
        } catch (_: IllegalStateException) {
            require(key == fixture.original.metaId && before == state(fixture.original) &&
                accessKey == fixture.access.metaId && accessBefore == state(fixture.access) && fixture.cell.roomByMetaId == index,
                "refused calculation mutated state: $label")
        }
    }

    private fun guards() {
        var fixture = Fixture()
        require(!BasementHallKey.beforeMerge(fixture.incoming, fixture.receiving, false), "unsupported split")
        require(!BasementHallKey.beforeMerge(null, fixture.receiving, true) &&
            !BasementHallKey.beforeMerge(fixture.incoming, null, true) &&
            !BasementHallKey.beforeMerge(fixture.receiving, fixture.receiving, true), "invalid buildings accepted")
        rejected("different cell") { it.receiving.id = BuildingID.makeID(40, CY, 16) }
        rejected("different building") { it.receiving.id = BuildingID.makeID(CX, CY, 15) }
        rejected("custom incoming") { it.incoming.setUserDefined(true) }
        rejected("custom receiving") { it.receiving.setUserDefined(true) }
        rejected("custom room") { it.original.userDefined = true }
        rejected("extra incoming") { it.incoming.rooms.add(room(1, "other", 10710, 9490)) }
        rejected("incoming outside") { it.incoming.emptyoutside.add(room(1, "emptyoutside", 10710, 9490)) }
        rejected("incoming ID") { it.access.id = 1 }
        rejected("incoming owner") { it.access.building = it.receiving }
        rejected("name") { it.original.name = "custom" }
        rejected("level") { it.original.level = 1 }
        rejected("bounds") { it.original.x2++ }
        rejected("rectangle") { it.original.rects.add(RoomDef.RoomRect(10707, 9484, 1, 4)) }
        rejected("wrong original ID") { it.original.id++ }
        rejected("wrong original key") { it.original.metaId++ }
        rejected("missing header") { it.cell.info = null }
        rejected("unregistered building") { it.cell.buildings.remove(it.receiving) }
        rejected("runtime index") { it.cell.rooms.remove(it.original.id) }
        rejected("persistent index") { it.cell.roomByMetaId.remove(ORIGINAL) }
        rejected("occupied index") { it.cell.roomByMetaId.put(SPLIT, it.access) }
        rejected("occupied null entry") { it.cell.roomByMetaId.put(SPLIT, null) }
        rejected("occupied list") { it.cell.roomList[0].metaId = SPLIT }
        rejected("duplicate native key") { it.cell.roomList[0].metaId = ORIGINAL }
        Core.gameMap = "Muldraugh, KY;Custom"
        try {
            rejected("additional map") { }
        } finally {
            Core.gameMap = "Muldraugh, KY"
        }
        for (asset in listOf(HEADER, ACCESS)) {
            changedAsset(asset, false)
            changedAsset(asset, true)
        }
        fixture = Fixture()
        fixture.split()
        require(BasementHallKey.calculated(fixture.original, CX, CY, ORIGINAL, true) == SPLIT, "marked hall key lost")
        fixture.cell.roomByMetaId.remove(SPLIT)
        require(BasementHallKey.calculated(fixture.original, CX, CY, ORIGINAL, true) == SPLIT, "unoccupied marked key lost")
        fixture.cell.roomByMetaId.put(SPLIT, null)
        calculationRefused(fixture, CX, CY, "occupied null entry")
        fixture.cell.roomByMetaId.remove(SPLIT)
        require(BasementHallKey.calculated(fixture.access, CX, CY, ORIGINAL, true) == ORIGINAL, "access key changed")
        require(BasementHallKey.calculated(fixture.original, CX, CY, ORIGINAL, false) == ORIGINAL, "unsupported retention")
        calculationRefused(fixture, CX + 1, CY, "missing destination cell")
        require(BasementHallKey.calculated(fixture.original, CX, CY, 123, true) == SPLIT, "assigned key followed changed native key")
        fixture.original.metaId = 0
        require(BasementHallKey.calculated(fixture.original, CX, CY, ORIGINAL, true) == SPLIT,
            "adopted identity lost its assigned key after native/editor marker reset")
        fixture.original.metaId = SPLIT
        val unregistered = room(0, "hall", 10707, 9484)
        unregistered.building = fixture.receiving
        unregistered.metaId = SPLIT
        require(BasementHallKey.calculated(unregistered, CX, CY, ORIGINAL, true) == ORIGINAL,
            "manually marked unregistered room adopted")
        unregistered.userDefined = true
        require(BasementHallKey.calculated(unregistered, CX, CY, 123, true) == 123L, "unregistered custom room changed")
        fixture.original.userDefined = true
        fixture.receiving.setUserDefined(true)
        fixture.original.name = "custom"
        fixture.original.rects.clear()
        fixture.original.rects.add(RoomDef.RoomRect(10708, 9485, 2, 5))
        fixture.original.CalculateBounds()
        require(BasementHallKey.calculated(fixture.original, CX, CY, 123, true) == SPLIT,
            "adopted room lost its assigned key after name/shape/custom edits")
        fixture.cell.roomByMetaId.put(SPLIT, fixture.access)
        calculationRefused(fixture, CX, CY, "occupied index")
        fixture.cell.roomByMetaId.remove(SPLIT)
        fixture.cell.roomList[0].metaId = SPLIT
        calculationRefused(fixture, CX, CY, "unindexed occupied key")
        fixture.cell.roomList[0].metaId = 0
        val destination = IsoMetaCell(CX + 1, CY)
        destination.info = LotHeader(CX + 1, CY)
        fixture.grid.maxX = CX + 1
        field(fixture.grid, "grid", arrayOf(arrayOf(fixture.cell), arrayOf(destination)))
        field(fixture.grid, "width", 2)
        require(BasementHallKey.calculated(fixture.original, CX + 1, CY, 123, true) == SPLIT,
            "adopted room lost its assigned key in an existing destination cell")
    }

    private fun woven() {
        Main.main(emptyArray())
        require(BasementHallKey.SUPPORTED, "native bytecode is unsupported")
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", BasementHallKeyChecks::class.java.classLoader)
        for (role in 0 until 3) {
            zombie.network.GameServer.server = role == 1
            zombie.network.GameClient.client = role == 2
            Core.gameMap = "Muldraugh, KY"
            zombie.network.GameClient.gameMap = Core.gameMap
            zombie.network.GameServer.gameMap = Core.gameMap
            var fixture = merged(false)
            require(fixture.original.metaId == SPLIT && fixture.cell.roomByMetaId.get(SPLIT) === fixture.original,
                "woven merge did not split stock hall, role=$role")
            require(fixture.original.calculateMetaID(CX, CY) == SPLIT && fixture.access.calculateMetaID(CX, CY) == ORIGINAL,
                "woven calculateMetaID lost original/access distinction")
            flags(fixture.original, 1)
            flags(fixture.access, 14)
            val saved = fixture.save()
            fixture = merged(false)
            fixture.load(saved)
            require(flags(fixture.original) == 1 && flags(fixture.access) == 14, "woven reconstructed save lost flags")
            val tail = room(0, "unrelated", 10707, 9490)
            tail.building = fixture.receiving
            invoke(Basements(), "mergeRoomsOntoMetaCell", arrayOf(ArrayList::class.java, IsoMetaCell::class.java),
                arrayListOf(tail), fixture.cell)
            require(tail.id == RoomID.makeID(CX, CY, 109), "later room ID shifted by split")
            reindex(Basements(), fixture.cell)
            require(fixture.original.id == RoomID.makeID(CX, CY, 107) && fixture.original.calculateMetaID(CX, CY) == SPLIT &&
                fixture.cell.isoRooms[fixture.original.id] === fixture.cachedRoom && fixture.receipt.isSpawnedRoom(fixture.original.id),
                "native reindex lost room/cache/receipt")
        }
        zombie.network.GameServer.server = false
        zombie.network.GameClient.client = false
        val fixture = merged(false)
        flags(fixture.original, 1)
        flags(fixture.access, 14)
        fixture.original.name = "edited-hall"
        fixture.original.rects.clear()
        fixture.original.rects.add(RoomDef.RoomRect(10708, 9485, 2, 5))
        fixture.original.CalculateBounds()
        fixture.cell.roomList.remove(fixture.original)
        fixture.cell.rooms.remove(fixture.original.id)
        fixture.cell.roomByMetaId.remove(SPLIT)
        fixture.cell.isoRooms.clear()
        val regions = zombie.iso.areas.isoregion.metagrid.WorldRegionToMetaGrid()
        reindex(regions, fixture.cell)
        invoke(zombie.buildingRooms.BREBuilding(), "mergeRoomsOntoMetaCell", arrayOf(ArrayList::class.java, IsoMetaCell::class.java),
            arrayListOf(fixture.original), fixture.cell)
        reindex(regions, fixture.cell)
        require(fixture.original.id == RoomID.makeID(CX, CY, 108) && fixture.original.metaId == SPLIT &&
            fixture.cell.roomByMetaId.get(SPLIT) === fixture.original && fixture.cell.roomByMetaId.get(ORIGINAL) === fixture.access &&
            fixture.cell.rooms[fixture.original.id] === fixture.original && fixture.original.building === fixture.receiving &&
            fixture.original.calculateMetaID(CX, CY) == SPLIT && flags(fixture.original) == 1 && flags(fixture.access) == 14,
            "edited BRE re-add/WorldRegion reindex lost assigned key, access routing, identity or independent states")
        val edited = fixture.save()
        flags(fixture.original, 0)
        flags(fixture.access, 0)
        fixture.load(edited)
        require(flags(fixture.original) == 1 && flags(fixture.access) == 14,
            "edited/remerged original and access states did not independently reload")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        System.getProperty("pz.test.cache")?.let { ZomboidFileSystem.instance.setCacheDir(it) }
        ZomboidFileSystem.instance.base.set(Path.of(".").toFile())
        Core.gameMap = "Muldraugh, KY"
        zombie.core.random.RandStandard.INSTANCE.init()
        roundTrips()
        guards()
        woven()
        println("BASEMENT_HALL_KEY_CHECKS_PASS (all256 legacy flag pairs,512 reconstructed split-save roundtrips," +
            " downgrade dependency,IDs/layout/owner/caches/spawn receipts,source/map/custom/collision guards," +
            " woven SP/server/client,registered identity retention,explicit collision refusal,edited BRE re-add/WorldRegion reindex; no UI/render coverage)")
    }
}
