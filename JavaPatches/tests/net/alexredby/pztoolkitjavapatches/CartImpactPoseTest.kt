package net.alexredby.pztoolkitjavapatches

import java.nio.FloatBuffer
import org.joml.Matrix4f
import org.joml.Vector3f
import org.lwjgl.util.vector.Matrix4f as NativeMatrix
import sun.misc.Unsafe
import zombie.characters.IsoPlayer
import zombie.core.math.PZMath
import zombie.core.skinnedmodel.ModelManager
import zombie.core.skinnedmodel.animation.AnimationPlayer
import zombie.core.skinnedmodel.model.Model
import zombie.core.skinnedmodel.model.ModelInstance
import zombie.core.skinnedmodel.model.ModelInstanceRenderData
import zombie.core.skinnedmodel.model.ModelSlotRenderData
import zombie.core.skinnedmodel.model.SkinningData

object CartImpactPoseTest {
    private lateinit var unsafe: Unsafe
    private val NAMES =
        arrayOf(
            "Bip01_Spine",
            "Bip01_R_Thigh",
            "Bip01_R_Calf",
            "Bip01_R_Foot",
            "Bip01_R_Toe0",
            "Bip01_Head",
        )

    private fun <T> allocate(type: Class<T>): T = type.cast(unsafe.allocateInstance(type))

