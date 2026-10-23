package net.alexredby.pztoolkitjavapatches

import java.nio.FloatBuffer
import java.util.WeakHashMap
import org.joml.Matrix4f
import org.joml.Quaternionf
import org.joml.Vector3f
import zombie.characters.IsoPlayer
import zombie.core.math.PZMath
import zombie.core.skinnedmodel.ModelManager
import zombie.core.skinnedmodel.animation.AnimationClip
import zombie.core.skinnedmodel.animation.Keyframe
import zombie.core.skinnedmodel.model.ModelInstance
import zombie.core.skinnedmodel.model.ModelInstanceRenderData
import zombie.core.skinnedmodel.model.ModelSlotRenderData
import zombie.core.skinnedmodel.model.SkinningBone
import zombie.core.skinnedmodel.model.SkinningData

/** Fit hands to the cart handles in this render instance while the native legs keep walking. */
internal object CartGrip {
    private class Matrices {
        val poses = arrayOfNulls<Matrix4f>(60)
        val attachment = Matrix4f()
        val adjustment = Matrix4f()
        val target = Matrix4f()
        val rotation = Quaternionf()
        val headRotation = Quaternionf()
        val headTarget = Quaternionf()
        val model = org.lwjgl.util.vector.Matrix4f()
        val skin = org.lwjgl.util.vector.Matrix4f()
    }

    private val matrices = ThreadLocal.withInitial(::Matrices)
    private val headNeutrals = WeakHashMap<AnimationClip, WeakHashMap<SkinningData, Quaternionf?>>()

    private fun pose(poses: Array<out Matrix4f?>?, index: Int): Matrix4f =
        (poses ?: throw NullPointerException())[index] ?: throw NullPointerException()

    /** Read the body being drawn, rather than a newer live AnimationPlayer pose. */
    @JvmStatic
    fun nativeSpine(
        slot: ModelSlotRenderData?,
        owner: ModelInstance?,
        position: Vector3f?,
    ): Boolean {
        for (data in (slot ?: throw NullPointerException()).modelData) if (
            data.modelInstance === owner &&
                data.matrixPalette != null &&
                (owner ?: throw NullPointerException()).model != null &&
                owner.model.tag is SkinningData
        ) {
            val skin = owner.model.tag as SkinningData
            val index = skin.boneIndices["Bip01_Spine"]
            val palette = data.matrixPalette
            if (
                index == null ||
                    index < 0 ||
                    (index + 1) * 16 > palette.limit() ||
                    index >= skin.boneOffset.size ||
                    skin.boneOffset[index] == null
            )
                return false
            val scratch = matrices.get()
            val before = palette.position()
            try {
                palette.position(index * 16)
                scratch.skin.load(palette)
                PZMath.convertMatrix(scratch.skin, scratch.target).transpose()
                PZMath.convertMatrix(skin.boneOffset[index], scratch.adjustment)
                    .transpose()
                    .invert()
                scratch.target.mul(scratch.adjustment)
                if (!scratch.target.isFinite()) return false
                scratch.target.getTranslation(position)
                return (position ?: throw NullPointerException()).isFinite()
            } finally {
                palette.position(before)
            }
        }
        return false
    }

    @JvmStatic
    fun upperBody(bone: SkinningBone?): Boolean {
        var current = bone
        while (current != null) {
            // Native thighs branch from Spine too; keep their entire walking chains live.
            if ("Bip01_L_Thigh".equals(current.name) || "Bip01_R_Thigh".equals(current.name))
                return false
            if ("Bip01_Spine".equals(current.name)) return true
            current = current.parent
        }
        return false
    }

    @JvmStatic
    fun poses(clip: AnimationClip?, actor: SkinningData?, delta: Matrix4f?): Array<Matrix4f?>? {
        val poses = matrices.get().poses
        if (actor == null || actor.numBones() > poses.size) return null
        if (
            actor.getBone("Bip01_Spine") == null ||
                actor.getBone("Bip01_L_Hand") == null ||
                actor.getBone("Bip01_R_Hand") == null
        )
            return null
        for (i in 0 until actor.numBones()) {
            val bone = actor.getBoneAt(i)
            if (!upperBody(bone)) continue
            if (poses[i] == null) poses[i] = Matrix4f()
            if (!CartGrounding.referencePose(clip, actor, bone.name, poses[i])) return null
            (delta ?: throw NullPointerException()).mul(poses[i], poses[i])
        }
        return poses
    }

    @JvmStatic
    fun livePoses(
        actor: SkinningData?,
        body: SkinningData?,
        palette: FloatBuffer?,
        delta: Matrix4f?,
    ): Array<Matrix4f?>? = livePoses(actor, body, palette, delta, false)

    @JvmStatic
    fun livePoses(
        actor: SkinningData?,
        body: SkinningData?,
        palette: FloatBuffer?,
        delta: Matrix4f?,
        full: Boolean,
    ): Array<Matrix4f?>? {
        val change = delta ?: throw NullPointerException()
        return livePoses(
            actor,
            body,
            palette,
            change,
            full,
            Math.abs(Math.atan2(change.m01().toDouble(), change.m00().toDouble())).toFloat(),
        )
    }

    @JvmStatic
    fun livePoses(
        actor: SkinningData?,
        body: SkinningData?,
        palette: FloatBuffer?,
        delta: Matrix4f?,
        full: Boolean,
        pressure: Float,
    ): Array<Matrix4f?>? {
        val state = matrices.get()
        if (
            actor == null ||
                actor.numBones() > state.poses.size ||
                body == null ||
                palette == null ||
                !(delta ?: throw NullPointerException()).isFinite() ||
                !pressure.isFinite() ||
                pressure < 0
        )
            return null
        val spine = actor.getBone("Bip01_Spine") ?: return null
        val position = palette.position()
        try {
            for (i in 0 until actor.numBones()) {
                val bone = actor.getBoneAt(i)
                if (!full && !upperBody(bone)) continue
                val index = body.boneIndices[bone.name]
                if (
                    index == null ||
                        index < 0 ||
                        (index + 1) * 16 > palette.limit() ||
                        index >= body.boneOffset.size ||
                        body.boneOffset[index] == null
                )
                    return null
                if (state.poses[i] == null) state.poses[i] = Matrix4f()
                palette.position(index * 16)
                state.skin.load(palette)
                PZMath.convertMatrix(state.skin, state.poses[i]).transpose()
                PZMath.convertMatrix(body.boneOffset[index], state.adjustment).transpose().invert()
                pose(state.poses, i).mul(state.adjustment)
                if (!pose(state.poses, i).isFinite()) return null
            }
        } finally {
            palette.position(position)
        }
        val lean = Math.atan2(delta.m01().toDouble(), delta.m00().toDouble()).toFloat()
        var base = pose(state.poses, spine.index)
        val extra = CartSteeringMath.woodenBankExtra(lean)
        val roll = Math.max(-.27925268f, Math.min(.27925268f, (2.1f + .2f * extra) * lean))
        state.adjustment
            .translation(base.m30(), base.m31(), base.m32())
            .rotateZ(roll)
            .translate(-base.m30(), -base.m31(), -base.m32())
        for (i in 0 until actor.numBones()) if (i != spine.index && upperBody(actor.getBoneAt(i)))
            state.adjustment.mul(state.poses[i], state.poses[i])
        val chest = actor.getBone("Bip01_Spine1") ?: return null
        // Bend above the pelvis around the already banked chest; both native leg chains stay
        // untouched.
        base = pose(state.poses, chest.index)
        state.adjustment
            .translation(base.m30(), base.m31(), base.m32())
            .rotateX(
                -Math.toRadians(
                        (14 * CartSteeringMath.woodenTurnAmount(pressure) +
                                6 * CartSteeringMath.woodenBankExtra(pressure))
                            .toDouble(),
                    )
                    .toFloat(),
            )
            .translate(-base.m30(), -base.m31(), -base.m32())
        for (i in 0 until actor.numBones()) if (descendant(actor.getBoneAt(i), chest))
            state.adjustment.mul(state.poses[i], state.poses[i])
        return state.poses
    }

    private fun descendant(bone: SkinningBone?, ancestor: SkinningBone?): Boolean {
        var current = bone
        while (current != null) {
            if (current === ancestor) return true
            current = current.parent
        }
        return false
    }

    private fun adjust(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData,
        root: SkinningBone,
        change: Matrix4f,
    ) {
        for (i in 0 until actor.numBones()) if (descendant(actor.getBoneAt(i), root))
            change.mul(pose(poses, i), pose(poses, i))
    }

