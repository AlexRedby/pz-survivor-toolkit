package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Method
import java.util.ArrayList
import java.util.LinkedHashMap
import se.krka.kahlua.integration.annotations.LuaMethod
import se.krka.kahlua.integration.expose.LuaJavaInvoker
import se.krka.kahlua.integration.expose.MultiLuaJavaInvoker
import se.krka.kahlua.integration.expose.caller.MethodCaller
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.j2se.J2SEPlatform
import zombie.Lua.LuaManager
import zombie.characters.IsoPlayer
import zombie.core.properties.PropertyContainer
import zombie.iso.IsoCell
import zombie.iso.IsoGridSquare
import zombie.iso.IsoObject
import zombie.iso.IsoWorld
import zombie.iso.SpriteDetails.IsoFlagType
import zombie.iso.objects.*
import zombie.iso.sprite.IsoSprite
import zombie.network.GameServer
import zombie.util.list.PZArrayList

/** Callback-free final observation of the pinned native walkAdj zero-child branch. */
object QueueSpatialFacts {
    @JvmField internal val SUPPORTED = arrayOf(
            "zombie/characters/IsoPlayer.class" to "3f1c4634d3a8e7e36baf4b33f76cf7ef79d88c3351bd0eb2a6a6bb34c2d9858f",
            "zombie/characters/IsoGameCharacter.class" to "29040e19c3e420499f73bc0ea0d5b86d7f7d38655acdc13d0107df736eb54c0b",
            "zombie/characters/BodyDamage/BodyDamage.class" to "e3509531e997649a240db7a8427a4d9df67582fe2460baf436ade26aae8c638e",
            "zombie/iso/IsoMovingObject.class" to "7e6e84fe9d3cb264e8d8e682d91e0abe919d481b7349d17b997e8a78f2293a5f",
            "zombie/iso/IsoObject.class" to "22387ecf47c1cf9aac192466de6298067f27584160c76a72baee38c6ad36dff2",
            "zombie/iso/IsoGridSquare.class" to "e8192f87d88da607abe0293228c84efbd822ed4ac0a331102c030bc3eeaba467",
            "zombie/iso/IsoCell.class" to "5e9a88e1cd9a3f370e31ae0152c9de381d649caea7cab750ebc82a91b4e1f767",
            "zombie/iso/IsoWorld.class" to "5b7406a70f33578a47ff417b0b6aa7a2b7a5bebfa00487a60935303f5747fb71",
            "zombie/iso/IsoChunkMap.class" to "7a64d736a95ba700afd2916ad7a93875ce39ce9390f7b1ea14197d1e90db49e4",
            "zombie/iso/IsoChunk.class" to "5048becc3f46f746686513d4dcadb137e6e11bfd44617075f41923b3db11650a",
            "zombie/core/properties/PropertyContainer.class" to "bc236f8e9e4e0da8a86b0d1fd19ad8d44a040fe4f67d1baac77401b3b148bd77",
            "zombie/iso/SpriteDetails/IsoFlagType.class" to "0c11206e0b8366e286d4d7e2aaa802d40f106463163397a59bc5d761f40a8bf9",
            "zombie/iso/sprite/IsoSprite.class" to "68c01e6b1c914f662621743e09c8dd8a62c0258392ce1a75654a713e1034067f",
            "zombie/util/list/PZArrayList.class" to "7ce79434a59558ed7c966d46d592d765ea6160949e0e87705002ccac7d4f5394",
            "zombie/iso/objects/IsoThumpable.class" to "cc19adbef73edbda83a56fdb727b70210278e6e4bd3c2c1def881dab804f8323",
            "zombie/iso/objects/IsoDoor.class" to "024bb36ef8a724c374ebf941b2dbf6ef3ccac4c0269ab2b8c55581a74689d929",
            "zombie/iso/objects/IsoWindow.class" to "41066d88458b7c88f25f893647cbb940af1f893315057813228932c5bafa92d9",
            "zombie/iso/objects/IsoBarricade.class" to "49b181237bee661405aa94284751269091d18b37a150aab20de4fb03525595e0",
            "zombie/iso/objects/IsoTelevision.class" to "58502db63f4714d60e681d801b39ff5da955c046635b04decd5ae857773c24ab",
            "zombie/iso/objects/IsoRadio.class" to "334f5b6d86b26c4ce2c5eec58a115d719f0b285223e9df9ed2aa8692685f8759",
            "zombie/iso/objects/IsoWaveSignal.class" to "1df260ed620eb4a1e2ea159f0da0beaf743a967a3e0a7312b03dca7728606f03",
            "zombie/iso/objects/IsoWorldInventoryObject.class" to "7be6f2d54525fa587908ce8efa7da5d26cfd3d19bd1cc02911ee12f7649857b3",
            "zombie/iso/objects/IsoTree.class" to "48b8b8aa39dbbb534700c2e979c6b38097cdcfab2938786f1b56166e510f396a",
            "se/krka/kahlua/j2se/KahluaTableImpl.class" to "101df1481366f976f76c037094e29f5ad21c71f5026dc3d0693f25d68b1c79f7",
            "se/krka/kahlua/vm/KahluaThread.class" to "25f4c0dea91800dcb3fadd3d482ed5f7d5cf17908bf167afd308b85c99856bb6",
            "se/krka/kahlua/integration/expose/LuaJavaInvoker.class" to "2c431080d2ce2b94966012e982e64b6d66cd1ae67af2eccd23e163fdfea24457",
            "se/krka/kahlua/integration/expose/MultiLuaJavaInvoker.class" to "ff446aca11076e954a84bc9a0d320d8a1939686c979d5b8ef7988842ed844155",
            "se/krka/kahlua/integration/expose/caller/MethodCaller.class" to "511ba515b1d0e6acd1671aea0195d37e3302eb7e992c73543a5844d6a5a6d098",
            "se/krka/kahlua/j2se/MathLib.class" to "8aaa15ef6da1a368a1e6b2f745a8bf88d952e9b9600e471fd8155e8486cb4a75",
            "se/krka/kahlua/j2se/J2SEPlatform.class" to "5c1ce45a49034dc05378475ee772e5d1645971fae475c57070770c8cba0af492",
            "se/krka/kahlua/integration/expose/LuaJavaClassExposer.class" to "4c8dc24c94de2cb814741f135d7d9baf8bc09062dd821d3c56cc4b09f322c0bd",
    ).all { (path, hash) -> BytecodeSupport.supports(path, hash) }

