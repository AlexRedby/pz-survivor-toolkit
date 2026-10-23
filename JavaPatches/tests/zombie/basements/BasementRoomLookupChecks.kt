package zombie.basements

import java.nio.BufferUnderflowException
import java.nio.ByteBuffer
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.BasementRoomLookup
import net.alexredby.pztoolkitjavapatches.Main
import zombie.iso.*
import zombie.iso.areas.IsoBuilding
import zombie.iso.areas.IsoRoom

object BasementRoomLookupChecks {
    @JvmStatic
    fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    @JvmStatic
    fun field(target: Any, name: String, value: Any?) {
        target.javaClass.getDeclaredField(name).apply { isAccessible = true }.set(target, value)
    }

    @JvmStatic
    fun room(index: Int, name: String, z: Int, vararg rectangles: IntArray): RoomDef {
        val room = RoomDef(RoomID.makeID(25, 34, index), name)
        room.level = z
        for (rect in rectangles) room.rects.add(
            RoomDef.RoomRect(rect[0], rect[1], rect[2], rect[3]),
        )
        room.CalculateBounds()
        room.metaId = room.calculateMetaID(25, 34)
        return room
    }

    @JvmStatic
    fun flags(room: RoomDef, flags: Int) {
        room.setExplored((flags and 1) != 0)
        room.lightsActive = (flags and 2) != 0
        room.doneSpawn = (flags and 4) != 0
        room.setRoofFixed((flags and 8) != 0)
    }

    @JvmStatic
    fun flags(room: RoomDef): Int =
        (if (room.explored) 1 else 0) or
            (if (room.lightsActive) 2 else 0) or
            (if (room.doneSpawn) 4 else 0) or
            (if (room.isRoofFixed()) 8 else 0)

    @JvmStatic
    fun save(grid: IsoMetaGrid): ByteBuffer =
        ByteBuffer.allocate(4096).apply {
            grid.savePart(this, 0, false)
            flip()
        }

    @JvmStatic
    fun loadRoomSection(grid: IsoMetaGrid, bytes: ByteBuffer) {
        val count = bytes.getInt(24)
        bytes.position(0)
        bytes.limit(28 + count * 10)
        try {
            grid.load(bytes)
            throw AssertionError("room section did not end at building count")
        } catch (_: BufferUnderflowException) {
            require(bytes.position() == bytes.limit(), "unexpected native load boundary")
        }
    }

    private class Fixture(outside: Boolean, missingSourceIndex: Int = -1, woven: Boolean = false) {
        val grid: IsoMetaGrid = IsoWorld.instance.metaGrid
        val destination = IsoMetaCell(25, 33)
        val source = IsoMetaCell(25, 34)
        val receiving = BuildingDef()
        val incoming = BuildingDef()
        val previousID = BuildingID.makeID(25, 34, 4)
        val previous: BasementRoomLookup.State?
        val moved = ArrayList<RoomDef>()

