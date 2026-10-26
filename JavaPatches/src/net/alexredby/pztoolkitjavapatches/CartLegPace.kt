package net.alexredby.pztoolkitjavapatches

import java.util.Objects
import java.util.WeakHashMap
import java.util.function.Function
import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.core.skinnedmodel.ModelManager
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlendPicker.PickResults
import zombie.core.skinnedmodel.advancedanimation.AnimNode
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode
import zombie.core.skinnedmodel.animation.AnimationClip
import zombie.core.skinnedmodel.animation.AnimationTrack
import zombie.core.skinnedmodel.animation.BoneAxis
import zombie.iso.Vector2

/** Game-thread compensation for directional clips with different root-motion speeds. */
object CartLegPace {
    private const val MAX_FAST_CLEARANCE = .24f

    @JvmRecord
    private data class Velocity(
        val bone: String?,
        val axis: BoneAxis?,
        val x: Double,
        val y: Double,
    ) {
        override fun toString() = "Velocity[bone=$bone, axis=$axis, x=$x, y=$y]"
    }

    // Native getTotalTranslation builds a frame list; clips are immutable after loading.
    private val velocities = WeakHashMap<AnimationClip, Velocity>()
    private val picks = PickResults()
    private val translation = Vector2()

    class Ramp() {
        @JvmField var speed = 0.0
        @JvmField var velocity = 0.0

        fun reset(target: Double) {
            speed = if (target.isFinite()) Math.max(0.0, target) else 0.0
            velocity = 0.0
        }

        fun update(target: Double, seconds: Double, load: Double): Double =
            update(target, seconds, load, false)

        fun update(target: Double, seconds: Double, load: Double, coasting: Boolean): Double {
            if (!speed.isFinite() || !velocity.isFinite()) reset(target)
            if (!target.isFinite() || target < 0 || !seconds.isFinite() || seconds <= 0)
                return speed
            val dt = Math.min(.1, seconds)
            val boundedLoad = if (load.isFinite()) Math.max(0.0, Math.min(1.0, load)) else 0.0
            val frequency =
                1 /
                    (if (target > speed) .13 + .09 * boundedLoad
                    else if (coasting) .22 + .16 * boundedLoad else .04 + .02 * boundedLoad)
            val previous = speed
            val offset = speed - target
            val rate = velocity + frequency * offset
            val decay = Math.exp(-frequency * dt)
            speed = target + (offset + rate * dt) * decay
            velocity = (velocity - frequency * rate * dt) * decay
            val bounded =
                Math.max(Math.min(previous, target), Math.min(Math.max(previous, target), speed))
            // Releasing Sprint must brake immediately, even while the spring was accelerating.
            if (bounded != speed) {
                speed = bounded
                velocity = 0.0
            }
            return speed
        }

        fun settled(target: Double): Boolean =
            target.isFinite() && Math.abs(speed - target) < 1e-3 && Math.abs(velocity) < 1e-2
    }

    /** XML reads the variable at track creation; existing tracks need their rate updated. */
    @JvmStatic
    fun apply(player: IsoPlayer?, pace: Float) {
        if (player == null || !pace.isFinite() || pace < 0) return
        player.setVariable("ToolkitCartLegPace", pace)
        val animator = player.getAdvancedAnimator()
        if (animator != null && animator.getRootLayer() != null)
            applyTracks(animator.getRootLayer().getLiveAnimNodes(), pace, pivotName(player))
    }

    @JvmStatic
    fun applyTracks(nodes: Iterable<LiveAnimNode?>?, pace: Float, currentGait: String?) {
        for (entry in nodes ?: throw NullPointerException()) {
            val node = entry ?: throw NullPointerException()
            if (!node.isActive()) continue
            // At postUpdateAnimating entry the outgoing gait can still be active.
            if (!(currentGait ?: throw NullPointerException()).equals(node.getName())) continue
            for (track in node.getMainAnimationTracks()) track.setSpeedDelta(pace)
        }
    }