    private fun keyRotation(frame: Keyframe?): Quaternionf? {
        if (frame == null || frame.rotation == null) return null
        val q = frame.rotation
        val rotation = Quaternionf(q.x, q.y, q.z, q.w)
        return if (rotation.isFinite() && rotation.lengthSquared() > 1e-12f) rotation.normalize()
        else null
    }

    private fun meanRunningHead(clip: AnimationClip, actor: SkinningData): Quaternionf? {
        val chest = actor.getBone("Bip01_Spine1")
        val neck = actor.getBone("Bip01_Neck")
        val head = actor.getBone("Bip01_Head")
        val duration = clip.getDuration()
        if (
            chest == null ||
                neck == null ||
                head == null ||
                neck.parent !== chest ||
                head.parent !== neck ||
                !duration.isFinite() ||
                duration <= 0
        )
            return null
        val neckFrames = clip.getBoneFramesAt(neck.index)
        val headFrames = clip.getBoneFramesAt(head.index)
        if (neckFrames == null || neckFrames.isEmpty() || headFrames == null || headFrames.size < 2)
            return null
        val neckRotation = keyRotation(neckFrames[0]) ?: return null
        // This authored Run clip has a static Neck; do not silently generalize to another rig/clip.
        for (frame in neckFrames) {
            val q = keyRotation(frame)
            if (
                q == null ||
                    !frame.time.isFinite() ||
                    frame.time < 0 ||
                    frame.time > duration ||
                    Math.abs(neckRotation.dot(q)) < .999999f
            )
                return null
        }
        val rotations = arrayOfNulls<Quaternionf>(headFrames.size)
        for (i in headFrames.indices) {
            val frame = headFrames[i]
            val q = keyRotation(frame)
            if (
                q == null ||
                    !frame.time.isFinite() ||
                    frame.time < 0 ||
                    frame.time > duration ||
                    (i > 0 && frame.time <= headFrames[i - 1].time)
            )
                return null
            rotations[i] = q
        }
        var x = 0.0
        var y = 0.0
        var z = 0.0
        var w = 0.0
        for (i in headFrames.indices) {
            val q = rotations[i] ?: throw NullPointerException()
            val previous =
                (if (i == 0) headFrames[headFrames.size - 1].time - duration
                    else headFrames[i - 1].time)
                    .toDouble()
            val next =
                (if (i == headFrames.size - 1) headFrames[0].time + duration
                    else headFrames[i + 1].time)
                    .toDouble()
            // Circular trapezoid weights also handle a duplicated key at both loop endpoints.
            val weight =
                (next - previous) / 2 *
                    (if ((rotations[0] ?: throw NullPointerException()).dot(q) < 0) -1 else 1)
            x += weight * q.x
            y += weight * q.y
            z += weight * q.z
            w += weight * q.w
        }
        val mean = Quaternionf(x.toFloat(), y.toFloat(), z.toFloat(), w.toFloat())
        return if (mean.isFinite() && mean.lengthSquared() > 1e-12f)
            neckRotation.mul(mean.normalize()).normalize()
        else null
    }

    private fun runningHeadNeutral(clip: AnimationClip?, actor: SkinningData): Quaternionf? =
        synchronized(CartGrip::class.java) {
            if (clip == null) return@synchronized null
            val actors = headNeutrals.computeIfAbsent(clip) { WeakHashMap() }
            if (!actors.containsKey(actor)) actors[actor] = meanRunningHead(clip, actor)
            actors[actor]
        }

    @JvmStatic
    fun calmRunningHead(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        reference: AnimationClip?,
        runWeight: Float,
    ) {
        if (!runWeight.isFinite() || runWeight <= 0 || actor == null || poses == null) return
        val head = actor.getBone("Bip01_Head")
        val chest = actor.getBone("Bip01_Spine1")
        if (head == null || chest == null) return
        val neutral = runningHeadNeutral(reference, actor) ?: return
        val state = matrices.get()
        state.target.rotation(neutral)
        pose(poses, chest.index).mul(state.target, state.target)
        if (!state.target.isFinite()) return
        state.target.getUnnormalizedRotation(state.headTarget).normalize()
        pose(poses, head.index).getUnnormalizedRotation(state.headRotation).normalize()
        if (!state.headTarget.isFinite() || !state.headRotation.isFinite()) return
        // The cart chest leaves native Run's head counter-rotation unbalanced; retain a quarter of
        // its sway.
        state.rotation
            .set(state.headRotation)
            .slerp(state.headTarget, .75f * Math.min(1f, runWeight))
            .mul(state.headRotation.conjugate())
            .normalize()
        val pose = pose(poses, head.index)
        val x = pose.m30()
        val y = pose.m31()
        val z = pose.m32()
        state.adjustment.translation(x, y, z).rotate(state.rotation).translate(-x, -y, -z)
        adjust(poses, actor, head, state.adjustment)
        pose.setTranslation(x, y, z)
    }

    private fun aim(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData,
        root: SkinningBone,
        pivot: Vector3f,
        from: Vector3f,
        to: Vector3f,
    ) {
        val state = matrices.get()
        state.rotation.rotationTo(
            from.sub(pivot, Vector3f()).normalize(),
            to.sub(pivot, Vector3f()).normalize(),
        )
        state.adjustment
            .translation(pivot)
            .rotate(state.rotation)
            .translate(-pivot.x, -pivot.y, -pivot.z)
        adjust(poses, actor, root, state.adjustment)
    }

    // Solve two links without stretching; leg correction keeps the planted foot target.
    @JvmStatic
    fun reach(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        handName: String?,
        target: Matrix4f?,
        bodyDelta: Matrix4f?,
        wood: Boolean,
    ): Boolean = reach(poses, actor, handName, target, bodyDelta, wood, 1f)

    @JvmStatic
    fun reach(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        handName: String?,
        target: Matrix4f?,
        bodyDelta: Matrix4f?,
        wood: Boolean,
        policyWeight: Float,
    ): Boolean = reach(poses, actor, handName, target, bodyDelta, wood, policyWeight, false)

    @JvmStatic
    private fun reach(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        handName: String?,
        target: Matrix4f?,
        bodyDelta: Matrix4f?,
        wood: Boolean,
        policyWeight: Float,
        preserveFootMotion: Boolean,
    ): Boolean =
        reach(
            poses,
            actor,
            handName,
            target,
            bodyDelta,
            wood,
            policyWeight,
            preserveFootMotion,
            false,
        )

