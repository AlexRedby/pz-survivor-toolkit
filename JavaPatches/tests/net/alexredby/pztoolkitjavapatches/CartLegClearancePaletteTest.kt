package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Constructor
import java.lang.reflect.Field
import java.lang.reflect.InvocationTargetException
import java.lang.reflect.Method
import java.nio.FloatBuffer
import java.util.ArrayList
import java.util.HashMap
import org.joml.Matrix4f
import org.joml.Vector3f
import sun.misc.Unsafe
import zombie.core.math.PZMath
import zombie.core.skinnedmodel.model.Model
import zombie.core.skinnedmodel.model.ModelInstance
import zombie.core.skinnedmodel.model.ModelInstanceRenderData
import zombie.core.skinnedmodel.model.SkinningData

/** Exercise the render-palette boundary independently of the geometric solver. */
object CartLegClearancePaletteTest {
    private const val SPINE = "Bip01_Spine"
    private const val CHEST = "Bip01_Spine1"
    private const val THIGH = "Bip01_L_Thigh"
    private const val CALF = "Bip01_L_Calf"
    private val actorNames = arrayOf(SPINE, CHEST, THIGH, CALF)
    private val targetNames = arrayOf(CALF, SPINE, THIGH, CHEST)
    private val source = CartLegClearanceData.Skin("synthetic/source.x", "synthetic", 1L,
        arrayOf(CHEST, THIGH, CALF, SPINE), 5, intArrayOf(0, 1, 2, 3, 3, 4), intArrayOf(0, 1, 2, 0, 1, 3),
        floatArrayOf(1f, 2f, -3f, 1f, -2f, .5f, 4f, 1f, .25f, -1f, 2f, 1f,
            .5f, -.25f, .125f, .25f, 1.5f, -.75f, .375f, .75f, .5f, .25f, -.75f, 1f), intArrayOf(0, 1, 2, 1, 3, 4))
    private val scratchType: Class<*>
    private val newScratch: Constructor<*>
    private val readMethod: Method
    private val pointsField: Field
    private val unsafe: Unsafe