    private fun field(owner: Class<*>, name: String) = if (!SUPPORTED) null else try {
        owner.getDeclaredField(name).apply { isAccessible = true }
    } catch (_: Exception) { null }
    private val invokerCaller = field(LuaJavaInvoker::class.java, "caller")
    private val callerMethod = field(MethodCaller::class.java, "method")
    private val ignoredSprites = field(IsoGridSquare::class.java, "ignoreBlockingSprites")
    private val readMethod = QueueSpatialFacts::class.java.getMethod("noMovement", Any::class.java, Any::class.java, Any::class.java, Any::class.java)
    private val checkMethod = QueueSpatialFacts::class.java.getMethod("apiMatches", Any::class.java)
    private val getCellMethod = LuaManager.GlobalObject::class.java.getMethod("getCell")
    private val standardLibrary = J2SEPlatform().newEnvironment() as KahluaTableImpl
    private val standardAbs = (standardLibrary.delegate["math"] as KahluaTableImpl).delegate["abs"]
    private val standardIpairs = standardLibrary.delegate["ipairs"]
    // Expected methods are immutable build metadata. Effective Lua bindings,
    // world geometry and eligibility remain fresh on every observation.
    private fun methodGroups(type: Class<*>, vararg names: String): Map<String, Set<Method>> {
        val methods = type.methods
        return java.util.Map.copyOf(names.associateWith { name ->
            java.util.Set.copyOf(methods.filter {
                it.name == name && !java.lang.reflect.Modifier.isStatic(it.modifiers)
            })
        })
    }
    private val actorMethods = methodGroups(IsoPlayer::class.java,"getX","getY","getSquare","getCurrentSquare")
    private val squareMethods = methodGroups(IsoGridSquare::class.java,"getX","getY","getZ","has","canReachTo")

