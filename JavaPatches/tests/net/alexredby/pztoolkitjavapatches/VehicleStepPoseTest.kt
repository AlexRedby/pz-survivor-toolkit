package net.alexredby.pztoolkitjavapatches

import jassimp.AiPostProcessSteps
import jassimp.Jassimp
import java.nio.FloatBuffer
import java.nio.file.Path
import java.util.ArrayList
import java.util.EnumSet
import java.util.HashMap
import org.joml.Matrix4f
import org.joml.Vector3f
import sun.misc.Unsafe
import zombie.core.math.PZMath
import zombie.core.skinnedmodel.HelperFunctions
import zombie.core.skinnedmodel.animation.AnimationClip
import zombie.core.skinnedmodel.animation.AnimationPlayer
import zombie.core.skinnedmodel.animation.AnimationTrack
import zombie.core.skinnedmodel.model.Model
import zombie.core.skinnedmodel.model.ModelInstance
import zombie.core.skinnedmodel.model.ModelInstanceRenderData
import zombie.core.skinnedmodel.model.ModelSlotRenderData
import zombie.core.skinnedmodel.model.SkinningData
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeletonParams
import zombie.core.skinnedmodel.model.jassimp.JAssImpImporter
import zombie.core.skinnedmodel.model.jassimp.ProcessedAiSceneParams

object VehicleStepPoseTest {
    private class Source(val actor: SkinningData, val clip: AnimationClip) {
        val track =
            AnimationTrack.alloc().apply {
                startClip(this@Source.clip, false, 0f)
                setUseDeferredMovement(false)
            }