    /** Native requested root speed, before directional compensation or a Sprint ramp. */
    @JvmStatic
    fun targetSpeed(player: IsoPlayer?, stepX: Float, stepY: Float): Float {
        val amount = Math.hypot(stepX.toDouble(), stepY.toDouble())
        if (!amount.isFinite()) return Float.NaN
        if (amount < 1e-6) return 0f
        val node = pivotNode(player) ?: return Float.NaN
        val owner = player ?: throw NullPointerException()
        // Backing retains its authored slower stride and the existing injury envelope.
        if (!owner.isRunning() && !owner.isSprinting() && stepY < 0)
            return maneuverSpeed(owner, stepX, stepY)
        val native = CartInjury.nativeNode(owner, node) ?: return Float.NaN
        val speed =
            nativeSpeed(
                native,
                owner.getVariableFloat("WalkInjury", 0f),
                owner.getVariableFloat("WalkSpeed", 0f),
                native.getSpeedScale(owner),
                ::clip,
            )
        return speed * amount.toFloat()
    }

    /** Stationary turns and reverse travel retain their calibrated maneuver budget. */
    @JvmStatic
    fun maneuverSpeed(player: IsoPlayer?, stepX: Float, stepY: Float): Float {
        val amount = Math.hypot(stepX.toDouble(), stepY.toDouble())
        if (!amount.isFinite()) return Float.NaN
        if (amount < 1e-6) return 0f
        val node = pivotNode(player) ?: return Float.NaN
        val owner = player ?: throw NullPointerException()
        val sprint = owner.isSprinting()
        val run = owner.isRunning()
        val cart = owner.getPrimaryHandItem()
        val walk =
            walkingReference(if (cart == null) null else cart.getFullType(), sprint || run, stepY)
        val mode = if (sprint) "Sprint" else if (run) "Run" else "Walk"
        var blend = owner.getVariableFloat("WalkSpeed", 0f)
        if (sprint) blend = Math.max(0f, (blend - .5f) * 2)
        val base = if (sprint) .96f else 1.04f
        val ordinary =
            targetSpeed(
                node,
                clip(if (sprint) "Bob_Run" else walk),
                clip(if (sprint || run) "Bob_$mode" else walk),
                if (run || sprint) blend else 1f,
                if (run || sprint) 1f else amount.toFloat(),
                base,
            )
        val injury = CartInjury.blend(owner, node) ?: return ordinary
        val nativeVelocity = injuryVelocity(node, injury, ::clip) ?: return ordinary
        val healthyRadius =
            if (run || sprint) 1f
            else Math.max(0f, Math.min(1f, owner.getVariableFloat("WalkSpeed", .8f)))
        val radius = if (run || sprint) 1f else CartInjury.walkMagnitude(owner, healthyRadius)
        val effort = if (radius > 1e-6f) amount.toFloat() / radius else 0f
        val healthy =
            if (run || sprint) ordinary * amount.toFloat()
            else if (radius > 1e-6f) ordinary * healthyRadius / radius else 0f
        var nativeSpeed = base * Math.hypot(nativeVelocity.x, nativeVelocity.y).toFloat()
        // Keep the slower authored reverse stride; injury cannot make backing up faster.
        if (!run && !sprint && stepY < 0) {
            val backward =
                velocity(clip(walk), node.getDeferredBoneName(), node.getDeferredBoneAxis())
            if (backward != null)
                nativeSpeed =
                    Math.min(
                        nativeSpeed,
                        base * healthyRadius * Math.hypot(backward.x, backward.y).toFloat(),
                    )
        }
        return healthy * (1 - injury.amount) + nativeSpeed * effort * injury.amount
    }

    /** Sample the actual native field, including the moving origin of defaultWalk. */
    @JvmStatic
    fun nativeSpeed(
        node: AnimNode?,
        injury: Float,
        speed: Float,
        pace: Float,
        clips: Function<String?, AnimationClip?>?,
    ): Float {
        if (!pace.isFinite() || pace < 0) return Float.NaN
        val root = fieldVelocity(node, injury, speed, clips, null) ?: return Float.NaN
        return (pace * Math.hypot(root.x, root.y)).toFloat()
    }

