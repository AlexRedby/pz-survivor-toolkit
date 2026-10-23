package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field
import java.util.WeakHashMap
import org.joml.Matrix4f
import org.joml.Quaternionf
import org.joml.Vector3f
import se.krka.kahlua.integration.annotations.LuaMethod
import se.krka.kahlua.vm.KahluaTable
import zombie.Lua.LuaManager
import zombie.ai.states.CollideWithWallState
import zombie.characters.IsoPlayer
import zombie.characters.CharacterTimedActions.BaseAction
import zombie.characters.CharacterTimedActions.LuaTimedActionNew
import zombie.core.skinnedmodel.ModelManager
import zombie.core.skinnedmodel.advancedanimation.AnimLayer
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode
import zombie.core.skinnedmodel.model.ModelInstanceRenderData
import zombie.core.skinnedmodel.model.ModelSlotRenderData
import zombie.inventory.InventoryItem
import zombie.iso.IsoGridSquare
import zombie.iso.IsoWorld
import zombie.iso.objects.IsoWorldInventoryObject
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.scripting.ScriptManager

/** Presentation only: inventory/world ownership remains with the native timed action. */
internal object CartTransition {
    private val states = WeakHashMap<IsoPlayer?, State>()
    // Native queue/render cleanup can run before the replacement action's first update.
    private val cancelled = WeakHashMap<IsoPlayer?, State>()
    private val pickupHandoffs = WeakHashMap<IsoPlayer?, PickupHandoff>()
    private const val PICKUP_HANDOFF_NANOS = 300_000_000L
    private class PickupHandoff(state: State, peer: Any?, now: Long) {
        @JvmField val source = state
        @JvmField val connection = peer
        @JvmField val deadline = now + PICKUP_HANDOFF_NANOS
        @JvmField val model = CartGrounding.resolvedModel(state.cart)
        @JvmField var held: InventoryItem? = null
        @JvmField var receipted = false
        @JvmField var performed = false
    }
    private val CLIP_RETIRING = clipRetiringField()
    private const val RESTART_BLEND_NANOS = 350_000_000.0
    // Start behind the handle ends rather than clearing the shafts with a large pelvis-only retreat.
    private const val STANCE_BACK = 0.06f

    // The grounded metal cart must rise with a restarted setdown before the old
    // crouch releases; the previous low hand path is otherwise beyond arm reach.
    @JvmStatic
    fun restartCartWeight(profile: CartWheelbarrow?, pickup: Boolean, bodyWeight: Float): Float =
        if (profile === CartWheelbarrow.METAL && !pickup) bodyWeight * bodyWeight else bodyWeight

    private class State {
        @JvmField var item: InventoryItem? = null
        @JvmField var actionOwner: BaseAction? = null
        @JvmField var connection: Any? = null
        @JvmField var action = 0L
        @JvmField var remote = false
        @JvmField var remoteWaiting = false
        @JvmField var pickup = false
        @JvmField var ik = false
        @JvmField var rendered = false
        @JvmField var recovering = false
        @JvmField var authored = false
        @JvmField var clipRetired = false
        @JvmField var handoffRemembered = false
        @JvmField var cancelledProgress = 0f
        @JvmField var nativeHeight = 0f
        @JvmField var referenceHeight = 0f
        @JvmField var movementProgress = 0f
        @JvmField var recoveryReach = 0f
        @JvmField var recoveryGrip = 0f
        @JvmField var recoveryPose: Array<Matrix4f?>? = null
        @JvmField var recoveryCart: Matrix4f? = null
        @JvmField var movingRecovery = false
        @JvmField var lastPose: Array<Matrix4f?>? = null
        @JvmField var restartPose: Array<Matrix4f?>? = null
        @JvmField var lastPlacement: CartTransitionMath.Placement? = null
        @JvmField var restartPlacement: CartTransitionMath.Placement? = null
        @JvmField var lastReach = 0f
        @JvmField var lastGrip = 0f
        @JvmField var restartReach = 0f
        @JvmField var restartGrip = 0f
        @JvmField var lastRender = 0L
        @JvmField var restartStart = 0L
        @JvmField var pendingStart = 0L
        @JvmField var remoteModelBindStart = 0L
        @JvmField var nativeRotation: Quaternionf? = null
        @JvmField var referenceRotation: Quaternionf? = null
        @JvmField var recoveryStart = 0L
        @JvmField var visualModel: String? = null
        @JvmField var progress = 0f
        @JvmField var updated = 0L
        @JvmField var world: IsoWorldInventoryObject? = null
        @JvmField var cancelSquare: IsoGridSquare? = null
        @JvmField var placement: CartTransitionMath.Placement? = null
    }
    private val State.cart: InventoryItem get() = item ?: throw NullPointerException()
    private val State.ownedWorld: IsoWorldInventoryObject get() = world ?: throw NullPointerException()
    private val State.placed: CartTransitionMath.Placement get() = placement ?: throw NullPointerException()

    @JvmStatic
    fun wooden(item: InventoryItem?): Boolean = item != null && "SaucedWheelbarrow.WheelbarrowWood".equals(item.getFullType())
    @JvmStatic
    fun wheelbarrow(item: InventoryItem?): Boolean = CartWheelbarrow.forItem(item) != null
    @JvmStatic
    fun supported(item: InventoryItem?): Boolean = wheelbarrow(item) || CartShopping.item(item)
    @JvmStatic
    fun worldScale(item: InventoryItem?): Float = (item ?: throw NullPointerException()).worldScale * (if (wheelbarrow(item)) 0.85f else 1f)
    @JvmStatic
    fun heightOffset(item: InventoryItem?): Float = if (wheelbarrow(item)) 0.00175f else 0f
    @JvmStatic
    private fun held(item: InventoryItem?, out: Matrix4f?): Matrix4f? {
        val profile = CartWheelbarrow.forItem(item)
        return if (profile == null) CartShopping.held(out, model(item), (item ?: throw NullPointerException()).worldScale) else profile.held(out)
    }
    @JvmStatic
    private fun modelName(item: InventoryItem?): String? {
        val profile = CartWheelbarrow.forItem(item)
        val script = CartGrounding.resolvedModel(item ?: throw NullPointerException())
        return if (profile != null) profile.model() else script?.getName()
    }
    @JvmStatic
    private fun phase(state: State): CartTransitionMath.Progress? =
        if (CartShopping.item(state.item)) CartShopping.progress(state.progress.toDouble(), !state.pickup)
        else CartTransitionMath.progress(state.progress.toDouble(), !state.pickup)
    @JvmStatic
    private fun blend(item: InventoryItem?, from: Matrix4f?, to: Matrix4f?, model: Matrix4f?, weight: Double, out: Matrix4f?): Boolean =
        if (CartShopping.item(item)) CartTransitionMath.blendModel(from, to, model, weight, out)
        else CartTransitionMath.blend(from, to, weight, out)

    @JvmStatic
    fun model(item: InventoryItem?): Matrix4f? {
        val script = ScriptManager.instance.getModelScript((item ?: throw NullPointerException()).getWorldStaticModel()) ?: return null
        val model = ModelManager.instance.tryGetLoadedModel(script, true)
        if (model == null || model.mesh == null || !model.mesh.isReady()) return null
        val result = Matrix4f()
        val attachment = script.getAttachmentById("world")
        if (attachment != null) ModelInstanceRenderData.makeAttachmentTransform(attachment, result).invert()
        ModelInstanceRenderData.postMultiplyMeshTransform(result, model.mesh)
        result.scale(script.scale)
        CartWorldSupport.apply(item.getFullType(), result, worldScale(item))
        return result
    }
    @JvmStatic
    fun placement(item: InventoryItem?, world: IsoWorldInventoryObject?): CartTransitionMath.Placement =
        CartTransitionMath.Placement((world ?: throw NullPointerException()).getWorldPosX(), world.getWorldPosY(), world.getWorldPosZ() + heightOffset(item),
            (item ?: throw NullPointerException()).getWorldXRotation(), item.getWorldZRotation(), item.getWorldYRotation(), worldScale(item))