    @JvmStatic
    private fun reach(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        handName: String?,
        target: Matrix4f?,
        bodyDelta: Matrix4f?,
        wood: Boolean,
        policyWeight: Float,
        preserveFootMotion: Boolean,
        metal: Boolean,
    ): Boolean {
        if (!policyWeight.isFinite() || policyWeight < 0 || policyWeight > 1) return false
        val skeleton = actor ?: throw NullPointerException()
        val hand = skeleton.getBone(handName)
        if (hand == null || hand.parent == null || hand.parent.parent == null) return false
        if (policyWeight == 0f) return true
        val forearm = hand.parent
        val upper = forearm.parent
        val shoulder = pose(poses, upper.index).getTranslation(Vector3f())
        val elbow = pose(poses, forearm.index).getTranslation(Vector3f())
        val wrist = pose(poses, hand.index).getTranslation(Vector3f())
        val goal = (target ?: throw NullPointerException()).getTranslation(Vector3f())
        val a = shoulder.distance(elbow)
        val b = elbow.distance(wrist)
        var distance = shoulder.distance(goal)
        if (
            !distance.isFinite() ||
                !(a + b).isFinite() ||
                a < .00001f ||
                b < .00001f ||
                distance < .00001f ||
                distance <= Math.abs(a - b)
        )
            return false
        val clavicle = upper.parent
        // Both wheelbarrows need bounded shoulder reach; their elbow bend policies remain separate.
        if (
            (wood || bodyDelta != null) &&
                distance > a + b - .01f &&
                clavicle != null &&
                ("Bip01_L_Clavicle".equals(clavicle.name) ||
                    "Bip01_R_Clavicle".equals(clavicle.name))
        ) {
            val pivot = pose(poses, clavicle.index).getTranslation(Vector3f())
            val from = shoulder.sub(pivot, Vector3f())
            val to = goal.sub(pivot, Vector3f())
            val c = from.length()
            val d = to.length()
            val reserve = a + b - distance
            if (c < .00001f || d < .00001f || !(c + d).isFinite()) return false
            // Ease in before full extension; the native clavicle rotates, with 5mm elbow reserve at
            // the limit.
            val correction =
                if (reserve <= 0) .005f * policyWeight - reserve
                else (.01f - reserve) * (.01f - reserve) / .02f * policyWeight
            val desired = distance - correction
            if (desired <= Math.abs(c - d)) return false
            val angle =
                Math.acos(Math.max(-1f, Math.min(1f, from.dot(to) / (c * d))).toDouble()).toFloat()
            val remaining =
                Math.acos(
                        Math.max(
                                -1f,
                                Math.min(1f, (c * c + d * d - desired * desired) / (2 * c * d)),
                            )
                            .toDouble(),
                    )
                    .toFloat()
            var turn = angle - remaining
            if (!turn.isFinite()) return false
            // Host's native metal Sprint-to-stop pose needs more than 35 degrees even with a
            // straight arm.
            // Keep the same continuous preferred-reserve solve, reducing reserve at the verified
            // 40-degree cap.
            // Other carts and generic reach callers retain their original 35-degree limit.
            turn = Math.min(turn, Math.toRadians((if (metal) 40 else 35).toDouble()).toFloat())
            if (turn > .000001f) {
                val axis = from.cross(to, Vector3f())
                if (axis.lengthSquared() < .00000001f) return false
                val shifted =
                    Quaternionf().rotationAxis(turn, axis.normalize()).transform(from).add(pivot)
                if (shifted.distance(goal) >= a + b) return false
                aim(poses, skeleton, clavicle, pivot, shoulder, shifted)
                pose(poses, clavicle.index).setTranslation(pivot)
                pose(poses, upper.index).getTranslation(shoulder)
                pose(poses, forearm.index).getTranslation(elbow)
                pose(poses, hand.index).getTranslation(wrist)
                distance = shoulder.distance(goal)
            }
        }
        if (distance >= a + b) return false
        val axis = goal.sub(shoulder, Vector3f()).div(distance)
        val bend = elbow.sub(shoulder, Vector3f())
        if (
            (handName ?: throw NullPointerException()).equals("Bip01_L_Foot") ||
                handName.equals("Bip01_R_Foot")
        ) {
            val toe = skeleton.getBone(handName.replace("_Foot", "_Toe0"))
            if (toe == null || toe.parent !== hand) return false
            if (preserveFootMotion) {
                // Native Run/Sprint calves flex around thigh-local +Y. Toe-off can turn the
                // horizontal toe projection backwards without reversing that anatomical hinge.
                axis.cross(pose(poses, upper.index).transformDirection(Vector3f(0f, 1f, 0f)), bend)
            } else {
                // A shifted squat hip can put the knee behind the new leg axis; face the planted
                // toes.
                pose(poses, toe.index).getTranslation(bend).sub(wrist)
                bend.y = 0f
            }
        }
        if (bodyDelta != null) {
            val nativeBend =
                if (policyWeight < 1) Vector3f(bend).fma(-bend.dot(axis), axis) else null
            bend.set(goal).sub(shoulder).fma(-b, Vector3f(target.m00(), target.m01(), target.m02()))
            bend.fma(-bend.dot(axis), axis).normalize()
            val relaxed = bodyDelta.transformDirection(Vector3f(0f, -1f, if (wood) 1f else .25f))
            relaxed.fma(-relaxed.dot(axis), axis).normalize()
            // Keep the elbow down/back instead of lifting it just to minimize the wrist angle.
            val extra =
                if (wood)
                    CartSteeringMath.woodenBankExtra(
                        Math.atan2(bodyDelta.m01().toDouble(), bodyDelta.m00().toDouble())
                            .toFloat(),
                    )
                else 0f
            bend.lerp(relaxed, .6f - .05f * extra)
            if (nativeBend != null) {
                if (!nativeBend.isFinite() || nativeBend.lengthSquared() < .00000001f) return false
                bend.fma(-bend.dot(axis), axis).normalize()
                nativeBend.normalize()
                Quaternionf()
                    .slerp(Quaternionf().rotationTo(nativeBend, bend), policyWeight)
                    .transform(nativeBend, bend)
            }
        }
        bend.fma(-bend.dot(axis), axis)
        if (!bend.isFinite() || bend.lengthSquared() < .00000001f) return false
        val along = (a * a - b * b + distance * distance) / (2 * distance)
        val solved =
            shoulder
                .fma(along, axis, Vector3f())
                .fma(
                    Math.sqrt(Math.max(0f, a * a - along * along).toDouble()).toFloat(),
                    bend.normalize(),
                )
        aim(poses, skeleton, upper, shoulder, elbow, solved)
        pose(poses, hand.index).getTranslation(wrist)
        aim(poses, skeleton, forearm, solved, wrist, goal)
        val adjustment = matrices.get().adjustment
        if (bodyDelta != null) {
            // Pronation belongs in the forearm, rather than twisting the entire underhand turn at
            // the wrist.
            val forearmAxis = goal.sub(solved, Vector3f()).normalize()
            val from = pose(poses, forearm.index).transformDirection(Vector3f(0f, 0f, 1f))
            val to = target.transformDirection(Vector3f(0f, 0f, 1f))
            from.fma(-from.dot(forearmAxis), forearmAxis).normalize()
            to.fma(-to.dot(forearmAxis), forearmAxis).normalize()
            val roll =
                Math.atan2(
                        forearmAxis.dot(from.cross(to, Vector3f())).toDouble(),
                        from.dot(to).toDouble(),
                    )
                    .toFloat() * policyWeight
            adjustment
                .translation(solved)
                .rotate(roll, forearmAxis)
                .translate(-solved.x, -solved.y, -solved.z)
            adjust(poses, skeleton, forearm, adjustment)
        }
        pose(poses, hand.index).invert(adjustment)
        target.mul(adjustment, adjustment)
        adjust(poses, skeleton, hand, adjustment)
        return true
    }

    // shortcut: these are native MaleBody/FemaleBody mesh measurements; recalibrate for another
    // hand mesh/rig.
    @JvmRecord
    data class Grasp(val palmX: Float, val palmDepth: Float, val curl: Float) {
        override fun toString() = "Grasp[palmX=$palmX, palmDepth=$palmDepth, curl=$curl]"
    }

    private val MALE_ROUND = Grasp(.055f, .027f, -1.68f)
    private val FEMALE_ROUND = Grasp(.063f, .025f, -1.55f)
    private val MALE_WOOD = Grasp(.055f, .020f, -1.4f)
    private val FEMALE_WOOD = Grasp(.055f, .024f, -1.75f)
    private val MALE_METAL = Grasp(.050f, .0335f, -1.5f)
    private val FEMALE_METAL = Grasp(.045f, .0272f, -1.7f)

    @JvmStatic
    fun grasp(female: Boolean, model: String?): Grasp {
        if ("WheelbarrowWood".equals(model)) return if (female) FEMALE_WOOD else MALE_WOOD
        if ("WheelbarrowMetal".equals(model)) return if (female) FEMALE_METAL else MALE_METAL
        return if (female) FEMALE_ROUND else MALE_ROUND
    }

    // shortcut: B42 has one mitten segment and one thumb, so individual phalange wrapping needs a
    // detailed rig.
    @JvmStatic
    fun closeFingers(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        side: String?,
        grasp: Grasp?,
        underhand: Boolean,
    ) {
        val skeleton = actor ?: throw NullPointerException()
        val hand = skeleton.getBone("Bip01_${side}_Hand")
        val fingers = skeleton.getBone("Bip01_${side}_Finger1")
        val thumb = skeleton.getBone("Bip01_${side}_Finger0")
        if (hand == null || fingers == null || thumb == null) return
        val handPose = pose(poses, hand.index)
        val local = Matrix4f(handPose).invert().mul(pose(poses, fingers.index))
        val target =
            Matrix4f(handPose)
                .translate(local.m30(), local.m31(), local.m32())
                .rotateY((grasp ?: throw NullPointerException()).curl)
        val change = matrices.get().adjustment
        pose(poses, fingers.index).invert(change)
        target.mul(change, change)
        adjust(poses, skeleton, fingers, change)
        if (grasp === MALE_WOOD || grasp === FEMALE_WOOD) {
            // Follow the steeper wooden grip while keeping the thumb knuckle and native twist.
            handPose.invert(change).mul(pose(poses, thumb.index))
            val thumbLocal = Matrix4f(change).setTranslation(0f, 0f, 0f)
            target
                .set(handPose)
                .translate(change.m30(), change.m31(), change.m32())
                .rotateY(
                    Math.toRadians((if (grasp === FEMALE_WOOD) 10 else 20).toDouble()).toFloat(),
                )
                .rotateZ(Math.toRadians((if ("L".equals(side)) -35 else 35).toDouble()).toFloat())
                .mul(thumbLocal)
            pose(poses, thumb.index).invert(change)
            target.mul(change, change)
            adjust(poses, skeleton, thumb, change)
        }
        if (underhand) return
        val pivot = pose(poses, thumb.index).getTranslation(Vector3f())
        val from = pose(poses, thumb.index).transformPosition(Vector3f(.033f, 0f, 0f))
        val to =
            handPose.transformPosition(
                Vector3f(.045f, if ("L".equals(side)) -.001f else .001f, .025f),
            )
        aim(poses, skeleton, thumb, pivot, from, to)
    }

