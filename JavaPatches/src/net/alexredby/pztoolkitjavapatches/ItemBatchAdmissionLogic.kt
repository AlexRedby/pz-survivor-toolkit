package net.alexredby.pztoolkitjavapatches

import java.lang.instrument.ClassFileTransformer
import java.lang.instrument.Instrumentation
import java.security.MessageDigest
import java.security.ProtectionDomain
import java.util.HexFormat
import java.util.NoSuchElementException
import java.util.concurrent.ConcurrentLinkedQueue
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.Loader
import net.bytebuddy.jar.asm.ClassReader
import net.bytebuddy.jar.asm.ClassVisitor
import net.bytebuddy.jar.asm.ClassWriter
import net.bytebuddy.jar.asm.MethodVisitor
import net.bytebuddy.jar.asm.Opcodes
import zombie.core.Transaction
import zombie.core.Transaction.TransactionState
import zombie.inventory.ItemContainer
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.fields.ContainerID
import zombie.network.fields.ContainerID.ContainerType
import zombie.network.fields.character.PlayerID
import zombie.network.packets.ItemTransactionPacket

internal object ItemBatchAdmissionLogic {
    private const val TARGET = "zombie/core/TransactionManager"
    private const val HELPER = "net/alexredby/pztoolkitjavapatches/ItemBatchAdmission"
    private const val HASH = "4a0f649f5e55edd13eff7d6788934fbec49e0073901609e1c12731fc47d7481d"
    private const val CHECK_DESCRIPTOR =
        "(ILzombie/inventory/InventoryItem;Lzombie/inventory/ItemContainer;" +
            "Lzombie/inventory/ItemContainer;Ljava/lang/String;Lzombie/network/packets/ItemTransactionPacket;" +
            "Lzombie/characters/IsoPlayer;)B"

    @JvmField
    val SUPPORTED =
        QueueManagers.ITEM_SUPPORTED &&
            BytecodeSupport.supports(
                "zombie/network/fields/ContainerID.class",
                "d7ef29f65c423135d70f829a1381b9e32ce06d68f87ae49de1980bfcf7c0244b",
            ) &&
            BytecodeSupport.supports(
                "zombie/inventory/ItemContainer.class",
                "a2ac7dd6235f91255dc57b91419a2c8609bdb105214cddf7fb445b70507b6f96",
            )

    private var installed = false
    @Volatile private var woven = false

    /** Invoked only through ItemBatchAdmission.install's original Java class monitor. */
    @JvmStatic
    fun install(supported: Boolean): Boolean {
        if (!supported || !SUPPORTED) return false
        if (installed) return woven
        val instrumentation =
            Accessor.tryGet<Instrumentation>(Loader::class.java, "g_instrumentation", null)
        if (instrumentation == null || !instrumentation.isRetransformClassesSupported())
            return false
        val transformer =
            object : ClassFileTransformer {
                override fun transform(
                    loader: ClassLoader?,
                    name: String?,
                    type: Class<*>?,
                    domain: ProtectionDomain?,
                    bytes: ByteArray?,
                ): ByteArray? {
                    // Keep foreign-class dispatch independent of Kotlin runtime initialization.
                    if (!TARGET.equals(name)) return null
                    val replacement = weave(bytes)
                    woven = replacement != null
                    if (!woven)
                        System.err.println(
                            "[PZToolkitJavaPatches] Disabled item batch admission: native consistency method changed",
                        )
                    return replacement
                }
            }
        instrumentation.addTransformer(transformer, true)
        return try {
            val loaded =
                instrumentation.allLoadedClasses.firstOrNull { it.name == TARGET.replace('/', '.') }
            if (loaded != null) instrumentation.retransformClasses(loaded)
            else
                Class.forName(
                    TARGET.replace('/', '.'),
                    false,
                    ItemBatchAdmission::class.java.classLoader,
                )
            if (!woven) {
                instrumentation.removeTransformer(transformer)
                false
            } else {
                installed = true
                true
            }
        } catch (error: Exception) {
            installationFailed(instrumentation, transformer, error)
        } catch (error: LinkageError) {
            installationFailed(instrumentation, transformer, error)
        }
    }