    @JvmStatic
    @LuaMethod(name = "toolkitWoodCartStance", global = true)
    fun stance(player: IsoPlayer?, world: IsoWorldInventoryObject?): KahluaTable? {
        if (!Main.CART_TRANSITION_SUPPORTED || world == null || !supported(world.getItem())) return null
        val item = world.getItem()
        val model = model(item)
        val profile = CartWheelbarrow.forItem(item)
        val held = held(item, Matrix4f())
        if (model == null || held == null) return null
        val ground = Matrix4f()
        val pose = placement(item, world)
        val left = Vector3f(); val right = Vector3f()
        CartGrip.handle(modelName(item), true, left); CartGrip.handle(modelName(item), false, right)
        val target = CartTransitionMath.stance(pose, model, held, left, right) ?: return null
        if (!CartTransitionMath.worldToActor(pose, model, target.x, target.y, (player ?: throw NullPointerException()).getZ(), target.slotAngle, ground)) return null
        val axle = if (profile == null) Vector3f() else profile.center(Vector3f())
        val difference = if (profile == null) Vector3f() else ground.transformPosition(axle, Vector3f()).sub(held.transformPosition(axle, Vector3f()))
        if (profile != null) difference.z += profile.pickupStanceBack()
        val c = Math.cos(target.slotAngle.toDouble()).toFloat(); val s = Math.sin(target.slotAngle.toDouble()).toFloat()
        val x = target.x - 1.5f * (c * difference.x + s * difference.z)
        val y = target.y + 1.5f * (-s * difference.x + c * difference.z)
        val result = LuaManager.platform.newTable()
        result.rawset("x", x.toDouble()); result.rawset("y", y.toDouble()); result.rawset("angle", target.slotAngle.toDouble())
        val heading = target.slotAngle - Math.PI / 2
        result.rawset("faceX", player.getX() + Math.cos(heading))
        result.rawset("faceY", player.getY() + Math.sin(heading))
        val animation = player.getAnimationPlayer()
        result.rawset("aligned", animation != null && !player.isTurning()
            && Math.abs(CartSteeringMath.wrap((animation.getRenderedAngle() - target.slotAngle).toDouble())) < Math.toRadians(1.0))
        return result
    }
    @JvmStatic
    @LuaMethod(name = "toolkitWoodCartFace", global = true)
    fun face(player: IsoPlayer?, world: IsoWorldInventoryObject?): Boolean {
        if (player == null) return false
        val target = stance(player, world)
        return target != null && CartPickupApproach.face(player, world, (target.rawget("x") as Number).toFloat(),
            (target.rawget("y") as Number).toFloat(), (target.rawget("angle") as Number).toFloat())
    }
    @JvmStatic
    fun authoredClip(player: IsoPlayer?, retirementSupported: Boolean): Boolean {
        val actor = player ?: throw NullPointerException()
        if (!actor.containsVariable("ToolkitWoodCartClipPilot"))
            actor.setVariable("ToolkitWoodCartClipPilot", retirementSupported && !GameClient.client && !GameServer.server)
        val selected = actor.getVariableBoolean("ToolkitWoodCartClipPilot")
        if (selected && !retirementSupported) throw IllegalStateException("Authored cart clips require native node retirement support")
        return selected
    }
    @JvmStatic
    @Synchronized
    @LuaMethod(name = "toolkitWoodCartUpdate", global = true)
    fun update(player: IsoPlayer?, item: InventoryItem?, pickup: Boolean, progress: Double): Boolean {
        if (!Main.CART_TRANSITION_SUPPORTED || player == null || !player.isLocalPlayer() || !supported(item)
            || !progress.isFinite() || player.isDead()) return false
        var state = states[player]
        if (state == null || state.recovering || state.item !== item || state.pickup != pickup) {
            val previous = cancelled.remove(player)
            end(player); pickupHandoffs.remove(player)
            state = State(); state.item = item; state.pickup = pickup
            state.action = CartActionSync.generation()
            state.authored = authoredClip(player, CLIP_RETIRING != null)
            if (pickup) {
                state.world = (item ?: throw NullPointerException()).getWorldItem()
                if (state.world == null) return false
                state.placement = placement(item, state.world)
            }
            if (state.authored && previous != null && previous.item === item && previous.pickup == pickup
                && previous.lastPose != null && previous.lastPlacement != null
                && System.nanoTime() - previous.lastRender <= 200_000_000L
                && !pendingExpired(previous, System.nanoTime()) && !protectedState(player)
                && (if (pickup) previous.world === state.world && state.ownedWorld.getItem() === item
                    && state.ownedWorld.getSquare() != null && state.ownedWorld.getSquare() === previous.cancelSquare
                    && previous.placed.equals(state.placement)
                    && player.getPrimaryHandItem() == null && player.getSecondaryHandItem() == null
                    else (item ?: throw NullPointerException()).getWorldItem() == null && item.getContainer() === player.getInventory()
                        && player.getPrimaryHandItem() === item && player.getSecondaryHandItem() === item)) {
                state.restartPose = previous.lastPose; state.restartPlacement = previous.lastPlacement
                state.restartReach = previous.lastReach; state.restartGrip = previous.lastGrip
                state.restartStart = System.nanoTime(); state.rendered = previous.rendered
            }
            state.connection = if (GameClient.client) GameClient.connection else null
            state.actionOwner = localPickupAction(player, item)
            states[player] = state
        }
        state.progress = Math.max(0.0, Math.min(1.0, progress)).toFloat(); state.updated = System.nanoTime()
        poseVariables(player, state); publish(player, state)
        return true
    }
    @JvmStatic
    private fun localPickupAction(player: IsoPlayer, item: InventoryItem?): BaseAction? {
        val actions = player.getCharacterActions()
        if (actions.size != 1) return null
        val action = actions[0] as? LuaTimedActionNew ?: return null
        if (action.chr !== player || !"ToolkitWoodCartPickup".equals(action.getMetaType())) return null
        val table = action.getTable()
        if (table == null || table.rawget("character") !== player) return null
        val id = table.rawget("itemId")
        return if (id is Number
            && id.toDouble() == (item ?: throw NullPointerException()).getID().toDouble()) action else null
    }
    @JvmStatic
    private fun poseVariables(player: IsoPlayer, state: State) {
        val phase = phase(state)
        player.setVariable("ToolkitWoodCartPoseX", ((phase ?: throw NullPointerException()).lift + 0.10 * phase.crouch * (1 - phase.lift)).toFloat())
        player.setVariable("ToolkitWoodCartPoseY", phase.lift.toFloat())
        if (state.authored) {
            player.setVariable("ToolkitWoodCartClipTime", state.progress)
            player.setVariable("ToolkitWoodCartClipPickup", state.pickup)
            player.setVariable("ToolkitMetalCartClip", CartWheelbarrow.forItem(state.item) === CartWheelbarrow.METAL)
            player.setVariable("ToolkitShoppingCartClip", CartShopping.item(state.item))
        }
    }
    @JvmStatic
    private fun clipRetiringField(): Field? = try {
        LiveAnimNode::class.java.getDeclaredField("transitioningOut").apply { isAccessible = true }
    } catch (unsupported: ReflectiveOperationException) { null }
      catch (unsupported: RuntimeException) { null }
    @JvmStatic
    fun retireAuthoredNode(node: LiveAnimNode?, pickup: Boolean): Boolean {
        val direction = if (pickup) "Pickup" else "Setdown"
        val name = (node ?: throw NullPointerException()).getSourceNode().name
        if (!("ToolkitWoodCartClip" + direction).equals(name) && !("ToolkitMetalCartClip" + direction).equals(name)
            && !("ToolkitShoppingCartClip" + direction).equals(name)) return false
        try {
            val field = CLIP_RETIRING ?: throw IllegalStateException("Native cart clip retirement unavailable")
            if (field.getBoolean(node)) return false
            // Native selection must create a new clock-bound node while this one fades at its final pose.
            field.setBoolean(node, true)
            for (track in node.getMainAnimationTracks()) { track.trackTimeToVariable = null; track.setSpeedDelta(0f) }
            return true
        } catch (unsupported: IllegalAccessException) { throw IllegalStateException(unsupported) }
    }
    @JvmStatic
    private fun retireAuthoredLayer(layer: AnimLayer?, pickup: Boolean) {
        if (layer != null) for (node in layer.getLiveAnimNodes()) retireAuthoredNode(node, pickup)
    }
    @JvmStatic
    private fun retireAuthored(player: IsoPlayer, state: State) {
        if (!state.authored || state.clipRetired) return
        val animator = player.getAdvancedAnimator()
        if (animator != null) {
            retireAuthoredLayer(animator.getRootLayer(), state.pickup)
            for (i in 0 until animator.getSubLayerCount()) retireAuthoredLayer(animator.getSubLayerAt(i), state.pickup)
        }
        state.clipRetired = true
    }
    @JvmStatic
    private fun protectedState(player: IsoPlayer): Boolean = !player.isLocalPlayer() || unsafeState(player)
    @JvmStatic
    private fun unsafeState(player: IsoPlayer): Boolean = player.isDead() || player.isAiming() || player.hasHitReaction()
        || player.isKnockedDown() || player.isGettingUp() || player.getVehicle() != null
        || player.isCurrentState(CollideWithWallState.instance())
        || player.isGrappling() || player.isBeingGrappled() || player.isRagdollSimulationActive()
    @JvmStatic
    private fun publish(player: IsoPlayer, state: State) {
        if (!state.remote) CartActionSync.publish(player, state.item, state.action, state.pickup, state.recovering,
            state.progress, state.cancelledProgress, state.placement)
    }
    @JvmStatic
    private fun remoteItem(player: IsoPlayer, pose: CartActionSync.Pose): InventoryItem? {
        if (!pose.pickup()) {
            val item = player.getPrimaryHandItem()
            return if (supported(item) && item.getID() == pose.cart && player.getSecondaryHandItem() === item
                && item.getContainer() === player.getInventory() && item.getWorldItem() == null) item else null
        }
        if (player.getPrimaryHandItem() != null || player.getSecondaryHandItem() != null
            || IsoWorld.instance == null || IsoWorld.instance.currentCell == null) return null
        val square = IsoWorld.instance.currentCell.getGridSquare(Math.floor(pose.x.toDouble()).toInt(), Math.floor(pose.y.toDouble()).toInt(), Math.floor(pose.z.toDouble()).toInt()) ?: return null
        for (world in square.getWorldObjects()) {
            val item = world.getItem()
            if (supported(item) && item.getID() == pose.cart && item.getWorldItem() === world
                && Math.abs(world.getWorldPosX() - pose.x) < 0.03 && Math.abs(world.getWorldPosY() - pose.y) < 0.03) return item
        }
        return null
    }
    @JvmStatic
    private fun remoteOwner(player: IsoPlayer, state: State): Boolean {
        if (state.pickup) return state.world != null && state.cart.getWorldItem() === state.world
            && state.ownedWorld.getItem() === state.item && state.ownedWorld.getSquare() != null
            && player.getPrimaryHandItem() == null && player.getSecondaryHandItem() == null
        return state.cart.getWorldItem() == null && state.cart.getContainer() === player.getInventory()
            && player.getPrimaryHandItem() === state.item && player.getSecondaryHandItem() === state.item
    }
    @JvmStatic
    private fun emptyRemoteModel(model: String?): Boolean = model == null || model.isEmpty()

