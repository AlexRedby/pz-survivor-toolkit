package net.alexredby.pztoolkitjavapatches

import jassimp.AiAnimation
import jassimp.AiBuiltInWrapperProvider
import jassimp.AiNode
import java.io.DataOutputStream
import java.security.DigestOutputStream
import java.security.MessageDigest
import java.util.HexFormat
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeletonParams
import zombie.core.skinnedmodel.model.jassimp.JAssImpImporter

/**
 * Remove three known DAMN Library mesh-object tracks before native skeletal binding. No upstream
 * assets are copied or rewritten; native skeletal tracks and error reporting stay native.
 */
object DamnLibraryAnimationBindings {
    @JvmField
    val SUPPORTED =
        BytecodeSupport.supports(
            "zombie/core/skinnedmodel/model/jassimp/ImportedSkeleton.class",
            "ceb9756c05f26f7aa730cc761cf13852fb3275690077500e047b3a8c6da8c0af",
        ) &&
            BytecodeSupport.supports(
                "jassimp/AiAnimation.class",
                "aed921fe2b2366ead7cc31db8efeeb84407650dcf8c7bf941362e0efcc06b300",
            )

    private val fingerprints =
        mapOf(
            "Bob_SatBack_facingBack" to
                "f6bf756f1039a8729b29daa3a7d29f1752574e74e9869d395d642eaacc853abc",
            "Bob_SatBack_facingRight" to
                "4945e7467d2ff325b95bd9a0fb2e7415a2de093a3aa4e10a5fa1b3e7ac5ceba6",
            "Bob_Spec_bushGunner" to
                "14555ff885a4de89a01bfb331e0abb25c8e4e9e202fcb7ccf270e79c2251ab97",
        )

    @JvmStatic
    fun prepare(params: ImportedSkeletonParams?) {
        if (
            !SUPPORTED ||
                params == null ||
                params.mode != JAssImpImporter.LoadMode.AnimationOnly ||
                params.scene == null ||
                params.scene.getNumAnimations() != 1 ||
                params.scene.getNumMeshes() != 1 ||
                params.skinnedTo?.boneIndices?.containsKey("Body") == true
        )
            return
        val animation = params.scene.getAnimations()[0]
        val expected = fingerprints[animation.getName()] ?: return
        if (animation.getNumChannels() != 46) return
        val root: AiNode = params.scene.getSceneRoot(AiBuiltInWrapperProvider()) ?: return
        if (root.getParent() != null || root.getNumChildren() != 3) return
        val children = root.getChildren().associateBy { it.getName() }
        if (children.keys != setOf("Dummy01", "Translation_Data", "Body")) return
        val dummy = children.getValue("Dummy01")
        val translation = children.getValue("Translation_Data")
        val body = children.getValue("Body")
        if (
            dummy.getParent() !== root ||
                translation.getParent() !== root ||
                body.getParent() !== root ||
                body.getNumChildren() != 0 ||
                body.getNumMeshes() != 1 ||
                body.getMeshes()[0] != 0 ||
                dummy.findNode("Body") != null ||
                params.scene.getMeshes()[0].getBones().any { it.getName() == "Body" }
        )
            return
        // The carrier mesh is a sibling of the skeleton. Even facingRight's fixed 90-degree
        // mesh transform must not be retargeted to a human bone. Changed upstream input stays
        // native.
        if (expected != fingerprint(animation, root)) return
        animation.getChannels().removeIf { it.getNodeName() == "Body" }
    }

    /** Canonical native-import topology/transforms and every animation channel/key payload. */
    internal fun fingerprint(animation: AiAnimation, root: AiNode): String {
        val digest = MessageDigest.getInstance("SHA-256")
        DataOutputStream(DigestOutputStream(java.io.OutputStream.nullOutputStream(), digest)).use {
            out ->
            fun node(current: AiNode) {
                out.writeUTF(current.getName())
                out.writeInt(current.getNumMeshes())
                for (mesh in current.getMeshes()) out.writeInt(mesh)
                val transform = current.getTransform(AiBuiltInWrapperProvider())
                for (row in 0..3) for (column in 0..3) out.writeFloat(transform.get(row, column))
                out.writeInt(current.getNumChildren())
                for (child in current.getChildren()) node(child)
            }
            node(root)
            out.writeUTF(animation.getName())
            out.writeDouble(animation.getDuration())
            out.writeDouble(animation.getTicksPerSecond())
            out.writeInt(animation.getNumChannels())
            for (channel in animation.getChannels()) {
                out.writeUTF(channel.getNodeName())
                out.writeInt(channel.getPreState().ordinal)
                out.writeInt(channel.getPostState().ordinal)
                out.writeInt(channel.getNumPosKeys())
                for (i in 0 until channel.getNumPosKeys()) {
                    out.writeDouble(channel.getPosKeyTime(i))
                    out.writeFloat(channel.getPosKeyX(i))
                    out.writeFloat(channel.getPosKeyY(i))
                    out.writeFloat(channel.getPosKeyZ(i))
                }
                out.writeInt(channel.getNumRotKeys())
                for (i in 0 until channel.getNumRotKeys()) {
                    out.writeDouble(channel.getRotKeyTime(i))
                    out.writeFloat(channel.getRotKeyX(i))
                    out.writeFloat(channel.getRotKeyY(i))
                    out.writeFloat(channel.getRotKeyZ(i))
                    out.writeFloat(channel.getRotKeyW(i))
                }
                out.writeInt(channel.getNumScaleKeys())
                for (i in 0 until channel.getNumScaleKeys()) {
                    out.writeDouble(channel.getScaleKeyTime(i))
                    out.writeFloat(channel.getScaleKeyX(i))
                    out.writeFloat(channel.getScaleKeyY(i))
                    out.writeFloat(channel.getScaleKeyZ(i))
                }
            }
        }
        return HexFormat.of().formatHex(digest.digest())
    }
}
