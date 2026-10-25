package net.alexredby.pztoolkitjavapatches

import java.nio.FloatBuffer
import org.joml.Matrix4f
import org.lwjgl.util.vector.Matrix4f as NativeMatrix
import zombie.core.math.PZMath
import zombie.core.skinnedmodel.model.ModelInstance
import zombie.core.skinnedmodel.model.ModelSlotRenderData
import zombie.core.skinnedmodel.model.SkinningData

/** Apply every leg descendant to the actual body and matching clothing, atomically per draw. */
internal object VehicleStepPalette {
    private class Write(
        val palette: FloatBuffer,
        val index: Int,
        val shader: Array<NativeMatrix?>,
        val value: NativeMatrix,
    )

    @JvmStatic
    fun extract(
        slot: ModelSlotRenderData,
        owner: ModelInstance,
        actor: SkinningData,
    ): Array<Matrix4f?>? {
        val body = slot.modelData.firstOrNull { it.modelInstance === owner } ?: return null
        val skin = owner.model?.tag as? SkinningData ?: return null
        if (CartGrip.livePoses(actor, skin, body.matrixPalette, Matrix4f(), true, 0f) == null)
            return null
        return CartGrip.capture(actor, null)
    }

    private fun leg(actor: SkinningData, index: Int): Boolean {
        var bone = actor.getBoneAt(index)
        while (bone != null) {
            if (bone.name == "Bip01_L_Thigh" || bone.name == "Bip01_R_Thigh") return true
            bone = bone.parent
        }
        return false
    }

    @JvmStatic
    fun apply(
        slot: ModelSlotRenderData,
        owner: ModelInstance,
        actor: SkinningData,
        poses: Array<Matrix4f?>,
    ): Boolean {
        val writes = ArrayList<Write>()
        var body = false
        for (data in slot.modelData) {
            val instance = data.modelInstance ?: continue
            if (
                instance.animPlayer !== owner.animPlayer ||
                    instance.model == null ||
                    instance.model.isStatic
            )
                continue
            val target = instance.model.tag as? SkinningData ?: return false
            val palette = data.matrixPalette ?: return false
            if (palette.isReadOnly) return false
            val value = data.properties.GetParameter("MatrixPalette")?.GetValue() ?: return false
            if (!Array<NativeMatrix>::class.java.isInstance(value)) return false
            @Suppress("UNCHECKED_CAST") val shader = value as Array<NativeMatrix?>
            for ((name, index) in target.boneIndices) {
                val bone = actor.getBone(name) ?: continue
                if (!leg(actor, bone.index)) continue
                if (
                    index < 0 ||
                        index >= target.boneOffset.size ||
                        target.boneOffset[index] == null ||
                        index >= shader.size ||
                        (index + 1) * 16 > palette.limit()
                )
                    return false
                val pose = poses.getOrNull(bone.index) ?: return false
                if (!pose.isFinite) return false
                val raw = PZMath.convertMatrix(Matrix4f(pose).transpose(), NativeMatrix())
                NativeMatrix.mul(target.boneOffset[index], raw, raw)
                if (!PZMath.convertMatrix(raw, Matrix4f()).isFinite) return false
                writes.add(Write(palette, index, shader, raw))
            }
            if (instance === owner) body = true
        }
        if (!body || writes.isEmpty()) return false
        // No palette changes until every body/clothing target has passed validation.
        for (write in writes) {
            write.palette.duplicate().position(write.index * 16).let { write.value.store(it) }
            write.shader[write.index] = write.value
        }
        return true
    }
}