    /** Populate only presentation state; native actions retain hands, items and world ownership. */
    @JvmStatic
    @Synchronized
    fun remote(player: IsoPlayer?, pose: CartActionSync.Pose?, progress: Float): Boolean {
        if (!Main.CART_SYNC_SUPPORTED || !GameClient.client || (player ?: throw NullPointerException()).isLocalPlayer() || unsafeState(player)
            || !(pose ?: throw NullPointerException()).valid() || !pose.nearby(player.getX(), player.getY(), player.getZ())) return false
        val item = remoteItem(player, pose) ?: return false
        var state = states[player]
        val same = state != null && state.remote && state.item === item && state.action == pose.action && state.pickup == pose.pickup()
        val performing = player.getVariableBoolean("IsPerformingAnAction")
        val nativeAction = performing && "ToolkitWoodCart".equals(player.getVariableString("PerformingAction"))
            && CartGrounding.sameModel(item, player.overridePrimaryHandModel) && emptyRemoteModel(player.overrideSecondaryHandModel)
        if (performing && !nativeAction) return false
        if (!nativeAction && !same) return false
        if (!same) {
            endRemote(player); state = State(); state.remote = true; state.item = item; state.action = pose.action; state.pickup = pose.pickup()
            state.world = if (pose.pickup()) item.getWorldItem() else null
            state.connection = GameClient.connection
            val network = player.getNetworkCharacterAI()
            state.actionOwner = if (network == null) null else network.getAction()
            pickupHandoffs.remove(player); states[player] = state
        }
        val current = state ?: throw NullPointerException()
        current.placement = pose.placement()
        val now = System.nanoTime()
        if (!nativeAction) {
            if (!current.recovering) {
                if (!current.rendered || !CartGrip.validPosture(current.nativeHeight, current.nativeRotation)
                    || !CartGrip.validPosture(current.referenceHeight, current.referenceRotation)
                    || !emptyRemoteModel(player.overridePrimaryHandModel) || !emptyRemoteModel(player.overrideSecondaryHandModel)) return false
                current.visualModel = String(item.getStaticModel().toCharArray())
                player.overridePrimaryHandModel = current.visualModel; player.resetEquippedHandsModels()
                current.recovering = true; current.cancelledProgress = if (pose.recovering()) pose.cancelled else current.progress
                current.recoveryStart = now; current.pendingStart = now; current.remoteModelBindStart = now
            }
            rebindRemoteRecovery(player, current, now)
            current.remoteWaiting = !pose.recovering()
            if (current.remoteWaiting && now - current.pendingStart > 300_000_000L || !recoveryOwner(player, current)) return false
            if (pose.recovering()) { current.cancelledProgress = pose.cancelled; current.progress = Math.min(progress, pose.cancelled) }
        } else {
            // A recovery snapshot can precede the native action-exit packet on the other reliable channel.
            if (current.recovering) return false
            current.progress = if (pose.recovering()) Math.min(progress, pose.cancelled) else progress
            // Native approach catch-up may leave current animation yaw facing away from the world handles.
            if (current.pickup) {
                val network = player.getNetworkCharacterAI()
                if (network != null && network.prediction != null && network.prediction.direction.isFinite()) {
                    val heading = network.prediction.direction
                    player.setTargetAndCurrentDirection(Math.cos(heading.toDouble()).toFloat(), Math.sin(heading.toDouble()).toFloat())
                }
            }
        }
        refreshPickupAction(player, current, now); current.updated = now
        player.setVariable("ToolkitWoodCartClipPilot", false); poseVariables(player, current)
        return true
    }