    private fun referenceThumb(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData,
        clip: AnimationClip?,
        side: String?,
    ): Boolean {
        // Action clips and their native blend-out already contain closure; apply it only once.
        val hand = actor.getBone("Bip01_${side}_Hand")
        val thumb = actor.getBone("Bip01_${side}_Finger0")
        val referenceHand = Matrix4f()
        val referenceThumb = Matrix4f()
        if (
            hand == null ||
                thumb == null ||
                !CartGrounding.referencePose(clip, actor, hand.name, referenceHand) ||
                !CartGrounding.referencePose(clip, actor, thumb.name, referenceThumb)
        )
            return false
        val local = Matrix4f(pose(poses, hand.index)).invert().mul(pose(poses, thumb.index))
        referenceHand
            .invert()
            .mul(referenceThumb)
            .setTranslation(local.m30(), local.m31(), local.m32())
        val change =
            Matrix4f(pose(poses, hand.index))
                .mul(referenceHand)
                .mul(Matrix4f(pose(poses, thumb.index)).invert())
        adjust(poses, actor, thumb, change)
        return true
    }

    // Mesh-local grip stations measured from the GPU handles; keep the whole palm inside the finite
    // shaft.
    @JvmStatic
    fun handle(model: String?, left: Boolean, point: Vector3f?): Boolean {
        if (model == null) return false
        when (model) {
            "ShoppingCartModel",
            "ShoppingCartPartialModel",
            "ShoppingCartFullModel",
            "ShoppingCartFlashlightModel",
            "ShoppingCartFlashlightPartialModel",
            "ShoppingCartFlashlightFullModel" ->
                (point ?: throw NullPointerException()).set(
                    -150.07166f,
                    343.47412f,
                    if (left) .809756f else -.809769f,
                )
            "WheelbarrowWood" ->
                (point ?: throw NullPointerException()).set(
                    if (left) .00172237f else -.00172238f,
                    .00541905f,
                    -.00342593f,
                )
            "WheelbarrowMetal" ->
                (point ?: throw NullPointerException()).set(
                    if (left) -7.409948f else -39.674755f,
                    6.614635f,
                    81.45f,
                )
            else -> return false
        }
        return true
    }

    @JvmStatic
    fun target(
        model: String?,
        left: Boolean,
        female: Boolean,
        delta: Matrix4f?,
        cart: Matrix4f?,
        out: Matrix4f?,
    ): Boolean {
        val change = delta ?: throw NullPointerException()
        return target(
            model,
            left,
            female,
            change,
            cart,
            out,
            Math.abs(Math.atan2(change.m01().toDouble(), change.m00().toDouble())).toFloat(),
        )
    }

    @JvmStatic
    fun target(
        model: String?,
        left: Boolean,
        female: Boolean,
        delta: Matrix4f?,
        cart: Matrix4f?,
        out: Matrix4f?,
        pressure: Float,
    ): Boolean =
        target(model, left, female, delta, cart, out, pressure, Math.toRadians(5.0).toFloat())

    @JvmStatic
    fun transitionTarget(
        model: String?,
        left: Boolean,
        female: Boolean,
        delta: Matrix4f?,
        cart: Matrix4f?,
        out: Matrix4f?,
    ): Boolean {
        var radial = Math.toRadians(5.0).toFloat()
        if ("WheelbarrowMetal".equals(model)) {
            // Follow the actual shaft elevation, including a cancelled/restarted lift.
            // Turning the complete grasp around the shaft keeps its contact station,
            // thumb opposition and across-palm angle, while relaxing the low wrist.
            val held = CartWheelbarrow.METAL.held(Matrix4f())
            val heldAngle =
                Math.atan2(
                    held.m21().toDouble(),
                    Math.hypot(held.m20().toDouble(), held.m22().toDouble()),
                )
            val current = cart ?: throw NullPointerException()
            val angle =
                Math.atan2(
                    current.m21().toDouble(),
                    Math.hypot(current.m20().toDouble(), current.m22().toDouble()),
                )
            val lift =
                Math.max(
                    0.0,
                    Math.min(
                        1.0,
                        (angle + CartWorldSupport.pitch()) / (heldAngle + CartWorldSupport.pitch()),
                    ),
                )
            radial = Math.toRadians(-20 + 25 * lift).toFloat()
        }
        val change = delta ?: throw NullPointerException()
        return target(
            model,
            left,
            female,
            change,
            cart,
            out,
            Math.abs(Math.atan2(change.m01().toDouble(), change.m00().toDouble())).toFloat(),
            radial,
        )
    }

    private fun target(
        model: String?,
        left: Boolean,
        female: Boolean,
        delta: Matrix4f?,
        cart: Matrix4f?,
        out: Matrix4f?,
        pressure: Float,
        radial: Float,
    ): Boolean {
        if (!pressure.isFinite() || pressure < 0 || !radial.isFinite()) return false
        val point = Vector3f()
        if (!handle(model, left, point)) return false
        val current = cart ?: throw NullPointerException()
        current.transformPosition(point)
        val wood = "WheelbarrowWood".equals(model)
        val metal = "WheelbarrowMetal".equals(model)
        val shape = grasp(female, model)
        val result = out ?: throw NullPointerException()
        result.identity()
        if (wood || metal) {
            val axis =
                if (wood) Vector3f(if (left) .13444413f else -.13444413f, .98614604f, -.09716362f)
                else Vector3f(0f, 0f, 1f)
            val down = if (wood) Vector3f(0f, .098053805f, .9951811f) else Vector3f(0f, -1f, 0f)
            current.transformDirection(axis).normalize()
            current.transformDirection(down).normalize()
            val inward = down.cross(axis, Vector3f()).normalize().mul(if (left) 1f else -1f)
            // Diagonal underhand grip: shaft across curled fingers, palm inward/up, wrist above the
            // handle.
            val cos = Math.cos(radial.toDouble()).toFloat()
            val sin = Math.sin(radial.toDouble()).toFloat()
            val x = down.mul(cos, Vector3f()).fma(sin, inward)
            var z = inward.mul(cos, Vector3f()).fma(-sin, down)
            // Turn the closed fist across the shaft instead of opening its fingers to gain
            // clearance.
            val beta =
                Math.toRadians(
                        (if (wood) 25 + 10 * CartSteeringMath.woodenTurnAmount(pressure)
                            else if (female) 25f else 20f)
                            .toDouble(),
                    )
                    .toFloat()
            x.mul(Math.cos(beta.toDouble()).toFloat())
                .fma(-Math.sin(beta.toDouble()).toFloat(), axis)
                .normalize()
            val y = z.cross(x, Vector3f()).normalize()
            z = x.cross(y, Vector3f()).normalize()
            result.m00(x.x).m01(x.y).m02(x.z).m10(y.x).m11(y.y).m12(y.z).m20(z.x).m21(z.y).m22(z.z)
        } else {
            result.m00(0f).m01(0f).m02(-1f).m10(1f).m11(0f).m12(0f).m20(0f).m21(-1f).m22(0f)
        }
        if (!wood && !metal) (delta ?: throw NullPointerException()).mul(result, result)
        result.setTranslation(
            point.x - result.m00() * shape.palmX - result.m20() * shape.palmDepth,
            point.y - result.m01() * shape.palmX - result.m21() * shape.palmDepth,
            point.z - result.m02() * shape.palmX - result.m22() * shape.palmDepth,
        )
        return result.isFinite()
    }

    @JvmStatic
    fun grip(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        model: String?,
        female: Boolean,
        delta: Matrix4f?,
        cart: Matrix4f?,
    ): Boolean {
        val change = delta ?: throw NullPointerException()
        return grip(
            poses,
            actor,
            model,
            female,
            change,
            cart,
            Math.abs(Math.atan2(change.m01().toDouble(), change.m00().toDouble())).toFloat(),
        )
    }

