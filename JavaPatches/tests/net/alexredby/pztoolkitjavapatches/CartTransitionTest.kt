package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field
import java.util.HashMap
import org.joml.Matrix4f
import org.joml.Quaternionf
import sun.misc.Unsafe
import zombie.Lua.LuaManager
import zombie.characters.CharacterTimedActions.BaseAction
import zombie.characters.IsoPlayer
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.iso.IsoGridSquare
import zombie.iso.objects.IsoWorldInventoryObject

object CartTransitionTest {
    private fun writeEnum(writer: zombie.core.network.ByteBufferWriter, value: Enum<*>) {
        try {
            zombie.core.network.ByteBufferWriter::class
                .java
                .getMethod("putEnum", Enum::class.java)
                .invoke(writer, value)
        } catch (error: java.lang.reflect.InvocationTargetException) {
            throw required(error.cause)
        }
    }

    private fun <T : Any> required(value: T?): T = value ?: throw NullPointerException()

    private lateinit var unsafe: Unsafe

    private fun <T : Any> allocate(type: Class<T>): T = type.cast(unsafe.allocateInstance(type))

    private fun check(condition: Boolean, message: String) {
        if (!condition) throw AssertionError(message)
    }

    private fun close(actual: Float, expected: Float, message: String) {
        check(Math.abs(actual - expected) < .00002f, "$message: $actual != $expected")
    }

    private class NativePass : RuntimeException()

    private fun nativePass(render: Runnable, message: String) {
        try {
            render.run()
            throw AssertionError(message)
        } catch (expected: NativePass) {}
    }

    private fun invoke(method: java.lang.reflect.Method, receiver: Any?, vararg args: Any?): Any? =
        try {
            method.invoke(receiver, *args)
        } catch (error: java.lang.reflect.InvocationTargetException) {
            throw error.cause as RuntimeException
        } catch (error: ReflectiveOperationException) {
            throw AssertionError(error)
        }

    private class Player : IsoPlayer(null, null, 0, 0, 0) {
        @JvmField var primary: InventoryItem? = null
        @JvmField var secondary: InventoryItem? = null
        @JvmField var inventory: ItemContainer? = null
        @JvmField var square: IsoGridSquare? = null
        @JvmField var variables: MutableMap<String?, Float>? = null
        @JvmField var actions: java.util.Stack<BaseAction>? = null
        @JvmField var machine: zombie.ai.StateMachine? = null
        @JvmField var animation: zombie.core.skinnedmodel.animation.AnimationPlayer? = null
        @JvmField var network: zombie.characters.NetworkPlayerAI? = null
        @JvmField var protection = 0
        @JvmField var modelResets = 0
        @JvmField var handWrites = 0
        @JvmField var clipPilotWrites = 0
        @JvmField var performing = false
        @JvmField var otherFloor = false
        @JvmField var clipPilot = false
        @JvmField var clipPilotAbsent = false
        @JvmField var receiptInterleave = false
        @JvmField var performingAction: String? = null
        @JvmField var onlineID: Short = 0

        override fun getOnlineID(): Short = onlineID

        @JvmField var nativeParams: MutableMap<zombie.ai.State.Param<*>, Any?>? = null
        @JvmField var booleanVariables: MutableMap<String?, Boolean>? = null
        @JvmField var modelError: RuntimeException? = null
        @JvmField var expectedForceNull = false
        @JvmField var modelScopes = 0

        override fun getX(): Float = 10.25f

        override fun getY(): Float = 20.75f

        override fun getZ(): Float = if (otherFloor) 3f else 2f

        override fun getCurrentSquare(): IsoGridSquare? = square

        override fun getPrimaryHandItem(): InventoryItem? = primary

        override fun getSecondaryHandItem(): InventoryItem? = secondary

        override fun getInventory(): ItemContainer? = inventory

        override fun setPrimaryHandItem(item: InventoryItem?) {
            handWrites++
            primary = item
            if (receiptInterleave && item != null)
                check(
                    !CartTransition.pickupHandoff(this),
                    "partial native equipment activated a bridge",
                )
        }

        override fun setSecondaryHandItem(item: InventoryItem?) {
            handWrites++
            secondary = item
        }

        override fun isLocalPlayer(): Boolean = protection != 1

        @JvmField var nativeNetworkComponent: zombie.characters.component.NetworkComponent? = null

        override fun <T : zombie.characters.ecs.ECSComponent?> tryGetECSComponent(
            type: Class<T>,
        ): T? =
            if (
                type === zombie.characters.component.NetworkComponent::class.java &&
                    nativeNetworkComponent != null
            )
                type.cast(nativeNetworkComponent)
            else null

        override fun hasAnimationPlayer(): Boolean = animation != null

        override fun getAnimationPlayer(): zombie.core.skinnedmodel.animation.AnimationPlayer? =
            animation

        override fun getNetworkCharacterAI(): zombie.characters.NetworkPlayerAI? = network

        override fun isNpc(): Boolean = protection == 11

        override fun isSneaking(): Boolean = protection == 12

        override fun isDead(): Boolean = protection == 2

        override fun isAiming(): Boolean = protection == 3

        override fun hasHitReaction(): Boolean = protection == 4

        override fun isKnockedDown(): Boolean = protection == 5

        override fun isGettingUp(): Boolean = protection == 6

        override fun getVehicle(): zombie.vehicles.BaseVehicle? =
            if (protection == 7) vehicle else null

        @JvmField var vehicle: zombie.vehicles.BaseVehicle? = null

        override fun isGrappling(): Boolean = protection == 8

        override fun isBeingGrappled(): Boolean = protection == 9

        override fun isRagdollSimulationActive(): Boolean = protection == 10

        override fun getStateMachine(): zombie.ai.StateMachine {
            if (machine == null) machine = zombie.ai.StateMachine(this)
            return machine ?: throw NullPointerException()
        }

        override fun getAdvancedAnimator():
            zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator? = null

        override fun containsVariable(name: String?): Boolean {
            if ("ToolkitWoodCartClipPilot".equals(name)) return !clipPilotAbsent
            return variables != null &&
                (variables ?: throw NullPointerException()).containsKey(name) ||
                booleanVariables != null &&
                    (booleanVariables ?: throw NullPointerException()).containsKey(name)
        }

        override fun getVariableBoolean(name: String?): Boolean {
            if ("ToolkitWoodCartClipPilot".equals(name)) return clipPilot
            return "IsPerformingAnAction".equals(name) && performing
        }

        override fun getCharacterActions(): java.util.Stack<BaseAction> {
            if (actions == null) actions = java.util.Stack()
            return actions ?: throw NullPointerException()
        }

        override fun resetEquippedHandsModels() {
            modelResets++
        }

        override fun resetModelNextFrame() {
            modelResets++
        }

        override fun getVariableString(name: String?): String? =
            if ("PerformingAction".equals(name)) performingAction else super.getVariableString(name)

        override fun getStateMachineParams(
            type: Class<*>?,
        ): MutableMap<zombie.ai.State.Param<*>, Any?> {
            if (nativeParams == null) nativeParams = HashMap()
            return nativeParams ?: throw NullPointerException()
        }

        override fun getItemVisuals(visuals: zombie.core.skinnedmodel.visual.ItemVisuals?) {
            if (modelError != null) {
                check(
                    forceNullOverride == expectedForceNull,
                    "native model scope did not isolate the leased visual",
                )
                modelScopes++
                throw modelError ?: throw NullPointerException()
            }
        }

        override fun getAttachedItems(): zombie.characters.AttachedItems.AttachedItems =
            zombie.characters.AttachedItems.AttachedItems(
                zombie.characters.AttachedItems.AttachedLocationGroup("fixture"),
            )

        override fun setVariable(
            name: String?,
            value: Float,
        ): zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot? {
            if (variables == null) variables = HashMap()
            (variables ?: throw NullPointerException())[name] = value
            return null
        }

        override fun setVariable(
            name: String?,
            value: String?,
        ): zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot? {
            if ("PerformingAction".equals(name)) {
                performingAction = value
                return null
            }
            return super.setVariable(name, value)
        }

        override fun setVariable(
            name: String?,
            value: Boolean,
        ): zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot? {
            if ("IsPerformingAnAction".equals(name)) {
                performing = value
                return null
            }
            if ("ToolkitWoodCartClipPilot".equals(name)) {
                clipPilot = value
                clipPilotAbsent = false
                clipPilotWrites++
                return null
            }
            check(
                "ToolkitWoodCartClipPickup".equals(name) ||
                    "ToolkitMetalCartClip".equals(name) ||
                    "ToolkitShoppingCartClip".equals(name),
                "unexpected boolean presentation variable: $name",
            )
            if (booleanVariables == null) booleanVariables = HashMap()
            (booleanVariables ?: throw NullPointerException())[name] = value
            return null
        }

        override fun getVariableFloat(name: String?, fallback: Float): Float =
            if (variables == null) fallback
            else (variables ?: throw NullPointerException()).getOrDefault(name, fallback)

        override fun clearVariable(name: String?) {
            if (variables != null) (variables ?: throw NullPointerException()).remove(name)
            if (booleanVariables != null)
                (booleanVariables ?: throw NullPointerException()).remove(name)
        }
    }

    private class Cart : InventoryItem(null, null, null, nullValue<String>()) {
        @JvmField var container: ItemContainer? = null
        @JvmField var world: IsoWorldInventoryObject? = null
        @JvmField var kind: String? = null
        @JvmField var model: String? = null
        @JvmField var rotation = 0f
        @JvmField var alpha = 0f
        @JvmField var probeNative = false

        override fun getFullType(): String? = kind

        override fun getStaticModel(): String? = if (model == null) "WheelbarrowWood" else model

        override fun getContainer(): ItemContainer? = container

        override fun getWorldItem(): IsoWorldInventoryObject? = world

        override fun setWorldZRotation(value: Float) {
            rotation = value
        }

        override fun getWorldAlpha(): Float = alpha

        override fun setWorldAlpha(value: Float) {
            alpha = value
        }

        override fun getScriptItem(): zombie.scripting.objects.Item? {
            if (probeNative) throw NativePass()
            return null
        }

        override fun getWorldStaticItem(): String? {
            if (probeNative) throw NativePass()
            return null
        }
    }

    private fun <T> nullValue(): T? = null

    private class WorldItem : IsoWorldInventoryObject(nullValue<zombie.iso.IsoCell>()) {
        @JvmField var invalidations = 0
        @JvmField var item: InventoryItem? = null
        @JvmField var square: IsoGridSquare? = null
        @JvmField var probeNative = false

        override fun getWorldPosX(): Float = 10.25f

        override fun getWorldPosY(): Float = 20.75f

        override fun getWorldPosZ(): Float = 2f

        override fun getItem(): InventoryItem? = item

        override fun getSquare(): IsoGridSquare? = square

        override fun getRenderSquare(): IsoGridSquare? = square

        override fun getSpriteModel(): zombie.iso.SpriteModel? {
            if (probeNative) throw NativePass()
            return null
        }

        override fun getForwardIsoDirection(): zombie.iso.IsoDirections = throw NativePass()

        override fun invalidateRenderChunkLevel(flags: Long) {
            check(flags == 256L, "wrong visual invalidation flags")
            invalidations++
        }
    }

    @JvmRecord
    private data class Recovery(
        val player: Player,
        val cart: Cart,
        val world: WorldItem,
        val pickup: Boolean,
    ) {
        override fun toString(): String =
            "Recovery[player=$player, cart=$cart, world=$world, pickup=$pickup]"
    }

    private class NativeRemoteComponent : zombie.characters.component.NetworkComponent() {
        @JvmField var player: Player? = null

        override fun isRemote(): Boolean = true

        override fun updateNetworkAI() {}

        override fun getNetworkAI(): zombie.characters.NetworkCharacterAI? =
            (player ?: throw NullPointerException()).network
    }

    private fun groundPasses() {
        var player = allocate(Player::class.java)
        val cart = allocate(Cart::class.java)
        var world = allocate(WorldItem::class.java)
        cart.kind = "SaucedWheelbarrow.WheelbarrowWood"
        cart.world = world
        cart.alpha = 0.7f
        cart.worldScale = 1f
        world.item = cart
        val renderer = zombie.core.skinnedmodel.model.ItemModelRenderer()
        val outlineType = zombie.iso.fboRenderChunk.FBORenderObjectOutline::class.java
        val outline = allocate(outlineType)
        val outlineRender =
            outlineType.getDeclaredMethod(
                "renderObject",
                Int::class.javaPrimitiveType!!,
                zombie.iso.IsoObject::class.java,
            )
        outlineRender.setAccessible(true)
        val outlinePass: Runnable = Runnable {
            invoke(outlineRender, outline, 0, world)
        }
        val jobType = Class.forName("zombie.iso.fboRenderChunk.FBORenderItems\$RenderJob")
        val job = allocate(jobType)
        val jobWorld = jobType.getDeclaredField("worldInventoryObject")
        jobWorld.setAccessible(true)
        jobWorld.set(job, world)
        val jobModels = jobType.getDeclaredField("renderer")
        jobModels.setAccessible(true)
        jobModels.set(job, arrayOf(renderer, renderer, renderer))
        val jobRender = jobType.getDeclaredMethod("renderMain")
        jobRender.setAccessible(true)
        world.square = allocate(IsoGridSquare::class.java)
        val core = zombie.core.Core.getInstance()
        val previous3D: Boolean = core.isOption3DGroundItem()
        try {
            core.setOption3DGroundItem(true)
            check(
                CartTransition.update(player, cart, true, 0.6),
                "pickup ground-pass setup refused",
            )
            check(!CartTransition.hidden(cart), "ground disappeared before a held model rendered")
            val statesField = CartTransition::class.java.getDeclaredField("states")
            statesField.setAccessible(true)
            var state = ((statesField.get(null) as MutableMap<*, *>)).get(player)
            val rendered = required(state).javaClass.getDeclaredField("rendered")
            rendered.setAccessible(true)
            rendered.setBoolean(state, true)
            check(
                CartTransition.hidden(cart),
                "rendered held model must hide the exact ground item",
            )
            val other = allocate(Cart::class.java)
            other.kind = cart.kind
            check(!CartTransition.hidden(other), "held visual hid a different cart")
            var sprite = allocate(zombie.iso.sprite.IsoSprite::class.java)
            val texture = zombie.iso.sprite.IsoSprite::class.java.getDeclaredField("texture")
            texture.setAccessible(true)
            texture.set(sprite, allocate(zombie.core.textures.Texture::class.java))
            world.sprite = sprite
            cart.probeNative = true
            world.probeNative = true
            for (i in 0 until 3) {
                check(
                    renderer.renderMain(cart, null, null, 0f, 0f, 0f, 0f, 0f, true) ===
                        zombie.core.skinnedmodel.model.ItemModelRenderer.RenderStatus.NoModel,
                    "cached FBO model/depth pass survived held visual",
                )
                check(
                    invoke(jobRender, job) ===
                        zombie.core.skinnedmodel.model.ItemModelRenderer.RenderStatus.NoModel,
                    "cached native FBO job survived held visual",
                )
                world.render(0f, 0f, 0f, null, false, false, null)
                world.renderObjectPicker(0f, 0f, 0f, null)
                outlinePass.run()
            }
            close(cart.alpha, 0.7f, "world passes changed serialized alpha")
            CartTransition.end(player)
            check(!CartTransition.hidden(cart), "cancel did not restore the ground visual")
            check(world.invalidations == 1, "cancel did not invalidate the ground cache once")
            nativePass(
                Runnable {
                    renderer.renderMain(cart, null, null, 0f, 0f, 0f, 0f, 0f, true)
                },
                "model pass stayed hidden after cleanup",
            )
            nativePass(
                Runnable {
                    invoke(jobRender, job)
                },
                "cached FBO job stayed hidden after cleanup",
            )
            nativePass(
                Runnable {
                    world.render(0f, 0f, 0f, null, false, false, null)
                },
                "sprite pass stayed hidden after cleanup",
            )
            nativePass(
                Runnable {
                    world.renderObjectPicker(0f, 0f, 0f, null)
                },
                "picker stayed hidden after cleanup",
            )
            outlinePass.run()
            for (kind in arrayOf("SaucedWheelbarrow.Unknown", "Base.Hammer")) {
                cart.kind = kind
                nativePass(outlinePass, "native outline changed for " + kind)
            }
            cart.kind = "SaucedCarts.ShoppingCart"
            outlinePass.run()
            cart.kind = "SaucedWheelbarrow.WheelbarrowMetal"
            outlinePass.run()
            cart.kind = "SaucedWheelbarrow.WheelbarrowWood"
            core.setOption3DGroundItem(false)
            nativePass(outlinePass, "2D wooden cart lost its native outline")
            cart.world = null
            check(CartTransition.update(player, cart, false, 0.6), "setdown setup refused")
            state = ((statesField.get(null) as MutableMap<*, *>)).get(player)
            rendered.setBoolean(state, true)
            check(
                !CartTransition.hidden(cart),
                "setdown without a native world item hid a static item",
            )
        } finally {
            CartTransition.end(player)
            core.setOption3DGroundItem(previous3D)
        }
    }

