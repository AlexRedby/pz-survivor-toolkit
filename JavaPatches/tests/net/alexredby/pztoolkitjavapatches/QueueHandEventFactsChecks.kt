package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import java.util.LinkedHashMap
import me.zed_0xff.zombie_buddy.Exposer
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.integration.expose.LuaJavaInvoker
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.KahluaThread
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.LuaClosure
import se.krka.kahlua.vm.Prototype
import se.krka.kahlua.vm.UpValue
import sun.misc.Unsafe
import zombie.Lua.KahluaNumberConverter
import zombie.Lua.LuaManager
import zombie.characters.IsoPlayer

/** Actual selected source, native closures/capture cells and invokers; no game process. */
object QueueHandEventFactsChecks {
    private fun table() = KahluaTableImpl(LinkedHashMap<Any, Any?>())
    @JvmStatic fun foreign(a: Any?, b: Any?, c: Any?, d: Any?): Boolean = error("foreign API executed")
    @JvmStatic fun forwarding(a: Any?, b: Any?, c: Any?, d: Any?): Boolean? = QueueHandEventFacts.trackingAbsent(a,b,c,d)

    @JvmStatic fun main(args: Array<String>) {
        val source = System.getenv("PZ_TEST_ARCHERY_STATE_SOURCE")?.let { Path.of(it) }
            ?: error("Set PZ_TEST_ARCHERY_STATE_SOURCE to the selected R5_AimState.lua")
        check(Files.isRegularFile(source)) { "Selected archery source is missing" }
        check(QueueHandEventFacts.SUPPORTED) { "Native capture observer bytecode is unsupported" }
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = LuaManager.platform.newEnvironment()
        val converters = KahluaConverterManager();KahluaNumberConverter.install(converters)
        LuaManager.exposer = LuaManager.Exposer(converters,LuaManager.platform,LuaManager.env)
        Exposer.addClassWithGlobalLuaMethod(QueueHandEventFacts::class.java);Exposer.afterExposeAll()
        val thread = KahluaThread(LuaManager.platform,LuaManager.env).apply { debugOwnerThread=Thread.currentThread() }
        LuaManager.thread=thread
        fun run(text: String): Any? = thread.call(LuaCompiler.loadstring(text,"archery-facts-check",LuaManager.env),emptyArray<Any?>())
        run("""
            calls=0
            local function event() return {Add=function(f) end} end
            Events={OnEquipPrimary=event(),OnEquipSecondary=event(),OnGameStart=event(),OnServerStarted=event(),OnTick=event()}
            bow={}; actor={getPrimaryHandItem=function() calls=calls+1; return bow end,
                getSecondaryHandItem=function() calls=calls+1; return nil end,
                setVariable=function() calls=calls+1 end}
            WPANC={BowReload={isPrimitiveBow=function(item) calls=calls+1;return item==bow end,
                requestNotchedArrowReturn=function() calls=calls+1 end}}
            local modules={WPANC_BowReload=WPANC.BowReload,
                WPANC_Hooks={removeEventHandler=function() end},
                WPANC_ArrowBallistics={applyCharacterRange=function() calls=calls+1 end},
                WPANC_ProjectRemnantsContract={isNPC=function() error('unexpected NPC call') end},
                WPANC_ArcheryContract={isPlayerCharacter=function() calls=calls+1;return true end}}
            require=function(name) if modules[name] then return modules[name] end;error('absent optional module') end
            isClient=function() calls=calls+1;return false end
        """.trimIndent())
        val loaded=LuaCompiler.loadstring(Files.readString(source),"R5_AimState.lua",LuaManager.env)
        fun filename(p: Prototype) { p.filename=source.toString();p.prototypes.forEach { filename(it) } }
        filename(loaded.prototype)
        thread.call(loaded,emptyArray<Any?>())
        val state=((LuaManager.env.rawget("WPANC") as KahluaTableImpl).delegate["BowState"] as KahluaTableImpl)
        val primary=state.delegate["onEquipPrimary"] as LuaClosure
        val secondary=state.delegate["onEquipSecondary"] as LuaClosure
        val updated=state.delegate["markUpdated"] as LuaClosure
        val key=LuaManager.env.rawget("actor") as KahluaTableImpl
        val bow=LuaManager.env.rawget("bow")
        fun read(p: Any?=primary,s: Any?=secondary,u: Any?=updated,supported: Boolean=true,owner: Boolean=true) =
            QueueHandEventFacts.readTestKey(key,p,s,u,supported,owner)
        check(LuaPrototypeFingerprint.leaf(primary.prototype)==QueueHandEventFacts.PRIMARY)
        check(LuaPrototypeFingerprint.leaf(secondary.prototype)==QueueHandEventFacts.SECONDARY)
        check(LuaPrototypeFingerprint.leaf(updated.prototype)==QueueHandEventFacts.UPDATED)
        check(primary.upvalues[3]===secondary.upvalues[3] && primary.upvalues[3]===updated.upvalues[0])
        check(read()==true)
        thread.call(primary,arrayOf(key,bow))
        val before=LuaManager.env.rawget("calls")
        check(read()==false) { "Source-populated capture was treated as absent" }
        check(LuaManager.env.rawget("calls")==before) { "Observation invoked gameplay callbacks" }
        val cell=primary.upvalues[3]
        val old=cell.getValue()
        val handlers=state.delegate["EventHandlers"] as KahluaTableImpl
        thread.call(handlers.delegate["onServerStarted"],emptyArray<Any?>())
        check(cell.getValue()!==old && read()==true) { "Source clearTracking rebind was cached" }
        (old as KahluaTableImpl).delegate[key]=bow
        check(read()==true) { "Detached previous capture retained authority" }
        val current=cell.getValue() as KahluaTableImpl
        current.delegate[key]=false
        check(read()==false) { "Non-nil malformed tracking value must remain present" }
        current.delegate[key]=null
        check(read()==false) { "Malformed explicit null entry must remain present" }
        current.delegate.remove(key)
        check(read()==true)
        check(read(supported=false)==null && read(owner=false)==null)
        check(read(p=null)==null && read(s=table())==null && read(u=primary)==null)
        val saved=secondary.upvalues[3]
        secondary.upvalues[3]=UpValue(null,0).apply { setValue(current) }
        check(read()==null) { "Equal table with unrelated cell passed shared capture proof" }
        secondary.upvalues[3]=saved
        val code=primary.prototype.code[0]
        primary.prototype.code[0]=code xor 64
        check(read()==null) { "Mutable prototype fingerprint was cached" }
        primary.prototype.code[0]=code
        val meta=table();meta.delegate["__metatable"]=false
        current.metatable=meta
        check(read()==null) { "Hidden native metatable passed" }
        current.metatable=null
        current.setRewriteTable(table());check(read()==null);current.setRewriteTable(null)
        cell.setValue(null);check(read()==null);cell.setValue("bad");check(read()==null);cell.setValue(current)
        val wrongMap=KahluaTableImpl(HashMap<Any,Any?>())
        cell.setValue(wrongMap);check(read()==null);cell.setValue(current)
        check(read()==true)

        val helper=LuaManager.env.rawget("toolkitArcheryTrackingAbsent")
        val checker=LuaManager.env.rawget("toolkitArcheryTrackingApiMatches")
        check(helper is LuaJavaInvoker && checker is LuaJavaInvoker)
        check(thread.call(checker,arrayOf(helper))==true)
        val unsafe=Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible=true }.get(null) as Unsafe
        val actor=unsafe.allocateInstance(IsoPlayer::class.java) as IsoPlayer
        val arguments=arrayOf<Any?>(actor,primary,secondary,updated)
        val calls=LuaManager.env.rawget("calls")
        check(thread.call(helper,arguments)==true)
        val environment=primary.env
        val foreignEnvironment=table()
        primary.env=foreignEnvironment;secondary.env=foreignEnvironment;updated.env=foreignEnvironment
        check(thread.call(helper,arguments)==null) { "Foreign environment callbacks retained runtime authority" }
        primary.env=environment;secondary.env=environment;updated.env=environment
        current.delegate[actor]=bow;check(thread.call(helper,arguments)==false);current.delegate.remove(actor)
        check(thread.call(helper,arrayOf(key,primary,secondary,updated))==null) { "Lua table borrowed native actor authority" }
        check(thread.pcall(helper,arrayOf(actor,primary,secondary))[0]==false) { "Native invoker admitted omitted required arguments" }
        check(QueueHandEventFacts.trackingAbsent(actor,primary,secondary,updated)==null) { "Unframed Java call retained authority" }
        thread.debugOwnerThread=null;check(thread.call(helper,arguments)==null)
        thread.debugOwnerThread=Thread.currentThread()
        var foreignThread: Boolean?=true
        Thread { foreignThread=QueueHandEventFacts.trackingAbsent(actor,primary,secondary,updated) }.apply { start();join() }
        check(foreignThread==null)
        run("original=toolkitArcheryTrackingAbsent;toolkitArcheryTrackingAbsent=function(...) calls=calls+1;return original(...) end")
        check(thread.call(checker,arrayOf(helper))==false && thread.call(helper,arguments)==null)
        LuaManager.env.rawset("toolkitArcheryTrackingAbsent",helper)
        for (name in listOf("foreign","forwarding")) {
            LuaManager.env.rawset("foreignAPI",null)
            LuaManager.exposer.exposeGlobalClassFunction(LuaManager.env,QueueHandEventFactsChecks::class.java,
                QueueHandEventFactsChecks::class.java.getMethod(name,Any::class.java,Any::class.java,Any::class.java,Any::class.java),"foreignAPI")
            val foreign=LuaManager.env.rawget("foreignAPI")
            check(foreign is LuaJavaInvoker && thread.call(checker,arrayOf(foreign))==false)
            if (name=="forwarding") check(thread.call(foreign,arguments)==null)
        }
        check(LuaManager.env.rawget("calls")==calls) { "Native observation or identity proof executed a callback" }
        check(thread.call(helper,arguments)==true)