    @JvmStatic
    private fun bindPickup(player: IsoPlayer, handoff: PickupHandoff, nativeReceipt: Boolean): Boolean {
        val item = player.getPrimaryHandItem()
        if (item == null && player.getSecondaryHandItem() == null) return false
        if (item == null || player.getSecondaryHandItem() !== item
            || item.getID() != handoff.source.cart.getID() || !item.getFullType().equals(handoff.source.cart.getFullType())
            || item.getContainer() !== player.getInventory() || item.getWorldItem() != null
            || CartGrounding.resolvedModel(item) !== handoff.model
            || handoff.receipted && handoff.held !== item && !nativeReceipt) {
            pickupHandoffs.remove(player); return false
        }
        handoff.held = item; handoff.receipted = true
        return true
    }
    /** The cart callback still needs error observation when Lua queue management declines it. */
    @JvmStatic
    @Synchronized
    fun observePickupPerform(action: LuaTimedActionNew?): Boolean {
        if (action == null) return false
        val player = action.chr as? IsoPlayer ?: return false
        if (!player.isLocalPlayer() || !"ToolkitWoodCartPickup".equals(action.getMetaType())) return false
        val handoff = pickupHandoffs[player]
        val state = if (handoff == null) states[player] else handoff.source
        val table = action.getTable()
        if (state == null || state.remote || state.actionOwner !== action || !supported(state.item)
            || table == null || table.rawget("character") !== player) return false
        val id = table.rawget("itemId")
        if (id !is Number || id.toDouble() != state.cart.getID().toDouble()) return false
        val now = System.nanoTime()
        if (handoff != null) return handoffValid(player, handoff, now)
        if (state.handoffRemembered || !state.pickup || state.recovering || !state.rendered || state.world == null
            || now - state.lastRender > PICKUP_HANDOFF_NANOS || now - state.updated > PICKUP_HANDOFF_NANOS) return false
        // This temporary eligibility check neither registers nor renews a handoff deadline.
        val observer = PickupHandoff(state, state.connection, now)
        return observer.model != null && handoffValid(player, observer, now)
    }
    /** The native successful perform boundary proves completion even after forceComplete(). */
    @JvmStatic
    @Synchronized
    fun pickupPerformed(action: LuaTimedActionNew?, scope: ActionCompletion.Scope?, failure: Throwable?) {
        if (failure != null || scope == null || scope.failed || !"perform".equals(scope.phase)
            || scope.action !== (action ?: throw NullPointerException()).getTable() || scope.callback == null
            || scope.callback !== (scope.action ?: throw NullPointerException()).rawget("perform")) return
        val player = action.chr as? IsoPlayer ?: return
        if (!player.isLocalPlayer()) return
        val handoff = pickupHandoffs[player]
        if (handoff == null || handoff.source.remote || handoff.source.actionOwner !== action || handoff.performed
            || !handoffValid(player, handoff, System.nanoTime())) return
        handoff.performed = true
        bindPickup(player, handoff, false)
    }
    /** Only a complete native EquipPacket receipt may bind a subsequently deserialized object. */
    @JvmStatic
    @Synchronized
    fun pickupEquipped(player: IsoPlayer?, connection: Any?) {
        if (player == null || !CartMotionSync.connected() || connection !== GameClient.connection) return
        val now = System.nanoTime()
        val state = states[player]
        if (state != null) rememberPickup(player, state, now)
        val handoff = pickupHandoffs[player]
        if (handoff == null || !handoffValid(player, handoff, now)) return
        // Each complete native parse can supply another exact clone for this same
        // pinned action/cart lease. Its original deadline and all context stay fixed.
        bindPickup(player, handoff, true)
    }
    @JvmStatic
    private fun refreshPickupAction(player: IsoPlayer, state: State, now: Long) {
        // Native PlayerActionsState.setParams(Enter) rebuilds BaseAction for the same
        // accepted cart/generation. Only its fresh active lease may advance the owner;
        // once remembered, a completion token pins that exact final native object.
        if (!state.remote || !state.pickup || state.recovering || state.handoffRemembered || !state.rendered
            || states[player] !== state || state.world == null
            || now - state.lastRender > PICKUP_HANDOFF_NANOS || now - state.updated > PICKUP_HANDOFF_NANOS
            || !player.getVariableBoolean("IsPerformingAnAction")
            || !"ToolkitWoodCart".equals(player.getVariableString("PerformingAction"))
            || !CartGrounding.sameModel(state.cart, player.overridePrimaryHandModel)
            || !emptyRemoteModel(player.overrideSecondaryHandModel)) return
        val network = player.getNetworkCharacterAI()
        val owner = if (network == null) null else network.getAction()
        if (owner != null && owner.javaClass == BaseAction::class.java && owner.chr === player) state.actionOwner = owner
    }
    @JvmStatic
    private fun rememberPickup(player: IsoPlayer, state: State, now: Long) {
        if (state.handoffRemembered || !state.pickup || state.recovering || !state.rendered || state.world == null || state.actionOwner == null
            || now - state.lastRender > PICKUP_HANDOFF_NANOS || now - state.updated > PICKUP_HANDOFF_NANOS
            || unsafeState(player) || state.connection !== (if (GameClient.client) GameClient.connection else null)) return
        val previous = pickupHandoffs[player]
        if (previous != null && previous.source === state) return
        refreshPickupAction(player, state, now)
        val handoff = PickupHandoff(state, state.connection, now)
        if (handoff.model != null && handoffValid(player, handoff, now)) {
            state.handoffRemembered = true; pickupHandoffs[player] = handoff
        }
    }
    @JvmStatic
    private fun handoffValid(player: IsoPlayer?, handoff: PickupHandoff, now: Long): Boolean {
        val source = handoff.source
        if (now >= handoff.deadline || unsafeState(player ?: throw NullPointerException()) || player.isNpc() || player.isSneaking()
            || Math.abs(player.getVariableFloat("WalkInjury", 0f)) >= 0.15f || source.remote == player.isLocalPlayer()
            || source.connection !== handoff.connection || handoff.connection !== (if (GameClient.client) GameClient.connection else null)
            || handoff.connection != null && !CartMotionSync.connected()
            || source.remote && GameClient.IDToPlayerMap[player.getOnlineID()] !== player
            || source.actionOwner == null || (source.actionOwner ?: throw NullPointerException()).chr !== player
            || player.isHideEquippedHandR()) return false
        val current = states[player]
        if (current != null && current !== source) return false
        val actions = player.getCharacterActions()
        if (!actions.isEmpty() && (actions.size != 1 || actions[0] !== source.actionOwner)) return false
        if (source.remote) {
            val network = player.getNetworkCharacterAI()
            if (network == null || network.getAction() != null && network.getAction() !== source.actionOwner) return false
        }
        val performing = player.getVariableBoolean("IsPerformingAnAction")
        if (performing) {
            if (!"ToolkitWoodCart".equals(player.getVariableString("PerformingAction")) || !emptyRemoteModel(player.overrideSecondaryHandModel)) return false
            if (source.remote) {
                // Native setOverride(true,cart,"") owns forceNullOverride until action exit.
                // After retirement the exact same native action may already have cleared its strings.
                return player.getNetworkCharacterAI().getAction() === source.actionOwner
                    && (CartGrounding.sameModel(source.cart, player.overridePrimaryHandModel)
                        || current == null && emptyRemoteModel(player.overridePrimaryHandModel))
            }
            if (player.forceNullOverride || source.actionOwner !is LuaTimedActionNew) return false
            val action = source.actionOwner as LuaTimedActionNew
            if (!"ToolkitWoodCartPickup".equals(action.getMetaType())) return false
            val table = action.getTable()
            // finish(self) precedes native perform's return. Keep its candidate inert until
            // that exact successful callback and authoritative held object are both observed.
            if (table == null || table.rawget("character") !== player) return false
            val id = table.rawget("itemId")
            return id is Number && id.toDouble() == source.cart.getID().toDouble()
                && (emptyRemoteModel(player.overridePrimaryHandModel) || CartGrounding.sameModel(source.cart, player.overridePrimaryHandModel))
        }
        return !player.forceNullOverride && emptyRemoteModel(player.overridePrimaryHandModel) && emptyRemoteModel(player.overrideSecondaryHandModel)
    }
    /** Bounded geometry-only handoff; ordinary motion synchronization continues independently. */
    @JvmStatic
    @Synchronized
    fun pickupHandoff(player: IsoPlayer?): Boolean {
        val handoff = pickupHandoffs[player] ?: return false
        if (!handoffValid(player, handoff, System.nanoTime()) || CartMotionSync.visualEnabled(player)) {
            pickupHandoffs.remove(player); return false
        }
        // A renderer may observe primary assignment before a complete native receipt.
        // A local token also waits for its exact successful native perform boundary.
        if (!handoff.source.remote && !handoff.performed) return false
        val actor = player ?: throw NullPointerException()
        val item = actor.getPrimaryHandItem()
        if (handoff.held == null) {
            // SP complete may follow perform. Its original exact world object needs no ID lookup.
            if (!handoff.source.remote && item === handoff.source.item && actor.getSecondaryHandItem() === item
                && (item ?: throw NullPointerException()).getWorldItem() == null && item.getContainer() === actor.getInventory()) {
                if (!bindPickup(actor, handoff, false)) return false
            } else return false
        }
        if (item !== handoff.held || actor.getSecondaryHandItem() !== item || item == null
            || item.getWorldItem() != null || item.getContainer() !== actor.getInventory()
            || CartGrounding.resolvedModel(item) !== handoff.model) {
            pickupHandoffs.remove(actor); return false
        }
        return true
    }
    /** Animation entry also sweeps offscreen/idle tokens; render visibility never owns their lifetime. */
    @JvmStatic
    @Synchronized
    fun prunePickupHandoffs() {
        val now = System.nanoTime()
        pickupHandoffs.entries.removeIf { !handoffValid(it.key, it.value, now) }
    }
    @JvmStatic
    @Synchronized
    fun endRemote(player: IsoPlayer?) {
        val state = states[player]
        if (state != null && state.remote) end(player)
        else {
            val handoff = pickupHandoffs[player]
            if (handoff != null && !handoffValid(player, handoff, System.nanoTime())) pickupHandoffs.remove(player)
        }
    }
    @JvmStatic
    private fun recoveryOwner(player: IsoPlayer, state: State): Boolean {
        if (state.remote) return !unsafeState(player) && remoteOwner(player, state)
            && state.visualModel != null && state.visualModel === player.overridePrimaryHandModel && emptyRemoteModel(player.overrideSecondaryHandModel)
        if (state.visualModel == null || protectedState(player)) return false
        if (state.pickup) return state.world != null && state.cart.getWorldItem() === state.world
            && state.ownedWorld.getItem() === state.item && state.ownedWorld.getSquare() != null
            && player.getPrimaryHandItem() == null && player.getSecondaryHandItem() == null
            && Math.abs(player.getZ() - state.placed.z) < 0.25f
            && state.visualModel === player.overridePrimaryHandModel && player.overrideSecondaryHandModel == null
        return state.cart.getWorldItem() == null && state.cart.getContainer() === player.getInventory()
            && player.getPrimaryHandItem() === state.item && player.getSecondaryHandItem() === state.item
            && state.visualModel === player.overridePrimaryHandModel && player.overrideSecondaryHandModel == null
    }
    @JvmStatic
    private fun rebindRemoteRecovery(player: IsoPlayer, state: State, now: Long) {
        // ActionContext.update follows our animation-entry hook. Its native exit can clear
        // the leased override again before rendering, even after the recovery aggregate arrived.
        if (!state.remote || !state.recovering || state.visualModel == null
            || now - state.recoveryStart > 300_000_000L || unsafeState(player) || !remoteOwner(player, state)
            || player.getVariableBoolean("IsPerformingAnAction") || !emptyRemoteModel(player.overridePrimaryHandModel)
            || !emptyRemoteModel(player.overrideSecondaryHandModel)) return
        player.overridePrimaryHandModel = state.visualModel; player.resetEquippedHandsModels()
        state.remoteModelBindStart = state.recoveryStart
    }
    @JvmStatic
    private fun pendingExpired(state: State, now: Long): Boolean =
        now - state.recoveryStart >= (0.4 + 0.2 * state.cancelledProgress) * 1_000_000_000.0
            || state.pendingStart != 0L && now - state.pendingStart > 200_000_000L
    @JvmStatic
    private fun recoveryActions(player: IsoPlayer, state: State, now: Long): Boolean {
        if (state.remote) return !player.getVariableBoolean("IsPerformingAnAction") && (!state.remoteWaiting || now - state.pendingStart <= 300_000_000L)
        if (pendingExpired(state, now)) return false
        val actions = player.getCharacterActions()
        if (actions.isEmpty()) return !player.getVariableBoolean("IsPerformingAnAction")
        if (!state.authored || actions.size != 1) return false
        val action = actions[0] as? LuaTimedActionNew ?: return false
        if (action.chr !== player || action.forceStop || action.forceComplete || action.finished()) return false
        val table = action.getTable()
        if (table == null || table.rawget("character") !== player) return false
        val type = action.getMetaType()
        val owned = if (state.pickup) "ISWalkToTimedActionF".equals(type) && table.rawget("toolkitWoodCartItem") === state.item
            || "ToolkitWoodCartPickup".equals(type) && table.rawget("itemId").let { it is Number && it.toDouble() == state.cart.getID().toDouble() }
            else ("ToolkitWoodCartSetdown".equals(type) || "ToolkitWoodCartDrop".equals(type)) && table.rawget("item") === state.item
        if (owned && state.pickup && (state.ownedWorld.getSquare() !== state.cancelSquare || !state.placed.equals(placement(state.item, state.world)))) return false
        if (owned && state.pendingStart == 0L) state.pendingStart = now
        return owned
    }
    @JvmStatic
    @Synchronized
    fun suppressHeldModel(character: zombie.characters.IsoGameCharacter?): Boolean {
        if (character !is IsoPlayer) return false
        val state = states[character]
        return state != null && state.recovering && !state.pickup && recoveryOwner(character, state) && recoveryActions(character, state, System.nanoTime())
    }
    @JvmStatic
    @Synchronized
    @LuaMethod(name = "toolkitWoodCartCancel", global = true)
    fun cancel(player: IsoPlayer?, item: InventoryItem?, pickup: Boolean, stoppedAction: BaseAction?): Boolean {
        val state = states[player]
        if (!Main.CART_TRANSITION_SUPPORTED || state == null || state.item !== item || state.pickup != pickup
            || state.recovering || !state.rendered || state.progress <= 0
            || state.authored && (state.recoveryPose == null || state.recoveryCart == null)
            || !CartGrip.validPosture(state.nativeHeight, state.nativeRotation) || !CartGrip.validPosture(state.referenceHeight, state.referenceRotation)
            || protectedState(player ?: throw NullPointerException()) || player.getVariableBoolean("IsPerformingAnAction")) return false
        val actions = player.getCharacterActions()
        if (!actions.isEmpty() && (actions.size != 1 || actions[0] !== stoppedAction)) return false
        // Keep the same visual model through native stop's same-frame override removal, including held setdown.
        val model = (item ?: throw NullPointerException()).getStaticModel()
        if (model == null || model.isBlank() || player.overridePrimaryHandModel != null || player.overrideSecondaryHandModel != null) return false
        // Its identity is the lease token; another writer may select the very same model name.
        state.visualModel = String(model.toCharArray())
        player.overridePrimaryHandModel = state.visualModel
        if (!recoveryOwner(player, state)) {
            if (player.overridePrimaryHandModel === state.visualModel) player.overridePrimaryHandModel = null
            state.visualModel = null; return false
        }
        player.resetEquippedHandsModels()
        state.recovering = true; state.cancelledProgress = state.progress; state.recoveryStart = System.nanoTime()
        if (state.authored) {
            retireAuthored(player, state); state.movingRecovery = true; state.movementProgress = state.progress
            state.restartPose = null; state.restartPlacement = null
            state.cancelSquare = if (state.world == null) null else state.ownedWorld.getSquare()
            cancelled[player] = state
        }
        publish(player, state)
        return true
    }
    @JvmStatic
    @Synchronized
    @LuaMethod(name = "toolkitWoodCartTick", global = true)
    fun tick(player: IsoPlayer?) { tick(player, System.nanoTime()) }
    @JvmStatic
    fun tick(player: IsoPlayer?, now: Long) {
        val previous = cancelled[player]
        if (previous != null && (protectedState(player ?: throw NullPointerException()) || now - previous.lastRender > 200_000_000L)) cancelled.remove(player)
        val state = states[player]
        if (state != null && state.remote) return
        if (state == null || !state.recovering) return
        val actor = player ?: throw NullPointerException()
        if (!recoveryOwner(actor, state) || !recoveryActions(actor, state, now)) {
            end(actor, !protectedState(actor) && !pendingExpired(state, now)); return
        }
        if (!actor.getCharacterActions().isEmpty()) { state.updated = now; return }
        state.progress = CartTransitionMath.recover(state.cancelledProgress.toDouble(), (now - state.recoveryStart) * 1e-9, !state.pickup).toFloat()
        state.updated = now
        if (state.progress <= 0) end(actor) else { poseVariables(actor, state); publish(actor, state) }
    }
    @JvmStatic
    @Synchronized
    @LuaMethod(name = "toolkitWoodCartStatus", global = true)
    fun status(player: IsoPlayer?): KahluaTable {
        val result = LuaManager.platform.newTable(); val state = states[player]
        result.rawset("active", state != null && !state.recovering); result.rawset("recovering", state != null && state.recovering)
        if (state != null) {
            result.rawset("rendered", state.rendered); result.rawset("ik", state.ik)
            result.rawset("progress", state.progress.toDouble()); result.rawset("pickup", state.pickup); result.rawset("authored", state.authored)
        }
        return result
    }
    @JvmStatic
    @Synchronized
    @LuaMethod(name = "toolkitWoodCartSetdownPose", global = true)
    fun setdownPose(player: IsoPlayer?, item: InventoryItem?, x: Double, y: Double, z: Double, rotation: Double) {
        val state = states[player]
        if (state != null && state.item === item && !state.pickup && (x + y + z + rotation).isFinite()) {
            state.placement = CartTransitionMath.Placement(x.toFloat(), y.toFloat(), z.toFloat() + heightOffset(item), 0f, rotation.toFloat(), 0f, worldScale(item))
            publish(player ?: throw NullPointerException(), state)
        }
    }
    @JvmStatic
    @Synchronized
    @LuaMethod(name = "toolkitWoodCartEnd", global = true)
    fun end(player: IsoPlayer?) { end(player, false) }
    @JvmStatic
    private fun end(player: IsoPlayer?, preserveCancelled: Boolean) {
        if (player == null) {
            CartMotionSync.clearAll(); CartActionSync.clearAll(); CartEmergencyDrop.reset()
            for (owner in java.util.ArrayList(states.keys)) end(owner)
            cancelled.clear(); pickupHandoffs.clear()
            return
        }
        if (!preserveCancelled) cancelled.remove(player)
        if (player.isLocalPlayer()) CartActionSync.end(player)
        val state = states[player]
        if (state != null) rememberPickup(player, state, System.nanoTime()) else pickupHandoffs.remove(player)
        states.remove(player)
        if (state != null) retireAuthored(player, state)
        player.clearVariable("ToolkitWoodCartPoseX"); player.clearVariable("ToolkitWoodCartPoseY")
        player.clearVariable("ToolkitWoodCartClipTime"); player.clearVariable("ToolkitWoodCartClipPickup")
        player.clearVariable("ToolkitMetalCartClip"); player.clearVariable("ToolkitShoppingCartClip")
        if (state != null && state.visualModel != null && state.visualModel === player.overridePrimaryHandModel) {
            player.overridePrimaryHandModel = null; player.resetEquippedHandsModels()
        }
        if (state != null && state.world != null) state.ownedWorld.invalidateRenderChunkLevel(256)
    }

