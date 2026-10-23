package net.alexredby.pztoolkitjavapatches

import java.nio.FloatBuffer
import java.util.WeakHashMap
import org.joml.Matrix4f
import org.joml.Vector3f
import org.lwjgl.util.vector.Matrix4f as NativeMatrix
import zombie.characters.IsoPlayer
import zombie.core.math.PZMath
import zombie.core.skinnedmodel.ModelManager
import zombie.core.skinnedmodel.animation.AnimationPlayer
import zombie.core.skinnedmodel.model.Model
import zombie.core.skinnedmodel.model.ModelInstance
import zombie.core.skinnedmodel.model.ModelInstanceRenderData
import zombie.core.skinnedmodel.model.ModelSlotRenderData
import zombie.core.skinnedmodel.model.SkinningData

/**
 * Slot-local knee clearance during the confirmed wooden-cart release; native movement stays
 * untouched.
 */
internal object CartImpactPose {
    @JvmField val MAX_ANGLE = Math.toRadians(6.0).toFloat()

    private class Snapshot(
        val player: IsoPlayer,
        val owner: ModelInstance,
        val model: Model,
        val animator: AnimationPlayer,
        val angle: Float,
    )

    private class Write(
        val palette: FloatBuffer,
        val index: Int,
        val shader: Array<NativeMatrix?>,
        val value: NativeMatrix,
    )

    private val slots = WeakHashMap<ModelSlotRenderData?, Snapshot>()
    private const val THIGH = "Bip01_R_Thigh"
    private const val CALF = "Bip01_R_Calf"
    private const val FOOT = "Bip01_R_Foot"

    @JvmStatic
    fun angle(age: Long): Float {
        if (age <= 0 || age >= 450_000_000L) return 0f
        val ms = age / 1_000_000.0
        val u = if (ms < 120) ms / 120 else if (ms <= 280) 1.0 else (450 - ms) / 170
        return MAX_ANGLE * (u * u * (3 - 2 * u)).toFloat()
    }

    @JvmStatic
    @Synchronized
    fun bind(slot: ModelSlotRenderData?, source: ModelManager.ModelSlot?) {
        val player = source?.character as? IsoPlayer
        val age = if (player != null) CartImpactMotion.poseAgeNanos(player) else -1
        capture(slot, source, age)
    }

    /**
     * Producer-only immutable snapshot; explicit age also permits isolated render-lifecycle tests.
     */
    @JvmStatic
    @Synchronized
    fun capture(slot: ModelSlotRenderData?, source: ModelManager.ModelSlot?, age: Long) {
        slots.remove(slot)
        val amount = angle(age)
        if (slot == null || source == null) return
        val player = source.character as? IsoPlayer ?: return
        if (
            player.isFemale() ||
                slot.character !== player ||
                slot.`object` !== player ||
                source.model == null ||
                source.model.`object` !== player ||
                source.model.model == null ||
                source.model.animPlayer == null ||
                amount <= 0
        )
            return
        val owner = source.model
        slots[slot] = Snapshot(player, owner, owner.model, owner.animPlayer, amount)
    }

    @JvmStatic
    @Synchronized
    fun release(slot: ModelSlotRenderData?) {
        slots.remove(slot)
    }

    private fun matrix(value: Matrix4f?): Boolean =
        value != null &&
            value.isFinite &&
            Math.abs(value.m03()) < 1e-5 &&
            Math.abs(value.m13()) < 1e-5 &&
            Math.abs(value.m23()) < 1e-5 &&
            Math.abs(value.m33() - 1) < 1e-5 &&
            Math.abs(value.determinant3x3()) > 1e-8

    @JvmStatic
    fun swivel(
        thigh: Matrix4f?,
        calf: Matrix4f?,
        foot: Matrix4f?,
        angle: Float,
        outThigh: Matrix4f?,
        outCalf: Matrix4f?,
    ): Boolean {
        if (
            !matrix(thigh) ||
                !matrix(calf) ||
                !matrix(foot) ||
                !java.lang.Float.isFinite(angle) ||
                angle < 0 ||
                angle > MAX_ANGLE
        )
            return false
        val hip = thigh!!.getTranslation(Vector3f())
        val knee = calf!!.getTranslation(Vector3f())
        val ankle = foot!!.getTranslation(Vector3f())
        val axis = ankle.sub(hip, Vector3f())
        if (
            axis.lengthSquared() < 1e-10f ||
                knee.distanceSquared(hip) < 1e-10f ||
                knee.distanceSquared(ankle) < 1e-10f
        )
            return false
        axis.normalize()
        val radius = knee.sub(hip, Vector3f())
        radius.fma(-radius.dot(axis), axis)
        if (radius.lengthSquared() < 1e-10f) return false
        val delta =
            Matrix4f().translation(hip).rotate(angle, axis).translate(-hip.x, -hip.y, -hip.z)
        delta.mul(thigh, outThigh)
        delta.mul(calf, outCalf)
        return matrix(outThigh) && matrix(outCalf)
    }

