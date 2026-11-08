package net.alexredby.pztoolkitjavapatches

import java.util.ArrayList
import java.util.LinkedHashMap
import me.zed_0xff.zombie_buddy.Exposer
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.integration.expose.LuaJavaInvoker
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.KahluaThread
import sun.misc.Unsafe
import zombie.Lua.KahluaNumberConverter
import zombie.Lua.LuaManager
import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.core.properties.PropertyContainer
import zombie.iso.IsoCell
import zombie.iso.IsoChunk
import zombie.iso.IsoChunkMap
import zombie.iso.IsoGridSquare
import zombie.iso.IsoMovingObject
import zombie.iso.IsoObject
import zombie.iso.IsoWorld
import zombie.iso.SpriteDetails.IsoFlagType
import zombie.network.GameServer
import zombie.pathfind.Path
import zombie.util.list.PZArrayList

/** Actual native world reads and Kahlua Java invokers; no game process or route runs. */
object QueueSpatialFactsChecks {
    private var forbiddenCalls = 0
    private val unsafe = Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null) as Unsafe
    private fun <T> bare(type: Class<T>): T = type.cast(unsafe.allocateInstance(type))
    private fun field(type: Class<*>, target: Any, name: String, value: Any?) {
        type.getDeclaredField(name).apply { isAccessible = true }.set(target, value)
    }
    private fun square(x: Int, y: Int, z: Int = 0): IsoGridSquare = bare(IsoGridSquare::class.java).also {
        field(IsoGridSquare::class.java, it, "x", x);field(IsoGridSquare::class.java, it, "y", y);field(IsoGridSquare::class.java, it, "z", z)
        field(IsoGridSquare::class.java, it, "properties", PropertyContainer())
        field(IsoGridSquare::class.java, it, "objects", PZArrayList(IsoObject::class.java, 8))
        field(IsoGridSquare::class.java, it, "specialObjects", ArrayList<IsoObject>())
        field(IsoGridSquare::class.java, it, "nav", arrayOfNulls<IsoGridSquare>(8))
    }
    private class Fixture {
        val actor = bare(IsoPlayer::class.java)
        val current = square(2, 2)
        val east = square(3, 2)
        val south = square(2, 3)
        val southeast = square(3, 3)
        val targetObject = bare(IsoObject::class.java)
        val grid = arrayOf(arrayOfNulls<IsoGridSquare>(64))
        init {
            field(IsoGameCharacter::class.java, actor, "health", 100f)
            field(IsoMovingObject::class.java, actor, "current", current)
            actor.setX(2.5f);actor.setY(2.5f)
            IsoPlayer.players[0] = actor;IsoPlayer.numPlayers = 1
            field(IsoObject::class.java, targetObject, "square", current)
            current.getObjects().add(targetObject)
            val cell = bare(IsoCell::class.java)
            val chunk = bare(IsoChunk::class.java)
            for (square in arrayOf(current, east, south, southeast)) grid[0][square.getX() + square.getY() * 8] = square
            field(IsoChunk::class.java, chunk, "squares", grid)
            field(IsoChunk::class.java, chunk, "minLevel", 0);field(IsoChunk::class.java, chunk, "maxLevel", 0)
            field(IsoChunk::class.java, chunk, "loaded", true)
            val map = bare(IsoChunkMap::class.java)
            field(IsoChunkMap::class.java, map, "chunksSwapA", arrayOf(chunk));field(IsoChunkMap::class.java, map, "chunksSwapB", arrayOf(chunk))
            field(IsoCell::class.java, cell, "chunkMap", arrayOf(map))
            IsoChunkMap.chunkGridWidth = 1;IsoChunkMap.chunkWidthInTiles = 8
            IsoWorld.instance.currentCell = cell
        }
        fun read(target: Any? = current, exclusions: Any? = null, objectValue: Any? = null, supported: Boolean = true, owner: Boolean = true) =
            QueueSpatialFacts.read(actor, target, exclusions, objectValue, supported, owner)
    }
    private fun table(vararg values: Any?): KahluaTableImpl = KahluaTableImpl(LinkedHashMap<Any, Any?>()).also {
        for (index in values.indices) it.delegate[(index + 1).toDouble()] = values[index]
    }
    private class ForeignPlayer : IsoPlayer(null) {
        override fun getX(): Float { forbiddenCalls++;error("foreign player getter invoked") }
    }
    private class ForeignObject : IsoObject() {
        override fun getSquare(): IsoGridSquare? { forbiddenCalls++;error("foreign bound-object getter invoked") }
    }
    private class ForeignList : ArrayList<IsoObject>() {
        override fun get(index: Int): IsoObject { forbiddenCalls++;error("foreign world-list getter invoked") }
    }
    @JvmStatic fun foreign(actor: Any?, target: Any?, excluded: Any?, targetObject: Any?): Boolean = true
    @JvmStatic fun forwarding(actor: Any?, target: Any?, excluded: Any?, targetObject: Any?): Boolean =
        QueueSpatialFacts.noMovement(actor, target, excluded, targetObject)

    @JvmStatic fun main(arguments: Array<String>) {
        check(QueueSpatialFacts.SUPPORTED) { "native spatial classes are unsupported" }
        check(java.lang.reflect.Modifier.isFinal(IsoGridSquare::class.java.modifiers))
        check(java.lang.reflect.Modifier.isFinal(IsoCell::class.java.modifiers))
        val f = Fixture()
        check(f.read()) { "same-square native baseline" }
        check(f.read(objectValue = f.targetObject)) { "bound object baseline" }
        check(f.read(f.east)) { "adjacent native reachable baseline" }
        check(f.read(f.southeast)) { "diagonal native reachable baseline" }
        check(!f.read(supported = false));check(!f.read(owner = false))
        check(!f.read(exclusions = table(f.current)))
        check(f.read(exclusions = table(f.east)))
        val sparse = table();sparse.delegate[2.0] = f.east
        check(!f.read(exclusions = sparse))
        val malformed = table(f.east);malformed.delegate["unexpected"] = f.east
        check(!f.read(exclusions = malformed))
        val huge = table();repeat(33) { huge.delegate[(it + 1).toDouble()] = f.east }
        check(!f.read(exclusions = huge))
        val inherited = table();inherited.metatable = table()
        check(!f.read(exclusions = inherited))
        f.actor.setX(20f);check(!f.read());f.actor.setX(Float.NaN);check(!f.read());f.actor.setX(2.5f)
        field(IsoGameCharacter::class.java, f.actor, "health", 0f);check(!f.read())
        field(IsoGameCharacter::class.java, f.actor, "health", 100f)
        IsoPlayer.players[0] = null;check(!f.read());IsoPlayer.players[0] = f.actor
        GameServer.server = true;check(!f.read());GameServer.server = false
        f.grid[0][2 + 2 * 8] = square(2,2);check(!f.read());f.grid[0][2 + 2 * 8] = f.current
        field(IsoObject::class.java, f.targetObject, "square", f.east)
        check(!f.read(objectValue = f.targetObject));field(IsoObject::class.java, f.targetObject, "square", f.current)
        f.current.getObjects().clear();check(!f.read(objectValue = f.targetObject));f.current.getObjects().add(f.targetObject)
        f.current.getProperties().set(IsoFlagType.collideW)
        f.actor.setX(1.99f);check(!f.read()) { "stale pose must not borrow native correction authority" }
        f.grid[0][3 + 2 * 8] = null;check(!f.read()) { "unloaded corrected square" }
        f.grid[0][3 + 2 * 8] = f.east
        f.current.getProperties().unset(IsoFlagType.collideW);f.actor.setX(2.5f)
        f.east.getProperties().set(IsoFlagType.collideW);check(!f.read(f.east)) { "blocked native neighbor" }
        f.east.getProperties().unset(IsoFlagType.collideW)
        val wrongLevel = square(2, 2, 1)
        check(!f.read(wrongLevel))
        check(!QueueSpatialFacts.read(Any(), f.current, null, null, true, true))
        check(!QueueSpatialFacts.read(f.actor, Any(), null, null, true, true))
        check(!QueueSpatialFacts.read(bare(ForeignPlayer::class.java), f.current, null, null, true, true))
        check(!f.read(objectValue = bare(ForeignObject::class.java)))
        field(IsoGridSquare::class.java, f.east, "specialObjects", ForeignList())
        check(!f.read(f.east)) { "foreign native list must remain uncalled" }
        field(IsoGridSquare::class.java, f.east, "specialObjects", ArrayList<IsoObject>())
        f.actor.setZ(1f);check(!f.read()) { "actor current-level mismatch" };f.actor.setZ(0f)
        f.actor.setZ(.01f);check(!f.read()) { "fractional actor level" };f.actor.setZ(0f)
        f.actor.setY(1.99f);check(!f.read()) { "actor current-row mismatch" };f.actor.setY(2.5f)
        // The actual native accessor can remain true after completed walking;
        // that base latch is distinct from current local-player locomotion.
        field(IsoGameCharacter::class.java,f.actor,"isMoving",true)
        check(f.actor.isMoving() && !f.actor.isJustMoved() && !f.actor.isPlayerMoving()) { "native stale-moving fixture" }
        check(f.read()) { "stationary native isMoving latch rejected a no-movement edit" }
        field(IsoPlayer::class.java,f.actor,"justMoved",true);check(!f.read()) { "current local movement intent" }
        field(IsoPlayer::class.java,f.actor,"justMoved",false)
        field(IsoPlayer::class.java,f.actor,"isPlayerMoving",true);check(!f.read()) { "active local locomotion" }
        field(IsoPlayer::class.java,f.actor,"isPlayerMoving",false)
        f.actor.setPath2(bare(Path::class.java));check(!f.read());f.actor.setPath2(null)
        f.actor.setPathfindRunning(true);check(!f.read());f.actor.setPathfindRunning(false)
        field(IsoGameCharacter::class.java,f.actor,"isMoving",false)
        check(forbiddenCalls == 0) { "foreign native getter/list callback was invoked and swallowed" }

        LuaManager.platform = J2SEPlatform();LuaManager.env = LuaManager.platform.newEnvironment()
        val converters = KahluaConverterManager();KahluaNumberConverter.install(converters)
        LuaManager.exposer = LuaManager.Exposer(converters, LuaManager.platform, LuaManager.env)
        for (type in arrayOf(IsoPlayer::class.java,IsoGridSquare::class.java,IsoFlagType::class.java)) {
            LuaManager.exposer.setExposed(type);LuaManager.exposer.exposeLikeJava(type,LuaManager.env)
        }
        LuaManager.exposer.exposeGlobalClassFunction(LuaManager.env,LuaManager.GlobalObject::class.java,
            LuaManager.GlobalObject::class.java.getMethod("getCell"),"getCell")
        check(Exposer.hasGlobalLuaMethod(QueueSpatialFacts::class.java)) { "runtime annotation scanner omitted helper" }
        Exposer.addClassWithGlobalLuaMethod(QueueSpatialFacts::class.java);Exposer.afterExposeAll()
        val helper = LuaManager.env.rawget("toolkitQueueSpatialNoMovement")
        val checker = LuaManager.env.rawget("toolkitQueueSpatialApiMatches")
        check(helper is LuaJavaInvoker && checker is LuaJavaInvoker) { "runtime annotation exposure omitted globals" }
        val thread = KahluaThread(LuaManager.platform, LuaManager.env).apply { debugOwnerThread = Thread.currentThread() }
        LuaManager.thread = thread
        val args = arrayOf<Any?>(f.actor, f.current, null, f.targetObject)
        check(thread.call(checker, arrayOf(helper)) == true) { "canonical helper certificate" }
        check(thread.call(helper, args) == true) { "real Kahlua native final-read crossing" }
        check(!QueueSpatialFacts.noMovement(f.actor, f.current, null, null)) { "unframed Java call borrowed native Lua entry" }
        LuaManager.env.rawset("originalHelper", helper);LuaManager.env.rawset("originalChecker", checker)
        fun lua(source: String) = thread.call(LuaCompiler.loadstring(source, "spatial-check", LuaManager.env), null)
        lua("callbacks=0; toolkitQueueSpatialNoMovement=function(...) callbacks=callbacks+1; return originalHelper(...) end")
        check(thread.call(checker, arrayOf(helper)) == false)
        check(thread.call(helper, args) == false) { "forwarding Lua override retained helper authority" }
        LuaManager.env.rawset("toolkitQueueSpatialNoMovement", helper)
        lua("toolkitQueueSpatialApiMatches=function(...) return originalChecker(...) end")
        check(thread.call(checker, arrayOf(helper)) == false) { "checker forwarding override retained bootstrap authority" }
        LuaManager.env.rawset("toolkitQueueSpatialApiMatches", checker)
        for (name in listOf("foreign", "forwarding")) {
            LuaManager.env.rawset("foreignHelper", null)
            val method = QueueSpatialFactsChecks::class.java.getMethod(name, Any::class.java, Any::class.java, Any::class.java, Any::class.java)
            LuaManager.exposer.exposeGlobalClassFunction(LuaManager.env, QueueSpatialFactsChecks::class.java, method, "foreignHelper")
            val foreign = LuaManager.env.rawget("foreignHelper")
            check(foreign is LuaJavaInvoker && !QueueSpatialFacts.canonicalApi(foreign))
            LuaManager.env.rawset("toolkitQueueSpatialNoMovement", foreign)
            check(thread.call(checker, arrayOf(foreign)) == false) { "foreign same-class invoker certified" }
            if (name == "forwarding") check(thread.call(foreign, args) == false)
        }
        LuaManager.env.rawset("toolkitQueueSpatialNoMovement", helper)
        val sentinel = table();sentinel.metatable = table()
        check(thread.call(helper, arrayOf(f.actor, f.current, sentinel, null)) == false)
        lua("function MustNeverRun() callbacks=callbacks+1; error('native observation executed a Lua getter') end")
        val forbidden = LuaManager.env.rawget("MustNeverRun")
        val classes = (LuaManager.env as KahluaTableImpl).delegate["__classmetatables"] as KahluaTableImpl
        for ((type,name) in listOf(IsoPlayer::class.java to "getX",IsoGridSquare::class.java to "has",IsoGridSquare::class.java to "canReachTo")) {
            val meta = classes.delegate[type] as KahluaTableImpl
            val methods = meta.delegate["__index"] as KahluaTableImpl
            val original = methods.delegate[name]
            methods.delegate[name] = forbidden
            check(thread.call(helper,args) == false) { "Lua $name override retained native branch authority" }
            methods.delegate[name] = original
        }
        val getCell = LuaManager.env.rawget("getCell");LuaManager.env.rawset("getCell",forbidden)
        check(thread.call(helper,args) == false) { "Lua global getCell override retained native branch authority" }
        LuaManager.env.rawset("getCell",getCell)
        val math = LuaManager.env.rawget("math") as KahluaTableImpl
        val abs = math.delegate["abs"]
        for (replacement in arrayOf(forbidden,math.delegate["floor"])) {
            math.delegate["abs"] = replacement
            check(thread.call(helper,args) == false) { "foreign math.abs role retained native branch authority" }
        }
        math.delegate["abs"] = abs
        check(thread.call(helper,args) == true) { "restored native API bindings" }
        check(LuaManager.env.rawget("callbacks") == 0.0) { "observation invoked a Lua callback" }
        thread.debugOwnerThread = null;check(thread.call(helper, args) == false)
        thread.debugOwnerThread = Thread.currentThread()
        var result = true
        Thread { result = QueueSpatialFacts.noMovement(f.actor, f.current, null, null) }.apply { start();join() }
        check(!result) { "foreign thread retained native ownership" }
        println("QUEUE_SPATIAL_FACTS_CHECKS_PASS")
    }
}
