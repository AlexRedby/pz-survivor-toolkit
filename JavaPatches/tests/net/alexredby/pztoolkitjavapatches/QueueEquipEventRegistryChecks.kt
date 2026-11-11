package net.alexredby.pztoolkitjavapatches

import java.nio.file.Files
import java.nio.file.Path
import java.util.ArrayList
import java.util.HashMap
import java.util.LinkedHashMap
import me.zed_0xff.zombie_buddy.Exposer
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.integration.expose.LuaJavaInvoker
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.KahluaThread
import se.krka.kahlua.vm.LuaClosure
import zombie.Lua.Event
import zombie.Lua.KahluaNumberConverter
import zombie.Lua.LuaEventManager
import zombie.Lua.LuaManager

/** Actual native event registration and Lua invokers, without game/network initialization. */
object QueueEquipEventRegistryChecks {
    private fun table() = KahluaTableImpl(LinkedHashMap<Any, Any?>())
    private fun array(vararg values: Any?) = table().apply {
        values.forEachIndexed { i, value -> delegate[(i + 1).toDouble()] = value }
    }
    @JvmStatic fun foreign(a: Any?, b: Any?): Boolean = error("Foreign API executed")
    @JvmStatic fun forwarding(a: Any?, b: Any?): Boolean? = QueueEquipEventRegistry.callbacksMatch(a,b)
    @JvmStatic fun forwardingSnapshot(): KahluaTableImpl? = QueueEquipEventRegistry.callbacks()

