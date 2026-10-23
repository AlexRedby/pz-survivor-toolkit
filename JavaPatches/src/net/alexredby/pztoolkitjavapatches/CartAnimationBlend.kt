package net.alexredby.pztoolkitjavapatches

import java.util.Collections
import java.util.ArrayList
import java.util.IdentityHashMap
import java.util.function.Predicate
import zombie.characters.IsoPlayer
import zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode
import zombie.core.skinnedmodel.animation.AnimationTrack
import zombie.core.skinnedmodel.animation.LiveAnimationTrackEntries
import zombie.core.skinnedmodel.model.SkinningBone

/** Conservative fast-pose presence along the displayed Spine's native transform chain. */
internal object CartAnimationBlend {
    private const val MIN_WEIGHT = .001f
    private val entries = ThreadLocal.withInitial(::LiveAnimationTrackEntries)

    @JvmStatic
    fun fastWeight(player: IsoPlayer?): Float {
        if (player == null) return 0f
        val animator = player.getAdvancedAnimator() ?: return 0f
        val fast = fastTracks(animator)
        if (fast.isEmpty()) return 0f
        if (player.hasAnimationPlayer()) {
            val animation = player.getAnimationPlayer()
            if (animation != null && animation.hasSkinningData()) {
                val spine = animation.getSkinningData().boneIndices["Bip01_Spine"]
                if (spine != null && spine >= 0 && spine < animation.getModelTransformsCount() && animation.getMultiTrack() != null) {
                    val weight = fastWeight(animation.getMultiTrack().getTracks(), animation.getSkinningData().getBoneAt(spine), fast::contains)
                    if (weight.isFinite()) return weight
                }
            }
        }
        // Missing native tracks/skeleton cannot prove retirement. Use conservative
        // raw ownership of the same identified root and masked fast tracks.
        var raw = 0.0
        for (track in fast) {
            val weight = track.getBlendWeight()
            if (weight.isFinite() && weight > 0) raw += weight
        }
        return Math.min(1.0, raw).toFloat()
    }

    /**
     * Model-space Spine still contains an outgoing pelvis/root transform after
     * an incoming masked Walk completely owns the local Spine. Keep the largest
     * native fast share along that chain until every contributor has retired.
     * This is presence, not a summed pose weight or a geometric clearance bound.
     */
    @JvmStatic
    fun fastWeight(tracks: List<AnimationTrack?>?, spine: SkinningBone?, fast: Predicate<AnimationTrack>?): Float {
        if (spine == null) return Float.NaN
        var weight = 0f
        var bone: SkinningBone? = spine
        while (bone != null) {
            val local = fastWeight(tracks, bone.index, fast)
            if (!local.isFinite()) return Float.NaN
            weight = Math.max(weight, local)
            bone = bone.parent
        }
        return weight
    }

    @JvmStatic
    fun fastTracks(animator: AdvancedAnimator?): Set<AnimationTrack> {
        val owner = animator ?: throw NullPointerException()
        val nodes = ArrayList<LiveAnimNode>()
        if (owner.getRootLayer() != null) nodes.addAll(owner.getRootLayer().getLiveAnimNodes())
        // Both masked hand layers can own the entire Spine while the root Run is
        // still live. Classifying only root identities incorrectly retires clearance.
        for (i in 0 until owner.getSubLayerCount()) {
            val layer = owner.getSubLayerAt(i)
            if (layer != null) nodes.addAll(layer.getLiveAnimNodes())
        }
        val fast = Collections.newSetFromMap(IdentityHashMap<AnimationTrack, Boolean>())
        for (node in nodes) {
            val fastNode = when (node.getName() ?: throw NullPointerException()) {
                "ToolkitCartPivotRun", "ToolkitCartPivotSprint", "ToolkitWoodCartBraceRun", "ToolkitWoodCartBraceSprint",
                "ToolkitCartRun", "ToolkitCartSprint", "ToolkitCartRunLeft", "ToolkitCartRunRight", "ToolkitCartSprintLeft", "ToolkitCartSprintRight" -> true
                else -> false
            }
            if (fastNode) for (track in node.getMainAnimationTracks()) fast.add(track)
            val transitionOwner = fastNode || when (node.getName() ?: throw NullPointerException()) {
                "ToolkitCartIdle", "ToolkitCartIdleLeft", "ToolkitCartIdleRight", "ToolkitCartWalk", "ToolkitCartWalkLeft", "ToolkitCartWalkRight",
                "ToolkitCartPivotWalk", "ToolkitWoodCartPivotWalk" -> true
                else -> false
            }
            val transition = node.getTransitionInTrack()
            if (transitionOwner && transition != null) {
                val name = transition.getName()
                if (CartLegPace.brakeClip(name) || "Bob_Cart_WalkToRun".equals(name) || "Bob_Cart_WalkToSprint".equals(name)) fast.add(transition)
            }
        }
        // The shared upper brace is identical in Walk and fast gaits. Promoting
        // its full weight while any outgoing fast track remains would pin the
        // reserve to one, then snap it to zero. The ancestor chain already sees
        // the actual outgoing root/pelvis underneath the brace's Spine mask.
        return fast
    }

    /**
     * The caller supplies a valid skeleton bone index. Returns NaN when native
     * allocation cannot be established. Non-fast tracks still consume the same
     * bone's budget; a fast identity absent from tracks is not rendered.
     * Node activity/isPlaying do not replace native blend weights.
     *
     * This matches the normal-frame B42.21 allocator. The private first-frame
     * underweight normalization flag is deliberately not guessed. A Spine-local
     * share does not describe ancestor masks or prove complete geometric clearance.
     */
    @JvmStatic
    fun fastWeight(tracks: List<AnimationTrack?>?, bone: Int, fast: Predicate<AnimationTrack>?): Float {
        if (tracks == null || bone < 0 || fast == null) return Float.NaN
        val scratch = entries.get()
        try {
            for (track in tracks) {
                if (track == null) return Float.NaN
                val weight = track.getBlendWeight()
                if (!weight.isFinite() || weight < 0 || track.getLayerIdx() < 0 || track.getLayerIdx() >= 16) return Float.NaN
                if (weight >= MIN_WEIGHT) {
                    val mask = track.getBoneWeight(bone)
                    if (!mask.isFinite() || mask < 0) return Float.NaN
                }
            }
            scratch.setTracks(tracks, MIN_WEIGHT, false)
            var remaining = 1f
            var weight = 0f
            var i = scratch.count() - 1
            while (i >= 0 && remaining > MIN_WEIGHT) {
                val entry = scratch.get(i)
                val mask = entry.getTrack().getBoneWeight(bone)
                if (mask <= MIN_WEIGHT) { i--; continue }
                val raw = entry.getBlendWeight() * mask
                if (!raw.isFinite()) return Float.NaN
                if (raw <= MIN_WEIGHT) { i--; continue }
                val effective = Math.max(0f, Math.min(remaining, raw))
                remaining = Math.max(0f, remaining - raw)
                if (fast.test(entry.getTrack())) weight += effective
                i--
            }
            return Math.max(0f, Math.min(1f, weight))
        } catch (unavailableBone: IndexOutOfBoundsException) {
            return Float.NaN
        } finally {
            scratch.clear()
        }
    }
}
