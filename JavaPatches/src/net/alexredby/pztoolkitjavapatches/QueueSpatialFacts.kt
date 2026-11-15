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
import zombie.radio.devices.DeviceData

/** Callback-free final observation of the pinned native walkAdj zero-child branch. */
object QueueSpatialFacts {
    @JvmField internal val SUPPORTED = arrayOf(
            "zombie/characters/IsoPlayer.class" to "643585044a88ad1b29e8d5173774f66085c685c363ed10a89c0b79018de2874e",
            "zombie/characters/IsoGameCharacter.class" to "1ccabc492ba130f51486bf38a8400334545852253bbac9c46fff71242ab672f6",
            "zombie/characters/BodyDamage/BodyDamage.class" to "b8e5d774f9bed459dbf34590ab304a12ad5ecc56c26e2a37d6600a9817bfb8e6",
            "zombie/iso/IsoMovingObject.class" to "70c0249c3bdb7b4c4fc335e644c74bc98c37aa0e4bfdc0665a75521460ea0900",
            "zombie/iso/IsoObject.class" to "7a99d06875c19ff132940d7192b414496537076e83474db0abc0cb38de6be70a",
            "zombie/iso/IsoGridSquare.class" to "b8cef32a10bb76433bad174397b51f1a046be1eef47997dc1e79dd8547d726c5",
            "zombie/iso/IsoCell.class" to "6c261778f1fac0c660ba8b6167b9bf5d318e8bd126378e3c1b3667c9469910ab",
            "zombie/iso/IsoWorld.class" to "e17f9d3266154e7715237656612832123a9032e7bb9ff73ae7a29ecdf73374df",
            "zombie/iso/IsoChunkMap.class" to "7a64d736a95ba700afd2916ad7a93875ce39ce9390f7b1ea14197d1e90db49e4",
            "zombie/iso/IsoChunk.class" to "b069a07b79dc86d2a1133dff187fdcde904e1fe9a9d2f066b877b9ea0ea31af8",
            "zombie/core/properties/PropertyContainer.class" to "400d434ad860a39feb745f1033a63dca446d6f93d8b1a2ec4c343b166b658959",
            "zombie/iso/SpriteDetails/IsoFlagType.class" to "0c11206e0b8366e286d4d7e2aaa802d40f106463163397a59bc5d761f40a8bf9",
            "zombie/iso/sprite/IsoSprite.class" to "498f94e38b171ed0eb528b3ab3b90cbf0d152cc81bfe9a3e1345825a627a04ce",
            "zombie/iso/objects/IsoThumpable.class" to "61893a53f89547abf25dd8459aaf1fb43051bee39866f578f3aee7f074e6c47d",
            "zombie/iso/objects/interfaces/GridSquareEdgeElement.class" to "3cb116b623c2115e4fe80698e34e3aa366c403c36428527fbd38d0cb91fcf9d6",
            "zombie/iso/objects/GridSquareEdgeFacingDirection.class" to "e4b51f30b99d9e6edecf9a5e23ca376a0ea933c92d48fb12e490402ee0bfa5d5",
            "zombie/iso/objects/IsoDoor.class" to "07bd820e06017aa831aa18706cf0f3af00cab0f046d804e4711e517e9c8d9019",
            "zombie/iso/objects/IsoWindow.class" to "9e9c03479f8ff97b984689870daf322dbf0b5cb492676c0ac86bc11d5b21c5cf",
            "zombie/iso/objects/IsoBarricade.class" to "ec42e234375fc3bfa2c8548ff284416c0235304a05bee967a37a5690110ac972",
            "zombie/iso/objects/IsoTelevision.class" to "58502db63f4714d60e681d801b39ff5da955c046635b04decd5ae857773c24ab",
            "zombie/iso/objects/IsoRadio.class" to "334f5b6d86b26c4ce2c5eec58a115d719f0b285223e9df9ed2aa8692685f8759",
            "zombie/iso/objects/IsoWaveSignal.class" to "5d70c0d2147eaed07f91bf5b9337c4bce7ee47b91e171803ba829903d8ff1cf7",
            "zombie/iso/objects/IsoWorldInventoryObject.class" to "1019fd27cfce76d84a8db499a71568429e87e95de504e041a202e0ba9c01ee0b",
            "zombie/iso/objects/IsoTree.class" to "58a2f9cc749b5fba729debb43407fae12c18ec83dee3bc4125fe17968962c44c",
            "se/krka/kahlua/j2se/KahluaTableImpl.class" to "1e79dbff83e85c8863df63f7847d3a506fddbaefa423cb676734751599db1aea",
            "se/krka/kahlua/vm/KahluaThread.class" to "25f4c0dea91800dcb3fadd3d482ed5f7d5cf17908bf167afd308b85c99856bb6",
            "se/krka/kahlua/integration/expose/LuaJavaInvoker.class" to "2c431080d2ce2b94966012e982e64b6d66cd1ae67af2eccd23e163fdfea24457",
            "se/krka/kahlua/integration/expose/MultiLuaJavaInvoker.class" to "ff446aca11076e954a84bc9a0d320d8a1939686c979d5b8ef7988842ed844155",
            "se/krka/kahlua/integration/expose/caller/MethodCaller.class" to "511ba515b1d0e6acd1671aea0195d37e3302eb7e992c73543a5844d6a5a6d098",
            "se/krka/kahlua/j2se/MathLib.class" to "8aaa15ef6da1a368a1e6b2f745a8bf88d952e9b9600e471fd8155e8486cb4a75",
            "se/krka/kahlua/j2se/J2SEPlatform.class" to "5c1ce45a49034dc05378475ee772e5d1645971fae475c57070770c8cba0af492",
            "se/krka/kahlua/integration/expose/LuaJavaClassExposer.class" to "ea8bf95fab20182b62d3fe41c44ebf621b592cfdc48df89aed8795135d3c966c",
    ).all { (path, hash) -> BytecodeSupport.supports(path, hash) }

