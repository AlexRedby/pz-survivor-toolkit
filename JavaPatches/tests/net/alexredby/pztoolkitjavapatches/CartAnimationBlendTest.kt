package net.alexredby.pztoolkitjavapatches

import java.util.HashMap
import org.lwjgl.util.vector.Matrix4f
import org.lwjgl.util.vector.Vector3f
import zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator
import zombie.core.skinnedmodel.advancedanimation.AnimBoneWeight
import zombie.core.skinnedmodel.advancedanimation.AnimLayer
import zombie.core.skinnedmodel.advancedanimation.AnimNode
import zombie.core.skinnedmodel.advancedanimation.AnimState
import zombie.core.skinnedmodel.advancedanimation.AnimTransition
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode
import zombie.core.skinnedmodel.animation.AnimationClip
import zombie.core.skinnedmodel.animation.AnimationTrack
import zombie.core.skinnedmodel.animation.Keyframe
import zombie.core.skinnedmodel.model.SkinningData

/** Exercises the real native entry sorter with controlled public track/mask inputs. */
object CartAnimationBlendTest {
    private val SKINNING = rig()

    private fun rig(): SkinningData {
        val identity = Matrix4f()
        val bones = listOf(identity, identity, identity, identity)
        return SkinningData(
            HashMap(),
            bones,
            bones,
            bones,
            listOf(-1, 0, 1, 2),
            HashMap(mapOf("root" to 0, "pelvis" to 1, "waist" to 2, "Bip01_Spine" to 3)),
        )
    }

    private fun track(name: String, weight: Float): AnimationTrack = track(name, weight, 1f, 11, 0)

    private fun track(
        name: String,
        weight: Float,
        boneMask: Float,
        priority: Int,
        depth: Int,
    ): AnimationTrack {
        val start = Keyframe()
        val end = Keyframe()
        start.boneName = "Bip01_Spine"
        end.boneName = "Bip01_Spine"
        start.position = Vector3f()
        end.position = Vector3f()
        end.time = 1f
        val track = AnimationTrack.alloc()
        track.startClip(AnimationClip(1f, listOf(start, end), name, true), true, 0f)
        track.priority = priority
        track.setBlendWeight(weight)
        mask(track, boneMask)
        if (depth > 0) {
            var layer = AnimLayer.alloc(null, null)
            for (i in 0 until depth) layer = AnimLayer.alloc(layer, null, null)
            track.setAnimLayer(layer)
        }
        return track
    }

    private fun mask(track: AnimationTrack, weight: Float) {
        track.setBoneWeights(listOf(AnimBoneWeight("Bip01_Spine", weight)))
        track.initBoneWeights(SKINNING)
    }

    private fun weight(tracks: List<AnimationTrack?>, vararg fast: AnimationTrack): Float {
        val identities = java.util.Set.of(*fast)
        return CartAnimationBlend.fastWeight(tracks, 3, identities::contains)
    }

    private fun chainMask(
        track: AnimationTrack,
        root: Float,
        pelvis: Float,
        waist: Float,
        spine: Float,
    ) {
        val weights = ArrayList<AnimBoneWeight>()
        val names = arrayOf("root", "pelvis", "waist", "Bip01_Spine")
        val values = floatArrayOf(root, pelvis, waist, spine)
        for (i in names.indices) {
            val weight = AnimBoneWeight(names[i], values[i])
            weight.includeDescendants = false
            weights.add(weight)
        }
        track.setBoneWeights(weights)
        track.initBoneWeights(SKINNING)
    }

    private fun chainWeight(tracks: List<AnimationTrack?>, vararg fast: AnimationTrack): Float {
        val identities = java.util.Set.of(*fast)
        return CartAnimationBlend.fastWeight(
            tracks,
            SKINNING.getBone("Bip01_Spine"),
            identities::contains,
        )
    }

    private fun close(actual: Float, expected: Number, message: String) {
        if (!actual.isFinite() || Math.abs(actual - expected.toDouble()) > 1e-6)
            throw AssertionError("$message: $actual != $expected")
    }

    private fun unavailable(result: Float, message: String) {
        if (!result.isNaN()) throw AssertionError("$message: $result")
    }

