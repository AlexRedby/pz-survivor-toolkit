package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field
import java.util.LinkedHashMap
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedQueue
import me.zed_0xff.zombie_buddy.Exposer
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.integration.expose.LuaJavaInvoker
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.JavaFunction
import se.krka.kahlua.vm.KahluaThread
import sun.misc.Unsafe
import zombie.Lua.KahluaNumberConverter
import zombie.Lua.LuaManager
import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.core.ActionManager
import zombie.core.BuildAction
import zombie.core.NetTimedAction
import zombie.core.Transaction.TransactionState
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.fields.character.PlayerID

/**
 * Native Lua entry and actual manager/token objects, with raw unstarted actor/item state.
 * No game, connection, packet, hand setters, action execution or edit permission is exercised.
 */
object QueueNativeHandStateChecks {
    private lateinit var unsafe: Unsafe
    private lateinit var thread: KahluaThread
    private lateinit var helper: Any
    private lateinit var checker: Any
    private var callbacks = 0
    private val actionClass = NetTimedAction::class.java.superclass
    private const val ID: Byte = -126
    private fun field(type: Class<*>, name: String): Field = type.getDeclaredField(name).apply { isAccessible = true }
    private fun put(type: Class<*>, name: String, target: Any, value: Any?) = field(type,name).set(target,value)
    private fun table() = KahluaTableImpl(LinkedHashMap<Any,Any?>())

    class Item : InventoryItem("Base","HandStateProbe","HandStateProbe","HandStateProbe") {
        override fun getID(): Int = error("observation called item ID getter")
        override fun getFullType(): String = error("observation called item type getter")
        override fun getContainer(): ItemContainer? = error("observation called item container getter")
    }
    class ForeignPlayer : IsoPlayer(null)
    class ForeignAction : NetTimedAction()

    @JvmStatic fun forwarding(actor: Any?, transaction: Any?, token: Any?): Any? =
        QueueNativeHandState.read(actor,transaction,token)
    @JvmStatic fun foreign(actor: Any?, transaction: Any?, token: Any?): Any? = error("foreign entry executed")

    private fun actor(id: Short): IsoPlayer = (unsafe.allocateInstance(IsoPlayer::class.java) as IsoPlayer).apply {
        onlineId=id
        // An uninitialized native root deliberately has no item list to scan.
        val root=unsafe.allocateInstance(ItemContainer::class.java) as ItemContainer
        root.parent=this
        put(IsoGameCharacter::class.java,"inventory",this,root)
        check(!GameServer.PlayerToAddressMap.containsKey(this)) { "fixture unexpectedly owns a network connection" }
    }
    private fun root(actor: IsoPlayer) = field(IsoGameCharacter::class.java,"inventory").get(actor) as ItemContainer
    private fun item(id: Int, root: ItemContainer?, type: String="Base.Screwdriver"): InventoryItem =
        (unsafe.allocateInstance(Item::class.java) as Item).apply {
            put(InventoryItem::class.java,"id",this,id)
            put(InventoryItem::class.java,"fullType",this,type)
            put(InventoryItem::class.java,"container",this,root)
        }
    private fun hands(actor: IsoPlayer, primary: InventoryItem?, secondary: InventoryItem?) {
        put(IsoGameCharacter::class.java,"leftHandItem",actor,primary)
        put(IsoGameCharacter::class.java,"rightHandItem",actor,secondary)
    }
    private fun identify(action: Any, actor: IsoPlayer, id: Byte=ID) {
        val owner=field(actionClass,"playerId").get(action) as PlayerID
        owner.setID(actor.onlineId)
        put(PlayerID::class.java,"player",owner,actor)
        put(actionClass,"id",action,id)
        put(actionClass,"state",action,TransactionState.Accept)
    }
    private fun action(actor: IsoPlayer): NetTimedAction = NetTimedAction().apply {
        identify(this,actor)
        type="ISEquipWeaponAction"
        action=table().apply {
            delegate["complete"]=JavaFunction { _,_ -> callbacks++; error("observation executed action complete") }
            delegate["getPrimaryHandItem"]=JavaFunction { _,_ -> callbacks++; error("observation executed Lua getter") }
        }
    }
    private fun state(action: Any, state: TransactionState) = put(actionClass,"state",action,state)
    private fun read(actor: Any?, transaction: Any?=ID.toDouble(), token: Any?): KahluaTableImpl? =
        thread.call(helper,arrayOf(actor,transaction,token)) as KahluaTableImpl?
    private fun snapshot(actor: IsoPlayer, token: String): KahluaTableImpl = read(actor,token=token)
        ?: error("valid server point observation rejected")
    private fun assertObservation(value: KahluaTableImpl, actor: IsoPlayer, token: String) {
        check(value.javaClass==KahluaTableImpl::class.java && value.metatable==null && value.rewriteTable==null)
        check(value.delegate.javaClass==LinkedHashMap::class.java)
        check(value.rawget("schema")==1.0 && value.rawget("scope")=="server-native-active-action-point")
        check(value.rawget("player")==actor.onlineId.toDouble() && value.rawget("transaction")==ID.toDouble())
        check(value.rawget("token")==token && value.rawget("kind")=="ISEquipWeaponAction" && value.rawget("state")=="accepted")
        for (name in listOf("rootMembershipVerified","packetCorrelated","effectsVerified","editAuthority")) {
            check(value.rawget(name)==false) { "$name incorrectly granted by a point observation" }
        }
        check(value.delegate.values.all { it is Boolean || it is Double || it is String }) { "DTO retained a native object" }
    }

