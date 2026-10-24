package net.alexredby.pztoolkitjavapatches

import java.util.WeakHashMap
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.exp
import kotlin.math.floor
import org.joml.Matrix4f
import org.joml.Vector3f
import zombie.GameTime
import zombie.characters.IsoPlayer
import zombie.core.math.PZMath
import zombie.core.skinnedmodel.HelperFunctions
import zombie.core.skinnedmodel.ModelManager
import zombie.core.skinnedmodel.animation.AnimationClip
import zombie.core.skinnedmodel.animation.AnimationPlayer
import zombie.core.skinnedmodel.animation.AnimationTrack
import zombie.core.skinnedmodel.model.Model
import zombie.core.skinnedmodel.model.ModelInstance
import zombie.core.skinnedmodel.model.ModelSlotRenderData
import zombie.core.skinnedmodel.model.SkinningBone
import zombie.core.skinnedmodel.model.SkinningData
import zombie.inventory.InventoryItem

/** Cosmetic native-walk playback with body-leading turns; never supplies root movement. */
internal object CartShoppingTurn {
    data class View(
        val phase: Float,
        val turn: Float,
        val walk: Float = 1f,
        val feet: CartShoppingFeet.Frame? = null,
    )

    /**
     * One cosmetic clock for straight walking and turning, bounded by a relaxed walking cadence.
     */
    class Blend {
        var phase = 0.0
            private set

        var turn = 0.0
            private set

        var walk = 0.0
            private set

        private var velocity = 0.0
        private var walkVelocity = 0.0
        private var clock: Any? = null
        private var previous = Double.NaN
        private var anchored = false

        fun update(
            goal: Double,
            seconds: Double,
            identity: Any?,
            nativePhase: Double,
            nativeDuration: Double,
            moving: Boolean = true,
        ): View {
            val dt = if (seconds.isFinite()) seconds.coerceIn(0.0, .1) else 0.0
            val active =
                moving &&
                    identity != null &&
                    nativePhase.isFinite() &&
                    nativeDuration.isFinite() &&
                    nativeDuration > 0
            val target = if (active && goal.isFinite()) goal.coerceIn(-1.0, 1.0) else 0.0
            if (dt > 0) {
                val frequency = 18.0
                val decay = exp(-frequency * dt)
                val offset = turn - target
                val rate = velocity + frequency * offset
                turn = (target + (offset + rate * dt) * decay).coerceIn(-1.0, 1.0)
                velocity = (velocity - frequency * rate * dt) * decay
                val walkTarget = if (active) 1.0 else 0.0
                val walkOffset = walk - walkTarget
                val walkRate = walkVelocity + frequency * walkOffset
                walk = (walkTarget + (walkOffset + walkRate * dt) * decay).coerceIn(0.0, 1.0)
                walkVelocity = (walkVelocity - frequency * walkRate * dt) * decay
                if (abs(turn) < .0001 && target == 0.0) {
                    turn = 0.0
                    velocity = 0.0
                }
                if (walk < .0001 && !active) {
                    walk = 0.0
                    walkVelocity = 0.0
                    anchored = false
                }
            }
            if (active) {
                val current = nativePhase - floor(nativePhase)
                if (!anchored) {
                    // Bob's native walk starts its anatomical left swing halfway through the clip.
                    phase = (current + .5) % 1.0
                    anchored = true
                } else if (identity === clock && previous.isFinite()) {
                    var delta = current - previous
                    if (delta < -.5) delta += 1.0
                    if (delta in 0.0..0.35) {
                        // Native strafe compensation can run much faster than a natural walk.
                        // Keep the cosmetic cycle <= 137 steps/min and honor slower/paused tracks.
                        phase = (phase + minOf(delta, dt / .88)) % 1.0
                    }
                }
                clock = identity
                previous = current
            } else {
                clock = null
                previous = Double.NaN
            }
            return View(phase.toFloat(), turn.toFloat(), walk.toFloat())
        }
    }

    private class State(val item: InventoryItem) {
        val blend = Blend()
        val feet = CartShoppingFeet.State()
        val poses = Array<Matrix4f?>(64) { Matrix4f() }
        var track: AnimationTrack? = null
        var view = View(0f, 0f, 0f)
    }

    private data class Draw(
        val player: IsoPlayer,
        val owner: ModelInstance,
        val model: Model,
        val animator: AnimationPlayer,
        val view: View,
    )