    private fun check(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun close(actual: Number, expected: Number, message: String) {
        check(
            Math.abs(actual.toDouble() - expected.toDouble()) < .00001,
            "$message: $actual != $expected",
        )
    }

    private class Player : IsoPlayer(null, null, 0, 0, 0) {
        var worker = false

        override fun isLocalPlayer(): Boolean {
            if (worker) throw AssertionError("worker read actor state")
            return true
        }

        override fun isCurrentState(state: zombie.ai.State?): Boolean {
            if (worker) throw AssertionError("worker read actor state")
            return false
        }
    }

    private data class Fixture(
        val player: Player,
        val source: ModelManager.ModelSlot,
        val slot: ModelSlotRenderData,
        val body: ModelInstanceRenderData,
        val clothes: ModelInstanceRenderData,
        val poses: Array<Matrix4f>,
    )

    private fun poses(): Array<Matrix4f> =
        arrayOf(
            Matrix4f().translation(.02f, .7f, 0f),
            Matrix4f().translation(0f, .5f, 0f).rotateZ(.1f),
            Matrix4f().translation(0f, .25f, .1f).rotateX(.3f),
            Matrix4f().rotateY(.2f),
            Matrix4f().translation(0f, -.03f, .06f),
            Matrix4f().translation(0f, 1f, 0f),
        )

    private fun skin(remap: Boolean): SkinningData {
        val names =
            if (remap) arrayOf(NAMES[5], NAMES[3], NAMES[2], NAMES[4], NAMES[0], NAMES[1])
            else NAMES
        val indices = HashMap<String, Int>()
        for (i in names.indices) indices[names[i]] = i
        val hierarchy = ArrayList<Int>()
        val offsets = ArrayList<NativeMatrix>()
        for (i in names.indices) {
            val name = names[i]
            val parent =
                when (name) {
                    NAMES[0] -> null
                    NAMES[2] -> NAMES[1]
                    NAMES[3] -> NAMES[2]
                    NAMES[4] -> NAMES[3]
                    else -> NAMES[0]
                }
            hierarchy.add(if (parent == null) -1 else indices[parent]!!)
            offsets.add(
                PZMath.convertMatrix(
                    Matrix4f()
                        .translation(.02f * i, -.01f * i, .015f * i)
                        .rotateY(.06f * i)
                        .transpose(),
                    NativeMatrix(),
                ),
            )
        }
        return SkinningData(HashMap(), offsets, offsets, offsets, hierarchy, indices)
    }

    private fun data(
        instance: ModelInstance,
        skin: SkinningData,
        poses: Array<Matrix4f>,
    ): ModelInstanceRenderData {
        instance.model = allocate(Model::class.java)
        instance.model.tag = skin
        val data = ModelInstanceRenderData()
        data.modelInstance = instance
        data.matrixPalette = FloatBuffer.allocate(NAMES.size * 16)
        val shader = arrayOfNulls<NativeMatrix>(NAMES.size)
        for (i in NAMES.indices) {
            val index = skin.boneIndices[NAMES[i]]!!
            val raw = PZMath.convertMatrix(Matrix4f(poses[i]).transpose(), NativeMatrix())
            NativeMatrix.mul(skin.boneOffset[index], raw, raw)
            data.matrixPalette.position(index * 16)
            raw.store(data.matrixPalette)
            shader[index] = NativeMatrix(raw)
        }
        data.matrixPalette.position(7)
        data.properties.SetMatrix4Array("MatrixPalette", shader)
        return data
    }

    private fun fixture(): Fixture {
        val player = allocate(Player::class.java)
        player.setDescriptor(allocate(zombie.characters.SurvivorDesc::class.java))
        player.setFemale(false)
        val owner = ModelInstance()
        owner.`object` = player
        owner.animPlayer = allocate(AnimationPlayer::class.java)
        val poses = poses()
        val body = data(owner, skin(false), poses)
        val clothing = ModelInstance()
        clothing.animPlayer = owner.animPlayer
        val clothes = data(clothing, skin(true), poses)
        val slot = ModelSlotRenderData()
        slot.character = player
        slot.`object` = player
        slot.modelData.add(body)
        slot.modelData.add(clothes)
        return Fixture(player, ModelManager.ModelSlot(0, owner, player), slot, body, clothes, poses)
    }

    private fun decode(data: ModelInstanceRenderData, name: String): Matrix4f {
        val skin = data.modelInstance.model.tag as SkinningData
        val index = skin.boneIndices[name]!!
        val view = data.matrixPalette.duplicate()
        view.position(index * 16)
        val raw = NativeMatrix()
        raw.load(view)
        return PZMath.convertMatrix(raw, Matrix4f())
            .transpose()
            .mul(PZMath.convertMatrix(skin.boneOffset[index], Matrix4f()).transpose().invert())
    }

    private fun envelope() {
        for (age in longArrayOf(-1, 0, 450_000_000L, Long.MAX_VALUE)) close(
            CartImpactPose.angle(age),
            0,
            "outside envelope",
        )
        close(
            CartImpactPose.angle(60_000_000L),
            CartImpactPose.MAX_ANGLE / 2,
            "smooth rise midpoint",
        )
        close(CartImpactPose.angle(120_000_000L), CartImpactPose.MAX_ANGLE, "peak start")
        close(CartImpactPose.angle(280_000_000L), CartImpactPose.MAX_ANGLE, "peak end")
        close(
            CartImpactPose.angle(365_000_000L),
            CartImpactPose.MAX_ANGLE / 2,
            "smooth fade midpoint",
        )
        var age = 0L
        while (age <= 450_000_000L) {
            check(
                CartImpactPose.angle(age) >= 0 &&
                    CartImpactPose.angle(age) <= CartImpactPose.MAX_ANGLE,
                "unbounded envelope",
            )
            age += 1_000_000L
        }
        for (edge in longArrayOf(0, 120_000_000L, 280_000_000L, 450_000_000L)) check(
            Math.abs(CartImpactPose.angle(edge + 1000) - CartImpactPose.angle(edge - 1000)) <
                .000001,
            "envelope edge discontinuity",
        )
    }

    private fun geometry() {
        val poses = poses()
        val before = poses.map(::Matrix4f).toTypedArray()
        val thigh = Matrix4f()
        val calf = Matrix4f()
        check(
            CartImpactPose.swivel(
                poses[1],
                poses[2],
                poses[3],
                CartImpactPose.MAX_ANGLE,
                thigh,
                calf,
            ),
            "valid swivel rejected",
        )
        val hip = thigh.getTranslation(Vector3f())
        val knee = calf.getTranslation(Vector3f())
        val ankle = poses[3].getTranslation(Vector3f())
        close(hip.distance(poses[1].getTranslation(Vector3f())), 0, "hip moved")
        close(
            hip.distance(knee),
            poses[1].getTranslation(Vector3f()).distance(poses[2].getTranslation(Vector3f())),
            "thigh stretched",
        )
        close(
            knee.distance(ankle),
            poses[2].getTranslation(Vector3f()).distance(ankle),
            "calf stretched",
        )
        close(knee.x, -.1 * Math.sin(CartImpactPose.MAX_ANGLE.toDouble()), "swivel sign changed")
        for (i in poses.indices) check(poses[i] == before[i], "native source pose changed")
        val global = Matrix4f().translation(.2f, -.1f, .3f).rotateXYZ(.4f, -.7f, .2f)
        val rotatedThigh = Matrix4f()
        val rotatedCalf = Matrix4f()
        check(
            CartImpactPose.swivel(
                global.mul(poses[1], Matrix4f()),
                global.mul(poses[2], Matrix4f()),
                global.mul(poses[3], Matrix4f()),
                CartImpactPose.MAX_ANGLE,
                rotatedThigh,
                rotatedCalf,
            ),
            "rotated leg rejected",
        )
        check(
            rotatedThigh.equals(global.mul(thigh, Matrix4f()), .00001f) &&
                rotatedCalf.equals(global.mul(calf, Matrix4f()), .00001f),
            "swivel depends on global pose axes",
        )
        check(
            !CartImpactPose.swivel(poses[1], poses[2], poses[1], .05f, thigh, calf),
            "degenerate hip/ankle accepted",
        )
        check(
            !CartImpactPose.swivel(
                poses[1],
                Matrix4f().translation(0f, .25f, 0f),
                poses[3],
                .05f,
                thigh,
                calf,
            ),
            "straight knee accepted",
        )
        check(
            !CartImpactPose.swivel(poses[1], poses[2], poses[3], Float.NaN, thigh, calf),
            "NaN angle accepted",
        )
    }

    private fun renderMapping() {
        val f = fixture()
        val beforeBody = f.body.matrixPalette.array().clone()
        val beforeClothes = f.clothes.matrixPalette.array().clone()
        val expectedThigh = Matrix4f()
        val expectedCalf = Matrix4f()
        CartImpactPose.swivel(
            f.poses[1],
            f.poses[2],
            f.poses[3],
            CartImpactPose.MAX_ANGLE,
            expectedThigh,
            expectedCalf,
        )
        CartImpactPose.capture(f.slot, f.source, 200_000_000L)
        f.player.worker = true
        CartImpactPose.render(f.slot)
        for (data in listOf(f.body, f.clothes)) {
            val skin = data.modelInstance.model.tag as SkinningData
            check(data.matrixPalette.position() == 7, "palette cursor changed")
            @Suppress("UNCHECKED_CAST")
            val shader =
                data.properties.GetParameter("MatrixPalette").GetValue() as Array<NativeMatrix?>
            for (i in NAMES.indices) {
                val expected =
                    if (i == 1) expectedThigh else if (i == 2) expectedCalf else f.poses[i]
                check(
                    decode(data, NAMES[i]).equals(expected, .00001f),
                    "remapped render pose differs: ${NAMES[i]}",
                )
                val index = skin.boneIndices[NAMES[i]]!!
                val raw = NativeMatrix()
                val view = data.matrixPalette.duplicate()
                view.position(index * 16)
                raw.load(view)
                check(
                    PZMath.convertMatrix(shader[index], Matrix4f()) ==
                        PZMath.convertMatrix(raw, Matrix4f()),
                    "shader and buffer disagree",
                )
                if (i != 1 && i != 2)
                    for (v in 0 until 16) check(
                        java.lang.Float.floatToIntBits(data.matrixPalette.get(index * 16 + v)) ==
                            java.lang.Float.floatToIntBits(
                                (if (data === f.body) beforeBody else beforeClothes)[
                                    index * 16 + v],
                            ),
                        "unrelated bone changed",
                    )
            }
        }
        val once = f.body.matrixPalette.array().clone()
        CartImpactPose.render(f.slot)
        check(
            once.contentEquals(f.body.matrixPalette.array()),
            "render accumulated swivel on reused slot",
        )
    }

    private fun fallbackAndLifetime() {
        for (bad in 0 until 10) {
            val f = fixture()
            CartImpactPose.capture(f.slot, f.source, 200_000_000L)
            when (bad) {
                0 -> CartImpactPose.release(f.slot)
                1 -> {
                    f.player.setFemale(true)
                    CartImpactPose.capture(f.slot, f.source, 200_000_000L)
                }
                2 -> CartImpactPose.capture(f.slot, f.source, -1)
                3 -> CartImpactPose.capture(f.slot, null, 200_000_000L)
                4 -> f.source.model.model = allocate(Model::class.java)
                5 ->
                    (f.clothes.modelInstance.model.tag as SkinningData).boneIndices.remove(NAMES[2])
                6 -> f.clothes.matrixPalette = f.clothes.matrixPalette.asReadOnlyBuffer()
                7 -> f.clothes.properties.SetFloat("MatrixPalette", 1f)
                8 -> f.body.matrixPalette.put(3 * 16, Float.NaN)
                9 -> f.slot.character = allocate(Player::class.java)
            }
            val before = f.body.matrixPalette.array().clone()
            CartImpactPose.render(f.slot)
            check(
                before.contentEquals(f.body.matrixPalette.array()),
                "invalid/expired slot changed body: $bad",
            )
            CartImpactPose.release(f.slot)
        }
        val f = fixture()
        val before = f.body.matrixPalette.array().clone()
        f.source.character = allocate(Player::class.java)
        CartImpactPose.capture(f.slot, f.source, 200_000_000L)
        CartImpactPose.render(f.slot)
        check(before.contentEquals(f.body.matrixPalette.array()), "foreign source accepted")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val field = Unsafe::class.java.getDeclaredField("theUnsafe")
        field.isAccessible = true
        unsafe = field.get(null) as Unsafe
        envelope()
        geometry()
        renderMapping()
        fallbackAndLifetime()
        println(
            "CART_IMPACT_POSE_PASS (fixed hip/foot, rigid leg links, remapped clothes/shader palettes, envelope, slot lifecycle and atomic fallback)",
        )
    }
}