    @JvmStatic
    fun grip(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        model: String?,
        female: Boolean,
        delta: Matrix4f?,
        cart: Matrix4f?,
        pressure: Float,
    ): Boolean {
        for (side in arrayOf("L", "R")) {
            val target = matrices.get().target
            if (
                !target(model, "L".equals(side), female, delta, cart, target, pressure) ||
                    !reach(
                        poses,
                        actor,
                        "Bip01_${side}_Hand",
                        target,
                        if ((model ?: throw NullPointerException()).startsWith("Wheelbarrow")) delta
                        else null,
                        "WheelbarrowWood".equals(model),
                        1f,
                        false,
                        "WheelbarrowMetal".equals(model),
                    )
            )
                return false
            closeFingers(poses, actor, side, grasp(female, model), model.startsWith("Wheelbarrow"))
        }
        return true
    }

    @JvmStatic
    fun skin(
        palette: FloatBuffer?,
        shaderPalette: Array<org.lwjgl.util.vector.Matrix4f?>?,
        target: SkinningData?,
        actor: SkinningData?,
        poses: Array<out Matrix4f?>?,
    ): Int = skin(palette, shaderPalette, target, actor, poses, false)

    @JvmStatic
    fun skin(
        palette: FloatBuffer?,
        shaderPalette: Array<org.lwjgl.util.vector.Matrix4f?>?,
        target: SkinningData?,
        actor: SkinningData?,
        poses: Array<out Matrix4f?>?,
        full: Boolean,
    ): Int {
        val state = matrices.get()
        val buffer = palette ?: throw NullPointerException()
        val position = buffer.position()
        var changed = 0
        try {
            val skin = target ?: throw NullPointerException()
            for (entry in skin.boneIndices.entries) {
                val bone = (actor ?: throw NullPointerException()).getBone(entry.key)
                val index = entry.value
                if (
                    bone == null ||
                        !full && !upperBody(bone) ||
                        index < 0 ||
                        (index + 1) * 16 > buffer.limit() ||
                        index >= skin.boneOffset.size ||
                        skin.boneOffset[index] == null
                )
                    continue
                PZMath.convertMatrix(pose(poses, bone.index), state.model).transpose()
                // Native skin matrices are inverse-bind * model-pose in transposed LWJGL storage.
                org.lwjgl.util.vector.Matrix4f.mul(skin.boneOffset[index], state.model, state.skin)
                buffer.position(index * 16)
                state.skin.store(buffer)
                if (shaderPalette != null && index < shaderPalette.size) {
                    if (shaderPalette[index] == null)
                        shaderPalette[index] = org.lwjgl.util.vector.Matrix4f()
                    (shaderPalette[index] ?: throw NullPointerException()).load(state.skin)
                }
                changed++
            }
        } finally {
            buffer.position(position)
        }
        return changed
    }

    private fun body(slot: ModelSlotRenderData?, owner: ModelInstance?): ModelInstanceRenderData? {
        for (data in (slot ?: throw NullPointerException()).modelData) if (
            data.modelInstance === owner
        )
            return data
        return null
    }

    @JvmStatic
    fun render(
        slot: ModelSlotRenderData?,
        owner: ModelInstance?,
        clip: AnimationClip?,
        delta: Matrix4f?,
        model: String?,
        cart: Matrix4f?,
    ): Boolean {
        val body = body(slot, owner)
        if (
            body == null ||
                body.matrixPalette == null ||
                (owner ?: throw NullPointerException()).model.tag !is SkinningData
        )
            return false
        val bodySkin = owner.model.tag as SkinningData
        for (hand in arrayOf("Bip01_L_Hand", "Bip01_R_Hand")) {
            val index = bodySkin.boneIndices[hand]
            if (
                index == null ||
                    index < 0 ||
                    (index + 1) * 16 > body.matrixPalette.limit() ||
                    index >= bodySkin.boneOffset.size ||
                    bodySkin.boneOffset[index] == null
            )
                return false
        }
        val actor = owner.animPlayer.getSkinningData()
        val change = delta ?: throw NullPointerException()
        var pressure =
            Math.abs(Math.atan2(change.m01().toDouble(), change.m00().toDouble())).toFloat()
        val player = (slot ?: throw NullPointerException()).character
        if (player is IsoPlayer)
            pressure = Math.max(pressure, CartSteeringHooks.clearanceLean(player).toFloat())
        // Retain the wooden cart gait's spine/clavicle motion; IK absorbs arm swing at the fixed
        // handles.
        val shopping = CartShopping.model(model)
        if (shopping) pressure = 0f
        var poses =
            if (CartWheelbarrow.forModel(model) != null || shopping)
                livePoses(actor, bodySkin, body.matrixPalette, change, false, pressure)
            else poses(clip, actor, change)
        if (
            poses == null ||
                (CartWheelbarrow.forModel(model) != null || shopping) &&
                    (!referenceThumb(poses, actor, clip, "L") ||
                        !referenceThumb(poses, actor, clip, "R")) ||
                !grip(poses, actor, model, slot.character.isFemale(), change, cart, pressure)
        )
            return false
        if ("WheelbarrowWood".equals(model)) {
            var mesh: zombie.core.skinnedmodel.model.ModelMesh? = null
            var carts = 0
            for (data in slot.modelData) if (
                data.modelInstance.parent === owner &&
                    data.modelInstance.modelScript != null &&
                    model.equals(data.modelInstance.modelScript.getName()) &&
                    data.modelInstance.model != null
            ) {
                mesh = data.modelInstance.model.mesh
                carts++
            }
            val shift =
                if (carts == 1)
                    CartLegClearance.shift(slot, owner, mesh, cart, pressure, actor, poses)
                else 0.0
            if (shift.isFinite() && shift != 0.0) {
                val current = cart ?: throw NullPointerException()
                val fitted = Matrix4f(current).m30(current.m30() + shift.toFloat())
                // Rebuild from the unchanged native palette: never apply torso/finger adjustments
                // twice.
                poses = livePoses(actor, bodySkin, body.matrixPalette, change, false, pressure)
                val valid =
                    CartLegClearance.withinFootprint(fitted) &&
                        poses != null &&
                        referenceThumb(poses, actor, clip, "L") &&
                        referenceThumb(poses, actor, clip, "R") &&
                        grip(
                            poses,
                            actor,
                            model,
                            slot.character.isFemale(),
                            change,
                            fitted,
                            pressure,
                        ) &&
                        CartLegClearance.shift(slot, owner, mesh, fitted, pressure, actor, poses) ==
                            0.0
                if (valid) current.set(fitted)
                else {
                    // Recheck after IK because the selected cage includes a few upper-body
                    // influences.
                    // A refused corridor keeps the established cart/grip pose instead of forcing a
                    // fit.
                    poses = livePoses(actor, bodySkin, body.matrixPalette, change, false, pressure)
                    if (
                        poses == null ||
                            !referenceThumb(poses, actor, clip, "L") ||
                            !referenceThumb(poses, actor, clip, "R") ||
                            !grip(
                                poses,
                                actor,
                                model,
                                slot.character.isFemale(),
                                change,
                                current,
                                pressure,
                            )
                    )
                        return false
                }
            }
        }
        if (CartWheelbarrow.forModel(model) != null) {
            val runWeight = CartLegPace.runningWeight(slot.character)
            if (runWeight > 0) {
                val runReference =
                    try {
                        ModelManager.instance.getAnimationClip("Bob_Cart_Run")
                    } catch (unavailable: NullPointerException) {
                        null
                    }
                calmRunningHead(poses, actor, runReference, runWeight)
            }
        }
        skinSlot(slot, owner, clip, actor, poses)
        return true
    }

    @JvmStatic
    fun groundFeet(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        idle: AnimationClip?,
        cartIdle: AnimationClip?,
        liftWeight: Float,
    ): Boolean = groundFeet(poses, actor, idle, cartIdle, liftWeight, 0f, 0f, 0f)

    @JvmStatic
    fun groundFeet(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        idle: AnimationClip?,
        cartIdle: AnimationClip?,
        liftWeight: Float,
        shiftX: Float,
        shiftY: Float,
        shiftZ: Float,
    ): Boolean = groundFeet(poses, actor, idle, cartIdle, liftWeight, shiftX, shiftY, shiftZ, false)