    @JvmStatic fun main(args: Array<String>) {
        check(QueueEquipEventRegistry.SUPPORTED) { "Native equip registry bytecode is unsupported" }
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = LuaManager.platform.newEnvironment()
        val converters = KahluaConverterManager(); KahluaNumberConverter.install(converters)
        LuaManager.exposer = LuaManager.Exposer(converters,LuaManager.platform,LuaManager.env)
        Exposer.addClassWithGlobalLuaMethod(QueueEquipEventRegistry::class.java); Exposer.afterExposeAll()
        val thread = KahluaThread(LuaManager.platform,LuaManager.env).apply { debugOwnerThread=Thread.currentThread() }
        LuaManager.thread=thread
        fun run(text: String): Any? = thread.call(LuaCompiler.loadstring(text,"equip-registry-test",LuaManager.env),emptyArray<Any?>())
        fun closure(name: String): LuaClosure = (run("return function() error('callback executed') end") as LuaClosure).apply {
            prototype.filename="equip-registry-test.lua"; prototype.name=name
        }
        val a=closure("a"); val b=closure("b"); val c=closure("c")
        val helper=LuaManager.env.rawget("toolkitEquipEventCallbacksMatch")
        val snapshot=LuaManager.env.rawget("toolkitEquipEventCallbacks")
        val checker=LuaManager.env.rawget("toolkitEquipEventRegistryApiMatches")
        check(helper is LuaJavaInvoker && snapshot is LuaJavaInvoker && checker is LuaJavaInvoker)
        fun read(p: Any?=array(a,b),s: Any?=array(c)) = thread.call(helper,arrayOf(p,s))
        fun snap() = thread.call(snapshot,emptyArray<Any?>()) as KahluaTableImpl?
        check(thread.call(checker,arrayOf(helper))==true && thread.call(checker,arrayOf(snapshot))==true)
        LuaEventManager.Reset()
        check(read(array(),array())==null && snap()==null) { "Missing native registry became an empty fact" }
        LuaEventManager.register(LuaManager.platform,LuaManager.env)
        check(read(array(),array())==true)
        val empty=snap()!!
        check((empty.delegate["primary"] as KahluaTableImpl).delegate.isEmpty())
        val primary=LuaEventManager.AddEvent("OnEquipPrimary")
        val secondary=LuaEventManager.AddEvent("OnEquipSecondary")
        val eventTable=LuaManager.env.rawget("Events") as KahluaTableImpl
        fun eventFunction(name: String,operation: String) = (eventTable.delegate[name] as KahluaTableImpl).delegate[operation]
        thread.call(eventFunction("OnEquipPrimary","Add"),arrayOf(a))
        thread.call(eventFunction("OnEquipPrimary","Add"),arrayOf(b))
        thread.call(eventFunction("OnEquipSecondary","Add"),arrayOf(c))
        check(read()==true)
        check(read(array(b,a))==false && read(array(a))==false && read(array(a,b,c))==false)
        check(read(array(a,a))==false && read(array(),array())==false)
        // Native Add preserves duplicates; equality and snapshots preserve their order too.
        thread.call(eventFunction("OnEquipPrimary","Add"),arrayOf(a))
        check(read()==false && read(array(a,b,a))==true)
        thread.call(eventFunction("OnEquipPrimary","Remove"),arrayOf(a))
        check(read(array(b,a))==true)
        primary.callbacks.clear(); primary.callbacks.add(a); primary.callbacks.add(b)
        val observed=snap()!!
        val observedP=observed.delegate["primary"] as KahluaTableImpl
        val observedS=observed.delegate["secondary"] as KahluaTableImpl
        check(observedP.delegate[1.0]===a && observedP.delegate[2.0]===b && observedS.delegate[1.0]===c)
        check(read(observedP,observedS)==true)
        observedP.delegate.clear(); observedS.delegate[1.0]=a; observed.delegate.clear()
        check(primary.callbacks==listOf(a,b) && secondary.callbacks==listOf(c) && read()==true) {
            "Snapshot exposed a mutable native callback list"
        }
        check(snap()!==observed)

        for (bad in listOf(null,false,a,table().apply { delegate[1.0]=a;delegate[3.0]=b },
                table().apply { delegate["1"]=a },table().apply { delegate[1]=a },
                table().apply { delegate[0.0]=a },table().apply { delegate[Double.NaN]=a },
                array(a,false),array(a,null),KahluaTableImpl(HashMap<Any,Any?>()))) {
            check(read(bad)==null) { "Malformed supplied callback array was accepted" }
        }
        val malformed=array(a,b)
        malformed.metatable=table(); check(read(malformed)==null);malformed.metatable=null
        malformed.setRewriteTable(array(a,b));check(read(malformed)==null);malformed.setRewriteTable(null)
        val environment=a.env
        a.env=table()
        check(read()==null && snap()==null) { "Foreign callback environment retained authority" }
        a.env=environment
        @Suppress("UNCHECKED_CAST") val rawCallbacks=primary.callbacks as ArrayList<Any?>
        rawCallbacks.add(false);check(read()==null && snap()==null);rawCallbacks.removeAt(rawCallbacks.lastIndex)
        rawCallbacks.add(null);check(read()==null && snap()==null);rawCallbacks.removeAt(rawCallbacks.lastIndex)
        check(read()==true)

        val replacement=closure("a")
        LuaEventManager.reroute(a.prototype,replacement)
        check(read()==false && read(array(replacement,b))==true) { "Native reroute was cached" }
        primary.callbacks[0]=a
        thread.call(eventFunction("OnEquipPrimary","Remove"),arrayOf(b))
        check(read()==false && read(array(a))==true)
        thread.call(eventFunction("OnEquipPrimary","Add"),arrayOf(b))
        LuaEventManager.ResetCallbacks()
        check(read()==false && read(array(),array())==true)
        primary.callbacks.add(a);primary.callbacks.add(b);secondary.callbacks.add(c)
        // Native queued/active dispatch can retain an old Event identity. setEvents does
        // not erase it, but the current name registry predicate must follow the new map.
        val retained=primary
        val newPrimary=Event("OnEquipPrimary",0)
        val newSecondary=Event("OnEquipSecondary",1)
        newPrimary.callbacks.add(b);newSecondary.callbacks.add(c)
        LuaEventManager.setEvents(arrayListOf(newPrimary,newSecondary),hashMapOf("OnEquipPrimary" to newPrimary,"OnEquipSecondary" to newSecondary))
        check(retained.callbacks==listOf(a,b) && read()==false && read(array(b))==true)
        retained.callbacks.clear();check(read(array(b))==true)
        LuaEventManager.setEvents(arrayListOf(newPrimary,newSecondary),hashMapOf("OnEquipPrimary" to newPrimary))
        check(read(array(b))==null && snap()==null)
        LuaEventManager.Reset();check(read(array(),array())==null && snap()==null)
        LuaEventManager.register(LuaManager.platform,LuaManager.env)
        check(read(array(),array())==true)

        val p=array();val s=array()
        check(QueueEquipEventRegistry.callbacksMatch(p,s)==null && QueueEquipEventRegistry.callbacks()==null)
        check(QueueEquipEventRegistry.apiMatches(helper)==false)
        check(thread.pcall(helper,arrayOf(p))[0]==false)
        check(thread.pcall(helper,arrayOf(p,s,false))[0]==false)
        check(thread.call(snapshot,arrayOf(false))==null)
        thread.debugOwnerThread=null;check(read(p,s)==null && snap()==null);thread.debugOwnerThread=Thread.currentThread()
        var foreignThread: Any?=true
        Thread { foreignThread=QueueEquipEventRegistry.callbacksMatch(p,s) }.apply { start();join() }
        check(foreignThread==null)
        val env=LuaManager.env as KahluaTableImpl
        val foreignEnvironment=table().apply { delegate.putAll(env.delegate) }
        LuaManager.env=foreignEnvironment
        check(read(p,s)==null && snap()==null && thread.call(checker,arrayOf(helper))==false)
        LuaManager.env=env
        env.metatable=table();check(read(p,s)==null && snap()==null);env.metatable=null
        env.setRewriteTable(table());check(read(p,s)==null && snap()==null);env.setRewriteTable(null)
        run("originalMatch=toolkitEquipEventCallbacksMatch;toolkitEquipEventCallbacksMatch=function(...) return originalMatch(...) end")
        check(thread.call(checker,arrayOf(helper))==false && read(p,s)==null)
        env.rawset("toolkitEquipEventCallbacksMatch",helper)
        run("originalSnapshot=toolkitEquipEventCallbacks;toolkitEquipEventCallbacks=function(...) return originalSnapshot(...) end")
        check(thread.call(checker,arrayOf(snapshot))==false && snap()==null)
        env.rawset("toolkitEquipEventCallbacks",snapshot)
        for (name in listOf("foreign","forwarding","forwardingSnapshot")) {
            val method=if (name=="forwardingSnapshot") QueueEquipEventRegistryChecks::class.java.getMethod(name)
                else QueueEquipEventRegistryChecks::class.java.getMethod(name,Any::class.java,Any::class.java)
            env.rawset("foreignAPI",null)
            LuaManager.exposer.exposeGlobalClassFunction(env,QueueEquipEventRegistryChecks::class.java,method,"foreignAPI")
            val foreign=env.rawget("foreignAPI")
            check(thread.call(checker,arrayOf(foreign))==false)
            if (name!="foreign") check(thread.call(foreign,if (name=="forwardingSnapshot") emptyArray<Any?>() else arrayOf(p,s))==null)
        }
        check(read(p,s)==true && snap()!=null)
        // Real SourceProof and Lua consumer share these native APIs and this VM.
        LuaManager.exposer.exposeGlobalClassFunction(env,QueueLeafTransferFacts::class.java,
            QueueLeafTransferFacts::class.java.getMethod("luaMetatableMatches",Any::class.java,Any::class.java),"toolkitLuaMetatableMatches")
        val root=Path.of(System.getProperty("pz.test.project")).resolve("PZSurvivorToolkit/42/media/lua")
        val proof=thread.call(LuaCompiler.loadstring(Files.readString(root.resolve("shared/PZSurvivorToolkit/SourceProof.lua")),"SourceProof.lua",env),emptyArray<Any?>())
        env.rawset("require",JavaFunction { frame,count ->
            check(count==1 && frame.get(0)=="PZSurvivorToolkit/SourceProof");frame.push(proof);1
        })
        run("PZSurvivorToolkit={}")
        val consumer=thread.call(LuaCompiler.loadstring(Files.readString(root.resolve("client/PZSurvivorToolkit/ActionQueueHandEvents.lua")),"ActionQueueHandEvents.lua",env),emptyArray<Any?>()) as KahluaTableImpl
        val registered=consumer.delegate["registeredCallbacks"]
        val revalidate=consumer.delegate["registeredCallbacksMatch"]
        fun observed() = thread.call(registered,emptyArray<Any?>()) as KahluaTableImpl?
        val currentPrimary=LuaEventManager.AddEvent("OnEquipPrimary")
        currentPrimary.callbacks.add(a);currentPrimary.callbacks.add(b)
        val consumerSnapshot=observed()!!
        check(thread.call(revalidate,arrayOf(consumerSnapshot))==true) { "Real consumer rejected native registry snapshot" }
        currentPrimary.callbacks.remove(b)
        check(thread.call(revalidate,arrayOf(consumerSnapshot))==false) { "Real consumer cached old registry identity" }
        val fresh=observed()!!
        check(thread.call(revalidate,arrayOf(fresh))==true)
        val freshP=fresh.delegate["primary"] as KahluaTableImpl
        freshP.delegate[1.0]=b
        check(thread.call(revalidate,arrayOf(fresh))==false && currentPrimary.callbacks[0]===a)
        freshP.metatable=table();check(thread.call(revalidate,arrayOf(fresh))==null);freshP.metatable=null
        fresh.delegate["extra"]=true;check(thread.call(revalidate,arrayOf(fresh))==null)
        env.rawset("toolkitEquipEventCallbacksMatch",closure("foreign"))
        check(observed()==null && thread.call(revalidate,arrayOf(consumerSnapshot))==null)
        env.rawset("toolkitEquipEventCallbacksMatch",helper)
        check(observed()!=null)
        LuaEventManager.Reset();check(observed()==null && thread.call(revalidate,arrayOf(consumerSnapshot))==null)
        LuaEventManager.register(LuaManager.platform,env)
        val resetSnapshot=observed()!!
        check((resetSnapshot.delegate["primary"] as KahluaTableImpl).delegate.isEmpty()
            && thread.call(revalidate,arrayOf(resetSnapshot))==true)
        println("QUEUE_EQUIP_EVENT_REGISTRY_CHECKS_PASS native_registry=true fresh_identity=true snapshot_copy=true callback_free=true future_authority=false")
    }
}
