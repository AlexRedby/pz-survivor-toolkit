package net.alexredby.pztoolkitjavapatches

import jassimp.AiAnimation
import jassimp.AiBuiltInWrapperProvider
import jassimp.AiNode
import jassimp.AiNodeAnim
import jassimp.AiPostProcessSteps
import jassimp.Jassimp
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.lang.reflect.Field
import java.nio.FloatBuffer
import java.nio.file.Files
import java.nio.file.Path
import java.util.EnumSet
import me.zed_0xff.zombie_buddy.PatchEngine
import zombie.ZomboidFileSystem
import zombie.core.skinnedmodel.animation.AnimationClip
import zombie.core.skinnedmodel.animation.Keyframe
import zombie.core.skinnedmodel.model.SkinningData
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeletonParams
import zombie.core.skinnedmodel.model.jassimp.JAssImpImporter
import zombie.core.skinnedmodel.model.jassimp.ProcessedAiSceneParams
import zombie.debug.DebugLog
import zombie.debug.DebugType
import zombie.debug.LogSeverity

/**
 * Source-backed native regression. PZ_TEST_DAMNLIB_ANIMS explicitly selects upstream
 * common/media/anims_X/Bob; no Workshop assets are copied into this project.
 */
object DamnLibraryAnimationChecks {
    private val clips =
        listOf("Bob_SatBack_facingBack", "Bob_SatBack_facingRight", "Bob_Spec_bushGunner")
    private val log = ByteArrayOutputStream()

    private fun verify(value: Boolean, reason: String) {
        if (!value) throw AssertionError(reason)
    }

    private fun field(type: Class<*>, name: String): Field =
        type.getDeclaredField(name).apply { isAccessible = true }

    private fun field(target: Any, name: String): Any = field(target.javaClass, name).get(target)

    private fun load(source: Path): ImportedSkeletonParams {
        verify(Files.isRegularFile(source), "Missing explicitly selected upstream source: $source")
        val params = ProcessedAiSceneParams.create()
        params.scene =
            Jassimp.importFile(
                source.toString(),
                EnumSet.of(
                    AiPostProcessSteps.MAKE_LEFT_HANDED,
                    AiPostProcessSteps.REMOVE_REDUNDANT_MATERIALS,
                ),
            )
        params.mode = JAssImpImporter.LoadMode.AnimationOnly
        params.animBonesScaleModifier = 1f
        return ImportedSkeletonParams.create(params, params.scene.getMeshes()[0])
    }

    private fun animation(params: ImportedSkeletonParams): AiAnimation =
        params.scene.getAnimations()[0]

    private fun root(params: ImportedSkeletonParams): AiNode =
        params.scene.getSceneRoot(AiBuiltInWrapperProvider())

    private fun channels(params: ImportedSkeletonParams): MutableList<AiNodeAnim> =
        animation(params).getChannels()

    private fun bodyChannels(params: ImportedSkeletonParams): Int =
        channels(params).count { it.getNodeName() == "Body" }

    private fun DataOutputStream.number(value: Float) = writeInt(value.toRawBits())

    private fun DataOutputStream.frame(key: Keyframe) {
        writeInt(key.bone)
        writeUTF(key.boneName)
        number(key.time)
        number(key.position.x)
        number(key.position.y)
        number(key.position.z)
        number(key.rotation.x)
        number(key.rotation.y)
        number(key.rotation.z)
        number(key.rotation.w)
        number(key.scale.x)
        number(key.scale.y)
        number(key.scale.z)
    }