    private val states = WeakHashMap<IsoPlayer, State>()
    private val slots = WeakHashMap<ModelSlotRenderData, Draw>()

    fun amount(x: Float, y: Float): Double {
        if (!x.isFinite() || !y.isFinite() || y <= .05f) return 0.0
        val angle = atan2(-x.toDouble(), y.toDouble())
        val u = ((abs(angle) - .04) / .56).coerceIn(0.0, 1.0)
        return Math.signum(angle) * u * u * (3 - 2 * u)
    }

    /** Game-thread producer, after native animation has advanced and remote fields were applied. */
    @JvmStatic
    @Synchronized
    fun update(player: IsoPlayer) {
        val item = player.getPrimaryHandItem()
        if (
            !CartShopping.item(item) ||
                !CartSteeringHooks.supportedCart(player) ||
                !player.getVariableBoolean("ToolkitCartMotion") ||
                !player.getVariableBoolean("ToolkitCartPivot") ||
                player.isDead() ||
                player.hasHitReaction() ||
                player.isKnockedDown() ||
                player.isGettingUp() ||
                player.isAiming() ||
                player.isSneaking() ||
                player.getVehicle() != null ||
                player.isRagdollSimulationActive() ||
                player.isGrappling() ||
                player.isBeingGrappled() ||
                player.getVariableBoolean("IsPerformingAnAction") ||
                player.isRunning() ||
                player.isSprinting() ||
                abs(player.getVariableFloat("WalkInjury", 0f)) >= .15f ||
                CartAnimationBlend.fastWeight(player) > .001f
        ) {
            states.remove(player)
            return
        }
        val x = player.getVariableFloat("ToolkitCartStepX", 0f)
        val y = player.getVariableFloat("ToolkitCartStepY", 0f)
        val moving =
            x.isFinite() && y.isFinite() && y > .05f && player.getVariableBoolean("isMoving")
        val previousState = states[player]?.takeIf { it.item === item }
        if (!moving && previousState == null) return
        val state = previousState ?: State(item!!).also { states[player] = it }
        val animator = player.getAdvancedAnimator()
        var chosen: AnimationTrack? = null
        var largest = 0f
        val layer = animator?.getRootLayer()
        if (layer != null)
            for (node in layer.getLiveAnimNodes()) {
                if (node.getName() != "ToolkitCartPivotWalk") continue
                for (track in node.getMainAnimationTracks()) {
                    val weight = track.getBlendFieldWeight() * track.getBlendWeight()
                    val name = track.getName() ?: continue
                    if (
                        !weight.isFinite() ||
                            weight <= .0001f ||
                            !name.startsWith("Toolkit_CartPivot_") ||
                            name.endsWith("Idle") ||
                            name.endsWith("Backward")
                    )
                        continue
                    if (track === state.track) {
                        chosen = track
                        largest = Float.POSITIVE_INFINITY
                    } else if (weight > largest) {
                        chosen = track
                        largest = weight
                    }
                }
            }
        state.track = chosen
        val phase =
            if (chosen != null && chosen.getDuration() > 0)
                (chosen.getCurrentAnimationTime() / chosen.getDuration()).toDouble()
            else Double.NaN
        state.view =
            state.blend.update(
                amount(x, y),
                GameTime.getInstance().getRealworldSecondsSinceLastUpdate().toDouble(),
                chosen,
                phase,
                chosen?.getDuration()?.toDouble() ?: Double.NaN,
                moving,
            )
        if (!moving && state.view.walk == 0f) states.remove(player)
    }

    @JvmStatic
    @Synchronized
    fun reset(player: IsoPlayer?) {
        states.remove(player)
    }

    @JvmStatic
    @Synchronized
    fun bind(slot: ModelSlotRenderData?, source: ModelManager.ModelSlot?) {
        if (slot == null) return
        slots.remove(slot)
        val player = source?.character as? IsoPlayer ?: return
        val state = states[player] ?: return
        if (
            player.getPrimaryHandItem() !== state.item ||
                player.getSecondaryHandItem() !== state.item
        )
            return
        val owner = source?.model ?: return
        if (slot.character !== player || slot.`object` !== player || owner.`object` !== player)
            return
        val animation = owner.animPlayer
        var view = state.view
        if (animation != null && animation.hasSkinningData()) {
            val actor = animation.getSkinningData()
            val count = actor.numBones()
            var complete = count <= state.poses.size && count <= animation.getModelTransformsCount()
            if (complete)
                for (i in 0 until count) {
                    val pose = animation.getModelTransformAt(i)
                    if (pose == null) {
                        complete = false
                        break
                    }
                    PZMath.convertMatrix(pose, state.poses[i]!!).transpose()
                }
            if (complete && apply(state.poses, actor, view)) {
                val root =
                    CartShoppingFeet.Root(
                        slot.x.toDouble(),
                        slot.y.toDouble(),
                        animation.getRenderedAngle().toDouble(),
                    )
                view = view.copy(feet = state.feet.update(root, view, actor, state.poses))
            } else state.feet.clear()
        }
        capture(slot, source, view)
    }

