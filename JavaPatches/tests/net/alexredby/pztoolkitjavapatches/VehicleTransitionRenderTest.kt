package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Patch
import net.bytebuddy.jar.asm.ClassReader
import net.bytebuddy.jar.asm.ClassVisitor
import net.bytebuddy.jar.asm.MethodVisitor
import net.bytebuddy.jar.asm.Opcodes
import org.joml.Vector3f
import zombie.core.skinnedmodel.animation.AnimationClip
import zombie.core.skinnedmodel.animation.AnimationTrack
import zombie.core.skinnedmodel.model.ModelSlotRenderData

object VehicleTransitionRenderTest {
    private fun check(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun close(expected: Float, actual: Float, message: String) =
        check(kotlin.math.abs(expected - actual) < 2e-6f, "$message: $expected != $actual")

    private fun nativeSnapshotBoundary() {
        val patch = Main.VehicleTransitionSlot::class.java.getAnnotation(Patch::class.java)
        val nativeOwner = "zombie/core/skinnedmodel/model/ModelSlotRenderData"
        val copied = mutableSetOf<String>()
        var paletteReady = false
        // initModel only allocates body entries. The later synchronized init
        // overwrites the pooled slot's native vehicle fields before drawing.
        val source =
            ModelSlotRenderData::class.java.getResourceAsStream("/" + nativeOwner + ".class")!!
        source.use {
            ClassReader(it)
                .accept(
                    object : ClassVisitor(Opcodes.ASM9) {
                        override fun visitMethod(
                            access: Int,
                            name: String,
                            descriptor: String,
                            signature: String?,
                            exceptions: Array<out String>?,
                        ): MethodVisitor? {
                            if (
                                name != patch.methodName ||
                                    !descriptor.startsWith(
                                        "(Lzombie/core/skinnedmodel/ModelManager\$ModelSlot;)",
                                    )
                            )
                                return null
                            return object : MethodVisitor(Opcodes.ASM9) {
                                override fun visitFieldInsn(
                                    opcode: Int,
                                    owner: String,
                                    name: String,
                                    descriptor: String,
                                ) {
                                    if (opcode == Opcodes.PUTFIELD && owner == nativeOwner)
                                        copied.add(name)
                                }

                                override fun visitMethodInsn(
                                    opcode: Int,
                                    owner: String,
                                    name: String,
                                    descriptor: String,
                                    isInterface: Boolean,
                                ) {
                                    if (owner == nativeOwner && name == "initRenderData") {
                                        check(
                                            copied.containsAll(
                                                listOf(
                                                    "inVehicle",
                                                    "inVehicleX",
                                                    "inVehicleY",
                                                    "inVehicleZ",
                                                ),
                                            ),
                                            "render hook runs before the native vehicle snapshot is populated",
                                        )
                                        paletteReady = true
                                    }
                                }
                            }
                        }
                    },
                    ClassReader.SKIP_DEBUG or ClassReader.SKIP_FRAMES,
                )
        }
        check(
            paletteReady,
            "render hook targets a method before native offset and palette initialization",
        )
    }

    private fun immutablePhaseSnapshot() {
        var phaseReads = 0
        var fallbackCalls = 0
        var solveCalls = 0
        val owner = "net/alexredby/pztoolkitjavapatches/VehicleTransitionRender"
        VehicleTransitionRender::class.java.getResourceAsStream("/$owner.class")!!.use {
            ClassReader(it)
                .accept(
                    object : ClassVisitor(Opcodes.ASM9) {
                        override fun visitMethod(
                            access: Int,
                            name: String,
                            descriptor: String,
                            signature: String?,
                            exceptions: Array<out String>?,
                        ): MethodVisitor? {
                            if (name != "capture") return null
                            return object : MethodVisitor(Opcodes.ASM9) {
                                override fun visitMethodInsn(
                                    opcode: Int,
                                    callOwner: String,
                                    name: String,
                                    descriptor: String,
                                    isInterface: Boolean,
                                ) {
                                    if (
                                        callOwner ==
                                            "zombie/core/skinnedmodel/animation/AnimationTrack" &&
                                            name == "getCurrentAnimationTime"
                                    )
                                        phaseReads++
                                    if (callOwner == owner && name == "fallbackPosition")
                                        fallbackCalls++
                                    if (
                                        callOwner ==
                                            "net/alexredby/pztoolkitjavapatches/VehicleStepPose" &&
                                            name == "solve"
                                    )
                                        solveCalls++
                                }
                            }
                        }
                    },
                    ClassReader.SKIP_DEBUG or ClassReader.SKIP_FRAMES,
                )
        }
        check(phaseReads == 1, "draw snapshot reads its mutable track phase $phaseReads times")
        check(fallbackCalls == 1 && solveCalls == 1, "phase regression omitted a draw path")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        nativeSnapshotBoundary()
        immutablePhaseSnapshot()
        check(VehicleTransitionRender.SUPPORTED, "supported native bytecode changed")
        val inside = Vector3f(.18f, -.14f, .09f)
        val outside = Vector3f(.62f, -.41f, .12f)
        val standing = Vector3f(.003f, .5045f, .0124f)
        val out = Vector3f()
        VehicleTransitionRender.position(outside, inside, standing, 0f, out)
        check(out.equals(outside, 2e-6f), "standing entry moved before the transition")
        VehicleTransitionRender.position(outside, inside, Vector3f(), 1f, out)
        check(out.equals(inside, 2e-6f), "driving endpoint differs from native seat")
        check(
            VehicleTransitionRender.fallbackPosition(outside, inside, standing, 0f, true, false)
                .equals(outside, 2e-6f),
            "rejected entry IK starts at the wrong doorway endpoint",
        )
        check(
            VehicleTransitionRender.fallbackPosition(outside, inside, Vector3f(), 1f, true, false)
                .equals(inside, 2e-6f),
            "rejected entry IK finishes outside",
        )
        check(
            VehicleTransitionRender.fallbackPosition(outside, inside, Vector3f(), 0f, false, true)
                .equals(inside, 2e-6f),
            "rejected exit IK starts outside",
        )
        check(
            VehicleTransitionRender.fallbackPosition(outside, inside, standing, 1f, false, true)
                .equals(outside, 2e-6f),
            "rejected exit IK finishes inside",
        )
        check(
            VehicleTransitionRender.fallbackPosition(outside, inside, Vector3f(), .5f, false, false)
                .equals(inside, 2e-6f),
            "cancelled IK path did not return inside",
        )
        val root = Vector3f(.01f, .32f, .15f)
        VehicleTransitionRender.position(outside, inside, root, 1f, out)
        close(inside.y - .48f, out.y, "chair root height was added above the roof")
        close(inside.z + .225f, out.z, "camera Z flip was not accounted for")
        for (phase in 0..100) {
            val f = phase / 100f
            val seated = VehicleTransitionRender.seating(f)
            check(seated in 0f..1f, "unbounded interpolation")
            if (phase > 0)
                check(seated >= VehicleTransitionRender.seating(f - .01f), "path reverses")
            val left =
                VehicleTransitionRender.position(outside, inside, Vector3f(), seated, Vector3f())
            val right =
                VehicleTransitionRender.position(
                    Vector3f(-outside.x, outside.y, outside.z),
                    Vector3f(-inside.x, inside.y, inside.z),
                    Vector3f(),
                    seated,
                    Vector3f(),
                )
            close(-left.x, right.x, "driver and passenger use different door paths")
        }
        val clip = AnimationClip(1f, emptyList(), VehicleTransitionRender.CLIP, true)
        val track = AnimationTrack.alloc()
        track.startClip(clip, false, 0f)
        track.setBlendWeight(1f)
        track.setCurrentTimeValue(.2f)
        check(VehicleTransitionRender.transition(track, true, false), "entry was rejected")
        check(
            !VehicleTransitionRender.transition(track, false, true),
            "wrong direction used for exit",
        )
        track.setCurrentTimeValue(Float.NaN)
        check(
            !VehicleTransitionRender.transition(track, true, false),
            "invalid track phase moved the draw",
        )
        track.setCurrentTimeValue(.2f)
        track.reverse = true
        close(.8f, track.getCurrentAnimationTime(), "native reversed phase contract changed")
        check(
            !VehicleTransitionRender.transition(track, false, true),
            "reverse clip bypassed the independent exit contacts",
        )
        track.startClip(
            AnimationClip(1f, emptyList(), VehicleTransitionRender.EXIT_CLIP, true),
            false,
            0f,
        )
        track.setBlendWeight(1f)
        check(
            VehicleTransitionRender.transition(track, false, true),
            "independent exit was rejected",
        )
        check(
            VehicleTransitionRender.transition(track, false, false),
            "cancelled exit lost blend normalization",
        )
        check(
            !VehicleTransitionRender.transition(track, true, true),
            "contradictory action flags accepted",
        )
        track.looping = true
        check(
            !VehicleTransitionRender.transition(track, false, true),
            "looping override was changed",
        )
        track.looping = false
        track.setBlendWeight(0f)
        check(!VehicleTransitionRender.transition(track, false, true), "dead track moved the draw")
        track.startClip(AnimationClip(1f, emptyList(), "Bob_SatChairIn", true), false, 0f)
        track.setBlendWeight(1f)
        check(
            !VehicleTransitionRender.transition(track, true, false),
            "third-party/native override was changed",
        )
        val slot = ModelSlotRenderData()
        slot.inVehicle = true
        slot.inVehicleX = 4f
        slot.inVehicleY = 5f
        slot.inVehicleZ = 6f
        VehicleTransitionRender.capture(slot, null, false)
        close(4f, slot.inVehicleX, "unsupported engine changed rendering")
        close(5f, slot.inVehicleY, "unsupported engine changed height")
        close(6f, slot.inVehicleZ, "unsupported engine changed depth")
        println("VEHICLE_TRANSITION_RENDER_PASS")
    }
}