    @JvmStatic
    fun walkingReference(cartType: String?, fast: Boolean, stepY: Float): String =
        if (!fast && stepY < 0 && CartWheelbarrow.forType(cartType) != null) "Bob_WalkBwdNoAim1Hand"
        else "Bob_Walk"

    @JvmStatic
    fun targetSpeed(
        node: AnimNode?,
        slow: AnimationClip?,
        fast: AnimationClip?,
        blend: Float,
        amount: Float,
        base: Float,
    ): Float {
        if (
            node == null ||
                slow == null ||
                fast == null ||
                !blend.isFinite() ||
                !amount.isFinite() ||
                amount < 0 ||
                !base.isFinite() ||
                base < 0
        )
            return Float.NaN
        val low = velocity(slow, node.getDeferredBoneName(), node.getDeferredBoneAxis())
        val high = velocity(fast, node.getDeferredBoneName(), node.getDeferredBoneAxis())
        if (low == null || high == null) return Float.NaN
        val weight = Math.max(0f, Math.min(1f, blend)).toDouble()
        return (base *
                amount *
                (Math.hypot(low.x, low.y) * (1 - weight) + Math.hypot(high.x, high.y) * weight))
            .toFloat()
    }

    /** Cadence changes the native extracted movement budget; movement must not scale it again. */
    @JvmStatic
    fun applySpeed(player: IsoPlayer?, speed: Float, stepX: Float, stepY: Float) {
        if (player == null) return
        if (!speed.isFinite() || speed < 0) {
            apply(player, scale(player, stepX, stepY))
            return
        }
        val incoming = pivotNode(player)
        val current =
            blendedSpeed(incoming, stepX, stepY, ::clip, CartInjury.blend(player, incoming))
        val pace =
            if (speed == 0f) 0f
            else if (current > 1e-6) Math.min(2.5f, speed / current)
            else scale(player, stepX, stepY)
        player.setVariable("ToolkitCartLegPace", pace)
        val animator = player.getAdvancedAnimator()
        if (animator != null && animator.getRootLayer() != null) {
            val currentGait =
                if (incoming != null && Math.hypot(stepX.toDouble(), stepY.toDouble()) >= 1e-6)
                    incoming.name
                else null
            applySpeedTracks(
                animator.getRootLayer().getLiveAnimNodes(),
                speed,
                currentGait,
                pace,
                stepY,
            )
        }
    }

    @JvmStatic
    fun brace(
        player: IsoPlayer?,
        target: Float,
        stepX: Float,
        stepY: Float,
        amount: Double,
        blocked: Boolean,
    ): Float {
        val radius = (1 - amount * amount * (3 - 2 * amount)).toFloat()
        val x = stepX * radius
        val y = stepY * radius
        val owner = player ?: throw NullPointerException()
        owner.setVariable("ToolkitCartStepX", x)
        owner.setVariable("ToolkitCartStepY", y)
        val speed = if (blocked) 0f else target * radius
        applySpeed(owner, speed, x, y)
        return speed
    }

    @JvmStatic
    fun applySpeedTracks(
        nodes: Iterable<LiveAnimNode?>?,
        speed: Float,
        currentGait: String?,
        currentPace: Float,
        stepY: Float,
    ) {
        for (entry in nodes ?: throw NullPointerException()) {
            val node = entry ?: throw NullPointerException()
            val name = node.getName()
            if (
                !"ToolkitCartPivotWalk".equals(name) &&
                    !"ToolkitWoodCartPivotWalk".equals(name) &&
                    !"ToolkitCartPivotRun".equals(name) &&
                    !"ToolkitCartPivotSprint".equals(name)
            )
                continue
            // Native refreshes the current gait's directional weights after this hook.
            if (name.equals(currentGait)) {
                for (track in node.getMainAnimationTracks()) track.setSpeedDelta(currentPace)
                continue
            }
            var x = 0.0
            var y = 0.0
            var valid = true
            for (track in node.getMainAnimationTracks()) {
                val weight = track.getBlendFieldWeight()
                if (!weight.isFinite()) {
                    valid = false
                    break
                }
                if (weight < 1e-4f) continue
                val root =
                    velocity(
                        track.getClip(),
                        node.getDeferredBoneName(),
                        node.getDeferredBoneAxis(),
                    )
                if (root == null) {
                    valid = false
                    break
                }
                x += Math.min(1f, weight) * root.x
                y += Math.min(1f, weight) * root.y
            }
            val current = Math.hypot(x, y)
            if (speed != 0f && (!valid || current < 1e-6)) continue
            // Inactive nodes retain their old field weights through a direction change.
            val pace =
                if (speed == 0f || y * stepY < -1e-6) 0f
                else Math.min(2.5, speed / current).toFloat()
            for (track in node.getMainAnimationTracks()) track.setSpeedDelta(pace)
        }
    }