    private fun canonical(actor: IsoPlayer, token: String) {
        check(helper is LuaJavaInvoker && checker is LuaJavaInvoker)
        check(thread.call(checker,arrayOf(helper))==true)
        check(thread.call(checker,arrayOf(checker))==false)
        check(QueueNativeHandState.read(actor,ID.toDouble(),token)==null) { "unframed Java read acquired Lua authority" }
        check(!QueueNativeHandState.apiMatches(helper))
        check(thread.pcall(helper,arrayOf(actor,ID.toDouble()))[0]==false) { "omitted argument admitted" }
        check(read(table(),token=token)==null)
        val subclass=unsafe.allocateInstance(ForeignPlayer::class.java)
        check(read(subclass,token=token)==null) { "actor subclass borrowed exact native actor authority" }
        thread.debugOwnerThread=null
        check(read(actor,token=token)==null)
        thread.debugOwnerThread=Thread.currentThread()
        var foreignResult: Any?=true
        Thread { foreignResult=QueueNativeHandState.read(actor,ID.toDouble(),token) }.apply { start();join() }
        check(foreignResult==null)
        val env=LuaManager.env as KahluaTableImpl
        env.metatable=table();check(read(actor,token=token)==null);env.metatable=null
        env.setRewriteTable(table());check(read(actor,token=token)==null);env.setRewriteTable(null)
        val environment=LuaManager.env
        LuaManager.env=table();check(read(actor,token=token)==null);LuaManager.env=environment
        val wrapper=LuaCompiler.loadstring("return function(...) return toolkitOriginalHandState(...) end","hand-wrapper",env)
        env.rawset("toolkitOriginalHandState",helper)
        env.rawset("toolkitNativeHandState",thread.call(wrapper,emptyArray<Any?>()))
        check(thread.call(checker,arrayOf(helper))==false && read(actor,token=token)==null)
        env.rawset("toolkitNativeHandState",helper)
        for (name in listOf("foreign","forwarding")) {
            env.rawset("foreignAPI",null)
            LuaManager.exposer.exposeGlobalClassFunction(env,QueueNativeHandStateChecks::class.java,
                QueueNativeHandStateChecks::class.java.getMethod(name,Any::class.java,Any::class.java,Any::class.java),"foreignAPI")
            val foreign=env.rawget("foreignAPI")
            check(thread.call(checker,arrayOf(foreign))==false)
            if (name=="forwarding") check(thread.call(foreign,arrayOf(actor,ID.toDouble(),token))==null)
        }
        check(thread.call(checker,arrayOf(helper))==true)
        assertObservation(snapshot(actor,token),actor,token)
    }

