package net.alexredby.pztoolkitjavapatches

import java.util.HashMap
import org.lwjgl.util.vector.Vector3f
import sun.misc.Unsafe
import zombie.characters.IsoPlayer
import zombie.core.skinnedmodel.ModelManager
import zombie.core.skinnedmodel.advancedanimation.AnimNode
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlend
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlendPicker
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlendTriangle
import zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator
import zombie.core.skinnedmodel.advancedanimation.AnimLayer
import zombie.core.skinnedmodel.advancedanimation.AnimTransition
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode
import zombie.core.skinnedmodel.animation.AnimationClip
import zombie.core.skinnedmodel.animation.AnimationPlayer
import zombie.core.skinnedmodel.animation.AnimationMultiTrack
import zombie.core.skinnedmodel.animation.AnimationTrack
import zombie.core.skinnedmodel.animation.BoneAxis
import zombie.core.skinnedmodel.animation.Keyframe
import zombie.core.skinnedmodel.model.SkinningData
import zombie.core.skinnedmodel.model.ModelMesh
import zombie.iso.Vector2

object CartLegPaceTest {
    private class Player : IsoPlayer(null, null, 0, 0, 0) {
        @JvmField var animation: AnimationPlayer? = null
        @JvmField var animator: AdvancedAnimator? = null
        @JvmField var loaded = false
        @JvmField var run = false
        @JvmField var sprint = false
        @JvmField var stepX = 0f
        @JvmField var stepY = 0f
        @JvmField var pace = 0f
        override fun setVariable(name: String?, value: Float): zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot? {
            if ((name ?: throw NullPointerException()).equals("ToolkitCartStepX")) stepX = value
            if (name.equals("ToolkitCartStepY")) stepY = value
            if (name.equals("ToolkitCartLegPace")) pace = value
            return null
        }
        override fun hasAnimationPlayer(): Boolean = loaded
        override fun isRunning(): Boolean = run
        override fun isSprinting(): Boolean = sprint
        override fun getAnimationPlayer(): AnimationPlayer? = animation
        override fun getAdvancedAnimator(): AdvancedAnimator? = animator
    }
    private fun nativePelvisBinding() {
        val unsafeField = Unsafe::class.java.getDeclaredField("theUnsafe"); unsafeField.isAccessible = true
        val unsafe = unsafeField.get(null) as Unsafe
        val player = unsafe.allocateInstance(Player::class.java) as Player
        val animation = unsafe.allocateInstance(AnimationPlayer::class.java) as AnimationPlayer
        player.animation = animation; player.loaded = true; player.run = true
        player.animator = AdvancedAnimator()
        val layer = AnimLayer.alloc(player, player.animator)
        val root = AdvancedAnimator::class.java.getDeclaredField("rootLayer"); root.isAccessible = true; root.set(player.animator, layer)
        val fast = live("ToolkitCartRun", true, clip("Bob_Run", 1, 0, 0, "Translation_Data"))
        fast.getMainAnimationTrackAt(0).setBlendWeight(1f)
        layer.getLiveAnimNodes().add(fast)
        val skinning = AnimationPlayer::class.java.getDeclaredField("skinningData"); skinning.isAccessible = true
        val transforms = AnimationPlayer::class.java.getDeclaredField("modelTransforms"); transforms.isAccessible = true
        close(CartLegPace.woodenGaitShift(player), 0, "unloaded native skinning keeps gait fallback")
        val identity = org.lwjgl.util.vector.Matrix4f()
        val bones = listOf(identity, identity)
        val actor = SkinningData(HashMap(), bones, bones, bones, listOf(-1, 0), HashMap(mapOf("root" to 0, "Bip01_Spine" to 1)))
        skinning.set(animation, actor)
        val pose = org.lwjgl.util.vector.Matrix4f()
        pose.m03 = .01f; pose.m23 = -.02f
        // Opposite storage entries deliberately disagree so reading untransposed translation cannot pass.
        pose.m30 = .8f; pose.m32 = .9f
        val palette = arrayOf(identity, pose); transforms.set(animation, palette)
        val before = FloatArray(16); pose.store(java.nio.FloatBuffer.wrap(before))
        close(CartLegPace.woodenGaitShift(player), -.08594764, "native transposed Spine x/z drive shaft clearance")
        val displayed = org.joml.Vector3f(0f, .5f, .0109462375f)
        close(CartLegPace.woodenGaitShift(player, displayed), -.025, "clearance follows the displayed snapshot instead of a newer live pose")
        if (!displayed.equals(org.joml.Vector3f(0f, .5f, .0109462375f))) throw AssertionError("clearance changed the displayed Spine input")
        val after = FloatArray(16); pose.store(java.nio.FloatBuffer.wrap(after))
        if (!before.contentEquals(after)) throw AssertionError("pelvis binding changed the native model pose")
        pose.m03 = 0f; pose.m23 = -.03f
        close(CartLegPace.woodenGaitShift(player), -.06594764, "native pelvis movement updates clearance independently of gait")
        player.run = false
        close(CartLegPace.woodenGaitShift(player), -.06594764, "cleared gait flags do not retire the displayed running pose")
        fast.getMainAnimationTrackAt(0).setBlendWeight(.25f)
        close(CartLegPace.woodenGaitShift(player), -.04719764, "only reserve fades; already blended body intrusion remains protected")
        layer.getLiveAnimNodes().remove(fast)
        close(CartLegPace.woodenGaitShift(player), 0, "ordinary Walk retains native cart position despite pelvis sway")
        val side = live("ToolkitCartPivotWalk", true, clip("Bob_StrafeNoAim_Left", 1, 0, 0, "Translation_Data"))
        layer.getLiveAnimNodes().add(side)
        side.getMainAnimationTrackAt(0).setBlendWeight(.347241f)
        pose.m03 = -.02f; pose.m23 = -.005f
        close(CartLegPace.woodenGaitShift(player), -.085, "incoming Strafe keeps the measured thigh clear before full blend")
        close(CartLegPace.woodenFastShift(player), 0, "a side-only clearance cannot promote the walking footprint to Run")
        side.getMainAnimationTrackAt(0).setBlendWeight(1f)
        pose.m03 = -.000058505f; pose.m23 = .008871079f
        close(CartLegPace.woodenGaitShift(player), -.085, "Strafe clearance survives the neutral Spine phase with protruding thigh")
        player.run = true; pose.m03 = .03f; pose.m23 = .014f
        fast.getMainAnimationTrackAt(0).setBlendWeight(1f)
        layer.getLiveAnimNodes().add(fast)
        close(CartLegPace.woodenGaitShift(player), CartLegPace.woodenBodyShift(0f, pose.m03, pose.m23),
            "Strafe overlap cannot reduce the existing fast-pose clothing clearance")
        player.run = false
        layer.getLiveAnimNodes().remove(fast)
        side.setActive(false); side.getMainAnimationTrackAt(0).setBlendWeight(.1f)
        close(CartLegPace.woodenGaitShift(player), -.0425, "outgoing Strafe keeps clearance through the native fade")
        layer.getLiveAnimNodes().remove(side); layer.getLiveAnimNodes().add(fast)
        player.run = true; player.loaded = false
        close(CartLegPace.woodenGaitShift(player), 0, "unavailable animation player keeps gait fallback")
        player.loaded = true; player.animation = null
        close(CartLegPace.woodenGaitShift(player), 0, "missing native animation keeps gait fallback")
        player.animation = animation; actor.boneIndices.remove("Bip01_Spine")
        close(CartLegPace.woodenGaitShift(player), 0, "rig without Spine keeps gait fallback")
        for (index in intArrayOf(-1, 2)) {
            actor.boneIndices["Bip01_Spine"] = index
            close(CartLegPace.woodenGaitShift(player), 0, "invalid Spine index keeps gait fallback")
        }
        actor.boneIndices["Bip01_Spine"] = 1
        for (unloaded in arrayOf(null, emptyArray<org.lwjgl.util.vector.Matrix4f?>(), arrayOf(identity, null))) {
            transforms.set(animation, unloaded)
            close(CartLegPace.woodenGaitShift(player), 0, "unavailable native model pose keeps gait fallback")
        }
    }
    private fun sideClearance() {
        for (name in listOf("Toolkit_CartPivot_StrafeLeft", "Toolkit_CartPivot_StrafeRight", "Toolkit_CartPivot_WoodLeft", "Toolkit_CartPivot_WoodRight")) {
            val side = live("ToolkitWoodCartPivotWalk", false, clip(name, 1, 0, 0, "Translation_Data"))
            side.getMainAnimationTrackAt(0).setBlendWeight(.1f)
            close(CartLegPace.woodenSideShift(listOf(side)), -.0425, "canonical outgoing side clips retain the calibrated shaft envelope")
        }
        val left = live("ToolkitCartPivotWalk", true, clip("Bob_StrafeNoAim_Left", 1, 0, 0, "Translation_Data"))
        val right = live("ToolkitCartPivotWalk", false, clip("Bob_StrafeNoAim_Right", 1, 0, 0, "Translation_Data"))
        val other = live("defaultWalk", true, clip("Bob_StrafeNoAim_Left", 1, 0, 0, "Translation_Data"))
        val forward = live("ToolkitCartPivotWalk", true, clip("Bob_Walk", 1, 0, 0, "Translation_Data"))
        close(CartLegPace.woodenSideShift(listOf(other, forward)), 0, "ordinary clips retain their calibrated cart position")
        val woodLeft = live("ToolkitWoodCartPivotWalk", true, clip("Toolkit_WoodCartPivot_Left", 1, 0, 0, "Translation_Data"))
        val woodRight = live("ToolkitWoodCartPivotWalk", false, clip("Toolkit_WoodCartPivot_Right", 1, 0, 0, "Translation_Data"))
        for (side in listOf(left, right, woodLeft, woodRight)) {
            side.getMainAnimationTrackAt(0).setBlendWeight(.1f)
            close(CartLegPace.woodenSideShift(listOf(side, other, forward)), -.0425, "both native Strafe directions include fade-out")
        }
        close(CartLegPace.woodenSideShift(listOf(left, right)), -.085, "a mirrored handoff retains clearance without doubling it")
        for (invalid in floatArrayOf(Float.NaN, Float.POSITIVE_INFINITY, -.2f)) {
            left.getMainAnimationTrackAt(0).setBlendWeight(invalid)
            close(CartLegPace.woodenSideShift(listOf(left)), 0, "invalid Strafe weights are ignored")
        }
        close(CartLegPace.releaseSideShift(0f, -.085f, 1.0 / 60), -.085, "clearance is acquired before the native thigh can hit a shaft")
        var current = -.085f
        for (tick in 0 until 70) {
            val next = CartLegPace.releaseSideShift(current, 0f, 1.0 / 60)
            if (next < current || next - current > .010) throw AssertionError("Strafe clearance snapped during release")
            current = next
        }
        close(current, 0, "ordinary walking regains its exact calibrated position after release")
        close(CartLegPace.releaseSideShift(-.03f, -.085f, 0.0), -.085, "zero dt cannot postpone required clearance")
        close(CartLegPace.releaseSideShift(-.03f, 0f, Double.NaN), -.03, "invalid dt cannot snap the retained clearance")
    }
    private fun close(actual: Float, expected: Number, message: String) {
        if (!actual.isFinite() || Math.abs(actual - expected.toDouble()) > 1e-5) throw AssertionError("$message: $actual != $expected")
    }
    private fun clip(name: String, duration: Number, x: Number, y: Number, bone: String): AnimationClip {
        val start = Keyframe()
        val end = Keyframe()
        start.boneName = bone; end.boneName = bone
        start.position = Vector3f(); end.position = Vector3f(x.toFloat(), 0f, -y.toFloat()); end.time = duration.toFloat()
        return AnimationClip(duration.toFloat(), listOf(start, end), name, true)
    }
    private fun blend(name: String, x: Float, y: Float): Anim2DBlend = Anim2DBlend().also { it.animName = name; it.posX = x; it.posY = y }
    private fun node(): AnimNode {
        val node = AnimNode()
        val idle = blend("idle", 0f, 0f)
        val forward = blend("forward", 0f, 1f)
        val right = blend("right", 1f, 0f)
        val back = blend("back", 0f, -1f)
        val left = blend("left", -1f, 0f)
        node.blends2d.addAll(listOf(idle, forward, right, back, left))
        val rim = listOf(forward, right, back, left)
        for (i in rim.indices) {
            val triangle = Anim2DBlendTriangle(); triangle.node1 = idle; triangle.node2 = rim[(i + 1) % rim.size]; triangle.node3 = rim[i]
            node.blendTris.add(triangle)
        }
        node.blend2dPicker = Anim2DBlendPicker(); node.blend2dPicker.SetPickTriangles(node.blendTris)
        return node
    }
    private fun blendedSpeed(node: AnimNode, clips: Map<String, AnimationClip>, x: Float, y: Float): Float {
        val pick = node.blend2dPicker.Pick(x, y, Anim2DBlendPicker.PickResults())
        var dx = 0.0; var dy = 0.0
        for (i in 0 until pick.numNodes) {
            val blend = if (i == 0) pick.node1 else if (i == 1) pick.node2 else pick.node3
            val weight = if (i == 0) pick.scale1 else if (i == 1) pick.scale2 else pick.scale3
            if (weight < 1e-4f) continue
            val clip = clips[blend.animName] ?: throw NullPointerException()
            val root = clip.getTotalTranslation("Translation_Data", BoneAxis.Y, Vector2())
            dx += Math.min(1f, weight) * root.x / clip.getDuration(); dy += Math.min(1f, weight) * root.y / clip.getDuration()
        }
        return Math.hypot(dx, dy).toFloat()
    }
    private fun live(name: String, active: Boolean, clip: AnimationClip): LiveAnimNode {
        val source = AnimNode(); source.name = name
        val node = LiveAnimNode.alloc(null, source)
        val track = AnimationTrack.alloc(); track.startClip(clip, true, 0f); track.setSpeedDelta(1.1f)
        track.advance(.25f); track.setBlendWeight(.3f); node.addMainTrack(track); node.setActive(active)
        return node
    }
    private fun transition(layer: AnimLayer, nodeName: String, clipName: String, weight: Float): LiveAnimNode {
        val source = AnimNode(); source.name = nodeName
        val outgoing = AnimNode(); outgoing.name = "ToolkitCartPivotRun"
        val node = LiveAnimNode.alloc(layer, source)
        val track = AnimationTrack.alloc(); track.startClip(clip(clipName, 2, 0, 1, "Translation_Data"), false, 0f); track.setSpeedDelta(.7f)
        if (layer.getAnimationTrack() != null) layer.getAnimationTrack().addTrack(track)
        node.startTransitionIn(outgoing, AnimTransition(), track); node.setTransitionInBlendDelta(weight); layer.getLiveAnimNodes().add(node)
        return node
    }