    init {
        try {
            unsafe = Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null) as Unsafe
            scratchType = Class.forName(CartLegClearance::class.java.name + "\$Scratch")
            newScratch = scratchType.getDeclaredConstructor().apply { isAccessible = true }
            readMethod = CartLegClearance::class.java.getDeclaredMethod("skin", ModelInstanceRenderData::class.java,
                CartLegClearanceData.Skin::class.java, scratchType, SkinningData::class.java, Array<Matrix4f>::class.java)
                .apply { isAccessible = true }
            pointsField = scratchType.getDeclaredField("points").apply { isAccessible = true }
        } catch (unavailable: ReflectiveOperationException) {
            throw ExceptionInInitializerError(unavailable)
        }
    }

    private fun skeleton(names: Array<String>, parents: List<Int>, offsets: List<org.lwjgl.util.vector.Matrix4f>): SkinningData {
        val indices = HashMap<String, Int>()
        for (i in names.indices) indices[names[i]] = i
        return SkinningData(HashMap(), offsets, offsets, offsets, parents, indices)
    }

    private fun nativeMatrix(matrix: Matrix4f): org.lwjgl.util.vector.Matrix4f =
        PZMath.convertMatrix(Matrix4f(matrix).transpose(), org.lwjgl.util.vector.Matrix4f())

    private class Fixture {
        val actor: SkinningData
        val target: SkinningData
        val data = ModelInstanceRenderData()
        val nativePoses = arrayOf(Matrix4f().translation(-.2f, .45f, .02f).rotateY(.2f),
            Matrix4f().translation(-.3f, .6f, .1f).rotateZ(-.1f),
            Matrix4f().translation(.05f, .4f, .08f).rotateXYZ(.1f, -.3f, .2f),
            Matrix4f().translation(.07f, .2f, -.06f).rotateXYZ(-.2f, .15f, .35f))
        // Poisoned/absent lower poses must never override native walking branches.
        val pending = arrayOf<Matrix4f?>(Matrix4f().translation(.04f, .5f, -.01f).rotateY(-.2f),
            Matrix4f().translation(.1f, .7f, -.2f).rotateXYZ(.2f, .1f, .25f), null, Matrix4f().translation(999f, 888f, 777f))
        val scratch: Any

        init {
            val identities = ArrayList<org.lwjgl.util.vector.Matrix4f>()
            for (ignored in actorNames) identities.add(org.lwjgl.util.vector.Matrix4f())
            actor = skeleton(actorNames, listOf(-1, 0, 0, 2), identities)
            val offsets = ArrayList<org.lwjgl.util.vector.Matrix4f>()
            for (i in targetNames.indices) offsets.add(nativeMatrix(Matrix4f()
                .translation(.11f * (i + 1), -.07f * i, .03f * (i + 2)).rotateXYZ(.1f * i, -.08f * i, .06f * i)
                .scale(1.2f, .8f, 1.1f)))
            target = skeleton(targetNames, listOf(2, -1, 1, 1), offsets)
            val instance = ModelInstance()
            instance.model = unsafe.allocateInstance(Model::class.java) as Model
            instance.model.tag = target
            // Only this render slot owns the input pose; there is no live AnimationPlayer.
            data.modelInstance = instance
            data.matrixPalette = FloatBuffer.allocate(targetNames.size * 16)
            for (i in actorNames.indices) slotPose(actorNames[i], nativePoses[i])
            data.matrixPalette.position(7)
            scratch = newScratch.newInstance()
        }

        fun slotPose(name: String, pose: Matrix4f) {
            val index = target.boneIndices[name] ?: throw AssertionError("fixture target bone missing: $name")
            val bind = PZMath.convertMatrix(target.boneOffset[index], Matrix4f()).transpose()
            val palette = data.matrixPalette
            val before = palette.position()
            try {
                palette.position(index * 16)
                nativeMatrix(Matrix4f(pose).mul(bind)).store(palette)
            } finally {
                palette.position(before)
            }
        }

        fun read(): Boolean {
            val palette = data.matrixPalette
            val position = palette?.position() ?: -1
            val limit = palette?.limit() ?: -1
            val bytes = palette?.let { contents(it) }
            val pendingBefore = arrayOfNulls<FloatArray>(pending.size)
            for (i in pending.indices) pending[i]?.let { pendingBefore[i] = it.get(FloatArray(16)) }
            try {
                return readMethod.invoke(null, data, source, scratch, actor, pending) as Boolean
            } catch (error: InvocationTargetException) {
                throw AssertionError("Unavailable render palette must be refused without throwing", error.cause)
            } finally {
                if (palette != null && (palette.position() != position || palette.limit() != limit || !bytes.contentEquals(contents(palette))))
                    throw AssertionError("Reader changed palette values, limit or position")
                for (i in pending.indices) {
                    val pose = pending[i]
                    if (pose != null && !pendingBefore[i].contentEquals(pose.get(FloatArray(16))))
                        throw AssertionError("Reader changed pending render poses")
                }
            }
        }

        fun expectPoints() {
            val chest = pending[1] ?: throw AssertionError("fixture chest pose missing")
            val thigh = nativePoses[2]
            val calf = nativePoses[3]
            val expected = arrayOf(chest.transformPosition(Vector3f(1f, 2f, -3f)),
                thigh.transformPosition(Vector3f(-2f, .5f, 4f)), calf.transformPosition(Vector3f(.25f, -1f, 2f)),
                chest.transformPosition(Vector3f(2f, -1f, .5f)).mul(.25f).add(thigh.transformPosition(Vector3f(2f, -1f, .5f)).mul(.75f)),
                (pending[0] ?: throw AssertionError("fixture spine pose missing")).transformPosition(Vector3f(.5f, .25f, -.75f)))
            val actual = pointsField.get(scratch) as DoubleArray
            for (i in expected.indices) for (axis in 0 until 3) {
                val value = actual[i * 3 + axis]
                val wanted = expected[i].get(axis)
                if (!value.isFinite() || Math.abs(value - wanted) > 2e-5)
                    throw AssertionError("Same-slot/pending pose mismatch at vertex $i axis $axis: $value expected $wanted")
            }
        }
    }

    private fun contents(buffer: FloatBuffer): FloatArray {
        val view = buffer.duplicate()
        view.clear()
        val values = FloatArray(view.remaining())
        view.get(values)
        return values
    }

    private fun sameSlotAndPendingOwnership() {
        val fixture = Fixture()
        if (!fixture.read()) throw AssertionError("Valid remapped render palette refused")
        fixture.expectPoints()
        // A second slot can share the model/skeleton while carrying a newer native leg pose.
        val first = fixture.data.matrixPalette
        val firstValues = contents(first)
        fixture.data.matrixPalette = FloatBuffer.wrap(firstValues.copyOf())
        fixture.data.matrixPalette.position(13)
        fixture.nativePoses[2].translation(.17f, .37f, -.03f).rotateY(.45f)
        fixture.nativePoses[3].translation(-.02f, .19f, .09f).rotateX(-.2f)
        fixture.slotPose(THIGH, fixture.nativePoses[2]); fixture.slotPose(CALF, fixture.nativePoses[3])
        fixture.slotPose(CHEST, Matrix4f().translation(-20f, 30f, 40f).rotateZ(.8f))
        fixture.slotPose(SPINE, Matrix4f().translation(50f, -60f, 70f))
        fixture.pending[2] = Matrix4f().m00(Float.NaN)
        fixture.pending[3] = null
        fixture.data.matrixPalette = fixture.data.matrixPalette.asReadOnlyBuffer()
        if (!fixture.read()) throw AssertionError("Current read-only slot palette refused")
        fixture.expectPoints()
        if (first.position() != 7 || !firstValues.contentEquals(contents(first)))
            throw AssertionError("Reading the newer slot changed another render slot")
        if (!fixture.read()) throw AssertionError("Repeated same-slot read refused")
        fixture.expectPoints()
    }

    private fun unavailable(label: String, mutation: (Fixture) -> Unit) {
        val fixture = Fixture()
        mutation(fixture)
        if (fixture.read()) throw AssertionError("Accepted unavailable render data: $label")
    }

    private fun unavailableInputs() {
        unavailable("missing target bone after an earlier bone was read") { it.target.boneIndices.remove(THIGH) }
        unavailable("negative palette index") { it.target.boneIndices[THIGH] = -1 }
        unavailable("palette index outside limit") { it.target.boneIndices[THIGH] = 100 }
        unavailable("short palette") { it.data.matrixPalette.limit(63) }
        unavailable("missing palette") { it.data.matrixPalette = null }
        unavailable("missing target SkinningData") { it.data.modelInstance.model.tag = null }
        unavailable("missing inverse-bind offset") { it.target.boneOffset[it.target.boneIndices[THIGH] ?: error("fixture bone missing")] = null }
        unavailable("singular inverse-bind offset") {
            it.target.boneOffset[it.target.boneIndices[THIGH] ?: error("fixture bone missing")] = nativeMatrix(Matrix4f().scaling(0f, 1f, 1f))
        }
        unavailable("NaN inverse-bind offset") { it.target.boneOffset[it.target.boneIndices[THIGH] ?: error("fixture bone missing")].m13 = Float.NaN }
        unavailable("infinite inverse-bind offset") { it.target.boneOffset[it.target.boneIndices[THIGH] ?: error("fixture bone missing")].m21 = Float.POSITIVE_INFINITY }
        unavailable("NaN native palette") { it.data.matrixPalette.put((it.target.boneIndices[THIGH] ?: error("fixture bone missing")) * 16, Float.NaN) }
        unavailable("infinite native palette") { it.data.matrixPalette.put((it.target.boneIndices[THIGH] ?: error("fixture bone missing")) * 16 + 12, Float.NEGATIVE_INFINITY) }
        unavailable("missing pending upper pose") { it.pending[1] = null }
        unavailable("nonfinite pending upper pose") { (it.pending[1] ?: error("fixture pending pose missing")).m31(Float.NaN) }
        unavailable("singular native palette") { it.slotPose(THIGH, Matrix4f().scaling(0f, 1f, 1f)) }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        sameSlotAndPendingOwnership()
        unavailableInputs()
        println("CART_LEG_CLEARANCE_PALETTE_PASS")
    }
}