    @JvmStatic
    fun pivotName(cartType: String?, run: Boolean, sprint: Boolean): String {
        if (sprint) return "ToolkitCartPivotSprint"
        if (run) return "ToolkitCartPivotRun"
        return if (CartWheelbarrow.forType(cartType) != null) "ToolkitWoodCartPivotWalk"
        else "ToolkitCartPivotWalk"
    }

    private fun pivotName(player: IsoPlayer): String {
        val cart = player.getPrimaryHandItem()
        return pivotName(
            if (cart == null) null else cart.getFullType(),
            player.isRunning(),
            player.isSprinting(),
        )
    }

    @JvmStatic
    fun pivotNode(player: IsoPlayer?): AnimNode? {
        if (player == null) return null
        val animator = player.getAdvancedAnimator()
        if (animator == null || animator.animSet == null) return null
        val sprint = player.isSprinting()
        val run = player.isRunning()
        val state =
            animator.animSet.states[if (sprint) "sprint" else if (run) "run" else "movement"]
                ?: return null
        val name = pivotName(player)
        for (node in state.nodes) if (name.equals(node.name)) return node
        return null
    }

    @JvmStatic
    fun brakeClip(name: String?): Boolean =
        when (name) {
            "Bob_RunToStop2H_Heavy",
            "Bob_SprintToStop2h_Heavy",
            "Toolkit_CartPivot_StopRun",
            "Toolkit_CartPivot_StopSprint" -> true
            else -> false
        }

    private fun brakeTrack(node: LiveAnimNode): AnimationTrack? {
        if (!"ToolkitCartIdle".equals(node.getName()) || !node.isTransitioningIn()) return null
        val track = node.getTransitionInTrack() ?: return null
        return if (brakeClip(track.getName())) track else null
    }

    @JvmStatic
    fun brakeTrack(player: IsoPlayer?): AnimationTrack? {
        val animator = (player ?: throw NullPointerException()).getAdvancedAnimator()
        if (animator != null && animator.getRootLayer() != null)
            for (node in animator.getRootLayer().getLiveAnimNodes()) {
                val track = brakeTrack(node)
                if (track != null) return track
            }
        return null
    }

    @JvmStatic
    fun cancelBrake(player: IsoPlayer?, hard: Boolean) {
        val animator = (player ?: throw NullPointerException()).getAdvancedAnimator()
        if (animator == null || animator.getRootLayer() == null) return
        for (node in animator.getRootLayer().getLiveAnimNodes()) {
            val track = brakeTrack(node) ?: continue
            // Stop translation independently of the pose's native fade when a collision interrupts
            // it.
            track.setUseDeferredMovement(false)
            if (hard) node.stopTransitionIn()
        }
    }

    /** Model-Z grip clearance follows each native gait, including outgoing tracks. */
    @JvmStatic fun woodenGaitShift(player: IsoPlayer?): Float = woodenGaitShift(player, null)

    @JvmStatic
    fun woodenGaitShift(player: IsoPlayer?, spine: org.joml.Vector3fc?): Float {
        if (player == null) return 0f
        var side = Math.min(woodenSideShift(player), CartSteeringHooks.sideClearance(player))
        // Bank and Strafe provide the same shaft clearance; do not stack their advances.
        side =
            Math.min(
                0f,
                side -
                    CartSteeringMath.woodenShift(
                        CartSteeringHooks.clearanceLean(player).toFloat(),
                        0f,
                    ),
            )
        return Math.min(woodenFastShift(player, spine), side)
    }