    @JvmStatic
    fun groundFeet(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        idle: AnimationClip?,
        cartIdle: AnimationClip?,
        liftWeight: Float,
        shiftX: Float,
        shiftY: Float,
        shiftZ: Float,
        preserveFootMotion: Boolean,
    ): Boolean {
        if (
            !liftWeight.isFinite() ||
                liftWeight < 0 ||
                liftWeight > 1 ||
                !(shiftX + shiftY + shiftZ).isFinite() ||
                Math.abs(shiftX) > .1f ||
                shiftY > 0 ||
                shiftY < -.08f ||
                Math.abs(shiftZ) > .23f
        )
            return false
        if (preserveFootMotion && shiftX == 0f && shiftY == 0f && shiftZ == 0f) return true
        val targets = arrayOfNulls<Matrix4f>(2)
        val sides = arrayOf("L", "R")
        for (i in sides.indices) {
            val side = sides[i]
            val skeleton = actor ?: throw NullPointerException()
            val foot = skeleton.getBone("Bip01_${side}_Foot")
            val toe = skeleton.getBone("Bip01_${side}_Toe0")
            if (
                foot == null ||
                    toe == null ||
                    toe.parent !== foot ||
                    foot.parent == null ||
                    foot.parent.parent == null
            )
                return false
            var correction = 0f
            if (!preserveFootMotion) {
                val from = Matrix4f()
                val to = Matrix4f()
                if (
                    !CartGrounding.referencePose(idle, skeleton, toe.name, from) ||
                        !CartGrounding.referencePose(cartIdle, skeleton, toe.name, to)
                )
                    return false
                val height = from.m31() + (to.m31() - from.m31()) * liftWeight
                correction = height - pose(poses, toe.index).m31()
            }
            if (Math.abs(correction) >= .0001f || shiftX != 0f || shiftY != 0f || shiftZ != 0f) {
                val target = Matrix4f(pose(poses, foot.index))
                targets[i] = target
                target.m31(target.m31() + correction)
            }
        }
        // Shift weight behind/between the low handles while keeping the torso rigid and both feet
        // planted.
        if (shiftX != 0f || shiftY != 0f || shiftZ != 0f)
            for (i in 0 until (actor ?: throw NullPointerException()).numBones()) pose(poses, i)
                .translateLocal(shiftX, shiftY, shiftZ)
        for (i in sides.indices) if (
            targets[i] != null &&
                !reach(
                    poses,
                    actor,
                    "Bip01_${sides[i]}_Foot",
                    targets[i],
                    null,
                    false,
                    1f,
                    preserveFootMotion,
                )
        )
            return false
        return true
    }

    @JvmStatic
    fun bendTransitionTorso(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        angle: Float,
    ): Boolean {
        if (!angle.isFinite() || angle < 0 || angle > Math.PI / 2) return false
        val skeleton = actor ?: throw NullPointerException()
        val spine = skeleton.getBone("Bip01_Spine") ?: return false
        if (angle == 0f) return true
        val base = pose(poses, spine.index)
        val bend =
            Matrix4f()
                .translation(base.m30(), base.m31(), base.m32())
                .rotateX(-angle)
                .translate(-base.m30(), -base.m31(), -base.m32())
        // Native thighs branch from Spine too; a hip hinge must leave both leg chains alone.
        for (i in 0 until skeleton.numBones()) if (upperBody(skeleton.getBoneAt(i)))
            bend.mul(pose(poses, i), pose(poses, i))
        for (side in arrayOf("L", "R")) {
            val upper = skeleton.getBone("Bip01_${side}_UpperArm") ?: return false
            val shoulder = pose(poses, upper.index).getTranslation(Vector3f())
            // Let the arms hang toward the handles instead of carrying them backward with the
            // torso.
            val hang =
                Matrix4f()
                    .translation(shoulder)
                    .rotateX(angle)
                    .translate(-shoulder.x, -shoulder.y, -shoulder.z)
            adjust(poses, skeleton, upper, hang)
        }
        return true
    }

    @JvmRecord
    data class Posture(val height: Float, val rotation: Quaternionf?) {
        override fun toString() = "Posture[height=$height, rotation=$rotation]"
    }

    private fun validRotation(rotation: Quaternionf?): Boolean =
        rotation != null &&
            rotation.isFinite() &&
            rotation.lengthSquared().isFinite() &&
            rotation.lengthSquared() > 1e-12f

    @JvmStatic
    fun validPosture(height: Float, rotation: Quaternionf?): Boolean =
        height.isFinite() && validRotation(rotation)

    @JvmStatic
    fun nativePosture(slot: ModelSlotRenderData?, owner: ModelInstance?): Posture? {
        for (body in (slot ?: throw NullPointerException()).modelData) if (
            body.modelInstance === owner &&
                body.matrixPalette != null &&
                (owner ?: throw NullPointerException()).model.tag is SkinningData
        ) {
            val skin = owner.model.tag as SkinningData
            val actor = owner.animPlayer.getSkinningData()
            val spine = if (actor == null) null else actor.getBone("Bip01_Spine")
            val chest = if (actor == null) null else actor.getBone("Bip01_Spine1")
            if (spine == null || chest == null) return null
            val poses = livePoses(actor, skin, body.matrixPalette, Matrix4f(), true) ?: return null
            val rotation = pose(poses, chest.index).getUnnormalizedRotation(Quaternionf())
            val height = pose(poses, spine.index).m31()
            return if (validPosture(height, rotation)) Posture(height, rotation.normalize())
            else null
        }
        return null
    }

    @JvmStatic
    fun referencePosture(actor: SkinningData?, phase: CartTransitionMath.Progress?): Posture? {
        val reference = Matrix4f()
        val heights = FloatArray(3)
        val rotations = arrayOfNulls<Quaternionf>(3)
        val clips = arrayOf("Bob_Idle", "Bob_IdleLooting_Low", "Bob_Cart_Idle")
        for (i in clips.indices) {
            val clip = ModelManager.instance.getAnimationClip(clips[i])
            if (!CartGrounding.referencePose(clip, actor, "Bip01_Spine", reference)) return null
            heights[i] = reference.m31()
            if (!CartGrounding.referencePose(clip, actor, "Bip01_Spine1", reference)) return null
            rotations[i] = reference.getUnnormalizedRotation(Quaternionf())
            if (!validRotation(rotations[i])) return null
            (rotations[i] ?: throw NullPointerException()).normalize()
        }
        val height =
            CartTransitionMath.nativeHeight(
                    phase,
                    heights[0].toDouble(),
                    heights[1].toDouble(),
                    heights[2].toDouble(),
                )
                .toFloat()
        // The same shallow low/idle edge and lift weight as the native action's 2D triangle.
        val value = phase ?: throw NullPointerException()
        val rotation =
            (rotations[0] ?: throw NullPointerException())
                .slerp(rotations[1], (.10 * value.crouch).toFloat())
                .slerp(rotations[2], value.lift.toFloat())
                .normalize()
        return if (validPosture(height, rotation)) Posture(height, rotation) else null
    }

    @JvmStatic
    fun recoverPosture(
        start: Posture?,
        referenceStart: Posture?,
        reference: Posture?,
        amount: Float,
    ): Posture? {
        if (
            start == null ||
                referenceStart == null ||
                reference == null ||
                !amount.isFinite() ||
                amount < 0 ||
                amount > 1 ||
                !validPosture(start.height, start.rotation) ||
                !validPosture(referenceStart.height, referenceStart.rotation) ||
                !validPosture(reference.height, reference.rotation)
        )
            return null
        val residual =
            Quaternionf(referenceStart.rotation)
                .normalize()
                .conjugate()
                .mul(Quaternionf(start.rotation).normalize())
                .normalize()
        val rotation =
            Quaternionf(reference.rotation)
                .normalize()
                .mul(Quaternionf().slerp(residual, amount))
                .normalize()
        val height = reference.height + (start.height - referenceStart.height) * amount
        return if (validPosture(height, rotation)) Posture(height, rotation) else null
    }

    @JvmStatic
    fun nativeRotation(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        target: Quaternionf?,
    ): Boolean {
        if (
            actor == null ||
                poses == null ||
                poses.size < actor.numBones() ||
                !validRotation(target)
        )
            return false
        val spine = actor.getBone("Bip01_Spine")
        val chest = actor.getBone("Bip01_Spine1")
        if (
            spine == null ||
                chest == null ||
                poses[spine.index] == null ||
                poses[chest.index] == null ||
                !pose(poses, spine.index).isFinite() ||
                !pose(poses, chest.index).isFinite()
        )
            return false
        val current = pose(poses, chest.index).getUnnormalizedRotation(Quaternionf())
        if (!validRotation(current)) return false
        val correction =
            Quaternionf(target).normalize().mul(current.normalize().conjugate()).normalize()
        val angle = 2 * Math.acos(Math.min(1f, Math.abs(correction.w)).toDouble()).toFloat()
        if (!angle.isFinite() || angle > Math.toRadians(20.0).toFloat()) return false
        for (i in 0 until actor.numBones()) if (
            upperBody(actor.getBoneAt(i)) && (poses[i] == null || !pose(poses, i).isFinite())
        )
            return false
        if (angle < .000001f) return true
        val pivot = pose(poses, spine.index).getTranslation(Vector3f())
        val change =
            Matrix4f().translation(pivot).rotate(correction).translate(-pivot.x, -pivot.y, -pivot.z)
        if (!change.isFinite()) return false
        for (i in 0 until actor.numBones()) if (upperBody(actor.getBoneAt(i)))
            change.mul(poses[i], poses[i])
        pose(poses, spine.index).setTranslation(pivot)
        return true
    }