    private fun pickerOverlap() {
        val forward = track("WalkForward", .82f)
        val idle = track("WalkIdle", .82f)
        forward.setBlendFieldWeight(.8f)
        idle.setBlendFieldWeight(.2f)
        val run = track("RunForward", .5644444f)
        close(
            weight(listOf(run, idle, forward), run),
            .344,
            "overlapping raw weights above one must clip Run after the larger Walk track",
        )
        close(
            weight(listOf(forward, run, idle), run),
            .344,
            "allocation must use native sort order rather than caller order",
        )
        close(
            forward.getBlendWeight(),
            .656,
            "ownership calculation must not mutate native picker weights",
        )
        close(
            run.getBlendWeight(),
            .5644444,
            "ownership calculation must not mutate an outgoing track",
        )
        run.setBlendWeight(2f)
        close(
            weight(listOf(forward, run, idle), run),
            1,
            "raw fast weight above one cannot exceed its bone budget",
        )
        run.setBlendWeight(.8f)
        val sprint = track("SprintForward", .7f)
        close(
            weight(listOf(forward, run, sprint, idle), run, sprint),
            1,
            "native Run/Sprint overlap shares one clipped budget",
        )
    }

    private fun masksPriorityAndOutgoing() {
        val run = track("Run", .8f, .5f, 11, 0)
        val brace = track("Brace", .9f, 1f, 12, 0)
        close(weight(listOf(run), run), .4, "Spine bone mask multiplies the entry weight")
        close(
            weight(listOf(run, brace), run),
            .1,
            "higher-priority unknown pose consumes Spine budget first",
        )
        mask(brace, 0f)
        close(
            weight(listOf(run, brace), run),
            .4,
            "masked upper pose cannot hide the Spine's fast share",
        )
        mask(brace, .5f)
        close(
            weight(listOf(run, brace), run),
            .4,
            "a partial higher-priority mask leaves sufficient lower budget",
        )
        val upper = track("UpperLayer", .8f, 1f, 1, 1)
        close(
            weight(listOf(run, upper), run),
            .2,
            "native layer ordering precedes numeric track priority",
        )
        // Native continues drawing weighted outgoing poses even when their clips are paused.
        run.isPlaying = false
        close(
            weight(listOf(run), run),
            .4,
            "outgoing track activity must not retire a displayed pose",
        )
        val absent = track("MissingFast", 1f)
        close(
            weight(listOf(run), absent),
            0,
            "a fast identity absent from the actual multi-track is not displayed",
        )
        close(weight(listOf(run)), 0, "unknown identities do not become fast by clip name")
    }

    private fun thresholdsAndInvalidInputs() {
        val run = track("Run", .000999f)
        close(weight(listOf(run), run), 0, "native threshold omits negligible entries")
        run.setBlendWeight(.001f)
        close(weight(listOf(run), run), 0, "bone contribution at exactly the threshold is omitted")
        run.setBlendWeight(.00101f)
        close(weight(listOf(run), run), .00101, "contribution above threshold survives")
        run.setBlendWeight(.9f)
        mask(run, .001f)
        close(weight(listOf(run), run), 0, "mask at native threshold cannot contribute")
        mask(run, 1f)
        for (invalid in floatArrayOf(Float.NaN, Float.POSITIVE_INFINITY, -.1f)) {
            run.setBlendWeight(invalid)
            unavailable(
                weight(listOf(run), run),
                "invalid raw weight must request conservative fallback",
            )
            run.setBlendWeight(.5f)
            if (invalid >= 0 || invalid.isNaN()) {
                mask(run, invalid)
                unavailable(
                    weight(listOf(run), run),
                    "invalid bone mask must request conservative fallback",
                )
            }
            mask(run, 1f)
        }
        unavailable(CartAnimationBlend.fastWeight(null, 3) { true }, "missing multi-track")
        unavailable(CartAnimationBlend.fastWeight(listOf(run), -1) { true }, "negative bone")
        unavailable(
            CartAnimationBlend.fastWeight(listOf(run), 3, null),
            "missing identity predicate",
        )
        unavailable(weight(listOf(run, null), run), "missing native track")
        unavailable(weight(listOf(track("BadLayer", 1f, 1f, 11, 16))), "invalid native layer")
        close(weight(emptyList()), 0, "empty actual multi-track has no fast contribution")
        close(weight(listOf(run), run), .5, "failed checks must clear thread-local native entries")
        close(
            CartAnimationBlend.fastWeight(null as zombie.characters.IsoPlayer?),
            0,
            "missing player",
        )
    }

