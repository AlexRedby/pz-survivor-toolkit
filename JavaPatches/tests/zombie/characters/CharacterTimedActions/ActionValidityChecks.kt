package zombie.characters.CharacterTimedActions

import java.lang.reflect.Field
import java.util.Stack
import java.util.concurrent.ConcurrentLinkedQueue
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.ActionCompletion
import net.alexredby.pztoolkitjavapatches.Main
import net.alexredby.pztoolkitjavapatches.QueueManagers
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.KahluaTable
import sun.misc.Unsafe
import zombie.Lua.LuaManager
import zombie.characters.IsoPlayer
import zombie.core.ActionManager
import zombie.core.NetTimedAction
import zombie.core.Transaction.TransactionState
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.fields.character.PlayerID

object ActionValidityChecks {
    private const val ID: Byte = -126
    private lateinit var unsafe: Unsafe
    private lateinit var transactions: ConcurrentLinkedQueue<Any>
    private lateinit var lifecycle: KahluaTable
    private val events = ArrayList<String>()
    private var allowed = true
    private var waitAllowed = false

    class Player : IsoPlayer(null) {
        lateinit var actions: Stack<BaseAction>
        var dead = false
        var local = true

        override fun getCharacterActions() = actions

        override fun isDead() = dead

        override fun isLocalPlayer() = local
    }