    private fun bridge() {
        var player = allocate(Player::class.java)
        player.inventory = allocate(ItemContainer::class.java)
        player.square = allocate(IsoGridSquare::class.java)
        val cart = allocate(Cart::class.java)
        cart.kind = "SaucedWheelbarrow.WheelbarrowWood"
        cart.container = player.inventory
        player.primary = cart
        player.secondary = cart
        try {
            check(
                CartTransition.beginDrop(player, cart, 11.1, 20.4, 2.0, 123.0),
                "valid owned placement refused",
            )
            check(
                CartTransition.place(null, cart) == null,
                "different caller square bypassed scope",
            )
            CartTransition.endDrop()
            check(
                CartTransition.place(player.square, cart) == null,
                "closed context must not redirect later drops",
            )
            for (invalid in
                arrayOf(
                    doubleArrayOf(Double.NaN, 20.0, 2.0, 0.0),
                    doubleArrayOf(11.0, 20.0, 2.0, Double.POSITIVE_INFINITY),
                    doubleArrayOf(11.0, 20.0, 2.0, -1.0),
                    doubleArrayOf(11.0, 20.0, 2.0, 360.0),
                    doubleArrayOf(50.0, 20.0, 2.0, 0.0),
                    doubleArrayOf(11.0, 20.0, 3.0, 0.0),
                )) {
                check(
                    !CartTransition.beginDrop(
                        player,
                        cart,
                        invalid[0],
                        invalid[1],
                        invalid[2],
                        invalid[3],
                    ),
                    "invalid pose accepted",
                )
                check(
                    CartTransition.place(player.square, cart) == null,
                    "invalid begin retained older pending pose",
                )
            }
            var foreign = allocate(Cart::class.java)
            foreign.kind = cart.kind
            foreign.container = player.inventory
            check(
                !CartTransition.beginDrop(player, foreign, 11.0, 20.0, 2.0, 0.0),
                "foreign held identity accepted",
            )
            player.secondary = foreign
            check(
                !CartTransition.beginDrop(player, cart, 11.0, 20.0, 2.0, 0.0),
                "one-handed cart accepted",
            )
            player.secondary = cart
            cart.container = allocate(ItemContainer::class.java)
            check(
                !CartTransition.beginDrop(player, cart, 11.0, 20.0, 2.0, 0.0),
                "foreign inventory accepted",
            )
            cart.container = player.inventory
            cart.kind = "SaucedWheelbarrow.WheelbarrowMetal"
            check(
                CartTransition.beginDrop(player, cart, 11.0, 20.0, 2.0, 0.0),
                "metal owned placement refused",
            )
            CartTransition.endDrop()
            cart.kind = "SaucedCarts.ShoppingCart"
            check(
                CartTransition.beginDrop(player, cart, 11.0, 20.0, 2.0, 0.0),
                "shopping cart owned placement refused",
            )
            CartTransition.endDrop()
            cart.kind = "Other.Cart"
            check(
                !CartTransition.beginDrop(player, cart, 11.0, 20.0, 2.0, 0.0),
                "unknown cart accepted",
            )
            cart.kind = "SaucedWheelbarrow.WheelbarrowWood"
            cart.world = allocate(IsoWorldInventoryObject::class.java)
            check(
                !CartTransition.beginDrop(player, cart, 11.0, 20.0, 2.0, 0.0),
                "already-world cart accepted",
            )
            cart.world = null
            check(
                CartTransition.beginDrop(player, cart, 11.0, 20.0, 2.0, 0.0),
                "valid final context",
            )
            check(
                CartTransition.place(player.square, foreign) == null,
                "different item bypassed scope",
            )
            CartTransition.endDrop()
            var world = allocate(WorldItem::class.java)
            cart.world = world
            cart.alpha = 0.7f
            cart.worldScale = 1f
            check(CartTransition.update(player, cart, true, 0.2), "pickup presentation refused")
            close(cart.alpha, 0.7f, "presentation must not change serialized item alpha")
            for (i in 0..100) {
                check(
                    CartTransition.update(player, cart, true, i / 100.0),
                    "pickup pose update refused",
                )
                val x: Float = required(required(player.variables).get("ToolkitWoodCartPoseX"))
                val y: Float = required(required(player.variables).get("ToolkitWoodCartPoseY"))
                check(
                    y >= 0 && y <= x && x <= 1 && x - y <= 0.10001f,
                    "ground action escaped the shallow 2D blend triangle",
                )
                if (i == 44)
                    close(x, 0.10f, "grounded pose must only use a tenth of the deep crouch clip")
            }
            CartTransition.end(player)
            close(cart.alpha, 0.7f, "cancel leaves item alpha unchanged")
            check(world.invalidations == 1, "cancel invalidates cached world rendering once")
            CartTransition.end(player)
            check(world.invalidations == 1, "cleanup is idempotent")
        } finally {
            CartTransition.endDrop()
            CartTransition.end(player)
        }
    }

    private fun state(player: Player): Any? {
        var field = CartTransition::class.java.getDeclaredField("states")
        field.setAccessible(true)
        return ((field.get(null) as MutableMap<*, *>)).get(player)
    }

    private fun value(state: Any?, name: String): Any? {
        var field = required(state).javaClass.getDeclaredField(name)
        field.setAccessible(true)
        return field.get(state)
    }

    private fun value(state: Any?, name: String, value: Any?) {
        var field = required(state).javaClass.getDeclaredField(name)
        field.setAccessible(true)
        field.set(state, value)
    }

    private fun cancelled(player: Player): Any? {
        var field = CartTransition::class.java.getDeclaredField("cancelled")
        field.setAccessible(true)
        return ((field.get(null) as MutableMap<*, *>)).get(player)
    }

    private fun recovery(pickup: Boolean): Recovery {
        var player = allocate(Player::class.java)
        player.inventory = allocate(ItemContainer::class.java)
        player.square = allocate(IsoGridSquare::class.java)
        player.vehicle = allocate(zombie.vehicles.BaseVehicle::class.java)
        val cart = allocate(Cart::class.java)
        cart.kind = "SaucedWheelbarrow.WheelbarrowWood"
        cart.alpha = 0.7f
        cart.worldScale = 1f
        var world = allocate(WorldItem::class.java)
        world.item = cart
        world.square = player.square
        if (pickup) cart.world = world
        else {
            cart.container = player.inventory
            player.primary = cart
            player.secondary = cart
        }
        check(CartTransition.update(player, cart, pickup, 0.55), "recovery setup refused")
        val current = state(player)
        var field = required(current).javaClass.getDeclaredField("rendered")
        field.setAccessible(true)
        field.setBoolean(current, true)
        for (name in arrayOf("nativeRotation", "referenceRotation")) {
            field = required(current).javaClass.getDeclaredField(name)
            field.setAccessible(true)
            field.set(current, Quaternionf())
        }
        return Recovery(player, cart, world, pickup)
    }

    private fun recovered(fixture: Recovery) {
        check(state(fixture.player) == null, "recovery state leaked after cleanup")
        check(required(fixture.player.variables).isEmpty(), "recovery pose variables leaked")
        close(fixture.cart.alpha, 0.7f, "recovery changed serialized alpha")
        check(fixture.player.handWrites == 0, "presentation recovery wrote native hand ownership")
    }

    private fun recoveryLifecycle() {
        for (pickup in booleanArrayOf(true, false)) {
            val fixture = recovery(pickup)
            var player = fixture.player
            val cart = fixture.cart
            try {
                val stopped = allocate(BaseAction::class.java)
                player.getCharacterActions().add(stopped)
                check(
                    CartTransition.cancel(player, cart, pickup, stopped),
                    "exact sole stopped action refused recovery",
                )
                val current = state(player)
                val start: Long = (value(current, "recoveryStart") as Long)
                check((value(current, "recovering") as Boolean), "cancel did not enter recovery")
                check(
                    !(value(current, "authored") as Boolean) &&
                        !(value(current, "movingRecovery") as Boolean),
                    "default cancellation entered the authored pose recovery pilot",
                )
                close(
                    (value(current, "cancelledProgress") as Float),
                    0.55f,
                    "cancel lost interrupted progress",
                )
                check(
                    !CartTransition.cancel(player, cart, pickup, stopped),
                    "duplicate cancellation restarted the recovery clock",
                )
                check(
                    (value(current, "recoveryStart") as Long) == start,
                    "duplicate cancellation changed recovery origin",
                )
                check(
                    "WheelbarrowWood".equals(player.overridePrimaryHandModel) &&
                        player.modelResets == 1,
                    "recovery did not preserve its exact visual model through native override removal",
                )
                if (pickup)
                    check(
                        CartTransition.hidden(cart),
                        "pickup recovery exposed both visual cart copies",
                    )
                else
                    check(
                        !CartTransition.hidden(cart),
                        "held setdown recovery hid an unrelated world cart",
                    )
                required(player.actions).clear()
                check(
                    CartTransition.suppressHeldModel(player) == !pickup,
                    "visual suppression did not match exact held recovery",
                )
                CartTransition.tick(player, start)
                close(
                    (value(current, "progress") as Float),
                    0.55f,
                    "first recovery tick jumped the pose",
                )
                CartTransition.tick(player, start + 200_000_000L)
                val intermediate: Float = (value(current, "progress") as Float)
                check(
                    intermediate > 0 && intermediate < 0.55f,
                    "recovery did not advance back along the action timeline",
                )
                CartTransition.tick(player, start + 600_001_000L)
                recovered(fixture)
                check(
                    player.overridePrimaryHandModel == null,
                    "finished recovery retained its visual lease",
                )
                check(
                    player.modelResets == 2,
                    "visual lease did not reset models exactly on acquire/release",
                )
                check(
                    cart.world === (if (pickup) fixture.world else null) &&
                        cart.container === (if (pickup) null else player.inventory) &&
                        player.primary === (if (pickup) null else cart) &&
                        player.secondary === (if (pickup) null else cart),
                    "recovery transferred the cart",
                )
                check(
                    !CartTransition.hidden(cart),
                    "finished recovery left the real world cart hidden",
                )
                CartTransition.tick(player, start + 900_000_000L)
                CartTransition.end(player)
                check(player.modelResets == 2, "repeated cleanup reset another owner's model")
            } finally {
                CartTransition.end(player)
            }
        }
    }

    private fun authoredClipDefault() {
        var client: Boolean = zombie.network.GameClient.client
        var server: Boolean = zombie.network.GameServer.server
        try {
            for (networkClient in booleanArrayOf(false, true)) for (networkServer in
                booleanArrayOf(false, true)) for (choice in -1..1) {
                zombie.network.GameClient.client = networkClient
                zombie.network.GameServer.server = networkServer
                var player = allocate(Player::class.java)
                player.clipPilotAbsent = choice < 0
                player.clipPilot = choice == 1
                var expected: Boolean =
                    if (choice < 0) !networkClient && !networkServer else choice == 1
                check(
                    CartTransition.authoredClip(player, true) == expected,
                    "clip default did not distinguish SP from network roles or explicit choice",
                )
                check(
                    !player.clipPilotAbsent && player.clipPilot == expected,
                    "clip default did not publish the matching XML selector",
                )
                check(
                    player.clipPilotWrites == (if (choice < 0) 1 else 0),
                    "clip default rewrote an explicit actor choice",
                )
                check(
                    CartTransition.authoredClip(player, true) == expected &&
                        player.clipPilotWrites == (if (choice < 0) 1 else 0),
                    "repeated action initialization rewrote the selected clip mode",
                )
            }
            zombie.network.GameClient.client = false
            zombie.network.GameServer.server = false
            for (choice in -1..1) {
                var player = allocate(Player::class.java)
                player.clipPilotAbsent = choice < 0
                player.clipPilot = choice == 1
                if (choice == 1) {
                    try {
                        CartTransition.authoredClip(player, false)
                        throw AssertionError("explicit unsupported clip opt-in did not fail fast")
                    } catch (expected: IllegalStateException) {
                        check(
                            required(expected.message).contains("native node retirement"),
                            "unsupported clip changed its failure reason",
                        )
                    }
                    check(
                        player.clipPilot && !player.clipPilotAbsent && player.clipPilotWrites == 0,
                        "unsupported clip fallback erased an explicit opt-in",
                    )
                } else {
                    check(
                        !CartTransition.authoredClip(player, false) &&
                            !player.clipPilot &&
                            !player.clipPilotAbsent,
                        "unsupported absent clip mode did not select the procedural XML node",
                    )
                    check(
                        player.clipPilotWrites == (if (choice < 0) 1 else 0),
                        "unsupported fallback rewrote an explicit opt-out",
                    )
                }
            }
            for (pickup in booleanArrayOf(true, false)) {
                val fixture = recovery(pickup)
                var player = fixture.player
                try {
                    CartTransition.end(player)
                    player.clipPilotAbsent = true
                    check(
                        CartTransition.update(player, fixture.cart, pickup, 0.0),
                        "SP default action setup refused",
                    )
                    check(
                        (value(state(player), "authored") as Boolean) &&
                            player.clipPilot &&
                            !player.clipPilotAbsent,
                        "ordinary SP action did not consume the absent authored-clip default",
                    )
                    CartTransition.end(player)
                    check(
                        player.clipPilot && !player.clipPilotAbsent,
                        "presentation cleanup erased the actor's selected clip mode",
                    )
                } finally {
                    CartTransition.end(player)
                }
            }
        } finally {
            zombie.network.GameClient.client = client
            zombie.network.GameServer.server = server
        }
    }

