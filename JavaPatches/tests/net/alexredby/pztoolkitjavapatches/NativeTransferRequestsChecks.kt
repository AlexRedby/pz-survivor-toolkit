package net.alexredby.pztoolkitjavapatches

import java.nio.ByteBuffer
import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.ConcurrentLinkedQueue
import net.alexredby.native_transfer_request_fixture.NativeTransferSenderStub
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.integration.expose.LuaJavaInvoker
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.KahluaThread
import se.krka.kahlua.vm.LuaClosure
import se.krka.kahlua.vm.Prototype
import sun.misc.Unsafe
import zombie.Lua.KahluaNumberConverter
import zombie.Lua.LuaManager
import zombie.characters.BaseCharacterSoundEmitter
import zombie.characters.DummyCharacterSoundEmitter
import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.core.Transaction
import zombie.core.TransactionManager
import zombie.core.network.ByteBufferWriter
import zombie.core.raknet.UdpConnection
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.PacketTypes
import zombie.network.packets.ItemTransactionPacket

/** Real native Lua request sites and real LuaJavaInvoker; no game/world or copied action bodies. */
object NativeTransferRequestsChecks {
    private var calls = 0
    private val sentinel = IllegalStateException("native request sentinel")
    private var lastThrown: Throwable? = null
    private var addFault: String? = null
    private var consistencyCalls = 0

    /** A socket-free transport; packet construction/serialization and manager add stay native. */
    class Connection : UdpConnection(null, 0, 0) {
        lateinit var bytes: ByteBuffer
        var packets = 0
        var onSend: (() -> Unit)? = null

        override fun startPacket(): ByteBufferWriter {
            bytes.clear()
            return ByteBufferWriter(bytes)
        }

        override fun isLimitExceeded(type: PacketTypes.PacketType): Boolean = false

        override fun cancelPacket() = error("native handle fixture unexpectedly cancelled a packet")

        override fun endPacket(priority: Int, reliability: Int, channel: Byte) {
            packets++
            val callback = onSend
            onSend = null
            callback?.invoke()
        }
    }

    @JvmStatic fun useNativeManager(): Boolean = LuaManager.env?.rawget("UseNativeManager") == true

    @JvmStatic
    fun nativeConsistency(): Byte {
        consistencyCalls++
        if (LuaManager.env.rawget("NativeConsistencyFailure") == true) {
            lastThrown = sentinel
            throw sentinel
        }
        return if (LuaManager.env.rawget("NativeConsistencyReject") == true) 1 else 0
    }

    @JvmStatic
    fun afterNativeAdd(transaction: Transaction) {
        val fault = addFault ?: return
        addFault = null
        when (fault) {
            "duplicate" -> TransactionManager.add(transaction)
            "multiple" -> TransactionManager.add(ItemTransactionPacket())
            else -> error("unknown native add fault")
        }
    }

    class Player : IsoPlayer(null) {
        lateinit var probeEmitter: BaseCharacterSoundEmitter

        override fun getEmitter(): BaseCharacterSoundEmitter = probeEmitter

        override fun isPlayerMoving(): Boolean = false
    }

    /** Only the downstream sender is replaced; native Lua extraction and production advice run. */
    @JvmStatic
    fun sender(
        actor: IsoPlayer,
        items: List<InventoryItem>,
        source: ItemContainer,
        destination: ItemContainer,
    ): Byte {
        try {
            if (LuaManager.env.rawget("ProbeWorker") == true) {
                val receipts = LuaManager.env.rawget("Receipts") as KahluaTableImpl
                val receipt = receipts.rawget(1.0) as NativeTransferRequestReceipt
                val action = receipt.getAction()
                val requestItems = receipt.getItems()
                check(receipt.isCurrent(action)) { "native sender lost owner scope" }
                val failure = java.util.concurrent.atomic.AtomicReference<Throwable?>()
                val worker = Thread {
                    try {
                        val alien =
                            NativeTransferRequests.begin(actor, requestItems, source, destination)
                        check(alien == null) { "foreign thread borrowed the Lua owner's frame" }
                        NativeTransferRequests.end(alien, 0, null)
                        check(!receipt.isCurrent(action))
                    } catch (error: Throwable) {
                        failure.set(error)
                    }
                }
                    .apply { isDaemon = true }
                worker.start()
                worker.join(5000)
                check(!worker.isAlive) { "foreign thread gate stalled" }
                failure.get()?.let { throw it }
                check(receipt.isCurrent(action)) { "worker altered owner scope" }
                LuaManager.env.rawset("WorkerDenied", true)
            }
            calls++
            LuaManager.env.rawset("DelegateCalls", calls.toDouble())
            LuaManager.env.rawset("ExtractedItemCount", items.size.toDouble())
            LuaManager.env.rawset("ExtractedFirst", items.firstOrNull())
            LuaManager.env.rawset("ExtractedSecond", items.getOrNull(1))
            val hook = LuaManager.env.rawget("OnNativeDelegate")
            if (hook != null) {
                LuaManager.env.rawset("OnNativeDelegate", null)
                LuaManager.thread.call(hook, emptyArray<Any?>())
            }
            if (LuaManager.env.rawget("ThrowNativeRequest") == true) throw sentinel
            return (LuaManager.env.rawget("NextTransaction") as Double).toInt().toByte()
        } catch (error: Throwable) {
            lastThrown = error
            throw error
        }
    }

    /** Negative provenance input: a real invoker whose Java method is not the native API. */
    @JvmStatic
    fun requestWrapper(
        actor: IsoPlayer,
        items: KahluaTableImpl,
        source: ItemContainer,
        destination: ItemContainer,
    ): Byte = LuaManager.GlobalObject.createItemTransaction(actor, items, source, destination)

    @JvmStatic
    fun rewritePending(enabled: Boolean) {
        val toolkit = LuaManager.env.rawget("PZSurvivorToolkit") as KahluaTableImpl
        val owner = toolkit.rawget("ActionQueueTransferRequests") as KahluaTableImpl
        val pending = owner.rawget("pending") as KahluaTableImpl
        pending.setRewriteTable(if (enabled) LuaManager.platform.newTable() else null)
    }

    @JvmStatic
    fun mutateStart(enabled: Boolean) {
        val prototype = (LuaManager.env.rawget("StockStart") as LuaClosure).prototype
        val old = if (enabled) "microwave" else "request-probe-microwave"
        val index = prototype.constants.indexOf(old)
        check(index >= 0)
        prototype.constants[index] = if (enabled) "request-probe-microwave" else "microwave"
    }