    /** The game-thread stance solve samples the same cosmetic body as the renderer. */
    @JvmStatic
    @Synchronized
    fun current(player: IsoPlayer): View? {
        val state = states[player] ?: return null
        return state.view.takeIf {
            it.walk > .001f &&
                player.getPrimaryHandItem() === state.item &&
                player.getSecondaryHandItem() === state.item
        }
    }

    /** Snapshot ownership is checked once by the producer; workers never read live actor state. */
    @JvmStatic
    @Synchronized
    fun capture(slot: ModelSlotRenderData, source: ModelManager.ModelSlot?, view: View) {
        slots.remove(slot)
        val player = source?.character as? IsoPlayer ?: return
        val owner = source.model ?: return
        val model = owner.model ?: return
        val animation = owner.animPlayer ?: return
        if (
            slot.character !== player ||
                slot.`object` !== player ||
                owner.`object` !== player ||
                !view.phase.isFinite() ||
                view.phase !in 0f..1f ||
                !view.turn.isFinite() ||
                abs(view.turn) > 1f ||
                !view.walk.isFinite() ||
                view.walk <= .001f ||
                view.walk > 1f
        )
            return
        slots[slot] = Draw(player, owner, model, animation, view)
    }

    @JvmStatic
    @Synchronized
    fun release(slot: ModelSlotRenderData?) {
        slots.remove(slot)
    }

    @JvmStatic
    @Synchronized
    fun view(slot: ModelSlotRenderData?, owner: ModelInstance?): View? {
        val target = slot ?: return null
        val instance = owner ?: return null
        val draw = slots[target] ?: return null
        return draw.view.takeIf {
            instance === draw.owner &&
                instance.model === draw.model &&
                instance.animPlayer === draw.animator &&
                target.character === draw.player &&
                target.`object` === draw.player
        }
    }

    private class Sampler {
        var clip: AnimationClip? = null
        val track = AnimationTrack.alloc()
        val position = org.lwjgl.util.vector.Vector3f()
        val rotation = org.lwjgl.util.vector.Quaternion()
        val scale = org.lwjgl.util.vector.Vector3f()
        val native = org.lwjgl.util.vector.Matrix4f()
        val target = Array(64) { Matrix4f() }
        val result = Array(64) { Matrix4f() }
        val working = Array(64) { Matrix4f() }
        val from = Matrix4f()
        val local = Matrix4f()
        val offset = Vector3f()
    }

    private val sampler = ThreadLocal.withInitial(::Sampler)
    private val walkingSampler = ThreadLocal.withInitial(::Sampler)

    private fun clip(name: String): AnimationClip? =
        try {
            ModelManager.instance.getAnimationClip(name)
        } catch (_: NullPointerException) {
            null
        }

    @JvmStatic
    fun apply(poses: Array<out Matrix4f?>, actor: SkinningData, view: View): Boolean =
        apply(
            poses,
            actor,
            clip("Toolkit_ShoppingWalk"),
            if (abs(view.turn) > .001f)
                clip(
                    if (view.turn > 0) "Toolkit_ShoppingTurn_Left"
                    else "Toolkit_ShoppingTurn_Right",
                )
            else null,
            view,
        )

    /**
     * Stage both clips before committing; a missing/refused turn retains the valid straight walk.
     */
    @JvmStatic
    fun apply(
        poses: Array<out Matrix4f?>,
        actor: SkinningData,
        walkClip: AnimationClip?,
        turnClip: AnimationClip?,
        view: View,
    ): Boolean {
        val count = actor.numBones()
        if (count > 64 || poses.size < count || !valid(view)) return false
        val walk = walkingSampler.get()
        for (i in 0 until count) {
            val pose = poses[i] ?: return false
            if (!pose.isFinite) return false
            walk.working[i].set(pose)
        }
        if (
            !sample(
                walk.working,
                actor,
                walkClip,
                view.phase,
                view.walk.toDouble(),
                walk,
            )
        )
            return false
        if (abs(view.turn) > .001f) {
            sample(
                walk.working,
                actor,
                turnClip,
                view.phase,
                abs(view.turn * view.walk).toDouble(),
                sampler.get(),
            )
        }
        CartShoppingFeet.apply(walk.working, actor, view.feet)
        for (i in 0 until count) poses[i]!!.set(walk.working[i])
        return true
    }