    internal fun canonicalApi(function: Any?, expected: Method = readMethod): Boolean {
        if (!SUPPORTED) return false
        val single = when (function?.javaClass) {
            LuaJavaInvoker::class.java -> function as LuaJavaInvoker
            MultiLuaJavaInvoker::class.java -> {
                val values = (function as MultiLuaJavaInvoker).invokers
                if (values.javaClass != ArrayList::class.java || values.size != 1) return false
                values[0]
            }
            else -> return false
        }
        if (single.javaClass != LuaJavaInvoker::class.java) return false
        val caller = invokerCaller?.get(single) ?: return false
        return caller.javaClass == MethodCaller::class.java && callerMethod?.get(caller) == expected
    }
    private fun plain(value: Any?): KahluaTableImpl? {
        return direct(value)?.takeIf { it.metatable == null }
    }
    private fun direct(value: Any?): KahluaTableImpl? {
        if (value?.javaClass != KahluaTableImpl::class.java) return null
        return (value as KahluaTableImpl).takeIf {
            it.rewriteTable == null && it.delegate.javaClass == LinkedHashMap::class.java
        }
    }
    private fun lookup(value: Any?, key: String): Any? {
        var table = direct(value) ?: return null
        val seen = java.util.IdentityHashMap<KahluaTableImpl, Boolean>()
        repeat(8) {
            if (seen.put(table, true) != null) return null
            table.delegate[key]?.let { return it }
            val parent = direct(table.metatable) ?: return null
            table = direct(parent.delegate["__index"]) ?: return null
        }
        return null
    }
    private fun methodsMatch(function: Any?, expected: Set<Method>): Boolean {
        if (expected.isEmpty() || expected.size > 16) return false
        val functions = when (function?.javaClass) {
            LuaJavaInvoker::class.java -> listOf(function as LuaJavaInvoker)
            MultiLuaJavaInvoker::class.java -> {
                val values = (function as MultiLuaJavaInvoker).invokers
                if (values.javaClass != ArrayList::class.java || values.size > 16) return false
                values
            }
            else -> return false
        }
        if (functions.size != expected.size) return false
        val observed = HashSet<Method>()
        for (single in functions) {
            if (single.javaClass != LuaJavaInvoker::class.java) return false
            val caller = invokerCaller?.get(single) ?: return false
            if (caller.javaClass != MethodCaller::class.java) return false
            val method = callerMethod?.get(caller) as? Method ?: return false
            if (method !in expected || !observed.add(method)) return false
        }
        return observed == expected
    }
    private fun nativeBindings(actor: IsoPlayer, target: IsoGridSquare, current: IsoGridSquare, corrected: IsoGridSquare): Boolean {
        val env = plain(LuaManager.env) ?: return false
        if (!canonicalApi(env.delegate["getCell"], getCellMethod) ||
            plain(env.delegate["math"])?.delegate?.get("abs") !== standardAbs ||
            env.delegate["ipairs"] !== standardIpairs) return false
        val flags = direct(env.delegate["IsoFlagType"]) ?: return false
        if (lookup(flags,"collideW") !== IsoFlagType.collideW || lookup(flags,"collideN") !== IsoFlagType.collideN) return false
        val classes = direct(env.delegate["__classmetatables"]) ?: return false
        fun receiver(value: Any, expected: Map<String, Set<Method>>): Boolean {
            val meta = direct(classes.delegate[value.javaClass]) ?: return false
            val methods = direct(meta.delegate["__index"]) ?: return false
            for ((name,group) in expected) if (!methodsMatch(lookup(methods,name),group)) return false
            return true
        }
        if (!receiver(actor,actorMethods)) return false
        for (square in setOf(target,current,corrected)) {
            if (!receiver(square,squareMethods)) return false
        }
        return true
    }
    private fun entry(name: String, method: Method, arguments: Array<Any?>): Boolean {
        if (!SUPPORTED) return false
        val thread = LuaManager.thread ?: return false
        if (thread.debugOwnerThread !== Thread.currentThread()) return false
        val env = plain(LuaManager.env) ?: return false
        val frame = thread.currentCoroutine?.currentCallFrame() ?: return false
        if (frame.nArguments != arguments.size || !canonicalApi(frame.javaFunction, method)
            || frame.javaFunction !== env.delegate[name]) return false
        for (index in arguments.indices) if (frame.get(index) !== arguments[index]) return false
        return true
    }