    @JvmField internal val DEVICE_SUPPORTED = SUPPORTED && BytecodeSupport.supports(
        "zombie/radio/devices/DeviceData.class", "6c8825dbc39b2a7508a903dd3ef381bbb3dbd9b96f89398d9deeaddde0162bed")

    private fun field(owner: Class<*>, name: String) = if (!SUPPORTED) null else try {
        owner.getDeclaredField(name).apply { isAccessible = true }
    } catch (_: Exception) { null }
    private val invokerCaller = field(LuaJavaInvoker::class.java, "caller")
    private val callerMethod = field(MethodCaller::class.java, "method")
    private val ignoredSprites = field(IsoGridSquare::class.java, "ignoreBlockingSprites")
    private val readMethod = QueueSpatialFacts::class.java.getMethod("noMovement", Any::class.java, Any::class.java, Any::class.java, Any::class.java)
    private val checkMethod = QueueSpatialFacts::class.java.getMethod("apiMatches", Any::class.java)
    private val deviceMethod = QueueSpatialFacts::class.java.getMethod("deviceTarget", Any::class.java, Any::class.java, Any::class.java, Any::class.java)
    private val deviceCheckMethod = QueueSpatialFacts::class.java.getMethod("deviceApiMatches", Any::class.java)
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
        if (thread.environment !== env) return false
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

    // Opaque to Lua: no mutable table, registry or exposed accessors retain ownership.
    private class DeviceAnchor(
        val device: IsoWaveSignal,
        val data: DeviceData,
        val square: IsoGridSquare,
        val cell: IsoCell,
        val x: Int,
        val y: Int,
        val z: Int,
    )

    @JvmStatic @LuaMethod(name = "toolkitQueueDeviceApiMatches", global = true)
    fun deviceApiMatches(function: Any?): Boolean = try {
        DEVICE_SUPPORTED && entry("toolkitQueueDeviceApiMatches", deviceCheckMethod, arrayOf(function)) &&
            canonicalApi(function, deviceMethod) &&
            plain(LuaManager.env)?.delegate?.get("toolkitQueueDeviceTarget") === function
    } catch (_: Exception) { false } catch (_: AssertionError) { false }

    /**
     * Four explicit Lua arguments, including nil for absent anchor/routeSquare.
     * Capture returns an opaque anchor or nil; validation returns true/live,
     * false/definite binding loss, or nil/unsupported or currently unknown world.
     * A nil device resolves the native parent only during capture; checks use
     * the original anchor body. routeSquare must identify the original square.
     */
    @JvmStatic @LuaMethod(name = "toolkitQueueDeviceTarget", global = true)
    fun deviceTarget(device: Any?, data: Any?, anchor: Any?, routeSquare: Any?): Any? = try {
        if (!entry("toolkitQueueDeviceTarget", deviceMethod, arrayOf(device, data, anchor, routeSquare))) null
        else readDeviceTarget(device, data, anchor, routeSquare, DEVICE_SUPPORTED, true)
    } catch (_: Exception) { null } catch (_: AssertionError) { null }

    /** Explicit negative-test seams; production always obtains build/owner from entry. */
    internal fun readDeviceTarget(deviceValue: Any?, dataValue: Any?, anchorValue: Any?, routeSquare: Any?, supported: Boolean, owner: Boolean): Any? {
        return try {
            if (!supported || !owner || GameServer.server || dataValue?.javaClass != DeviceData::class.java) return null
            val data = dataValue as DeviceData
            val anchor = if (anchorValue == null) null else anchorValue as? DeviceAnchor
            if (anchorValue != null && anchor == null) return null
            // Only capture resolves the native parent. Validation retains the original
            // body even if the captured DeviceData was subsequently rebound elsewhere.
            val candidate = deviceValue ?: anchor?.device ?: data.getParent()
            if (candidate?.javaClass != IsoTelevision::class.java && candidate?.javaClass != IsoRadio::class.java) return null
            val device = candidate as IsoWaveSignal
            if (anchor != null && (anchor.device !== device || anchor.data !== data) ||
                routeSquare != null && routeSquare !== (anchor?.square ?: device.getSquare())) return null
            if (anchor != null && (device.getSquare() !== anchor.square ||
                device.getDeviceData() !== data || data.getParent() !== device ||
                anchor.square.getX() != anchor.x || anchor.square.getY() != anchor.y ||
                anchor.square.getZ() != anchor.z)) return false
            val square = device.getSquare()
            val world = IsoWorld.instance
            val cell = world?.currentCell
            if (square?.javaClass != IsoGridSquare::class.java ||
                world?.javaClass != IsoWorld::class.java || cell?.javaClass != IsoCell::class.java ||
                anchor != null && cell !== anchor.cell || !loaded(square, cell)) return null
            val objects = square.getObjects()
            if (objects?.javaClass != ArrayList::class.java || objects.size > 256) return null
            var member = false
            for (index in 0 until objects.size) if (objects[index] === device) { member = true; break }
            if (!member || device.getDeviceData() !== data || data.getParent() !== device) {
                if (anchor != null) false else null
            } else anchor?.let { true } ?: DeviceAnchor(device, data, square, cell,
                square.getX(), square.getY(), square.getZ())
        } catch (_: Exception) { null } catch (_: AssertionError) { null }
    }

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
        // Both native List fields are constructed as exact ArrayLists. Check the
        // implementation before size/member reads can dispatch custom callbacks.
        if (objects.javaClass != ArrayList::class.java || objects.size > 256 ||
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
            if (objects.javaClass != ArrayList::class.java || objects.size > 256) return false
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