    private fun authoredClockAndRecovery() {
        val layer = allocate(zombie.core.skinnedmodel.advancedanimation.AnimLayer::class.java)
        var character = required(layer).javaClass.getDeclaredField("character")
        character.setAccessible(true)
        val track = zombie.core.skinnedmodel.animation.AnimationTrack.alloc()
        track.currentClip =
            zombie.core.skinnedmodel.animation.AnimationClip(2f, listOf(), "ClockFixture", false)
        track.animLayer = layer
        track.trackTimeToVariable = "ToolkitWoodCartClipTime"
        track.looping = false
        track.setSpeedDelta(0f)
        val tick =
            required(track)
                .javaClass
                .getDeclaredMethod("TickCurrentTime", Float::class.javaPrimitiveType!!)
        tick.setAccessible(true)
        for (metal in booleanArrayOf(false, true)) for (pickup in booleanArrayOf(true, false)) {
            val fixture = recovery(pickup)
            var player = fixture.player
            try {
                check(
                    !(value(state(player), "authored") as Boolean),
                    "clip pilot enabled without actor opt-in",
                )
                check(
                    !required(player.variables).containsKey("ToolkitWoodCartClipTime") &&
                        player.booleanVariables == null,
                    "default presentation published pilot animation variables",
                )
                CartTransition.end(player)
                player.clipPilot = true
                fixture.cart.kind =
                    "SaucedWheelbarrow.Wheelbarrow" + (if (metal) "Metal" else "Wood")
                fixture.cart.model = "Wheelbarrow" + (if (metal) "Metal" else "Wood")
                character.set(layer, player)
                track.reverse = !pickup
                for (progress in floatArrayOf(-0.1f, 0f, 0.25f, 0.75f, 1f, 1.1f)) {
                    check(
                        CartTransition.update(player, fixture.cart, pickup, (progress).toDouble()),
                        "authored clock update refused",
                    )
                    val clamped: Float = Math.max(0f, Math.min(1f, progress))
                    close(
                        required(required(player.variables).get("ToolkitWoodCartClipTime")),
                        clamped,
                        "clip clock did not clamp job delta",
                    )
                    check(
                        required(
                            required(player.booleanVariables).get("ToolkitWoodCartClipPickup"),
                        ) == pickup,
                        "clip direction changed",
                    )
                    check(
                        required(required(player.booleanVariables).get("ToolkitMetalCartClip")) ==
                            metal,
                        "wrong model selected for authored body clip",
                    )
                    invoke(tick, track, 0.2f)
                    close(
                        track.getCurrentTimeValue(),
                        2 * clamped,
                        "native clock ignored normalized progress at zero speed",
                    )
                    close(
                        track.getCurrentTrackTime(),
                        2 * (if (pickup) clamped else 1 - clamped),
                        "native reverse sampled wrong clip time",
                    )
                }
                CartTransition.update(player, fixture.cart, pickup, 0.55)
                val current = state(player)
                val rendered = required(current).javaClass.getDeclaredField("rendered")
                rendered.setAccessible(true)
                rendered.setBoolean(current, true)
                for (name in arrayOf("nativeRotation", "referenceRotation")) {
                    var field = required(current).javaClass.getDeclaredField(name)
                    field.setAccessible(true)
                    field.set(current, Quaternionf())
                }
                val pose = arrayOf(Matrix4f())
                val cart = Matrix4f()
                val poseField = required(current).javaClass.getDeclaredField("recoveryPose")
                poseField.setAccessible(true)
                val cartField = required(current).javaClass.getDeclaredField("recoveryCart")
                cartField.setAccessible(true)
                check(
                    !CartTransition.cancel(player, fixture.cart, pickup, null),
                    "authored recovery accepted a missing final pose and cart capture",
                )
                poseField.set(current, pose)
                check(
                    !CartTransition.cancel(player, fixture.cart, pickup, null),
                    "authored recovery accepted a missing cart capture",
                )
                poseField.set(current, null)
                cartField.set(current, cart)
                check(
                    !CartTransition.cancel(player, fixture.cart, pickup, null),
                    "authored recovery accepted a missing final body pose capture",
                )
                check(
                    player.overridePrimaryHandModel == null && player.modelResets == 0,
                    "captureless cancellation acquired a visual model lease",
                )
                poseField.set(current, pose)
                check(
                    CartTransition.cancel(player, fixture.cart, pickup, null),
                    "authored captured-pose recovery refused",
                )
                check(
                    (value(current, "movingRecovery") as Boolean),
                    "authored cancellation re-entered procedural body recovery",
                )
                close(
                    (value(current, "movementProgress") as Float),
                    0.55f,
                    "authored recovery lost its initial pose weight",
                )
                check(
                    value(current, "recoveryPose") === pose &&
                        value(current, "recoveryCart") === cart,
                    "cancellation replaced its final rendered pose capture",
                )
                CartTransition.tick(
                    player,
                    (value(current, "recoveryStart") as Long) + 200_000_000L,
                )
                close(
                    required(required(player.variables).get("ToolkitWoodCartClipTime")),
                    (value(current, "progress") as Float),
                    "recovery clock diverged from presentation progress",
                )
                CartTransition.end(player)
                recovered(fixture)
                check(
                    required(player.booleanVariables).isEmpty(),
                    "clip direction leaked after cleanup",
                )
                check(player.clipPilot, "presentation cleanup erased the actor's pilot opt-in")
            } finally {
                CartTransition.end(player)
            }
        }
        track.release()
    }

    private fun restartRecovery(pickup: Boolean): Recovery {
        val fixture = recovery(pickup)
        var player = fixture.player
        player.clipPilot = true
        val current = state(player)
        value(current, "authored", true)
        value(current, "recoveryPose", arrayOf(Matrix4f().translation(0f, 0.1f, 0f)))
        value(current, "recoveryCart", Matrix4f().translation(0f, 0.2f, 0f))
        // The displayed recovery frame has already moved away from its immutable cancellation seed.

        value(current, "lastPose", arrayOf(Matrix4f().translation(0f, 0.3f, 0f)))
        value(
            current,
            "lastPlacement",
            CartTransitionMath.Placement(10.2f, 20.7f, 2.1f, 5f, 20f, 0f, 1f),
        )
        value(current, "lastReach", 0.35f)
        value(current, "lastGrip", 0.15f)
        value(current, "lastRender", System.nanoTime())
        check(
            CartTransition.cancel(player, fixture.cart, pickup, null),
            "authored restart setup refused",
        )
        check(
            cancelled(player) === current,
            "authored cancellation did not retain its latest-frame candidate",
        )
        return fixture
    }

    private fun authoredRestartHandoff() {
        for (pickup in booleanArrayOf(true, false)) for (route in 0 until 3) {
            val fixture = restartRecovery(pickup)
            var player = fixture.player
            try {
                val previous = state(player)
                val pose = value(previous, "lastPose")
                val placement = value(previous, "lastPlacement")
                var replacement: String? = null
                if (route > 0) {
                    player.getCharacterActions().add(allocate(BaseAction::class.java))
                    player.performing = true
                    if (route == 2) {
                        replacement = String("WheelbarrowWood".toCharArray())
                        player.overridePrimaryHandModel = replacement
                    }
                    CartTransition.tick(player, System.nanoTime())
                    check(
                        state(player) == null && cancelled(player) === previous,
                        "native queue cleanup discarded the immediate restart candidate",
                    )
                }
                check(
                    CartTransition.update(player, fixture.cart, pickup, 0.0),
                    "same-item restart refused",
                )
                val restarted = state(player)
                check(
                    restarted !== previous && !(value(restarted, "recovering") as Boolean),
                    "restart reused cancellation progress",
                )
                check(
                    value(restarted, "restartPose") === pose &&
                        value(restarted, "restartPlacement") === placement,
                    "restart did not inherit the last displayed pose and cart placement",
                )
                check(
                    value(restarted, "restartPose") !== value(previous, "recoveryPose"),
                    "restart inherited the stale cancellation seed",
                )
                close(
                    (value(restarted, "restartReach") as Float),
                    0.35f,
                    "restart lost the displayed reach weight",
                )
                close(
                    (value(restarted, "restartGrip") as Float),
                    0.15f,
                    "restart lost the displayed grip weight",
                )
                close(
                    (value(restarted, "progress") as Float),
                    0f,
                    "restart did not reset native action progress",
                )
                check(
                    (value(restarted, "restartStart") as Long) > 0 && cancelled(player) == null,
                    "restart candidate was not consumed once",
                )
                check(
                    player.overridePrimaryHandModel === replacement,
                    "restart cleanup erased a replacement model identity",
                )
                check(
                    player.handWrites == 0 &&
                        fixture.cart.world === (if (pickup) fixture.world else null) &&
                        fixture.cart.container === (if (pickup) null else player.inventory) &&
                        player.primary === (if (pickup) null else fixture.cart) &&
                        player.secondary === player.primary,
                    "restart handoff changed authoritative item ownership",
                )
            } finally {
                CartTransition.end(player)
            }
        }
    }

    private fun authoredRestartRefusals() {
        for (pickup in booleanArrayOf(true, false)) for (failure in
            arrayOf(
                "stale",
                "pruned",
                "item",
                "direction",
                "world",
                "world-item",
                "world-square",
                "world-unloaded",
                "world-placement",
                "hands",
                "inventory",
                "protected",
                "protected-tick",
                "protected-after-cleanup",
                "explicit",
                "global",
            )) {
            if (pickup && failure.equals("inventory") || !pickup && failure.startsWith("world"))
                continue
            val fixture = restartRecovery(pickup)
            var player = fixture.player
            try {
                val previous = state(player)
                var item: Cart = fixture.cart
                var direction: Boolean = pickup
                when (failure) {
                    "stale" -> value(previous, "lastRender", System.nanoTime() - 201_000_000L)
                    "pruned" -> {
                        CartTransition.tick(
                            player,
                            (value(previous, "lastRender") as Long) + 200_000_001L,
                        )
                        check(
                            cancelled(player) == null,
                            "stale cancelled candidate survived the player tick",
                        )
                    }
                    "item" -> {
                        item = allocate(Cart::class.java)
                        item.kind = fixture.cart.kind
                        item.worldScale = 1f
                        if (pickup) {
                            var world = allocate(WorldItem::class.java)
                            world.item = item
                            world.square = player.square
                            item.world = world
                        } else {
                            item.container = player.inventory
                            player.primary = item
                            player.secondary = item
                        }
                    }
                    "direction" -> {
                        direction = !pickup
                        if (direction) fixture.cart.world = fixture.world
                        else {
                            fixture.cart.world = null
                            fixture.cart.container = player.inventory
                            player.primary = item
                            player.secondary = item
                        }
                    }
                    "world" -> {
                        var world = allocate(WorldItem::class.java)
                        world.item = item
                        world.square = player.square
                        item.world = world
                    }
                    "world-item" -> required(fixture.world).item = allocate(Cart::class.java)
                    "world-square" ->
                        required(fixture.world).square = allocate(IsoGridSquare::class.java)
                    "world-unloaded" -> required(fixture.world).square = null
                    "world-placement" -> item.worldScale = 1.1f
                    "hands" -> {
                        if (pickup) player.primary = allocate(Cart::class.java)
                        else player.secondary = null
                    }
                    "inventory" -> item.container = allocate(ItemContainer::class.java)
                    "protected" -> player.protection = 3
                    "protected-tick" -> {
                        player.protection = 3
                        CartTransition.tick(player, System.nanoTime())
                        check(
                            state(player) == null && cancelled(player) == null,
                            "protected-state cleanup retained a restart candidate",
                        )
                        player.protection = 0
                    }
                    "protected-after-cleanup" -> {
                        player.getCharacterActions().add(allocate(BaseAction::class.java))
                        CartTransition.tick(player, System.nanoTime())
                        check(
                            state(player) == null && cancelled(player) === previous,
                            "queue cleanup did not preserve its pending candidate",
                        )
                        required(player.actions).clear()
                        player.protection = 3
                        CartTransition.tick(player, System.nanoTime())
                        check(
                            state(player) == null && cancelled(player) == null,
                            "protected tick retained a candidate without an active state",
                        )
                        player.protection = 0
                    }
                    "explicit" -> CartTransition.end(player)
                    "global" -> CartTransition.end(null)
                }
                if (failure.equals("explicit") || failure.equals("global"))
                    check(
                        cancelled(player) == null,
                        "explicit cleanup retained a cancelled presentation candidate",
                    )
                check(
                    CartTransition.update(player, item, direction, 0.0),
                    "restart refusal fixture did not create a new state: " + failure,
                )
                check(
                    value(state(player), "restartPose") == null &&
                        value(state(player), "restartPlacement") == null,
                    "unsafe cancelled snapshot inherited: " + pickup + "/" + failure,
                )
                check(
                    !CartTransition.hidden(item),
                    "rejected snapshot hid the native world cart: " + failure,
                )
                check(
                    cancelled(player) == null && player.handWrites == 0,
                    "rejected restart leaked a candidate or changed hands",
                )
            } finally {
                CartTransition.end(player)
            }
        }
    }

    private fun authoredRestartRecancellation() {
        for (pickup in booleanArrayOf(true, false)) {
            val fixture = restartRecovery(pickup)
            var player = fixture.player
            try {
                check(
                    CartTransition.update(player, fixture.cart, pickup, 0.35),
                    "recancellation restart setup refused",
                )
                val current = state(player)
                check(
                    value(current, "restartPose") != null &&
                        value(current, "restartPlacement") != null,
                    "recancellation fixture did not inherit the unfinished handoff",
                )
                val pose = arrayOf(Matrix4f().translation(0f, 0.4f, 0f))
                val cart = Matrix4f().translation(0f, 0.5f, 0f)
                value(current, "rendered", true)
                value(current, "recoveryPose", pose)
                value(current, "recoveryCart", cart)
                value(current, "nativeRotation", Quaternionf())
                value(current, "referenceRotation", Quaternionf())
                check(
                    CartTransition.cancel(player, fixture.cart, pickup, null),
                    "cancellation during inherited handoff refused",
                )
                check(
                    value(current, "restartPose") == null &&
                        value(current, "restartPlacement") == null,
                    "recancellation retained the old handoff and would blend the recovery cart twice",
                )
                check(
                    value(current, "recoveryPose") === pose &&
                        value(current, "recoveryCart") === cart,
                    "recancellation discarded the newly displayed recovery seed",
                )
                check(
                    (value(current, "movingRecovery") as Boolean) && cancelled(player) === current,
                    "recancellation did not retain its own recovery state",
                )
                check(player.handWrites == 0, "recancellation changed authoritative hand ownership")
            } finally {
                CartTransition.end(player)
            }
        }
    }

    private fun pendingAction(
        player: Player,
        item: Cart,
        type: String,
    ): zombie.characters.CharacterTimedActions.LuaTimedActionNew {
        var action = allocate(zombie.characters.CharacterTimedActions.LuaTimedActionNew::class.java)
        val table = se.krka.kahlua.j2se.KahluaTableImpl(java.util.HashMap())
        val meta = se.krka.kahlua.j2se.KahluaTableImpl(java.util.HashMap())
        meta.rawset("Type", type)
        table.setMetatable(meta)
        table.rawset("character", player)
        if (type.equals("ISWalkToTimedActionF")) table.rawset("toolkitWoodCartItem", item)
        else if (type.equals("ToolkitWoodCartPickup"))
            table.rawset("itemId", (item.getID()).toDouble())
        else table.rawset("item", item)
        value(action, "table", table)
        action.chr = player
        action.maxTime = -1
        return action
    }

    private fun authoredPendingHandoff() {
        for (type in
            arrayOf(
                "ISWalkToTimedActionF",
                "ToolkitWoodCartPickup",
                "ToolkitWoodCartSetdown",
                "ToolkitWoodCartDrop",
            )) {
            val pickup: Boolean =
                type.equals("ISWalkToTimedActionF") || type.equals("ToolkitWoodCartPickup")
            val fixture = restartRecovery(pickup)
            var player = fixture.player
            try {
                val current = state(player)
                val lease = player.overridePrimaryHandModel
                val progress: Float = (value(current, "progress") as Float)
                required(player.actions).add(pendingAction(player, fixture.cart, type))
                player.performing = true
                val start: Long = System.nanoTime()
                CartTransition.tick(player, start)
                check(
                    state(player) === current && cancelled(player) === current,
                    "owned pending action discarded its rendered recovery: " + type,
                )
                CartTransition.tick(null)
                check(
                    state(player) === current && cancelled(player) === current,
                    "null-player tick disturbed another player's pending presentation",
                )
                check(
                    (value(current, "pendingStart") as Long) == start,
                    "pending action did not establish its first-seen deadline",
                )
                check(
                    player.overridePrimaryHandModel === lease,
                    "pending action lost its exact visual lease",
                )
                check(
                    CartTransition.hidden(fixture.cart) == pickup,
                    "pending pickup exposed its ground model",
                )
                check(
                    CartTransition.suppressHeldModel(player) == !pickup,
                    "pending setdown exposed a duplicate held model",
                )
                CartTransition.tick(player, start + 100_000_000L)
                close(
                    (value(current, "progress") as Float),
                    progress,
                    "pending action continued returning the cart to an endpoint",
                )
                if (type.equals("ISWalkToTimedActionF"))
                    required(player.actions)
                        .set(0, pendingAction(player, fixture.cart, "ToolkitWoodCartPickup"))
                CartTransition.tick(player, start + 150_000_000L)
                check(
                    (value(current, "pendingStart") as Long) == start,
                    "repeated pending ticks or walk-to-pickup handoff extended the deadline",
                )
                check(
                    CartTransition.update(player, fixture.cart, pickup, 0.0),
                    "owned pending action could not take over presentation",
                )
                val fresh = state(player)
                check(
                    fresh !== current && value(fresh, "restartPose") === value(current, "lastPose"),
                    "pending takeover lost its latest displayed pose",
                )
                check(
                    (value(fresh, "rendered") as Boolean) &&
                        CartTransition.hidden(fixture.cart) == pickup,
                    "fresh inherited pickup exposed the ground cart before its first actor render",
                )
                check(
                    player.handWrites == 0 &&
                        fixture.cart.world === (if (pickup) fixture.world else null) &&
                        player.primary === (if (pickup) null else fixture.cart) &&
                        player.secondary === player.primary,
                    "pending presentation changed native cart ownership",
                )
            } finally {
                CartTransition.end(player)
            }
        }
    }