    private fun installationFailed(
        instrumentation: Instrumentation,
        transformer: ClassFileTransformer,
        error: Throwable,
    ): Boolean {
        woven = false
        instrumentation.removeTransformer(transformer)
        System.err.println("[PZToolkitJavaPatches] Disabled item batch admission: $error")
        return false
    }

    class Shadow(packet: ItemTransactionPacket?) : Transaction() {
        init {
            state = TransactionState.Request
            val owner = Accessor.tryGet<PlayerID>(packet, "playerId", null)
            if (owner != null && owner.getPlayer() != null) playerId.set(owner.getPlayer())
        }

        fun append(entry: Any?) {
            entries.add(entry as TransactionEntry?)
        }

        fun isEmpty(): Boolean = entries.isEmpty()

        override fun getDescription(): String = "Toolkit incoming item batch prefix"

        companion object {
            private fun entry(value: Any?): TransactionEntry =
                (value as TransactionEntry?) ?: throw NullPointerException()

            fun id(value: Any?): Int? = entry(value).itemId

            fun source(value: Any?): ContainerID = entry(value).sourceId

            fun destination(value: Any?): ContainerID = entry(value).destinationId
        }
    }

    @JvmStatic
    fun beginRequest(
        packet: ItemTransactionPacket?,
        requests: ThreadLocal<ItemBatchAdmission.RequestScope>,
    ): ItemBatchAdmission.RequestScope? {
        if (
            !woven ||
                !GameServer.server ||
                GameClient.client ||
                Accessor.tryGet<TransactionState>(packet, "state", null) != TransactionState.Request
        )
            return null
        val extra = Accessor.tryGet<String>(packet, "extra", null)
        if (extra != null && extra.isNotEmpty()) return null
        val entries = Accessor.tryGet<List<*>>(packet, "entries", null)
        if (entries == null || entries.size < 2) return null
        var source: ItemContainer? = null
        var destination: ItemContainer? = null
        for (entry in entries) {
            if (
                entry == null ||
                    Shadow.id(entry) == null ||
                    Shadow.id(entry) == -1 ||
                    special(Shadow.source(entry).containerType) ||
                    special(Shadow.destination(entry).containerType)
            )
                return null
            val sc = Shadow.source(entry).getContainer()
            val dc = Shadow.destination(entry).getContainer()
            if (sc == null || dc == null || sc.getType() == "floor" || dc.getType() == "floor")
                return null
            if (source == null) {
                source = sc
                destination = dc
            } else if (source !== sc || destination !== dc) return null
        }
        return ItemBatchAdmission.RequestScope(requests.get(), packet, entries).also {
            requests.set(it)
        }
    }

    private fun special(type: ContainerType?): Boolean =
        type == ContainerType.Undefined ||
            type == ContainerType.IsoObject ||
            type == ContainerType.Floor

    @JvmStatic
    fun endRequest(
        scope: ItemBatchAdmission.RequestScope?,
        requests: ThreadLocal<ItemBatchAdmission.RequestScope>,
    ) {
        if (scope == null) return
        if (scope.previous == null) requests.remove() else requests.set(scope.previous)
    }

    @JvmStatic
    fun beginCheck(
        packet: ItemTransactionPacket?,
        itemId: Int,
        source: ItemContainer?,
        destination: ItemContainer?,
        requests: ThreadLocal<ItemBatchAdmission.RequestScope>,
        checks: ThreadLocal<ItemBatchAdmission.CheckScope>,
    ): ItemBatchAdmission.CheckScope? {
        val request = requests.get()
        val previous = checks.get()
        if (request == null && previous == null) return null
        var entry: Any? = null
        if (
            request != null &&
                request.packet === packet &&
                !request.checking &&
                request.index < request.entries.size
        ) {
            val candidate = request.entries[request.index]
            if (
                (Shadow.id(candidate) ?: throw NullPointerException()) == itemId &&
                    Shadow.source(candidate).getContainer() === source &&
                    Shadow.destination(candidate).getContainer() === destination
            )
                entry = candidate
        }
        // Mask an outer check during unrelated/reentrant native consistency calls.
        return ItemBatchAdmission.CheckScope(previous, if (entry == null) null else request, entry)
            .also { scope ->
                if (scope.request != null) scope.request.checking = true
                checks.set(scope)
            }
    }