    @JvmStatic fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        unsafe=field(Unsafe::class.java,"theUnsafe").get(null) as Unsafe
        check(QueueNativeHandState.SUPPORTED && ActionAcknowledgements.SUPPORTED) { "native hand-state ABI unsupported" }
        LuaManager.platform=J2SEPlatform()
        LuaManager.env=LuaManager.platform.newEnvironment()
        val converters=KahluaConverterManager();KahluaNumberConverter.install(converters)
        LuaManager.exposer=LuaManager.Exposer(converters,LuaManager.platform,LuaManager.env)
        Exposer.addClassWithGlobalLuaMethod(QueueNativeHandState::class.java);Exposer.afterExposeAll()
        thread=KahluaThread(LuaManager.platform,LuaManager.env).apply { debugOwnerThread=Thread.currentThread() }
        LuaManager.thread=thread
        helper=LuaManager.env.rawget("toolkitNativeHandState")
        checker=LuaManager.env.rawget("toolkitNativeHandStateApiMatches")
        @Suppress("UNCHECKED_CAST")
        val queue=field(ActionManager::class.java,"actions").get(null) as ConcurrentLinkedQueue<Any>
        val previous=queue.toList()
        val server=GameServer.server;val client=GameClient.client
        queue.clear();GameServer.server=true;GameClient.client=false
        val owned=ArrayList<NetTimedAction>()
        try {
            val actor=actor(17)
            val action=action(actor);owned.add(action);queue.add(action)
            val before=ActionAcknowledgements.pending()!!.toList()
            check(ActionAcknowledgements.token(action)==null)
            check(read(actor,token="00000000-0000-0000-0000-000000000000")==null)
            check(ActionAcknowledgements.token(action)==null && ActionAcknowledgements.pending()!!.toList()==before) {
                "query created an acknowledgement episode"
            }
            // Call the real lifecycle hook, without native action execution or a connection.
            ActionAcknowledgements.started(action)
            val token=ActionAcknowledgements.token(action) ?: error("started did not create a UUID episode")
            check(UUID.fromString(token).toString()==token)
            ActionAcknowledgements.started(action)
            check(ActionAcknowledgements.token(action)==token) { "duplicate started renewed episode" }
            val empty=snapshot(actor,token);assertObservation(empty,actor,token)
            check(empty.rawget("primaryPresent")==false && empty.rawget("secondaryPresent")==false)
            check(empty.rawget("primaryId")==false && empty.rawget("secondaryType")==false && empty.rawget("sameItem")==false)
            val root=root(actor)
            val a=item(101,root);val b=item(102,root)
            hands(actor,a,b)
            val pair=snapshot(actor,token);assertObservation(pair,actor,token)
            check(pair.rawget("primaryId")==101.0 && pair.rawget("secondaryId")==102.0 && pair.rawget("sameItem")==false)
            check(pair.rawget("primaryType")=="Base.Screwdriver" && pair.rawget("primaryContainerIsRoot")==true)
            check(pair.rawget("secondaryContainerIsRoot")==true && pair.rawget("rootMembershipVerified")==false)
            hands(actor,a,a)
            check(snapshot(actor,token).rawget("sameItem")==true)
            val replacement=item(101,root)
            hands(actor,a,replacement)
            val sameId=snapshot(actor,token)
            check(sameId.rawget("primaryId")==sameId.rawget("secondaryId") && sameId.rawget("sameItem")==false) {
                "same ID inferred item identity"
            }
            hands(actor,replacement,replacement)
            check(snapshot(actor,token).rawget("sameItem")==true)
            put(InventoryItem::class.java,"container",replacement,null)
            check(snapshot(actor,token).rawget("primaryContainerIsRoot")==false)
            check(pair.rawget("primaryId")==101.0 && pair.rawget("sameItem")==false) { "old DTO changed after native writes" }
            canonical(actor,token)
            for (number in listOf<Any?>(null,0.0,128.0,-129.0,1.5,Double.NaN,Double.POSITIVE_INFINITY,ID.toInt(),ID.toString(),-125.0)) {
                check(read(actor,number,token)==null) { "invalid transaction admitted: $number" }
            }
            for (bad in listOf<Any?>(null,false,table(),"",token.dropLast(1),"x".repeat(36),UUID.randomUUID().toString())) {
                check(read(actor,token=bad)==null) { "wrong token admitted" }
            }
            GameServer.server=false;check(read(actor,token=token)==null);GameServer.server=true
            GameClient.client=true;check(read(actor,token=token)==null);GameClient.client=false
            actor.onlineId=(-1).toShort();check(read(actor,token=token)==null);actor.onlineId=17
            val owner=field(actionClass,"playerId").get(action) as PlayerID
            owner.setID(18);check(read(actor,token=token)==null);owner.setID(17)
            for (status in TransactionState.entries.filter { it!=TransactionState.Accept }) {
                state(action,status);check(read(actor,token=token)==null) { "nonaccepted action observed: $status" }
            }
            state(action,TransactionState.Accept)
            val duplicate=action(actor);owned.add(duplicate);queue.add(duplicate)
            check(read(actor,token=token)==null) { "duplicate active action admitted" }
            state(duplicate,TransactionState.Done);check(read(actor,token=token)!=null)
            state(duplicate,TransactionState.Reject);check(read(actor,token=token)!=null);queue.remove(duplicate)
            val other=actor(18);val foreign=action(other);owned.add(foreign);queue.add(foreign)
            check(read(actor,token=token)!=null) { "independent foreign action blocked actor" }
            val foreignOwner=field(actionClass,"playerId").get(foreign) as PlayerID
            foreignOwner.setID(17);check(read(actor,token=token)==null) { "foreign same network ID admitted" };queue.remove(foreign)
            val inherited=unsafe.allocateInstance(ForeignAction::class.java) as ForeignAction
            put(actionClass,"playerId",inherited,owner);identify(inherited,actor);queue.remove(action);queue.add(inherited)
            check(read(actor,token=token)==null) { "native action subclass admitted" };queue.remove(inherited);queue.add(action)
            val build=BuildAction();identify(build,actor);queue.add(build)
            check(read(actor,token=token)==null) { "foreign action kind admitted" };queue.remove(build)
            root.parent=null;check(read(actor,token=token)==null);root.parent=actor
            root.containingItem=a;check(read(actor,token=token)==null);root.containingItem=null
            put(IsoGameCharacter::class.java,"inventory",actor,null);check(read(actor,token=token)==null)
            put(IsoGameCharacter::class.java,"inventory",actor,root)
            action.type="";check(read(actor,token=token)==null);action.type="ISEquipWeaponAction"
            val lua=action.action;action.action=null;check(read(actor,token=token)==null);action.action=lua
            queue.remove(action);check(read(actor,token=token)==null);queue.add(action)
            state(action,TransactionState.Done)
            ActionAcknowledgements.settled(arrayListOf<Any>(action),false)
            check(ActionAcknowledgements.token(action)==null && read(actor,token=token)==null)
            val reused=action(actor);owned.add(reused);queue.add(reused);ActionAcknowledgements.started(reused)
            val next=ActionAcknowledgements.token(reused) ?: error("byte reuse did not create new episode")
            check(next!=token && read(actor,token=token)==null && read(actor,token=next)!=null) { "old episode survived byte reuse" }
            ActionAcknowledgements.settled(arrayListOf<Any>(reused),true)
            check(ActionAcknowledgements.token(reused)==null && read(actor,token=next)==null) { "canceled episode retained observation" }
            check(callbacks==0) { "observation invoked gameplay callback" }
            println("QUEUE_NATIVE_HAND_STATE_CHECKS_PASS canonical_native_lua=true active_uuid_episode=true raw_metadata=true callbacks=false packet_correlated=false root_membership_verified=false effects_verified=false edit_authority=false game_started=false")
        } finally {
            GameServer.server=true
            ActionAcknowledgements.settled(ArrayList<Any>(owned),true)
            queue.clear();queue.addAll(previous)
            GameServer.server=server;GameClient.client=client
        }
    }
}