    private fun authoredPendingDeadline() {
        for (pickup in booleanArrayOf(true, false)) for (admittedBeforeDeadline in
            booleanArrayOf(true, false)) {
            val fixture = restartRecovery(pickup)
            var player = fixture.player
            try {
                val current = state(player)
                val origin: Long = (value(current, "recoveryStart") as Long)
                var deadline: Long =
                    origin +
                        (Math.ceil(
                                (0.4 + 0.2 * (value(current, "cancelledProgress") as Float)) *
                                    1_000_000_000.0,
                            ))
                            .toLong()
                val admission: Long = deadline - 50_000_000L
                value(current, "lastRender", admission)
                CartTransition.tick(player, admission - 1)
                check(
                    state(player) === current,
                    "late pending fixture ended before its original recovery deadline",
                )
                required(player.actions)
                    .add(
                        pendingAction(
                            player,
                            fixture.cart,
                            if (pickup) "ToolkitWoodCartPickup" else "ToolkitWoodCartSetdown",
                        ),
                    )
                player.performing = true
                if (admittedBeforeDeadline) {
                    CartTransition.tick(player, admission)
                    check(
                        state(player) === current && cancelled(player) === current,
                        "valid pending action was rejected before the original deadline",
                    )
                    check(
                        (value(current, "pendingStart") as Long) == admission,
                        "late pending action lost its first-seen time",
                    )
                    CartTransition.tick(player, deadline - 1)
                    check(
                        state(player) === current,
                        "pending presentation ended before the original recovery deadline",
                    )
                }
                CartTransition.tick(player, deadline)
                check(
                    state(player) == null && cancelled(player) == null,
                    "late pending action extended the original recovery deadline",
                )
                check(
                    !CartTransition.hidden(fixture.cart) &&
                        !CartTransition.suppressHeldModel(player) &&
                        player.overridePrimaryHandModel == null,
                    "recovery deadline leaked its visual lease or model suppression",
                )
                check(
                    CartTransition.update(player, fixture.cart, pickup, 0.0),
                    "native action setup failed after pending expiration",
                )
                check(
                    value(state(player), "restartPose") == null &&
                        !CartTransition.hidden(fixture.cart),
                    "expired late pending action reused its cancelled presentation snapshot",
                )
                check(
                    player.handWrites == 0,
                    "pending deadline cleanup changed authoritative hand ownership",
                )
            } finally {
                CartTransition.end(player)
            }
        }
    }

    private fun authoredPendingRefusals() {
        for (type in
            arrayOf(
                "ISWalkToTimedActionF",
                "ToolkitWoodCartPickup",
                "ToolkitWoodCartSetdown",
                "ToolkitWoodCartDrop",
            )) for (failure in
            arrayOf(
                "wrong-item",
                "unmarked",
                "wrong-type",
                "native-owner",
                "lua-owner",
                "multiple",
                "finished",
                "stopped",
                "timeout",
                "expired-update",
                "protected",
                "foreign-model",
                "physical-owner",
            )) {
            val pickup: Boolean =
                type.equals("ISWalkToTimedActionF") || type.equals("ToolkitWoodCartPickup")
            val fixture = restartRecovery(pickup)
            var player = fixture.player
            try {
                val current = state(player)
                var action = pendingAction(player, fixture.cart, type)
                val table = action.getTable()
                required(player.actions).add(action)
                player.performing = true
                var foreign: String? = null
                when (failure) {
                    "wrong-item" -> {
                        if (type.equals("ISWalkToTimedActionF"))
                            table.rawset("toolkitWoodCartItem", allocate(Cart::class.java))
                        else if (pickup)
                            table.rawset("itemId", (fixture.cart.getID()).toDouble() + 1)
                        else table.rawset("item", allocate(Cart::class.java))
                    }
                    "unmarked" ->
                        table.rawset(
                            if (type.equals("ISWalkToTimedActionF")) "toolkitWoodCartItem"
                            else if (pickup) "itemId" else "item",
                            null,
                        )
                    "wrong-type" -> table.getMetatable().rawset("Type", "ISUnequipAction")
                    "native-owner" -> action.chr = allocate(Player::class.java)
                    "lua-owner" -> table.rawset("character", allocate(Player::class.java))
                    "multiple" -> required(player.actions).add(allocate(BaseAction::class.java))
                    "finished" -> action.maxTime = 0
                    "stopped" -> action.forceStop = true
                    "protected" -> player.protection = 3
                    "foreign-model" -> {
                        foreign = String("WheelbarrowWood".toCharArray())
                        player.overridePrimaryHandModel = foreign
                    }
                    "physical-owner" -> {
                        if (pickup) required(fixture.world).item = allocate(Cart::class.java)
                        else player.secondary = null
                    }
                    "timeout",
                    "expired-update" -> {
                        val start: Long = System.nanoTime()
                        CartTransition.tick(player, start)
                        check(
                            state(player) === current,
                            "valid pending timeout fixture was not retained",
                        )
                        if (failure.equals("expired-update")) {
                            value(current, "pendingStart", System.nanoTime() - 201_000_000L)
                            value(current, "lastRender", System.nanoTime())
                            check(
                                CartTransition.update(player, fixture.cart, pickup, 0.0),
                                "expired pending update refused the native action",
                            )
                            check(
                                value(state(player), "restartPose") == null &&
                                    !CartTransition.hidden(fixture.cart),
                                "fresh render timestamp bypassed the fixed pending deadline",
                            )
                            continue
                        }
                        CartTransition.tick(player, start + 150_000_000L)
                        CartTransition.tick(player, start + 200_000_001L)
                    }
                }
                if (!failure.equals("timeout")) CartTransition.tick(player, System.nanoTime())
                check(
                    state(player) == null &&
                        !CartTransition.hidden(fixture.cart) &&
                        !CartTransition.suppressHeldModel(player),
                    "unsafe pending action retained cart presentation: " + type + "/" + failure,
                )
                if (failure.equals("timeout") || failure.equals("protected"))
                    check(
                        cancelled(player) == null,
                        "expired/protected pending action retained a restart candidate",
                    )
                check(
                    player.overridePrimaryHandModel === foreign,
                    "pending cleanup clobbered a foreign visual identity",
                )
                check(
                    player.handWrites == 0,
                    "rejected pending action changed native hand ownership",
                )
            } finally {
                CartTransition.end(player)
            }
        }
    }

    private fun authoredNodeRetirement() {
        val tick =
            zombie.core.skinnedmodel.animation.AnimationTrack::class
                .java
                .getDeclaredMethod("TickCurrentTime", Float::class.javaPrimitiveType!!)
        tick.setAccessible(true)
        val find =
            zombie.core.skinnedmodel.advancedanimation.AnimLayer::class
                .java
                .getDeclaredMethod(
                    "findLiveNode",
                    zombie.core.skinnedmodel.advancedanimation.AnimNode::class.java,
                )
        find.setAccessible(true)
        for (prefix in arrayOf("ToolkitWoodCartClip", "ToolkitMetalCartClip")) for (pickup in
            booleanArrayOf(true, false)) {
            var player = allocate(Player::class.java)
            player.setVariable("ToolkitWoodCartClipTime", 0.55f)
            val layer = allocate(zombie.core.skinnedmodel.advancedanimation.AnimLayer::class.java)
            var character = required(layer).javaClass.getDeclaredField("character")
            character.setAccessible(true)
            character.set(layer, player)
            val nodes =
                java.util.ArrayList<zombie.core.skinnedmodel.advancedanimation.LiveAnimNode>()
            val nodesField = required(layer).javaClass.getDeclaredField("liveAnimNodes")
            nodesField.setAccessible(true)
            nodesField.set(layer, nodes)
            val source = zombie.core.skinnedmodel.advancedanimation.AnimNode()
            source.name = prefix + (if (pickup) "Pickup" else "Setdown")
            source.parentState = zombie.core.skinnedmodel.advancedanimation.AnimState()
            source.parentState.name = "actions"
            val unrelatedSource = zombie.core.skinnedmodel.advancedanimation.AnimNode()
            unrelatedSource.name = "UnrelatedAction"
            unrelatedSource.parentState = source.parentState
            val old = zombie.core.skinnedmodel.advancedanimation.LiveAnimNode.alloc(layer, source)
            val unrelated =
                zombie.core.skinnedmodel.advancedanimation.LiveAnimNode.alloc(
                    layer,
                    unrelatedSource,
                )
            old.setActive(true)
            nodes.add(old)
            nodes.add(unrelated)
            val tracks = arrayOfNulls<zombie.core.skinnedmodel.animation.AnimationTrack>(4)
            for (i in 0 until tracks.size) {
                val track = zombie.core.skinnedmodel.animation.AnimationTrack.alloc()
                tracks[i] = track
                track.currentClip =
                    zombie.core.skinnedmodel.animation.AnimationClip(
                        2f,
                        listOf(),
                        "RetirementFixture",
                        false,
                    )
                track.animLayer = layer
                track.trackTimeToVariable = "ToolkitWoodCartClipTime"
                track.looping = false
                track.reverse = !pickup
                track.setSpeedDelta(1f)
                invoke(tick, track, 0.2f)
            }
            try {
                old.addMainTrack(required(tracks[0]))
                old.addMainTrack(required(tracks[1]))
                unrelated.addMainTrack(required(tracks[2]))
                check(
                    invoke(find, layer, source) === old,
                    "native selection did not find the active pilot node",
                )
                check(
                    !CartTransition.retireAuthoredNode(old, !pickup),
                    "retirement accepted the opposite action direction",
                )
                check(
                    required(tracks[0]).trackTimeToVariable != null,
                    "opposite-direction retirement changed the clock",
                )
                check(
                    !CartTransition.retireAuthoredNode(unrelated, pickup),
                    "retirement changed an unrelated action node",
                )
                check(
                    CartTransition.retireAuthoredNode(old, pickup),
                    "owned pilot node retirement refused",
                )
                check(
                    !CartTransition.retireAuthoredNode(old, pickup),
                    "already-retired node was retired twice",
                )
                check(
                    invoke(find, layer, source) == null,
                    "native selection reused the retired same-direction node",
                )
                player.setVariable("ToolkitWoodCartClipTime", 0f)
                for (i in 0 until 2) {
                    check(
                        required(tracks[i]).trackTimeToVariable == null,
                        "outgoing main track retained the shared clock binding",
                    )
                    close(
                        required(tracks[i]).getSpeedDelta(),
                        0f,
                        "outgoing main track retained autonomous playback",
                    )
                    invoke(tick, required(tracks[i]), 0.2f)
                    close(
                        required(tracks[i]).getCurrentTrackTime(),
                        2 * (if (pickup) 0.55f else 0.45f),
                        "new action clock reset moved the fading pose",
                    )
                }
                check(
                    "ToolkitWoodCartClipTime".equals(required(tracks[2]).trackTimeToVariable),
                    "unrelated track lost its clock binding",
                )
                close(
                    required(tracks[2]).getSpeedDelta(),
                    1f,
                    "unrelated track playback speed changed",
                )
                check(
                    invoke(find, layer, unrelatedSource) === unrelated,
                    "retirement made an unrelated node unselectable",
                )
                val fresh =
                    zombie.core.skinnedmodel.advancedanimation.LiveAnimNode.alloc(layer, source)
                fresh.addMainTrack(required(tracks[3]))
                fresh.setActive(true)
                nodes.add(fresh)
                required(tracks[3]).setSpeedDelta(0f)
                check(
                    invoke(find, layer, source) === fresh,
                    "native selection did not choose the fresh same-direction node",
                )
                player.setVariable("ToolkitWoodCartClipTime", 0.25f)
                invoke(tick, required(tracks[3]), 0.2f)
                close(
                    required(tracks[3]).getCurrentTrackTime(),
                    2 * (if (pickup) 0.25f else 0.75f),
                    "fresh track did not follow the restarted action clock",
                )
            } finally {
                for (track in tracks) required(track).release()
            }
        }
    }

    private fun recoveryRefusals() {
        for (pickup in booleanArrayOf(true, false)) for (failure in 0 until 20) {
            val fixture = recovery(pickup)
            var player = fixture.player
            val cart = fixture.cart
            var requested: InventoryItem = cart
            var direction: Boolean = pickup
            try {
                when (failure) {
                    0 -> {
                        var field = required(state(player)).javaClass.getDeclaredField("rendered")
                        field.setAccessible(true)
                        field.setBoolean(state(player), false)
                    }
                    1 -> requested = allocate(Cart::class.java)
                    2 -> direction = !pickup
                    3 -> player.performing = true
                    4 -> player.getCharacterActions().add(allocate(BaseAction::class.java))
                    5 -> {
                        player.getCharacterActions().add(allocate(BaseAction::class.java))
                        required(player.actions).add(allocate(BaseAction::class.java))
                    }
                    6 -> player.overridePrimaryHandModel = "ForeignPrimary"
                    7 -> player.overrideSecondaryHandModel = "ForeignSecondary"
                    8 -> player.primary = if (pickup) allocate(Cart::class.java) else null
                    9 -> {
                        if (pickup) cart.world = null
                        else cart.container = allocate(ItemContainer::class.java)
                    }
                    10 -> {
                        if (pickup) required(fixture.world).item = allocate(Cart::class.java)
                        else cart.world = fixture.world
                    }
                    11 -> {
                        if (pickup) required(fixture.world).square = null
                        else player.secondary = null
                    }
                    12 -> {
                        if (pickup) player.otherFloor = true
                        else player.secondary = allocate(Cart::class.java)
                    }
                    13,
                    14 -> {
                        var field =
                            required(state(player))
                                .javaClass
                                .getDeclaredField(
                                    if (failure == 13) "nativeHeight" else "referenceHeight",
                                )
                        field.setAccessible(true)
                        field.setFloat(state(player), Float.NaN)
                    }
                    15,
                    16,
                    17,
                    18 -> {
                        var field =
                            required(state(player))
                                .javaClass
                                .getDeclaredField(
                                    if (failure % 2 == 1) "nativeRotation" else "referenceRotation",
                                )
                        field.setAccessible(true)
                        field.set(
                            state(player),
                            if (failure < 17) null else Quaternionf(0f, 0f, 0f, 0f),
                        )
                    }
                    19 ->
                        check(
                            CartTransition.update(player, cart, pickup, 0.0),
                            "zero-progress setup refused",
                        )
                }
                check(
                    !CartTransition.cancel(player, requested, direction, null),
                    "invalid recovery accepted: " + pickup + "/" + failure,
                )
                check(
                    !(value(state(player), "recovering") as Boolean),
                    "refused cancellation retained recovery state",
                )
                check(
                    !CartTransition.suppressHeldModel(player),
                    "refused cancellation suppressed an equipped visual",
                )
                check(
                    player.modelResets == 0 && player.handWrites == 0,
                    "refused cancellation changed models or hand ownership",
                )
                check(
                    java.util.Objects.equals(
                        player.overridePrimaryHandModel,
                        if (failure == 6) "ForeignPrimary" else null,
                    ),
                    "refusal overwrote another primary visual",
                )
                check(
                    java.util.Objects.equals(
                        player.overrideSecondaryHandModel,
                        if (failure == 7) "ForeignSecondary" else null,
                    ),
                    "refusal overwrote another secondary visual",
                )
                close(cart.alpha, 0.7f, "refused recovery changed serialized alpha")
            } finally {
                CartTransition.end(player)
            }
        }
    }