        fun sample(time: Float): Array<Matrix4f?> {
            track.setCurrentTimeValue(time)
            track.setPreviousTimeValue(time)
            track.UpdateKeyframes(0f)
            val local =
                Array(actor.numBones()) { index ->
                    val p = org.lwjgl.util.vector.Vector3f()
                    val q = org.lwjgl.util.vector.Quaternion()
                    val scale = org.lwjgl.util.vector.Vector3f()
                    val native = org.lwjgl.util.vector.Matrix4f()
                    track.get(index, p, q, scale)
                    HelperFunctions.CreateFromQuaternion(q, native)
                    HelperFunctions.setPosition(native, p)
                    PZMath.convertMatrix(native, Matrix4f()).transpose()
                }
            val poses = arrayOfNulls<Matrix4f>(local.size)
            fun model(index: Int): Matrix4f {
                poses[index]?.let {
                    return it
                }
                val parent = actor.getBoneAt(index).parent
                return (if (parent == null) Matrix4f(local[index])
                    else Matrix4f(model(parent.index)).mul(local[index]))
                    .also { poses[index] = it }
            }
            for (index in poses.indices) model(index)
            return poses
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun read(path: Path): Source {
        val params = ProcessedAiSceneParams.create()
        params.scene =
            Jassimp.importFile(
                path.toString(),
                EnumSet.of(
                    AiPostProcessSteps.MAKE_LEFT_HANDED,
                    AiPostProcessSteps.REMOVE_REDUNDANT_MATERIALS,
                ),
            )
        params.mode = JAssImpImporter.LoadMode.AnimationOnly
        params.animBonesScaleModifier = 1f
        val imported =
            ImportedSkeleton.process(
                ImportedSkeletonParams.create(params, params.scene.getMeshes()[0]),
            )
        fun field(name: String): Any =
            imported.javaClass.getDeclaredField(name).also { it.isAccessible = true }.get(imported)
        val indices = field("boneIndices") as HashMap<String, Int>
        val hierarchy = field("skeletonHierarchy") as ArrayList<Int>
        val clips = field("clips") as HashMap<String, AnimationClip>
        val offsets = List(indices.size) { org.lwjgl.util.vector.Matrix4f() }
        return Source(
            SkinningData(HashMap(), offsets, offsets, offsets, hierarchy, indices),
            clips.values.single(),
        )
    }

    private fun check(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun point(source: Source, poses: Array<Matrix4f?>, name: String): Vector3f =
        poses[source.actor.boneIndices[name]!!]!!.getTranslation(Vector3f())

    private fun matrix(source: Source, poses: Array<Matrix4f?>, name: String): Matrix4f =
        poses[source.actor.boneIndices[name]!!]!!

    private fun lengths(source: Source, poses: Array<Matrix4f?>, side: String): Pair<Float, Float> {
        val hip = point(source, poses, "Bip01_${side}_Thigh")
        val knee = point(source, poses, "Bip01_${side}_Calf")
        val foot = point(source, poses, "Bip01_${side}_Foot")
        return Pair(hip.distance(knee), knee.distance(foot))
    }

    private fun flex(source: Source, poses: Array<Matrix4f?>, side: String): Float {
        val knee = point(source, poses, "Bip01_${side}_Calf")
        val hip = point(source, poses, "Bip01_${side}_Thigh").sub(knee).normalize()
        val foot = point(source, poses, "Bip01_${side}_Foot").sub(knee).normalize()
        return Math.PI.toFloat() - Math.acos(hip.dot(foot).coerceIn(-1f, 1f).toDouble()).toFloat()
    }

    private fun paletteMapping(source: Source, references: VehicleStepPose.References) {
        val unsafe =
            Unsafe::class
                .java
                .getDeclaredField("theUnsafe")
                .also { it.isAccessible = true }
                .get(null) as Unsafe
        val animator = unsafe.allocateInstance(AnimationPlayer::class.java) as AnimationPlayer
        val original = source.sample(.2f)
        fun draw(remap: Boolean): ModelInstanceRenderData {
            val count = source.actor.numBones()
            val indices = HashMap<String, Int>()
            for ((name, index) in source.actor.boneIndices) indices[name] =
                if (remap) count - 1 - index else index
            val hierarchy = MutableList(count) { -1 }
            for ((name, index) in indices) {
                val parent = source.actor.getBone(name).parent
                hierarchy[index] = if (parent == null) -1 else indices[parent.name]!!
            }
            // Nonidentity bind offsets expose wrong multiplication order as well as bone remapping.
            val offsets =
                List(count) { i ->
                    PZMath.convertMatrix(
                        Matrix4f().translation(.001f * i, -.002f * i, .003f * i).transpose(),
                        org.lwjgl.util.vector.Matrix4f(),
                    )
                }
            val target = SkinningData(HashMap(), offsets, offsets, offsets, hierarchy, indices)
            val model =
                (unsafe.allocateInstance(Model::class.java) as Model).apply {
                    tag = target
                    isStatic = false
                }
            val instance =
                ModelInstance().apply {
                    this.model = model
                    animPlayer = animator
                }
            val data =
                ModelInstanceRenderData().apply {
                    modelInstance = instance
                    matrixPalette = FloatBuffer.allocate(count * 16)
                }
            val shader = Array(count) { org.lwjgl.util.vector.Matrix4f() }
            for ((name, index) in indices) {
                val pose = original[source.actor.boneIndices[name]!!]!!
                val raw =
                    PZMath.convertMatrix(
                        Matrix4f(pose).transpose(),
                        org.lwjgl.util.vector.Matrix4f(),
                    )
                org.lwjgl.util.vector.Matrix4f.mul(offsets[index], raw, raw)
                data.matrixPalette.position(index * 16)
                raw.store(data.matrixPalette)
                shader[index].load(raw)
            }
            data.properties.SetMatrix4Array("MatrixPalette", shader)
            data.matrixPalette.position(7)
            return data
        }
        val body = draw(false)
        val clothes = draw(true)
        val slot =
            ModelSlotRenderData().apply {
                modelData.add(body)
                modelData.add(clothes)
            }
        val owner = body.modelInstance
        val extracted = VehicleStepPalette.extract(slot, owner, source.actor)
        check(extracted != null, "actual body palette could not be reconstructed")
        for (i in original.indices) check(
            extracted!![i]!!.equals(original[i], 2e-5f),
            "palette extraction changed the native pose",
        )
        val origin =
            VehicleStepPose.solve(
                source.actor,
                extracted!!,
                references,
                Vector3f(1.130038f, -.26007798f, .220038f),
                Vector3f(.319956f, .239876f, .159978f),
                .2f,
                false,
            )
        check(origin != null, "palette foot solve failed")
        val beforeBody = body.matrixPalette.array().clone()
        val beforeClothes = clothes.matrixPalette.array().clone()
        clothes.properties.SetFloat("MatrixPalette", 1f)
        check(
            !VehicleStepPalette.apply(slot, owner, source.actor, extracted),
            "malformed clothing shader palette was accepted",
        )
        check(
            beforeBody.contentEquals(body.matrixPalette.array()) &&
                beforeClothes.contentEquals(clothes.matrixPalette.array()),
            "failed staging partially changed body or clothing",
        )
        val validClothes = draw(true)
        slot.modelData.clear()
        slot.modelData.add(body)
        slot.modelData.add(validClothes)
        check(
            VehicleStepPalette.apply(slot, owner, source.actor, extracted),
            "valid body/clothing palettes were rejected",
        )
        for (data in listOf(body, validClothes)) {
            val skin = data.modelInstance.model.tag as SkinningData
            check(data.matrixPalette.position() == 7, "draw palette cursor changed")
            for ((name, index) in skin.boneIndices) {
                val bone = source.actor.getBone(name)
                var ancestor = bone
                var affected = false
                while (ancestor != null) {
                    if (ancestor.name == "Bip01_L_Thigh" || ancestor.name == "Bip01_R_Thigh")
                        affected = true
                    ancestor = ancestor.parent
                }
                val raw = org.lwjgl.util.vector.Matrix4f()
                data.matrixPalette.duplicate().position(index * 16).let { raw.load(it) }
                val decoded =
                    PZMath.convertMatrix(raw, Matrix4f())
                        .transpose()
                        .mul(
                            PZMath.convertMatrix(skin.boneOffset[index], Matrix4f())
                                .transpose()
                                .invert(),
                        )
                check(
                    decoded.equals(
                        if (affected) extracted[bone.index] else original[bone.index],
                        2e-5f,
                    ),
                    "body/clothing descendant not synchronized: $name",
                )
                @Suppress("UNCHECKED_CAST")
                val shader =
                    data.properties.GetParameter("MatrixPalette").GetValue()
                        as Array<org.lwjgl.util.vector.Matrix4f>
                check(
                    PZMath.convertMatrix(raw, Matrix4f())
                        .equals(PZMath.convertMatrix(shader[index], Matrix4f()), 1e-6f),
                    "shader and palette differ: $name",
                )
            }
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        val game = Path.of("").toAbsolutePath()
        val root = Path.of(System.getProperty("pz.test.project"))
        val standing = read(game.resolve("media/anims_X/Bob/Bob_SatChairIn.x"))
        val driving = read(game.resolve("media/anims_X/Bob/Bob_IdleDriving.x"))
        val start = standing.sample(0f)
        val end = driving.sample(0f)
        val ref =
            VehicleStepPose.References(
                point(standing, start, "Bip01"),
                matrix(standing, start, "Bip01_L_Foot"),
                matrix(standing, start, "Bip01_R_Foot"),
                point(driving, end, "Bip01"),
                matrix(driving, end, "Bip01_L_Foot"),
                matrix(driving, end, "Bip01_R_Foot"),
            )
        var samples = 0
        for (exiting in listOf(false, true)) {
            val name =
                if (exiting) VehicleTransitionRender.EXIT_CLIP else VehicleTransitionRender.CLIP
            val source = read(root.resolve("PZSurvivorToolkit/42/media/anims_X/Bob/$name.x"))
            val unreachableOutside = Vector3f(50f, -.26007798f, .220038f)
            val unreachableInside = Vector3f(.319956f, .239876f, .159978f)
            check(
                VehicleStepPose.solve(
                    source.actor,
                    source.sample(.5f),
                    ref,
                    unreachableOutside,
                    unreachableInside,
                    .5f,
                    exiting,
                ) == null,
                "unreachable vehicle stretched the step instead of rejecting it",
            )
            val fallbackStart =
                VehicleTransitionRender.fallbackPosition(
                    unreachableOutside,
                    unreachableInside,
                    if (exiting) Vector3f() else ref.standingRoot,
                    0f,
                    !exiting,
                    exiting,
                )
            val fallbackEnd =
                VehicleTransitionRender.fallbackPosition(
                    unreachableOutside,
                    unreachableInside,
                    if (exiting) ref.standingRoot else Vector3f(),
                    1f,
                    !exiting,
                    exiting,
                )
            check(
                fallbackStart.equals(
                    if (exiting) unreachableInside else unreachableOutside,
                    2e-5f,
                ) &&
                    fallbackEnd.equals(
                        if (exiting) unreachableOutside else unreachableInside,
                        2e-5f,
                    ),
                "rejected solve reversed the fallback endpoints",
            )
            if (!exiting) paletteMapping(source, ref)
            check(
                kotlin.math.abs(source.clip.getDuration() - 1f) < 1e-6f,
                "native action duration changed",
            )
            // Both native endpoint skeletons must remain exact, including hands and clothing bones.
            for ((time, native, poses) in
                listOf(
                    Triple(0f, if (exiting) driving else standing, if (exiting) end else start),
                    Triple(1f, if (exiting) standing else driving, if (exiting) start else end),
                )) {
                val actual = source.sample(time)
                for (bone in source.actor.boneIndices.keys) check(
                    matrix(source, actual, bone).equals(matrix(native, poses, bone), 2e-5f),
                    "changed endpoint $name $time $bone",
                )
            }
            for (door in listOf(1f, -1f)) {
                val outside = Vector3f(door * 1.130038f, -.26007798f, .220038f)
                val inside = Vector3f(door * .319956f, .239876f, .159978f)
                val contact = VehicleStepPose.contacts(ref, outside, inside, 0f, exiting)
                val lead = if (contact.leadingLeft) "L" else "R"
                val trail = if (contact.leadingLeft) "R" else "L"
                check((lead == "R") == (door > 0), "lead foot did not follow the actual doorway")
                var leadAnchor: Vector3f? = null
                var trailAnchor: Vector3f? = null
                for (frame in 0..240) {
                    val time = frame / 240f
                    val poses = source.sample(time)
                    val previous = listOf(lengths(source, poses, "L"), lengths(source, poses, "R"))
                    val origin =
                        VehicleStepPose.solve(
                            source.actor,
                            poses,
                            ref,
                            outside,
                            inside,
                            time,
                            exiting,
                        )
                    check(
                        origin != null,
                        "unreachable actual doorway target: exit=$exiting door=$door phase=$time",
                    )
                    for ((index, side) in listOf("L", "R").withIndex()) {
                        val now = lengths(source, poses, side)
                        check(
                            kotlin.math.abs(now.first - previous[index].first) < 2e-5f &&
                                kotlin.math.abs(now.second - previous[index].second) < 2e-5f,
                            "IK stretched $side leg",
                        )
                        val world =
                            VehicleStepPose.world(
                                origin!!,
                                point(source, poses, "Bip01_${side}_Foot"),
                            )
                        val wanted =
                            VehicleStepPose.contacts(ref, outside, inside, time, exiting).let {
                                if (side == "L") it.left else it.right
                            }
                        check(
                            world.distance(wanted) < 2e-5f,
                            "foot missed vehicle-floor target $side: $world $wanted",
                        )
                    }
                    val leadWorld =
                        VehicleStepPose.world(origin!!, point(source, poses, "Bip01_${lead}_Foot"))
                    val trailWorld =
                        VehicleStepPose.world(origin, point(source, poses, "Bip01_${trail}_Foot"))
                    if ((!exiting && time <= .52f) || (exiting && time <= .42f)) {
                        if (trailAnchor == null) trailAnchor = Vector3f(trailWorld)
                        check(
                            trailWorld.distance(trailAnchor) < 2e-5f,
                            "support ankle slid on the floor",
                        )
                    }
                    if ((!exiting && time >= .38f && time <= .66f) || (exiting && time >= .4f)) {
                        if (leadAnchor == null) leadAnchor = Vector3f(leadWorld)
                        check(
                            leadWorld.distance(leadAnchor) < 2e-5f,
                            "lead foot slid after landing",
                        )
                    }
                    if (!exiting && frame == 48) {
                        check(
                            leadWorld.y - trailWorld.y > .10f,
                            "lead foot did not lift before the squat",
                        )
                        check(
                            flex(source, poses, lead) - flex(source, poses, trail) > .2f,
                            "both knees still bend symmetrically",
                        )
                    }
                    samples++
                }
            }
        }
        println(
            "VEHICLE_STEP_POSE_PASS samples=$samples supportDrift<0.00002 legLengthError<0.00002",
        )
    }
}