    private fun valid(view: View): Boolean =
        view.phase.isFinite() &&
            view.phase in 0f..1f &&
            view.turn.isFinite() &&
            abs(view.turn) <= 1f &&
            view.walk.isFinite() &&
            view.walk in 0f..1f

    /** Transactional local-joint blend; full model poses are committed only after validation. */
    @JvmStatic
    fun apply(
        poses: Array<out Matrix4f?>,
        actor: SkinningData,
        clip: AnimationClip?,
        view: View,
    ): Boolean =
        valid(view) &&
            sample(
                poses,
                actor,
                clip,
                view.phase,
                abs(view.turn * view.walk).toDouble(),
                sampler.get(),
            )

    private fun sample(
        poses: Array<out Matrix4f?>,
        actor: SkinningData,
        clip: AnimationClip?,
        phase: Float,
        weight: Double,
        scratch: Sampler,
    ): Boolean {
        val count = actor.numBones()
        val pelvis = actor.getBone("Bip01_Pelvis") ?: return false
        if (
            clip == null ||
                count > 64 ||
                poses.size < count ||
                !phase.isFinite() ||
                phase !in 0f..1f ||
                !weight.isFinite() ||
                weight !in 0.0..1.0 ||
                clip.getDuration() <= 0 ||
                !clip.getDuration().isFinite()
        )
            return false
        for (i in 0 until count) {
            val parent = actor.getBoneAt(i).parent
            if (poses[i]?.isFinite != true || parent != null && parent.index >= i) return false
            val frames =
                try {
                    clip.getBoneFramesAt(i)
                } catch (_: IndexOutOfBoundsException) {
                    return false
                }
            if (frames.isNullOrEmpty() || frames[0].boneName != actor.getBoneAt(i).name)
                return false
        }
        if (scratch.clip !== clip) {
            scratch.track.reset()
            scratch.track.startClip(clip, true, 0f)
            scratch.track.setUseDeferredMovement(false)
            scratch.clip = clip
        }
        val time = (phase % 1f) * clip.getDuration()
        scratch.track.setCurrentTimeValue(time)
        scratch.track.setPreviousTimeValue(time)
        scratch.track.UpdateKeyframes(0f)
        for (i in 0 until count) {
            val bone = actor.getBoneAt(i)
            val parent = bone.parent
            scratch.track.get(i, scratch.position, scratch.rotation, scratch.scale)
            HelperFunctions.CreateFromQuaternion(scratch.rotation, scratch.native)
            HelperFunctions.setPosition(scratch.native, scratch.position)
            PZMath.convertMatrix(scratch.native, scratch.target[i]).transpose()
            val from = scratch.from.set(poses[i]!!)
            if (parent != null) scratch.local.set(poses[parent.index]!!).invert().mul(from, from)
            var ancestor: SkinningBone? = bone
            while (ancestor != null && ancestor !== pelvis) ancestor = ancestor.parent
            val local = scratch.local
            if (ancestor === pelvis) {
                if (
                    !CartTransitionMath.blend(
                        from,
                        scratch.target[i],
                        weight,
                        local,
                    )
                )
                    return false
                if (bone !== pelvis) {
                    val length = from.getTranslation(scratch.offset).length()
                    local.getTranslation(scratch.offset)
                    if (length > 0) {
                        if (scratch.offset.lengthSquared() < 1e-12f) {
                            // Native Walk omits offsets for unskinned end markers. Keep the
                            // actor's marker instead of collapsing it or refusing the gait.
                            if (!bone.name.endsWith("Nub")) return false
                            from.getTranslation(scratch.offset)
                        }
                        local.setTranslation(scratch.offset.normalize(length))
                    }
                }
            } else local.set(from)
            if (parent == null) scratch.result[i].set(local)
            else scratch.result[parent.index].mul(local, scratch.result[i])
            if (!scratch.result[i].isFinite) return false
        }
        for (i in 0 until count) poses[i]!!.set(scratch.result[i])
        return true
    }
}