    @Suppress("UNCHECKED_CAST")
    private fun skeleton(imported: ImportedSkeleton): ByteArray {
        val bytes = ByteArrayOutputStream()
        DataOutputStream(bytes).use { out ->
            val indices = field(imported, "boneIndices") as Map<String, Int>
            verify(
                indices.size == 45 && "Body" !in indices,
                "Expected native 45-bone human binding",
            )
            for ((name, index) in indices.toSortedMap()) {
                out.writeUTF(name)
                out.writeInt(index)
            }
            for (parent in field(imported, "skeletonHierarchy") as List<Int>) out.writeInt(parent)
            for (name in listOf("bindPose", "invBindPose", "skinOffsetMatrices")) {
                val matrices = field(imported, name) as List<org.lwjgl.util.vector.Matrix4f>
                out.writeInt(matrices.size)
                for (matrix in matrices) {
                    val values = FloatBuffer.allocate(16)
                    matrix.store(values)
                    for (value in values.array()) out.number(value)
                }
            }
            val importedClips = field(imported, "clips") as Map<String, AnimationClip>
            verify(importedClips.size == 1, "Expected one imported native clip")
            val clip = importedClips.values.single()
            verify(clip.getKeyframes().size == 47, "Expected all 47 native skeletal keyframes")
            out.writeUTF(clip.name)
            out.number(clip.getDuration())
            out.writeBoolean(clip.keepLastFrame)
            out.writeBoolean(clip.isRagdoll)
            for (key in clip.getKeyframes()) out.frame(key)
            out.writeInt(clip.getRootMotionFrameCount())
            for (i in 0 until clip.getRootMotionFrameCount()) out.frame(
                clip.getRootMotionFrameAt(i),
            )
        }
        return bytes.toByteArray()
    }

    private fun run(params: ImportedSkeletonParams, bodyError: Boolean): ByteArray {
        log.reset()
        val result = skeleton(ImportedSkeleton.process(params))
        val output = log.toString(Charsets.UTF_8)
        verify(
            output.contains("Could not find bone index for node name: \"Body\"") == bodyError,
            "Native Body diagnostic did not match expected state: $output",
        )
        return result
    }

    private fun untouched(params: ImportedSkeletonParams, reason: String) {
        val before = channels(params).toList()
        DamnLibraryAnimationBindings.prepare(params)
        verify(before == channels(params) && bodyChannels(params) == 1, reason)
    }