    private fun collisionInterruptions() {
        for (pickup in booleanArrayOf(true, false)) {
            val fixture = recovery(pickup)
            var player = fixture.player
            val current = zombie.ai.StateMachine::class.java.getDeclaredField("currentState")
            current.setAccessible(true)
            try {
                current.set(
                    player.getStateMachine(),
                    zombie.ai.states.CollideWithWallState.instance(),
                )
                check(
                    !CartTransition.cancel(player, fixture.cart, pickup, null),
                    "native wall collision accepted recovery",
                )
                current.set(player.getStateMachine(), null)
                check(
                    CartTransition.cancel(player, fixture.cart, pickup, null),
                    "ordinary recovery refused after collision exit",
                )
                current.set(
                    player.getStateMachine(),
                    zombie.ai.states.CollideWithWallState.instance(),
                )
                val slot = zombie.core.skinnedmodel.model.ModelSlotRenderData()
                slot.character = player
                check(
                    !CartTransition.render(slot),
                    "transition render retained native wall collision ownership",
                )
                recovered(fixture)
                check(
                    cancelled(player) == null &&
                        player.overridePrimaryHandModel == null &&
                        !CartTransition.hidden(fixture.cart) &&
                        !CartTransition.suppressHeldModel(player),
                    "native collision retained a recovery snapshot, visual lease or suppression",
                )
                current.set(player.getStateMachine(), null)
                check(
                    CartTransition.update(player, fixture.cart, pickup, 0.3),
                    "native collision exit prevented a fresh ordinary action",
                )
                check(
                    CartTransition.cancel(player, fixture.cart, pickup, null) == false,
                    "fresh unrendered action inherited the cancelled pose capture",
                )
                check(
                    player.handWrites == 0 &&
                        player.primary === (if (pickup) null else fixture.cart) &&
                        player.secondary === (if (pickup) null else fixture.cart),
                    "collision recovery changed native hand ownership",
                )
            } finally {
                current.set(player.getStateMachine(), null)
                CartTransition.end(player)
            }
        }
    }

    private fun recoveryInterruptions() {
        for (pickup in booleanArrayOf(true, false)) for (protection in 1..10) {
            val fixture = recovery(pickup)
            var player = fixture.player
            try {
                player.protection = protection
                check(
                    !CartTransition.cancel(player, fixture.cart, pickup, null),
                    "protected state accepted recovery: " + protection,
                )
                player.protection = 0
                check(
                    CartTransition.cancel(player, fixture.cart, pickup, null),
                    "valid empty-stack recovery refused",
                )
                val start: Long = (value(state(player), "recoveryStart") as Long)
                player.protection = protection
                CartTransition.tick(player, start + 10_000_000L)
                recovered(fixture)
            } finally {
                CartTransition.end(player)
            }
        }
        for (pickup in booleanArrayOf(true, false)) for (interruption in 0 until 6) {
            val fixture = recovery(pickup)
            var player = fixture.player
            try {
                check(
                    CartTransition.cancel(player, fixture.cart, pickup, null),
                    "valid recovery refused",
                )
                val start: Long = (value(state(player), "recoveryStart") as Long)
                when (interruption) {
                    0 -> player.getCharacterActions().add(allocate(BaseAction::class.java))
                    1 -> player.performing = true
                    2 -> {
                        if (pickup) fixture.cart.world = null else player.secondary = null
                    }
                    3 -> player.overridePrimaryHandModel = "ReplacementPrimary"
                    4 -> player.overrideSecondaryHandModel = "ReplacementSecondary"
                    5 -> {
                        val previous = state(player)
                        check(
                            CartTransition.update(player, fixture.cart, pickup, 0.2),
                            "new same-cart action update refused",
                        )
                        check(
                            state(player) !== previous &&
                                !(value(state(player), "recovering") as Boolean),
                            "new same-cart action reused recovery state",
                        )
                        close(
                            (value(state(player), "progress") as Float),
                            0.2f,
                            "new action inherited recovery progress",
                        )
                        check(
                            player.overridePrimaryHandModel == null && player.modelResets == 2,
                            "new action retained the stopped action's model lease",
                        )
                        continue
                    }
                }
                CartTransition.tick(player, start + 10_000_000L)
                recovered(fixture)
                check(
                    java.util.Objects.equals(
                        player.overridePrimaryHandModel,
                        if (interruption == 3) "ReplacementPrimary" else null,
                    ),
                    "recovery cleanup erased a replacement primary model",
                )
                check(
                    java.util.Objects.equals(
                        player.overrideSecondaryHandModel,
                        if (interruption == 4) "ReplacementSecondary" else null,
                    ),
                    "recovery cleanup erased a replacement secondary model",
                )
            } finally {
                CartTransition.end(player)
            }
        }
    }

    private fun recoveryLeaseIdentity() {
        for (pickup in booleanArrayOf(true, false)) for (tick in booleanArrayOf(false, true)) {
            val fixture = recovery(pickup)
            var player = fixture.player
            try {
                check(
                    CartTransition.cancel(player, fixture.cart, pickup, null),
                    "identity lease setup refused",
                )
                val current = state(player)
                val lease = player.overridePrimaryHandModel
                check(
                    lease === value(current, "visualModel") &&
                        lease !== fixture.cart.getStaticModel(),
                    "recovery did not acquire a unique model lease token",
                )
                var foreign: String? =
                    if (tick) fixture.cart.getStaticModel()
                    else String(required(lease).toCharArray())
                check(
                    foreign !== lease && foreign.equals(lease),
                    "foreign lease fixture must have equal text and different identity",
                )
                player.overridePrimaryHandModel = foreign
                check(
                    !CartTransition.suppressHeldModel(player),
                    "equal-text foreign override retained held-model suppression",
                )
                if (tick) {
                    player.getCharacterActions().add(allocate(BaseAction::class.java))
                    CartTransition.tick(
                        player,
                        (value(current, "recoveryStart") as Long) + 10_000_000L,
                    )
                } else CartTransition.end(player)
                recovered(fixture)
                check(
                    player.overridePrimaryHandModel === foreign,
                    "cleanup erased an equal-text foreign model lease",
                )
                check(
                    player.modelResets == 1,
                    "cleanup rebuilt a model owned by an equal-text foreign writer",
                )
                CartTransition.end(player)
                check(
                    player.overridePrimaryHandModel === foreign && player.modelResets == 1,
                    "repeated cleanup touched a foreign model lease",
                )
            } finally {
                CartTransition.end(player)
            }
        }
    }

    private fun geometry() {
        var model: Matrix4f = Matrix4f().rotateX((Math.PI).toFloat() / 2).scale(90f)
        val held: Matrix4f =
            Matrix4f()
                .translation(-0.0060535767f, 0.097179376f, -0.34652624f)
                .rotateX((Math.toRadians(74.24)).toFloat())
                .scale(76.5f)
        for (angle in
            floatArrayOf(
                0f,
                0.3f,
                (Math.PI).toFloat() / 4,
                (Math.PI).toFloat() / 2,
                (Math.PI).toFloat(),
                3.7f,
                5.4f,
            )) {
            val pose = CartTransition.dropPlacement(held, model, 10.25f, 20.75f, 2f, angle, 1f)
            check(
                pose != null && pose.xRotation == 0f && pose.yRotation == 0f,
                "drop must use native planar orientation",
            )
            var expected: Double = angle + Math.PI
            val actual: Double = Math.toRadians((required(pose).zRotation).toDouble())
            check(
                Math.abs(Math.atan2(Math.sin(actual - expected), Math.cos(actual - expected))) <
                    0.00001,
                "drop yaw folded across native Euler singularity",
            )
            close(required(pose).worldScale, 0.85f, "world/held scale agreement")
            check(
                required(pose).zRotation >= 0 && required(pose).zRotation < 360,
                "native yaw normalization",
            )
            val ground = Matrix4f()
            check(
                CartTransitionMath.worldToActor(pose, model, 10.25f, 20.75f, 2f, angle, ground),
                "grounded stance projects",
            )
            val axle =
                org.joml.Vector3f(
                    CartWheelSpin.CENTER_X,
                    CartWheelSpin.CENTER_Y,
                    CartWheelSpin.CENTER_Z,
                )
            val offset =
                ground
                    .transformPosition(axle, org.joml.Vector3f())
                    .sub(held.transformPosition(axle, org.joml.Vector3f()))
            close(offset.x, 0f, "grounded wheel stays laterally aligned")
            close(
                offset.z,
                -0.06f,
                "lowering rolls forward to leave feet behind the handle ends at every heading",
            )
        }
        check(
            CartTransition.dropPlacement(Matrix4f().m00(Float.NaN), model, 0f, 0f, 0f, 0f, 1f) ==
                null,
            "invalid held transform accepted",
        )
    }

    private fun metalDropGeometry() {
        val profile = CartWheelbarrow.METAL
        // Native world scale paired with the calibrated .85 hand attachment.

        var model = Matrix4f().scale(0.0091743395f / 0.85f)
        check(
            CartWorldSupport.apply("SaucedWheelbarrow.WheelbarrowMetal", model, 0.85f),
            "metal world support refused",
        )
        for (bank in
            floatArrayOf(
                (Math.toRadians((-7).toDouble())).toFloat(),
                0f,
                (Math.toRadians((7).toDouble())).toFloat(),
            )) for (gait in floatArrayOf(0f, -0.24f)) for (angle in
            floatArrayOf(0f, 0.3f, 1.57f, 3.14f, 4.7f, 6.1f)) {
            val held = profile.held(Matrix4f())
            check(
                CartGrounding.alignWheelbarrow(
                    held,
                    profile,
                    bank,
                    Math.abs(bank),
                    gait,
                    Matrix4f(),
                ),
                "metal held pose refused",
            )
            val pose =
                CartTransition.dropPlacement(
                    held,
                    model,
                    10.25f,
                    20.75f,
                    2f,
                    angle,
                    1f,
                    profile.pickupStanceBack(),
                    profile,
                )
            check(
                pose != null && pose.xRotation == 0f && pose.yRotation == 0f,
                "metal drop lost native planar placement",
            )
            val ground = Matrix4f()
            check(
                CartTransitionMath.worldToActor(pose, model, 10.25f, 20.75f, 2f, angle, ground),
                "metal landing did not project",
            )
            val offset =
                ground
                    .transformPosition(profile.center(org.joml.Vector3f()))
                    .sub(held.transformPosition(profile.center(org.joml.Vector3f())))
            close(offset.x, 0f, "metal drop moved the axle sideways")
            close(
                offset.z,
                -profile.pickupStanceBack(),
                "metal drop must match its pickup stance at every heading",
            )
            close(required(pose).worldScale, 0.85f, "metal drop changed native hand/world scale")
        }
    }

    private fun recoveryModelScope() {
        val manager = allocate(zombie.core.skinnedmodel.ModelManager::class.java)
        val type = zombie.core.skinnedmodel.ModelManager.ModelSlot::class.java
        val method =
            zombie.core.skinnedmodel.ModelManager::class
                .java
                .getDeclaredMethod(
                    "DoCharacterModelEquipped",
                    zombie.characters.IsoGameCharacter::class.java,
                    type,
                )
        method.setAccessible(true)
        for (previous in booleanArrayOf(false, true)) {
            val ordinary = allocate(Player::class.java)
            ordinary.forceNullOverride = previous
            invoke(
                method,
                manager,
                ordinary,
                zombie.core.skinnedmodel.ModelManager.ModelSlot(
                    0,
                    zombie.core.skinnedmodel.model.ModelInstance(),
                    ordinary,
                ),
            )
            check(
                ordinary.forceNullOverride == previous,
                "ordinary native model rebuild changed the caller's override flag",
            )
            for (pickup in booleanArrayOf(false, true)) for (guard in 0 until 6) {
                val fixture = recovery(pickup)
                var player = fixture.player
                try {
                    check(
                        CartTransition.cancel(player, fixture.cart, pickup, null),
                        "model-scope recovery setup refused",
                    )
                    when (guard) {
                        1 -> player.overridePrimaryHandModel = "ForeignPrimary"
                        2 -> player.overrideSecondaryHandModel = "ForeignSecondary"
                        3 -> player.getCharacterActions().add(allocate(BaseAction::class.java))
                        4 -> player.protection = 3
                        5 -> player.performing = true
                    }
                    player.forceNullOverride = previous
                    player.expectedForceNull = previous || !pickup && guard == 0
                    player.modelError = NativePass()
                    val slot =
                        zombie.core.skinnedmodel.ModelManager.ModelSlot(
                            0,
                            zombie.core.skinnedmodel.model.ModelInstance(),
                            player,
                        )
                    try {
                        invoke(method, manager, player, slot)
                        throw AssertionError("native model error was suppressed")
                    } catch (error: NativePass) {
                        check(
                            error === player.modelError,
                            "model scope changed the native exception identity",
                        )
                    }
                    check(
                        player.modelScopes == 1 && player.forceNullOverride == previous,
                        "native model error leaked its temporary visual suppression",
                    )
                    check(
                        player.handWrites == 0 &&
                            player.primary === (if (pickup) null else fixture.cart) &&
                            player.secondary === (if (pickup) null else fixture.cart),
                        "visual suppression changed native item ownership",
                    )
                    check(
                        fixture.cart.world === (if (pickup) fixture.world else null) &&
                            fixture.cart.container === (if (pickup) null else player.inventory),
                        "visual suppression moved the exact cart",
                    )
                } finally {
                    CartTransition.end(player)
                }
            }
        }
    }

    private fun remoteNativeHandModels() {
        val manager = zombie.scripting.ScriptManager.instance
        var module = zombie.scripting.objects.ScriptModule()
        module.name = "Base"
        manager.moduleMap.put("Base", module)
        manager.moduleList.add(module)
        val models = required(manager).javaClass.getDeclaredField("models")
        models.setAccessible(true)
        ((models.get(manager) as zombie.scripting.ScriptBucketCollection<*>)).registerModule(module)
        var model = zombie.scripting.objects.ModelScript()
        model.name = "WheelbarrowWood"
        model.InitLoadPP(model.name)
        model.setModule(module)
        manager.addModelScript(model)
        val previousClient: Boolean = zombie.network.GameClient.client
        zombie.network.GameClient.client = true
        val fixture = recovery(false)
        var player = fixture.player
        var item = fixture.cart
        CartTransition.end(player)
        player.protection = 1
        val nativeAction = allocate(BaseAction::class.java)
        nativeAction.chr = player
        val ai = allocate(zombie.characters.NetworkPlayerAI::class.java)
        ai.setAction(nativeAction)
        // Native action params default null hand-model names to the empty string.

        zombie.ai.states.PlayerActionsState.SECONDARY.set(player, null)
        val empty: String? = zombie.ai.states.PlayerActionsState.SECONDARY.get(player)
        check("".equals(empty), "native secondary action param no longer defaults to empty")
        item.model = "Base.WheelbarrowWood"
        ai.setOverride(true, "WheelbarrowWood", empty)
        player.performing = true
        player.performingAction = "ToolkitWoodCart"
        val pose =
            CartActionSync.Pose(
                item.getID(),
                1,
                1,
                0,
                0.4f,
                0f,
                10.25f,
                20.75f,
                2.00175f,
                0f,
                0f,
                0f,
                0.85f,
            )
        try {
            for (gate in arrayOf("secondary", "action", "inactive", "cart", "container")) {
                player.overrideSecondaryHandModel = empty
                player.performingAction = "ToolkitWoodCart"
                player.performing = true
                item.container = player.inventory
                var candidate = pose
                when (gate) {
                    "secondary" -> player.overrideSecondaryHandModel = "Mug"
                    "action" -> player.performingAction = "OtherAction"
                    "inactive" -> player.performing = false
                    "cart" ->
                        candidate =
                            CartActionSync.Pose(
                                item.getID() + 1,
                                1,
                                1,
                                0,
                                0.4f,
                                0f,
                                10.25f,
                                20.75f,
                                2.00175f,
                                0f,
                                0f,
                                0f,
                                0.85f,
                            )
                    "container" -> item.container = allocate(ItemContainer::class.java)
                }
                check(
                    !CartTransition.remote(player, candidate, 0.4f) && state(player) == null,
                    "remote action borrowed unrelated native ownership: " + gate,
                )
            }
            item.container = player.inventory
            player.performing = true
            player.performingAction = "ToolkitWoodCart"
            ai.setOverride(true, "WheelbarrowWood", empty)
            check(
                CartTransition.remote(player, pose, 0.4f),
                "native empty secondary rejected exact remote cart action",
            )
            val current = state(player)
            value(current, "rendered", true)
            value(current, "nativeRotation", Quaternionf())
            value(current, "referenceRotation", Quaternionf())
            ai.setOverride(false, empty, empty)
            player.performing = false
            player.performingAction = ""
            val cancelled =
                CartActionSync.Pose(
                    item.getID(),
                    1,
                    2,
                    2,
                    0.3f,
                    0.4f,
                    10.25f,
                    20.75f,
                    2.00175f,
                    0f,
                    0f,
                    0f,
                    0.85f,
                )
            check(
                CartTransition.remote(player, cancelled, 0.3f) &&
                    true.equals(value(current, "recovering")),
                "native empty exit overrides prevented remote cancellation recovery",
            )
            val lease: String? = player.overridePrimaryHandModel
            check(
                lease != null &&
                    lease.equals(item.getStaticModel()) &&
                    CartTransition.remote(player, cancelled, 0.25f),
                "remote recovery lost its exact visual lease through native empty secondary",
            )
            // Native ActionContext.exit runs after the bridge's postUpdateAnimating entry hook.

            ai.setOverride(false, null, null)
            check(
                CartTransition.remote(player, cancelled, 0.24f) &&
                    player.overridePrimaryHandModel === lease,
                "late native action exit discarded the same cart/generation recovery lease",
            )
            var deadline: Long = (value(current, "recoveryStart") as Long)
            check(
                required(value(current, "remoteModelBindStart")).equals(deadline),
                "native clear extended recovery binding deadline",
            )
            value(current, "recoveryStart", System.nanoTime() - 301_000_000L)
            ai.setOverride(false, null, null)
            check(
                !CartTransition.remote(player, cancelled, 0.23f) &&
                    player.overridePrimaryHandModel == null,
                "expired native-clear recovery reclaimed an override",
            )
            value(current, "recoveryStart", deadline)
            player.overridePrimaryHandModel = lease
            player.performing = true
            player.performingAction = "OtherAction"
            ai.setOverride(false, null, null)
            check(
                !CartTransition.remote(player, cancelled, 0.23f) &&
                    player.overridePrimaryHandModel == null,
                "native-clear recovery stole another active action",
            )
            player.performing = false
            player.performingAction = ""
            player.overridePrimaryHandModel = lease
            player.overridePrimaryHandModel = String(required(lease).toCharArray())
            CartTransition.endRemote(player)
            check(
                player.overridePrimaryHandModel !== lease &&
                    player.overridePrimaryHandModel.equals(lease),
                "remote cleanup cleared a foreign equal-valued model lease",
            )
            check(
                player.handWrites == 0 &&
                    player.primary === item &&
                    player.secondary === item &&
                    item.container === player.inventory,
                "remote action presentation changed native item ownership",
            )
        } finally {
            CartTransition.endRemote(player)
            zombie.network.GameClient.client = previousClient
        }
    }