    @JvmStatic
    fun nativeHeight(poses: Array<out Matrix4f?>?, actor: SkinningData?, target: Float): Boolean {
        if (!target.isFinite()) return false
        val skeleton = actor ?: throw NullPointerException()
        val spine = skeleton.getBone("Bip01_Spine") ?: return false
        val correction = target - pose(poses, spine.index).m31()
        if (!correction.isFinite() || Math.abs(correction) > .2f) return false
        for (i in 0 until skeleton.numBones()) pose(poses, i).translateLocal(0f, correction, 0f)
        return true
    }

    @JvmStatic
    fun transition(
        slot: ModelSlotRenderData?,
        owner: ModelInstance?,
        delta: Matrix4f?,
        cart: Matrix4f?,
        reachWeight: Float,
        gripWeight: Float,
        liftWeight: Float,
        shiftX: Float,
        shiftY: Float,
        shiftZ: Float,
        hinge: Float,
        baseHeight: Float,
        baseRotation: Quaternionf?,
    ): Boolean =
        transition(
            slot,
            owner,
            delta,
            cart,
            reachWeight,
            gripWeight,
            liftWeight,
            shiftX,
            shiftY,
            shiftZ,
            hinge,
            baseHeight,
            baseRotation,
            "WheelbarrowWood",
        )

    @JvmStatic
    fun transition(
        slot: ModelSlotRenderData?,
        owner: ModelInstance?,
        delta: Matrix4f?,
        cart: Matrix4f?,
        reachWeight: Float,
        gripWeight: Float,
        liftWeight: Float,
        shiftX: Float,
        shiftY: Float,
        shiftZ: Float,
        hinge: Float,
        baseHeight: Float,
        baseRotation: Quaternionf?,
        model: String?,
    ): Boolean {
        val body = body(slot, owner)
        if (
            body == null ||
                body.matrixPalette == null ||
                (owner ?: throw NullPointerException()).model.tag !is SkinningData
        )
            return false
        val bodySkin = owner.model.tag as SkinningData
        val actor = owner.animPlayer.getSkinningData()
        val poses = livePoses(actor, bodySkin, body.matrixPalette, Matrix4f(), true)
        if (
            poses == null ||
                baseHeight.isFinite() && !nativeHeight(poses, actor, baseHeight) ||
                baseRotation != null && !nativeRotation(poses, actor, baseRotation) ||
                !bendTransitionTorso(poses, actor, hinge)
        )
            return false
        val cartIdle = ModelManager.instance.getAnimationClip("Bob_Cart_Idle")
        if (
            !groundFeet(
                poses,
                actor,
                ModelManager.instance.getAnimationClip("Bob_Idle"),
                cartIdle,
                liftWeight,
                shiftX,
                shiftY,
                shiftZ,
            )
        )
            return false
        if (
            !transitionGrip(
                poses,
                actor,
                (slot ?: throw NullPointerException()).character.isFemale(),
                delta,
                cart,
                reachWeight,
                gripWeight,
                null,
                model,
            )
        )
            return false
        skinSlot(slot, owner, cartIdle, actor, poses, true)
        return true
    }

    @JvmStatic
    fun authoredTransition(
        slot: ModelSlotRenderData?,
        owner: ModelInstance?,
        clip: AnimationClip?,
        delta: Matrix4f?,
        cart: Matrix4f?,
        reachWeight: Float,
        gripWeight: Float,
        restartPose: Array<out Matrix4f?>?,
        restartWeight: Float,
    ): Boolean =
        authoredTransition(
            slot,
            owner,
            clip,
            delta,
            cart,
            reachWeight,
            gripWeight,
            restartPose,
            restartWeight,
            "WheelbarrowWood",
        )

    @JvmStatic
    fun authoredTransition(
        slot: ModelSlotRenderData?,
        owner: ModelInstance?,
        clip: AnimationClip?,
        delta: Matrix4f?,
        cart: Matrix4f?,
        reachWeight: Float,
        gripWeight: Float,
        restartPose: Array<out Matrix4f?>?,
        restartWeight: Float,
        model: String?,
    ): Boolean {
        val body = body(slot, owner)
        if (
            body == null ||
                body.matrixPalette == null ||
                (owner ?: throw NullPointerException()).model.tag !is SkinningData
        )
            return false
        val bodySkin = owner.model.tag as SkinningData
        val actor = owner.animPlayer.getSkinningData()
        val poses = livePoses(actor, bodySkin, body.matrixPalette, Matrix4f(), true) ?: return false
        if (restartPose != null && !releasePose(poses, actor, restartPose, restartWeight))
            return false
        // Blend into the same grip as held motion before the clip reaches contact.
        if (restartPose == null && reachWeight <= 0) return true
        if (
            reachWeight > 0 &&
                !transitionGrip(
                    poses,
                    actor,
                    (slot ?: throw NullPointerException()).character.isFemale(),
                    delta,
                    cart,
                    reachWeight,
                    gripWeight,
                    clip,
                    model,
                )
        )
            return false
        skinSlot(slot, owner, clip, actor, poses, true)
        return true
    }

    @JvmStatic
    fun transitionGrip(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        female: Boolean,
        delta: Matrix4f?,
        cart: Matrix4f?,
        reachWeight: Float,
        gripWeight: Float,
    ): Boolean = transitionGrip(poses, actor, female, delta, cart, reachWeight, gripWeight, null)

    @JvmStatic
    fun transitionGrip(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        female: Boolean,
        delta: Matrix4f?,
        cart: Matrix4f?,
        reachWeight: Float,
        gripWeight: Float,
        thumbReference: AnimationClip?,
    ): Boolean =
        transitionGrip(
            poses,
            actor,
            female,
            delta,
            cart,
            reachWeight,
            gripWeight,
            thumbReference,
            "WheelbarrowWood",
        )

    @JvmStatic
    fun transitionGrip(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        female: Boolean,
        delta: Matrix4f?,
        cart: Matrix4f?,
        reachWeight: Float,
        gripWeight: Float,
        thumbReference: AnimationClip?,
        model: String?,
    ): Boolean {
        if (
            thumbReference == null &&
                reachWeight == 1f &&
                gripWeight == 1f &&
                !"WheelbarrowMetal".equals(model)
        ) {
            if (!grip(poses, actor, model, female, delta, cart)) return false
        } else
            for (side in arrayOf("L", "R")) {
                val skeleton = actor ?: throw NullPointerException()
                val hand = skeleton.getBone("Bip01_${side}_Hand")
                val target = Matrix4f()
                if (
                    !transitionTarget(model, "L".equals(side), female, delta, cart, target) ||
                        !CartTransitionMath.blend(
                            pose(poses, hand.index),
                            target,
                            CartTransitionMath.smooth(reachWeight.toDouble()),
                            target,
                        )
                )
                    return false
                if ("WheelbarrowMetal".equals(model))
                    metalApproach(target, cart, "L".equals(side), reachWeight, gripWeight)
                if (
                    !reach(
                        poses,
                        skeleton,
                        hand.name,
                        target,
                        delta,
                        "WheelbarrowWood".equals(model),
                        reachWeight,
                        false,
                        "WheelbarrowMetal".equals(model),
                    )
                )
                    return false
                val before = arrayOfNulls<Matrix4f>(skeleton.numBones())
                for (i in before.indices) if (descendant(skeleton.getBoneAt(i), hand))
                    before[i] = Matrix4f(pose(poses, i))
                if (
                    thumbReference != null && !referenceThumb(poses, skeleton, thumbReference, side)
                )
                    return false
                closeFingers(poses, skeleton, side, grasp(female, model), true)
                for (i in before.indices) if (before[i] != null)
                    CartTransitionMath.blend(
                        before[i],
                        pose(poses, i),
                        CartTransitionMath.smooth(gripWeight.toDouble()),
                        pose(poses, i),
                    )
            }
        return true
    }

