package net.alexredby.pztoolkitjavapatches

import java.util.ArrayList
import sun.misc.Unsafe
import zombie.characters.IsoPlayer
import zombie.characters.IsoGameCharacter
import zombie.inventory.ItemContainer
import zombie.inventory.InventoryItem
import zombie.inventory.types.ComboItem
import zombie.inventory.types.HandWeapon
import zombie.inventory.types.InventoryContainer
import zombie.entity.GameEntity
import zombie.entity.ComponentContainer
import zombie.entity.Component
import zombie.entity.ComponentType
import zombie.entity.components.script.EntityScriptInfo
import zombie.entity.util.Array as EntityArray
import zombie.scripting.objects.Item
import zombie.scripting.objects.ItemTag
import java.util.LinkedHashMap
import me.zed_0xff.zombie_buddy.Exposer
import me.zed_0xff.zombie_buddy.PatchEngine
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.integration.annotations.LuaMethod
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.stdlib.BaseLib
import se.krka.kahlua.stdlib.TableLib
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.KahluaThread
import se.krka.kahlua.vm.LuaClosure
import zombie.Lua.Event
import zombie.Lua.KahluaNumberConverter
import zombie.Lua.LuaEventManager
import zombie.Lua.LuaManager

/** Actual woven native Event.trigger; no game actor or mod callback is needed. */
object EquipEventDispatchChecks {
    private val args = emptyArray<Any?>()
    private lateinit var nested: Event
    private lateinit var mutableEvent: Event
    @JvmStatic @LuaMethod(name="renameDispatchForTest",global=true)
    fun rename() { mutableEvent.name="DifferentEvent" }
    @JvmStatic @LuaMethod(name="dispatchNestedEquipForTest",global=true)
    fun nested() { nested.trigger(LuaManager.env,LuaManager.caller,args) }
    private fun compile(text: String) = LuaCompiler.loadstring(text,"dispatch-check",LuaManager.env)
    private fun run(text: String): Any? = LuaManager.thread.call(compile(text),args)
    private fun checkLua(text: String) { check(run(text) == true) { text } }
    @JvmStatic fun main(unused: Array<String>) {
        check(EquipEventDispatchLogic.SUPPORTED)
        LuaManager.platform=J2SEPlatform()
        LuaManager.env=LuaManager.platform.newEnvironment()
        val converters=KahluaConverterManager();KahluaNumberConverter.install(converters)
        LuaManager.exposer=LuaManager.Exposer(converters,LuaManager.platform,LuaManager.env)
        Exposer.addClassWithGlobalLuaMethod(EquipEventDispatchLogic::class.java)
        Exposer.addClassWithGlobalLuaMethod(EquipEventDispatchChecks::class.java)
        Exposer.afterExposeAll()
        val env=LuaManager.env as KahluaTableImpl
        val thread=KahluaThread(LuaManager.platform,env).apply { debugOwnerThread=Thread.currentThread() }
        LuaManager.thread=thread
        val methods=arrayOf(
            "instanceof" to LuaManager.GlobalObject::class.java.getMethod("instof",Any::class.java,String::class.java),
            "getPlayer" to LuaManager.GlobalObject::class.java.getMethod("getPlayer"),
            "getSpecificPlayer" to LuaManager.GlobalObject::class.java.getMethod("getSpecificPlayer",Int::class.javaPrimitiveType),
            "isMultiplayer" to LuaManager.GlobalObject::class.java.getMethod("isMultiplayer"),
            "isClient" to LuaManager.GlobalObject::class.java.getMethod("isClient"),
            "isServer" to LuaManager.GlobalObject::class.java.getMethod("isServer"),
            "getClassSimpleName" to LuaManager.GlobalObject::class.java.getMethod("getClassSimpleName",Any::class.java),
        )
        LuaManager.exposer.setExposed(ItemTag::class.java)
        LuaManager.exposer.exposeLikeJava(ItemTag::class.java,env)
        // Match the final registration step of native Exposer.exposeAll.
        // Manual alias registration previously hid isType versus instof.
        LuaManager.exposer.exposeGlobalFunctions(LuaManager.GlobalObject())
        checkLua("return toolkitEquipEventDispatchApiMatches(toolkitEquipEventDispatchIdle) and toolkitEquipEventDispatchApiMatches(toolkitEquipGlobalsTrusted) and toolkitEquipEventDispatchApiMatches(toolkitEquipNativeQuiet) and toolkitEquipEventDispatchApiMatches(toolkitEquipNativePreparedQuiet)")
        checkLua("return toolkitEquipGlobalsTrusted() and toolkitEquipEventDispatchIdle(1)==nil and toolkitEquipGlobalsTrusted(1)==false")
        checkLua("return toolkitEquipEventDispatchIdle()==nil")
        // A native call before patching must not arm the observer.
        val startup=Event("OnGameStart",0)
        check(!startup.trigger(env,LuaManager.caller,args))
        checkLua("return toolkitEquipEventDispatchIdle()==nil")
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches",EquipEventDispatchChecks::class.java.classLoader)
        check(!startup.trigger(env,LuaManager.caller,args))
        checkLua("return toolkitEquipEventDispatchIdle()==true")
        check(EquipEventDispatchLogic.idle()==null && !EquipEventDispatchLogic.globalsTrusted()) { "direct JVM calls gained API authority" }
        val primary=Event("OnEquipPrimary",1)
        nested=Event("OnEquipSecondary",2)
        env.delegate["calls"]=0.0
        nested.callbacks.add(compile("calls=calls+1;assert(toolkitEquipEventDispatchIdle()==false)"))
        primary.callbacks.add(compile("assert(toolkitEquipEventDispatchIdle()==false);dispatchNestedEquipForTest();assert(toolkitEquipEventDispatchIdle()==false);calls=calls+1"))
        check(primary.trigger(null,LuaManager.caller,args))
        checkLua("return calls==2 and toolkitEquipEventDispatchIdle()==true")
        reusableDispatchSlots(env)
        // Even an Error escaping native callback iteration restores the scope.
        val broken=Event("OnEquipPrimary",3)
        val failure=AssertionError("dispatch sentinel")
        val callbacks=object:ArrayList<LuaClosure>() {
            override fun isEmpty()=false
            override val size:Int get()=1
            override fun get(index:Int):LuaClosure=throw failure
        }
        Event::class.java.getDeclaredField("callbacks").apply { isAccessible=true }.set(broken,callbacks)
        check(runCatching { broken.trigger(env,LuaManager.caller,args) }.exceptionOrNull() === failure)
        checkLua("return toolkitEquipEventDispatchIdle()==true and calls==2")
        // Native off-thread queue captures an Event identity. An obsolete map
        // identity is still unsafe until native RunQueuedEvents drains it.
        val mapField=LuaEventManager::class.java.getDeclaredField("EventMap").apply { isAccessible=true }
        @Suppress("UNCHECKED_CAST") val map=mapField.get(null) as MutableMap<String,Event>
        val old=Event("OnEquipPrimary",4)
        old.callbacks.add(compile("assert(toolkitEquipEventDispatchIdle()==false);calls=calls+1"))
        synchronized(map) { map["OnEquipPrimary"]=old }
        val producer=Thread { LuaEventManager.triggerEvent("OnEquipPrimary") };producer.start();producer.join()
        synchronized(map) { map["OnEquipPrimary"]=Event("OnEquipPrimary",5) }
        checkLua("return toolkitEquipEventDispatchIdle()==false and calls==2")
        LuaEventManager.RunQueuedEvents()
        checkLua("return toolkitEquipEventDispatchIdle()==true and calls==3")
        // Mutable labels do not hide an active hand identity. An obsolete
        // renamed event is also rejected because no current registry owns it.
        mutableEvent=Event("DifferentEvent",7)
        mutableEvent.callbacks.add(compile("assert(toolkitEquipEventDispatchIdle()==false);calls=calls+1"))
        synchronized(map) { map["OnEquipPrimary"]=mutableEvent }
        check(mutableEvent.trigger(env,LuaManager.caller,args))
        checkLua("return toolkitEquipEventDispatchIdle()==true and calls==4")
        synchronized(map) { map["OnEquipPrimary"]=Event("OnEquipPrimary",8) }
        check(mutableEvent.trigger(env,LuaManager.caller,args))
        checkLua("return toolkitEquipEventDispatchIdle()==true and calls==5")
        val tick=Event("OnTick",9)
        tick.callbacks.add(compile("assert(toolkitEquipEventDispatchIdle()==true)"))
        synchronized(map) { map["OnTick"]=tick }
        check(tick.trigger(env,LuaManager.caller,args))
        mutableEvent=Event("OnTick",10)
        mutableEvent.callbacks.add(compile("renameDispatchForTest();assert(toolkitEquipEventDispatchIdle()==false)"))
        synchronized(map) { map["OnTick"]=mutableEvent }
        check(mutableEvent.trigger(env,LuaManager.caller,args))
        // ANY pending event blocks without scanning or executing its contents.
        env.delegate["unrelatedCalls"]=0.0
        val otherEvent=Event("OnToolkitDispatchCheck",6)
        otherEvent.callbacks.add(compile("unrelatedCalls=unrelatedCalls+1;assert(toolkitEquipEventDispatchIdle()==false)"))
        synchronized(map) { map["OnToolkitDispatchCheck"]=otherEvent }
        val unrelated=Thread { LuaEventManager.triggerEvent("OnToolkitDispatchCheck") };unrelated.start();unrelated.join()
        checkLua("return toolkitEquipEventDispatchIdle()==false and calls==5 and unrelatedCalls==0")
        LuaEventManager.RunQueuedEvents()
        checkLua("return toolkitEquipEventDispatchIdle()==true and calls==5 and unrelatedCalls==1")
        val nativeInstanceof=env.delegate["instanceof"]
        LuaManager.exposer.exposeGlobalClassFunction(env,LuaManager.GlobalObject::class.java,
            LuaManager.GlobalObject::class.java.getMethod("isType",Any::class.java,String::class.java),"instanceof")
        checkLua("return toolkitEquipGlobalsTrusted()==false")
        env.delegate["instanceof"]=nativeInstanceof
        checkLua("return toolkitEquipGlobalsTrusted()==true")
        val luaTags=env.delegate["ItemTag"] as KahluaTableImpl
        val rod=luaTags.delegate["FISHING_ROD"]
        luaTags.delegate["FISHING_ROD"]=ItemTag.AMMO
        checkLua("return toolkitEquipGlobalsTrusted()==false")
        luaTags.delegate["FISHING_ROD"]=rod
        luaTags.metatable=KahluaTableImpl(LinkedHashMap<Any,Any?>())
        checkLua("return toolkitEquipGlobalsTrusted()==false")
        luaTags.metatable=null
        checkLua("return toolkitEquipGlobalsTrusted()==true")
        // Exact standard-library singleton/index proof rejects same-class
        // wrong-index values and fresh public-constructor lookalikes.
        for ((name,bad) in arrayOf(
            "pcall" to BaseLib(3), "type" to BaseLib(3), "tostring" to BaseLib(4),
            "select" to BaseLib(0), "pairs" to TableLib(7), "ipairs" to TableLib(7),
        )) {
            val saved=env.delegate[name];env.delegate[name]=bad
            checkLua("return toolkitEquipGlobalsTrusted()==false")
            env.delegate[name]=saved
        }
        for ((name,_) in methods) {
            val saved=env.delegate[name]
            env.delegate[name]=JavaFunction { _,_->error("foreign global was executed") }
            checkLua("return toolkitEquipGlobalsTrusted()==false")
            env.delegate[name]=saved
        }
        val api=env.delegate["toolkitEquipEventDispatchIdle"]
        env.delegate["copiedDispatch"]=api;env.delegate["toolkitEquipEventDispatchIdle"]=JavaFunction { _,_->0 }
        checkLua("return toolkitEquipEventDispatchApiMatches(copiedDispatch)==false and copiedDispatch()==nil")
        env.delegate["toolkitEquipEventDispatchIdle"]=api
        env.metatable=KahluaTableImpl(LinkedHashMap<Any,Any?>())
        checkLua("return toolkitEquipEventDispatchIdle()==nil and toolkitEquipGlobalsTrusted()==false")
        env.metatable=null
        thread.debugOwnerThread=Thread("foreign owner")
        checkLua("return toolkitEquipEventDispatchIdle()==nil and toolkitEquipGlobalsTrusted()==false")
        thread.debugOwnerThread=Thread.currentThread()
        val savedEnv=LuaManager.env
        val unsafe=compile("return toolkitEquipEventDispatchIdle()==nil")
        LuaManager.env=KahluaTableImpl(LinkedHashMap<Any,Any?>())
        check(thread.call(unsafe,args) == true)
        LuaManager.env=savedEnv
        checkLua("return toolkitEquipEventDispatchIdle()==true and toolkitEquipGlobalsTrusted()==true and calls==5")
        nativeQuietChecks(env,thread)
        val fresh=LuaManager.platform.newEnvironment() as KahluaTableImpl
        fresh.delegate.putAll(env.delegate)
        LuaManager.env=fresh
        LuaManager.thread=KahluaThread(LuaManager.platform,fresh).apply { debugOwnerThread=Thread.currentThread() }
        checkLua("return toolkitEquipEventDispatchIdle()==nil")
        check(!startup.trigger(fresh,LuaManager.caller,args))
        checkLua("return toolkitEquipEventDispatchIdle()==true")
        println("EQUIP_EVENT_DISPATCH_CHECKS_PASS woven_native=true nested=true throwable_exit=true queued_old_event=true globals_metadata_only=true")
    }
    private fun reusableDispatchSlots(env: KahluaTableImpl) {
        val stateField=EquipEventDispatchLogic::class.java.getDeclaredField("states").apply { isAccessible=true }
        val state=(stateField.get(null) as ThreadLocal<*>).get()!!
        val slotsField=state.javaClass.getDeclaredField("slots").apply { isAccessible=true }
        fun slots()=slotsField.get(state) as Array<*>
        fun cleared() {
            for (scope in slots().filterNotNull()) {
                for (name in arrayOf("event","name","owner")) {
                    check(scope.javaClass.getDeclaredField(name).apply { isAccessible=true }.get(scope)==null) {
                        "Retired dispatch kept a strong $name reference"
                    }
                }
            }
        }
        val before=slots().clone()
        val retired=Event("retired-event",20)
        check(!retired.trigger(env,LuaManager.caller,args))
        cleared()
        val saved=nested
        nested=Event("OnEquipSecondary",21)
        nested.callbacks.add(compile("assert(toolkitEquipEventDispatchIdle()==false)"))
        val outer=Event("OnEquipPrimary",22)
        outer.callbacks.add(compile("dispatchNestedEquipForTest();assert(toolkitEquipEventDispatchIdle()==false)"))
        repeat(128) { check(outer.trigger(env,LuaManager.caller,args));check(!retired.trigger(env,LuaManager.caller,args)) }
        check(slots().indices.all { slots()[it] === before[it] }) { "Warmed event depth allocated new Scope objects" }
        cleared()
        nested=saved
    }