    @JvmStatic
    @Synchronized
    fun render(slot: ModelSlotRenderData?): Boolean {
        val dataSlot = slot ?: throw NullPointerException()
        val player = dataSlot.character as? IsoPlayer ?: return false
        val state = states[player] ?: return false
        if ((if (state.remote) unsafeState(player) else protectedState(player)) || System.nanoTime() - state.updated > 1_000_000_000L) {
            end(player); return false
        }
        if (state.remote && state.pickup && !state.recovering && (player.getPrimaryHandItem() != null || player.getSecondaryHandItem() != null)) {
            end(player); return false
        }
        rebindRemoteRecovery(player, state, System.nanoTime())
        if (state.recovering && (!recoveryOwner(player, state) || !recoveryActions(player, state, System.nanoTime()))) {
            end(player, !pendingExpired(state, System.nanoTime())); return false
        }
        val clip = ModelManager.instance.getAnimationClip("Bob_Cart_Idle") ?: return false
        if (state.recovering && !state.movingRecovery && player.isJustMoved() && state.recoveryPose != null) {
            state.movingRecovery = true; state.movementProgress = state.progress
        }
        var cartModelPresent = false
        for (data in dataSlot.modelData) {
            val instance = data.modelInstance
            val profile = CartWheelbarrow.forItem(state.item)
            val modelName = modelName(state.item)
            if (instance.modelScript == null || !instance.modelScript.getName().equals(modelName)) continue
            cartModelPresent = true
            val held = Matrix4f(); val delta = Matrix4f()
            if (!CartGrounding.rigid(data, clip, held)) continue
            CartGrounding.lowerHandles(held, modelName)
            // Follow native gait clearance so ordinary rendering does not shift both handles after recovery.
            // Keep the captured neutral bank/grip policy; changing it needs a separate source-pose blend.
            val displayedSpine = Vector3f()
            val gait = if (profile != null && state.movingRecovery && !state.pickup) CartLegPace.woodenGaitShift(player,
                if (CartGrip.nativeSpine(dataSlot, instance.parent, displayedSpine)) displayedSpine else null) else 0f
            val model = model(state.item) ?: continue
            if (!(if (profile != null) CartGrounding.alignWheelbarrow(held, profile, 0f, 0f, gait, delta)
                else CartShopping.align(held, model, state.cart.worldScale, delta))) continue
            if (state.placement == null) state.placement = dropPlacement(dataSlot, held, model, state.item)
            if (state.placement == null) continue
            val ground = Matrix4f()
            if (!CartTransitionMath.worldToActor(state.placement, model, dataSlot.x, dataSlot.y, dataSlot.z, dataSlot.animPlayerAngle, ground)) continue
            val phase = phase(state)
            val release = if (state.movingRecovery) CartTransitionMath.recoveryRelease(state.progress.toDouble(), state.movementProgress.toDouble(), state.authored && state.pickup).toFloat() else 1f
            val transform = Matrix4f()
            if (!blend(state.item, ground, held, model, (phase ?: throw NullPointerException()).lift, transform)) continue
            val axle = if (profile == null) Vector3f(CartGrounding.contact(modelName)) else profile.center(Vector3f())
            val center = ground.transformPosition(axle, Vector3f()).lerp(held.transformPosition(axle, Vector3f()), phase.lift.toFloat())
            transform.translateLocal(center.sub(transform.transformPosition(axle, Vector3f())))
            // A cancelled setdown still owns the held cart; carry its return path with the walking actor.
            if (state.movingRecovery && !state.pickup && !blend(state.item, held, state.recoveryCart, model, release.toDouble(), transform)) {
                end(player); return false
            }
            val restartAge = (System.nanoTime() - state.restartStart).toDouble()
            val restart = if (state.restartPose == null) 0f else 1 - CartTransitionMath.smooth(restartAge / RESTART_BLEND_NANOS).toFloat()
            var cartRestart = restartCartWeight(profile, state.pickup, restart)
            if (profile != null && state.pickup && state.restartPose != null) {
                // Let the hip clear the shafts before lowering the cart after an interrupted pickup.
                val u = Math.max(0.0, Math.min(1.0, restartAge / 400_000_000.0))
                cartRestart = 1 - CartTransitionMath.smooth(u - 0.7 * u * (1 - u)).toFloat()
            }
            if (cartRestart > 0) {
                val from = Matrix4f()
                if (!CartTransitionMath.worldToActor(state.restartPlacement, model, dataSlot.x, dataSlot.y, dataSlot.z, dataSlot.animPlayerAngle, from)) {
                    end(player); return false
                }
                val target = Matrix4f(transform)
                if (!blend(state.item, target, from, model, cartRestart.toDouble(), transform)) { end(player); return false }
                val pivot = from.transformPosition(axle, Vector3f()).lerp(target.transformPosition(axle, Vector3f()), 1 - cartRestart)
                transform.translateLocal(pivot.sub(transform.transformPosition(axle, Vector3f())))
            } else { state.restartPose = null; state.restartPlacement = null }
            val reference = CartGrip.referencePosture(instance.parent.animPlayer.getSkinningData(), phase)
            var baseHeight = Float.NaN
            var baseRotation: Quaternionf? = null
            if (state.recovering && !state.movingRecovery) {
                // Native stop fades the action layer into cart idle; retain its calibrated height and chest posture.
                val posture = CartGrip.recoverPosture(CartGrip.Posture(state.nativeHeight, state.nativeRotation),
                    CartGrip.Posture(state.referenceHeight, state.referenceRotation), reference, state.progress / state.cancelledProgress)
                if (posture == null) { end(player); return false }
                baseHeight = posture.height; baseRotation = posture.rotation
            } else if (!state.recovering) {
                val posture = CartGrip.nativePosture(dataSlot, instance.parent)
                state.nativeHeight = if (posture == null) Float.NaN else posture.height
                state.referenceHeight = if (reference == null) Float.NaN else reference.height
                state.nativeRotation = if (posture == null) null else Quaternionf(posture.rotation)
                state.referenceRotation = if (reference == null) null else Quaternionf(reference.rotation)
            }
            // Keep the knee bend and hip hinge in one continuous descent, without an early sink/rebound.
            val lowering = if (profile == null) 0f else (-profile.pickupLowering() * phase.balance).toFloat()
            // A restarted pickup releases the old grip while its clip begins the approach again.
            val reach = if (state.pickup) phase.reach.toFloat() else phase.reach.toFloat() * (1 - restart) + state.restartReach * restart
            val grip = if (state.pickup) phase.grip.toFloat() else phase.grip.toFloat() * (1 - restart) + state.restartGrip * restart
            val clearance = if (profile != null && state.authored && state.movingRecovery && state.pickup)
                CartTransitionMath.recoveryClearance(state.cancelledProgress.toDouble(), (System.nanoTime() - state.recoveryStart) * 1e-9).toFloat() else 0f
            state.ik = if (state.movingRecovery) CartGrip.movingRecovery(dataSlot, instance.parent, clip, delta, transform, held,
                state.recoveryPose, release, !state.pickup, state.recoveryReach, state.recoveryGrip, clearance, modelName)
                else if (state.authored) CartGrip.authoredTransition(dataSlot, instance.parent, clip, delta, transform, reach, grip, state.restartPose, restart, modelName)
                else CartGrip.transition(dataSlot, instance.parent, delta, transform, phase.reach.toFloat(), phase.grip.toFloat(),
                    phase.lift.toFloat(), (ground.m30() - held.m30()) * phase.center.toFloat(), lowering, 0.16f * phase.balance.toFloat(),
                    Math.toRadians(if (profile == null) 0.0 else profile.pickupHingeDegrees() * phase.hinge).toFloat(), baseHeight, baseRotation, modelName)
            if (state.recovering && !state.ik) { end(player); return false }
            if (state.ik && !state.movingRecovery) {
                state.recoveryPose = CartGrip.capture(instance.parent.animPlayer.getSkinningData(), state.recoveryPose)
                if (state.recoveryCart == null) state.recoveryCart = Matrix4f()
                (state.recoveryCart ?: throw NullPointerException()).set(transform)
                state.recoveryReach = reach; state.recoveryGrip = grip
            }
            if (state.ik && state.authored) {
                state.lastPose = CartGrip.capture(instance.parent.animPlayer.getSkinningData(), state.lastPose)
                state.lastPlacement = CartTransitionMath.actorToWorldPlacement(transform, model, dataSlot.x, dataSlot.y, dataSlot.z, dataSlot.animPlayerAngle)
                state.lastReach = if (state.movingRecovery) (if (state.pickup) state.recoveryReach * release else 1 - release * (1 - state.recoveryReach)) else reach
                state.lastGrip = if (state.movingRecovery) (if (state.pickup) state.recoveryGrip * release else 1 - release * (1 - state.recoveryGrip)) else grip
                state.lastRender = System.nanoTime()
            }
            data.xfrm.set(transform).transpose()
            if (CartShopping.item(state.item)) CartShoppingWheels.prepare(dataSlot, state.item, data, transform)
            else CartWheelSpin.prepare(dataSlot, CartWheelSpin.follow(state.item, dataSlot.x, dataSlot.y, dataSlot.animPlayerAngle, transform))
            if (state.world != null && !state.rendered) state.ownedWorld.invalidateRenderChunkLevel(256)
            state.rendered = true; state.lastRender = System.nanoTime(); state.remoteModelBindStart = 0L
            return true
        }
        // Native action exit removes pickup's hand model; our exact lease binds on the next model rebuild.
        // Retain the previously rendered pose only through that initial bounded gap, never a failed cart solve.
        if (state.recovering && !(state.remote && !cartModelPresent && state.remoteModelBindStart != 0L
            && System.nanoTime() - state.remoteModelBindStart <= 300_000_000L)) end(player)
        return false
    }
    @JvmStatic
    @Synchronized
    fun hidden(item: InventoryItem?): Boolean {
        for (state in states.values) if (state.item === item && state.world != null && state.rendered) return true
        return false
    }
    @JvmStatic
    fun dropPlacement(slot: ModelSlotRenderData?, held: Matrix4f?, model: Matrix4f?, item: InventoryItem?): CartTransitionMath.Placement? {
        val profile = CartWheelbarrow.forItem(item)
        return if (profile == null) shoppingDropPlacement(held, model, (slot ?: throw NullPointerException()).x, slot.y, slot.z, slot.animPlayerAngle, (item ?: throw NullPointerException()).worldScale)
        else dropPlacement(held, model, (slot ?: throw NullPointerException()).x, slot.y, slot.z, slot.animPlayerAngle, (item ?: throw NullPointerException()).worldScale, profile.pickupStanceBack(), profile)
    }
    @JvmStatic
    fun dropPlacement(held: Matrix4f?, model: Matrix4f?, x: Float, y: Float, z: Float, angle: Float, scale: Float): CartTransitionMath.Placement? =
        dropPlacement(held, model, x, y, z, angle, scale, STANCE_BACK)
    @JvmStatic
    fun dropPlacement(held: Matrix4f?, model: Matrix4f?, x: Float, y: Float, z: Float, angle: Float, scale: Float, stanceBack: Float): CartTransitionMath.Placement? =
        dropPlacement(held, model, x, y, z, angle, scale, stanceBack, CartWheelbarrow.WOOD)
    @JvmStatic
    fun dropPlacement(held: Matrix4f?, model: Matrix4f?, x: Float, y: Float, z: Float, angle: Float, scale: Float, stanceBack: Float, profile: CartWheelbarrow?): CartTransitionMath.Placement? {
        val pose = CartTransitionMath.actorToWorldPlacement(held, model, x, y, z, angle) ?: return null
        val relative = Matrix4f().rotationY(angle + Math.PI.toFloat()).mul(held).mul(Matrix4f(model).invert())
        var yaw = Math.toDegrees(Math.atan2(-relative.m02().toDouble(), relative.m00().toDouble())).toFloat()
        yaw = (yaw % 360 + 360) % 360
        val groundPose = CartTransitionMath.Placement(pose.x, pose.y, z + 0.00175f, 0f, yaw, 0f, scale * 0.85f)
        val ground = Matrix4f()
        if (!CartTransitionMath.worldToActor(groundPose, model, x, y, z, angle, ground)) return null
        val axle = (profile ?: throw NullPointerException()).center(Vector3f())
        val difference = (held ?: throw NullPointerException()).transformPosition(axle, Vector3f()).sub(ground.transformPosition(axle, Vector3f()))
        difference.z -= stanceBack
        val c = Math.cos(angle.toDouble()).toFloat(); val s = Math.sin(angle.toDouble()).toFloat()
        return CartTransitionMath.Placement(pose.x - 1.5f * (c * difference.x + s * difference.z),
            pose.y + 1.5f * (-s * difference.x + c * difference.z), z + 0.00175f, 0f, yaw, 0f, scale * 0.85f)
    }
    @JvmStatic
    fun shoppingDropPlacement(held: Matrix4f?, model: Matrix4f?, x: Float, y: Float, z: Float, angle: Float, scale: Float): CartTransitionMath.Placement? {
        val pose = CartTransitionMath.actorToWorldPlacement(held, model, x, y, z, angle) ?: return null
        // Euler decomposition has two yaw branches; keep native world yaw in [0,360).
        val relative = Matrix4f().rotationY(angle + Math.PI.toFloat()).mul(held).mul(Matrix4f(model).invert())
        var yaw = Math.toDegrees(Math.atan2(-relative.m02().toDouble(), relative.m00().toDouble())).toFloat()
        yaw = (yaw % 360 + 360) % 360
        val groundPose = CartTransitionMath.Placement(pose.x, pose.y, z, 0f, yaw, 0f, scale)
        val ground = Matrix4f()
        if (!CartTransitionMath.worldToActor(groundPose, model, x, y, z, angle, ground)) return null
        val left = Vector3f(); val right = Vector3f()
        CartGrip.handle("ShoppingCartModel", true, left); CartGrip.handle("ShoppingCartModel", false, right)
        val center = left.add(right).mul(0.5f)
        val difference = (held ?: throw NullPointerException()).transformPosition(center, Vector3f()).sub(ground.transformPosition(center, Vector3f()))
        val c = Math.cos(angle.toDouble()).toFloat(); val s = Math.sin(angle.toDouble()).toFloat()
        return CartTransitionMath.Placement(pose.x - 1.5f * (c * difference.x + s * difference.z),
            pose.y + 1.5f * (-s * difference.x + c * difference.z), z, 0f, yaw, 0f, scale)
    }
    @JvmStatic
    @LuaMethod(name = "toolkitWoodCartDropPose", global = true)
    fun dropPose(player: IsoPlayer?, item: InventoryItem?): KahluaTable? {
        if (!Main.CART_TRANSITION_SUPPORTED || player == null || !supported(item)) return null
        val model = model(item) ?: return null
        val direction = player.getForwardDirection()
        val profile = CartWheelbarrow.forItem(item)
        val pose = if (profile == null) shoppingDropPlacement(held(item, Matrix4f()), model, player.getX(), player.getY(), player.getZ(),
            direction.getDirection() + Math.PI.toFloat() / 2, (item ?: throw NullPointerException()).worldScale)
            else dropPlacement(profile.held(Matrix4f()), model, player.getX(), player.getY(), player.getZ(),
                direction.getDirection() + Math.PI.toFloat() / 2, (item ?: throw NullPointerException()).worldScale, profile.pickupStanceBack(), profile)
        if (pose == null || target(player, pose.x, pose.y, player.getZ()) == null) return null
        val result = LuaManager.platform.newTable()
        result.rawset("x", pose.x.toDouble()); result.rawset("y", pose.y.toDouble())
        result.rawset("z", player.getZ().toDouble()); result.rawset("rotation", pose.zRotation.toDouble())
        return result
    }
    @JvmRecord
    private data class Drop(val player: IsoPlayer?, val item: InventoryItem?, val x: Float, val y: Float, val z: Float, val rotation: Float) {
        override fun toString(): String = "Drop[player=$player, item=$item, x=$x, y=$y, z=$z, rotation=$rotation]"
    }
    private val drop = ThreadLocal<Drop>()