    private fun index(skin: SkinningData, name: String, palette: FloatBuffer): Int {
        val index = skin.boneIndices[name]
        return if (
            index != null &&
                index >= 0 &&
                index < skin.boneOffset.size &&
                skin.boneOffset[index] != null &&
                (index + 1).toLong() * 16 <= palette.limit()
        )
            index
        else -1
    }

    private fun pose(skin: SkinningData, name: String, palette: FloatBuffer): Matrix4f? {
        val index = index(skin, name, palette)
        if (index < 0) return null
        val raw = NativeMatrix()
        val view = palette.duplicate()
        view.position(index * 16)
        raw.load(view)
        val offset = PZMath.convertMatrix(skin.boneOffset[index], Matrix4f()).transpose()
        val model = PZMath.convertMatrix(raw, Matrix4f()).transpose()
        if (!matrix(offset) || !matrix(model)) return null
        model.mul(offset.invert())
        return if (matrix(model)) model else null
    }

    private fun stage(
        data: ModelInstanceRenderData,
        skin: SkinningData,
        name: String,
        pose: Matrix4f,
        writes: ArrayList<Write>,
    ): Boolean {
        if (data.matrixPalette == null || data.matrixPalette.isReadOnly) return false
        val index = index(skin, name, data.matrixPalette)
        val property = data.properties.GetParameter("MatrixPalette")
        if (index < 0 || property == null) return false
        val value = property.GetValue()
        if (!Array<NativeMatrix>::class.java.isInstance(value)) return false
        @Suppress("UNCHECKED_CAST") val shader = value as Array<NativeMatrix?>
        if (index >= shader.size) return false
        val offset = PZMath.convertMatrix(skin.boneOffset[index], Matrix4f()).transpose()
        if (!matrix(offset) || pose(skin, name, data.matrixPalette) == null) return false
        val raw = PZMath.convertMatrix(Matrix4f(pose).transpose(), NativeMatrix())
        NativeMatrix.mul(skin.boneOffset[index], raw, raw)
        if (!matrix(PZMath.convertMatrix(raw, Matrix4f()).transpose())) return false
        writes.add(Write(data.matrixPalette, index, shader, raw))
        return true
    }

    /**
     * Worker uses only bound identity/angle and this slot's prepared matrices, never actor state.
     */
    @JvmStatic
    @Synchronized
    fun render(slot: ModelSlotRenderData?) {
        val snapshot = slots.remove(slot) ?: return
        if (
            slot!!.character !== snapshot.player ||
                slot.`object` !== snapshot.player ||
                snapshot.owner.model !== snapshot.model ||
                snapshot.owner.animPlayer !== snapshot.animator
        )
            return
        val skin = snapshot.model.tag as? SkinningData ?: return
        val writes = ArrayList<Write>()
        try {
            var body: ModelInstanceRenderData? = null
            for (data in slot.modelData) if (data.modelInstance === snapshot.owner) {
                body = data
                break
            }
            if (body == null || body.matrixPalette == null) return
            val thigh = skin.getBone(THIGH)
            val calf = skin.getBone(CALF)
            val foot = skin.getBone(FOOT)
            if (
                thigh == null ||
                    calf == null ||
                    foot == null ||
                    calf.parent !== thigh ||
                    foot.parent !== calf
            )
                return
            val fromThigh = pose(skin, THIGH, body.matrixPalette)
            val fromCalf = pose(skin, CALF, body.matrixPalette)
            val fromFoot = pose(skin, FOOT, body.matrixPalette)
            val toThigh = Matrix4f()
            val toCalf = Matrix4f()
            if (!swivel(fromThigh, fromCalf, fromFoot, snapshot.angle, toThigh, toCalf)) return
            for (data in slot.modelData) {
                val instance = data.modelInstance
                if (
                    instance == null ||
                        instance.animPlayer !== snapshot.animator ||
                        instance.model == null ||
                        instance.model.isStatic
                )
                    continue
                val target = instance.model.tag as? SkinningData ?: return
                if (
                    !stage(data, target, THIGH, toThigh, writes) ||
                        !stage(data, target, CALF, toCalf, writes)
                )
                    return
            }
        } catch (invalid: RuntimeException) {
            return
        }
        // All affected meshes passed validation before the first palette write.
        for (write in writes) {
            val view = write.palette.duplicate()
            view.position(write.index * 16)
            write.value.store(view)
            write.shader[write.index] = write.value
        }
    }
}