    @JvmStatic
    fun endCheck(
        scope: ItemBatchAdmission.CheckScope?,
        result: Byte,
        failure: Throwable?,
        checks: ThreadLocal<ItemBatchAdmission.CheckScope>,
    ) {
        if (scope == null) return
        try {
            if (scope.request != null) {
                if (failure == null && result == 0.toByte()) {
                    scope.request.prefix.append(scope.entry)
                    scope.request.index++
                }
                scope.request.checking = false
            }
        } finally {
            if (scope.previous == null) checks.remove() else checks.set(scope.previous)
        }
    }

    @JvmStatic
    fun reservations(
        real: ConcurrentLinkedQueue<Transaction>,
        checks: ThreadLocal<ItemBatchAdmission.CheckScope>,
    ): Iterator<Transaction> {
        val nativeIterator = real.iterator()
        val check = checks.get()
        if (check == null || check.request == null || check.request.prefix.isEmpty())
            return nativeIterator
        val prefix = check.request.prefix
        return object : Iterator<Transaction> {
            private var pending = true

            override fun hasNext(): Boolean = nativeIterator.hasNext() || pending

            override fun next(): Transaction {
                if (nativeIterator.hasNext()) return nativeIterator.next()
                if (!pending) throw NoSuchElementException()
                pending = false
                return prefix
            }
        }
    }

    private fun canonicalCheck(bytes: ByteArray?): ByteArray {
        val writer = ClassWriter(0)
        writer.visit(Opcodes.V17, Opcodes.ACC_PUBLIC, TARGET, null, "java/lang/Object", null)
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
                        if (name == "isConsistent" && descriptor == CHECK_DESCRIPTOR)
                            writer.visitMethod(access, name, descriptor, signature, exceptions)
                        else null
                },
                ClassReader.SKIP_DEBUG,
            )
        writer.visitEnd()
        return writer.toByteArray()
    }

    @JvmStatic
    fun weave(bytes: ByteArray?): ByteArray? =
        try {
            val original =
                ItemBatchAdmission::class
                    .java
                    .classLoader
                    .getResourceAsStream("$TARGET.class")
                    .use { input ->
                        input?.readAllBytes()
                    }
            if (
                original == null ||
                    HASH !=
                        HexFormat.of()
                            .formatHex(MessageDigest.getInstance("SHA-256").digest(original)) ||
                    !canonicalCheck(original).contentEquals(canonicalCheck(bytes))
            )
                null
            else {
                val reader = ClassReader(bytes)
                val writer = ClassWriter(reader, 0)
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
                            val output =
                                super.visitMethod(access, name, descriptor, signature, exceptions)
                            if (name != "isConsistent" || descriptor != CHECK_DESCRIPTOR)
                                return output
                            return object : MethodVisitor(Opcodes.ASM9, output) {
                                override fun visitMethodInsn(
                                    opcode: Int,
                                    owner: String?,
                                    method: String?,
                                    descriptor: String?,
                                    itf: Boolean,
                                ) {
                                    if (
                                        opcode == Opcodes.INVOKEVIRTUAL &&
                                            owner == "java/util/concurrent/ConcurrentLinkedQueue" &&
                                            method == "iterator" &&
                                            descriptor == "()Ljava/util/Iterator;"
                                    ) {
                                        super.visitMethodInsn(
                                            Opcodes.INVOKESTATIC,
                                            HELPER,
                                            "reservations",
                                            "(Ljava/util/concurrent/ConcurrentLinkedQueue;)Ljava/util/Iterator;",
                                            false,
                                        )
                                        replacements++
                                    } else
                                        super.visitMethodInsn(
                                            opcode,
                                            owner,
                                            method,
                                            descriptor,
                                            itf,
                                        )
                                }
                            }
                        }
                    },
                    0,
                )
                if (replacements == 1) writer.toByteArray() else null
            }
        } catch (error: Exception) {
            System.err.println("[PZToolkitJavaPatches] Disabled item batch bytecode: $error")
            null
        }
}