    @JvmStatic
    @LuaMethod(name = "toolkitWoodCartDropBegin", global = true)
    fun beginDrop(player: IsoPlayer?, item: InventoryItem?, x: Double, y: Double, z: Double, rotation: Double): Boolean {
        drop.remove()
        if (!Main.CART_TRANSITION_SUPPORTED || player == null || !supported(item) || (item ?: throw NullPointerException()).getWorldItem() != null
            || item.getContainer() !== player.getInventory() || player.getPrimaryHandItem() !== item || player.getSecondaryHandItem() !== item
            || !(x + y + z + rotation).isFinite() || Math.hypot(x - player.getX(), y - player.getY()) > 1.5
            || z != player.getZ().toDouble() || rotation < 0 || rotation >= 360) return false
        drop.set(Drop(player, item, x.toFloat(), y.toFloat(), z.toFloat(), rotation.toFloat()))
        return true
    }
    @JvmStatic
    @LuaMethod(name = "toolkitWoodCartDropEnd", global = true)
    fun endDrop() { drop.remove() }
    @JvmStatic
    fun place(square: IsoGridSquare?, item: InventoryItem?): InventoryItem? {
        val pending = drop.get()
        if (pending == null || pending.item !== item || square !== (pending.player ?: throw NullPointerException()).getCurrentSquare()) return null
        val target = target(pending.player, pending.x, pending.y, pending.z) ?: return null
        var ox = pending.x - target.getX(); var oy = pending.y - target.getY()
        // The native constructor randomizes exact zero offsets.
        if (ox == 0f) ox = 0.00001f
        if (oy == 0f) oy = 0.00001f
        drop.remove()
        (item ?: throw NullPointerException()).setWorldZRotation(pending.rotation)
        return target.AddWorldInventoryItem(item, ox, oy, 0f, true)
    }
    @JvmStatic
    fun target(player: IsoPlayer?, x: Float, y: Float, z: Float): IsoGridSquare? {
        val square = (player ?: throw NullPointerException()).getCurrentSquare()
        if (square == null || square.HasStairs() || IsoWorld.instance == null || IsoWorld.instance.currentCell == null) return null
        val target = IsoWorld.instance.currentCell.getGridSquare(Math.floor(x.toDouble()).toInt(), Math.floor(y.toDouble()).toInt(), z.toInt())
        return if (target != null && target.TreatAsSolidFloor() && square.canReachTo(target)
            && !target.HasStairs() && !target.isSolid() && !target.isSolidTrans()) target else null
    }
}