    private fun outgoingAncestorPresence() {
        val sprint = track("Sprint", .5f)
        chainMask(sprint, 1f, 1f, 1f, 1f)
        val walk = track("WalkUpper", 1f, 1f, 12, 0)
        close(
            weight(listOf(sprint, walk), sprint),
            0,
            "incoming Walk can completely own local Spine",
        )
        close(
            chainWeight(listOf(sprint, walk), sprint),
            .5,
            "outgoing pelvis/root still contributes to model-space Spine after its local fast share retires",
        )
        val upper = track("FastUpper", .4f, 1f, 13, 0)
        sprint.setBlendWeight(.7f)
        close(
            chainWeight(listOf(sprint, walk, upper), sprint, upper),
            .7,
            "chain presence takes the maximum instead of counting the same pose at several joints",
        )
        val unknown = track("UnknownFullBody", 1f, 1f, 14, 0)
        chainMask(unknown, 1f, 1f, 1f, 1f)
        close(
            chainWeight(listOf(sprint, walk, upper, unknown), sprint, upper),
            0,
            "higher-priority full-body owner can retire the entire fast chain",
        )
        sprint.setBlendWeight(0f)
        upper.setBlendWeight(0f)
        close(
            chainWeight(listOf(sprint, walk, upper), sprint, upper),
            0,
            "ordinary Walk has no reserve once every native fast contributor retires",
        )
        sprint.setBlendWeight(.5f)
        chainMask(sprint, 1f, Float.NaN, 1f, 1f)
        unavailable(
            chainWeight(listOf(sprint, walk), sprint),
            "invalid ancestor mask requests conservative fallback",
        )
        unavailable(
            CartAnimationBlend.fastWeight(
                listOf(sprint),
                null as zombie.core.skinnedmodel.model.SkinningBone?,
            ) {
                true
            },
            "missing chain",
        )
        close(walk.getBlendWeight(), 1, "chain inspection must not change native track weights")
    }

    private fun node(layer: AnimLayer, name: String, track: AnimationTrack): LiveAnimNode {
        val source = AnimNode()
        source.name = name
        val node = LiveAnimNode.alloc(layer, source)
        track.setAnimLayer(layer)
        node.addMainTrack(track)
        node.setActive(false)
        layer.getLiveAnimNodes().add(node)
        return node
    }

    private fun classified(animator: AdvancedAnimator, tracks: List<AnimationTrack>): Float {
        val fast = CartAnimationBlend.fastTracks(animator)
        return CartAnimationBlend.fastWeight(tracks, 3, fast::contains)
    }