    @JvmStatic fun woodenFastShift(player: IsoPlayer?): Float = woodenFastShift(player, null)

    @JvmStatic
    fun woodenFastShift(player: IsoPlayer?, displayedSpine: org.joml.Vector3fc?): Float {
        val owner = player ?: throw NullPointerException()
        val animator = owner.getAdvancedAnimator()
        val gait =
            if (animator == null || animator.getRootLayer() == null) 0f
            else woodenGaitShift(animator.getRootLayer().getLiveAnimNodes())
        // Gait flags change before the pose blends. Follow the displayed tracks,
        // including the braking clip, instead of switching the clearance reserve on/off.
        val weight = CartAnimationBlend.fastWeight(owner)
        if (weight == 0f) return gait
        if (displayedSpine != null)
            return woodenBodyShift(gait, displayedSpine.x(), displayedSpine.z(), weight)
        if (!owner.hasAnimationPlayer()) return gait
        val animation = owner.getAnimationPlayer()
        if (animation == null || !animation.hasSkinningData()) return gait
        val spine = animation.getSkinningData().boneIndices["Bip01_Spine"]
        if (spine == null || spine < 0 || spine >= animation.getModelTransformsCount()) return gait
        val pose = animation.getModelTransformAt(spine)
        // AnimationPlayer stores the model pose transposed, as in the native render palette.
        return if (pose == null) gait else woodenBodyShift(gait, pose.m03, pose.m23, weight)
    }

    @JvmStatic
    fun woodenSideShift(player: IsoPlayer?): Float {
        val animator = (player ?: throw NullPointerException()).getAdvancedAnimator()
        return if (animator == null || animator.getRootLayer() == null) 0f
        else woodenSideShift(animator.getRootLayer().getLiveAnimNodes())
    }

    @JvmStatic
    fun woodenSideShift(nodes: Iterable<LiveAnimNode?>?): Float {
        var weight = 0.0
        for (entry in nodes ?: throw NullPointerException()) {
            val node = entry ?: throw NullPointerException()
            if (
                "ToolkitCartPivotWalk".equals(node.getName()) ||
                    "ToolkitWoodCartPivotWalk".equals(node.getName())
            )
                for (track in node.getMainAnimationTracks()) {
                    val side =
                        when (track.getName() ?: throw NullPointerException()) {
                            "Bob_StrafeNoAim_Left",
                            "Bob_StrafeNoAim_Right",
                            "Toolkit_WoodCartPivot_Left",
                            "Toolkit_WoodCartPivot_Right",
                            "Toolkit_CartPivot_StrafeLeft",
                            "Toolkit_CartPivot_StrafeRight",
                            "Toolkit_CartPivot_WoodLeft",
                            "Toolkit_CartPivot_WoodRight" -> true
                            else -> false
                        }
                    if (!side) continue
                    val blend = track.getBlendWeight()
                    if (blend.isFinite() && blend > 0) weight += blend
                }
        }
        val t = Math.min(1.0, weight / .2).toFloat()
        // shortcut: B42 Strafe/backward blend needs 8.5 cm of shaft clearance; recalibrate for
        // another rig/clip.
        return -.085f * t * t * (3 - 2 * t)
    }

    @JvmStatic
    fun releaseSideShift(current: Float, target: Float, seconds: Double): Float {
        if (!seconds.isFinite() || seconds <= 0) return Math.min(current, target)
        val released = current * Math.exp(-Math.min(.1, seconds) / .15).toFloat()
        return Math.min(target, if (released < -.0001f) released else 0f)
    }

    @JvmStatic
    fun woodenBodyShift(gait: Float, x: Float, z: Float): Float = woodenBodyShift(gait, x, z, 1f)

