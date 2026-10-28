import java.io.BufferedWriter
import java.io.StringWriter
import java.lang.reflect.Method
import net.alexredby.cartlab.Multiplayer
import sun.misc.Unsafe
import zombie.characters.IsoPlayer
import zombie.core.raknet.UdpConnection
import zombie.core.skinnedmodel.ModelCamera
import zombie.core.skinnedmodel.ModelManager
import zombie.core.skinnedmodel.animation.AnimationPlayer
import zombie.core.skinnedmodel.model.ModelInstance
import zombie.core.skinnedmodel.model.ModelInstanceRenderData
import zombie.core.skinnedmodel.model.ModelSlotRenderData
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.iso.IsoGridSquare
import zombie.iso.objects.IsoWorldInventoryObject
import zombie.network.CoopSlave
import zombie.network.GameClient
import zombie.network.GameServer

/** Actual native API and read-only model capture checks without a world, socket or game startup. */
object ModelProbeCheck {
    private class BracePlayer : IsoPlayer(null, null, 0, 0, 0) {
        var localFixture = true
        var deadFixture = false
        var userFixture = "client1"
        var onlineFixture: Short = 0
        var primary: InventoryItem? = null
        var secondary: InventoryItem? = null
        lateinit var inventoryFixture: ItemContainer
        var squareFixture: IsoGridSquare? = null

        override fun getX() = 10f

        override fun getY() = 20f

        override fun getZ() = 7f

        override fun getDirectionAngleRadians() = 0f

        override fun getAnimationPlayer(): AnimationPlayer? = null

        override fun isLocalPlayer() = localFixture

        override fun isDead() = deadFixture

        override fun getUsername() = userFixture

        override fun getOnlineID() = onlineFixture

        override fun getPrimaryHandItem(): InventoryItem? = primary

        override fun getSecondaryHandItem(): InventoryItem? = secondary

        override fun getInventory(): ItemContainer = inventoryFixture

        override fun getCurrentSquare(): IsoGridSquare? = squareFixture
    }

    private class BraceItem :
        InventoryItem("SaucedWheelbarrow", "WheelbarrowWood", "WheelbarrowWood", null as String?) {
        var identity = 0
        lateinit var typeFixture: String
        var containerFixture: ItemContainer? = null
        var modelFixture: String? = null
        var worldFixture: IsoWorldInventoryObject? = null

        override fun getID() = identity

        override fun getFullType() = typeFixture

        override fun getContainer(): ItemContainer? = containerFixture

        override fun getStaticModel(): String? = modelFixture

        override fun getWorldItem(): IsoWorldInventoryObject? = worldFixture
    }

    private class BraceWorld : IsoWorldInventoryObject(null as zombie.iso.IsoCell?) {
        var itemFixture: InventoryItem? = null

        override fun getItem(): InventoryItem? = itemFixture
    }