        // The real Lua consumer, SourceProof and native observer share one VM.
        // Only the file-opening adapter is a double; it supplies actual selected bytes.
        LuaManager.exposer.exposeGlobalClassFunction(LuaManager.env,QueueLeafTransferFacts::class.java,
            QueueLeafTransferFacts::class.java.getMethod("luaMetatableMatches",Any::class.java,Any::class.java),"toolkitLuaMetatableMatches")
        LuaManager.exposer.exposeGlobalClassFunction(LuaManager.env,LuaManager.GlobalObject::class.java,
            LuaManager.GlobalObject::class.java.getMethod("getFilenameOfClosure",LuaClosure::class.java),"getFilenameOfClosure")
        var opens=0;var closes=0
        LuaManager.env.rawset("getModFileReader",JavaFunction { frame,count ->
            check(count==3 && frame.get(0)=="WildernessProgressionArcheryNexusCompanion"
                && frame.get(1)=="media/lua/shared/R5_AimState.lua" && frame.get(2)==false)
            opens++
            val reader=Files.newBufferedReader(source)
            val value=table()
            value.delegate["readLine"]=JavaFunction { f,_ -> f.push(reader.readLine());1 }
            value.delegate["close"]=JavaFunction { _,_ -> reader.close();closes++;0 }
            frame.push(value);1
        })
        val root=Path.of(System.getProperty("pz.test.project")).resolve("PZSurvivorToolkit/42/media/lua")
        val proof=thread.call(LuaCompiler.loadstring(Files.readString(root.resolve("shared/PZSurvivorToolkit/SourceProof.lua")),"SourceProof.lua",LuaManager.env),emptyArray<Any?>())
        LuaManager.env.rawset("require",JavaFunction { frame,count ->
            check(count==1 && frame.get(0)=="PZSurvivorToolkit/SourceProof");frame.push(proof);1
        })
        run("PZSurvivorToolkit={}")
        val events=thread.call(LuaCompiler.loadstring(Files.readString(root.resolve("client/PZSurvivorToolkit/ActionQueueHandEvents.lua")),"ActionQueueHandEvents.lua",LuaManager.env),emptyArray<Any?>()) as KahluaTableImpl
        val observe=events.delegate["archeryTrackingAbsent"]
        check(thread.call(observe,arrayOf(actor))==true) { "Real Lua consumer/native observer rejected empty tracking" }
        current.delegate[actor]=bow
        check(thread.call(observe,arrayOf(actor))==false) { "Real consumer inferred absence from current ordinary hands" }
        thread.call(handlers.delegate["onServerStarted"],emptyArray<Any?>())
        check(thread.call(observe,arrayOf(actor))==true) { "Real consumer missed source table rebind" }
        check(opens==1 && closes==1) { "Source pin reopened or leaked its reader" }
        check(LuaManager.env.rawget("calls")==calls) { "Real Lua consumer executed a gameplay callback" }
        println("QUEUE_HAND_EVENT_FACTS_CHECKS_PASS selected_source=true private_capture=true fresh_rebind=true callback_free=true edit_authority=false host_authority=false")
    }
}
