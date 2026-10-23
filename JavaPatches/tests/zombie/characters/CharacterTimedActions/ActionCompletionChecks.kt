package zombie.characters.CharacterTimedActions

import java.lang.reflect.Field
import java.util.ArrayList
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.ActionCompletion
import net.alexredby.pztoolkitjavapatches.Main
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.KahluaTable
import sun.misc.Unsafe
import zombie.Lua.LuaManager
import zombie.characters.IsoPlayer
import zombie.network.GameClient

object ActionCompletionChecks {
    private lateinit var unsafe: Unsafe
    private val events = ArrayList<String>()

    private fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError("$message: $events")
    }

    private fun field(owner: Class<*>, name: String): Field =
        owner.getDeclaredField(name).apply { isAccessible = true }

    private fun table(): KahluaTable = LuaManager.platform.newTable()

    private fun action(complete: Boolean): LuaTimedActionNew {
        val action = unsafe.allocateInstance(LuaTimedActionNew::class.java) as LuaTimedActionNew
        action.table = table()
        action.table.rawset("Type", "LifecycleProbe")
        action.table.rawset(
            "perform",
            JavaFunction { _, _ ->
                events.add("perform")
                events.add("callback-tail")
                0
            },
        )
        if (complete)
            action.table.rawset(
                "complete",
                JavaFunction { _, _ ->
                    events.add("effects")
                    0
                },
            )
        action.chr = unsafe.allocateInstance(IsoPlayer::class.java) as IsoPlayer
        action.loopAction = true
        action.useCustomRemoteTimedActionSync = true
        return action
    }

    private fun installHooks() {
        val toolkit = table()
        val lifecycle = table()
        lifecycle.rawset(
            "begin",
            JavaFunction { frame, _ ->
                events.add("begin:" + frame.get(1))
                frame.push(true)
                1
            },
        )
        lifecycle.rawset(
            "finish",
            JavaFunction { frame, _ ->
                events.add("finish:" + frame.get(1) + ":" + frame.get(2))
                0
            },
        )
        toolkit.rawset("ActionQueueLifecycle", lifecycle)
        LuaManager.env.rawset("PZSurvivorToolkit", toolkit)
    }

    private fun observerScopes() {
        events.clear()
        installHooks()
        val outer = action(true)
        val inner = action(true)
        val owned = ActionCompletion.begin(outer, "perform", true)
        val toolkit = LuaManager.env.rawget("PZSurvivorToolkit") as KahluaTable
        val lifecycle = toolkit.rawget("ActionQueueLifecycle") as KahluaTable
        lifecycle.rawset(
            "begin",
            JavaFunction { frame, _ ->
                events.add("declined:" + frame.get(1))
                frame.push(false)
                1
            },
        )
        inner.table.rawset(
            "perform",
            JavaFunction { _, _ -> throw IllegalStateException("expected observed-only failure") },
        )
        require(
            ActionCompletion.begin(inner, "perform", true) == null,
            "declined Lua lifecycle acquired queue ownership",
        )
        val observing = ActionCompletion.observeOnly(inner, "perform")
        inner.perform()
        require(
            field(ActionCompletion.Scope::class.java, "failed").getBoolean(observing),
            "observer-only native protected failure became success",
        )
        require(
            !field(ActionCompletion.Scope::class.java, "failed").getBoolean(owned),
            "observer-only failure poisoned outer queue scope",
        )
        ActionCompletion.end(observing, null)
        require(
            (field(ActionCompletion::class.java, "current").get(null) as ThreadLocal<*>).get() ===
                owned,
            "observer-only scope failed to restore outer scope",
        )
        require(
            events.none { it.startsWith("finish:") },
            "observer-only scope notified Lua queue finish",
        )
        ActionCompletion.end(owned, null)
        clean()
        require(
            events[events.size - 1] == "finish:perform:true",
            "outer queue callback lost its original finish boundary",
        )
        events.clear()
        val foreign = action(true)
        foreign.perform()
        clean()
        require(
            events == listOf("declined:perform", "perform", "callback-tail"),
            "declined unrelated native action acquired a fallback scope",
        )
        events.clear()
        installHooks()
    }

    private fun clean() {
        require(
            (field(ActionCompletion::class.java, "current").get(null) as ThreadLocal<*>).get() ==
                null,
            "native completion scope leaked",
        )
    }

    private fun run(client: Boolean) {
        GameClient.client = client
        val action = action(true)
        action.perform()
        if (!client) action.complete()
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
        installHooks()
        run(false)
        require(
            events == listOf("perform", "callback-tail", "effects"),
            "original native callback order changed",
        )
        events.clear()
        PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            ActionCompletionChecks::class.java.classLoader,
        )
        Main.main(emptyArray())
        run(false)
        require(
            events ==
                listOf(
                    "begin:perform",
                    "perform",
                    "callback-tail",
                    "finish:perform:true",
                    "begin:complete",
                    "effects",
                    "finish:complete:true",
                ),
            "woven SP phase boundary did not surround actual native callbacks",
        )
        clean()
        events.clear()
        run(true)
        require(
            events == listOf("begin:perform", "perform", "callback-tail", "finish:perform:true"),
            "woven MP boundary lost callback tail",
        )
        clean()
        events.clear()
        GameClient.client = false
        val absent = action(false)
        absent.perform()
        absent.complete()
        require(
            events.contains("finish:complete:true"),
            "absent optional complete treated as action failure",
        )
        clean()
        events.clear()
        val rejected = action(true)
        rejected.table.rawset(
            "complete",
            JavaFunction { frame, _ ->
                frame.push(false)
                1
            },
        )
        rejected.perform()
        rejected.complete()
        require(
            events.contains("finish:complete:false"),
            "explicit native effect rejection became success",
        )
        clean()
        events.clear()
        val failure = action(true)
        failure.table.rawset(
            "perform",
            JavaFunction { _, _ -> throw IllegalStateException("expected completion failure") },
        )
        failure.perform()
        require(
            events.contains("finish:perform:false"),
            "native protected Lua failure became a success",
        )
        clean()
        events.clear()
        val nested = action(true)
        val outer = action(true)
        nested.table.rawset(
            "perform",
            JavaFunction { _, _ -> throw IllegalStateException("expected nested failure") },
        )
        outer.table.rawset(
            "perform",
            JavaFunction { _, _ ->
                nested.perform()
                0
            },
        )
        outer.perform()
        require(
            events ==
                listOf(
                    "begin:perform",
                    "begin:perform",
                    "finish:perform:false",
                    "finish:perform:true",
                ),
            "nested callback failure poisoned its caller",
        )
        clean()
        events.clear()
        val broken = action(true)
        broken.chr = null
        try {
            broken.perform()
            throw AssertionError("native Java exception swallowed")
        } catch (expected: NullPointerException) {}
        require(
            events == listOf("begin:perform", "finish:perform:false"),
            "native Java exception did not settle failure",
        )
        clean()
        events.clear()
        observerScopes()
        require(
            ActionCompletion.begin(action(true), "perform", false) == null,
            "unsupported engine acquired completion scope",
        )
        require(events.isEmpty(), "unsupported engine notified Lua")
        println(
            "ACTION_COMPLETION_CHECKS_PASS (original/woven SP/MP callbacks, optional complete, nested protected errors, Java exception, observer-only failure/isolation, unsupported guard)",
        )
    }
}