    /** Trusted bootstrap root, like toolkitLuaMetatableMatches; no Lua callback is invoked. */
    @JvmStatic @LuaMethod(name = "toolkitQueueSpatialApiMatches", global = true)
    fun apiMatches(function: Any?): Boolean = try {
        entry("toolkitQueueSpatialApiMatches", checkMethod, arrayOf(function)) && canonicalApi(function)
            && plain(LuaManager.env)?.delegate?.get("toolkitQueueSpatialNoMovement") === function
    } catch (_: Exception) { false } catch (_: AssertionError) { false }

    @JvmStatic @LuaMethod(name = "toolkitQueueSpatialNoMovement", global = true)
    fun noMovement(actor: Any?, target: Any?, exclusions: Any?, targetObject: Any?): Boolean = try {
        entry("toolkitQueueSpatialNoMovement", readMethod, arrayOf(actor, target, exclusions, targetObject)) &&
            read(actor, target, exclusions, targetObject, SUPPORTED, true, true)
    } catch (_: Exception) { false } catch (_: AssertionError) { false }

    private val objectClasses = setOf(IsoObject::class.java, IsoDoor::class.java, IsoWindow::class.java,
        IsoThumpable::class.java, IsoBarricade::class.java, IsoTelevision::class.java, IsoRadio::class.java,
        IsoWorldInventoryObject::class.java, IsoTree::class.java)
    private fun properties(square: IsoGridSquare): Boolean = square.getProperties()?.javaClass == PropertyContainer::class.java
    private fun loaded(square: IsoGridSquare?, cell: IsoCell): Boolean = square != null &&
        square.javaClass == IsoGridSquare::class.java && cell.getGridSquare(square.getX(), square.getY(), square.getZ()) === square
    private fun safeObjects(square: IsoGridSquare): Boolean {
        if (!properties(square)) return false
        val objects = square.getObjects() ?: return false
        val special = square.getSpecialObjects() ?: return false
        if (objects.javaClass != PZArrayList::class.java || objects.size > 256 ||
            special.javaClass != ArrayList::class.java || special.size > 256) return false
        fun safe(value: IsoObject?): Boolean {
            if (value == null || value.javaClass !in objectClasses) return false
            val sprite = value.getSprite()
            if (sprite != null && (sprite.javaClass != IsoSprite::class.java ||
                sprite.getProperties()?.javaClass != PropertyContainer::class.java)) return false
            return true
        }
        for (index in 0 until objects.size) if (!safe(objects[index])) return false
        for (index in 0 until special.size) if (!safe(special[index])) return false
        return true
    }
    private fun safeReach(current: IsoGridSquare, target: IsoGridSquare, cell: IsoCell): Boolean {
        if (current === target) return true // Native canReachTo returns before inspecting objects.
        if (current.getZ() != target.getZ() || kotlin.math.abs(current.getX().toLong() - target.getX()) > 1 ||
            kotlin.math.abs(current.getY().toLong() - target.getY()) > 1) return false
        val ignored = ignoredSprites?.get(null) ?: return false
        if (ignored.javaClass != ArrayList::class.java || (ignored as ArrayList<*>).size > 128 ||
            ignored.any { it !is String }) return false
        // Diagonal reachability may inspect either intermediate edge square.
        for (x in minOf(current.getX(), target.getX())..maxOf(current.getX(), target.getX())) {
            for (y in minOf(current.getY(), target.getY())..maxOf(current.getY(), target.getY())) {
                val square = cell.getGridSquare(x, y, current.getZ()) ?: return false
                if (!safeObjects(square)) return false
            }
        }
        return current.canReachTo(target)
    }

