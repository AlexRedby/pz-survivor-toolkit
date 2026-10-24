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
        transactions.clear()
        GameClient.client = false
        println(
            "ACTION_VALIDITY_CHECKS_PASS (original/woven native validity, exact remote Done, original perform cleanup, no update/effect replay, owner/transaction/custom-sync/cancel/hit/death/movement/SP/unsupported guards)",
        )
    }
}
