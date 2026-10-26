package zombie.core

import java.io.StringReader
import java.nio.file.Files
import java.nio.file.Path
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.integration.LuaCaller
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.KahluaTable
import se.krka.kahlua.vm.KahluaThread
import se.krka.kahlua.vm.LuaClosure
import zombie.Lua.LuaManager
import zombie.characters.IsoPlayer
import zombie.network.PZNetKahluaNull
import zombie.network.PZNetKahluaTableImpl

/** Constructor parameter names are part of B42's native timed-action wire ABI. */
object FitnessConstructorChecks {
    // Exercise the original NetTimedAction.set(actor, action) argument builder.
    // Its final actor-registration hook is the only suppressed engine operation.
    private class Packet : NetTimedAction() {
        var registrations = 0
        override fun set(player: IsoPlayer?) { registrations++ }
    }

    private fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun compile(source: String, name: String, environment: KahluaTable): LuaClosure =
        LuaCompiler.loadis(StringReader(source), name, environment)

    private fun parameters(closure: LuaClosure): List<String> =
        closure.prototype.locvars.take(closure.prototype.numParams)

    private fun arguments(action: KahluaTable, constructor: LuaClosure): PZNetKahluaTableImpl {
        action.metatable.rawset("new", constructor)
        val packet = Packet()
        packet.set(null, action)
        require(packet.registrations == 1, "native payload builder skipped its final actor hook")
        require(packet.type == "ISFitnessAction", "native payload lost action metatable type")
        return packet.actionArgs
    }