    @JvmStatic
    fun woodenBodyShift(gait: Float, x: Float, z: Float, reserveWeight: Float): Float {
        if (!x.isFinite() || !z.isFinite()) return gait
        if (!reserveWeight.isFinite() || reserveWeight < 0 || reserveWeight > 1) return gait
        // shortcut: B42 idle pelvis and shaft clearance; recalibrate this envelope for another
        // rig/stance.
        val body = z - .0109462375f - 3 * Math.abs(x + 4.6785715e-7f)
        // This is a position envelope, not a motion amplifier: the former 5mm
        // trigger inserted 25mm of reserve and magnified a small gait sway.
        // Its reserve now enters through the same native fast-pose blend above.
        // Retain the measured intrusion inside the fast pose's available corridor.
        // Walk has legitimate pelvis sway too: its proxy must not keep the full
        // fast correction until the final track vanishes, then release it at once.
        // Fade the existing maximum corridor, rather than multiplying every
        // measured intrusion and weakening protection throughout the whole blend.
        val envelope = Math.max(-MAX_FAST_CLEARANCE * reserveWeight, body - .025f * reserveWeight)
        return Math.max(-MAX_FAST_CLEARANCE, Math.min(gait, envelope))
    }

    @JvmStatic
    fun woodenGaitShift(nodes: Iterable<LiveAnimNode?>?): Float {
        var shift = 0.0
        for (entry in nodes ?: throw NullPointerException()) {
            val node = entry ?: throw NullPointerException()
            val offset =
                if (
                    "ToolkitCartPivotRun".equals(node.getName()) ||
                        "ToolkitWoodCartBraceRun".equals(node.getName())
                )
                    -.12f
                else if (
                    "ToolkitCartPivotSprint".equals(node.getName()) ||
                        "ToolkitWoodCartBraceSprint".equals(node.getName())
                )
                    -.05f
                else 0f
            if (offset != 0f)
                for (track in node.getMainAnimationTracks()) {
                    val blend = track.getBlendWeight()
                    if (blend.isFinite() && blend > 0) shift += offset * blend
                }
        }
        return Math.max(-.12, shift).toFloat()
    }

    /** Visual correction follows the rendered Run tracks through their fade-out. */
    @JvmStatic
    fun runningWeight(character: IsoGameCharacter?): Float {
        if (character == null) return 0f
        val animator = character.getAdvancedAnimator()
        return if (animator == null || animator.getRootLayer() == null) 0f
        else runningWeight(animator.getRootLayer().getLiveAnimNodes())
    }

    @JvmStatic
    fun runningWeight(nodes: Iterable<LiveAnimNode?>?): Float {
        var weight = 0.0
        for (entry in nodes ?: throw NullPointerException()) {
            val node = entry ?: throw NullPointerException()
            if (!"ToolkitCartPivotRun".equals(node.getName())) continue
            for (track in node.getMainAnimationTracks()) {
                val blend = track.getBlendWeight()
                if (blend.isFinite() && blend > 0) weight += blend
            }
        }
        return Math.min(1.0, weight).toFloat()
    }

    /** Directional authored clips spend the same root budget as the native gait field. */
    @JvmStatic
    fun scale(player: IsoPlayer?, stepX: Float, stepY: Float): Float {
        val sprint = player != null && player.isSprinting()
        val base = if (sprint) .96f else 1.04f
        if (player == null) return base
        val node = pivotNode(player) ?: return base
        val injury = CartInjury.blend(player, node)
        val desired = targetSpeed(player, stepX, stepY)
        val current = blendedSpeed(node, stepX, stepY, ::clip, injury)
        return if (desired.isFinite() && current > 1e-6f) Math.min(2.5f, desired / current)
        else base
    }

    private fun clip(name: String?): AnimationClip? =
        try {
            ModelManager.instance.getAnimationClip(name)
        } catch (notLoaded: NullPointerException) {
            // ModelManager has no animation mesh while loading or leaving a world.
            null
        }

    private fun blendedSpeed(
        node: AnimNode?,
        stepX: Float,
        stepY: Float,
        clips: Function<String?, AnimationClip?>?,
    ): Float = blendedSpeed(node, stepX, stepY, clips, null)

    @JvmStatic
    fun blendedSpeed(
        node: AnimNode?,
        stepX: Float,
        stepY: Float,
        clips: Function<String?, AnimationClip?>?,
        injury: CartInjury.Blend?,
    ): Float {
        if (Math.hypot(stepX.toDouble(), stepY.toDouble()) < 1e-6) return Float.NaN
        val root = fieldVelocity(node, stepX, stepY, clips, injury) ?: return Float.NaN
        return Math.hypot(root.x, root.y).toFloat()
    }

