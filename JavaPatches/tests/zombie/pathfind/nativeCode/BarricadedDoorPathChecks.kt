package zombie.pathfind.nativeCode

import java.lang.reflect.Method
import java.nio.ByteBuffer
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.BarricadedDoorPaths
import net.alexredby.pztoolkitjavapatches.Main
import sun.misc.Unsafe
import zombie.characters.IsoPlayer
import zombie.characters.IsoZombie
import zombie.iso.IsoCell
import zombie.iso.IsoChunk
import zombie.iso.IsoChunkMap
import zombie.iso.IsoDirections
import zombie.iso.IsoGridSquare
import zombie.iso.IsoObject
import zombie.iso.IsoWorld
import zombie.iso.SpriteDetails.IsoFlagType
import zombie.iso.objects.IsoBarricade
import zombie.iso.objects.IsoDoor
import zombie.iso.objects.IsoThumpable
import zombie.iso.sprite.IsoSprite

object BarricadedDoorPathChecks {
    private lateinit var unsafe: Unsafe
    private lateinit var javaBits: Method

    private class Player : IsoPlayer(null) {
        override fun isNpc(): Boolean = false
    }

    private fun require(condition: Boolean, message: String) {
        if (!condition) throw AssertionError(message)
    }

    private fun set(obj: Any, name: String, value: Any) {
        obj.javaClass.getDeclaredField(name).apply { isAccessible = true }.set(obj, value)
    }

    private fun javaBits(square: IsoGridSquare): Int = javaBits.invoke(null, square) as Int

    private class Fixture(val north: Boolean, thumpable: Boolean, oppositeSide: Boolean) {
        val squares = Array(8) { y -> Array(8) { x -> IsoGridSquare(null, null, x, y, 0) } }
        val square: IsoGridSquare
        val opposite: IsoGridSquare
        val door: IsoObject
        val barricade: IsoBarricade

        init {
            for (y in 0..7) for (x in 0..7) {
                val sq = squares[y][x]
                sq.getProperties().set(IsoFlagType.solidfloor)
                if (x > 0) sq.setAdjacentSquare(IsoDirections.W, squares[y][x - 1])
                if (y > 0) sq.setAdjacentSquare(IsoDirections.N, squares[y - 1][x])
                if (x < 7) sq.setAdjacentSquare(IsoDirections.E, squares[y][x + 1])
                if (y < 7) sq.setAdjacentSquare(IsoDirections.S, squares[y + 1][x])
            }
            val cell = unsafe.allocateInstance(IsoCell::class.java) as IsoCell
            val map = unsafe.allocateInstance(IsoChunkMap::class.java) as IsoChunkMap
            val chunk = unsafe.allocateInstance(IsoChunk::class.java) as IsoChunk
            chunk.loaded = true
            chunk.loadedBits = 2
            set(chunk, "loadId", 1.toShort())
            chunk.minLevel = 0
            chunk.maxLevel = 0
            chunk.squares = arrayOf(arrayOfNulls<IsoGridSquare>(64))
            for (y in 0..7) for (x in 0..7) {
                chunk.squares[0][y * 8 + x] = squares[y][x]
                squares[y][x].chunk = chunk
            }
            val chunks =
                arrayOfNulls<IsoChunk>(IsoChunkMap.chunkGridWidth * IsoChunkMap.chunkGridWidth)
            chunks[0] = chunk
            map.worldX = IsoChunkMap.chunkGridWidth / 2
            map.worldY = IsoChunkMap.chunkGridWidth / 2
            set(map, "chunksSwapB", chunks)
            set(cell, "chunkMap", arrayOf(map))
            IsoWorld.instance.currentCell = cell
            IsoPlayer.numPlayers = 1
            square = at(4, 3)
            opposite = at(3, 3)
            val sprite = IsoSprite()
            door =
                if (thumpable) {
                    IsoThumpable(null).apply {
                        this.north = this@Fixture.north
                        setIsDoor(true)
                    }
                } else {
                    IsoDoor(null).apply { this.north = this@Fixture.north }
                }
            door.setSquare(square)
            door.setSprite(sprite)
            square.getSpecialObjects().add(door)
            square.getObjects().add(door)
            val side = if (oppositeSide) opposite else square
            val direction =
                if (north) {
                    if (oppositeSide) IsoDirections.S else IsoDirections.N
                } else {
                    if (oppositeSide) IsoDirections.E else IsoDirections.W
                }
            barricade = IsoBarricade(side, direction)
            side.getSpecialObjects().add(barricade)
            require(
                barricaded(),
                "native barricade lookup failed, north=$north thumpable=$thumpable opposite=$oppositeSide",
            )
        }