        init {
            grid.minX = 25
            grid.maxX = 25
            grid.minY = 33
            grid.maxY = 34
            destination.info = LotHeader(25, 33)
            source.info = LotHeader(25, 34)
            field(grid, "grid", arrayOf(arrayOf(destination, source)))
            field(grid, "width", 1)
            field(grid, "height", 2)
            val prefix = room(0, "other-basement", -2, intArrayOf(6600, 8500, 2, 2))
            prefix.id = RoomID.makeID(25, 33, 0)
            prefix.metaId = prefix.calculateMetaID(25, 33)
            destination.roomList.add(prefix)
            destination.rooms[prefix.id] = prefix
            destination.roomByMetaId.put(prefix.metaId, prefix)
            receiving.id = previousID
            moved.add(
                room(
                    8,
                    "livingroom",
                    0,
                    intArrayOf(6631, 8704, 7, 3),
                    intArrayOf(6631, 8707, 9, 2),
                    intArrayOf(6636, 8709, 4, 3),
                    intArrayOf(6634, 8712, 5, 2),
                ),
            )
            moved.add(room(9, "bathroom", 0, intArrayOf(6634, 8709, 2, 3)))
            moved.add(room(10, "bedroom", 0, intArrayOf(6631, 8709, 3, 4)))
            moved.add(room(11, "bedroom", 0, intArrayOf(6634, 8714, 5, 3)))
            receiving.rooms.addAll(moved)
            if (outside) {
                val extra = room(12, "emptyoutside", 0, intArrayOf(6640, 8704, 1, 1))
                receiving.emptyoutside.add(extra)
                moved.add(extra)
            }
            for (room in moved) room.building = receiving
            receiving.CalculateBounds(ArrayList())
            receiving.metaId = receiving.calculateMetaID(25, 34)
            source.buildings.add(receiving)
            source.buildingByMetaId.put(receiving.metaId, receiving)
            for (room in moved) {
                source.roomList.add(room)
                source.rooms[room.id] = room
                source.roomByMetaId.put(room.metaId, room)
            }
            if (missingSourceIndex >= 0)
                source.roomByMetaId.remove(moved[missingSourceIndex].metaId)
            previous = BasementRoomLookup.beforeMerge(receiving, true)
            val basement =
                room(
                    0,
                    "hunterstorage",
                    -1,
                    intArrayOf(6632, 8703, 7, 5),
                    intArrayOf(6632, 8708, 6, 6),
                )
            basement.building = incoming
            incoming.rooms.add(basement)
            incoming.CalculateBounds(ArrayList())
            Basements::class
                .java
                .getDeclaredMethod(
                    "mergeBuildings",
                    BuildingDef::class.java,
                    BuildingDef::class.java,
                )
                .apply { isAccessible = true }
                .invoke(Basements(), incoming, receiving)
            require(
                BuildingID.getCellY(receiving.id) == 33,
                "native building did not cross cell boundary",
            )
            for (room in moved) {
                require(
                    room in destination.roomList &&
                        destination.rooms[room.id] === room &&
                        (if (woven && moved.indexOf(room) != missingSourceIndex)
                            destination.roomByMetaId.get(room.metaId) === room
                        else !destination.roomByMetaId.containsKey(room.metaId)) &&
                        room !in source.roomList &&
                        !source.roomByMetaId.containsKey(room.metaId),
                    "native cross-cell omission not reproduced",
                )
            }
            require(
                destination.roomByMetaId.get(basement.metaId) === basement,
                "native incoming room index changed",
            )
            require(
                moved[0].metaId == 231L &&
                    moved[1].metaId == 327914L &&
                    moved[2].metaId == 327911L &&
                    moved[3].metaId == 655594L,
                "actual header room IDs changed",
            )
        }
    }

    private fun state(room: RoomDef): List<Any?> =
        listOf(
            room.metaId,
            room.name,
            room.level,
            room.x,
            room.y,
            room.x2,
            room.y2,
            room.area,
            room.building,
            ArrayList(room.rects),
            ArrayList(room.objects),
            flags(room),
        )

    @JvmStatic
    fun roundTrips() {
        for (flagState in 0 until 16) {
            val fixture = Fixture(false)
            val cell = fixture.destination
            for ((i, room) in fixture.moved.withIndex()) flags(room, flagState xor i)
            val beforeSave = save(fixture.grid)
            val roomList = ArrayList(cell.roomList)
            val allRoomIDs = cell.roomList.map { it.id }.toLongArray()
            val runtimeRooms = HashMap(cell.rooms)
            val buildings = ArrayList(cell.buildings)
            val buildingIndex = gnu.trove.map.hash.TLongObjectHashMap(cell.buildingByMetaId)
            val cachedRoom = IsoRoom().apply { def = fixture.moved[0] }
            cell.isoRooms[cachedRoom.def.id] = cachedRoom
            val cachedBuilding = IsoBuilding().apply { def = fixture.receiving }
            cell.isoBuildings[fixture.receiving.id] = cachedBuilding
            val roomCache = HashMap(cell.isoRooms)
            val buildingCache = HashMap(cell.isoBuildings)
            val chunk = IsoChunk(null as IsoCell?)
            for (room in fixture.moved) chunk.addSpawnedRoom(room.id)
            val roomIDs = fixture.moved.map { it.id }.toLongArray()
            val roomState = fixture.moved.map { state(it) }
            require(
                BasementRoomLookup.repair(fixture.receiving, fixture.previous, true) == 4,
                "wrong repair count",
            )
            require(
                cell.roomList == roomList &&
                    cell.rooms == runtimeRooms &&
                    cell.buildings == buildings &&
                    cell.buildingByMetaId == buildingIndex &&
                    cell.isoRooms == roomCache &&
                    cell.isoBuildings == buildingCache,
                "repair changed native layout/IDs/caches",
            )
            require(
                allRoomIDs.contentEquals(cell.roomList.map { it.id }.toLongArray()),
                "repair shifted another room's runtime ID",
            )
            for ((i, room) in fixture.moved.withIndex()) {
                require(
                    room.id == roomIDs[i] && chunk.isSpawnedRoom(room.id),
                    "repair invalidated native spawn receipt",
                )
                require(roomState[i] == state(room), "repair changed room metadata/state")
                require(cell.roomByMetaId.get(room.metaId) === room, "moved room not indexed")
            }
            require(beforeSave == save(fixture.grid), "repair changed serialized bytes")
            require(
                BasementRoomLookup.repair(fixture.receiving, fixture.previous, true) == 0,
                "repair not idempotent",
            )
            for (room in fixture.moved) flags(room, 0)
            loadRoomSection(fixture.grid, beforeSave)
            for ((i, room) in fixture.moved.withIndex()) {
                require(
                    flags(room) == (flagState xor i),
                    "native old-format room flags not restored",
                )
            }
        }
    }