    @JvmStatic
    @Suppress("UNCHECKED_CAST")
    fun main(args: Array<String>) {
        val configured = System.getenv("PZ_TEST_DAMNLIB_ANIMS")
        verify(
            !configured.isNullOrBlank(),
            "Set PZ_TEST_DAMNLIB_ANIMS to upstream damnlib/common/media/anims_X/Bob",
        )
        val source = Path.of(configured!!)
        verify(
            source.isAbsolute && Files.isDirectory(source),
            "PZ_TEST_DAMNLIB_ANIMS must name an existing absolute directory",
        )
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"))
        DebugType.General.setLogSeverity(LogSeverity.Error)
        DebugLog.getInstance().setStdErr(log)
        DebugLog.getInstance().setStdOut(log)
        try {
            verify(
                DamnLibraryAnimationBindings.SUPPORTED,
                "Native skeleton/import bytecode is unsupported",
            )
            val nativeHuman =
                ImportedSkeleton.process(load(Path.of("media/anims_X/Bob/Bob_Idle.x")))
            val nativeIndices = field(nativeHuman, "boneIndices") as Map<String, Int>
            val nativeHierarchy = field(nativeHuman, "skeletonHierarchy") as List<Int>
            val nativeOffsets = List(nativeIndices.size) { org.lwjgl.util.vector.Matrix4f() }
            val target =
                SkinningData(
                    HashMap(),
                    nativeOffsets,
                    nativeOffsets,
                    nativeOffsets,
                    nativeHierarchy,
                    HashMap(nativeIndices),
                )
            val baseline = mutableMapOf<String, ByteArray>()
            for (clip in clips) {
                val params = load(source.resolve("$clip.X"))
                verify(
                    animation(params).getName() == clip,
                    "Native Jassimp changed the authored AnimationSet name",
                )
                verify(
                    bodyChannels(params) == 1,
                    "Upstream source no longer reproduces the orphan Body channel",
                )
                baseline[clip] = run(params, true)
                val bound = load(source.resolve("$clip.X"))
                bound.skinnedTo = target
                baseline["$clip:bound"] = run(bound, true)
            }
            // Public native entry point used by ProcessedAiScene/FileTask_LoadAnimation.
            PatchEngine.applyPatches(
                "net.alexredby.pztoolkitjavapatches",
                DamnLibraryAnimationChecks::class.java.classLoader,
            )
            for (clip in clips) {
                val params = load(source.resolve("$clip.X"))
                val expected = channels(params).filter { it.getNodeName() != "Body" }
                verify(
                    baseline.getValue(clip).contentEquals(run(params, false)),
                    "Woven input cleanup changed skeletal output for $clip",
                )
                verify(
                    channels(params) == expected,
                    "Woven cleanup replaced/reordered unrelated channels for $clip",
                )
                verify(
                    bodyChannels(params) == 0,
                    "Woven process did not remove orphan Body for $clip",
                )
                DamnLibraryAnimationBindings.prepare(params)
                verify(
                    channels(params) == expected,
                    "Repeated cleanup changed already-correct input",
                )
                val bound = load(source.resolve("$clip.X"))
                bound.skinnedTo = target
                verify(
                    baseline.getValue("$clip:bound").contentEquals(run(bound, false)),
                    "Woven cleanup changed the native target-bound skeleton for $clip",
                )
                verify(
                    bodyChannels(bound) == 0,
                    "Target-bound import retained orphan Body for $clip",
                )
            }
            val first = source.resolve("${clips[0]}.X")
            val unknown = load(first)
            field(AiAnimation::class.java, "m_name").set(animation(unknown), "UnknownMod_Clip")
            untouched(unknown, "Unknown clip name was changed")
            run(unknown, true)

            val changed = load(first)
            val human = channels(changed).single { it.getNodeName() == "Bip01" }
            human.getPosKeyBuffer().putFloat(8, human.getPosKeyX(0) + .125f)
            untouched(changed, "Changed upstream key payload bypassed the fingerprint guard")
            run(changed, true)

            val missing = load(first)
            root(missing).getChildren().removeIf { it.getName() == "Body" }
            untouched(missing, "Missing mesh node bypassed the shape guard")
            run(missing, true)

            val child = load(first)
            root(child).findNode("Body").getChildren().add(root(child).findNode("Translation_Data"))
            untouched(child, "Body with children was treated as an orphan leaf")
            run(child, true)

            val topology = load(first)
            field(AiNode::class.java, "m_name")
                .set(root(topology).findNode("Bip01_Head"), "ChangedHeadNode")
            untouched(topology, "Changed skeleton topology bypassed the fingerprint guard")

            val bound = load(first)
            val indices = HashMap(nativeIndices)
            val hierarchy = ArrayList(nativeHierarchy)
            indices["Body"] = indices.size
            hierarchy.add(-1)
            val offsets = List(indices.size) { org.lwjgl.util.vector.Matrix4f() }
            bound.skinnedTo = SkinningData(HashMap(), offsets, offsets, offsets, hierarchy, indices)
            untouched(bound, "Genuine target Body binding was removed")

            val skeletal = load(first)
            val tree = root(skeletal)
            val body = tree.findNode("Body")
            val dummy = tree.findNode("Dummy01")
            tree.getChildren().remove(body)
            dummy.getChildren().add(body)
            field(AiNode::class.java, "m_parent").set(body, dummy)
            untouched(skeletal, "Body inside the actual skeleton was removed")
            log.reset()
            val actual = ImportedSkeleton.process(skeletal)
            verify(
                (field(actual, "boneIndices") as Map<*, *>).containsKey("Body"),
                "Native genuine Body bone was lost",
            )
            verify(
                !log.toString().contains("Could not find bone index"),
                "Genuine bone binding produced an importer error",
            )

            val unknownBone = load(first)
            val head = channels(unknownBone).single { it.getNodeName() == "Bip01_Head" }
            field(AiNodeAnim::class.java, "m_nodeName").set(head, "UnknownBone")
            untouched(unknownBone, "Unrelated unknown bone error was hidden")
            log.reset()
            ImportedSkeleton.process(unknownBone)
            verify(
                log.toString().contains("node name: \"UnknownBone\"") &&
                    log.toString().contains("node name: \"Body\""),
                "Unknown input no longer reaches native bone error reporting",
            )
        } finally {
            DebugLog.getInstance().setStdErr(System.err)
            DebugLog.getInstance().setStdOut(System.out)
        }
        println(
            "DAMN_LIBRARY_ANIMATION_PASS (3 source-backed woven imports, exact 45 bones/47 keys, untouched unknown/bound inputs and native diagnostics)",
        )
        System.exit(0)
    }
}