    private fun remotePickupFacing(
        player: Player,
        ai: zombie.characters.NetworkPlayerAI,
        pose: CartActionSync.Pose,
    ) {
        var animation = allocate(zombie.core.skinnedmodel.animation.AnimationPlayer::class.java)
        value(animation, "targetDir", zombie.iso.Vector2())
        val forward =
            zombie.characters.IsoGameCharacter::class.java.getDeclaredField("forwardDirection")
        forward.setAccessible(true)
        forward.set(player, zombie.iso.Vector2())
        player.animation = animation
        player.network = ai
        ai.prediction = zombie.network.fields.character.Prediction()
        ai.prediction.direction = 1.4306948f
        ai.targetX = 10.225f
        ai.targetY = 20.674f
        val stale: Float = -1.8766751f
        player.setTargetAndCurrentDirection(
            (Math.cos((stale).toDouble())).toFloat(),
            (Math.sin((stale).toDouble())).toFloat(),
        )
        player.setForwardDirection(
            (Math.cos((ai.prediction.direction).toDouble())).toFloat(),
            (Math.sin((ai.prediction.direction).toDouble())).toFloat(),
        )
        animation.updateForwardDirection(player)
        check(
            Math.abs(
                CartSteeringMath.wrap((animation.getAngle() - ai.prediction.direction).toDouble()),
            ) > 2,
            "native target-only update no longer reproduces stale pickup render yaw",
        )
        check(CartTransition.remote(player, pose, 0.18f), "exact remote pickup facing refused")
        close(
            animation.getAngle(),
            ai.prediction.direction,
            "remote pickup kept native catch-up yaw away from handles",
        )
        close(
            animation.getTargetAngle(),
            ai.prediction.direction,
            "remote pickup changed only current animation yaw",
        )
        close(player.getX(), 10.25f, "remote pickup facing moved actor X")
        close(player.getY(), 20.75f, "remote pickup facing moved actor Y")
        close(ai.targetX, 10.225f, "remote pickup facing changed native target X")
        close(ai.targetY, 20.674f, "remote pickup facing changed native target Y")
        for (guard in arrayOf("foreign-action", "protected", "invalid-heading")) {
            animation.setAngle(stale)
            player.performingAction = "ToolkitWoodCart"
            player.protection = 1
            ai.prediction.direction = 1.4306948f
            if (guard.equals("foreign-action")) player.performingAction = "OtherAction"
            if (guard.equals("protected")) player.protection = 3
            if (guard.equals("invalid-heading")) ai.prediction.direction = Float.NaN
            val accepted: Boolean = CartTransition.remote(player, pose, 0.2f)
            check(
                accepted == guard.equals("invalid-heading"),
                "pickup facing changed ownership guard: " + guard,
            )
            close(
                animation.getAngle(),
                stale,
                "pickup facing borrowed unrelated or invalid native heading: " + guard,
            )
        }
        player.performingAction = "ToolkitWoodCart"
        player.protection = 1
        player.animation = null
        player.network = null
    }

    private fun remotePickupModelBind() {
        val modelField =
            zombie.core.skinnedmodel.ModelManager::class.java.getDeclaredField("animModel")
        modelField.setAccessible(true)
        val previousModel: Any? = modelField.get(zombie.core.skinnedmodel.ModelManager.instance)
        val mesh = allocate(zombie.core.skinnedmodel.model.ModelMesh::class.java)
        val clip =
            zombie.core.skinnedmodel.animation.AnimationClip(1f, listOf(), "Bob_Cart_Idle", true)
        mesh.skinningData =
            zombie.core.skinnedmodel.model.SkinningData(
                java.util.HashMap(java.util.Map.of(clip.name, clip)),
                listOf(),
                listOf(),
                listOf(),
                listOf(),
                java.util.HashMap(),
            )
        val previousCell = zombie.iso.IsoWorld.instance.currentCell
        val previousClient: Boolean = zombie.network.GameClient.client
        val previousPlayers: Int = IsoPlayer.numPlayers
        val cell = allocate(zombie.iso.IsoCell::class.java)
        val map = allocate(zombie.iso.IsoChunkMap::class.java)
        value(cell, "chunkMap", arrayOf(map))
        val chunks =
            arrayOfNulls<zombie.iso.IsoChunk>(
                zombie.iso.IsoChunkMap.chunkGridWidth * zombie.iso.IsoChunkMap.chunkGridWidth,
            )
        val chunk = allocate(zombie.iso.IsoChunk::class.java)
        chunk.loaded = true
        chunk.maxLevel = 2
        chunk.minLevel = chunk.maxLevel
        chunk.squares = Array(1) { arrayOfNulls<IsoGridSquare>(64) }
        chunks[2 * zombie.iso.IsoChunkMap.chunkGridWidth + 1] = chunk
        value(map, "chunksSwapB", chunks)
        try {
            modelField.set(zombie.core.skinnedmodel.ModelManager.instance, mesh)
            zombie.iso.IsoWorld.instance.currentCell = cell
            zombie.network.GameClient.client = true
            IsoPlayer.numPlayers = 1
            for (gate in
                arrayOf(
                    "delayed",
                    "facing",
                    "late-clear",
                    "timeout",
                    "replacement",
                    "foreign-lease",
                    "new-action",
                    "failed-solve",
                    "missing-script",
                    "unnamed-script",
                    "unrelated-script",
                    "unnamed-only",
                )) {
                val fixture = recovery(true)
                var player = fixture.player
                var item = fixture.cart
                CartTransition.end(player)
                player.protection = 1
                var square = allocate(IsoGridSquare::class.java)
                value(square, "worldObjects", java.util.ArrayList(listOf(fixture.world)))
                required(fixture.world).square = square
                player.square = square
                chunk.squares[0][4 * 8 + 2] = square
                check(
                    cell.getGridSquare(10, 20, 2) === square,
                    "native remote pickup lookup fixture did not resolve the exact square",
                )
                val nativeAction = allocate(BaseAction::class.java)
                nativeAction.chr = player
                val ai = allocate(zombie.characters.NetworkPlayerAI::class.java)
                ai.setAction(nativeAction)
                ai.setOverride(true, "WheelbarrowWood", "")
                player.performing = true
                player.performingAction = "ToolkitWoodCart"
                val pose =
                    CartActionSync.Pose(
                        item.getID(),
                        20,
                        1,
                        1,
                        0.4f,
                        0f,
                        10.25f,
                        20.75f,
                        2.00175f,
                        0f,
                        0f,
                        0f,
                        0.85f,
                    )
                try {
                    check(
                        CartTransition.remote(player, pose, 0.4f),
                        "remote pickup setup refused: " + gate,
                    )
                    if (gate.equals("facing")) remotePickupFacing(player, ai, pose)
                    val current = state(player)
                    value(current, "rendered", true)
                    value(current, "nativeRotation", Quaternionf())
                    value(current, "referenceRotation", Quaternionf())
                    // Native exit can arrive before the recovery aggregate and removes pickup's
                    // only hand model.

                    ai.setOverride(false, "", "")
                    player.performing = false
                    player.performingAction = ""
                    check(
                        CartTransition.remote(player, pose, 0.4f),
                        "native stop before recovery snapshot lost the rendered pickup",
                    )
                    val lease: String? = player.overridePrimaryHandModel
                    val slot = zombie.core.skinnedmodel.model.ModelSlotRenderData()
                    slot.character = player
                    check(
                        !CartTransition.render(slot) &&
                            state(player) === current &&
                            player.overridePrimaryHandModel === lease,
                        "empty render slot discarded the queued pickup model binding",
                    )
                    val cancelled =
                        CartActionSync.Pose(
                            item.getID(),
                            20,
                            2,
                            3,
                            0.3f,
                            0.4f,
                            10.25f,
                            20.75f,
                            2.00175f,
                            0f,
                            0f,
                            0f,
                            0.85f,
                        )
                    check(
                        CartTransition.remote(player, cancelled, 0.3f) && state(player) === current,
                        "delayed recovery aggregate could not resume its exact rendered action",
                    )
                    when (gate) {
                        "late-clear" -> {
                            ai.setOverride(false, null, null)
                            check(
                                !CartTransition.render(slot) &&
                                    state(player) === current &&
                                    player.overridePrimaryHandModel === lease,
                                "render-time native clear lost the bounded exact recovery lease",
                            )
                            check(
                                required(value(current, "remoteModelBindStart"))
                                    .equals(value(current, "recoveryStart")),
                                "render-time native clear extended the recovery binding deadline",
                            )
                            value(current, "remoteModelBindStart", System.nanoTime() - 301_000_000L)
                        }
                        "delayed",
                        "facing" -> {
                            check(
                                !CartTransition.render(slot) && state(player) === current,
                                "recovery snapshot ended the initial bind grace",
                            )
                            check(
                                required(value(current, "remoteModelBindStart"))
                                    .equals(value(current, "pendingStart")),
                                "repeated recovery aggregate extended the initial bind deadline",
                            )
                            value(current, "remoteModelBindStart", System.nanoTime() - 301_000_000L)
                        }
                        "timeout" ->
                            value(current, "remoteModelBindStart", System.nanoTime() - 301_000_000L)
                        "replacement" -> item.world = null
                        "foreign-lease" ->
                            player.overridePrimaryHandModel = String(required(lease).toCharArray())
                        "new-action" -> {
                            player.performing = true
                            player.performingAction = "OtherAction"
                        }
                        "unnamed-only" -> {
                            val unrelated = zombie.core.skinnedmodel.model.ModelInstanceRenderData()
                            unrelated.modelInstance = zombie.core.skinnedmodel.model.ModelInstance()
                            unrelated.modelInstance.modelScript =
                                zombie.scripting.objects.ModelScript()
                            check(
                                unrelated.modelInstance.modelScript.getName() == null,
                                "unnamed model fixture acquired a name",
                            )
                            slot.modelData.add(unrelated)
                            check(
                                !CartTransition.render(slot) && state(player) === current,
                                "unnamed entry counted as the missing cart model or ended bind grace",
                            )
                            value(current, "remoteModelBindStart", System.nanoTime() - 301_000_000L)
                        }
                        "failed-solve",
                        "missing-script",
                        "unnamed-script",
                        "unrelated-script" -> {
                            if (gate != "failed-solve") {
                                val unrelated =
                                    zombie.core.skinnedmodel.model.ModelInstanceRenderData()
                                unrelated.modelInstance =
                                    zombie.core.skinnedmodel.model.ModelInstance()
                                unrelated.modelInstance.modelScript =
                                    if (gate == "missing-script") null
                                    else
                                        zombie.scripting.objects.ModelScript().also {
                                            if (gate == "unrelated-script") it.name = "OtherModel"
                                        }
                                slot.modelData.add(unrelated)
                            }
                            var data = zombie.core.skinnedmodel.model.ModelInstanceRenderData()
                            data.modelInstance = zombie.core.skinnedmodel.model.ModelInstance()
                            data.modelInstance.modelScript =
                                zombie.scripting.ScriptManager.instance.getModelScript(
                                    "Base.WheelbarrowWood",
                                )
                            slot.modelData.add(data)
                        }
                    }
                    check(
                        !CartTransition.render(slot) && state(player) == null,
                        "bind grace retained an invalid or expired recovery: " + gate,
                    )
                    check(
                        if ("foreign-lease".equals(gate))
                            player.overridePrimaryHandModel !== lease &&
                                player.overridePrimaryHandModel.equals(lease)
                        else player.overridePrimaryHandModel == null,
                        "bind cleanup changed another model lease: " + gate,
                    )
                    check(
                        player.handWrites == 0 &&
                            player.primary == null &&
                            player.secondary == null &&
                            required(fixture.world).item === item &&
                            item.container == null,
                        "remote model binding changed native ownership: " + gate,
                    )
                } finally {
                    CartTransition.endRemote(player)
                }
            }
            val local = recovery(true)
            try {
                check(
                    CartTransition.cancel(local.player, local.cart, true, null),
                    "local missing-model setup refused",
                )
                val slot = zombie.core.skinnedmodel.model.ModelSlotRenderData()
                slot.character = local.player
                check(
                    !CartTransition.render(slot) && state(local.player) == null,
                    "remote bind grace changed local missing-model failure",
                )
            } finally {
                CartTransition.end(local.player)
            }
        } finally {
            zombie.network.GameClient.client = previousClient
            zombie.iso.IsoWorld.instance.currentCell = previousCell
            IsoPlayer.numPlayers = previousPlayers
            modelField.set(zombie.core.skinnedmodel.ModelManager.instance, previousModel)
        }
    }