    private fun wovenBoundary() {
        val instrumentation =
            me.zed_0xff.zombie_buddy.Accessor.tryGet<java.lang.instrument.Instrumentation>(
                me.zed_0xff.zombie_buddy.Loader::class.java,
                "g_instrumentation",
                null,
            ) ?: error("Native transfer checks require the ZombieBuddy test javaagent")
        val throwing =
            KahluaTableImpl(
                object : java.util.LinkedHashMap<Any, Any>() {
                    override fun isEmpty(): Boolean = throw sentinel
                },
            )
        GameClient.client = true
        val original = runCatching {
            LuaManager.GlobalObject.createItemTransaction(null, throwing, null, null)
        }
            .exceptionOrNull()
        check(original === sentinel) { "native error control did not reach the input iterator" }
        GameClient.client = false
        val items = LuaManager.platform.newTable() as KahluaTableImpl
        check(LuaManager.GlobalObject.createItemTransaction(null, items, null, null) == 0.toByte())
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            NativeTransferRequestsChecks::class.java.classLoader,
        )
        var captured: ByteArray? = null
        var capturedManager: ByteArray? = null
        var capturedTransaction: ByteArray? = null
        val transformer =
            object : java.lang.instrument.ClassFileTransformer {
                override fun transform(
                    loader: ClassLoader?,
                    name: String?,
                    type: Class<*>?,
                    domain: java.security.ProtectionDomain?,
                    bytes: ByteArray?,
                ): ByteArray? {
                    if (name == "zombie/Lua/LuaManager\$GlobalObject") captured = bytes?.clone()
                    if (name == "zombie/core/TransactionManager") capturedManager = bytes?.clone()
                    if (name == "zombie/core/Transaction") capturedTransaction = bytes?.clone()
                    return null
                }
            }
        instrumentation.addTransformer(transformer, true)
        try {
            instrumentation.retransformClasses(
                LuaManager.GlobalObject::class.java,
                TransactionManager::class.java,
                Transaction::class.java,
            )
        } finally {
            instrumentation.removeTransformer(transformer)
        }
        var enters = 0
        var exits = 0
        net.bytebuddy.jar.asm
            .ClassReader(captured ?: error("native API transform not captured"))
            .accept(
                object : net.bytebuddy.jar.asm.ClassVisitor(net.bytebuddy.jar.asm.Opcodes.ASM9) {
                    override fun visitMethod(
                        access: Int,
                        name: String?,
                        descriptor: String?,
                        signature: String?,
                        exceptions: Array<out String>?,
                    ): net.bytebuddy.jar.asm.MethodVisitor? {
                        if (name != "createItemTransaction") return null
                        return object :
                            net.bytebuddy.jar.asm.MethodVisitor(
                                net.bytebuddy.jar.asm.Opcodes.ASM9,
                            ) {
                            override fun visitMethodInsn(
                                opcode: Int,
                                owner: String?,
                                name: String?,
                                descriptor: String?,
                                isInterface: Boolean,
                            ) {
                                if (
                                    owner ==
                                        "net/alexredby/pztoolkitjavapatches/NativeTransferRequests"
                                ) {
                                    if (name == "begin") enters++
                                    if (name == "end") exits++
                                }
                            }
                        }
                    }
                },
                net.bytebuddy.jar.asm.ClassReader.SKIP_DEBUG or
                    net.bytebuddy.jar.asm.ClassReader.SKIP_FRAMES,
            )
        check(enters == 1 && exits >= 1) {
            "actual native API advice missing or duplicated: $enters/$exits"
        }
        fun calls(bytes: ByteArray?, method: String, helper: String): Int {
            var count = 0
            net.bytebuddy.jar.asm
                .ClassReader(bytes ?: error("native $method transform not captured"))
                .accept(
                    object :
                        net.bytebuddy.jar.asm.ClassVisitor(net.bytebuddy.jar.asm.Opcodes.ASM9) {
                        override fun visitMethod(
                            access: Int,
                            name: String?,
                            descriptor: String?,
                            signature: String?,
                            exceptions: Array<out String>?,
                        ): net.bytebuddy.jar.asm.MethodVisitor? {
                            if (name != method) return null
                            return object :
                                net.bytebuddy.jar.asm.MethodVisitor(
                                    net.bytebuddy.jar.asm.Opcodes.ASM9,
                                ) {
                                override fun visitMethodInsn(
                                    opcode: Int,
                                    owner: String?,
                                    name: String?,
                                    descriptor: String?,
                                    isInterface: Boolean,
                                ) {
                                    if (
                                        owner ==
                                            "net/alexredby/pztoolkitjavapatches/NativeTransferRequestsLogic" &&
                                            name == helper
                                    )
                                        count++
                                }
                            }
                        }
                    },
                    net.bytebuddy.jar.asm.ClassReader.SKIP_DEBUG or
                        net.bytebuddy.jar.asm.ClassReader.SKIP_FRAMES,
                )
            return count
        }
        check(calls(capturedManager, "createItemTransaction", "beginManager") == 1)
        check(calls(capturedManager, "createItemTransaction", "endManager") >= 1)
        check(calls(capturedManager, "add", "added") == 1)
        check(calls(capturedTransaction, "set", "allocated") == 1) {
            "actual native allocation observer missing or duplicated"
        }
        check(
            LuaManager.GlobalObject.createItemTransaction(null, items, null, null) == 0.toByte(),
        ) {
            "woven native SP/off result changed"
        }
        GameClient.client = true
        val failure = runCatching {
            LuaManager.GlobalObject.createItemTransaction(null, throwing, null, null)
        }
            .exceptionOrNull()
        check(failure === sentinel) {
            "woven native API swallowed/replaced its original iterator throwable"
        }
        println("NATIVE_TRANSFER_REQUESTS_WOVEN_PASS enter=$enters exit=$exits")
    }

    private fun nativeHandleChecks(unsafe: Unsafe, actor: IsoPlayer, source: ItemContainer) {
        fun field(type: Class<*>, name: String) =
            type.getDeclaredField(name).apply { isAccessible = true }
        val nativeQueue =
            field(TransactionManager::class.java, "transactions").get(null)
                as ConcurrentLinkedQueue<Transaction>
        val nextId = field(Transaction::class.java, "lastId")
        val savedId = nextId.getByte(null)
        val savedConnection = GameClient.connection
        val savedDestination = LuaManager.env.rawget("Destination")
        val owner =
            (LuaManager.env.rawget("PZSurvivorToolkit") as KahluaTableImpl).rawget(
                "ActionQueueTransferRequests",
            ) as KahluaTableImpl
        val savedObserver = owner.rawget("observe")
        val secondActor = unsafe.allocateInstance(Player::class.java) as Player
        field(zombie.iso.IsoObject::class.java, "ecsComponentMap")
            .set(actor, java.util.HashMap<Any, Any>())
        field(zombie.iso.IsoObject::class.java, "ecsComponentMap")
            .set(secondActor, java.util.HashMap<Any, Any>())
        secondActor.probeEmitter = DummyCharacterSoundEmitter(secondActor)
        secondActor.onlineId = 32
        val secondSource = ItemContainer("inventory", null, secondActor)
        field(IsoGameCharacter::class.java, "inventory").set(secondActor, secondSource)
        val destination = ItemContainer("crate", null, secondActor)
        val item = LuaManager.env.rawget("FirstItem") as InventoryItem
        fun connection(): Connection =
            (unsafe.allocateInstance(Connection::class.java) as Connection).apply {
                bytes = ByteBuffer.allocate(4096)
                GameClient.connection = this
                nativeQueue.clear()
            }
        fun start(id: Int, tag: String): Pair<KahluaTableImpl, NativeTransferRequestReceipt> {
            nextId.setByte(null, id.toByte())
            execute(
                "resetEvents();NativeAction=makeAction('$tag');selectAction(NativeAction);StockStart(NativeAction)",
                "native-handle-$tag",
            )
            val action = LuaManager.env.rawget("NativeAction") as KahluaTableImpl
            val receipts = LuaManager.env.rawget("Receipts") as KahluaTableImpl
            val receipt = receipts.rawget(1.0) as NativeTransferRequestReceipt
            check(receipts.rawget(2.0) === receipt) { "$tag lost the original request receipt" }
            return action to receipt
        }
        fun matches(value: Pair<KahluaTableImpl, NativeTransferRequestReceipt>, id: Int): Boolean =
            value.second.matchesTransaction(value.first, id)
        try {
            LuaManager.env.rawset("UseNativeManager", true)
            LuaManager.env.rawset("Destination", destination)
            execute(
                "PZSurvivorToolkit.ActionQueueTransferRequests.observe=function(r) " +
                    "assert(r:isCurrent(r:getAction()));Events[#Events+1]=r:getPhase();Receipts[#Receipts+1]=r;" +
                    "if r:getPhase()=='before' and NativeBefore then NativeBefore(r)end end",
                "ActionQueueTransferRequests.lua",
            )
            var wire = connection()
            val preflight = runCatching {
                ItemTransactionPacket()
                    .set(
                        actor,
                        listOf(item),
                        source,
                        destination,
                        null,
                        zombie.iso.IsoDirections.N,
                        0f,
                        0f,
                        0f,
                    )
            }
                .exceptionOrNull()
            check(preflight == null) {
                "native packet fixture cannot set its endpoints: $preflight"
            }
            wire = connection()
            val consistencyBefore = consistencyCalls
            val positive = start(41, "positive")
            check(wire.packets == 1 && nativeQueue.size == 1) {
                "original native create/write/add did not run once: packets=${wire.packets} queued=${nativeQueue.size} result=${positive.first.rawget("transactionId")} stubCalls=$calls consistencyCalls=${consistencyCalls-consistencyBefore}"
            }
            check(positive.second.hasNativeHandle() && matches(positive, 41)) {
                "exact native packet did not produce a handle"
            }
            check(matches(positive, 41) && !matches(positive, 42)) {
                "handle match changed identity or consumed evidence"
            }
            check(
                !positive.second.matchesTransaction(
                    LuaManager.platform.newTable() as KahluaTableImpl,
                    41,
                ),
            )
            check(!positive.second.isWireAmbiguous())
            val originalEnv = LuaManager.env
            val originalThread = LuaManager.thread
            val replacedEnvironmentMatches =
                try {
                    LuaManager.env = LuaManager.platform.newEnvironment()
                    matches(positive, 41)
                } finally {
                    LuaManager.env = originalEnv
                }
            val replacedVmMatches =
                try {
                    LuaManager.thread =
                        KahluaThread(LuaManager.platform, originalEnv).apply {
                            debugOwnerThread = Thread.currentThread()
                        }
                    matches(positive, 41)
                } finally {
                    LuaManager.thread = originalThread
                }
            println(
                "NATIVE_TRANSFER_HANDLE_VM_PROBE environment_match=$replacedEnvironmentMatches vm_match=$replacedVmMatches",
            )
            val firstPacket = nativeQueue.single()
            val packetId = field(Transaction::class.java, "id")
            val packetEntries =
                field(Transaction::class.java, "entries").get(firstPacket) as List<*>
            val entry = packetEntries.single()!!
            val entrySource =
                entry.javaClass.getField("sourceId").get(entry) as zombie.network.fields.ContainerID
            val entryDestination =
                entry.javaClass.getField("destinationId").get(entry)
                    as zombie.network.fields.ContainerID
            check(
                packetId.getByte(firstPacket) == 41.toByte() &&
                    entry.javaClass.getField("itemId").get(entry) == item.getID(),
            )
            check(
                entrySource.getContainer() === source &&
                    entryDestination.getContainer() === destination,
            )
            val playerId =
                field(Transaction::class.java, "playerId").get(firstPacket)
                    as zombie.network.fields.character.PlayerID
            check(playerId.getPlayer() === actor) {
                "captured packet owner differs from native input"
            }
            val collision = ItemTransactionPacket()
            packetId.setByte(collision, 41)
            TransactionManager.add(collision)
            check(!matches(positive, 41)) {
                "a live same-byte collision retained authoritative correlation"
            }
            nativeQueue.remove(collision)
            check(!matches(positive, 41)) {
                "removing a transient byte collision revived historical correlation"
            }
            nativeQueue.clear()
            check(!matches(positive, 41)) { "removed native packet retained a current handle" }
            val replacement = ItemTransactionPacket()
            packetId.setByte(replacement, 41)
            TransactionManager.add(replacement)
            check(!matches(positive, 41)) { "same-byte replacement revived an old native handle" }

            wire = connection()
            val continuationStart = start(60, "continuation-start")
            val savedRemove = LuaManager.env.rawget("removeItemTransaction")
            try {
                LuaManager.env.rawset("removeItemTransaction", null)
                LuaManager.exposer.exposeGlobalClassFunction(
                    LuaManager.env,
                    LuaManager.GlobalObject::class.java,
                    LuaManager.GlobalObject::class
                        .java
                        .getMethod(
                            "removeItemTransaction",
                            Byte::class.javaPrimitiveType,
                            Boolean::class.javaPrimitiveType,
                        ),
                    "removeItemTransaction",
                )
                check(LuaManager.env.rawget("removeItemTransaction") is LuaJavaInvoker)
                nextId.setByte(null, 61)
                execute(
                    "resetEvents();NativeAction.queueList={{items={FirstItem},time=1},{items={SecondItem},time=2}};StockPerform(NativeAction)",
                    "native-handle-continuation",
                )
                val continuationReceipt =
                    (LuaManager.env.rawget("Receipts") as KahluaTableImpl).rawget(1.0)
                        as NativeTransferRequestReceipt
                check(
                    continuationReceipt.getBoundary() == "continuation" &&
                        continuationReceipt.hasNativeHandle(),
                )
                check(
                    continuationReceipt.matchesTransaction(continuationStart.first, 61) &&
                        !matches(continuationStart, 60),
                )
                check(
                    wire.packets == 2 &&
                        nativeQueue.size == 1 &&
                        packetId.getByte(nativeQueue.single()) == 61.toByte(),
                ) {
                    "native continuation did not retire its previous packet and add exactly one new packet: packets=${wire.packets} queue=${nativeQueue.size} ids=${nativeQueue.map { packetId.getByte(it) }}"
                }
            } finally {
                LuaManager.env.rawset("removeItemTransaction", savedRemove)
            }

            wire = connection()
            val independent = start(42, "independent")
            nextId.setByte(null, 43)
            TransactionManager.createItemTransaction(
                secondActor,
                listOf(item),
                secondSource,
                destination,
            )
            check(matches(independent, 42)) {
                "a different actor invalidated an independent cursor"
            }
            nextId.setByte(null, 44)
            TransactionManager.createItemTransaction(actor, listOf(item), source, destination)
            check(!matches(independent, 42)) {
                "unknown direct manager call retained the previous actor cursor"
            }
            val directSet = start(54, "direct-set")
            ItemTransactionPacket()
                .set(
                    actor,
                    listOf(item),
                    source,
                    destination,
                    null,
                    zombie.iso.IsoDirections.N,
                    0f,
                    0f,
                    0f,
                )
            check(!matches(directSet, 54)) {
                "direct native allocation retained the previous actor cursor"
            }
            val prepared = ItemTransactionPacket()
            prepared.set(
                actor,
                listOf(item),
                source,
                destination,
                null,
                zombie.iso.IsoDirections.N,
                0f,
                0f,
                0f,
            )
            val directAdd = start(57, "direct-add")
            TransactionManager.add(prepared)
            check(!matches(directAdd, 57)) {
                "direct native add retained the previous actor cursor"
            }
            val foreign = start(45, "foreign-global")
            nextId.setByte(null, 46)
            LuaManager.GlobalObject.createItemTransaction(
                actor,
                LuaManager.platform.newTable() as KahluaTableImpl,
                source,
                destination,
            )
            check(!matches(foreign, 45)) { "unsupported Global request retained a previous cursor" }

            connection()
            val reusedOld = start(47, "reuse-old")
            nativeQueue.clear()
            val reusedNew = start(47, "reuse-new")
            check(
                !matches(reusedOld, 47) &&
                    !matches(reusedNew, 47) &&
                    reusedNew.second.isWireAmbiguous(),
            ) {
                "byte reuse granted authoritative native correlation"
            }
            // A late result changes the real manager's replacement object by byte;
            // it must not make either receipt authoritative again.
            val late = ItemTransactionPacket()
            packetId.setByte(late, 47)
            field(Transaction::class.java, "state").set(late, Transaction.TransactionState.Done)
            TransactionManager.instance.setStateFromPacket(late)
            TransactionManager.instance.setStateFromPacket(late)
            check(!matches(reusedOld, 47) && !matches(reusedNew, 47)) {
                "late duplicate results revived reused-byte evidence"
            }
            connection()
            val disconnected = start(48, "connection-old")
            connection()
            check(!matches(disconnected, 48)) { "connection replacement retained a handle" }
            val warmConnection = connection()
            start(62, "connection-warm")
            wire = connection()
            wire.onSend = { GameClient.connection = warmConnection }
            val switchedDuringSend = start(62, "connection-during-send")
            check(!matches(switchedDuringSend, 62)) {
                "a connection change during send borrowed another connection's one-use byte history"
            }
            val observerConnection = connection()
            // Mint on a fresh connection, then switch inside the source observer.
            connection()
            LuaManager.env.rawset(
                "NativeBefore",
                se.krka.kahlua.vm.JavaFunction { _, _ ->
                    GameClient.connection = observerConnection
                    0
                },
            )
            val switchedInObserver = start(63, "connection-in-observer")
            LuaManager.env.rawset("NativeBefore", null)
            check(!matches(switchedInObserver, 63)) {
                "a before-observer connection switch changed the minted request connection"
            }

            for (mode in listOf("duplicate", "multiple")) {
                connection()
                addFault = mode
                val ambiguous = start(49, mode)
                check(!matches(ambiguous, 49)) { "$mode native adds granted one exact handle" }
            }
            wire = connection()
            wire.onSend = {
                TransactionManager.createItemTransaction(actor, listOf(item), source, destination)
            }
            val nested = start(50, "nested-manager")
            check(wire.packets == 2 && nested.second.hasNestedRequest() && !matches(nested, 50)) {
                "nested native manager call borrowed the outer handle"
            }
            wire = connection()
            wire.onSend = {
                ItemTransactionPacket()
                    .set(
                        actor,
                        listOf(item),
                        source,
                        destination,
                        null,
                        zombie.iso.IsoDirections.N,
                        0f,
                        0f,
                        0f,
                    )
            }
            val extraAllocation = start(58, "extra-allocation")
            check(wire.packets == 1 && nativeQueue.size == 1 && !matches(extraAllocation, 58)) {
                "an extra native allocation inside the manager retained a single-object handle"
            }

            connection()
            LuaManager.env.rawset("NativeConsistencyReject", true)
            val rejected = start(51, "zero")
            check(
                rejected.first.rawget("transactionId") == 0.0 && !rejected.second.hasNativeHandle(),
            )
            LuaManager.env.rawset("NativeConsistencyReject", false)
            wire = connection()
            wire.onSend = { throw sentinel }
            val failedSend = start(52, "send-failed")
            check(
                failedSend.first.rawget("transactionId") == 0.0 &&
                    !failedSend.second.hasNativeHandle() &&
                    nativeQueue.isEmpty(),
            ) {
                "failed native send fabricated a submitted native handle"
            }
            val afterFailedSend = start(52, "send-failed-reuse")
            check(!matches(afterFailedSend, 52) && afterFailedSend.second.isWireAmbiguous()) {
                "a sent allocation lost to failure was revived by byte reuse"
            }
            connection()
            LuaManager.env.rawset("Destination", savedDestination)
            val failedSet = start(53, "set-failed")
            check(
                failedSet.first.rawget("transactionId") == 0.0 &&
                    !failedSet.second.hasNativeHandle() &&
                    nativeQueue.isEmpty(),
            )
            LuaManager.env.rawset("Destination", destination)
            val afterFailedSet = start(53, "after-set-failed")
            check(matches(afterFailedSet, 53)) {
                "a set failure before ID allocation fabricated a consumed byte"
            }

            connection()
            LuaManager.env.rawset("NativeConsistencyFailure", true)
            val failure = runCatching {
                TransactionManager.createItemTransaction(actor, listOf(item), source, destination)
            }
                .exceptionOrNull()
            check(failure === sentinel) {
                "manager advice replaced an original native consistency throwable"
            }
            execute(
                "resetEvents();local control=makeAction('throw-control');" +
                    "PZSurvivorToolkit.ActionQueueTransferRequests.pending[Actor]=nil;" +
                    "local controlOk,controlError=pcall(StockStart,control);" +
                    "NativeAction=makeAction('throw');selectAction(NativeAction);" +
                    "local ok,err=pcall(StockStart,NativeAction);" +
                    "assert(ok==controlOk and tostring(err)==tostring(controlError) and NativeAction.transactionId==control.transactionId);" +
                    "assert(table.concat(Events,',')=='before,failed' and not Receipts[1]:hasNativeHandle())",
                "native-handle-original-throwable",
            )
            check(lastThrown === sentinel)
            LuaManager.env.rawset("NativeConsistencyFailure", false)
            LuaManager.env.rawset("NativeBefore", null)
            check(!replacedEnvironmentMatches && !replacedVmMatches) {
                "replaced Lua environment/VM retained native correlation"
            }
            val nativeBenchmark =
                execute(
                    "local a=makeAction('native-request-cost');return function(enabled) " +
                        "PZSurvivorToolkit.ActionQueueTransferRequests.pending[Actor]=enabled and a or nil;StockStart(a)end",
                    "native-request-cost-fixture",
                )
                    as LuaClosure
            fun nativeSample(enabled: Boolean): Long {
                // Connection/queue/byte and diagnostic table preparation are not timed.
                connection()
                nextId.setByte(null, 71)
                LuaManager.env.rawset("Events", LuaManager.platform.newTable())
                LuaManager.env.rawset("Receipts", LuaManager.platform.newTable())
                val started = System.nanoTime()
                LuaManager.thread.call(nativeBenchmark, arrayOf<Any?>(enabled))
                return System.nanoTime() - started
            }
            repeat(300) {
                nativeSample(false)
                nativeSample(true)
            }
            val nativeInactive = LongArray(600)
            val nativeObserved = LongArray(600)
            for (index in nativeInactive.indices) {
                if (index % 2 == 0) {
                    nativeInactive[index] = nativeSample(false)
                    nativeObserved[index] = nativeSample(true)
                } else {
                    nativeObserved[index] = nativeSample(true)
                    nativeInactive[index] = nativeSample(false)
                }
            }
            nativeInactive.sort()
            nativeObserved.sort()
            println(
                "NATIVE_TRANSFER_MANAGER_COST inactive_median_ns=${nativeInactive[300]} observed_median_ns=${nativeObserved[300]} observed_p95_ns=${nativeObserved[569]} samples=600 original_manager=true fake_socket=true qualified_live=false",
            )
            check(nativeObserved[569] <= 1_000_000) {
                "native manager fixture p95 exceeded frozen 1 ms CPU gate"
            }
            check(nativeObserved[300] - nativeInactive[300] <= 250_000) {
                "native manager fixture median overhead exceeded frozen 0.25 ms CPU gate"
            }
            GameClient.client = false
            execute(
                "resetEvents();NativeAction=makeAction('off');selectAction(NativeAction);StockStart(NativeAction);" +
                    "assert(NativeAction.transactionId==0 and #Receipts==0)",
                "native-handle-sp-off",
            )
            println("NATIVE_TRANSFER_HANDLES_CHECKS_PASS original_manager=true socket_free=true")
        } finally {
            addFault = null
            GameClient.client = true
            LuaManager.env.rawset("UseNativeManager", false)
            LuaManager.env.rawset("NativeConsistencyReject", false)
            LuaManager.env.rawset("NativeConsistencyFailure", false)
            LuaManager.env.rawset("Destination", savedDestination)
            owner.rawset("observe", savedObserver)
            GameClient.connection = savedConnection
            nativeQueue.clear()
            nextId.setByte(null, savedId)
        }
    }

    private fun filename(prototype: Prototype, path: String) {
        prototype.filename = path
        prototype.prototypes.forEach { filename(it, path) }
    }

    private fun execute(text: String, path: String): Any? {
        val closure = LuaCompiler.loadstring(text, path, LuaManager.env)
        filename(closure.prototype, path)
        val result = LuaManager.thread.pcall(closure, emptyArray<Any?>())
        check(result[0] == true) { path + ": " + result.drop(1).joinToString("\n") }
        return result.getOrNull(1)
    }

    @JvmStatic
    fun main(args: Array<String>) {
        val game = if (args.isNotEmpty()) Path.of(args[0]) else Path.of("").toAbsolutePath()
        val native = game.resolve("media/lua/client/TimedActions/ISInventoryTransferAction.lua")
        check(Files.isRegularFile(native)) { "Pass the actual game Java folder or run in it" }
        zombie.ZomboidFileSystem.instance.setCacheDir(
            System.getProperty("pz.test.cache")
                ?: Files.createTempDirectory("transfer-requests-checks").toString(),
        )
        LuaManager.platform = se.krka.kahlua.j2se.J2SEPlatform()
        LuaManager.env = LuaManager.platform.newEnvironment()
        val converters = KahluaConverterManager()
        KahluaNumberConverter.install(converters)
        LuaManager.exposer = LuaManager.Exposer(converters, LuaManager.platform, LuaManager.env)
        val exposed =
            listOf(
                InventoryItem::class.java,
                ItemContainer::class.java,
                IsoGameCharacter::class.java,
                IsoPlayer::class.java,
                Player::class.java,
                BaseCharacterSoundEmitter::class.java,
                DummyCharacterSoundEmitter::class.java,
            )
        exposed.forEach { LuaManager.exposer.setExposed(it) }
        exposed.forEach {
            LuaManager.exposer.exposeLikeJava(it, LuaManager.env)
            LuaManager.exposer.typeMap[it.simpleName] = it
        }
        LuaManager.exposer.exposeGlobalClassFunction(
            LuaManager.env,
            LuaManager.GlobalObject::class.java,
            LuaManager.GlobalObject::class
                .java
                .getMethod("instof", Any::class.java, String::class.java),
            "instanceof",
        )
        LuaManager.exposer.exposeGlobalClassFunction(
            LuaManager.env,
            LuaManager.GlobalObject::class.java,
            LuaManager.GlobalObject::class
                .java
                .getMethod(
                    "createItemTransaction",
                    IsoPlayer::class.java,
                    KahluaTableImpl::class.java,
                    ItemContainer::class.java,
                    ItemContainer::class.java,
                ),
            "createItemTransaction",
        )
        check(LuaManager.env.rawget("createItemTransaction") is LuaJavaInvoker)
        LuaManager.exposer.exposeGlobalClassFunction(
            LuaManager.env,
            NativeTransferRequestsChecks::class.java,
            NativeTransferRequestsChecks::class
                .java
                .getMethod(
                    "requestWrapper",
                    IsoPlayer::class.java,
                    KahluaTableImpl::class.java,
                    ItemContainer::class.java,
                    ItemContainer::class.java,
                ),
            "unknownJavaRequest",
        )
        for (name in listOf("rewritePending", "mutateStart")) {
            LuaManager.exposer.exposeGlobalClassFunction(
                LuaManager.env,
                NativeTransferRequestsChecks::class.java,
                NativeTransferRequestsChecks::class
                    .java
                    .getMethod(name, Boolean::class.javaPrimitiveType),
                name,
            )
        }

        LuaManager.thread =
            KahluaThread(LuaManager.platform, LuaManager.env).apply {
                debugOwnerThread = Thread.currentThread()
            }
        zombie.ui.UIManager.defaultthread = LuaManager.thread
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        GameClient.client = true
        GameServer.server = false
        // Smoke-test and install the production native API advice before the
        // isolated downstream sender stub. No positive path calls begin/end manually.
        wovenBoundary()
        val senderPackage = NativeTransferSenderStub::class.java.packageName
        check(senderPackage == "net.alexredby.native_transfer_request_fixture")
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches(
            senderPackage,
            NativeTransferRequestsChecks::class.java.classLoader,
        )
        val unsafe =
            Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null)
                as Unsafe
        val actor = unsafe.allocateInstance(Player::class.java) as Player
        actor.probeEmitter = DummyCharacterSoundEmitter(actor)
        val source = ItemContainer("inventory", null, actor)
        val destination = ItemContainer("crate", null, null)
        IsoGameCharacter::class
            .java
            .getDeclaredField("inventory")
            .apply { isAccessible = true }
            .set(actor, source)
        fun item(id: Int): InventoryItem {
            val value = unsafe.allocateInstance(InventoryItem::class.java) as InventoryItem
            value.setID(id)
            value.setContainer(source)
            for ((name, text) in
                mapOf(
                    "module" to "Base",
                    "type" to "RequestProbe",
                    "fullType" to "Base.RequestProbe",
                )) InventoryItem::class
                .java
                .getDeclaredField(name)
                .apply { isAccessible = true }
                .set(value, text)
            return value
        }
        LuaManager.env.rawset("Actor", actor)
        LuaManager.env.rawset("Source", source)
        LuaManager.env.rawset("Destination", destination)
        LuaManager.env.rawset("FirstItem", item(701))
        LuaManager.env.rawset("SecondItem", item(702))
        execute(
            """
            require=function()end
            isClient=function()return true end
            ISBaseTimedAction={derive=function(_,name)local c={Type=name};c.__index=c;return c end,
                perform=function()error('fixture must retain a continuation')end}
            ISInventoryPage={}
            """
                .trimIndent(),
            "request-check-bootstrap",
        )
        execute(Files.readString(native), native.toString())
        val classTable = LuaManager.env.rawget("ISInventoryTransferAction") as KahluaTableImpl
        val start = classTable.rawget("start") as LuaClosure
        val perform = classTable.rawget("perform") as LuaClosure
        val logic = Class.forName("net.alexredby.pztoolkitjavapatches.NativeTransferRequestsLogic")
        val target = logic.getField("INSTANCE").get(null)
        val fingerprint = logic.declaredMethods.single { it.name.startsWith("fingerprint") }
        println(
            "Native transfer prototype pins: start=" +
                fingerprint.invoke(target, start.prototype) +
                " continuation=" +
                fingerprint.invoke(target, perform.prototype),
        )
        LuaManager.env.rawset("StockStart", start)
        LuaManager.env.rawset("StockPerform", perform)
        execute(
            """
            NextTransaction=-17;DelegateCalls=0
            PZSurvivorToolkit={ActionQueueTransferRequests={pending={}}}
            function noop()end
            function makeAction(tag)
                local a=setmetatable({character=Actor,item=FirstItem,srcContainer=Source,destContainer=Destination,
                    action={setTime=noop,setWaitForFinished=noop,reset=noop},maxTime=1,transactionId=0,
                    queueList={{items={FirstItem},time=1}},tag=tag},ISInventoryTransferAction)
                a.isAlreadyTransferred=function()return false end
                a.checkQueueList=noop;a.startActionAnim=noop;a.getTransferStartSoundName=function()end
                a.playSourceContainerOpenSound=noop;a.playDestContainerOpenSound=noop
                a.playTransferCompleteSound=noop;a.resetJobDelta=noop;a.isValid=function()return true end
                return a
            end
            function selectAction(a)
                PZSurvivorToolkit.ActionQueueTransferRequests.pending[Actor]=a
            end
            function resetEvents() Events={};Receipts={};ExpectedAction=nil;ObserverStage=nil;ThrowNativeRequest=false end
            removeItemTransaction=function(id,cancel)
                assert(cancel==false);RemovedTransaction=id
            end
            resetEvents()
            """
                .trimIndent(),
            "request-check-fixture",
        )
        execute(
            """
            PZSurvivorToolkit.ActionQueueTransferRequests.observe=function(r)
                ObserverStage='identity';local a=r:getAction()
                assert(a==ExpectedAction and r:getActor()==Actor and r:getSource()==Source and r:getDestination()==Destination)
                ObserverStage='items/boundary';assert(r:getItems()==ExpectedItems and r:getBoundary()==ExpectedBoundary)
                ObserverStage='current';assert(r:isCurrent(a) and not r:isCurrent({}))
                local wrong,first,again=r:claim({}),r:claim(a),r:claim(a)
                ObserverStage='claim:'..r:getPhase()..':'..tostring(wrong)..':'..tostring(first)..':'..tostring(again)
                assert(not wrong and first and not again,'claim must be once per phase')
                Events[#Events+1]=r:getPhase()
                Receipts[#Receipts+1]=r
                if r:getPhase()=='before' then assert(r:getTransaction()==0)
                elseif r:getPhase()=='submitted' then assert(r:getTransaction()==NextTransaction) end
            end
            """
                .trimIndent(),
            "ActionQueueTransferRequests.lua",
        )
        NativeTransferRequests.prepareLibrary(
            "media/lua/client/PZSurvivorToolkit/ActionQueueTransferRequests.lua",
        )
        check(LuaManager.exposer.isExposed(NativeTransferRequestReceipt::class.java)) {
            "request library was not prepared before gameplay"
        }
        execute(
            """
            local a=makeAction('start');selectAction(a)
            ExpectedAction=a;ExpectedItems=a.queueList[1].items;ExpectedBoundary='start'
            local n=DelegateCalls;StockStart(a)
            assert(DelegateCalls==n+1 and a.transactionId==-17 and a.started==true,'native start delegate/result changed')
            assert(table.concat(Events,',')=='before,submitted' and Receipts[1]==Receipts[2],
                'request phases: '..table.concat(Events,',')..'; observer: '..tostring(ObserverStage))
            assert(not Receipts[1]:isCurrent(a) and not Receipts[1]:claim(a))
            local old=Receipts[1];resetEvents()
            ExpectedAction=a;ExpectedItems=a.queueList[1].items;ExpectedBoundary='start';StockStart(a)
            assert(a.transactionId==-17 and old~=Receipts[1] and not old:isCurrent(a),'byte reuse must not revive an old receipt')
            resetEvents()
            a=makeAction('continuation');a.started=true;a.transactionId=9
            a.queueList={{items={FirstItem},time=1},{items={SecondItem},time=2}}
            selectAction(a);ExpectedAction=a;ExpectedItems=a.queueList[2].items;ExpectedBoundary='continuation'
            n=DelegateCalls;StockPerform(a)
            assert(DelegateCalls==n+1 and RemovedTransaction==9 and a.transactionId==-17 and a.item==SecondItem)
            assert(table.concat(Events,',')=='before,submitted' and Receipts[1]==Receipts[2],
                'request phases: '..table.concat(Events,',')..'; observer: '..tostring(ObserverStage))
            assert(not Receipts[1]:isCurrent(a))
            resetEvents();ThrowNativeRequest=true
            local control=makeAction('failed-control')
            PZSurvivorToolkit.ActionQueueTransferRequests.pending[Actor]=nil
            local controlOk,controlErr=pcall(StockStart,control)
            a=makeAction('failed');selectAction(a)
            ExpectedAction=a;ExpectedItems=a.queueList[1].items;ExpectedBoundary='start'
            n=DelegateCalls
            local ok,err=pcall(StockStart,a)
            assert(ok==controlOk and tostring(err)==tostring(controlErr) and DelegateCalls==n+1,
                'bridge changed native invoker exception semantics: '..tostring(ok)..':'..tostring(err)..' control='..tostring(controlOk)..':'..tostring(controlErr)..' calls='..tostring(DelegateCalls)..' n='..tostring(n))
            assert(a.transactionId==control.transactionId and table.concat(Events,',')=='before,failed' and Receipts[1]==Receipts[2])
            assert(not Receipts[1]:isCurrent(a));ThrowNativeRequest=false
            """
                .trimIndent(),
            "request-positive-checks",
        )
        check(lastThrown === sentinel) { "native delegate throwable identity changed" }
        execute(
            """
            ForeignCall=function(a)return createItemTransaction(a.character,a.queueList[1].items,a.srcContainer,a.destContainer)end
            """
                .trimIndent(),
            "ISInventoryTransferAction.lua",
        )
        execute(
            """
            resetEvents();local a=makeAction('foreign');selectAction(a)
            local n=DelegateCalls;assert(ForeignCall(a)==-17 and DelegateCalls==n+1 and #Events==0)
            local foreign=setmetatable({},{__index=_G})
            setfenv(StockStart,foreign);n=DelegateCalls;StockStart(a);setfenv(StockStart,_G)
            assert(DelegateCalls==n+1 and #Events==0,'foreign owning environment must not grant a receipt')
            local observer=PZSurvivorToolkit.ActionQueueTransferRequests.observe
            PZSurvivorToolkit.ActionQueueTransferRequests.observe=ForeignCall
            n=DelegateCalls;StockStart(a)
            assert(DelegateCalls==n+1 and #Events==0,'foreign observer source must stay uncalled')
            PZSurvivorToolkit.ActionQueueTransferRequests.observe=observer
            local native=createItemTransaction
            createItemTransaction=unknownJavaRequest
            n=DelegateCalls;StockStart(a);createItemTransaction=native
            assert(DelegateCalls==n+1 and #Events==0,'unknown Java wrapper invoker granted native provenance')
            assert(createItemTransaction(Actor,{FirstItem,'not an item',SecondItem},Source,Destination)==-17)
            assert(ExtractedItemCount==2 and ExtractedFirst==FirstItem and ExtractedSecond==SecondItem,
                'actual GlobalObject must extract Java inventory items before the downstream sender')
            createItemTransaction=function(...)return native(...)end
            n=DelegateCalls;StockStart(a);createItemTransaction=native
            assert(DelegateCalls==n+1 and #Events==0,'Lua API wrapper must not satisfy direct native caller proof')
            resetEvents();a=makeAction('outer');selectAction(a)
            ExpectedAction=a;ExpectedItems=a.queueList[1].items;ExpectedBoundary='start'
            OnNativeDelegate=function()
                local outer=Receipts[1]
                OnNativeDelegate=function()
                    assert(not outer:isCurrent(a) and not outer:claim(a),'foreign nested request must mask its outer receipt')
                end
                assert(ForeignCall(a)==-17)
                assert(outer:isCurrent(a),'nested request must restore the outer scope')
            end
            n=DelegateCalls;StockStart(a)
            assert(DelegateCalls==n+2 and table.concat(Events,',')=='before,submitted')
            assert(not Receipts[1]:isCurrent(a))
            assert(Receipts[1]:hasNestedRequest(),'nested native request was not recorded as ambiguous')
            resetEvents();a=makeAction('worker');selectAction(a)
            ExpectedAction=a;ExpectedItems=a.queueList[1].items;ExpectedBoundary='start';ProbeWorker=true
            StockStart(a);ProbeWorker=false
            assert(WorkerDenied==true and table.concat(Events,',')=='before,submitted')
            resetEvents();a=makeAction('rewrite');selectAction(a);rewritePending(true)
            n=DelegateCalls;StockStart(a);rewritePending(false)
            assert(DelegateCalls==n+1 and #Events==0,'rewritten binding table granted own-field provenance')
            resetEvents();a=makeAction('mutated-prototype');selectAction(a);mutateStart(true)
            n=DelegateCalls;StockStart(a);mutateStart(false)
            assert(DelegateCalls==n+1 and #Events==0,'cached source identity hid changed prototype contents')
            NativeTransferRequestsChecksPassed=true
            """
                .trimIndent(),
            "request-negative-and-nested-checks",
        )
        check(LuaManager.env.rawget("NativeTransferRequestsChecksPassed") == true)
        val single = LuaManager.env.rawget("createItemTransaction") as LuaJavaInvoker
        LuaManager.env.rawset(
            "createItemTransaction",
            se.krka.kahlua.integration.expose.MultiLuaJavaInvoker().apply { addInvoker(single) },
        )
        execute(
            "resetEvents();local a=makeAction('multi');selectAction(a);ExpectedAction=a;ExpectedItems=a.queueList[1].items;ExpectedBoundary='start';StockStart(a);assert(table.concat(Events,',')=='before,submitted','canonical multi invoker lost native evidence')",
            "request-multi-invoker",
        )
        LuaManager.env.rawset(
            "createItemTransaction",
            se.krka.kahlua.integration.expose.MultiLuaJavaInvoker().apply {
                addInvoker(single)
                addInvoker(LuaManager.env.rawget("unknownJavaRequest") as LuaJavaInvoker)
            },
        )
        execute(
            """
            resetEvents();local a=makeAction('unknown-multi-control')
            PZSurvivorToolkit.ActionQueueTransferRequests.pending[Actor]=nil
            local n=DelegateCalls;local controlOk,controlErr=pcall(StockStart,a);local count=DelegateCalls-n
            a=makeAction('unknown-multi');selectAction(a)
            n=DelegateCalls;local ok,err=pcall(StockStart,a)
            assert(ok==controlOk and tostring(err)==tostring(controlErr) and DelegateCalls-n==count and count<=1,
                'multi invoker gate changed original delegate/result semantics')
            assert(#Events==0,'multi invoker with foreign member granted native provenance')
            """
                .trimIndent(),
            "request-unknown-multi-invoker",
        )
        LuaManager.env.rawset("createItemTransaction", single)
        nativeHandleChecks(unsafe, actor, source)

        // Run the real shared Lua owner and source/effect readers at those same
        // native boundaries. Only the downstream Java sender is stubbed.
        val project = Path.of(System.getProperty("pz.test.project", "."))
        LuaManager.env.rawset(
            "getFilenameOfClosure",
            se.krka.kahlua.vm.JavaFunction { frame, _ ->
                frame.push((frame.get(0) as? LuaClosure)?.prototype?.filename)
                1
            },
        )
        LuaManager.env.rawset(
            "RequestProof",
            execute(
                Files.readString(
                    project.resolve(
                        "PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua",
                    ),
                ),
                "SourceProof.lua",
            ),
        )
        LuaManager.env.rawset(
            "RequestOutcome",
            execute(
                Files.readString(
                    project.resolve(
                        "PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ActionQueueTransferOutcome.lua",
                    ),
                ),
                "ActionQueueTransferOutcome.lua",
            ),
        )
        execute(
            "require=function(name)assert(name=='PZSurvivorToolkit/SourceProof');return RequestProof end",
            "request-owner-loader",
        )
        execute(
            Files.readString(
                project.resolve(
                    "PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueTransferRequests.lua",
                ),
            ),
            "ActionQueueTransferRequests.lua",
        )
        source.items.add(LuaManager.env.rawget("FirstItem") as InventoryItem)
        source.items.add(LuaManager.env.rawget("SecondItem") as InventoryItem)
        execute(
            """
            function requestOwnerGuard(action) return action==OwnerAction end
            function requestOwnerBefore(action,receipt)
                OwnerBefore=(OwnerBefore or 0)+1
                local item=action.item
                local exact=RequestOutcome.atSource(action,{actor=Actor,source=Source,destination=Destination,
                    id=item:getID(),fullType=item:getFullType()})
                local value={receipt=receipt,exact=exact,phase='before',id=item:getID()}
                if not RequestTiming then OwnerEvidence[#OwnerEvidence+1]=value end
                if OwnerThrow=='before' then error('owner-before probe')end
                return value
            end
            function requestOwnerAfter(action,value,receipt)
                OwnerAfter=(OwnerAfter or 0)+1
                assert(value.receipt==receipt and receipt:isCurrent(action))
                value.phase,value.transaction=receipt:getPhase(),receipt:getTransaction()
                if OwnerThrow=='after' then error('owner-after probe')end
            end
            """
                .trimIndent(),
            "ActionQueueSettlement.lua",
        )
        execute(
            """
            local requests=PZSurvivorToolkit.ActionQueueTransferRequests
            ISTimedActionQueue={queues={}}
            OwnerEvidence={};OwnerBefore=0;OwnerAfter=0
            function installOwner(action)
                OwnerAction=action;action.toolkitQueueOperation={}
                local q={character=Actor,current=action,queue={action},toolkitOperationGeneration=11}
                ISTimedActionQueue.queues[Actor]=q
                return requests.prepare(action,requestOwnerGuard,requestOwnerBefore,requestOwnerAfter)
            end
            local a=makeAction('owner');local commit=assert(installOwner(a))
            assert(requests.pending[Actor]==nil and commit() and not commit())
            StockStart(a)
            assert(OwnerBefore==1 and OwnerAfter==1 and OwnerEvidence[1].exact==true
                and OwnerEvidence[1].phase=='submitted' and OwnerEvidence[1].transaction==-17)
            local old=OwnerEvidence[1].receipt;requests.observe(old)
            requests.observe({getActor=function()return Actor end})
            assert(OwnerBefore==1 and OwnerAfter==1,'old/copied receipt revived owner observation')
            a.queueList={{items={FirstItem},time=1},{items={SecondItem},time=2}};a.transactionId=9
            StockPerform(a)
            assert(OwnerBefore==2 and OwnerAfter==2 and OwnerEvidence[2].id==702 and OwnerEvidence[2].exact==true
                and OwnerEvidence[2].receipt~=old and OwnerEvidence[2].transaction==-17,
                'continuation did not receive its own fresh exact source visit')
            requests.clear(a);assert(requests.pending[Actor]==nil)
            a=makeAction('lost');assert(installOwner(a))()
            FirstItem:setIsCraftingConsumed(true)
            local n=DelegateCalls;StockStart(a)
            assert(OwnerEvidence[3].exact==false and OwnerEvidence[3].phase=='submitted' and DelegateCalls==n+1,
                'source denial must not skip/retry or fabricate native admission')
            FirstItem:setIsCraftingConsumed(false)
            getTimestampMs=function()return 100 end
            local observe=RequestOutcome.observer()
            local target={isExistYet=function()return true end,getItemById=function(_,id)return Destination:getItemById(id)end}
            local attempt={finished=true,succeeded=true,authority='completed',deadline=30000,
                members={{id=701,fullType='Base.RequestProbe'}}}
            assert(observe({source=Source,destination=target},attempt)=='waiting',
                'a returned request ID must not fabricate physical completion')
            requests.reset(Actor);assert(requests.pending[Actor]==nil)
            for _,phase in ipairs({'before','after'})do
                a=makeAction('throw-'..phase);assert(installOwner(a))();OwnerThrow=phase
                n=DelegateCalls;StockStart(a)
                assert(DelegateCalls==n+1 and a.transactionId==-17 and requests.pending[Actor]==nil,
                    'failed owner must be quarantined while native work continues once')
                OwnerThrow=nil
            end
            a=makeAction('reset');assert(installOwner(a))();ISTimedActionQueue.queues[Actor].toolkitOperationGeneration=12
            n=OwnerBefore;StockStart(a)
            assert(OwnerBefore==n and requests.pending[Actor]==nil,'reset generation retained old request ownership')
            NativeRequestOwnerChecksPassed=true
            """
                .trimIndent(),
            "native-request-owner-checks",
        )
        check(LuaManager.env.rawget("NativeRequestOwnerChecksPassed") == true)
        val benchmark =
            execute(
                """
                local requests=PZSurvivorToolkit.ActionQueueTransferRequests
                local a=makeAction('request-cost');assert(installOwner(a))();RequestTiming=true
                return function(enabled)
                    requests.pending[Actor]=enabled and a or nil
                    StockStart(a)
                end
                """
                    .trimIndent(),
                "request-cost-fixture",
            )
                as LuaClosure
        fun sample(enabled: Boolean): Long {
            val started = System.nanoTime()
            LuaManager.thread.call(benchmark, arrayOf<Any?>(enabled))
            return System.nanoTime() - started
        }
        repeat(300) {
            sample(false)
            sample(true)
        }
        val inactive = LongArray(600)
        val observed = LongArray(600)
        for (index in inactive.indices) {
            if (index % 2 == 0) {
                inactive[index] = sample(false)
                observed[index] = sample(true)
            } else {
                observed[index] = sample(true)
                inactive[index] = sample(false)
            }
        }
        inactive.sort()
        observed.sort()
        println(
            "NATIVE_TRANSFER_REQUEST_COST inactive_median_ns=${inactive[300]} observed_median_ns=${observed[300]} observed_p95_ns=${observed[569]} samples=600 qualified_live=false",
        )
        check(observed[569] <= 1_000_000) { "request-only p95 exceeded frozen 1 ms CPU gate" }
        check(observed[300] - inactive[300] <= 250_000) {
            "request-only median overhead exceeded frozen 0.25 ms CPU gate"
        }
        execute(
            "local before=OwnerBefore;for i=1,32 do PZSurvivorToolkit.ActionQueueTransferRequests.pending[Actor]=nil;StockStart(OwnerAction)end;assert(OwnerBefore==before,'inactive gate called Lua owner');PZSurvivorToolkit.ActionQueueTransferRequests.clear(OwnerAction);PZSurvivorToolkit.ActionQueueTransferRequests.pending[Actor]=OwnerAction;StockStart(OwnerAction);assert(OwnerBefore==before,'public hint created private ownership');PZSurvivorToolkit.ActionQueueTransferRequests.reset(Actor)",
            "request-inactive-and-hint-checks",
        )
        check(NativeTransferRequestReceipt::class.java.constructors.isEmpty()) {
            "receipt constructor exposed"
        }
        println(
            "NATIVE_TRANSFER_REQUESTS_CHECKS_PASS (actual native start/continuation, per-phase claim, byte reuse, failure, caller/env/observer/API proof, nested masking)",
        )
    }
}