    @JvmStatic
    fun main(args: Array<String>) {
        val project = Path.of(System.getProperty("pz.test.project"))
        // build.py executes regressions in the selected --game directory.
        val nativePath = Path.of("media/lua/shared/TimedActions/ISFitnessAction.lua")
        val nativeText = Files.readString(nativePath)
        val nativeStart = nativeText.indexOf("function ISFitnessAction:new(")
        require(nativeStart >= 0, "selected native Fitness constructor is missing")
        val wrapperPath = project.resolve("PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueFitness.lua")
        val wrapperText = Files.readString(wrapperPath)
        val wrapperStart = wrapperText.indexOf("class.new=function(")
        val wrapperEnd = wrapperText.indexOf("\nclass.stop=", wrapperStart)
        require(wrapperStart >= 0 && wrapperEnd > wrapperStart, "source-backed Fitness wrapper boundary changed")

        val platform = J2SEPlatform()
        val environment = platform.newEnvironment()
        val thread = KahluaThread(platform, environment).apply { debugOwnerThread = Thread.currentThread() }
        LuaManager.platform = platform
        LuaManager.env = environment
        LuaManager.thread = thread
        LuaManager.caller = LuaCaller(KahluaConverterManager())
        thread.call(compile("""
            ISBaseTimedAction = {}
            function ISBaseTimedAction.new(self, character)
                self.__index = self
                return setmetatable({character=character}, self)
            end
            ISFitnessAction = {Type='ISFitnessAction',getDuration=function() return 5000000 end,
                setFitnessSpeed=function() end}
            TestFitness = {setCurrentExercise=function(self, value) self.current=value end}
            TestCharacter = {getFitness=function() return TestFitness end}
            TestExercise = {type='squats',metabolics=1}
            function getGameTime()
                return {getCalender=function() return {getTimeInMillis=function() return 120000 end} end}
            end
        """.trimIndent(), "fitness-constructor-environment.lua", environment), emptyArray<Any?>())
        val native = thread.call(compile(nativeText.substring(nativeStart) + "\nreturn ISFitnessAction.new", nativePath.toString(), environment), emptyArray<Any?>()) as LuaClosure
        environment.rawset("NativeFitnessConstructor", native)
        val prefix = """
            local class=ISFitnessAction
            local native={new=NativeFitnessConstructor}
            local nativeRecords,exercises={},{}
            local nativePanelScope
            local function unchanged() return true end
        """.trimIndent() + "\n"
        fun wrapper(source: String, name: String, trusted: Boolean = true): LuaClosure =
            thread.call(compile(prefix + "local trusted=$trusted\n" + source + "\nreturn class.new", name, environment), emptyArray<Any?>()) as LuaClosure
        val wrapperSource = wrapperText.substring(wrapperStart, wrapperEnd)
        val wrapped = wrapper(wrapperSource, wrapperPath.toString())
        require(wrapped !== native, "supported Fitness source silently bypassed its wrapper")
        val fallback = wrapper(wrapperSource, "unsupported-fitness-constructor.lua", trusted = false)
        require(fallback === native, "unsupported Fitness source replaced the original constructor identity/ABI")
        val expected = listOf("self", "character", "exercise", "timeToExe", "exeData", "exeDataType")
        require(parameters(native) == expected && !native.prototype.isVararg, "selected native Fitness constructor ABI differs: ${parameters(native)}")
        require(parameters(wrapped) == parameters(native) && wrapped.prototype.numParams == native.prototype.numParams
            && wrapped.prototype.isVararg == native.prototype.isVararg,
            "Fitness wrapper changed native constructor parameter names/count/varargs: ${parameters(wrapped)}")

        val owner = environment.rawget("ISFitnessAction") as KahluaTable
        val character = environment.rawget("TestCharacter")
        val exercise = environment.rawget("TestExercise")
        for (minutes in listOf(10.0, 30.0)) {
            val action = thread.call(wrapped, arrayOf(owner, character, "squats", minutes, exercise, "squats")) as KahluaTable
            action.rawset("isUsingTimeout", thread.call(compile("return function() return true end", "timeout.lua", environment), emptyArray<Any?>()))
            require(action.rawget("endMS") == 120000.0 + minutes * 60000, "real native constructor did not calculate the selected deadline")
            for (value in listOf<Number>(minutes, minutes.toInt())) {
                action.rawset("timeToExe", value)
                val payload = arguments(action, wrapped)
                require(payload.delegate.keys.toList() == expected.drop(1), "native constructor wire field order differs: ${payload.delegate.keys}")
                require(payload.rawget("character") === character && payload.rawget("exercise") == "squats"
                    && payload.rawget("exeData") === exercise && payload.rawget("exeDataType") == "squats",
                    "native constructor wire payload lost character/exercise/data identity")
                val actual = payload.rawget("timeToExe")
                require(actual == value && actual.javaClass == value.javaClass, "native constructor wire payload changed minute value/type: $value -> $actual")
                // Lua-number server constructor execution uses the actual ordered native payload.
                if (value is Double) {
                    val serverArgs = arrayOfNulls<Any>(payload.size() + 1)
                    serverArgs[0] = owner
                    payload.delegate.values.forEachIndexed { index, argument -> serverArgs[index + 1] = argument }
                    val reconstructed = thread.call(native, serverArgs) as KahluaTable
                    require(reconstructed.rawget("timeToExe") == minutes && reconstructed.rawget("endMS") == action.rawget("endMS"),
                        "server reconstruction from native constructor payload lost full selected interval")
                }
            }
        }

        // The previous alias-named/vararg wrapper compiles and constructs locally,
        // but real NetTimedAction.set selects absent player/minutes/data/kind fields.
        val broken = wrapper("""
            class.new=function(owner,player,exercise,minutes,data,kind,...)
                return native.new(owner,player,exercise,minutes,data,kind,...)
            end
        """.trimIndent(), "prior-broken-fitness-wrapper.lua")
        require(parameters(broken) != expected && broken.prototype.isVararg, "negative constructor ABI control did not differ")
        val action = thread.call(broken, arrayOf(owner, character, "squats", 30.0, exercise, "squats")) as KahluaTable
        action.rawset("isUsingTimeout", thread.call(compile("return function() return true end", "timeout-negative.lua", environment), emptyArray<Any?>()))
        val brokenPayload = arguments(action, broken)
        require(brokenPayload.rawget("timeToExe") == null && brokenPayload.rawget("minutes") === PZNetKahluaNull.instance,
            "prior wrong parameter names did not reproduce the missing server timeToExe payload")
        require(brokenPayload.rawget("player") === PZNetKahluaNull.instance && brokenPayload.rawget("data") === PZNetKahluaNull.instance,
            "prior wrapper unexpectedly transported native character/exercise-data fields")
        val brokenServerArgs = arrayOfNulls<Any>(brokenPayload.size() + 1)
        brokenServerArgs[0] = owner
        brokenPayload.delegate.values.forEachIndexed { index, value -> brokenServerArgs[index + 1] = value }
        val failedServer = LuaManager.caller.protectedCall(thread, native, *brokenServerArgs)
        require(!failedServer.isSuccess && failedServer.errorString.contains("__mul"),
            "prior native payload did not reproduce the server constructor multiplication failure: ${failedServer.errorString}")
        println("FITNESS_CONSTRUCTOR_CHECKS_PASS (real Kahlua supported wrapper/unsupported identity ABI, NetTimedAction.set field order/identity, int/double minutes, server selected interval, prior alias-name failure)")
        kotlin.system.exitProcess(0)
    }
}