        fun at(x: Int, y: Int): IsoGridSquare = if (north) squares[x][y] else squares[y][x]

        fun barricaded(): Boolean =
            when (door) {
                is IsoDoor -> door.isBarricaded()
                else -> (door as IsoThumpable).isBarricaded()
            }

        fun open(value: Boolean) {
            when (door) {
                is IsoDoor -> door.setOpen(value)
                else -> (door as IsoThumpable).open = value
            }
        }

        fun detach() {
            barricade.getSquare().getSpecialObjects().remove(barricade)
        }

        fun attach() {
            barricade.getSquare().getSpecialObjects().add(barricade)
        }

        fun bits(): Long = SquareUpdateTask.getBits(square)

        fun map(detour: Boolean) {
            val buffer = ByteBuffer.allocateDirect(4096)
            buffer.putInt(32).putInt(32)
            for (y in 0..7) for (x in 0..7) {
                val rx = if (north) y else x
                val ry = if (north) x else y
                val floor =
                    rx >= 1 && rx <= 6 && (ry == 3 || (detour && ry == 5)) ||
                        (detour && (rx == 1 || rx == 6) && ry == 4)
                if (floor) squares[y][x].getProperties().unset(IsoFlagType.solid)
                else squares[y][x].getProperties().set(IsoFlagType.solid)
                val bits = SquareUpdateTask.getBits(squares[y][x])
                buffer.putLong(bits).putShort(0.toShort())
            }
            buffer.putShort(0.toShort()).flip()
            PathfindNative.updateChunk(1, 0, 0, buffer)
            PathfindNative.update()
        }

        fun changed() {
            // The engine notifies the barricade square; its neighbor update refreshes the door
            // owner.
            PathfindNative.instance.squareChanged(barricade.getSquare())
            while (true) {
                val task = PathfindNativeThread.instance.squareTaskQueue.poll() ?: break
                task.execute()
                task.release()
            }
            PathfindNative.update()
        }

        fun path(isZombie: Boolean, reverse: Boolean): List<FloatArray> {
            val request = PathFindRequest()
            request.mover =
                unsafe.allocateInstance(if (isZombie) IsoZombie::class.java else Player::class.java)
                    as zombie.ai.astar.Mover
            request.canThump = isZombie
            request.minLevel = 0
            request.maxLevel = 63
            request.startX = if (north) 3.5f else if (reverse) 6.5f else 1.5f
            request.startY =
                if (north) {
                    if (reverse) 6.5f else 1.5f
                } else 3.5f
            request.targetX = if (north) 3.5f else if (reverse) 1.5f else 6.5f
            request.targetY =
                if (north) {
                    if (reverse) 1.5f else 6.5f
                } else 3.5f
            val output = ByteBuffer.allocateDirect(3072)
            val result = PathfindNative.instance.findPath(request, output, false)
            val path = ArrayList<FloatArray>()
            if (result == 1) {
                val count = output.getShort().toInt()
                for (i in 0 until count) {
                    val x = output.getFloat()
                    val y = output.getFloat()
                    output.getFloat()
                    output.getInt()
                    path.add(floatArrayOf(x, y))
                }
            }
            return path
        }