    private fun nativeQuietChecks(env: KahluaTableImpl, thread: KahluaThread) {
        val unsafe=Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible=true }.get(null) as Unsafe
        fun set(type: Class<*>, key: String, owner: Any, value: Any?) = type.getDeclaredField(key).apply { isAccessible=true }.set(owner,value)
        val actor=unsafe.allocateInstance(IsoPlayer::class.java) as IsoPlayer
        val root=unsafe.allocateInstance(ItemContainer::class.java) as ItemContainer
        root.parent=actor
        val animals=ArrayList<Any>()
        set(IsoPlayer::class.java,"attachedAnimals",actor,animals)
        set(IsoGameCharacter::class.java,"inventory",actor,root)
        val script=unsafe.allocateInstance(Item::class.java) as Item
        val tags=HashSet<ItemTag>()
        set(Item::class.java,"itemTags",script,tags)
        val one=unsafe.allocateInstance(ComboItem::class.java) as ComboItem
        val two=unsafe.allocateInstance(HandWeapon::class.java) as HandWeapon
        one.id=1;two.id=2
        for (item in arrayOf(one,two)) {
            set(InventoryItem::class.java,"container",item,root)
            set(InventoryItem::class.java,"scriptItem",item,script)
        }
        val rows=KahluaTableImpl(LinkedHashMap<Any,Any?>())
        rows.delegate[1.0]=one;rows.delegate[2.0]=two
        val quiet=env.delegate["toolkitEquipNativeQuiet"]
        fun value(actorValue: Any?=actor, values: Any?=rows): Any? = thread.call(quiet,arrayOf(actorValue,values))
        check(value()==true)
        check(EquipEventDispatchLogic.nativeQuiet(actor,rows)==null)
        val ordered=KahluaTableImpl(LinkedHashMap<Any,Any?>(4,0.75f,true).apply { put(2.0,two);put(1.0,one) })
        val order=ordered.delegate.keys.toList()
        check(value(values=ordered)==true && ordered.delegate.keys.toList()==order) { "quiet observation reordered input map" }
        animals.add(Any());check(value()==false);animals.clear()
        set(IsoPlayer::class.java,"attachedAnimals",actor,object:ArrayList<Any>() { override fun isEmpty():Boolean=error("foreign animal callback executed") })
        check(value()==null);set(IsoPlayer::class.java,"attachedAnimals",actor,animals)
        tags.add(ItemTag.FISHING_ROD);check(value()==false);tags.clear()
        set(Item::class.java,"itemTags",script,object:HashSet<ItemTag>() { override fun contains(element:ItemTag):Boolean=error("foreign tag callback executed") })
        check(value()==null);set(Item::class.java,"itemTags",script,tags)
        set(GameEntity::class.java,"addedToEntityManager",one,true);check(value()==false)
        set(GameEntity::class.java,"addedToEntityManager",one,false)
        val contents=unsafe.allocateInstance(ComponentContainer::class.java) as ComponentContainer
        val list=EntityArray<Component>(false,4)
        val indexed=arrayOfNulls<Component>(100)
        set(ComponentContainer::class.java,"componentList",contents,list)
        set(ComponentContainer::class.java,"componentArray",contents,indexed)
        set(GameEntity::class.java,"components",one,contents)
        check(value()==true)
        val component=unsafe.allocateInstance(EntityScriptInfo::class.java) as EntityScriptInfo
        set(Component::class.java,"componentType",component,ComponentType.Script)
        set(Component::class.java,"owner",component,one)
        list.add(component);indexed[ComponentType.Script.GetID().toInt()]=component
        check(value()==true) { "native Script-only manager short circuit was not recognized" }
        set(Component::class.java,"owner",component,two);check(value()==false);set(Component::class.java,"owner",component,one)
        val counterfeit=unsafe.allocateInstance(ComponentType::class.java) as ComponentType
        val nameOffset=unsafe.objectFieldOffset(Enum::class.java.getDeclaredField("name"))
        unsafe.putObject(counterfeit,nameOffset,"Script")
        val fakeId=(ComponentType.Script.GetID()+1).toShort()
        ComponentType::class.java.getDeclaredField("id").apply { isAccessible=true }.setShort(counterfeit,fakeId)
        set(Component::class.java,"componentType",component,counterfeit)
        indexed[ComponentType.Script.GetID().toInt()]=null;indexed[fakeId.toInt()]=component
        check(value()==false) { "Same-name counterfeit component type borrowed native Script authority" }
        indexed[fakeId.toInt()]=null;indexed[ComponentType.Script.GetID().toInt()]=component
        set(Component::class.java,"componentType",component,ComponentType.Attributes);check(value()==false)
        set(Component::class.java,"componentType",component,ComponentType.Script)
        list.add(component);check(value()==false);list.size=1
        indexed[ComponentType.Script.GetID().toInt()]=null;check(value()==false)
        indexed[ComponentType.Script.GetID().toInt()]=component
        rows.delegate[2.0]=one;check(value()==null);rows.delegate[2.0]=two
        two.id=1;check(value()==null);two.id=2
        rows.delegate[3.0]=two;rows.delegate[4.0]=two;check(value()==null);rows.delegate.remove(4.0);rows.delegate.remove(3.0)
        rows.delegate.remove(1.0);rows.delegate[3.0]=one;check(value()==null);rows.delegate.remove(3.0);rows.delegate[1.0]=one
        set(InventoryItem::class.java,"container",two,null);check(value()==null);set(InventoryItem::class.java,"container",two,root)
        check(value(actorValue=rows)==null)
        rows.metatable=KahluaTableImpl(LinkedHashMap<Any,Any?>());check(value()==null);rows.metatable=null
        check(value(values=KahluaTableImpl(LinkedHashMap<Any,Any?>()))==null)
        check(value()==true)
        val source=unsafe.allocateInstance(ItemContainer::class.java) as ItemContainer
        val bag=unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        source.containingItem=bag
        val prepared=env.delegate["toolkitEquipNativePreparedQuiet"]
        fun pending(location: Any?=source): Any? = thread.call(prepared,arrayOf(actor,rows,location))
        for(item in arrayOf(one,two))set(InventoryItem::class.java,"container",item,source)
        check(pending()==true && value()==null) { "prepared proof changed root ownership semantics" }
        check(EquipEventDispatchLogic.nativePreparedQuiet(actor,rows,source)==null)
        check(pending(root)==null && pending(rows)==null && pending(null)==null)
        source.parent=actor;check(pending()==null);source.parent=null
        source.containingItem=null;check(pending()==null);source.containingItem=bag
        tags.add(ItemTag.FISHING_ROD);check(pending()==false);tags.clear()
        set(Component::class.java,"componentType",component,ComponentType.Attributes);check(pending()==false)
        set(Component::class.java,"componentType",component,ComponentType.Script)
        set(InventoryItem::class.java,"container",two,root);check(pending()==null)
        set(InventoryItem::class.java,"container",two,source)
        check(pending()==true)
        for(item in arrayOf(one,two))set(InventoryItem::class.java,"container",item,root)
        check(value()==true)
    }

}
