package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field
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
import java.util.WeakHashMap
import zombie.core.Transaction
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.packets.ItemTransactionPacket

/** Keep the client watchdog in one clock domain across initial TimeSync and later corrections. */
internal object ItemTransactionClockLogic {
    private const val TARGET = "zombie/core/TransactionManager"
    private const val PREDICATE = "lambda\$update\$1"
    private const val DESCRIPTOR = "(JLzombie/core/Transaction;)Z"
    private var installed = false
    @Volatile private var woven = false
    @JvmField
    val SUPPORTED =
        QueueManagers.ITEM_SUPPORTED &&
            BytecodeSupport.supports(
                "zombie/GameTime.class",
                "ec030ac26790d8c06712c3e1d5935bb29cc816ac3b6f1ea55b06ebeccb7e7125",
            )

    private fun nativeField(name: String): Field? =
        if (!SUPPORTED) null
        else Transaction::class.java.getDeclaredField(name).apply { isAccessible = true }

    private val start = nativeField("startTime")
    private val end = nativeField("endTime")
    // Exact reviewed native classes inherit Object equality. Weak keys retain no actor,
    // connection, inventory or completed request; values contain only local nanoseconds.
    private val births = WeakHashMap<Transaction, Long>()

    // As in item-batch admission, transform only the reviewed method, allowing unrelated
    // native methods to have other compatible patches. Changed predicates remain untouched.
    private fun canonical(bytes: ByteArray): ByteArray {
        val writer = ClassWriter(0)
        writer.visit(Opcodes.V17, Opcodes.ACC_PUBLIC, TARGET, null, "java/lang/Object", null)
        ClassReader(bytes).accept(object : ClassVisitor(Opcodes.ASM9) {
            override fun visitMethod(access: Int, name: String?, descriptor: String?,
                signature: String?, exceptions: Array<out String>?): MethodVisitor? =
                if (name == PREDICATE && descriptor == DESCRIPTOR)
                    writer.visitMethod(access, name, descriptor, signature, exceptions)
                else null
        }, ClassReader.SKIP_DEBUG)
        writer.visitEnd()
        return writer.toByteArray()
    }

    @JvmStatic
    fun weave(bytes: ByteArray?): ByteArray? {
        if (!SUPPORTED || bytes == null) return null
        val original = ItemTransactionClock::class.java.classLoader
            .getResourceAsStream("$TARGET.class")?.use { it.readAllBytes() } ?: return null
        if (!canonical(original).contentEquals(canonical(bytes))) return null
        val reader = ClassReader(bytes)
        val writer = ClassWriter(reader, ClassWriter.COMPUTE_MAXS)
        var returns = 0
        reader.accept(object : ClassVisitor(Opcodes.ASM9, writer) {
            override fun visitMethod(access: Int, name: String?, descriptor: String?,
                signature: String?, exceptions: Array<out String>?): MethodVisitor? {
                val output = super.visitMethod(access, name, descriptor, signature, exceptions)
                if (name != PREDICATE || descriptor != DESCRIPTOR) return output
                return object : MethodVisitor(Opcodes.ASM9, output) {
                    override fun visitInsn(opcode: Int) {
                        if (opcode == Opcodes.IRETURN) {
                            // Stack: nativeResult -> transaction, nativeResult -> adjustedResult.
                            super.visitVarInsn(Opcodes.ALOAD, 2)
                            super.visitInsn(Opcodes.SWAP)
                            super.visitMethodInsn(Opcodes.INVOKESTATIC,
                                "net/alexredby/pztoolkitjavapatches/ItemTransactionClock", "expired",
                                "(Lzombie/core/Transaction;Z)Z", false)
                            returns++
                        }
                        super.visitInsn(opcode)
                    }
                }
            }
        }, 0)
        return if (returns == 1) writer.toByteArray() else null
    }

    /** Called under the facade class monitor, before native request creation. */
    @JvmStatic
    fun install(supported: Boolean): Boolean {
        if (!supported || !SUPPORTED) return false
        if (installed) return woven
        val instrumentation = Accessor.tryGet<Instrumentation>(Loader::class.java, "g_instrumentation", null)
            ?: return false
        if (!instrumentation.isRetransformClassesSupported) return false
        val transformer = object : ClassFileTransformer {
            override fun transform(loader: ClassLoader?, name: String?, type: Class<*>?,
                domain: ProtectionDomain?, bytes: ByteArray?): ByteArray? {
                if (!TARGET.equals(name)) return null
                return try { weave(bytes).also { woven = it != null } }
                catch (error: Exception) { woven = false; null }
            }
        }
        instrumentation.addTransformer(transformer, true)
        try {
            val loaded = instrumentation.allLoadedClasses.firstOrNull { it.name == TARGET.replace('/', '.') }
            if (loaded != null) instrumentation.retransformClasses(loaded)
            else Class.forName(TARGET.replace('/', '.'), false, ItemTransactionClock::class.java.classLoader)
            if (woven) { installed = true; return true }
        } catch (error: Exception) { woven = false }
        catch (error: LinkageError) { woven = false }
        instrumentation.removeTransformer(transformer)
        System.err.println("[PZToolkitJavaPatches] Disabled item transaction clock: native timeout hook unavailable")
        return false
    }

    @JvmStatic
    fun allocated(transaction: Transaction?) {
        if (!woven || !SUPPORTED || !GameClient.client || GameServer.server ||
            transaction?.javaClass != ItemTransactionPacket::class.java) return
        synchronized(births) { births[transaction] = System.nanoTime() }
    }

    @JvmStatic
    fun expiredAt(transaction: Transaction?, nativeResult: Boolean, nowNanos: Long): Boolean {
        if (!woven || !SUPPORTED || !GameClient.client || GameServer.server ||
            transaction?.javaClass != ItemTransactionPacket::class.java)
            return nativeResult
        val birth = synchronized(births) { births[transaction] } ?: return nativeResult
        // The native predicate uses duration relative to the original request, including
        // setDuration on Accept. Never rewrite these wire-visible server timestamps.
        val duration = end!!.getLong(transaction) - start!!.getLong(transaction)
        val timeoutMillis = if (duration > 0L) duration + 10_000L else 20_000L
        val ageMillis = (nowNanos - birth) / 1_000_000L
        return ageMillis > timeoutMillis
    }
}