    @JvmStatic
    fun guards() {
        var fixture = Fixture(false)
        val cell = fixture.destination
        require(
            BasementRoomLookup.repair(fixture.receiving, fixture.previous, false) == 0 &&
                cell.roomByMetaId.size() == 2,
            "unsupported native bytecode modified",
        )
        require(
            BasementRoomLookup.beforeMerge(fixture.receiving, false) == null,
            "unsupported snapshot created",
        )
        require(
            BasementRoomLookup.repair(
                fixture.receiving,
                BasementRoomLookup.beforeMerge(fixture.receiving, true),
                true,
            ) == 0 && cell.roomByMetaId.size() == 2,
            "same-cell missing index modified",
        )
        val collision = room(90, "hall", 0, intArrayOf(6631, 8704, 1, 1))
        collision.metaId = fixture.moved[0].metaId
        cell.roomList.add(collision)
        cell.rooms[collision.id] = collision
        flags(fixture.moved[0], 1)
        flags(collision, 14)
        val existing = room(91, "custom", 0, intArrayOf(6640, 8704, 1, 1))
        cell.roomByMetaId.put(fixture.moved[1].metaId, existing)
        cell.roomList.remove(fixture.moved[2])
        cell.rooms[fixture.moved[3].id] = existing
        val beforeIndex = gnu.trove.map.hash.TLongObjectHashMap(cell.roomByMetaId)
        require(
            BasementRoomLookup.repair(fixture.receiving, fixture.previous, true) == 0 &&
                cell.roomByMetaId == beforeIndex &&
                flags(fixture.moved[0]) == 1 &&
                flags(collision) == 14,
            "ambiguous/existing/mismatched room was assigned or flags merged",
        )
        fixture = Fixture(false)
        for (room in fixture.moved) room.userDefined = true
        require(
            BasementRoomLookup.repair(fixture.receiving, fixture.previous, true) == 0 &&
                fixture.destination.roomByMetaId.size() == 2,
            "custom user-defined room modified",
        )
        fixture = Fixture(false, 0)
        require(
            BasementRoomLookup.repair(fixture.receiving, fixture.previous, true) == 3 &&
                !fixture.destination.roomByMetaId.containsKey(fixture.moved[0].metaId),
            "prior missing source index created",
        )
        fixture = Fixture(true)
        require(
            BasementRoomLookup.repair(fixture.receiving, fixture.previous, true) == 5,
            "moved emptyoutside room omitted",
        )
    }

    @JvmStatic
    fun woven() {
        Main.main(emptyArray())
        PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            BasementRoomLookupChecks::class.java.classLoader,
        )
        for (role in 0 until 3) {
            zombie.network.GameServer.server = role == 1
            zombie.network.GameClient.client = role == 2
            val fixture = Fixture(false, -1, true)
            require(
                fixture.destination.roomByMetaId.size() == 6,
                "woven native merge did not restore exactly4 entries",
            )
            for ((i, room) in fixture.moved.withIndex()) flags(room, 15 xor i)
            val bytes = save(fixture.grid)
            for (room in fixture.moved) flags(room, 0)
            loadRoomSection(fixture.grid, bytes)
            for ((i, room) in fixture.moved.withIndex()) {
                require(flags(room) == (15 xor i), "woven old-format flags lost for role=$role")
            }
        }
        zombie.network.GameServer.server = false
        zombie.network.GameClient.client = false
        val missing = Fixture(false, 0, true)
        require(
            missing.destination.roomByMetaId.size() == 5 &&
                !missing.destination.roomByMetaId.containsKey(missing.moved[0].metaId),
            "woven merge created a deliberately missing source index",
        )
    }

    @JvmStatic
    fun main(args: Array<String>) {
        System.getProperty("pz.test.cache")?.let {
            zombie.ZomboidFileSystem.instance.setCacheDir(it)
        }
        zombie.core.random.RandStandard.INSTANCE.init()
        roundTrips()
        guards()
        woven()
        println(
            "BASEMENT_ROOM_LOOKUP_CHECKS_PASS (native cross-cell omission, missing-only repair, all16 flags," +
                " byte-identical save, IDs/layout/caches/spawn receipts, unsupported/same-cell/custom/collision guards, emptyoutside, woven SP/server/client)",
        )
    }
}
