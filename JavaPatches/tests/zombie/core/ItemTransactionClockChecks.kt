package zombie.core

import java.lang.reflect.Field
import java.util.concurrent.ConcurrentLinkedQueue
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.ItemBatchAdmission
import net.alexredby.pztoolkitjavapatches.ItemTransactionClock
import net.bytebuddy.jar.asm.ClassReader
import net.bytebuddy.jar.asm.ClassVisitor
import net.bytebuddy.jar.asm.ClassWriter
import net.bytebuddy.jar.asm.MethodVisitor
import net.bytebuddy.jar.asm.Opcodes
import sun.misc.Unsafe
import zombie.GameTime
import zombie.characters.IsoPlayer
import zombie.iso.IsoDirections
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.packets.ItemTransactionPacket

/** Original engine versus woven timeout regression; no sockets, world or sleeps. */
object ItemTransactionClockChecks {
    private class ForeignPacket : ItemTransactionPacket()
    private class AliasedPacket(private val target: Transaction) : ItemTransactionPacket() {
        override fun equals(other: Any?) = other === target
        override fun hashCode() = target.hashCode()
    }
    private fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun field(owner: Class<*>, name: String): Field =
        owner.getDeclaredField(name).apply { isAccessible = true }

    private fun changed(source: ByteArray): ByteArray {
        val writer = ClassWriter(0)
        ClassReader(source).accept(object : ClassVisitor(Opcodes.ASM9, writer) {
            override fun visitMethod(access: Int, name: String?, descriptor: String?, signature: String?,
                exceptions: Array<out String>?): MethodVisitor {
                val original = super.visitMethod(access, name, descriptor, signature, exceptions)
                if (name != "lambda\$update\$1") return original
                return object : MethodVisitor(Opcodes.ASM9, original) {
                    override fun visitCode() {
                        super.visitCode()
                        super.visitInsn(Opcodes.NOP)
                    }
                }
            }
        }, 0)
        return writer.toByteArray()
    }