    private fun brakeTracks() {
        val unsafeField = Unsafe::class.java.getDeclaredField("theUnsafe"); unsafeField.isAccessible = true
        val unsafe = unsafeField.get(null) as Unsafe
        val player = unsafe.allocateInstance(Player::class.java) as Player
        player.animation = unsafe.allocateInstance(AnimationPlayer::class.java) as AnimationPlayer
        val multi = AnimationMultiTrack()
        val tracks = AnimationPlayer::class.java.getDeclaredField("multiTrack"); tracks.isAccessible = true; tracks.set(player.animation, multi)
        player.animator = AdvancedAnimator()
        val layer = AnimLayer.alloc(player, player.animator)
        val root = AdvancedAnimator::class.java.getDeclaredField("rootLayer"); root.isAccessible = true; root.set(player.animator, layer)
        if (CartLegPace.brakeTrack(player) != null) throw AssertionError("missing cart brake must not claim another animation")
        for (name in listOf("Bob_RunToStop2H_Heavy", "Bob_SprintToStop2h_Heavy", "Toolkit_CartPivot_StopRun", "Toolkit_CartPivot_StopSprint")) {
            val unrelated = transition(layer, "ToolkitCartIdle", "Bob_IdleToRun", .4f)
            val unrelatedTrack = unrelated.getTransitionInTrack()
            val idle = transition(layer, "ToolkitCartIdle", name, .6f)
            val stop = idle.getTransitionInTrack()
            if (CartLegPace.brakeTrack(player) !== stop) throw AssertionError("native cart transition must own the exact heavy stop: $name")
            idle.setActive(false)
            close(CartLegPace.woodenGaitShift(layer.getLiveAnimNodes()), 0, "upright stop cannot inherit the running offset that makes idle grip unreachable")
            val forward = live("ToolkitCartPivotRun", false, clip("forward", 1, 0, 1, "Translation_Data"))
            forward.getMainAnimationTrackAt(0).setBlendWeight(.5f)
            close(CartLegPace.woodenGaitShift(listOf(forward, idle)), -.06, "outgoing running gait keeps its actual clearance while the stop uses the live pelvis envelope")
            val time = stop.getCurrentTimeValue()
            CartLegPace.cancelBrake(player, false)
            if (stop.getUseDeferredMovement() || idle.getTransitionInTrack() !== stop || !idle.isTransitioningIn())
                throw AssertionError("resume cancels only stop translation and keeps its native visual fade")
            close(stop.getSpeedDelta(), .7, "resume must preserve stop cadence")
            close(stop.getCurrentTimeValue(), time, "resume must preserve stop phase")
            close(stop.getBlendWeight(), .6, "resume must preserve stop visual weight")
            CartLegPace.cancelBrake(player, true)
            if (idle.getTransitionInTrack() != null || idle.isTransitioningIn() || CartLegPace.brakeTrack(player) != null)
                throw AssertionError("hard cleanup must release the owned stop transition")
            if (multi.getTracks().contains(stop)) throw AssertionError("hard cleanup must remove the stop from the native animation mixer")
            if (unrelated.getTransitionInTrack() !== unrelatedTrack || !unrelatedTrack.getUseDeferredMovement())
                throw AssertionError("owned stop cleanup must retain the neighboring idle transition")
            layer.getLiveAnimNodes().clear(); multi.reset()
        }
        for (other in arrayOf(arrayOf("IdleHeavy", "Bob_RunToStop2H_Heavy"), arrayOf("ToolkitCartIdle", "Bob_RunToStop"), arrayOf("ToolkitCartIdle", "Bob_SprintToStop_2h_Heavy"))) {
            val idle = transition(layer, other[0], other[1], .4f)
            val track = idle.getTransitionInTrack()
            if (CartLegPace.brakeTrack(player) != null) throw AssertionError("unrelated or misspelled stop must stay outside cart ownership")
            CartLegPace.cancelBrake(player, false); CartLegPace.cancelBrake(player, true)
            if (idle.getTransitionInTrack() !== track || !track.getUseDeferredMovement()) throw AssertionError("cart cleanup changed an unrelated native transition")
            close(CartLegPace.woodenGaitShift(layer.getLiveAnimNodes()), 0, "unrelated transition cannot shift the cart")
            layer.getLiveAnimNodes().clear(); multi.reset()
        }
    }
    private fun bracingChecks() {
        val unsafeField = Unsafe::class.java.getDeclaredField("theUnsafe"); unsafeField.isAccessible = true
        val unsafe = unsafeField.get(null) as Unsafe
        val model = ModelManager::class.java.getDeclaredField("animModel"); model.isAccessible = true
        val previous = model.get(ModelManager.instance)
        val apply = AnimLayer::class.java.getDeclaredMethod("applyBlendField", LiveAnimNode::class.java, Float::class.javaPrimitiveType, Float::class.javaPrimitiveType, Float::class.javaPrimitiveType)
        apply.isAccessible = true
        try {
            for (mode in arrayOf("Walk", "Run", "Sprint")) for (phase in floatArrayOf(.1f, .35f, .6f)) {
                val player = unsafe.allocateInstance(Player::class.java) as Player; player.run = mode.equals("Run"); player.sprint = mode.equals("Sprint")
                val source = node(); source.name = "ToolkitCartPivot$mode"; source.deferredBoneName = "Translation_Data"; source.deferredBoneAxis = BoneAxis.Y
                val animator = AdvancedAnimator(); player.animator = animator
                animator.animSet = zombie.core.skinnedmodel.advancedanimation.AnimationSet()
                val state = zombie.core.skinnedmodel.advancedanimation.AnimState(); state.nodes.add(source)
                animator.animSet.states[if (mode.equals("Walk")) "movement" else mode.lowercase(java.util.Locale.getDefault())] = state
                val layer = AnimLayer.alloc(player, animator)
                val root = AdvancedAnimator::class.java.getDeclaredField("rootLayer"); root.isAccessible = true; root.set(animator, layer)
                val live = LiveAnimNode.alloc(layer, source); live.setActive(true); layer.getLiveAnimNodes().add(live)
                val clips = HashMap<String, AnimationClip>()
                for (blend in source.blends2d) {
                    val c = clip(blend.animName, 1, blend.posX * 2, blend.posY * 2, "Translation_Data"); clips[c.name] = c
                    val track = AnimationTrack.alloc(); track.startClip(c, true, 0f); track.advance(phase); live.addMainTrack(track)
                }
                val mesh = unsafe.allocateInstance(ModelMesh::class.java) as ModelMesh
                mesh.skinningData = SkinningData(clips, emptyList(), emptyList(), emptyList(), emptyList(), HashMap()); model.set(ModelManager.instance, mesh)
                var previousIdle = -1f
                for (amount in doubleArrayOf(0.0, .25, .5, .75, 1.0)) {
                    close(CartLegPace.brace(player, 2f, 0f, 1f, amount, true), 0, "obstructed stance must not request root movement")
                    apply.invoke(layer, live, 1f, player.stepX, player.stepY)
                    val idle = live.getMainAnimationTrackAt(0).getBlendFieldWeight()
                    if (idle < previousIdle) throw AssertionError("brace did not settle monotonically into native Idle")
                    previousIdle = idle
                    for (track in live.getMainAnimationTracks()) {
                        close(track.getSpeedDelta(), 0, "blocked root must remain frozen while field plants the feet")
                        close(track.getCurrentTimeValue(), phase, "planting must not seek the gait phase")
                    }
                }
                close(previousIdle, 1, "fully obstructed stance uses only the existing planted Idle clip")
                for (amount in doubleArrayOf(1.0, .75, .5, .25, 0.0)) {
                    val speed = CartLegPace.brace(player, 2f, 0f, 1f, amount, false)
                    apply.invoke(layer, live, 1f, player.stepX, player.stepY)
                    var rootSpeed = 0.0
                    for (track in live.getMainAnimationTracks()) rootSpeed += track.getClip().getTotalTranslation("Translation_Data", BoneAxis.Y, Vector2()).getLength() * track.getBlendFieldWeight() * track.getSpeedDelta()
                    close(rootSpeed.toFloat(), speed, "restart must grow the native budget instead of compensating the fade away")
                    if (amount == 1.0) close(speed, 0, "fully braced endpoint has no latent root budget")
                    else if (!(speed > 0)) throw AssertionError("cleared obstruction must restart without accepted-motion dependency")
                }
                close(player.stepY, 1, "clear stance must restore the full forward gait")
            }
        } finally { model.set(ModelManager.instance, previous) }
    }
    private fun rampChecks() {
        val empty = CartLegPace.Ramp()
        val full = CartLegPace.Ramp()
        for (i in 0 until 12) { empty.update(4.0, 1.0 / 60, 0.0); full.update(4.0, 1.0 / 60, 1.0) }
        if (!(full.speed > 0 && full.speed < empty.speed && empty.speed < 4)) throw AssertionError("cargo must lengthen Sprint acceleration")
        empty.reset(4.0); full.reset(4.0)
        for (i in 0 until 12) { empty.update(0.0, 1.0 / 60, 0.0); full.update(0.0, 1.0 / 60, 1.0) }
        if (!(full.speed > empty.speed && empty.speed > 0)) throw AssertionError("cargo must lengthen Sprint braking")
        var referenceSpeed = 0.0
        var referenceVelocity = 0.0
        for (fps in intArrayOf(20, 60, 144)) {
            val ramp = CartLegPace.Ramp()
            for (i in 0 until fps / 2) ramp.update(4.0, 1.0 / fps, 1.0)
            if (fps == 20) { referenceSpeed = ramp.speed; referenceVelocity = ramp.velocity }
            if (Math.abs(ramp.speed - referenceSpeed) > 1e-10 || Math.abs(ramp.velocity - referenceVelocity) > 1e-10)
                throw AssertionError("Sprint ramp depends on frame rate: $fps")
        }
        val ramp = CartLegPace.Ramp(); ramp.reset(0.0)
        for (i in 0 until 5) ramp.update(4.0, 1.0 / 60, 1.0)
        var previous = ramp.speed
        for (i in 0 until 100) {
            ramp.update(0.0, 1.0 / 60, 1.0)
            if (ramp.speed > previous || ramp.speed < 0) throw AssertionError("Sprint release kept accelerating or reversed movement")
            previous = ramp.speed
        }
        if (!ramp.settled(0.0)) throw AssertionError("Sprint ramp never settles after release")
        ramp.reset(2.0)
        for (paused in doubleArrayOf(0.0, -.1, Double.NaN, Double.POSITIVE_INFINITY)) {
            ramp.update(4.0, paused, 0.0)
            close(ramp.speed.toFloat(), 2, "paused/invalid dt cannot move the ramp")
            close(ramp.velocity.toFloat(), 0, "paused/invalid dt cannot accelerate the ramp")
        }
        ramp.update(Double.NaN, .1, 0.0)
        close(ramp.speed.toFloat(), 2, "missing calibration keeps the current speed")
        empty.reset(2.0); full.reset(2.0)
        empty.update(4.0, .1, 0.0); full.update(4.0, .5, Double.NaN)
        close(full.speed.toFloat(), empty.speed, "long dt is capped and invalid load uses empty cart")
        for (load in doubleArrayOf(-1.0, 2.0)) {
            empty.reset(0.0); full.reset(0.0)
            empty.update(4.0, .1, if (load < 0) 0.0 else 1.0); full.update(4.0, .1, load)
            close(full.speed.toFloat(), empty.speed, "cargo ratio is bounded to the supported range")
        }
        ramp.reset(Double.NaN)
        close(ramp.speed.toFloat(), 0, "invalid reset cannot poison later movement")
        if (!ramp.settled(0.0) || ramp.settled(Double.NaN)) throw AssertionError("invalid settled state")
    }
    private fun coastingChecks() {
        for (seconds in doubleArrayOf(.1, .3)) {
            var emptyResidual = 0.0
            var reference = 0.0
            for (load in doubleArrayOf(0.0, 1.0)) for (fps in intArrayOf(30, 60, 120)) {
                val coast = CartLegPace.Ramp(); coast.reset(4.0)
                val reverse = CartLegPace.Ramp(); reverse.reset(4.0)
                var previous = coast.speed
                var frame = 0
                while (frame < Math.round(seconds * fps)) {
                    coast.update(1.0, 1.0 / fps, load, true); reverse.update(1.0, 1.0 / fps, load)
                    if (!(coast.speed <= previous && coast.speed >= 1)) throw AssertionError("Walk coast must decelerate without undershooting")
                    previous = coast.speed; frame++
                }
                if (!(coast.speed > 1.02 && coast.speed > reverse.speed)) throw AssertionError("brief Walk must retain fast momentum without slowing reversal: $seconds/$load/$fps")
                if (fps == 30) reference = coast.speed else if (Math.abs(coast.speed - reference) > 1e-10) throw AssertionError("Walk coasting depends on frame rate: $fps")
                if (load == 0.0) emptyResidual = coast.speed else if (!(coast.speed > emptyResidual)) throw AssertionError("cargo must retain more speed after brief Walk")
            }
        }
        val coast = CartLegPace.Ramp(); coast.reset(4.0)
        for (frame in 0 until 600) coast.update(1.0, 1.0 / 60, 1.0, true)
        if (!coast.settled(1.0)) throw AssertionError("continued Walk must retire fast momentum")
        for (frame in 0 until 6) coast.update(4.0, 1.0 / 60, 1.0, true)
        if (!(coast.speed > 1 && coast.speed < 4)) throw AssertionError("fast restart must accelerate from retained Walk speed")
        val previous = coast.speed
        coast.update(1.0, 1.0 / 60, 1.0, true)
        if (!(coast.speed <= previous && coast.speed >= 1)) throw AssertionError("releasing a fast restart must brake immediately")
    }

