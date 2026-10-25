package net.alexredby.pztoolkitjavapatches

import java.util.WeakHashMap
import org.joml.Matrix4f
import org.joml.Vector3f
import zombie.core.skinnedmodel.ModelManager
import zombie.core.skinnedmodel.animation.AnimationTrack
import zombie.core.skinnedmodel.model.ModelSlotRenderData
import zombie.core.skinnedmodel.model.SkinningData

/**
 * Synchronize the cosmetic seat transfer without moving the reserved passenger or sending packets.
 */
internal object VehicleTransitionRender {
    const val CLIP = "Bob_ToolkitVehicleEnter"
    const val EXIT_CLIP = "Bob_ToolkitVehicleExit"
    private val references = WeakHashMap<SkinningData, VehicleStepPose.References>()
    private const val BODY_SCALE = 1.5f // Model.CharacterModelCameraBegin
    @JvmField
    val SUPPORTED =
        BytecodeSupport.supports(
            "zombie/core/skinnedmodel/model/ModelSlotRenderData.class",
            "83fab9cb79f1c2ba270d8b49e8cf2c166ca36e08986c52517ba73d15cd34f76d",
        ) &&
            BytecodeSupport.supports(
                "zombie/vehicles/BaseVehicle.class",
                "e7ade19e1e6f66450bef2bd37e52b2afccc7377c4e4571d0fa39435ecdb55661",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/animation/AnimationPlayer.class",
                "06fc56e5aa626c808e8c6c0870dc87c10a957d86c7c22782be1d437d52b8bc28",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/model/Model.class",
                "3dd5e7b618cecf3c27e216a386e07937b1be694a7fc083b1bc2f7c993cbee3d9",
            )

    /** The same path in reverse keeps the head down until it has cleared the doorway. */
    @JvmStatic
    fun seating(phase: Float): Float {
        val t = ((phase - .30f) / .60f).coerceIn(0f, 1f)
        return t * t * (3f - 2f * t)
    }

    @JvmStatic
    fun transition(track: AnimationTrack?, entering: Boolean, exiting: Boolean): Boolean =
        track != null &&
            (track.currentClip?.name == CLIP || track.currentClip?.name == EXIT_CLIP) &&
            !track.looping &&
            track.getBlendWeight().isFinite() &&
            track.getBlendWeight() > 0f &&
            track.getDuration().isFinite() &&
            track.getDuration() > 0f &&
            track.getCurrentAnimationTime().isFinite() &&
            track.getCurrentAnimationTime() in 0f..track.getDuration() &&
            !(entering && exiting) &&
            !track.reverse &&
            (!entering || track.currentClip.name == CLIP) &&
            (!exiting || track.currentClip.name == EXIT_CLIP)

    /**
     * Apply in native vehicle-local units. Bone coordinates are body-local, scaled and Z-flipped by
     * the camera.
     */
    @JvmStatic
    fun position(
        outside: Vector3f,
        inside: Vector3f,
        root: Vector3f,
        fraction: Float,
        out: Vector3f,
    ): Vector3f =
        out.set(outside)
            .lerp(inside, fraction)
            .add(
                -BODY_SCALE * root.x * fraction,
                -BODY_SCALE * root.y * fraction,
                BODY_SCALE * root.z * fraction,
            )

    /** Rejected IK retains the direction-correct cosmetic path; cancellation stays inside. */
    @JvmStatic
    fun fallbackPosition(
        outside: Vector3f,
        inside: Vector3f,
        root: Vector3f,
        phase: Float,
        entering: Boolean,
        exiting: Boolean,
    ): Vector3f {
        val fraction = if (entering || exiting) seating(if (exiting) 1f - phase else phase) else 1f
        return position(outside, inside, root, fraction, Vector3f())
    }