    private fun weaveChecks() {
        val nativeBytes = ItemTransactionClockChecks::class.java.classLoader
            .getResourceAsStream("zombie/core/TransactionManager.class").use { it!!.readAllBytes() }
        val woven = ItemTransactionClock.weave(nativeBytes)
        require(woven != null && ItemTransactionClock.weave(woven) == null,
            "clock predicate transform missing or accepted double weaving")
        require(ItemTransactionClock.weave(changed(nativeBytes)) == null,
            "clock predicate transform accepted changed source")
        var hooks = 0
        ClassReader(woven).accept(object : ClassVisitor(Opcodes.ASM9) {
            override fun visitMethod(access: Int, name: String?, descriptor: String?, signature: String?,
                exceptions: Array<out String>?): MethodVisitor = object : MethodVisitor(Opcodes.ASM9) {
                override fun visitMethodInsn(opcode: Int, owner: String?, method: String?, desc: String?, isInterface: Boolean) {
                    if (owner != "net/alexredby/pztoolkitjavapatches/ItemTransactionClock") return
                    require(name == "lambda\$update\$1" && method == "expired"
                        && desc == "(Lzombie/core/Transaction;Z)Z", "unexpected clock transform callsite")
                    hooks++
                }
            }
        }, 0)
        require(hooks == 1, "clock predicate transform must inject exactly one adjustment")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val unsafe = field(Unsafe::class.java, "theUnsafe").get(null) as Unsafe
        val player = (unsafe.allocateInstance(IsoPlayer::class.java) as IsoPlayer).apply {
            onlineId = 19
        }
        field(zombie.iso.IsoObject::class.java, "ecsComponentMap")
            .set(player, java.util.HashMap<Any, Any>())
        @Suppress("UNCHECKED_CAST")
        val transactions =
            field(TransactionManager::class.java, "transactions").get(null)
                as ConcurrentLinkedQueue<Transaction>
        val previous = transactions.toList()
        val clockFields = listOf("isUTest", "serverTimeShift", "serverTimeShiftIsSet")
            .map { field(GameTime::class.java, it) }
        val clockValues = clockFields.map { it.get(null) }
        val lastId = field(Transaction::class.java, "lastId")
        val previousId = lastId.getByte(null)
        val oldClient = GameClient.client
        val oldServer = GameServer.server
        val timeout = TransactionManager::class.java.getDeclaredMethod(
            "lambda\$update\$1", java.lang.Long.TYPE, Transaction::class.java,
        ).apply { isAccessible = true }
        fun expiredAt(transaction: Transaction, now: Long) =
            timeout.invoke(null, now, transaction) == true
        fun request(): ItemTransactionPacket = ItemTransactionPacket().apply {
            // An empty native payload avoids world/container/JNI work while retaining
            // the actual Request state, timestamp, owner and nonzero ID allocation.
            set(player, emptyList(), null, null, null, IsoDirections.N, 0f, 0f, 0f)
            require(id.toInt() != 0, "native allocation produced zero transaction ID")
            require(state == Transaction.TransactionState.Request, "not a native Request")
            TransactionManager.add(this)
        }
        try {
            transactions.clear()
            GameServer.server = false
            GameClient.client = true
            clockFields[0].setBoolean(null, false)
            val readyShift = 50_000_000_000L - System.nanoTime()
            clockFields[1].setLong(null, readyShift)
            clockFields[2].setBoolean(null, false)
            require(GameTime.getServerTimeMills() == 0L, "unsynchronized clock is not zero")
            val unsynchronized = request()
            val missingId = unsynchronized.id
            require(unsynchronized.startTime == 0L && unsynchronized.endTime == 0L,
                "real Transaction.set did not stamp the unsynchronized Request with zero")
            require(!TransactionManager.isDone(missingId) && !TransactionManager.isRejected(missingId),
                "present Request must be neither Done nor Reject")
            TransactionManager.update()
            require(transactions.singleOrNull() === unsynchronized,
                "unsynchronized update lost the exact Request object")

            // Native sync writes readiness directly. Matching the provisional
            // shift takes no follow-up TimeSync/network branch and yields a
            // controlled positive time, independent of this machine's uptime.
            GameTime.syncServerTime(0L, readyShift, 0L)
            require(GameTime.getServerTimeShiftIsSet(), "real native clock sync did not become ready")
            require(GameTime.getServerTimeMills() > 20_000L, "native monotonic uptime too short for regression")
            val synchronized = request()
            require(synchronized !== unsynchronized && synchronized.id != missingId,
                "control must retain a different nonzero native transaction")
            require(synchronized.startTime > 0L && synchronized.endTime == synchronized.startTime,
                "synchronized Request did not retain native positive clock stamps")
            TransactionManager.update()
            require(transactions.singleOrNull() === synchronized,
                "clock transition must expire only the exact zero-stamped Request")
            require(TransactionManager.isDone(missingId) && TransactionManager.isRejected(missingId),
                "absent nonzero ID no longer has native empty-allMatch semantics")
            require(!TransactionManager.isDone(synchronized.id) && !TransactionManager.isRejected(synchronized.id),
                "live synchronized control incorrectly became terminal")

            // Call the actual native update predicate with an explicit timestamp:
            // exact boundaries cannot be tested reliably against a running clock.
            synchronized.startTime = 100_000L
            synchronized.endTime = synchronized.startTime
            require(!expiredAt(synchronized, 119_999L), "Request expired before 20 seconds")
            require(!expiredAt(synchronized, 120_000L), "Request expired at inclusive 20-second boundary")
            require(expiredAt(synchronized, 120_001L), "Request did not expire after 20 seconds")
            synchronized.setDuration(1_100L)
            synchronized.state = Transaction.TransactionState.Accept
            require(!expiredAt(synchronized, 111_099L), "Accept expired before duration plus buffer")
            require(!expiredAt(synchronized, 111_100L), "Accept expired at inclusive duration plus buffer")
            require(expiredAt(synchronized, 111_101L), "Accept did not expire after duration plus buffer")
            synchronized.setDuration(-1L)
            require(!expiredAt(synchronized, 120_000L) && expiredAt(synchronized, 120_001L),
                "nonpositive duration must retain the native 20-second fallback")
            require(transactions.singleOrNull() === synchronized,
                "read-only timeout predicate changed transaction identity or membership")
            synchronized.state = Transaction.TransactionState.Reject
            require(!TransactionManager.isDone(synchronized.id) && TransactionManager.isRejected(synchronized.id),
                "actual Reject must remain distinct from absent-ID completion")
            synchronized.state = Transaction.TransactionState.Done
            require(TransactionManager.isDone(synchronized.id) && !TransactionManager.isRejected(synchronized.id),
                "actual Done must remain distinct from absent-ID rejection")

            transactions.clear()
            weaveChecks()
            require(!ItemTransactionClock.install(false), "unsupported install enabled clock repair")
            require(ItemBatchAdmission.install(ItemBatchAdmission.SUPPORTED),
                "existing batch admission transformer did not install")
            require(ItemTransactionClock.install(ItemTransactionClock.SUPPORTED),
                "native clock transformer failed after batch admission installation")
            PatchEngine.applyPatches(
                "net.alexredby.pztoolkitjavapatches", ItemTransactionClockChecks::class.java.classLoader,
            )
            require(ItemTransactionClock.SUPPORTED, "native clock repair source gate is unsupported")
            @Suppress("UNCHECKED_CAST")
            val births = field(
                Class.forName("net.alexredby.pztoolkitjavapatches.ItemTransactionClockLogic"), "births",
            ).get(null) as MutableMap<Transaction, Long>
            val untracked = ItemTransactionPacket()
            val foreign = ForeignPacket().apply {
                set(player, emptyList(), null, null, null, IsoDirections.N, 0f, 0f, 0f)
            }
            for (value in listOf(false, true)) {
                require(ItemTransactionClock.expiredAt(untracked, value, Long.MAX_VALUE) == value,
                    "untracked exact packet lost original timeout result")
                require(ItemTransactionClock.expiredAt(foreign, value, Long.MAX_VALUE) == value,
                    "unsupported packet subclass lost original timeout result")
                require(ItemTransactionClock.expiredAt(null, value, Long.MAX_VALUE) == value,
                    "missing packet lost original timeout result")
            }
            require(!births.containsKey(foreign), "unsupported subclass acquired a local clock")

            clockFields[2].setBoolean(null, false)
            val repaired = request()
            val birth = births[repaired] ?: throw AssertionError("real Transaction.set advice was not woven")
            val alias = AliasedPacket(repaired)
            for (value in listOf(false, true)) {
                require(ItemTransactionClock.expiredAt(alias, value, birth + 100_000_000_000L) == value,
                    "unsupported equal/hashCode alias borrowed an exact native packet's clock")
            }
            val stamp = repaired.startTime
            val deadline = repaired.endTime
            val state = repaired.state
            val id = repaired.id
            require(stamp == 0L && deadline == 0L, "repaired Request changed native zero timestamps")
            GameTime.syncServerTime(0L, readyShift, 0L)
            TransactionManager.update()
            require(transactions.singleOrNull() === repaired,
                "synthetic native timeout predicate was not woven: clock sync removed fresh Request")
            require(repaired.startTime == stamp && repaired.endTime == deadline && repaired.state == state && repaired.id == id,
                "clock repair mutated native timestamp, state or ID")
            fun expiresAfter(milliseconds: Long, fraction: Long = 0L, fallback: Boolean = true) =
                ItemTransactionClock.expiredAt(repaired, fallback, birth + milliseconds * 1_000_000L + fraction)
            require(!expiresAfter(19_999L) && !expiresAfter(20_000L) && !expiresAfter(20_000L, 999_999L),
                "repaired default timeout lost strict millisecond rounding")
            require(expiresAfter(20_001L, fallback = false), "repaired default timeout did not expire")
            repaired.setDuration(1_100L)
            repaired.state = Transaction.TransactionState.Accept
            require(!expiresAfter(11_099L) && !expiresAfter(11_100L) && !expiresAfter(11_100L, 999_999L),
                "repaired duration timeout lost strict millisecond rounding")
            require(expiresAfter(11_101L, fallback = false), "repaired duration timeout did not expire")
            repaired.setDuration(0L)
            require(!expiresAfter(20_000L) && expiresAfter(20_001L, fallback = false),
                "zero native duration lost default timeout")
            repaired.setDuration(-1L)
            require(!expiresAfter(20_000L) && expiresAfter(20_001L, fallback = false),
                "negative native duration lost default timeout")
            for (shift in listOf(readyShift + 1_000_000_000_000L, readyShift - 1_000_000_000_000L)) {
                clockFields[1].setLong(null, shift)
                require(!expiresAfter(1_000L) && expiresAfter(20_001L, fallback = false),
                    "server clock correction changed local allocation age")
                TransactionManager.update()
                require(transactions.singleOrNull() === repaired, "server clock correction removed fresh exact Request")
            }
            require(repaired.startTime == stamp && repaired.endTime == stamp - 1L && repaired.id == id
                && repaired.state == Transaction.TransactionState.Accept,
                "timeout inspection mutated native duration fields, state or ID")
            repaired.state = Transaction.TransactionState.Reject
            require(!TransactionManager.isDone(id) && TransactionManager.isRejected(id),
                "repaired clock weakened actual Reject validation")
            for ((client, server) in listOf(false to false, true to true)) {
                GameClient.client = client
                GameServer.server = server
                for (value in listOf(false, true)) {
                    require(ItemTransactionClock.expiredAt(repaired, value, birth + 100_000_000_000L) == value,
                        "server or single-player timeout result changed")
                }
            }
            GameClient.client = true
            GameServer.server = false
            clockFields[1].setLong(null, readyShift)
            val retained = request()
            require(retained !== repaired && retained.id != repaired.id, "fresh control aliases repaired native request")
            synchronized(births) { births[repaired] = System.nanoTime() - 21_000_000_000L }
            TransactionManager.update()
            require(transactions.singleOrNull() === retained,
                "real native update failed exact aged removal or removed the fresh control")
            require(TransactionManager.isDone(id) && TransactionManager.isRejected(id),
                "repair changed native absent-ID predicates after genuine local timeout")
        } finally {
            transactions.clear()
            transactions.addAll(previous)
            clockFields.zip(clockValues).forEach { (entry, value) -> entry.set(null, value) }
            lastId.setByte(null, previousId)
            GameClient.client = oldClient
            GameServer.server = oldServer
        }
        println("ITEM_TRANSACTION_CLOCK_CHECKS_PASS original-engine zero-stamp-sync-expiry synchronized-control exact-timeout-boundaries absent-allMatch socket-free")
    }
}