    private fun allMaskedLayersAndTransitions() {
        val animator = AdvancedAnimator()
        animator.init(null, null)
        val state = AnimState()
        state.name = "run"
        val leftState = AnimState()
        leftState.name = "maskingleft"
        val rightState = AnimState()
        rightState.name = "maskingright"
        animator.setState(state, listOf(leftState, rightState))
        if (animator.getSubLayerCount() != 2)
            throw AssertionError("fixture must create both actual animator sublayers")
        val root = track("Bob_Run", 1f)
        val left = track("Bob_Cart_Run", .50001f)
        val right = track("Bob_Cart_Run", .50001f)
        node(animator.getRootLayer(), "ToolkitCartPivotRun", root)
        val leftNode = node(animator.getSubLayerAt(0), "ToolkitCartRunLeft", left)
        val rightNode = node(animator.getSubLayerAt(1), "ToolkitCartRunRight", right)
        val tracks = ArrayList(listOf(root, left, right))
        close(weight(tracks, root), 0, "masked upper layers replace root Run at the Spine")
        close(
            classified(animator, tracks),
            1,
            "both masked Run layers must retain fast ownership when root contribution is zero",
        )
        left.setBlendWeight(.15f)
        right.setBlendWeight(.25f)
        root.setBlendWeight(.2f)
        close(
            classified(animator, tracks),
            .6,
            "inactive outgoing root and hand-layer poses fade by their actual contributions",
        )
        root.setBlendWeight(0f)
        left.setBlendWeight(0f)
        right.setBlendWeight(0f)
        close(
            classified(animator, tracks),
            0,
            "all fast layers must retire after their native fade",
        )
        val sprint = track("Bob_Cart_Sprint", 1f)
        node(animator.getSubLayerAt(0), "ToolkitCartSprintLeft", sprint)
        tracks.add(sprint)
        mask(sprint, 0f)
        close(
            classified(animator, tracks),
            0,
            "actual Sprint hand-only masks cannot invent Spine ownership",
        )
        mask(sprint, 1f)
        close(
            classified(animator, tracks),
            1,
            "a Sprint sublayer with actual Spine weight is recognized by node identity",
        )
        sprint.setBlendWeight(0f)
        for (owner in listOf(leftNode, rightNode)) for (name in
            listOf("Bob_Cart_WalkToRun", "Bob_Cart_WalkToSprint")) {
            val transition = track(name, .4f)
            transition.setAnimLayer(
                if (owner === leftNode) animator.getSubLayerAt(0) else animator.getSubLayerAt(1),
            )
            owner.startTransitionIn(AnimNode(), AnimTransition(), transition)
            tracks.add(transition)
            close(
                classified(animator, tracks),
                .4,
                "known upper fast entry transition retains the envelope before main playback",
            )
            transition.setBlendWeight(0f)
        }
        val unknown = track("Bob_Cart_Run", 1f)
        node(animator.getSubLayerAt(1), "UnknownModRun", unknown)
        tracks.add(unknown)
        root.setBlendWeight(1f)
        close(
            classified(animator, tracks),
            0,
            "an unknown upper owner consumes the budget without clip-name promotion",
        )
        unknown.setBlendWeight(0f)
        val brace = track("Toolkit_WoodCartBrace", 1f)
        node(animator.getSubLayerAt(1), "ToolkitWoodCartBraceRight", brace)
        tracks.add(brace)
        chainMask(root, 1f, 1f, 1f, 1f)
        for (outgoing in floatArrayOf(1f, .5f, .01f, .00101f, .0001f, 0f)) {
            root.setBlendWeight(outgoing)
            val fast = CartAnimationBlend.fastTracks(animator)
            close(
                CartAnimationBlend.fastWeight(
                    tracks,
                    SKINNING.getBone("Bip01_Spine"),
                    fast::contains,
                ),
                if (outgoing > .001f) outgoing else 0f,
                "shared brace must not pin the outgoing fast envelope to one",
            )
            close(
                classified(animator, tracks),
                0,
                "shared brace is not a fast-pose identity at the local Spine",
            )
        }
        root.setBlendWeight(0f)
        close(
            classified(animator, tracks),
            0,
            "ordinary Walk brace cannot acquire a new fast reserve",
        )
        for (name in
            listOf(
                "Bob_RunToStop2H_Heavy",
                "Bob_SprintToStop2h_Heavy",
                "Toolkit_CartPivot_StopRun",
                "Toolkit_CartPivot_StopSprint",
            )) {
            val idle = node(animator.getRootLayer(), "ToolkitCartIdle", track("Idle", 0f))
            val stop = track(name, .4f)
            stop.setAnimLayer(animator.getRootLayer())
            idle.startTransitionIn(AnimNode(), AnimTransition(), stop)
            close(
                classified(animator, listOf(stop)),
                .4,
                "native and canonical heavy stops retain actual fast ownership",
            )
            stop.setBlendWeight(0f)
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        pickerOverlap()
        masksPriorityAndOutgoing()
        thresholdsAndInvalidInputs()
        outgoingAncestorPresence()
        allMaskedLayersAndTransitions()
        println("CART_ANIMATION_BLEND_PASS")
    }
}