    /** Gates are explicit negative-test seams. Production always reads the owner/build itself. */
    internal fun read(actorValue: Any?, targetValue: Any?, exclusionsValue: Any?, targetObject: Any?, supported: Boolean, owner: Boolean, certifyBindings: Boolean = false): Boolean {
      return try {
        if (!supported || !owner || GameServer.server || actorValue?.javaClass != IsoPlayer::class.java ||
            targetValue?.javaClass != IsoGridSquare::class.java) return false
        val actor = actorValue as IsoPlayer
        val target = targetValue as IsoGridSquare
        // PathFindBehavior2 sets the base isMoving latch, but timed walking
        // completion does not reset it. Local input resets/recomputes justMoved
        // each tick; isPlayerMoving includes that signal and current path motion.
        if (!actor.isLocalPlayer() || actor.isDead() || actor.isPlayerMoving() || actor.isJustMoved() ||
            actor.getPath2() != null || actor.isPathfindRunning()) return false
        if (targetObject != null) {
            if (targetObject.javaClass != IsoObject::class.java && targetObject.javaClass != IsoRadio::class.java &&
                targetObject.javaClass != IsoTelevision::class.java) return false
            val bound = targetObject as IsoObject
            val objects = target.getObjects() ?: return false
            if (objects.javaClass != PZArrayList::class.java || objects.size > 256) return false
            if (bound.getSquare() !== target || bound.getObjectIndex() < 0) return false
        }
        val cell = IsoWorld.instance.currentCell ?: return false
        val current = actor.getSquare()
        if (!loaded(current, cell) || actor.getCurrentSquare() !== current || !loaded(target, cell) || !properties(target)) return false
        val z = actor.getZ().toDouble()
        if (!z.isFinite() || kotlin.math.floor(z) != current!!.getZ().toDouble()) return false
        if (exclusionsValue != null) {
            val exclusions = plain(exclusionsValue) ?: return false
            val count = exclusions.delegate.size
            if (count > 32) return false
            for (index in 1..count) {
                val square = exclusions.delegate[index.toDouble()]
                if (square?.javaClass != IsoGridSquare::class.java || square === current) return false
            }
        }
        val x = actor.getX().toDouble()
        val y = actor.getY().toDouble()
        if (!x.isFinite() || !y.isFinite() || kotlin.math.floor(x) != current.getX().toDouble() ||
            kotlin.math.floor(y) != current.getY().toDouble() || kotlin.math.abs(z-current.getZ()) > .001) return false
        // Preserve native west-before-north correction and double arithmetic.
        val corrected = when {
            target.has(IsoFlagType.collideW) && x < target.getX() -> cell.getGridSquare(target.getX() + 1, target.getY(), target.getZ())
            target.has(IsoFlagType.collideN) && y < target.getY() -> cell.getGridSquare(target.getX(), target.getY() + 1, target.getZ())
            else -> target
        }
        if (!loaded(corrected, cell)) return false
        if (certifyBindings && !nativeBindings(actor,target,current,corrected!!)) return false
        kotlin.math.abs(corrected!!.getX() + .5 - x) <= 1.6 && kotlin.math.abs(corrected.getY() + .5 - y) <= 1.6 &&
            safeReach(current, corrected, cell)
      } catch (_: Exception) { false } catch (_: AssertionError) { false }
    }
}