    @JvmStatic
    @Synchronized
    private fun references(actor: SkinningData): VehicleStepPose.References? {
        references[actor]?.let {
            return it
        }
        val standing = ModelManager.instance.getAnimationClip("Bob_SatChairIn") ?: return null
        val driving = ModelManager.instance.getAnimationClip("Bob_IdleDriving") ?: return null
        fun pose(clip: zombie.core.skinnedmodel.animation.AnimationClip, name: String): Matrix4f? {
            val result = Matrix4f()
            return if (CartGrounding.referencePose(clip, actor, name, result)) result else null
        }
        val result =
            VehicleStepPose.References(
                (pose(standing, "Bip01") ?: return null).getTranslation(Vector3f()),
                pose(standing, "Bip01_L_Foot") ?: return null,
                pose(standing, "Bip01_R_Foot") ?: return null,
                (pose(driving, "Bip01") ?: return null).getTranslation(Vector3f()),
                pose(driving, "Bip01_L_Foot") ?: return null,
                pose(driving, "Bip01_R_Foot") ?: return null,
            )
        references[actor] = result
        return result
    }

    /**
     * The synchronized init has copied the native passenger offset; only these draw-local fields
     * change.
     */
    @JvmStatic
    fun capture(slot: ModelSlotRenderData?, source: ModelManager.ModelSlot?, supported: Boolean) {
        if (!supported || slot == null || source == null || !slot.inVehicle) return
        val player = source.character ?: return
        if (slot.character !== player || slot.`object` !== player) return
        val vehicle = player.getVehicle() ?: return
        val seat = vehicle.getSeat(player)
        if (seat < 0 || vehicle.getCharacter(seat) !== player) return
        val entering = player.getVariableBoolean("bEnteringVehicle")
        val exiting = player.getVariableBoolean("bExitingVehicle")
        if (entering && exiting) return
        val animation = source.model?.animPlayer ?: return
        if (
            animation !== player.getAnimationPlayer() ||
                !animation.isReady() ||
                animation.isBoneTransformsNeedFirstFrame()
        )
            return
        val tracks = animation.getMultiTrack().getTracks()
        var chosen: AnimationTrack? = null
        for (track in tracks) {
            if (
                transition(track, entering, exiting) &&
                    (chosen == null || track.getBlendWeight() > chosen.getBlendWeight())
            )
                chosen = track
        }
        val track = chosen ?: return
        // Use one phase for this immutable draw snapshot, including first-use reference work.
        val phase = track.getCurrentAnimationTime() / track.getDuration()
        val inside = vehicle.getPassengerPosition(seat, "inside")?.getOffset() ?: return
        val outside = vehicle.getPassengerPosition(seat, "outside")?.getOffset() ?: return
        val modelOffset = vehicle.getScript()?.getModel()?.getOffset() ?: return
        val rootIndex = animation.getSkinningBoneIndex("Bip01", -1)
        if (rootIndex < 0 || rootIndex >= animation.getModelTransformsCount()) return
        // Native bone-model matrices use the transposed LWJGL storage convention.
        val rootMatrix = animation.getModelTransformAt(rootIndex)
        val root = Vector3f(rootMatrix.m03, rootMatrix.m13, rootMatrix.m23)
        var origin =
            fallbackPosition(
                outside,
                inside,
                root,
                phase,
                entering,
                exiting,
            )
        if (entering || exiting) {
            val actor = animation.getSkinningData()
            val reference = references(actor)
            val poses = VehicleStepPalette.extract(slot, source.model, actor)
            if (reference != null && poses != null) {
                val stepOrigin =
                    VehicleStepPose.solve(
                        actor,
                        poses,
                        reference,
                        outside,
                        inside,
                        phase,
                        exiting,
                    )
                if (
                    stepOrigin != null && VehicleStepPalette.apply(slot, source.model, actor, poses)
                )
                    origin = stepOrigin
            }
        }
        origin.add(modelOffset)
        if (!origin.x.isFinite() || !origin.y.isFinite() || !origin.z.isFinite()) return
        // A cancelled exit returns to the native inside offset while its retiring clip blends away.
        slot.inVehicleX = origin.x
        slot.inVehicleY = origin.y
        slot.inVehicleZ = origin.z
    }
}