    private fun speedChecks(source: AnimNode, walk: AnimationClip, run: AnimationClip, sprint: AnimationClip) {
        close(CartLegPace.targetSpeed(source, walk, run, .3f, 1f, 1.04f),
            1.04 * (walk.getTotalTranslation("Translation_Data", BoneAxis.Y, Vector2()).getLength() / walk.getDuration() * .7 +
                run.getTotalTranslation("Translation_Data", BoneAxis.Y, Vector2()).getLength() / run.getDuration() * .3),
            "absolute native target includes the native gait blend and base pace once")
        close(CartLegPace.targetSpeed(source, walk, walk, 1f, .4f, 1.04f),
            1.04 * .4 * walk.getTotalTranslation("Translation_Data", BoneAxis.Y, Vector2()).getLength() / walk.getDuration(),
            "walking target includes the intent magnitude once")
        close(CartLegPace.targetSpeed(null, 0f, 0f), 0, "idle needs no calibration")
        if (!CartLegPace.targetSpeed(null, 0f, 1f).isNaN() || !CartLegPace.targetSpeed(source, walk, null, 1f, 1f, 1f).isNaN())
            throw AssertionError("missing calibration must remain distinguishable from a stop")
        val walking = live("ToolkitCartPivotWalk", true, walk)
        val running = live("ToolkitCartPivotRun", false, run)
        val sprinting = live("ToolkitCartPivotSprint", false, sprint)
        val untouched = live("ToolkitCartSprintRight", true, sprint)
        val nodes = listOf(walking, running, sprinting, untouched)
        for (node in nodes) node.getMainAnimationTrackAt(0).setBlendFieldWeight(1f)
        for (speed in floatArrayOf(1.2f, .6f, 0f)) {
            CartLegPace.applySpeedTracks(nodes, speed, null, 0f, 1f)
            for (node in listOf(walking, running, sprinting)) {
                val track = node.getMainAnimationTrackAt(0)
                val clip = track.getClip()
                val velocity = (clip.getTotalTranslation("Translation_Data", BoneAxis.Y, Vector2()).getLength() / clip.getDuration()).toDouble()
                close((track.getSpeedDelta() * velocity).toFloat(), speed, "incoming and inactive outgoing gaits share one smoothed root velocity")
                close(track.getCurrentTimeValue(), .25, "speed ramp preserves animation phase")
                close(track.getBlendWeight(), .3, "speed ramp preserves native fade weights")
            }
            close(untouched.getMainAnimationTrackAt(0).getSpeedDelta(), 1.1, "upper-body cadence remains native")
        }
        val current = live("ToolkitCartPivotSprint", false, sprint)
        val strafe = AnimationTrack.alloc(); strafe.startClip(clip("old-strafe", 1, 1, 0, "Translation_Data"), true, 0f)
        strafe.setBlendFieldWeight(1f); current.addMainTrack(strafe)
        val forward = current.getMainAnimationTrackAt(0); forward.setBlendFieldWeight(0f)
        val sprintVelocity = sprint.getTotalTranslation("Translation_Data", BoneAxis.Y, Vector2()).getLength() / sprint.getDuration()
        val newPace = 1 / sprintVelocity
        CartLegPace.applySpeedTracks(listOf(current, running), 1f, current.getName(), newPace, 1f)
        close(forward.getSpeedDelta(), newPace, "reactivating current gait uses the new picker, not old strafe weights")
        close(strafe.getSpeedDelta(), newPace, "all current gait tracks receive the new directional cadence")
        forward.setBlendFieldWeight(1f); strafe.setBlendFieldWeight(0f)
        close(forward.getSpeedDelta() * sprintVelocity, 1, "native directional refresh cannot jump the requested speed")
        CartLegPace.applySpeedTracks(listOf(current), .5f, null, 1.04f, 0f)
        close(forward.getSpeedDelta() * sprintVelocity, .5, "zero intent keeps every remaining gait on outgoing root speed")
        // An outgoing blend keeps the last directional weights after native deactivation.
        val lateral = AnimationTrack.alloc(); lateral.startClip(clip("outgoing-strafe", 1, 1, 0, "Translation_Data"), true, 0f)
        lateral.setBlendFieldWeight(.25f); sprinting.addMainTrack(lateral)
        sprinting.getMainAnimationTrackAt(0).setBlendFieldWeight(.75f)
        CartLegPace.applySpeedTracks(listOf(sprinting), 1f, null, 0f, 1f)
        val intrinsic = Math.hypot(.25, .75 * sprint.getTotalTranslation("Translation_Data", BoneAxis.Y, Vector2()).getLength() / sprint.getDuration())
        close((intrinsic * lateral.getSpeedDelta()).toFloat(), 1, "outgoing blend velocity uses all main track weights")
        close(lateral.getSpeedDelta(), sprinting.getMainAnimationTrackAt(0).getSpeedDelta(), "all blended clips use one node cadence")
    }
    private fun reversalChecks(walk: AnimationClip, back: AnimationClip) {
        val forward = live("ToolkitCartPivotRun", false, walk)
        val backward = live("ToolkitCartPivotWalk", false, back)
        val current = live("ToolkitCartPivotSprint", false, walk)
        val untouched = live("ToolkitCartRunRight", true, walk)
        val nodes = listOf(forward, backward, current, untouched)
        for (node in nodes) node.getMainAnimationTrackAt(0).setBlendFieldWeight(1f)
        for (stepY in floatArrayOf(-1f, 1f, 0f, -1e-8f, 1e-8f)) {
            CartLegPace.applySpeedTracks(nodes, .6f, current.getName(), .7f, stepY)
            for (node in listOf(forward, backward)) {
                val track = node.getMainAnimationTrackAt(0)
                val root = track.getClip().getTotalTranslation("Translation_Data", BoneAxis.Y, Vector2())
                val velocity = root.getLength() / track.getClip().getDuration()
                val opposite = root.y / track.getClip().getDuration() * stepY < -1e-6
                close(track.getSpeedDelta() * velocity, if (opposite) 0 else .6, "only opposite outgoing root motion stops: ${node.getName()}/$stepY")
                close(track.getCurrentTimeValue(), .25, "reversal preserves outgoing foot phase")
                close(track.getBlendWeight(), .3, "reversal preserves native fade weight")
                close(track.getBlendFieldWeight(), 1, "reversal preserves latched directional weights")
            }
            close(current.getMainAnimationTrackAt(0).getSpeedDelta(), .7, "incoming gait gets new cadence before native directional refresh")
            close(untouched.getMainAnimationTrackAt(0).getSpeedDelta(), 1.1, "reversal leaves upper-body tracks untouched")
        }
        // Mixed outgoing fields use their combined root, not the sign of one clip.
        val reverseTrack = AnimationTrack.alloc(); reverseTrack.startClip(back, true, 0f); forward.addMainTrack(reverseTrack)
        forward.getMainAnimationTrackAt(0).setBlendFieldWeight(.1f); reverseTrack.setBlendFieldWeight(.9f)
        CartLegPace.applySpeedTracks(listOf(forward), .2f, null, 0f, -1f)
        val rootY = .1 * walk.getTotalTranslation("Translation_Data", BoneAxis.Y, Vector2()).y / walk.getDuration() +
            .9 * back.getTotalTranslation("Translation_Data", BoneAxis.Y, Vector2()).y / back.getDuration()
        close((Math.abs(rootY) * reverseTrack.getSpeedDelta()).toFloat(), .2, "same-sign mixed outgoing root keeps the requested speed")
        CartLegPace.applySpeedTracks(listOf(forward), .2f, null, 0f, 1f)
        for (track in forward.getMainAnimationTracks()) close(track.getSpeedDelta(), 0, "opposite mixed outgoing field stops all its main tracks")
        CartLegPace.applySpeedTracks(nodes, 0f, null, 0f, -1f)
        for (node in listOf(forward, backward, current)) for (track in node.getMainAnimationTracks()) close(track.getSpeedDelta(), 0, "zero speed stops every owned outgoing gait")
    }
    private fun woodenPivotChecks() {
        val wood = "SaucedWheelbarrow.WheelbarrowWood"
        for (type in arrayOf(null, wood, "SaucedWheelbarrow.WheelbarrowMetal", "SaucedCarts.ShoppingCart", wood + "Other")) {
            val walk = if (wood.equals(type) || "SaucedWheelbarrow.WheelbarrowMetal".equals(type)) "ToolkitWoodCartPivotWalk" else "ToolkitCartPivotWalk"
            if (!CartLegPace.pivotName(type, false, false).equals(walk) || !CartLegPace.pivotName(type, true, false).equals("ToolkitCartPivotRun") ||
                !CartLegPace.pivotName(type, false, true).equals("ToolkitCartPivotSprint") || !CartLegPace.pivotName(type, true, true).equals("ToolkitCartPivotSprint"))
                throw AssertionError("exact wooden walking node selection or fast gait changed")
        }
        val node = node()
        val clips = mapOf("idle" to clip("idle", 1, 0, 0, "Translation_Data"), "forward" to clip("forward", 1, 0, 1, "Translation_Data"),
            "back" to clip("back", 1, 0, -1, "Translation_Data"), "left" to clip("Toolkit_WoodCartPivot_Left", 1, -.75f, 0, "Translation_Data"),
            "right" to clip("Toolkit_WoodCartPivot_Right", 1, .75f, 0, "Translation_Data"))
        for (degree in -180..180) {
            val x = Math.sin(Math.toRadians(degree.toDouble())).toFloat(); val y = Math.cos(Math.toRadians(degree.toDouble())).toFloat()
            val pace = CartLegPace.scale(node, clips["forward"], x, y, 1.04f, clips::get)
            close(blendedSpeed(node, clips, x, y) * pace, 1.04, "larger authored lateral roots preserve the walking budget at $degree")
        }
        val current = live("ToolkitWoodCartPivotWalk", true, clips.getValue("right"))
        val outgoing = live("ToolkitWoodCartPivotWalk", false, clips.getValue("left"))
        val nativeWalk = live("ToolkitCartPivotWalk", false, clips.getValue("forward"))
        val upper = live("ToolkitCartWalkLeft", true, clips.getValue("right"))
        for (live in listOf(current, outgoing, nativeWalk)) live.getMainAnimationTrackAt(0).setBlendFieldWeight(1f)
        CartLegPace.applySpeedTracks(listOf(current, outgoing, nativeWalk, upper), .3f, current.getName(), .6f, 1f)
        close(current.getMainAnimationTrackAt(0).getSpeedDelta(), .6, "incoming wood gait uses its new pace before field refresh")
        close(outgoing.getMainAnimationTrackAt(0).getSpeedDelta(), .6, "same named wood gait receives its current pace")
        close(nativeWalk.getMainAnimationTrackAt(0).getSpeedDelta(), .3, "outgoing native walk retains its actual root budget")
        close(upper.getMainAnimationTrackAt(0).getSpeedDelta(), 1.1, "wood gait compensation leaves hand masks alone")
        CartLegPace.applySpeedTracks(listOf(current, outgoing), .3f, "ToolkitCartPivotRun", 1f, 1f)
        for (live in listOf(current, outgoing)) close(live.getMainAnimationTrackAt(0).getSpeedDelta(), .4, "wood root velocity controls cadence throughout fade to Run")
        CartLegPace.applySpeedTracks(listOf(current, outgoing), 0f, null, 0f, 1f)
        for (live in listOf(current, outgoing)) close(live.getMainAnimationTrackAt(0).getSpeedDelta(), 0, "stopping freezes both outgoing authored roots")
    }
    private fun fastBraceClearance() {
        val body = clip("Toolkit_WoodCartBrace", 1, 0, 0, "Translation_Data")
        for (gait in arrayOf("Run", "Sprint")) {
            val offset = if (gait.equals("Run")) -.12f else -.05f
            val outgoing = live("ToolkitCartPivot$gait", false, body)
            val brace = live("ToolkitWoodCartBrace$gait", true, body)
            val idle = live("ToolkitWoodCartBrace", true, body)
            val hand = live("ToolkitWoodCartBraceLeft", true, body)
            idle.getMainAnimationTrackAt(0).setBlendWeight(1f); hand.getMainAnimationTrackAt(0).setBlendWeight(1f)
            for (frame in 0..100) {
                val weight = frame / 100f
                outgoing.getMainAnimationTrackAt(0).setBlendWeight(1 - weight); brace.getMainAnimationTrackAt(0).setBlendWeight(weight)
                close(CartLegPace.woodenGaitShift(listOf(outgoing, brace, idle, hand)), offset, "$gait -> held brace preserves the complete native gait clearance throughout blending")
            }
            outgoing.getMainAnimationTrackAt(0).setBlendWeight(0f); brace.setActive(false)
            var previous = offset
            for (frame in 0..100) {
                val weight = 1 - frame / 100f
                brace.getMainAnimationTrackAt(0).setBlendWeight(weight)
                val shift = CartLegPace.woodenGaitShift(listOf(brace, idle, hand))
                close(shift, offset * weight, "$gait brace fade to Idle follows its actual inactive track weight")
                if (shift < previous - 1e-6 || shift - previous > Math.abs(offset) / 100 + 1e-6) throw AssertionError("$gait brace clearance snapped during the native fade")
                previous = shift
            }
            close(previous, 0, "$gait brace fade releases the exact ordinary Idle placement")
        }
    }
    private fun backwardChecks(node: AnimNode, clips: Map<String, AnimationClip>) {
        val wood = "SaucedWheelbarrow.WheelbarrowWood"
        if (!CartLegPace.walkingReference(wood, false, -1f).equals("Bob_WalkBwdNoAim1Hand")) throw AssertionError("wooden reverse walking must use the authored backward reference")
        if (!CartLegPace.walkingReference("SaucedWheelbarrow.WheelbarrowMetal", false, -1f).equals("Bob_WalkBwdNoAim1Hand")) throw AssertionError("metal reverse must use the same authored backward reference")
        for (other in arrayOf(null, "SaucedCarts.ShoppingCart", "SaucedWheelbarrow.Other")) if (!CartLegPace.walkingReference(other, false, -1f).equals("Bob_Walk"))
            throw AssertionError("reverse walking reference escaped the wooden cart scope")
        if (!CartLegPace.walkingReference(wood, true, -1f).equals("Bob_Walk") || !CartLegPace.walkingReference(wood, false, 0f).equals("Bob_Walk") ||
            !CartLegPace.walkingReference(wood, false, 1f).equals("Bob_Walk")) throw AssertionError("fast, forward and idle references must stay unchanged")
        val back = clips.getValue("back")
        for (amount in floatArrayOf(.44f, .72f, 1f)) for (degree in intArrayOf(135, 150, 180, 210, 225)) {
            val x = amount * Math.sin(Math.toRadians(degree.toDouble())).toFloat(); val y = amount * Math.cos(Math.toRadians(degree.toDouble())).toFloat()
            val expected = 1.04 * .590551 / (2f / 3) * Math.hypot(x.toDouble(), y.toDouble())
            val pace = CartLegPace.scale(node, back, x, y, 1.04f, clips::get)
            close(blendedSpeed(node, clips, x, y) * pace, expected, "backward and diagonal budgets keep the native WalkSpeed magnitude once")
            close(CartLegPace.targetSpeed(node, back, back, 1f, Math.hypot(x.toDouble(), y.toDouble()).toFloat(), 1.04f), expected,
                "Sprint settling and ordinary walking share the backward speed target")
        }
        close(CartLegPace.scale(node, back, 0f, 0f, 1.04f, clips::get), 1.04, "idle backward pace keeps the existing fallback")
        close(CartLegPace.targetSpeed(node, back, back, 1f, 0f, 1.04f), 0, "idle backward target is zero")
        close(CartLegPace.scale(node, null, 0f, -1f, 1.04f, clips::get), 1.04, "missing backward reference keeps the existing pace")
        if (!CartLegPace.targetSpeed(node, null, null, 1f, 1f, 1.04f).isNaN()) throw AssertionError("missing backward calibration must preserve the existing target fallback")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        fastBraceClearance(); woodenPivotChecks(); nativePelvisBinding(); sideClearance(); bracingChecks(); brakeTracks(); coastingChecks()
        val node = node()
        val clips = HashMap<String, AnimationClip>()
        clips["idle"] = clip("idle", 1, 0, 0, "Translation_Data")
        clips["forward"] = clip("forward", 1, 0, 2, "Translation_Data")
        clips["right"] = clip("right", 2, 2, 0, "Translation_Data")
        clips["left"] = clip("left", 1, -1, 0, "Translation_Data")
        clips["back"] = clip("back", 1, 0, -.5f, "Translation_Data")
        val forward = clips.getValue("forward")
        val owned = listOf(live("ToolkitCartPivotWalk", true, forward), live("ToolkitCartPivotRun", true, forward), live("ToolkitCartPivotSprint", true, forward))
        val untouched = listOf(live("ToolkitCartPivotWalk", false, forward), live("defaultWalk", true, forward), live("ToolkitCartPivotWalkOther", true, forward))
        val all = ArrayList(owned); all.addAll(untouched)
        for (current in owned) {
            CartLegPace.applyTracks(all, 2.08f, current.getName())
            for (live in all) {
                val track = live.getMainAnimationTrackAt(0)
                close(track.getSpeedDelta(), if (live === current) 2.08 else 1.1, "only the current active gait changes pace")
                close(track.getCurrentTimeValue(), .25, "pace update must not reset phase")
                close(track.getBlendWeight(), .3, "pace update must not change blend weights")
                track.setSpeedDelta(1.1f)
            }
        }
        // The hook precedes native active-flag refresh: outgoing is still active here.
        val walkTrack = owned[0].getMainAnimationTrackAt(0)
        val runTrack = owned[1].getMainAnimationTrackAt(0)
        walkTrack.setSpeedDelta(1.04f); runTrack.setSpeedDelta(.57f)
        CartLegPace.applyTracks(owned, .57f, "ToolkitCartPivotRun")
        close(walkTrack.getSpeedDelta(), 1.04, "Walk->Run preserves outgoing walking budget")
        close(runTrack.getSpeedDelta(), .57, "Walk->Run keeps incoming running budget")
        CartLegPace.applyTracks(owned, 1.04f, "ToolkitCartPivotWalk")
        close(runTrack.getSpeedDelta(), .57, "Run->Walk preserves outgoing running budget")
        close(walkTrack.getSpeedDelta(), 1.04, "Run->Walk keeps incoming walking budget")
        CartLegPace.applyTracks(owned, .96f, "ToolkitCartPivotSprint")
        close(runTrack.getSpeedDelta(), .57, "Run->Sprint preserves outgoing running budget")
        close(owned[2].getMainAnimationTrackAt(0).getSpeedDelta(), .96, "incoming sprint budget")
        val walkNode = live("ToolkitCartPivotWalk", true, forward)
        val runNode = live("ToolkitCartPivotRun", true, forward)
        val sprintNode = live("ToolkitCartPivotSprint", true, forward)
        val unrelated = live("defaultRun", true, forward)
        val upperBody = live("ToolkitCartRunRight", true, forward)
        close(CartLegPace.woodenGaitShift(listOf(walkNode, unrelated, upperBody)), 0, "walk and unrelated/upper-body tracks do not shift the running pose")
        for (blend in floatArrayOf(.2f, .8f)) {
            runNode.getMainAnimationTrackAt(0).setBlendWeight(blend)
            close(CartLegPace.woodenGaitShift(listOf(walkNode, runNode, upperBody)), -.12 * blend, "walking->running uses actual track weights")
        }
        runNode.setActive(false); sprintNode.getMainAnimationTrackAt(0).setBlendWeight(.2f)
        close(CartLegPace.woodenGaitShift(listOf(runNode, sprintNode)), -.106, "run->sprint weights the distinct incoming and inactive outgoing offsets")
        runNode.getMainAnimationTrackAt(0).setBlendWeight(.3f)
        close(CartLegPace.woodenGaitShift(listOf(walkNode, runNode)), -.036, "running->walking keeps the outgoing running pose during fade-out")
        val second = AnimationTrack.alloc(); second.startClip(forward, true, 0f); second.setBlendWeight(.4f); runNode.addMainTrack(second)
        close(CartLegPace.woodenGaitShift(listOf(runNode)), -.084, "all main track weights contribute")
        sprintNode.getMainAnimationTrackAt(0).setBlendWeight(.8f)
        close(CartLegPace.woodenGaitShift(listOf(runNode, sprintNode)), -.12, "gait shift clamps at the running offset")
        for (invalid in floatArrayOf(Float.NaN, Float.POSITIVE_INFINITY, -.2f)) {
            runNode.getMainAnimationTrackAt(0).setBlendWeight(invalid)
            close(CartLegPace.woodenGaitShift(listOf(runNode)), -.048, "invalid track weights are ignored")
        }
        second.setBlendWeight(0f); runNode.getMainAnimationTrackAt(0).setBlendWeight(1f); sprintNode.getMainAnimationTrackAt(0).setBlendWeight(1f)
        close(CartLegPace.woodenGaitShift(listOf(runNode)), -.12, "full running clearance stays unchanged")
        close(CartLegPace.woodenGaitShift(listOf(sprintNode)), -.05, "full sprint has its own clearance")
        runNode.getMainAnimationTrackAt(0).setBlendWeight(.25f); sprintNode.getMainAnimationTrackAt(0).setBlendWeight(.75f)
        close(CartLegPace.woodenGaitShift(listOf(runNode, sprintNode)), -.0675, "mostly sprint transition")
        runNode.getMainAnimationTrackAt(0).setBlendWeight(.75f); sprintNode.getMainAnimationTrackAt(0).setBlendWeight(.25f)
        close(CartLegPace.woodenGaitShift(listOf(runNode, sprintNode)), -.1025, "mostly running transition")
        close(CartLegPace.woodenGaitShift(null as IsoPlayer?), 0, "missing running player")
        close(CartLegPace.woodenBodyShift(0f, -4.6785715e-7f, .0109462375f), -.025, "fast-pose reserve is independent of the narrow intrusion threshold")
        close(CartLegPace.woodenBodyShift(-.12f, 0f, -.06f), -.12, "existing sufficient Run clearance is preserved")
        close(CartLegPace.woodenBodyShift(0f, 0f, -.03f), -.06594764, "pelvis advance retains clothing clearance after Run fades")
        close(CartLegPace.woodenBodyShift(-.01f, .01f, -.02f), -.08594764, "lateral pelvis drift cannot enter a fixed shaft")
        close(CartLegPace.woodenBodyShift(0f, 1f, -1f), -.24, "extreme pose clearance is bounded")
        close(CartLegPace.woodenBodyShift(-.03f, 0f, -.06405236f, .5f), -.0875, "available fast corridor retains the full measured intrusion instead of weighting it twice")
        // Native steady Walk snapshot: this negative proxy is an accepted ordinary
        // gait, not permission to retain 28mm of fast correction until weight zero.
        for (gait in floatArrayOf(0f, -.0294f)) {
            var previous = CartLegPace.woodenBodyShift(gait, .008203087f, .007592707f, 0f)
            close(previous, gait, "retired fast pose leaves the accepted Walk position")
            for (i in 1..10000) {
                val weight = i / 10000f
                val next = CartLegPace.woodenBodyShift(gait, .008203087f, .007592707f, weight)
                if (Math.abs(next - previous) > .0000241f) throw AssertionError("fast clearance jumps across an ownership boundary: $weight")
                previous = next
            }
        }
        for (invalid in floatArrayOf(Float.NaN, Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY)) {
            close(CartLegPace.woodenBodyShift(-.05f, invalid, 0f), -.05, "invalid lateral pose keeps gait fallback")
            close(CartLegPace.woodenBodyShift(-.05f, 0f, invalid), -.05, "invalid forward pose keeps gait fallback")
        }
        var lastShift = CartLegPace.woodenBodyShift(0f, -4.6785715e-7f, .0109462375f)
        for (i in 0..20000) {
            val z = .0109462375f - i * .000001f
            val shift = CartLegPace.woodenBodyShift(0f, -4.6785715e-7f, z)
            if (shift > lastShift + 1e-7f || Math.abs(shift - lastShift) > .0000011f) throw AssertionError("forward pelvis clearance must not amplify a native pose step")
            lastShift = shift
        }
        close(CartLegPace.runningWeight(listOf(walkNode, sprintNode, unrelated, upperBody)), 0, "head correction ignores walking, sprinting and upper-body tracks")
        for (blend in floatArrayOf(.2f, .8f)) {
            runNode.getMainAnimationTrackAt(0).setBlendWeight(blend)
            close(CartLegPace.runningWeight(listOf(runNode, sprintNode)), blend, "Run correction follows actual weight, including inactive fade-out")
        }
        second.setBlendWeight(.4f)
        close(CartLegPace.runningWeight(listOf(runNode)), 1, "Run correction sums main tracks and clamps at one")
        for (invalid in floatArrayOf(Float.NaN, Float.POSITIVE_INFINITY, -.2f)) {
            runNode.getMainAnimationTrackAt(0).setBlendWeight(invalid)
            close(CartLegPace.runningWeight(listOf(runNode)), .4, "Run correction ignores invalid weights")
        }
        close(CartLegPace.runningWeight(null as zombie.characters.IsoGameCharacter?), 0, "missing head-correction character")
        for (base in floatArrayOf(1.04f, 1f)) {
            for (loadPace in floatArrayOf(1f, .8f, .4f)) {
                close(CartLegPace.scale(node, forward, 0f, loadPace, base, clips::get), base, "forward pace must stay unchanged at $loadPace")
                close(CartLegPace.scale(node, forward, loadPace, 0f, base, clips::get), base * 2, "slower lateral clip must retain the existing load slowdown once")
                close(CartLegPace.scale(node, forward, -loadPace, 0f, base, clips::get), base * 2, "left strafe compensation")
            }
            close(CartLegPace.scale(node, forward, .4f, .4f, base, clips::get), base * 2 * Math.hypot(.4, .4) / Math.hypot(.4, .8),
                "diagonal compensation uses the blended vector, not a sum of speeds")
            close(CartLegPace.scale(node, forward, 0f, -1f, base, clips::get), 2.5, "very slow backward clips must respect the pace ceiling")
            close(CartLegPace.scale(node, forward, 0f, 0f, base, clips::get), base, "idle")
            close(CartLegPace.scale(node, forward, Float.NaN, 0f, base, clips::get), base, "invalid intent")
            close(CartLegPace.scale(node, null, 1f, 0f, base, clips::get), base, "missing reference")
            close(CartLegPace.scale(null, forward, 1f, 0f, base, clips::get), base, "missing node")
        }
        // Root translations read from the loaded B42.21 clips by ProbePace.
        val nativeClips = mapOf("idle" to clip("idle", 2f / 3, 0, 0, "Translation_Data"), "forward" to clip("forward", 2f / 3, 0, .944882f, "Translation_Data"),
            "right" to clip("right", 2f / 3, -.417323f, 0, "Translation_Data"), "left" to clip("left", 2f / 3, .417323f, 0, "Translation_Data"),
            "back" to clip("back", 2f / 3, 0, -.590551f, "Translation_Data"))
        backwardChecks(node, nativeClips); reversalChecks(nativeClips.getValue("forward"), nativeClips.getValue("back"))
        for (amount in floatArrayOf(.44f, .72f, 1f)) for (degree in -180..180) {
            val x = amount * Math.sin(Math.toRadians(degree.toDouble())).toFloat(); val y = amount * Math.cos(Math.toRadians(degree.toDouble())).toFloat()
            val scale = CartLegPace.scale(node, nativeClips["forward"], x, y, 1.04f, nativeClips::get)
            val expected = 1.04 * .944882 / (2f / 3) * Math.hypot(x.toDouble(), y.toDouble())
            val actual = blendedSpeed(node, nativeClips, x, y) * scale
            if (actual > expected + 1e-5) throw AssertionError("walking budget exceeded at $degree")
            if (amount <= .72f) close(actual, expected, "cardinal roots retain the measured cart walking budget at $degree")
        }
        val walk = nativeClips.getValue("forward")
        val run = clip("run", 2f / 3, 0, 2.094488f, "Translation_Data")
        val sprint = clip("sprint", 2f / 3, 0, 2.755905f, "Translation_Data")
        rampChecks(); speedChecks(node, walk, run, sprint)
        val runningClips = HashMap(nativeClips); runningClips["forward"] = run
        val walkVelocity = .944882 / (2f / 3)
        val runVelocity = 2.094488 / (2f / 3)
        var previous = Double.POSITIVE_INFINITY
        // Native calculateBaseSpeed/calculateWalkSpeed counts the held bag in both hands.
        for (load in floatArrayOf(0f, 1f)) {
            val modifier = 1 + 2 * (.70 - 1) * (1 + load / 2)
            val walking = 1 - Math.abs(1 - modifier) / 2
            val running = ((walking - .15) * modifier).toFloat()
            val expected = 1.04 * (walkVelocity * (1 - running) + runVelocity * running)
            var rate = CartLegPace.runningScale(node, walk, run, running, 0f, 1f, 1.04f, runningClips::get)
            var actual = (blendedSpeed(node, runningClips, 0f, 1f) * rate).toDouble()
            close(actual.toFloat(), expected, "wooden running keeps the native walk->run budget at load $load")
            if (actual <= 1.04 * walkVelocity * walking) throw AssertionError("running must be faster than walking at load $load")
            if (actual >= previous) throw AssertionError("cargo must still slow running")
            previous = actual
            for (degree in -180..180) {
                val x = Math.sin(Math.toRadians(degree.toDouble())).toFloat(); val y = Math.cos(Math.toRadians(degree.toDouble())).toFloat()
                rate = CartLegPace.runningScale(node, walk, run, running, x, y, 1.04f, runningClips::get)
                actual = (blendedSpeed(node, runningClips, x, y) * rate).toDouble()
                if (actual > expected + 1e-5) throw AssertionError("running direction exceeded native budget")
                if (y > .8) close(actual.toFloat(), expected, "forward turns retain running speed")
            }
        }
        close(CartLegPace.runningScale(node, walk, run, 0f, 0f, 1f, 1.04f, runningClips::get), 1.04 * walkVelocity / runVelocity, "zero run scalar blends to walking, not idle")
        close(CartLegPace.runningScale(node, walk, run, -1f, 0f, 1f, 1.04f, runningClips::get), 1.04 * walkVelocity / runVelocity, "negative native scalar clamps to walking")
        close(CartLegPace.runningScale(node, walk, run, 2f, 0f, 1f, 1.04f, runningClips::get), 1.04, "native scalar clamps to full running")
        runningClips["forward"] = sprint
        close(CartLegPace.runningScale(node, run, sprint, 0f, 0f, 1f, .96f, runningClips::get), .96 * 2.094488 / 2.755905, "low sprint scalar keeps native running floor")
        close(CartLegPace.runningScale(node, run, sprint, 1f, 0f, 1f, .96f, runningClips::get), .96, "full native sprint pace")
        close(CartLegPace.runningScale(node, run, sprint, Float.NaN, 0f, 1f, .96f, runningClips::get), .96, "invalid native speed")
        close(CartLegPace.runningScale(node, null, sprint, 1f, 0f, 1f, .96f, runningClips::get), .96, "missing slow gait")
        clips.remove("right")
        close(CartLegPace.scale(node, forward, 1f, 0f, 1.04f, clips::get), 1.04, "missing clip")
        for (invalid in listOf(clip("zero duration", 0, 1, 0, "Translation_Data"), clip("invalid translation", 1, Float.NaN, 0, "Translation_Data"),
                clip("missing root", 1, 1, 0, "OtherBone"), clip("no movement", 1, 0, 0, "Translation_Data"))) {
            clips["right"] = invalid
            close(CartLegPace.scale(node, forward, 1f, 0f, 1.04f, clips::get), 1.04, invalid.name)
            close(CartLegPace.scale(node, forward, 1f, 0f, 1.04f, clips::get), 1.04, "cached ${invalid.name}")
        }
        close(forward.getKeyframe(1).position.z, -2, "shared root frames stay unchanged")
        close(forward.getDuration(), 1, "shared clip duration stays unchanged")
        close(CartLegPace.scale(null, 1f, 0f), 1.04, "missing player")
        println("CART_LEG_PACE_PASS (native picker, root velocity, outgoing cadence/reversal, Sprint ramp, load, FPS, invalid clips)")
    }
}