    private fun metalApproach(
        target: Matrix4f,
        cart: Matrix4f?,
        left: Boolean,
        reach: Float,
        grip: Float,
    ) {
        // The coarse hand bridge must pass beside the shaft before its fingers close.
        // Keep that clearance through wrist rotation, then settle onto the unchanged grip.
        val distance =
            (.042 *
                    CartTransitionMath.smooth(reach / .05) *
                    (1 - CartTransitionMath.smooth(grip.toDouble())))
                .toFloat()
        val direction =
            (cart ?: throw NullPointerException())
                .transformDirection(Vector3f(if (left) .9396926f else -.9396926f, .34202015f, 0f))
                .normalize()
        target.translateLocal(direction.mul(distance))
    }

    @JvmStatic
    fun capture(actor: SkinningData?, saved: Array<Matrix4f?>?): Array<Matrix4f?>? {
        val poses = matrices.get().poses
        if (actor == null || actor.numBones() > poses.size) return null
        val result =
            if (saved == null || saved.size != actor.numBones())
                arrayOfNulls<Matrix4f>(actor.numBones())
            else saved
        for (i in result.indices) {
            if (poses[i] == null || !pose(poses, i).isFinite()) return null
            if (result[i] == null) result[i] = Matrix4f()
            pose(result, i).set(poses[i])
        }
        return result
    }

    @JvmStatic
    fun releasePose(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        start: Array<out Matrix4f?>?,
        amount: Float,
    ): Boolean {
        if (
            actor == null ||
                poses == null ||
                start == null ||
                poses.size < actor.numBones() ||
                start.size != actor.numBones() ||
                !amount.isFinite() ||
                amount < 0 ||
                amount > 1
        )
            return false
        val local = arrayOfNulls<Matrix4f>(actor.numBones())
        for (i in local.indices) {
            val parent = actor.getBoneAt(i).parent
            if (
                poses[i] == null ||
                    start[i] == null ||
                    !pose(poses, i).isFinite() ||
                    !pose(start, i).isFinite() ||
                    parent != null && parent.index >= i
            )
                return false
            val from = Matrix4f(start[i])
            val to = Matrix4f(poses[i])
            if (parent != null) {
                Matrix4f(start[parent.index]).invert().mul(from, from)
                Matrix4f(poses[parent.index]).invert().mul(to, to)
            }
            val joint = Matrix4f()
            local[i] = joint
            // Blend joint rotations in their parent frame; global matrix blending shortens bent
            // limbs.
            if (!CartTransitionMath.blend(to, from, amount.toDouble(), joint)) return false
            // Native idle/walk transfer root translation between Bip01 and Pelvis; neither offset
            // is a fixed bone.
            val name = actor.getBoneAt(i).name
            if (parent != null && !"Bip01".equals(name) && !"Bip01_Pelvis".equals(name)) {
                val length =
                    from.getTranslation(Vector3f()).length() * amount +
                        to.getTranslation(Vector3f()).length() * (1 - amount)
                val offset = joint.getTranslation(Vector3f())
                if (length > 0 && offset.lengthSquared() == 0f) return false
                if (length > 0) joint.setTranslation(offset.normalize(length))
            }
        }
        for (i in local.indices) {
            val parent = actor.getBoneAt(i).parent
            if (parent == null) pose(poses, i).set(local[i])
            else pose(poses, parent.index).mul(local[i], pose(poses, i))
        }
        return true
    }

    @JvmStatic
    fun movingRecovery(
        slot: ModelSlotRenderData?,
        owner: ModelInstance?,
        clip: AnimationClip?,
        delta: Matrix4f?,
        cart: Matrix4f?,
        held: Matrix4f?,
        start: Array<out Matrix4f?>?,
        amount: Float,
        carrying: Boolean,
        startReach: Float,
        startGrip: Float,
        clearance: Float,
    ): Boolean =
        movingRecovery(
            slot,
            owner,
            clip,
            delta,
            cart,
            held,
            start,
            amount,
            carrying,
            startReach,
            startGrip,
            clearance,
            "WheelbarrowWood",
        )

    @JvmStatic
    fun movingRecovery(
        slot: ModelSlotRenderData?,
        owner: ModelInstance?,
        clip: AnimationClip?,
        delta: Matrix4f?,
        cart: Matrix4f?,
        held: Matrix4f?,
        start: Array<out Matrix4f?>?,
        amount: Float,
        carrying: Boolean,
        startReach: Float,
        startGrip: Float,
        clearance: Float,
        model: String?,
    ): Boolean {
        if (!clearance.isFinite() || clearance < 0 || clearance > .25f) return false
        val body = body(slot, owner)
        if (
            body == null ||
                body.matrixPalette == null ||
                (owner ?: throw NullPointerException()).model.tag !is SkinningData
        )
            return false
        val bodySkin = owner.model.tag as SkinningData
        val actor = owner.animPlayer.getSkinningData()
        val poses = livePoses(actor, bodySkin, body.matrixPalette, Matrix4f(), true)
        // Clear the descending shaft with a small weight shift against this frame's walking feet.
        if (
            poses == null ||
                carrying &&
                    (!referenceThumb(poses, actor, clip, "L") ||
                        !referenceThumb(poses, actor, clip, "R") ||
                        !grip(
                            poses,
                            actor,
                            model,
                            (slot ?: throw NullPointerException()).character.isFemale(),
                            delta,
                            held,
                        )) ||
                !releasePose(poses, actor, start, amount) ||
                !carrying &&
                    clearance > 0 &&
                    !groundFeet(
                        poses,
                        actor,
                        null,
                        null,
                        0f,
                        -.18f * clearance,
                        -.04f * clearance,
                        .12f * clearance,
                        true,
                    ) ||
                carrying &&
                    !transitionGrip(
                        poses,
                        actor,
                        (slot ?: throw NullPointerException()).character.isFemale(),
                        delta,
                        cart,
                        1 - amount * (1 - startReach),
                        1 - amount * (1 - startGrip),
                        clip,
                        model,
                    )
        )
            return false
        skinSlot(slot, owner, clip, actor, poses, true)
        return true
    }

    private fun skinSlot(
        slot: ModelSlotRenderData?,
        owner: ModelInstance?,
        clip: AnimationClip?,
        actor: SkinningData,
        poses: Array<out Matrix4f?>?,
    ) = skinSlot(slot, owner, clip, actor, poses, false)

    private fun skinSlot(
        slot: ModelSlotRenderData?,
        owner: ModelInstance?,
        clip: AnimationClip?,
        actor: SkinningData,
        poses: Array<out Matrix4f?>?,
        full: Boolean,
    ) {
        for (data in (slot ?: throw NullPointerException()).modelData) {
            val instance = data.modelInstance
            if (
                instance.animPlayer === (owner ?: throw NullPointerException()).animPlayer &&
                    instance.model != null &&
                    !instance.model.isStatic &&
                    data.matrixPalette != null &&
                    instance.model.tag is SkinningData
            ) {
                val target = instance.model.tag as SkinningData
                val parameter = data.properties.GetParameter("MatrixPalette")
                val value = if (parameter == null) null else parameter.GetValue()
                @Suppress("UNCHECKED_CAST")
                val shaderPalette =
                    if (
                        value is Array<*> &&
                            org.lwjgl.util.vector.Matrix4f::class
                                .java
                                .isAssignableFrom(value.javaClass.componentType)
                    )
                        value as Array<org.lwjgl.util.vector.Matrix4f?>
                    else null
                skin(data.matrixPalette, shaderPalette, target, actor, poses, full)
            } else if (
                instance.parent === owner && instance.model != null && instance.model.isStatic
            ) {
                var attachment = owner.getAttachmentById(instance.attachmentNameParent)
                if (attachment == null)
                    attachment = owner.getAttachmentById(instance.parentBoneName)
                val bone = if (attachment == null) instance.parentBoneName else attachment.getBone()
                if (
                    bone != null &&
                        actor.getBone(bone) != null &&
                        (full || upperBody(actor.getBone(bone)))
                ) {
                    val transform = matrices.get().attachment
                    val adjustment = matrices.get().adjustment
                    if (
                        CartGrounding.rigid(data, clip, transform) &&
                            CartGrounding.referencePose(clip, actor, bone, adjustment)
                    ) {
                        adjustment.invert()
                        pose(poses, actor.getBone(bone).index).mul(adjustment, adjustment)
                        adjustment.mul(transform, transform)
                        data.xfrm.set(transform).transpose()
                    }
                }
            }
        }
    }
}