    private fun localPickupPerformReceipt() {
        val oldPlatform = LuaManager.platform
        val oldEnv = LuaManager.env
        val oldThread = LuaManager.thread
        val oldCaller = LuaManager.caller
        val oldClient: Boolean = zombie.network.GameClient.client
        val oldConnected: Boolean = zombie.network.GameClient.instance.connected
        val oldConnection = zombie.network.GameClient.connection
        var field = CartTransition::class.java.getDeclaredField("pickupHandoffs")
        field.setAccessible(true)
        val handoffs = (field.get(null) as MutableMap<IsoPlayer, Any?>)
        try {
            LuaManager.platform = se.krka.kahlua.j2se.J2SEPlatform()
            LuaManager.env = LuaManager.platform.newTable()
            LuaManager.thread = se.krka.kahlua.vm.KahluaThread(LuaManager.platform, LuaManager.env)
            LuaManager.thread.debugOwnerThread = Thread.currentThread()
            LuaManager.caller =
                se.krka.kahlua.integration.LuaCaller(
                    se.krka.kahlua.converter.KahluaConverterManager(),
                )
            val toolkit = LuaManager.platform.newTable()
            val lifecycle = LuaManager.platform.newTable()
            lifecycle.rawset(
                "begin",
                se.krka.kahlua.vm.JavaFunction { frame, count ->
                    frame.push(true)
                    return@JavaFunction 1
                },
            )
            lifecycle.rawset(
                "finish",
                se.krka.kahlua.vm.JavaFunction { frame, count ->
                    return@JavaFunction 0
                },
            )
            toolkit.rawset("ActionQueueLifecycle", lifecycle)
            LuaManager.env.rawset("PZSurvivorToolkit", toolkit)
            var connection = allocate(zombie.core.raknet.UdpConnection::class.java)
            zombie.network.GameClient.connection = connection
            zombie.network.GameClient.instance.connected = true
            for (variant in
                arrayOf(
                    "original",
                    "clone",
                    "failed",
                    "no-hooks",
                    "queue-declined",
                    "queue-declined-failed",
                    "queue-declined-wrong-action",
                    "no-receipt",
                    "wrong-action",
                    "stale",
                    "later-original",
                    "later-partial-original",
                    "later-clone-without-receipt",
                    "replacement",
                    "retired-stack",
                    "foreign-force-null",
                    "foreign-primary",
                    "foreign-secondary",
                    "foreign-action",
                    "foreign-replacement-action",
                    "hide-right",
                )) {
                zombie.network.GameClient.client = false
                val fixture = recovery(true)
                var player = fixture.player
                val source = fixture.cart
                zombie.network.GameClient.client = true
                source.setID(76123)
                var action = pendingAction(player, source, "ToolkitWoodCartPickup")
                action.maxTime = 100
                action.waitForFinished = true
                value(action, "useCustomRemoteTimedActionSync", true)
                action.loopAction = true
                action.forceComplete()
                check(
                    !action.finished() && action.forceComplete,
                    "forceComplete fixture unexpectedly met finished() predicate",
                )
                player.getCharacterActions().add(action)
                player.performing = true
                player.performingAction = "ToolkitWoodCart"
                declared(
                    action,
                    BaseAction::class.java,
                    "animVariables",
                    java.util.ArrayList<Any?>(),
                )
                zombie.ai.states.PlayerActionsState.instance().enter(player)
                check(
                    player.isHideWeaponModel(),
                    "native local action did not acquire its normal hidden-weapon state",
                )
                var state = state(player)
                value(state, "actionOwner", action)
                value(state, "connection", connection)
                value(state, "updated", System.nanoTime())
                value(state, "lastRender", System.nanoTime())
                val held =
                    if (
                        variant.equals("original") ||
                            variant.equals("later-original") ||
                            variant.equals("later-partial-original")
                    )
                        source
                    else allocate(Cart::class.java)
                held.kind = source.kind
                held.model = source.model
                held.setID(source.getID())
                val table = action.getTable()
                table.rawset("Type", "ToolkitWoodCartPickup")
                table.rawset(
                    "perform",
                    se.krka.kahlua.vm.JavaFunction { frame, count ->
                        CartTransition.end(player)
                        check(
                            handoffs.containsKey(player),
                            "local finish while performing=true did not remember its exact pickup",
                        )
                        check(
                            !CartTransition.pickupHandoff(player),
                            "local token activated before native perform receipt",
                        )
                        when (variant) {
                            "retired-stack" -> required(player.actions).clear()
                            "foreign-force-null" -> player.forceNullOverride = true
                            "hide-right" -> player.setHideEquippedHandR(true)
                            "foreign-primary" -> player.overridePrimaryHandModel = "Mug"
                            "foreign-secondary" -> player.overrideSecondaryHandModel = "Mug"
                            "foreign-action" -> player.performingAction = "OtherAction"
                            "foreign-replacement-action" -> {
                                required(player.actions).clear()
                                required(player.actions).add(BaseAction(player))
                            }
                        }
                        if (variant.equals("stale")) {
                            try {
                                value(handoffs.get(player), "deadline", System.nanoTime() - 1)
                            } catch (error: Exception) {
                                throw AssertionError(error)
                            }
                        }
                        if (!variant.startsWith("later-")) {
                            source.world = null
                            held.container = player.inventory
                            player.setPrimaryHandItem(held)
                            player.setSecondaryHandItem(held)
                        }
                        if (variant.equals("failed") || variant.equals("queue-declined-failed"))
                            throw IllegalStateException("expected failed cart perform receipt")
                        return@JavaFunction 0
                    },
                )
                if (variant.equals("no-hooks")) LuaManager.env.rawset("PZSurvivorToolkit", null)
                val finishes = IntArray(1)
                lifecycle.rawset(
                    "begin",
                    se.krka.kahlua.vm.JavaFunction { frame, count ->
                        frame.push(!variant.startsWith("queue-declined"))
                        return@JavaFunction 1
                    },
                )
                lifecycle.rawset(
                    "finish",
                    se.krka.kahlua.vm.JavaFunction { frame, count ->
                        finishes[0]++
                        return@JavaFunction 0
                    },
                )
                if (variant.equals("no-receipt")) {
                    CartTransition.end(player)
                    source.world = null
                    held.container = player.inventory
                    player.setPrimaryHandItem(held)
                    player.setSecondaryHandItem(held)
                } else if (
                    variant.equals("wrong-action") || variant.equals("queue-declined-wrong-action")
                ) {
                    val other = pendingAction(player, source, "OtherAction")
                    other.loopAction = true
                    value(other, "useCustomRemoteTimedActionSync", true)
                    other.getTable().rawset("perform", table.rawget("perform"))
                    other.perform()
                } else action.perform()
                LuaManager.env.rawset("PZSurvivorToolkit", toolkit)
                if (variant.startsWith("later-")) {
                    source.world = null
                    held.container = player.inventory
                    player.setPrimaryHandItem(held)
                    if (variant.equals("later-partial-original"))
                        check(
                            !CartTransition.pickupHandoff(player),
                            "partial delayed SP ownership activated/discarded token",
                        )
                    player.setSecondaryHandItem(held)
                }
                val accepted: Boolean = CartTransition.pickupHandoff(player)
                var expected: Boolean =
                    variant.equals("original") ||
                        variant.equals("clone") ||
                        variant.equals("later-original") ||
                        variant.equals("later-partial-original") ||
                        variant.equals("replacement") ||
                        variant.equals("retired-stack") ||
                        variant.equals("no-hooks") ||
                        variant.equals("queue-declined")
                check(
                    accepted == expected,
                    "native false-finished perform proof failed: " + variant,
                )
                if (variant.equals("no-hooks") || variant.startsWith("queue-declined"))
                    check(
                        finishes[0] == 0,
                        "observer-only cart callback notified Lua queue finish: " + variant,
                    )
                val completionScope = ActionCompletion::class.java.getDeclaredField("current")
                completionScope.setAccessible(true)
                check(
                    ((completionScope.get(null) as ThreadLocal<*>)).get() == null,
                    "cart observer-only completion scope leaked: " + variant,
                )
                check(
                    !action.finished() &&
                        action.forceComplete &&
                        action.waitForFinished &&
                        action.currentTime == 0f,
                    "presentation proof modified native completion flags/time: " + variant,
                )
                check(
                    player.handWrites == 2,
                    "bridge added hand writes beyond authoritative callback: " + variant,
                )
                if (variant.equals("replacement")) {
                    var replacement = allocate(Cart::class.java)
                    replacement.kind = held.kind
                    replacement.model = held.model
                    replacement.setID(held.getID())
                    replacement.container = player.inventory
                    player.secondary = replacement
                    player.primary = player.secondary
                    check(
                        !CartTransition.pickupHandoff(player),
                        "same-ID setter replaced a native-perform-pinned instance",
                    )
                }
                CartTransition.end(player)
            }
        } finally {
            CartTransition.end(null)
            zombie.network.GameClient.client = oldClient
            zombie.network.GameClient.connection = oldConnection
            zombie.network.GameClient.instance.connected = oldConnected
            LuaManager.platform = oldPlatform
            LuaManager.env = oldEnv
            LuaManager.thread = oldThread
            LuaManager.caller = oldCaller
        }
    }

    private fun declared(targetObject: Any?, type: Class<*>, name: String, value: Any?) {
        val f = type.getDeclaredField(name)
        f.setAccessible(true)
        f.set(targetObject, value)
    }

    private fun nativeCartEnter(player: Player): BaseAction {
        val component = allocate(NativeRemoteComponent::class.java)
        component.player = player
        player.nativeNetworkComponent = component
        var variables = zombie.network.fields.Variables()
        variables.get().put("PerformingAction", "ToolkitWoodCart")
        zombie.ai.states.PlayerActionsState.SITONGROUND.set(player, false)
        zombie.ai.states.PlayerActionsState.VARIABLES.set(player, variables)
        zombie.ai.states.PlayerActionsState.PRIMARY.set(player, "WheelbarrowWood")
        zombie.ai.states.PlayerActionsState.SECONDARY.set(player, "")
        zombie.ai.states.PlayerActionsState.OVERRIDE.set(player, true)
        zombie.ai.states.PlayerActionsState.instance().enter(player)
        check(
            player.isHideWeaponModel() && player.forceNullOverride && player.performing,
            "native remote action did not acquire its expected hidden-weapon/override lease",
        )
        return required(required(player.network).getAction())
    }

    @Suppress("UNCHECKED_CAST")
    private fun parseNativeEquip(
        player: Player,
        serialized: InventoryItem,
        connection: zombie.core.raknet.UdpConnection,
        incomplete: Boolean,
    ) {
        val bytes = java.nio.ByteBuffer.allocate(8192)
        val writer = zombie.core.network.ByteBufferWriter(bytes)
        writer.putShort(player.getOnlineID())
        writer.putByte(-1)
        val status: Class<out Enum<*>> =
            (Class.forName("zombie.network.packets.EquipPacket\$HandStatus") as Class<out Enum<*>>)
        writeEnum(writer, java.lang.Enum.valueOf(status, "ItemExist"))
        serialized.saveWithSize(bytes, false)
        writer.putByte(0)
        writeEnum(writer, java.lang.Enum.valueOf(status, "SameItemAsPrimary"))
        if (incomplete) writer.putByte(99)
        bytes.flip()
        val reader = zombie.core.network.ByteBufferReader(bytes)
        zombie.network.packets.EquipPacket().parse(reader, connection)
    }