        fun detours(path: List<FloatArray>): Boolean = path.any { it[if (north) 0 else 1] > 4.5f }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"))
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        zombie.ZomboidFileSystem.instance.init()
        zombie.Lua.LuaManager.init()
        unsafe =
            Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null)
                as Unsafe
        javaBits =
            Class.forName("zombie.pathfind.SquareUpdateTask")
                .getDeclaredMethod("getBits", IsoGridSquare::class.java)
                .apply { isAccessible = true }
        PathfindNative.init()
        PathfindNative.initWorld(0, 0, 1, 1, false)
        // Dispatch native square-change tasks synchronously without starting a background game
        // loop.
        PathfindNativeThread.instance = PathfindNativeThread()
        val baseline = Fixture(false, false, false)
        val stock = baseline.bits()
        val javaStock = javaBits(baseline.square)
        baseline.map(false)
        require(
            !baseline.path(false, false).isEmpty(),
            "native baseline did not reproduce route through barricaded door",
        )
        Main.main(emptyArray())
        PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            BarricadedDoorPathChecks::class.java.classLoader,
        )
        require(BarricadedDoorPaths.SUPPORTED, "unsupported barricaded-door bytecode")
        require(
            baseline.bits() == (stock or 32768L) &&
                javaBits(baseline.square) == (javaStock or 32768),
            "woven native/Java encoding hook failed",
        )
        require(
            BarricadedDoorPaths.correct(baseline.square, stock, false) == stock,
            "unsupported bytecode changed bits",
        )
        require(BarricadedDoorPaths.correct(null, stock, true) == stock, "null square changed bits")
        for (north in booleanArrayOf(false, true)) for (thumpable in
            booleanArrayOf(false, true)) for (side in booleanArrayOf(false, true)) {
            val f = Fixture(north, thumpable, side)
            val thump = if (north) 65536L else 32768L
            f.detach()
            require(!f.barricaded(), "removed barricade still found")
            val clean = f.bits()
            val javaClean = javaBits(f.square)
            f.attach()
            require(
                f.bits() == (clean or thump) && javaBits(f.square) == (javaClean or thump.toInt()),
                "unrelated square bits changed",
            )
            f.map(false)
            for (reverse in booleanArrayOf(false, true)) {
                require(
                    f.path(false, reverse).isEmpty(),
                    "player crosses barricaded door without alternative",
                )
                require(!f.path(true, reverse).isEmpty(), "zombie lost destructive route")
            }
            f.map(true)
            for (reverse in booleanArrayOf(false, true)) {
                val path = f.path(false, reverse)
                require(!path.isEmpty() && f.detours(path), "player did not route around barricade")
            }
            f.detach()
            require(
                f.bits() == clean && javaBits(f.square) == javaClean,
                "barricade removal left stale flags",
            )
            f.changed()
            val restored = f.path(false, false)
            require(
                !restored.isEmpty() && !f.detours(restored),
                "live removal did not restore native route",
            )
            f.attach()
            require(f.bits() == (clean or thump), "readded barricade not encoded")
            f.changed()
            val blockedAgain = f.path(false, false)
            require(
                !blockedAgain.isEmpty() && f.detours(blockedAgain),
                "live readd did not restore detour",
            )
            if (f.door is IsoThumpable) {
                f.door.setIsDoor(false)
                require(f.door.isBarricaded(), "non-door thumpable lost its native barricade")
                val sentinel = 0x10000000L
                require(
                    BarricadedDoorPaths.correct(f.square, sentinel, true) == sentinel,
                    "non-door thumpable gained door flags",
                )
                f.door.setIsDoor(true)
            }
            f.open(true)
            val open = f.bits()
            val javaOpen = javaBits(f.square)
            f.detach()
            require(
                f.bits() == open && javaBits(f.square) == javaOpen,
                "open door behavior changed",
            )
            f.square.getSpecialObjects().clear()
            require((f.bits() and thump) == 0L, "non-door square gained thump flag")
        }
        PathfindNative.destroyWorld()
        println(
            "BARRICADED_DOOR_PATH_CHECKS_PASS (native baseline reproduced; woven native and Java encoders; both orientations, door types and barricade sides; both walking directions; blocked/detour player routes; destructive zombie route; removal/readd/open/unsupported preservation)",
        )
    }
}
