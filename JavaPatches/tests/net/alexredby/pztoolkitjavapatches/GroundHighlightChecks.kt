package net.alexredby.pztoolkitjavapatches

import java.nio.file.Path
import me.zed_0xff.zombie_buddy.Exposer
import me.zed_0xff.zombie_buddy.PatchEngine
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.KahluaTable
import se.krka.kahlua.vm.KahluaThread
import sun.misc.Unsafe
import zombie.Lua.KahluaNumberConverter
import zombie.Lua.LuaManager
import zombie.characters.IsoPlayer
import zombie.core.Core
import zombie.core.textures.ColorInfo
import zombie.inventory.InventoryItem
import zombie.iso.IsoCell
import zombie.iso.IsoChunk
import zombie.iso.IsoChunkMap
import zombie.iso.IsoGridSquare
import zombie.iso.IsoObject
import zombie.iso.objects.IsoWorldInventoryObject
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.scripting.objects.Item

/** Real native object reads and Kahlua crossings; timings do not represent rendered game frames. */
object GroundHighlightChecks {
    private val unsafe =
        Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null)
            as Unsafe

    private fun verify(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun field(type: Class<*>, target: Any, name: String, value: Any?) {
        type.getDeclaredField(name).apply { isAccessible = true }.set(target, value)
    }

    private class Fixture {
        val cell = unsafe.allocateInstance(IsoCell::class.java) as IsoCell
        private val chunk = unsafe.allocateInstance(IsoChunk::class.java) as IsoChunk
        private val squares = arrayOf(arrayOfNulls<IsoGridSquare>(64))

        init {
            GameClient.client = false
            GameServer.server = false
            IsoPlayer.numPlayers = 1
            IsoChunkMap.chunkGridWidth = 1
            IsoChunkMap.chunkWidthInTiles = 8
            field(IsoChunk::class.java, chunk, "squares", squares)
            field(IsoChunk::class.java, chunk, "maxLevel", 0)
            field(IsoChunk::class.java, chunk, "minLevel", 0)
            field(IsoChunk::class.java, chunk, "loaded", true)
            val map = unsafe.allocateInstance(IsoChunkMap::class.java) as IsoChunkMap
            field(IsoChunkMap::class.java, map, "chunksSwapA", arrayOf(chunk))
            field(IsoChunkMap::class.java, map, "chunksSwapB", arrayOf(chunk))
            field(IsoCell::class.java, cell, "chunkMap", arrayOf(map))
        }

        fun square(x: Int, y: Int, loaded: Boolean = true): IsoGridSquare {
            val square = unsafe.allocateInstance(IsoGridSquare::class.java) as IsoGridSquare
            field(IsoGridSquare::class.java, square, "x", x)
            field(IsoGridSquare::class.java, square, "y", y)
            field(
                IsoGridSquare::class.java,
                square,
                "lighting",
                Array<IsoGridSquare.ILighting>(4) {
                    IsoGridSquare.Lighting().apply {
                        bSeen(true)
                        bCanSee(true)
                    }
                },
            )
            if (loaded) squares[0][x + y * 8] = square
            return square
        }

        fun ground(x: Int = 2, y: Int = 2, loaded: Boolean = true): IsoWorldInventoryObject {
            val square = square(x, y, loaded)
            val item = unsafe.allocateInstance(InventoryItem::class.java) as InventoryItem
            val script = unsafe.allocateInstance(Item::class.java) as Item
            field(Item::class.java, script, "worldRender", true)
            item.setScriptItem(script)
            val ground =
                unsafe.allocateInstance(IsoWorldInventoryObject::class.java)
                    as IsoWorldInventoryObject
            ground.square = square
            ground.item = item
            item.setWorldItem(ground)
            ground.xoff = .25f
            ground.yoff = .75f
            field(IsoObject::class.java, ground, "doRender", true)
            field(IsoObject::class.java, ground, "targetAlpha", FloatArray(4) { 1f })
            field(
                IsoObject::class.java,
                ground,
                "highlightColor",
                Array(4) { ColorInfo(.2f, .3f, .4f, .5f) },
            )
            field(IsoObject::class.java, ground, "outlineHighlightCol", IntArray(4) { 0x12345678 })
            field(IsoObject::class.java, ground, "ppfHighlighted", 1.toByte())
            field(IsoObject::class.java, ground, "isOutlineHighlight", 1.toByte())
            verify(
                cell.getGridSquare(x, y, 0) === if (loaded) square else null,
                "native cell fixture",
            )
            return ground
        }
    }

    private fun environment(): KahluaThread {
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", javaClass.classLoader)
        val bridge =
            Exposer.getClassesWithGlobalLuaMethod().firstOrNull {
                it.name == "net.alexredby.pztoolkitjavapatches.GroundHighlight"
            } ?: throw AssertionError("ZombieBuddy did not discover the ground-highlight globals")
        verify(
            Path.of(bridge.protectionDomain.codeSource.location.toURI()) ==
                Path.of(System.getProperty("pz.test.patch.jar")),
            "ground-highlight bridge did not come from the built JAR",
        )
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = LuaManager.platform.newEnvironment()
        LuaManager.converterManager = KahluaConverterManager()
        KahluaNumberConverter.install(LuaManager.converterManager)
        LuaManager.exposer =
            LuaManager.Exposer(LuaManager.converterManager, LuaManager.platform, LuaManager.env)
        for (type in
            arrayOf(
                IsoWorldInventoryObject::class.java,
                IsoObject::class.java,
                IsoCell::class.java,
                IsoGridSquare::class.java,
                InventoryItem::class.java,
                Item::class.java,
                ColorInfo::class.java,
            )) {
            LuaManager.exposer.setExposed(type)
            LuaManager.exposer.exposeLikeJava(type, LuaManager.env)
        }
        Exposer.afterExposeAll()
        val thread = KahluaThread(LuaManager.platform, LuaManager.env)
        thread.debugOwnerThread = Thread.currentThread()
        LuaManager.thread = thread
        thread.call(
            LuaCompiler.loadstring(
                """
                assert(type(toolkitGroundHighlightDistance)=='function')
                assert(type(toolkitGroundHighlightMatches)=='function')
                function ReferenceDistance(object, cell, playerNum, z, x, y, radius)
                    local square = object:getSquare()
                    local item = object:getItem()
                    if not square or not item or item:getWorldItem() ~= object then return -1 end
                    if square:getZ() ~= z then return -1 end
                    if cell:getGridSquare(square:getX(), square:getY(), square:getZ()) ~= square then return -1 end
                    if not square:isCanSee(playerNum) then return -1 end
                    if not object:getDoRender() or object:getTargetAlpha(playerNum) <= 0 then return -1 end
                    if not item:getScriptItem():isWorldRender() then return -1 end
                    local dx = object:getWorldPosX() - x
                    local dy = object:getWorldPosY() - y
                    local distance = dx * dx + dy * dy
                    if distance <= radius * radius then return distance end
                    return -1
                end
                function ReferenceMatches(object, playerNum, packed, attached, r, g, b, a)
                    local colour = object:getHighlightColor(playerNum)
                    return object:isHighlighted(playerNum)
                        and object:isOutlineHighlight(playerNum)
                        and object:isOutlineHlAttached(playerNum) == attached
                        and object:getOutlineHighlightCol(playerNum) == packed
                        and colour:getR() == r and colour:getG() == g
                        and colour:getB() == b and colour:getA() == a
                end
                function FallbackDistance(object, cell, playerNum, z, x, y, radius)
                    local distance = toolkitGroundHighlightDistance(object, cell, playerNum, z, x, y, radius)
                    if distance ~= nil then return distance end
                    return ReferenceDistance(object, cell, playerNum, z, x, y, radius)
                end
                function BenchmarkGroundHighlight(useBridge, repeats)
                    local distance = useBridge and toolkitGroundHighlightDistance or ReferenceDistance
                    local matches = useBridge and toolkitGroundHighlightMatches or ReferenceMatches
                    local checksum = 0
                    for repeatIndex = 1, repeats do
                        for index = 1, #GroundObjects do
                            local object = GroundObjects[index]
                            local d = distance(object, GroundCell, 0, 0, 2.5, 2.5, 4)
                            checksum = checksum + d
                            if d >= 0 and matches(object, 0, GroundPacked, false,
                                GroundR, GroundG, GroundB, GroundA) then checksum = checksum + 1 end
                        end
                    end
                    return checksum
                end
                """
                    .trimIndent(),
                "ground-highlight-reference",
                LuaManager.env,
            ),
            emptyArray<Any?>(),
        )
        return thread
    }

    private fun distanceArgs(ground: IsoWorldInventoryObject?, cell: IsoCell?): Array<Any?> =
        arrayOf(ground, cell, 0.0, 0.0, 2.5, 2.5, 4.0)

    private fun parity(thread: KahluaThread, name: String, args: Array<Any?>): Any? {
        val reference = thread.call(LuaManager.env.rawget("Reference$name"), args)
        val actual = thread.call(LuaManager.env.rawget("toolkitGroundHighlight$name"), args)
        verify(actual == reference, "$name parity: $actual != $reference")
        return actual
    }

    private fun distanceChecks(thread: KahluaThread) {
        val fixture = Fixture()
        val ground = fixture.ground()
        val args = distanceArgs(ground, fixture.cell)
        verify(
            thread.call(
                LuaManager.env.rawget("toolkitGroundHighlightDistance"),
                distanceArgs(null, fixture.cell),
            ) == -1.0,
            "missing object must be ineligible",
        )
        verify(
            thread.call(
                LuaManager.env.rawget("toolkitGroundHighlightDistance"),
                distanceArgs(ground, null),
            ) == -1.0,
            "missing cell must be ineligible",
        )
        verify(parity(thread, "Distance", args) == .125, "native float distance")
        args[3] = 1.0
        verify(parity(thread, "Distance", args) == -1.0, "different floor")
        args[3] = 0.0
        ground.square.setCanSee(0, false)
        verify(parity(thread, "Distance", args) == -1.0, "explored but not visible")
        args[2] = 1.0
        verify(parity(thread, "Distance", args) == .125, "local player visibility slot")
        args[2] = 0.0
        ground.square.setCanSee(0, true)
        field(IsoObject::class.java, ground, "doRender", false)
        verify(parity(thread, "Distance", args) == -1.0, "render disabled")
        field(IsoObject::class.java, ground, "doRender", true)
        field(IsoObject::class.java, ground, "targetAlpha", FloatArray(4))
        verify(parity(thread, "Distance", args) == -1.0, "transparent")
        field(IsoObject::class.java, ground, "targetAlpha", FloatArray(4) { Float.NaN })
        verify(parity(thread, "Distance", args) == .125, "native NaN alpha comparison changed")
        field(Item::class.java, ground.item.scriptItem, "worldRender", false)
        verify(parity(thread, "Distance", args) == -1.0, "script rendering disabled")
        field(Item::class.java, ground.item.scriptItem, "worldRender", true)
        ground.xoff = 4.5f
        ground.yoff = .5f
        verify(parity(thread, "Distance", args) == 16.0, "exact radius boundary/raw offset")
        ground.xoff = Math.nextUp(4.5f)
        verify(parity(thread, "Distance", args) == -1.0, "outside boundary")
        ground.xoff = .1234567f
        ground.yoff = .7654321f
        args[4] = 2.12345670000001
        args[5] = 2.76543210000001
        val exact = parity(thread, "Distance", args) as Double
        val floatDx = ground.worldPosX - (args[4] as Double).toFloat()
        val floatDy = ground.worldPosY - (args[5] as Double).toFloat()
        verify(exact != (floatDx * floatDx + floatDy * floatDy).toDouble(), "precision control")
        ground.xoff = Float.NaN
        verify(parity(thread, "Distance", args) == -1.0, "NaN position")
        ground.xoff = 0f
        val item = ground.item
        item.setWorldItem(null)
        verify(parity(thread, "Distance", args) == -1.0, "item ownership changed")
        item.setWorldItem(ground)
        ground.item = null
        verify(parity(thread, "Distance", args) == -1.0, "missing item")
        ground.item = item
        ground.square = null
        verify(parity(thread, "Distance", args) == -1.0, "missing square")
        ground.square = fixture.square(2, 2, false)
        verify(parity(thread, "Distance", args) == -1.0, "stale square identity")
        ground.square = fixture.square(2, 2)
        item.setScriptItem(null)
        try {
            GroundHighlight.distance(ground, fixture.cell, 0, 0.0, 2.5, 2.5, 4.0)
            throw AssertionError("native helper hid the missing-script failure")
        } catch (expected: NullPointerException) {
            // PZ MethodCaller logs native exceptions and returns no Lua values. The caller's
            // existing nil fallback must still reach the original Lua failure in this case.
        }
        for (name in arrayOf("ReferenceDistance", "FallbackDistance")) {
            val result = thread.pcall(LuaManager.env.rawget(name), args.copyOf())
            verify(
                result[0] == false,
                "missing script error: $name ${result.contentToString()}",
            )
        }
        verify(
            GroundHighlight.readDistance(null, null, 0, 0.0, 0.0, 0.0, 4.0, false) == null,
            "unsupported eligibility must remain unknown",
        )
    }

    private fun matchesArgs(ground: IsoWorldInventoryObject): Array<Any?> {
        val colour = ground.getHighlightColor(0)
        return arrayOf(
            ground,
            0.0,
            ground.getOutlineHighlightCol(0).toDouble(),
            false,
            colour.getR().toDouble(),
            colour.getG().toDouble(),
            colour.getB().toDouble(),
            colour.getA().toDouble(),
        )
    }

    private fun matchesChecks(thread: KahluaThread) {
        val fixture = Fixture()
        val ground = fixture.ground()
        val args = matchesArgs(ground)
        val missing = args.copyOf().apply { this[0] = null }
        verify(
            thread.call(LuaManager.env.rawget("toolkitGroundHighlightMatches"), missing) == false,
            "missing object cannot own highlights",
        )
        verify(parity(thread, "Matches", args) == true, "owned highlight")
        for ((name, value) in
            arrayOf(
                "ppfHighlighted" to 0.toByte(),
                "isOutlineHighlight" to 0.toByte(),
                "isOutlineHlAttached" to 1.toByte(),
            )) {
            field(IsoObject::class.java, ground, name, value)
            verify(parity(thread, "Matches", args) == false, "foreign flag: $name")
            field(
                IsoObject::class.java,
                ground,
                name,
                if (name == "isOutlineHlAttached") 0.toByte() else 1.toByte(),
            )
        }
        ground.setOutlineHighlightCol(0, .1f, .2f, .3f, .4f)
        verify(parity(thread, "Matches", args) == false, "foreign packed outline")
        args[2] = ground.getOutlineHighlightCol(0).toDouble()
        for (index in 4..7) {
            val old = args[index]
            args[index] = Math.nextUp(old as Double)
            verify(parity(thread, "Matches", args) == false, "exact model component $index")
            args[index] = old
        }
        args[1] = 1.0
        verify(parity(thread, "Matches", args) == false, "player-slot ownership")
        verify(
            GroundHighlight.readMatches(null, 0, 0, false, 0.0, 0.0, 0.0, 0.0, false) == null,
            "unsupported ownership must remain unknown",
        )
    }

    private fun crossingCount(thread: KahluaThread, useBridge: Boolean, objects: List<Any>): Int {
        val replacements = LinkedHashMap<Pair<KahluaTable, String>, Any?>()
        var calls = 0
        val methods =
            arrayOf(
                "getSquare",
                "getItem",
                "getWorldItem",
                "getZ",
                "getGridSquare",
                "getX",
                "getY",
                "isCanSee",
                "getDoRender",
                "getTargetAlpha",
                "getScriptItem",
                "isWorldRender",
                "getWorldPosX",
                "getWorldPosY",
                "getHighlightColor",
                "isHighlighted",
                "isOutlineHighlight",
                "isOutlineHlAttached",
                "getOutlineHighlightCol",
                "getR",
                "getG",
                "getB",
                "getA",
            )
        for (target in objects) {
            val meta = thread.getmetatable(target, false) as KahluaTable
            val index = meta.rawget("__index") as KahluaTable
            for (name in methods) {
                val original = thread.tableget(target, name)
                if (original !is JavaFunction || replacements.containsKey(index to name)) continue
                replacements[index to name] = index.rawget(name)
                index.rawset(
                    name,
                    JavaFunction { frame, count ->
                        calls++
                        original.call(frame, count)
                    },
                )
            }
        }
        for (name in arrayOf("toolkitGroundHighlightDistance", "toolkitGroundHighlightMatches")) {
            val original = LuaManager.env.rawget(name) as JavaFunction
            replacements[LuaManager.env to name] = original
            LuaManager.env.rawset(
                name,
                JavaFunction { frame, count ->
                    calls++
                    original.call(frame, count)
                },
            )
        }
        try {
            thread.call(
                LuaManager.env.rawget("BenchmarkGroundHighlight"),
                arrayOf<Any?>(useBridge, 1.0),
            )
            return calls
        } finally {
            for ((key, original) in replacements) key.first.rawset(key.second, original)
        }
    }

    private fun benchmark(thread: KahluaThread) {
        val fixture = Fixture()
        val near = fixture.ground(0, 0)
        val far = fixture.ground(1, 0).apply { xoff = 9f }
        val hidden = fixture.ground(2, 0).apply { square.setCanSee(0, false) }
        val invisible =
            fixture.ground(3, 0).apply {
                field(IsoObject::class.java, this, "doRender", false)
            }
        val transparent =
            fixture.ground(4, 0).apply {
                field(IsoObject::class.java, this, "targetAlpha", FloatArray(4))
            }
        val noModel =
            fixture.ground(5, 0).apply {
                field(Item::class.java, item.scriptItem, "worldRender", false)
            }
        val foreign =
            fixture.ground(6, 0).apply {
                xoff = -3.5f
                setHighlightColor(0, .8f, .7f, .6f, .5f)
            }
        val stale = fixture.ground(7, 0).apply { item.setWorldItem(null) }
        val grounds = listOf(near, far, hidden, invisible, transparent, noModel, foreign, stale)
        val list = LuaManager.platform.newTable()
        grounds.forEachIndexed { index, ground -> list.rawset(index + 1, ground) }
        LuaManager.env.rawset("GroundObjects", list)
        LuaManager.env.rawset("GroundCell", fixture.cell)
        val args = matchesArgs(near)
        for ((name, index) in
            arrayOf(
                "GroundPacked" to 2,
                "GroundR" to 4,
                "GroundG" to 5,
                "GroundB" to 6,
                "GroundA" to 7,
            )) {
            LuaManager.env.rawset(name, args[index])
        }
        val probes =
            listOf<Any>(
                near,
                fixture.cell,
                near.square,
                near.item,
                near.item.scriptItem,
                near.getHighlightColor(0),
            )
        val referenceCalls = crossingCount(thread, false, probes)
        val bridgeCalls = crossingCount(thread, true, probes)
        verify(
            referenceCalls > bridgeCalls * 5,
            "native crossings were not reduced: $referenceCalls/$bridgeCalls",
        )
        println(
            "GROUND_HIGHLIGHT_CROSSINGS objects=${grounds.size} reference=$referenceCalls bridge=$bridgeCalls",
        )
        val function = LuaManager.env.rawget("BenchmarkGroundHighlight")
        val reference = thread.call(function, arrayOf<Any?>(false, 1.0))
        verify(
            thread.call(function, arrayOf<Any?>(true, 1.0)) == reference,
            "benchmark output parity",
        )
        repeat(3) {
            thread.call(function, arrayOf<Any?>(false, 200.0))
            thread.call(function, arrayOf<Any?>(true, 200.0))
        }
        val samples = arrayOf(LongArray(5), LongArray(5))
        repeat(5) { round ->
            for (bridge in if (round % 2 == 0) arrayOf(false, true) else arrayOf(true, false)) {
                val started = System.nanoTime()
                thread.call(function, arrayOf<Any?>(bridge, 1500.0))
                samples[if (bridge) 1 else 0][round] = System.nanoTime() - started
            }
        }
        samples.forEach { it.sort() }
        println(
            "GROUND_HIGHLIGHT_KAHLUA_BENCH objects=${grounds.size * 1500} medianReferenceMs=${samples[0][2] / 1e6} " +
                "medianBridgeMs=${samples[1][2] / 1e6} (native read workload; no rendered-frame claim)",
        )
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        Core.debug = false
        val thread = environment()
        verify(GroundHighlight.SUPPORTED, "installed native classes are unsupported")
        distanceChecks(thread)
        matchesChecks(thread)
        benchmark(thread)
        println(
            "GROUND_HIGHLIGHT_CHECKS_PASS (native objects/cell/visibility, Kahlua parity/errors, exact ownership, unsupported and crossing benchmark)",
        )
        kotlin.system.exitProcess(0)
    }
}