    @Suppress("UNCHECKED_CAST")
    private fun nativePickupEquipReceipt() {
        zombie.ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"))
        zombie.ZomboidFileSystem.instance.init()
        val previousConnection = zombie.network.GameClient.connection
        val previousClient: Boolean = zombie.network.GameClient.client
        val previousConnected: Boolean = zombie.network.GameClient.instance.connected
        val dictionary = zombie.world.WorldDictionary::class.java.getDeclaredField("data")
        dictionary.setAccessible(true)
        val originalDictionary = dictionary.get(null)
        var data = originalDictionary
        if (data == null) {
            val constructor = zombie.world.DictionaryData::class.java.getDeclaredConstructor()
            constructor.setAccessible(true)
            data = constructor.newInstance()
            dictionary.set(null, data)
        }
        val ids = zombie.world.DictionaryData::class.java.getDeclaredField("itemIdToInfoMap")
        ids.setAccessible(true)
        val registry = (ids.get(data) as MutableMap<Short, zombie.world.ItemInfo>)
        val registryId: Short = 32000
        val info = zombie.world.ItemInfo()
        declared(
            info,
            zombie.world.DictionaryInfo::class.java,
            "fullType",
            "SaucedWheelbarrow.WheelbarrowWood",
        )
        declared(info, zombie.world.DictionaryInfo::class.java, "isLoaded", true)
        val oldInfo = registry.put(registryId, info)
        val manager = zombie.scripting.ScriptManager.instance
        var module = manager.moduleMap.get("SaucedWheelbarrow")
        if (module == null) {
            module = zombie.scripting.objects.ScriptModule()
            module.name = "SaucedWheelbarrow"
            manager.moduleMap.put(module.name, module)
            manager.moduleList.add(module)
        }
        val loadMod =
            zombie.scripting.ScriptManager::class.java.getDeclaredField("currentLoadFileMod")
        loadMod.setAccessible(true)
        val previousLoadMod = loadMod.get(null)
        loadMod.set(null, "pz-vanilla")
        zombie.world.WorldDictionary.StartScriptLoading()
        val script = zombie.scripting.objects.Item()
        script.setModule(module)
        script.InitLoadPP("WheelbarrowWood")
        script.Load(
            "WheelbarrowWood",
            "item WheelbarrowWood { ItemType = base:container, DisplayName = Cart, Icon = ToolkitHandoffMissingIcon, Capacity = 10, StaticModel = WheelbarrowWood, }",
        )
        val oldScript = module.items.getScriptMap().put("WheelbarrowWood", script)
        script.setRegistry_id(registryId)
        val serialized = script.InstanceItem(null, false)
        check(
            serialized is zombie.inventory.types.InventoryContainer,
            "native packet fixture did not create a real container",
        )
        serialized.getModData().rawset("nativeCargoMarker", 42.0)
        serialized.setStaticModel("WheelbarrowWood")
        var connection = allocate(zombie.core.raknet.UdpConnection::class.java)
        try {
            for (gate in
                arrayOf(
                    "active",
                    "native-replaced",
                    "native-replaced-world-cleared",
                    "retired",
                    "incomplete",
                    "foreign-primary",
                    "foreign-secondary",
                    "foreign-forced-null",
                    "foreign-action",
                    "foreign-native-action",
                    "replacement",
                    "alternate-model-before",
                    "other-actor-before",
                    "repeat-complete",
                    "repeat-incomplete",
                    "repeat-id",
                    "repeat-model",
                    "repeat-connection",
                    "repeat-actor",
                    "repeat-expired",
                    "repeat-action",
                    "repeat-pointer",
                )) {
                val incomplete: Boolean = gate.equals("incomplete")
                zombie.network.GameClient.client = false
                val fixture = recovery(true)
                var player = fixture.player
                val source = fixture.cart
                zombie.network.GameClient.client = true
                zombie.network.GameClient.connection = connection
                zombie.network.GameClient.instance.connected = true
                player.protection = 1
                source.setID(192837)
                var state = state(player)
                var action = allocate(BaseAction::class.java)
                action.chr = player
                val ai = allocate(zombie.characters.NetworkPlayerAI::class.java)
                ai.setAction(action)
                player.network = ai
                value(state, "remote", true)
                value(state, "actionOwner", action)
                value(state, "connection", connection)
                value(state, "updated", System.nanoTime())
                value(state, "lastRender", System.nanoTime())
                zombie.network.GameClient.IDToPlayerMap.put(player.getOnlineID(), player)
                action = nativeCartEnter(player)
                value(state, "actionOwner", action)
                if (gate.startsWith("native-replaced")) {
                    var replacement = nativeCartEnter(player)
                    check(
                        replacement !== action && replacement.chr === player,
                        "native Stage.Enter did not rebuild BaseAction",
                    )
                    if (gate.equals("native-replaced-world-cleared")) source.world = null
                } else if (gate.equals("alternate-model-before")) ai.setOverride(true, "Mug", "")
                else if (gate.equals("other-actor-before")) {
                    var foreign = allocate(BaseAction::class.java)
                    foreign.chr = allocate(Player::class.java)
                    ai.setAction(foreign)
                }
                // The action-ended aggregate may precede native equipment. Keep its token

                // while a draw observes primary assignment before secondary parsing.

                CartTransition.endRemote(player)
                player.receiptInterleave = true
                when (gate) {
                    "retired" -> ai.setOverride(true, "", "")
                    "foreign-primary" -> ai.setOverride(true, "Mug", "")
                    "foreign-secondary" -> ai.setOverride(true, "WheelbarrowWood", "Mug")
                    "foreign-forced-null" -> {
                        ai.setOverride(true, "", "")
                        player.performing = false
                    }
                    "foreign-action" -> player.performingAction = "OtherAction"
                    "foreign-native-action" -> {
                        val other = allocate(BaseAction::class.java)
                        other.chr = player
                        ai.setAction(other)
                    }
                }
                CartTransition.prunePickupHandoffs()
                serialized.setID(source.getID())
                serialized.setStaticModel("WheelbarrowWood")
                val registryField = InventoryItem::class.java.getDeclaredField("registryId")
                registryField.setAccessible(true)
                registryField.setShort(serialized, registryId)
                parseNativeEquip(player, serialized, connection, incomplete)
                val received = player.primary
                check(
                    received is zombie.inventory.types.InventoryContainer &&
                        received !== source &&
                        received.getID() == source.getID() &&
                        player.secondary === received &&
                        received.getContainer() === player.inventory,
                    "native full packet did not deserialize/bind exact new remote cart",
                )
                check(
                    java.lang.Double.valueOf(42.0)
                        .equals(required(received).getModData().rawget("nativeCargoMarker")),
                    "native packet lost its item payload",
                )
                CartTransition.endRemote(player)
                var expected: Boolean =
                    gate.equals("active") ||
                        gate.startsWith("native-replaced") ||
                        gate.equals("retired") ||
                        gate.equals("replacement") ||
                        gate.startsWith("repeat-")
                check(
                    CartTransition.pickupHandoff(player) == expected,
                    "woven native lease/full packet receipt guard failed: " + gate,
                )
                var nativeWrites: Int = 2
                if (gate.startsWith("repeat-")) {
                    val tokensField = CartTransition::class.java.getDeclaredField("pickupHandoffs")
                    tokensField.setAccessible(true)
                    val tokens = (tokensField.get(null) as MutableMap<IsoPlayer, Any?>)
                    val token = tokens.get(player)
                    var deadline: Long = (value(token, "deadline") as Long)
                    // Native parse completes on the game update thread before its next slot render.

                    // The first unbound primary/secondary interleave was checked above.

                    player.receiptInterleave = false
                    var target = player
                    var peer = connection
                    when (gate) {
                        "repeat-id" -> serialized.setID(source.getID() + 1)
                        "repeat-model" -> serialized.setStaticModel("Mug")
                        "repeat-connection" ->
                            peer = allocate(zombie.core.raknet.UdpConnection::class.java)
                        "repeat-actor" -> {
                            target = allocate(Player::class.java)
                            target.onlineID = 1
                            target.protection = 1
                            target.inventory = allocate(ItemContainer::class.java)
                            zombie.network.GameClient.IDToPlayerMap.put(
                                target.getOnlineID(),
                                target,
                            )
                        }
                        "repeat-expired" -> {
                            deadline = System.nanoTime() - 1
                            value(token, "deadline", deadline)
                        }
                        "repeat-action" -> player.performingAction = "OtherAction"
                        "repeat-pointer" -> {
                            val other = allocate(BaseAction::class.java)
                            other.chr = player
                            ai.setAction(other)
                        }
                    }
                    parseNativeEquip(target, serialized, peer, gate.equals("repeat-incomplete"))
                    if (target === player) nativeWrites += 2
                    check(
                        (value(token, "deadline") as Long) == deadline,
                        "repeated complete native receipt extended original deadline",
                    )
                    expected = gate.equals("repeat-complete") || gate.equals("repeat-actor")
                    if (gate.equals("repeat-complete")) {
                        check(
                            player.primary !== received &&
                                player.primary !== source &&
                                player.secondary === player.primary &&
                                required(player.primary).getID() == source.getID() &&
                                required(player.primary).getContainer() === player.inventory,
                            "second native complete packet did not supply a distinct exact held clone",
                        )
                        check(
                            tokens.get(player) === token && value(token, "held") === player.primary,
                            "complete native receipt did not repin the same token to the exact new instance",
                        )
                        check(
                            java.lang.Double.valueOf(42.0)
                                .equals(
                                    required(player.primary)
                                        .getModData()
                                        .rawget("nativeCargoMarker"),
                                ),
                            "repeated native clone lost cargo payload",
                        )
                    } else if (
                        gate.equals("repeat-incomplete") || gate.equals("repeat-connection")
                    ) {
                        check(
                            value(token, "held") === received && player.primary !== received,
                            "unproven repeated packet repinned its clone",
                        )
                    } else if (gate.equals("repeat-actor")) {
                        check(
                            value(token, "held") === received && player.primary === received,
                            "other actor's native receipt changed the pinned instance",
                        )
                        zombie.network.GameClient.IDToPlayerMap.remove(target.getOnlineID(), target)
                    }
                    check(
                        CartTransition.pickupHandoff(player) == expected,
                        "repeated native receipt guard failed: " + gate,
                    )
                }
                if (expected) {
                    ai.setOverride(false, null, null)
                    player.performing = false
                    player.performingAction = ""
                    CartTransition.prunePickupHandoffs()
                    check(
                        CartTransition.pickupHandoff(player),
                        "native action exit discarded exact received cart: " + gate,
                    )
                    if (gate.equals("replacement")) {
                        var replacement = allocate(Cart::class.java)
                        replacement.kind = source.kind
                        replacement.model = source.model
                        replacement.setID(source.getID())
                        replacement.container = player.inventory
                        player.secondary = replacement
                        player.primary = player.secondary
                        check(
                            !CartTransition.pickupHandoff(player),
                            "same-ID replacement inherited a native equip receipt",
                        )
                    }
                }
                check(
                    player.handWrites == nativeWrites,
                    "bridge added authoritative hand writes beyond native packet",
                )
                check(
                    source.world ===
                        (if (gate.equals("native-replaced-world-cleared")) null
                        else fixture.world) &&
                        required(fixture.world).item === source &&
                        source.container == null &&
                        java.lang.Double.valueOf(42.0)
                            .equals(required(received).getModData().rawget("nativeCargoMarker")),
                    "render receipt changed source/cargo ownership",
                )
                CartTransition.end(player)
                zombie.network.GameClient.IDToPlayerMap.remove(player.getOnlineID(), player)
            }
        } finally {
            if (oldInfo == null) registry.remove(registryId) else registry.put(registryId, oldInfo)
            dictionary.set(null, originalDictionary)
            loadMod.set(null, previousLoadMod)
            if (oldScript == null) module.items.getScriptMap().remove("WheelbarrowWood")
            else module.items.getScriptMap().put("WheelbarrowWood", oldScript)
            CartTransition.end(null)
            zombie.network.GameClient.client = previousClient
            zombie.network.GameClient.connection = previousConnection
            zombie.network.GameClient.instance.connected = previousConnected
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun pickupCompletionHandoff() {
        val previousClient: Boolean = zombie.network.GameClient.client
        val previousConnection = zombie.network.GameClient.connection
        val previousConnected: Boolean = zombie.network.GameClient.instance.connected
        var connection = allocate(zombie.core.raknet.UdpConnection::class.java)
        val map = CartTransition::class.java.getDeclaredField("pickupHandoffs")
        map.setAccessible(true)
        val handoffs = (map.get(null) as MutableMap<IsoPlayer, Any?>)
        try {
            zombie.network.GameClient.client = true
            zombie.network.GameClient.connection = connection
            zombie.network.GameClient.instance.connected = true
            for (remote in booleanArrayOf(false, true)) for (gate in
                arrayOf(
                    "valid",
                    "same-id-replacement",
                    "foreign-action",
                    "foreign-override",
                    "unsafe",
                    "npc",
                    "sneak",
                    "injury",
                    "foreign-stack",
                    "stale",
                    "connection",
                    "disconnect",
                    "new-generation",
                    "expired",
                    "unreceipted",
                    "receipt-repeat",
                    "empty-updates",
                    "reset",
                    "prune",
                    "old-render",
                    "render-249ms",
                    "old-update",
                    "no-render",
                    "cancelled",
                    "other-native-action",
                )) {
                zombie.network.GameClient.client = false
                val fixture = recovery(true)
                var player = fixture.player
                var item = fixture.cart
                zombie.network.GameClient.client = true
                val current = state(player)
                var action = allocate(BaseAction::class.java)
                action.chr = player
                value(current, "actionOwner", action)
                value(current, "connection", connection)
                value(current, "lastRender", System.nanoTime())
                value(current, "updated", System.nanoTime())
                value(current, "remote", remote)
                player.protection = if (remote) 1 else 0
                val ai = allocate(zombie.characters.NetworkPlayerAI::class.java)
                ai.setAction(action)
                player.network = ai
                zombie.network.GameClient.IDToPlayerMap.put(player.getOnlineID(), player)
                when (gate) {
                    "old-render" -> value(current, "lastRender", System.nanoTime() - 301_000_000L)
                    "render-249ms" -> value(current, "lastRender", System.nanoTime() - 249_000_000L)
                    "old-update" -> value(current, "updated", System.nanoTime() - 301_000_000L)
                    "no-render" -> value(current, "rendered", false)
                    "cancelled" -> value(current, "recovering", true)
                }
                var nativeHeld = item
                if (remote) {
                    nativeHeld = allocate(Cart::class.java)
                    nativeHeld.kind = item.kind
                    nativeHeld.model = item.model
                    nativeHeld.setID(item.getID())
                    nativeHeld.container = player.inventory
                    player.secondary = nativeHeld
                    player.primary = player.secondary
                    if (!gate.equals("unreceipted"))
                        CartTransition.pickupEquipped(player, connection)
                } else {
                    item.world = null
                    item.container = player.inventory
                    player.secondary = item
                    player.primary = player.secondary
                }
                CartTransition.end(player)
                val token = handoffs.get(player)
                if (
                    gate.equals("old-render") ||
                        gate.equals("old-update") ||
                        gate.equals("no-render") ||
                        gate.equals("cancelled")
                ) {
                    check(
                        token == null && !CartTransition.pickupHandoff(player),
                        "stale/unrendered/cancelled pickup created completion bridge: " + gate,
                    )
                    CartTransition.end(player)
                    zombie.network.GameClient.IDToPlayerMap.remove(player.getOnlineID(), player)
                    continue
                }
                check(token != null, "fresh pickup did not create a bounded completion candidate")
                if (!remote) {
                    value(token, "performed", true)
                    value(token, "held", item)
                }
                var deadline: Long = (value(token, "deadline") as Long)
                when (gate) {
                    "same-id-replacement" -> {
                        var replacement = allocate(Cart::class.java)
                        replacement.kind = item.kind
                        replacement.model = item.model
                        replacement.setID(item.getID())
                        replacement.container = player.inventory
                        player.secondary = replacement
                        player.primary = player.secondary
                    }
                    "foreign-action" -> {
                        player.performing = true
                        player.performingAction = "OtherAction"
                    }
                    "other-native-action" -> {
                        if (remote) ai.setAction(allocate(BaseAction::class.java))
                        else player.getCharacterActions().add(allocate(BaseAction::class.java))
                    }
                    "foreign-override" -> player.overridePrimaryHandModel = "Mug"
                    "unsafe" -> player.protection = 4
                    "npc" -> player.protection = 11
                    "sneak" -> player.protection = 12
                    "injury" -> player.setVariable("WalkInjury", 0.15f)
                    "foreign-stack" ->
                        player.getCharacterActions().add(allocate(BaseAction::class.java))
                    "reset" -> CartTransition.end(player)
                    "prune" -> {
                        value(token, "deadline", System.nanoTime() - 1)
                        CartTransition.prunePickupHandoffs()
                        check(
                            !handoffs.containsKey(player),
                            "offscreen token survived animation cleanup",
                        )
                    }
                    "empty-updates" -> {
                        for (i in 0 until 3) CartTransition.endRemote(player)
                        check(
                            handoffs.get(player) === token,
                            "empty action update discarded fresh completion token",
                        )
                    }
                    "stale",
                    "expired" -> value(token, "deadline", System.nanoTime() - 1)
                    "connection" ->
                        zombie.network.GameClient.connection =
                            allocate(zombie.core.raknet.UdpConnection::class.java)
                    "disconnect" -> zombie.network.GameClient.instance.connected = false
                    "new-generation" -> {
                        // A new exact action must not inherit a completed action's receipt or
                        // timer.

                        zombie.network.GameClient.client = false
                        val next = recovery(true)
                        zombie.network.GameClient.client = true
                        value(current, "action", (value(current, "action") as Long) + 1)
                        val statesField = CartTransition::class.java.getDeclaredField("states")
                        statesField.setAccessible(true)
                        ((statesField.get(null) as MutableMap<IsoPlayer, Any?>)).put(
                            player,
                            state(next.player),
                        )
                        CartTransition.end(next.player)
                    }
                    "receipt-repeat" -> {
                        CartTransition.pickupEquipped(player, connection)
                        check(
                            (value(token, "deadline") as Long) == deadline,
                            "repeated receipt extended completion deadline",
                        )
                    }
                }
                val accepted: Boolean = CartTransition.pickupHandoff(player)
                var expected: Boolean =
                    gate.equals("valid") ||
                        gate.equals("receipt-repeat") ||
                        gate.equals("empty-updates") ||
                        gate.equals("render-249ms") ||
                        !remote && gate.equals("unreceipted")
                check(
                    accepted == expected,
                    "completion bridge guard failed: " + remote + "/" + gate,
                )
                if (accepted) {
                    check(
                        !CartMotionSync.visualEnabled(player),
                        "completion bridge enabled ordinary motion",
                    )
                    check(
                        player.primary === nativeHeld &&
                            player.secondary === nativeHeld &&
                            nativeHeld.container === player.inventory,
                        "completion bridge changed exact native hands/inventory",
                    )
                    check(
                        player.handWrites == 0 && player.modelResets == 0,
                        "completion bridge mutated native hand models",
                    )
                    check(
                        (value(token, "deadline") as Long) == deadline,
                        "render polling renewed completion bridge",
                    )
                } else {
                    check(
                        !CartTransition.pickupHandoff(player),
                        "invalid completion token resurrected",
                    )
                }
                zombie.network.GameClient.connection = connection
                zombie.network.GameClient.instance.connected = true
                CartTransition.end(player)
                zombie.network.GameClient.IDToPlayerMap.remove(player.getOnlineID(), player)
            }
        } finally {
            CartTransition.end(null)
            zombie.network.GameClient.client = previousClient
            zombie.network.GameClient.connection = previousConnection
            zombie.network.GameClient.instance.connected = previousConnected
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        var field: Field = Unsafe::class.java.getDeclaredField("theUnsafe")
        field.setAccessible(true)
        unsafe = field.get(null) as Unsafe
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            CartTransitionTest::class.java.classLoader,
        )
        check(Main.CART_SUPPORTED, "installed B42.21 bytecode fixture unsupported")
        check(Main.CART_TRANSITION_SUPPORTED, "installed transition render bytecode unsupported")
        for (name in
            arrayOf(
                "wooden",
                "hidden",
                "place",
                "suppressHeldModel",
                "pickupEquipped",
                "pickupPerformed",
                "prunePickupHandoffs",
            )) {
            var exported: Boolean = false
            for (method in CartTransition::class.java.getDeclaredMethods()) if (
                name.equals(method.getName())
            )
                exported = java.lang.reflect.Modifier.isPublic(method.getModifiers())
            check(exported, "inlined native advice cannot call a package-private helper: " + name)
        }
        val atlas =
            zombie.core.skinnedmodel.model.WorldItemModelDrawer::class
                .java
                .getDeclaredMethod(
                    "renderAtlasTexture",
                    InventoryItem::class.java,
                    IsoGridSquare::class.java,
                    Float::class.javaPrimitiveType!!,
                    Float::class.javaPrimitiveType!!,
                    Float::class.javaPrimitiveType!!,
                    Float::class.javaPrimitiveType!!,
                    Float::class.javaPrimitiveType!!,
                    Boolean::class.javaPrimitiveType!!,
                )
        atlas.setAccessible(true)
        val cart = allocate(Cart::class.java)
        cart.kind = "SaucedWheelbarrow.WheelbarrowWood"
        check(
            false.equals(atlas.invoke(null, cart, null, 0f, 0f, 0f, 0f, 0f, false)),
            "wooden cart atlas must defer to the same renderer as FBO without accessing a scene",
        )
        bridge()
        geometry()
        metalDropGeometry()
        groundPasses()
        recoveryLifecycle()
        authoredClipDefault()
        authoredClockAndRecovery()
        authoredRestartHandoff()
        authoredRestartRefusals()
        authoredRestartRecancellation()
        authoredPendingHandoff()
        authoredPendingDeadline()
        authoredPendingRefusals()
        authoredNodeRetirement()
        recoveryRefusals()
        recoveryInterruptions()
        collisionInterruptions()
        recoveryLeaseIdentity()
        recoveryModelScope()
        remoteNativeHandModels()
        remotePickupModelBind()
        pickupCompletionHandoff()
        nativePickupEquipReceipt()
        localPickupPerformReceipt()
        println(
            "CART_TRANSITION_PASS (scoped exact-owner validation, native yaw geometry, model/depth/sprite/picker/outline suppression and cleanup)",
        )
    }
}
