package net.alexredby.pztoolkitjavapatches

import java.lang.instrument.ClassFileTransformer
import java.lang.instrument.Instrumentation
import java.security.ProtectionDomain
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.Loader
import net.bytebuddy.jar.asm.ClassReader
import net.bytebuddy.jar.asm.ClassVisitor
import net.bytebuddy.jar.asm.ClassWriter
import net.bytebuddy.jar.asm.MethodVisitor
import net.bytebuddy.jar.asm.Opcodes

/** Keep the south-edge cache equal to the south result, avoiding repeated neighbour rebakes. */
object CutawaySouthEdge {
    private const val TARGET = "zombie/iso/fboRenderChunk/FBORenderCutaways"
    private const val LEVEL = "$TARGET\$ChunkLevelData"
    private const val SOUTH = "hasCutawayWestWallsOnSouthEdge"
    private const val METHOD = "(ILjava/util/ArrayList;)V"
    private const val HASH = "9f44080e7858af88c858235939a7bfc2b3c792ee64b69c763568f1ecc6d6ce03"
    @JvmField val SUPPORTED = BytecodeSupport.supports("$TARGET.class", HASH)
    private var installed = false
    @Volatile private var woven = false

    @JvmStatic
    @Synchronized
    fun install(): Boolean {
        if (installed) return woven
        if (!SUPPORTED) return false
        val instrumentation =
            Accessor.tryGet<Instrumentation>(Loader::class.java, "g_instrumentation", null)
                ?: return false
        if (!instrumentation.isRetransformClassesSupported) return false
        val transformer =
            object : ClassFileTransformer {
                override fun transform(
                    loader: ClassLoader?,
                    name: String?,
                    type: Class<*>?,
                    domain: ProtectionDomain?,
                    bytes: ByteArray?,
                ): ByteArray? {
                    if (name != TARGET) return null
                    val result = weave(bytes)
                    woven = result != null
                    return result
                }
            }
        instrumentation.addTransformer(transformer, true)
        try {
            val loaded =
                instrumentation.allLoadedClasses.firstOrNull { it.name == TARGET.replace('/', '.') }
            if (loaded != null) instrumentation.retransformClasses(loaded)
            else
                Class.forName(
                    TARGET.replace('/', '.'),
                    false,
                    CutawaySouthEdge::class.java.classLoader,
                )
            if (woven) {
                installed = true
                System.out.println(
                    "[PZToolkitJavaPatches] Cutaway south edge ready: exact native south-cache assignment",
                )
                return true
            }
        } catch (error: Exception) {
            System.err.println("[PZToolkitJavaPatches] Cutaway south edge disabled: $error")
        } catch (error: LinkageError) {
            System.err.println("[PZToolkitJavaPatches] Cutaway south edge disabled: $error")
        }
        instrumentation.removeTransformer(transformer)
        woven = false
        return false
    }

    private fun boundary(bytes: ByteArray): ByteArray {
        val writer = ClassWriter(0)
        writer.visit(Opcodes.V17, Opcodes.ACC_PUBLIC, TARGET, null, "java/lang/Object", null)
        val methods =
            linkedMapOf(
                "doCutawayVisitSquares" to METHOD,
                "hasAnyCutawayWalls" to "(ILzombie/iso/IsoChunk;IBIIII)Z",
                "invalidateChunk" to "(ILzombie/iso/IsoChunkMap;III)V",
            )
        for ((method, type) in methods) {
            ClassReader(bytes)
                .accept(
                    object : ClassVisitor(Opcodes.ASM9) {
                        override fun visitMethod(
                            access: Int,
                            name: String?,
                            descriptor: String?,
                            signature: String?,
                            exceptions: Array<out String>?,
                        ): MethodVisitor? =
                            if (name == method && descriptor == type)
                                writer.visitMethod(access, name, descriptor, signature, exceptions)
                            else null
                    },
                    ClassReader.SKIP_DEBUG,
                )
        }
        writer.visitEnd()
        return writer.toByteArray()
    }

    internal fun weave(bytes: ByteArray?): ByteArray? {
        if (!SUPPORTED || bytes == null) return null
        val original =
            CutawaySouthEdge::class.java.classLoader.getResourceAsStream("$TARGET.class")?.use {
                it.readAllBytes()
            } ?: return null
        if (!boundary(original).contentEquals(boundary(bytes))) return null
        return transformReviewed(bytes)
    }

    // Reached in production only after exact class-resource admission and method comparison.
    // Two passes replace one existing ILOAD; branches, flag mutation, off-screen masks,
    // neighbour coordinates, player index, callbacks and invalidation order are untouched.
    private fun transformReviewed(bytes: ByteArray): ByteArray? {
        var variableIndex = 0
        var previousLoad = -1
        var previousIndex = -1
        var southResult = -1
        var assignmentLoad = -1
        var assignmentIndex = -1
        var comparisons = 0
        var assignments = 0
        val reader = ClassReader(bytes)
        reader.accept(
            object : ClassVisitor(Opcodes.ASM9) {
                override fun visitMethod(
                    access: Int,
                    name: String?,
                    descriptor: String?,
                    signature: String?,
                    exceptions: Array<out String>?,
                ): MethodVisitor? {
                    if (name != "doCutawayVisitSquares" || descriptor != METHOD) return null
                    return object : MethodVisitor(Opcodes.ASM9) {
                        override fun visitVarInsn(opcode: Int, variable: Int) {
                            if (opcode == Opcodes.ILOAD) {
                                previousLoad = variable
                                previousIndex = variableIndex
                            }
                            variableIndex++
                        }

                        override fun visitFieldInsn(
                            opcode: Int,
                            owner: String?,
                            name: String?,
                            descriptor: String?,
                        ) {
                            if (owner != LEVEL || name != SOUTH || descriptor != "Z") return
                            if (opcode == Opcodes.GETFIELD) {
                                southResult = previousLoad
                                comparisons++
                            }
                            if (opcode == Opcodes.PUTFIELD) {
                                assignmentLoad = previousLoad
                                assignmentIndex = previousIndex
                                assignments++
                            }
                        }
                    }
                }
            },
            ClassReader.SKIP_DEBUG,
        )
        if (
            comparisons != 1 ||
                assignments != 1 ||
                southResult < 0 ||
                assignmentLoad != southResult - 1 ||
                assignmentIndex < 0
        )
            return null
        val writer = ClassWriter(reader, 0)
        var index = 0
        var replacements = 0
        reader.accept(
            object : ClassVisitor(Opcodes.ASM9, writer) {
                override fun visitMethod(
                    access: Int,
                    name: String?,
                    descriptor: String?,
                    signature: String?,
                    exceptions: Array<out String>?,
                ): MethodVisitor? {
                    val output = super.visitMethod(access, name, descriptor, signature, exceptions)
                    if (name != "doCutawayVisitSquares" || descriptor != METHOD) return output
                    return object : MethodVisitor(Opcodes.ASM9, output) {
                        override fun visitVarInsn(opcode: Int, variable: Int) {
                            if (index++ == assignmentIndex) {
                                if (opcode != Opcodes.ILOAD || variable != assignmentLoad) return
                                replacements++
                                super.visitVarInsn(opcode, southResult)
                            } else super.visitVarInsn(opcode, variable)
                        }
                    }
                }
            },
            0,
        )
        return if (replacements == 1) writer.toByteArray() else null
    }
}