    private fun ensure(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun helper(type: Class<*>, name: String, vararg args: Class<*>): Method =
        type.getDeclaredMethod(name, *args).apply { isAccessible = true }

    private fun stateField(state: Any, name: String, value: Any?) {
        state.javaClass.getDeclaredField(name).apply { isAccessible = true }.set(state, value)
    }

    private inline fun <reified T> allocate(unsafe: Unsafe): T =
        unsafe.allocateInstance(T::class.java) as T

    private fun bool(method: Method, vararg args: Any?): Boolean =
        method.invoke(null, *args) as Boolean

    private fun nativeApiChecks(main: Class<*>) {
        val pose = main.getMethod("timelinePose", String::class.java, String::class.java)
        ensure(
            (pose.invoke(null, "ToolkitCartPose", "1,42,3,0,0,0,1,0,0,0,0,0,0") as String).contains(
                "\"serial\":3",
            ) &&
                (pose.invoke(null, "ToolkitCartActionPose", "1,9,42,11,0,0,0,1,2,0,0,0,0,1")
                        as String)
                    .contains("\"actionGeneration\":11") &&
                (pose.invoke(null, "ToolkitCartPose", "2,42,3") as String).contains("shapeError") &&
                pose.invoke(null, "OtherVariable", "anything") == null,
            "Timeline identity/shape guard",
        )
        zombie.characters.IsoGameCharacter::class
            .java
            .getDeclaredMethod("setVariable", String::class.java, String::class.java)
        for (name in arrayOf("parse", "processClient", "processServer", "write")) {
            ensure(
                zombie.network.packets.VariableSyncPacket::class.java.declaredMethods.any {
                    it.name == name
                },
                "Missing VariableSync hook $name",
            )
        }
        zombie.network.fields.character.Prediction::class.java.getDeclaredMethod("update")
        IsoPlayer::class.java.getDeclaredMethod("updateRemotePlayer")
        zombie.GameTime::class.java.getDeclaredMethod("getServerTimeShiftIsSet")
        zombie.iso.PlayerCamera::class.java.getDeclaredMethod("update")
        for (name in
            arrayOf("rightClickX", "rightClickY", "rightClickTargetX", "rightClickTargetY")) ensure(
            zombie.iso.PlayerCamera::class.java.getDeclaredField(name).type == java.lang.Float.TYPE,
            "Native camera pan field changed",
        )
        zombie.GameTime::class
            .java
            .getDeclaredMethod(
                "syncServerTime",
                java.lang.Long.TYPE,
                java.lang.Long.TYPE,
                java.lang.Long.TYPE,
            )
        ensure(
            zombie.GameTime::class.java.getDeclaredField("serverTimeShift").type ==
                java.lang.Long.TYPE,
            "Native clock shift changed",
        )
        zombie.network.packets.service.TimeSyncPacket::class
            .java
            .getDeclaredMethod("processClient", UdpConnection::class.java)
        UdpConnection::class.java.getDeclaredMethod("getStatistics")
        zombie.core.raknet.RakNetPeerInterface::class
            .java
            .getDeclaredMethod("GetNetStatistics", java.lang.Long.TYPE)
        for (name in
            arrayOf(
                "totalActualBytesSent",
                "totalActualBytesReceived",
                "totalUserMessageBytesResent",
                "bytesInResendBuffer",
                "messagesInResendBuffer",
            )) ensure(
            zombie.core.znet.ZNetStatistics::class.java.getDeclaredField(name).type ==
                java.lang.Long.TYPE,
            "Counter changed $name",
        )
    }

    private fun hostGate(main: Class<*>, unsafe: Unsafe) {
        val host = main.getDeclaredMethod("padHost")
        ensure(!bool(host), "Non-server pad mutation permission")
        val fresh =
            GameServer::class.java.getDeclaredField("worldExistedAtStartup").apply {
                isAccessible = true
            }
        val server = GameServer.server
        val client = GameClient.client
        val world = fresh.getBoolean(null)
        val name = GameServer.serverName
        val coop = CoopSlave.instance
        try {
            GameServer.server = true
            GameClient.client = false
            GameServer.serverName = "queue-smoke"
            CoopSlave.instance = allocate(unsafe)
            fresh.setBoolean(null, false)
            ensure(bool(host), "Fresh native Host pad gate refused")
            fresh.setBoolean(null, true)
            ensure(!bool(host), "Existing native world allowed pad mutation")
            fresh.setBoolean(null, false)
            GameServer.serverName = "user-save"
            ensure(!bool(host), "Foreign native Host allowed pad mutation")
        } finally {
            GameServer.server = server
            GameClient.client = client
            GameServer.serverName = name
            CoopSlave.instance = coop
            fresh.setBoolean(null, world)
        }
    }

    private fun ownerGate(main: Class<*>, unsafe: Unsafe, owner: BracePlayer, cart: BraceItem) {
        val guard = helper(main, "mpBraceOwner", IsoPlayer::class.java, java.lang.Integer.TYPE)
        val player = IsoPlayer.getInstance()
        val connection = GameClient.connection
        val handshake = GameClient.instance.connected
        val server = GameServer.server
        val client = GameClient.client
        try {
            GameClient.client = true
            GameServer.server = false
            GameClient.instance.connected = true
            IsoPlayer.setInstance(owner)
            GameClient.connection = allocate<UdpConnection>(unsafe)
            ensure(
                !GameClient.connection.isFullyConnected,
                "Expected native Host transport flag false",
            )
            ensure(
                bool(guard, owner, 42),
                "Armed exact owner blocked by native Host transport flag",
            )
            GameClient.instance.connected = false
            ensure(!bool(guard, owner, 42), "Disconnected client sampled")
            GameClient.instance.connected = true
            ensure(
                !bool(guard, owner, 43) && !bool(guard, null, 42),
                "Foreign cart/null owner sampled",
            )
            owner.localFixture = false
            ensure(!bool(guard, owner, 42), "Remote actor sampled")
            owner.localFixture = true
            owner.userFixture = "client2"
            ensure(!bool(guard, owner, 42), "Observer sampled")
            owner.userFixture = "client1"
            owner.deadFixture = true
            ensure(!bool(guard, owner, 42), "Dead owner sampled")
            owner.deadFixture = false
            owner.onlineFixture = -1
            ensure(!bool(guard, owner, 42), "Offline actor sampled")
            owner.onlineFixture = 0
            val square = owner.squareFixture
            owner.squareFixture = null
            ensure(!bool(guard, owner, 42), "Unloaded owner sampled")
            owner.squareFixture = square
            owner.secondary = null
            ensure(!bool(guard, owner, 42), "Unequipped cart sampled")
            owner.secondary = cart
            cart.containerFixture = null
            ensure(!bool(guard, owner, 42), "Non-owned cart sampled")
            cart.containerFixture = owner.inventoryFixture
            cart.typeFixture = "SaucedWheelbarrow.WheelbarrowMetal"
            ensure(!bool(guard, owner, 42), "Foreign cart type sampled")
            cart.typeFixture = "SaucedWheelbarrow.WheelbarrowWood"
            IsoPlayer.setInstance(null)
            ensure(!bool(guard, owner, 42), "Different local instance sampled")
            IsoPlayer.setInstance(owner)
            GameServer.server = true
            ensure(!bool(guard, owner, 42), "Server sampled as local owner")
            GameServer.server = false
            GameClient.client = false
            ensure(!bool(guard, owner, 42), "Single-player actor sampled")
        } finally {
            IsoPlayer.setInstance(player)
            GameClient.connection = connection
            GameClient.instance.connected = handshake
            GameServer.server = server
            GameClient.client = client
        }
    }

    private fun jsonChecks() {
        val raw = "quote\"slash\\\n\r\t" + 1.toChar()
        for ((owner, name) in
            arrayOf(
                "ClearanceProbe" to "jsonString",
                "net.alexredby.cartlab.Multiplayer" to "mpJsonString",
            )) {
            val method = helper(Class.forName(owner), name, String::class.java)
            println(method.invoke(null, raw))
            ensure(method.invoke(null, null as Any?) == "null", "null model JSON")
        }
    }

    private fun drawChecks(probe: Class<*>, unsafe: Unsafe, owner: BracePlayer, cart: BraceItem) {
        val output = probe.getDeclaredField("output").apply { isAccessible = true }
        val cameras = probe.getDeclaredField("cameras").apply { isAccessible = true }
        val drawText = StringWriter()
        output.set(null, BufferedWriter(StringWriter()))
        cameras.set(null, BufferedWriter(drawText))
        val slot =
            allocate<ModelSlotRenderData>(unsafe).apply {
                character = owner
                x = 10.25f
                y = 20f
                z = 7f
                animPlayerAngle = (Math.PI / 2).toFloat()
                squareDepth = .25f
            }
        val source = allocate<ModelManager.ModelSlot>(unsafe).apply { character = owner }
        ClearanceProbe.rememberNative(slot, source)
        val poses =
            probe.getDeclaredField("nativePoses").apply { isAccessible = true }.get(null)
                as Map<*, *>
        val nativePose = checkNotNull(poses[slot])
        ensure(
            helper(nativePose.javaClass, "x").invoke(nativePose) == 10f,
            "Cosmetic slot coordinate replaced original native capture",
        )
        val body = allocate<ModelInstance>(unsafe)
        val cartModel = allocate<ModelInstance>(unsafe)
        val prepare =
            helper(
                probe,
                "prepareDraw",
                ModelSlotRenderData::class.java,
                ModelInstance::class.java,
                ModelInstance::class.java,
            )
        prepare.invoke(null, slot, body, cartModel)
        ClearanceProbe.snapshot(slot)
        val bodyData = allocate<ModelInstanceRenderData>(unsafe).apply { modelInstance = body }
        val cartData = allocate<ModelInstanceRenderData>(unsafe).apply { modelInstance = cartModel }
        val previous = ModelCamera.instance
        val camera =
            allocate<zombie.core.opengl.CharacterModelCamera>(unsafe).apply {
                x = 10.25f
                y = 20f
                z = 7f
                useAngle = (Math.PI / 2).toFloat()
                useWorldIso = true
            }
        try {
            ModelCamera.instance = camera
            ClearanceProbe.beginCamera(camera)
            owner.primary = null
            owner.secondary = null
            ClearanceProbe.draw(slot, bodyData)
            ClearanceProbe.draw(slot, bodyData)
            camera.x = 11f
            ClearanceProbe.draw(slot, cartData)
            val recorded = drawText.toString().lineSequence().filter { it.isNotEmpty() }.toList()
            ensure(
                recorded.size == 2 &&
                    recorded.any { it.contains("\"part\":\"body\"") } &&
                    recorded.any { it.contains("\"part\":\"cart\"") } &&
                    recorded.any { it.contains("\"cameraX\":10.25") } &&
                    recorded.any { it.contains("\"currentCameraX\":11.0") } &&
                    recorded.all {
                        it.contains("\"preparedPrimary\":42,\"preparedSecondary\":42") &&
                            it.contains("\"primary\":-1,\"secondary\":-1")
                    },
                "Consumed camera/body/cart draw identity was not independently captured",
            )
            ClearanceProbe.endCamera()
            prepare.invoke(null, slot, body, cartModel)
            try {
                ClearanceProbe.draw(slot, bodyData)
                throw AssertionError("Draw without consumed camera was accepted")
            } catch (_: IllegalStateException) {}
        } finally {
            ClearanceProbe.endCamera()
            ModelCamera.instance = previous
            owner.primary = cart
            owner.secondary = cart
            output.set(null, null)
            cameras.set(null, null)
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun solveChecks(probe: Class<*>) {
        val trace =
            probe.getDeclaredField("solve").apply { isAccessible = true }.get(null)
                as ThreadLocal<StringBuilder>
        val output = probe.getDeclaredField("solves").apply { isAccessible = true }
        val text = StringWriter()
        output.set(null, BufferedWriter(text))
        ensure(ClearanceProbe.reachInput(null) == null, "Unscoped solver diagnostic")
        for (ok in arrayOf(true, false)) {
            trace.set(StringBuilder("{\"failures\":["))
            if (!ok) {
                ClearanceProbe.refusal("reach", "\"bone\":\"Bip01_R_Hand\"")
                ClearanceProbe.refusal("transitionGrip", null)
            }
            ClearanceProbe.finishSolve(ok)
            ensure(trace.get() == null, "Solver scope leaked into next frame")
        }
        ClearanceProbe.finishSolve(false)
        print(text)
        output.set(null, null)
    }

    private fun familyChecks(probe: Class<*>, cart: BraceItem) {
        val family = helper(probe, "cartFamily", String::class.java, String::class.java)
        for (model in
            arrayOf(
                "ShoppingCartModel",
                "ShoppingCartPartialModel",
                "ShoppingCartFullModel",
            )) ensure(
            bool(family, "SaucedCarts.ShoppingCart", model),
            "same-family mismatch was filtered",
        )
        ensure(
            !bool(family, "SaucedCarts.ShoppingCart", "WheelbarrowWood") &&
                !bool(family, "Base.Log", "ShoppingCartFullModel"),
            "wrong cart family",
        )
        val capture = helper(probe, "captureModel", InventoryItem::class.java, String::class.java)
        for (model in arrayOf("WheelbarrowWood", "WheelbarrowMetal")) {
            ensure(
                bool(capture, null, model),
                "Empty native pickup hands filtered presentation model: $model",
            )
            cart.typeFixture = "SaucedWheelbarrow.$model"
            ensure(bool(capture, cart, model), "Exact held cart presentation filtered: $model")
            val other = if (model == "WheelbarrowWood") "WheelbarrowMetal" else "WheelbarrowWood"
            ensure(
                !bool(capture, cart, other) && !bool(capture, cart, "ShoppingCartFullModel"),
                "Held item acquired another cart family: $model",
            )
        }
        for (model in
            arrayOf(
                "ShoppingCartModel",
                "ShoppingCartFullModel",
                "WheelbarrowMetalExtra",
                "Other.WheelbarrowMetal",
            )) ensure(!bool(capture, null, model), "Unrelated empty-hand model captured: $model")
        cart.typeFixture = "Base.Log"
        ensure(
            !bool(capture, cart, "WheelbarrowMetal"),
            "Foreign held item acquired metal presentation",
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun transitionChecks(
        probe: Class<*>,
        unsafe: Unsafe,
        owner: BracePlayer,
        cart: BraceItem,
    ) {
        val item = helper(probe, "transitionItem", IsoPlayer::class.java)
        val capture = helper(probe, "captureModel", InventoryItem::class.java, String::class.java)
        val transition = Class.forName("net.alexredby.pztoolkitjavapatches.CartTransition")
        val states =
            transition.getDeclaredField("states").apply { isAccessible = true }.get(null)
                as MutableMap<Any, Any>
        val previous = states[owner]
        val pickup = unsafe.allocateInstance(Class.forName("${transition.name}\$State"))
        val world = allocate<BraceWorld>(unsafe).apply { itemFixture = cart }
        cart.typeFixture = "SaucedCarts.ShoppingCart"
        cart.modelFixture = "Base.ShoppingCartFullModel"
        cart.worldFixture = world
        owner.primary = null
        owner.secondary = null
        try {
            states.remove(owner)
            ensure(
                item.invoke(null, owner) == null,
                "Empty hands inferred an untracked shopping cart",
            )
            stateField(pickup, "item", cart)
            stateField(pickup, "world", world)
            stateField(pickup, "pickup", true)
            stateField(pickup, "rendered", true)
            stateField(pickup, "updated", System.nanoTime())
            states[owner] = pickup
            ensure(
                item.invoke(null, owner) === cart && bool(capture, cart, "ShoppingCartFullModel"),
                "Exact rendered shopping pickup was not associated",
            )
            val due =
                helper(
                    probe,
                    "captureDue",
                    IsoPlayer::class.java,
                    InventoryItem::class.java,
                    java.lang.Long.TYPE,
                )
            val seen =
                probe.getDeclaredField("hands").apply { isAccessible = true }.get(null)
                    as MutableMap<*, *>
            seen.clear()
            val last = probe.getDeclaredField("last").apply { isAccessible = true }
            var now = System.nanoTime()
            last.setLong(null, now)
            stateField(pickup, "updated", now)
            stateField(pickup, "ik", true)
            stateField(pickup, "progress", .1f)
            // Native 60Hz frames must survive the 112ms cancellation window.
            for (frame in 1..7) {
                val frameTime = now + frame * 16_000_000L
                ensure(bool(due, owner, cart, frameTime), "Short cancel native frame decimated")
                last.setLong(null, frameTime)
            }
            now += 112_000_000L
            for (key in arrayOf("rendered", "ik")) {
                stateField(pickup, key, false)
                ensure(
                    !bool(due, owner, cart, now + 16_000_000L),
                    "Unsolved transition bypassed cadence: $key",
                )
                stateField(pickup, key, true)
            }
            stateField(pickup, "recovering", true)
            ensure(!bool(due, owner, cart, now + 16_000_000L), "Recovery bypassed active cadence")
            stateField(pickup, "recovering", false)
            stateField(pickup, "progress", 0f)
            ensure(!bool(due, owner, cart, now + 16_000_000L), "Zero progress bypassed cadence")
            stateField(pickup, "progress", .1f)
            stateField(pickup, "updated", now - 1_000_000_001L)
            ensure(!bool(due, owner, cart, now + 16_000_000L), "Stale transition bypassed cadence")
            stateField(pickup, "updated", now + 20_000_000L)
            ensure(!bool(due, owner, cart, now + 16_000_000L), "Future transition bypassed cadence")
            stateField(pickup, "updated", now)
            world.itemFixture = null
            ensure(
                !bool(due, owner, cart, now + 16_000_000L),
                "Foreign world item bypassed cadence",
            )
            world.itemFixture = cart
            stateField(pickup, "pickup", false)
            owner.primary = cart
            owner.secondary = cart
            ensure(bool(due, owner, cart, now + 16_000_000L), "Exact native drop decimated")
            owner.secondary = null
            ensure(
                !bool(due, owner, cart, now + 16_000_000L),
                "Foreign drop hands bypassed cadence",
            )
            owner.primary = null
            states.remove(owner)
            ensure(!bool(due, owner, cart, now + 16_000_000L), "Missing state bypassed cadence")
            ensure(bool(due, owner, cart, now + 34_000_000L), "Ordinary cadence lost")
            val remember =
                helper(probe, "rememberHands", IsoPlayer::class.java, java.lang.Long.TYPE)
            owner.primary = cart
            owner.secondary = cart
            remember.invoke(null, owner, now)
            for (elapsed in longArrayOf(0, 16_000_000L, 250_000_000L, 500_000_000L)) {
                last.setLong(null, now + elapsed)
                remember.invoke(null, owner, now + elapsed)
                ensure(bool(due, owner, cart, now + elapsed), "Handoff native slot decimated")
            }
            last.setLong(null, now + 500_000_001L)
            ensure(!bool(due, owner, cart, now + 500_000_001L), "Handoff window renewed")
            last.setLong(null, now - 1)
            ensure(!bool(due, owner, cart, now - 1), "Future handoff sample accepted")
            owner.primary = null
            owner.secondary = null
            remember.invoke(null, owner, now)
            last.setLong(null, now)
            ensure(!bool(due, owner, cart, now), "Missing hands extended handoff capture")
            seen.clear()
            states[owner] = pickup
            stateField(pickup, "pickup", true)
            stateField(pickup, "updated", System.nanoTime())
            stateField(pickup, "rendered", false)
            ensure(item.invoke(null, owner) == null, "Unrendered shopping state admitted")
            stateField(pickup, "rendered", true)
            stateField(pickup, "updated", 0L)
            ensure(item.invoke(null, owner) == null, "Stale shopping state admitted")
            stateField(pickup, "updated", System.nanoTime())
            owner.primary = cart
            ensure(item.invoke(null, owner) == null, "Nonempty hands used pickup fallback")
            owner.primary = null
            world.itemFixture = null
            ensure(
                item.invoke(null, owner) == null,
                "Replaced world cart acquired transition identity",
            )
        } finally {
            if (previous == null) states.remove(owner) else states[owner] = previous
            cart.worldFixture = null
            owner.primary = cart
            owner.secondary = cart
        }
        ensure(
            !bool(helper(probe, "cartModel", String::class.java), "ShoppingCartUnknownModel"),
            "unknown attachment",
        )
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val unsafe =
            Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null)
                as Unsafe
        val main = Multiplayer::class.java
        nativeApiChecks(main)
        hostGate(main, unsafe)
        // Unsafe skips all Kotlin initializers, so initialize every field read by these fixtures.
        val owner =
            allocate<BracePlayer>(unsafe).apply {
                localFixture = true
                deadFixture = false
                userFixture = "client1"
                onlineFixture = 0
                primary = null
                secondary = null
                squareFixture = allocate<IsoGridSquare>(unsafe)
                inventoryFixture = allocate<ItemContainer>(unsafe)
            }
        val cart =
            allocate<BraceItem>(unsafe).apply {
                identity = 42
                typeFixture = "SaucedWheelbarrow.WheelbarrowWood"
                containerFixture = owner.inventoryFixture
                modelFixture = null
                worldFixture = null
            }
        owner.primary = cart
        owner.secondary = cart
        ownerGate(main, unsafe, owner, cart)
        jsonChecks()
        val probe = Class.forName("ClearanceProbe")
        drawChecks(probe, unsafe, owner, cart)
        solveChecks(probe)
        familyChecks(probe, cart)
        transitionChecks(probe, unsafe, owner, cart)
    }
}