    private fun fieldVelocity(
        node: AnimNode?,
        stepX: Float,
        stepY: Float,
        clips: Function<String?, AnimationClip?>?,
        injury: CartInjury.Blend?,
    ): Velocity? {
        if (
            node == null ||
                !stepX.isFinite() ||
                !stepY.isFinite() ||
                clips == null ||
                node.blend2dPicker == null ||
                node.blendTris == null ||
                node.blendTris.isEmpty()
        )
            return null
        node.blend2dPicker.Pick(stepX, stepY, picks)
        if (picks.numNodes < 1 || picks.numNodes > 3) return null
        var x = 0.0
        var y = 0.0
        for (i in 0 until picks.numNodes) {
            val blend = if (i == 0) picks.node1 else if (i == 1) picks.node2 else picks.node3
            var weight = if (i == 0) picks.scale1 else if (i == 1) picks.scale2 else picks.scale3
            if (!weight.isFinite()) return null
            // Match AnimLayer.applyBlendField's cutoff, including edge rounding.
            weight = if (weight < 1e-4f) 0f else Math.min(1f, weight)
            if (weight == 0f) continue
            if (blend == null) return null
            val clip = clips.apply(blend.animName) ?: return null
            val velocity =
                velocity(clip, node.getDeferredBoneName(), node.getDeferredBoneAxis())
                    ?: return null
            if (injury != null && injury.forward == blend.animName) {
                val nativeVelocity = injuryVelocity(node, injury, clips) ?: return null
                x += weight * (velocity.x * (1 - injury.amount) + nativeVelocity.x * injury.amount)
                y += weight * (velocity.y * (1 - injury.amount) + nativeVelocity.y * injury.amount)
            } else {
                x += weight * velocity.x
                y += weight * velocity.y
            }
        }
        return Velocity(node.getDeferredBoneName(), node.getDeferredBoneAxis(), x, y)
    }

    @JvmStatic
    fun validClip(node: AnimNode, name: String?): Boolean =
        velocity(clip(name), node.getDeferredBoneName(), node.getDeferredBoneAxis()) != null

    private fun injuryVelocity(
        node: AnimNode,
        injury: CartInjury.Blend,
        clips: Function<String?, AnimationClip?>?,
    ): Velocity? {
        var x = 0.0
        var y = 0.0
        val entries = arrayOf(injury.first, injury.second, injury.third)
        val weights = floatArrayOf(injury.a, injury.b, injury.c)
        for (i in entries.indices) {
            val entry = entries[i] ?: continue
            if (weights[i] == 0f) continue
            val velocity =
                velocity(
                    (clips ?: throw NullPointerException()).apply(entry.animName),
                    node.getDeferredBoneName(),
                    node.getDeferredBoneAxis(),
                ) ?: return null
            x += weights[i] * velocity.x
            y += weights[i] * velocity.y
        }
        return Velocity(node.getDeferredBoneName(), node.getDeferredBoneAxis(), x, y)
    }

    private fun velocity(clip: AnimationClip?, bone: String?, axis: BoneAxis?): Velocity? {
        if (clip == null) return null
        var cached = velocities[clip]
        if (cached == null || !Objects.equals(cached.bone, bone) || cached.axis !== axis) {
            var x = Double.NaN
            var y = Double.NaN
            val duration = clip.getDuration()
            if (duration > 0 && duration.isFinite() && bone != null && axis != null) {
                try {
                    clip.getTotalTranslation(bone, axis, translation)
                    x = (translation.x / duration).toDouble()
                    y = (translation.y / duration).toDouble()
                } catch (invalidRoot: IndexOutOfBoundsException) {
                    // Missing root frames cannot provide a safe compensation factor.
                } catch (invalidRoot: NullPointerException) {
                    // Missing root frames cannot provide a safe compensation factor.
                }
            }
            cached = Velocity(bone, axis, x, y)
            velocities[clip] = cached
        }
        return if (cached.x.isFinite() && cached.y.isFinite()) cached else null
    }
}