    private fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError("$message: $events")
    }

    private fun field(type: Class<*>, name: String): Field =
        type.getDeclaredField(name).apply { isAccessible = true }

    private fun table(): KahluaTable = LuaManager.platform.newTable()

    private fun owner(player: Player): PlayerID =
        PlayerID().apply {
            setID(player.onlineId)
            require(Accessor.trySet(this, "player", player), "fixture native transaction owner")
        }

    private fun remote(player: Player, state: TransactionState): NetTimedAction =
        NetTimedAction().apply {
            require(Accessor.trySet(this, "id", ID), "fixture native transaction id")
            require(Accessor.trySet(this, "playerId", owner(player)), "fixture native owner")
            require(Accessor.trySet(this, "state", state), "fixture native transaction state")
            transactions.add(this)
        }

    private fun action(): LuaTimedActionNew {
        transactions.clear()
        events.clear()
        allowed = true
        waitAllowed = false
        GameClient.client = true
        val player =
            (unsafe.allocateInstance(Player::class.java) as Player).apply {
                actions = Stack()
                local = true
                onlineId = 19
            }
        val native = unsafe.allocateInstance(LuaTimedActionNew::class.java) as LuaTimedActionNew
        native.chr = player
        native.table = table()
        native.table.rawset("Type", "ValidityProbe")
        native.table.rawset(
            "isValid",
            JavaFunction { frame, _ ->
                events.add("valid")
                frame.push(false)
                1
            },
        )
        native.table.rawset(
            "update",
            JavaFunction { _, _ ->
                events.add("update-after-consumption")
                native.forceStop()
                0
            },
        )
        native.table.rawset(
            "perform",
            JavaFunction { _, _ ->
                events.add("perform-cleanup")
                0
            },
        )
        native.table.rawset(
            "complete",
            JavaFunction { _, _ ->
                events.add("server-effects-replayed")
                0
            },
        )
        (native as BaseAction).started = true
        native.waitForFinished = true
        native.started = true
        native.transactionId = ID
        field(LuaTimedActionNew::class.java, "playerId").set(native, owner(player))
        native.useCustomRemoteTimedActionSync = false
        native.loopAction = true
        player.actions.add(native)
        remote(player, TransactionState.Done)
        return native
    }

    private fun installGate() {
        lifecycle = table()
        lifecycle.rawset(
            "allowNativeCompletion",
            JavaFunction { frame, _ ->
                events.add("gate")
                val native = frame.get(1) as LuaTimedActionNew
                require(frame.get(0) === native.table, "gate lost exact Lua/native identity")
                frame.push(allowed)
                1
            },
        )
        lifecycle.rawset(
            "allowNativeCompletionWait",
            JavaFunction { frame, _ ->
                events.add("wait-gate")
                val native = frame.get(1) as LuaTimedActionNew
                require(frame.get(0) === native.table, "wait gate lost exact Lua/native identity")
                frame.push(waitAllowed)
                1
            },
        )
        val toolkit = table()
        toolkit.rawset("ActionQueueLifecycle", lifecycle)
        LuaManager.env.rawset("PZSurvivorToolkit", toolkit)
    }

    private fun rejected(label: String, change: (LuaTimedActionNew) -> Unit) {
        val native = action()
        change(native)
        require(!native.valid(), "$label rescued an invalid action")
        require(!native.isForceComplete, "$label requested completion")
        require("perform-cleanup" !in events, "$label replayed perform")
    }

    private fun waiting(): LuaTimedActionNew =
        action().also {
            allowed = false
            waitAllowed = true
            require(it.valid(), "exact Done and wait capability lost invalid action")
            require(!it.isForceComplete && !it.forceStop, "waiting executed a terminal transition")
        }

    private fun validResult(native: LuaTimedActionNew, value: Boolean) {
        native.table.rawset(
            "isValid",
            JavaFunction { frame, _ ->
                events.add("valid:" + value)
                frame.push(value)
                1
            },
        )
    }

    private fun accepting(): LuaTimedActionNew =
        action().also {
            allowed = false
            waitAllowed = true // The Lua gate models the exact sealed Started receipt.
            Accessor.trySet(transactions.peek(), "state", TransactionState.Accept)
            require(it.valid(), "paid replication while Accept lost its bounded native wait")
            require(!it.isForceComplete && !it.forceStop, "Accept performed a terminal transition")
        }

    @Suppress("UNCHECKED_CAST")
    private fun episode(native: LuaTimedActionNew): Any =
        (field(ActionCompletion::class.java, "waits").get(null) as Map<Any, Any>)[native]
            ?: throw AssertionError("missing native wait episode")

    private fun acceptedReplicationChecks() {
        // Reproduce the real order: target already consumed, native still Accept,
        // then Done, then the following sealed Completed receipt 71 ms later.
        val pending = accepting()
        val transaction = transactions.peek()
        val wait = episode(pending)
        val deadline = field(wait.javaClass, "deadlineNanos").getLong(wait)
        repeat(2) { pending.update() }
        require(pending.valid(), "Accept wait lost its exact started transaction")
        require(
            !pending.isForceComplete &&
                !pending.forceStop &&
                "gate" !in events &&
                "update-after-consumption" !in events &&
                "perform-cleanup" !in events &&
                "server-effects-replayed" !in events &&
                transactions.size == 1,
            "Accept wait executed completion, stale update, effects or cleanup",
        )
        Accessor.trySet(transaction, "state", TransactionState.Done)
        require(
            pending.valid() && !pending.isForceComplete,
            "Done without Completed ended the wait",
        )
        Thread.sleep(71)
        pending.update()
        require(
            pending.valid() &&
                !pending.isForceComplete &&
                field(wait.javaClass, "deadlineNanos").getLong(wait) == deadline,
            "delayed terminal receipt extended the absolute native wait deadline",
        )
        allowed = true
        require(
            pending.valid() && pending.isForceComplete,
            "Done plus Completed failed native completion",
        )
        pending.update()
        pending.perform()
        require(
            events.count { it == "perform-cleanup" } == 1 &&
                transactions.isEmpty() &&
                "update-after-consumption" !in events &&
                "server-effects-replayed" !in events,
            "accepted replication replayed effects or skipped the one original native perform",
        )
        pending.forceComplete = false
        require(
            !pending.valid() && !pending.isForceComplete,
            "performed Accept episode replayed completion",
        )

        val receiptFirst = accepting()
        allowed = true
        require(
            receiptFirst.valid() && !receiptFirst.isForceComplete,
            "Completed alone promoted Accept",
        )
        receiptFirst.update()
        require(
            "perform-cleanup" !in events && "update-after-consumption" !in events,
            "Accept with Completed receipt ran native callbacks",
        )
        Accessor.trySet(transactions.peek(), "state", TransactionState.Done)
        require(
            receiptFirst.valid() && receiptFirst.isForceComplete,
            "later Done failed the same receipt-first episode",
        )

        for ((label, change) in
            listOf<Pair<String, (LuaTimedActionNew) -> Unit>>(
                "rejected" to
                    {
                        Accessor.trySet(transactions.peek(), "state", TransactionState.Reject)
                    },
                "request rollback" to
                    {
                        Accessor.trySet(transactions.peek(), "state", TransactionState.Request)
                    },
                "duplicate Accept" to { remote(it.chr as Player, TransactionState.Accept) },
                "reused byte/different transaction" to
                    {
                        transactions.clear()
                        remote(it.chr as Player, TransactionState.Accept)
                    },
                "custom sync" to { it.useCustomRemoteTimedActionSync = true },
                "input/reset/generation revoked" to { waitAllowed = false },
                "native stop" to { it.forceStop() },
                "native head gone" to { (it.chr as Player).actions.clear() },
                "dead actor" to { (it.chr as Player).dead = true },
            )) {
            val native = accepting()
            change(native)
            require(!native.valid() && !native.isForceComplete, "$label retained an Accept wait")
            allowed = true
            waitAllowed = true
            Accessor.trySet(transactions.peek(), "state", TransactionState.Done)
            validResult(native, true)
            require(
                !native.valid() && !native.isForceComplete,
                "$label revived after later Done/Completed",
            )
        }
        val expired = accepting()
        val expiredWait = episode(expired)
        field(expiredWait.javaClass, "deadlineNanos").setLong(expiredWait, System.nanoTime() - 1L)
        require(!expired.valid(), "expired Accept retained validity")
        allowed = true
        Accessor.trySet(transactions.peek(), "state", TransactionState.Done)
        require(
            !expired.valid() && !expired.isForceComplete,
            "late Done/Completed revived expired Accept",
        )

        val rollback = accepting()
        Accessor.trySet(transactions.peek(), "state", TransactionState.Done)
        require(
            rollback.valid() && !rollback.isForceComplete,
            "Accept to Done failed before receipt",
        )
        Accessor.trySet(transactions.peek(), "state", TransactionState.Accept)
        require(!rollback.valid(), "observed Done regressed to Accept")
        allowed = true
        Accessor.trySet(transactions.peek(), "state", TransactionState.Done)
        require(
            !rollback.valid() && !rollback.isForceComplete,
            "Done rollback lost terminal revocation",
        )
    }

    private fun waitChecks() {
        val pending = waiting()
        repeat(2) { pending.update() }
        validResult(pending, true)
        require(pending.valid(), "latched wait lost later valid native action")
        pending.update()
        require(
            !pending.isForceComplete &&
                !pending.forceStop &&
                "update-after-consumption" !in events &&
                "perform-cleanup" !in events &&
                "server-effects-replayed" !in events &&
                transactions.size == 1,
            "native waiting ran Lua update, effects or transaction cleanup",
        )
        allowed = true
        require(
            pending.valid() && pending.isForceComplete,
            "delayed completion did not select native perform",
        )
        pending.update()
        pending.perform()
        require(
            events.count { it == "perform-cleanup" } == 1 &&
                transactions.isEmpty() &&
                "update-after-consumption" !in events &&
                "server-effects-replayed" !in events,
            "delayed completion replayed effects or bypassed original perform cleanup",
        )

        pending.forceComplete = false
        validResult(pending, true)
        allowed = false
        events.clear()
        require(
            pending.valid() &&
                events == listOf("valid:true") &&
                !ActionCompletion.skipNativeUpdate(pending, Main.COMPLETION_SUPPORTED),
            "successful waited perform blocked a native loop's later valid tick or update",
        )
        validResult(pending, false)
        allowed = true
        require(
            !pending.valid(),
            "performed wait reacquired completion without a genuine new start",
        )

        val failed = waiting()
        lifecycle.rawset(
            "begin",
            JavaFunction { frame, _ ->
                frame.push(false)
                1
            },
        )
        failed.table.rawset(
            "perform",
            JavaFunction { _, _ -> throw IllegalStateException("expected waited perform failure") },
        )
        allowed = true
        require(
            failed.valid() && failed.isForceComplete,
            "failed callback fixture lost paid completion",
        )
        failed.perform()
        failed.forceComplete = false
        validResult(failed, true)
        require(!failed.valid(), "protected queue-off perform failure revived a waited episode")
        installGate()

        val expired = waiting()
        @Suppress("UNCHECKED_CAST")
        val waits = field(ActionCompletion::class.java, "waits").get(null) as Map<Any, Any>
        val episode = waits[expired] ?: throw AssertionError("missing native wait episode")
        field(episode.javaClass, "deadlineNanos").setLong(episode, System.nanoTime() - 1L)
        require(!expired.valid(), "expired wait retained validity")
        allowed = true
        validResult(expired, true)
        require(
            !expired.valid() && !expired.isForceComplete,
            "late completion revived expired episode",
        )
        // This unsafe fixture cannot execute real start(): model only the shared new-start reset.
        ActionCompletion.nativeStarted(expired, Main.COMPLETION_SUPPORTED)
        validResult(expired, false)
        require(
            expired.valid() && expired.isForceComplete,
            "genuine new-start boundary retained old timeout",
        )

        val changes: List<Pair<String, (LuaTimedActionNew) -> Unit>> =
            listOf(
                "explicit native stop" to { native: LuaTimedActionNew -> native.forceStop() },
                "Lua reset/permission revoked" to { _: LuaTimedActionNew -> waitAllowed = false },
                "native head removed" to
                    { native: LuaTimedActionNew ->
                        (native.chr as Player).actions.clear()
                    },
                "transaction object replaced" to
                    { native: LuaTimedActionNew ->
                        transactions.clear()
                        remote(native.chr as Player, TransactionState.Done)
                    },
                "duplicate same-owner Done" to
                    { native: LuaTimedActionNew ->
                        remote(native.chr as Player, TransactionState.Done)
                    },
                "transaction rejected" to
                    { _: LuaTimedActionNew ->
                        Accessor.trySet(transactions.peek(), "state", TransactionState.Reject)
                    },
            )
        for ((label, change) in changes) {
            val native = waiting()
            change(native)
            require(!native.valid() && !native.isForceComplete, "$label retained waiting validity")
            allowed = true
            waitAllowed = true
            validResult(native, true)
            require(!native.valid() && !native.isForceComplete, "$label revived after Completed")
            native.update()
            require(
                native.forceStop && "update-after-consumption" !in events,
                "$label ran stale update",
            )
        }
        val postLuaStop = waiting()
        lifecycle.rawset(
            "allowNativeCompletion",
            JavaFunction { frame, _ ->
                postLuaStop.forceStop()
                frame.push(true)
                1
            },
        )
        require(
            !postLuaStop.valid() && !postLuaStop.isForceComplete,
            "completion gate overrode a new native stop",
        )
        installGate()
        val postWaitStop = action()
        allowed = false
        lifecycle.rawset(
            "allowNativeCompletionWait",
            JavaFunction { frame, _ ->
                postWaitStop.forceStop()
                frame.push(true)
                1
            },
        )
        require(
            !postWaitStop.valid() && !postWaitStop.isForceComplete,
            "wait gate overrode a new native stop",
        )
        installGate()
        val noWaitContract = action()
        allowed = false
        lifecycle.rawset("allowNativeCompletionWait", null)
        require(!noWaitContract.valid(), "Done alone invented a waiting capability")
        installGate()
        for (state in listOf(TransactionState.Request)) {
            val native = action()
            allowed = false
            waitAllowed = true
            Accessor.trySet(transactions.peek(), "state", state)
            require(
                !native.valid() && !native.isForceComplete,
                "$state acquired an accepted native wait",
            )
        }
        val noNativeWait = action()
        allowed = false
        waitAllowed = true
        noNativeWait.waitForFinished = false
        require(!noNativeWait.valid(), "non-waiting native action acquired completion waiting")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        unsafe = field(Unsafe::class.java, "theUnsafe").get(null) as Unsafe
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = table()
        LuaManager.thread = se.krka.kahlua.vm.KahluaThread(LuaManager.platform, LuaManager.env)
        LuaManager.thread.debugOwnerThread = Thread.currentThread()
        LuaManager.caller =
            se.krka.kahlua.integration.LuaCaller(se.krka.kahlua.converter.KahluaConverterManager())
        transactions =
            Accessor.tryGet<ConcurrentLinkedQueue<Any>>(
                ActionManager::class.java,
                "actions",
                null,
            ) ?: throw AssertionError("native action manager unavailable")
        GameServer.server = false
        installGate()
        val original = action()
        require(!original.valid(), "original engine no longer rejects a replicated consumed target")
        require(!original.isForceComplete && events == listOf("valid"), "native baseline changed")

        PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            ActionValidityChecks::class.java.classLoader,
        )
        require(Main.COMPLETION_SUPPORTED && QueueManagers.ACTION_SUPPORTED, "unsupported engine")
        val completed = action()
        require(completed.valid(), "paid native remote action lost its continuation")
        require(
            completed.isForceComplete && !completed.forceStop && events == listOf("valid", "gate"),
            "validity recovery ran update/effects instead of selecting original native completion",
        )
        require(transactions.size == 1, "validity recovery consumed the native Done transaction")
        completed.perform()
        require(
            events == listOf("valid", "gate", "perform-cleanup") && transactions.isEmpty(),
            "original native perform cleanup did not run once or remove its transaction",
        )
        require(!completed.forceStop, "terminal Lua update was run after authoritative completion")
        // A loop may keep this native object after perform; the engine clears this flag each tick.
        completed.forceComplete = false
        validResult(completed, true)
        allowed = false
        events.clear()
        require(
            completed.valid() && !completed.isForceComplete && events == listOf("valid:true"),
            "immediate completion latched the native object across a later valid loop tick",
        )

        rejected("pending transaction") {
            Accessor.trySet(transactions.peek(), "state", TransactionState.Accept)
        }
        rejected("rejected transaction") {
            Accessor.trySet(transactions.peek(), "state", TransactionState.Reject)
        }
        rejected("missing transaction") { transactions.clear() }
        rejected("other owner with reused byte") {
            val foreign =
                (unsafe.allocateInstance(Player::class.java) as Player).apply {
                    onlineId = 20
                }
            transactions.clear()
            remote(foreign, TransactionState.Done)
        }
        rejected("mixed duplicate states") { remote(it.chr as Player, TransactionState.Request) }
        rejected("explicit cancel or hit") { it.forceStop() }
        rejected("direct native movement stop") { (it.chr as Player).actions.clear() }
        rejected("custom remote sync") { it.useCustomRemoteTimedActionSync = true }
        rejected("not locally started") { (it as BaseAction).started = false }
        rejected("not remotely started") { it.started = false }
        rejected("zero transaction") { it.transactionId = 0 }
        rejected("dead actor") { (it.chr as Player).dead = true }
        rejected("remote actor") { (it.chr as Player).local = false }
        rejected("single player") { GameClient.client = false }
        rejected("disabled queue or revoked completed receipt") { allowed = false }
        rejected("missing Lua contract") { lifecycle.rawset("allowNativeCompletion", null) }
        installGate()
        val unsupported = action()
        require(
            !ActionCompletion.restoreNativeCompletion(unsupported, false, false) &&
                events.isEmpty(),
            "unsupported bytecode consulted Lua or changed validity",
        )
        val valid = action()
        valid.table.rawset(
            "isValid",
            JavaFunction { frame, _ ->
                events.add("valid-true")
                frame.push(true)
                1
            },
        )
        require(
            valid.valid() && !valid.isForceComplete && events == listOf("valid-true"),
            "already valid action acquired a forced completion",
        )
        acceptedReplicationChecks()
        waitChecks()
        transactions.clear()
        GameClient.client = false
        println(
            "ACTION_VALIDITY_CHECKS_PASS (original/woven native validity, exact remote Done, original perform cleanup, no update/effect replay, owner/transaction/custom-sync/cancel/hit/death/movement/SP/unsupported guards, bounded Accept/Done receipt wait, monotonic native state, woven update suppression, revocation/new-start reset)",
        )
    }
}
