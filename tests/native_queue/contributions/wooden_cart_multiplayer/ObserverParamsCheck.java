import java.util.*;
import java.lang.reflect.*;
import net.alexredby.cartlab.Main;
/** Actual native jar plus diagnostic instrumentation, without a game/world/socket. */
public final class ObserverParamsCheck {
    public static final class Agent { public static void premain(String args,java.lang.instrument.Instrumentation instrumentation){Main.observerParamsInstall(instrumentation);ObserverParamsCheck.installTestSeed(instrumentation);} }
    private static boolean testSeedInstalled;
    /** Test-only load hook: never installed by the normal diagnostic bootstrap. */
    public static synchronized void installTestSeed(java.lang.instrument.Instrumentation instrumentation){
        if(testSeedInstalled)return;
        new net.bytebuddy.agent.builder.AgentBuilder.Default().disableClassFormatChanges().with(net.bytebuddy.agent.builder.AgentBuilder.DescriptionStrategy.Default.POOL_ONLY).with(net.bytebuddy.agent.builder.AgentBuilder.RedefinitionStrategy.RETRANSFORMATION).type(net.bytebuddy.matcher.ElementMatchers.named("zombie.ai.State")).transform((builder,type,loader,module,domain)->builder.visit(net.bytebuddy.asm.Advice.to(SeedPendingAdvice.class).on(net.bytebuddy.matcher.ElementMatchers.named("loadFrom")))).installOn(instrumentation);testSeedInstalled=true;
    }
    public static boolean seedPending; public static Main.ObserverPacket seedInput; public static long seedApply; public static Object seededPending;
    public static final class SeedPendingAdvice {@net.bytebuddy.asm.Advice.OnMethodExit public static void exit(@net.bytebuddy.asm.Advice.Argument(1) zombie.characters.IsoGameCharacter actor)throws Exception{if(ObserverParamsCheck.seedPending)ObserverParamsCheck.seed(actor);}}
    public static void seed(zombie.characters.IsoGameCharacter actor)throws Exception{
        var applyingField=Main.class.getDeclaredField("observerApplying");applyingField.setAccessible(true);var applying=(Main.ObserverApply)((ThreadLocal<?>)applyingField.get(null)).get();check(applying!=null&&applying.input()==seedInput,"Exact original native apply missing at test seed");seedApply=applying.generation();
        var map=raw((Owner)actor);var life=Main.observerParamsInspect(map);var snapshot=helper("opSnapshot",Main.OPLife.class,boolean.class).invoke(null,life,true);check(snapshot!=null,"Partial native snapshot refused");
        var ctor=Main.OPCommit.class.getDeclaredConstructor(Main.ObserverPacket.class,long.class,long.class,Main.OPSnapshot.class);ctor.setAccessible(true);var source=ctor.newInstance(seedInput,seedApply,life.revision,snapshot);var loaded=Main.OPCommit.class.getDeclaredField("loadedParamMask");loaded.setAccessible(true);loaded.setInt(source,119);
        var pendingType=Class.forName("net.alexredby.cartlab.Main$OPPending");var pendingCtor=pendingType.getDeclaredConstructor(Main.OPCommit.class);pendingCtor.setAccessible(true);seededPending=pendingCtor.newInstance(source);var pending=Main.OPLife.class.getDeclaredField("pending");pending.setAccessible(true);pending.set(life,seededPending);
    }
    public static final class Network extends zombie.characters.component.NetworkComponent {public boolean isRemote(){return true;}public void updateNetworkAI(){}public zombie.characters.NetworkCharacterAI getNetworkAI(){return ((Owner)getECSOwnerEntity()).ai;}}
    public static final class AI extends zombie.characters.NetworkPlayerAI {AI(Owner owner){super(owner);}public zombie.characters.IsoPlayer getRelatedPlayer(){return (zombie.characters.IsoPlayer)getCharacter();}public zombie.debug.options.Multiplayer.DebugFlagsOG.IsoGameCharacterOG getBooleanDebugOptions(){return null;}}

    public static final class Owner extends zombie.characters.IsoPlayer {
        HashMap<Class<? extends zombie.characters.ecs.ECSComponent>,zombie.characters.ecs.ECSComponent> components;
        Stack<zombie.characters.CharacterTimedActions.BaseAction> actions; zombie.characters.NetworkPlayerAI ai;
        Owner(){super(null,null,0,0,0);}
        @Override public HashMap<Class<? extends zombie.characters.ecs.ECSComponent>,zombie.characters.ecs.ECSComponent> getECSComponentMap(){return components;}
        @Override public Stack<zombie.characters.CharacterTimedActions.BaseAction> getCharacterActions(){return actions;}
        @Override public float getX(){return 10f;} @Override public float getY(){return 20f;} @Override public float getZ(){return 0f;}
        @Override public float getVariableFloat(String name,float fallback){return fallback;}
        @Override public zombie.characters.NetworkPlayerAI getNetworkCharacterAI(){return ai;}
        @Override public zombie.inventory.InventoryItem getPrimaryHandItem(){return null;} @Override public zombie.inventory.InventoryItem getSecondaryHandItem(){return null;}
        @Override public void resetModelNextFrame(){} @Override public void setHideWeaponModel(boolean value){}
        @Override public zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot setVariable(String key,String value){return null;}
        @Override public zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot setVariable(String key,boolean value){return null;}


    }
    private static final sun.misc.Unsafe UNSAFE;
    static {try{var field=sun.misc.Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);UNSAFE=(sun.misc.Unsafe)field.get(null);}catch(Exception e){throw new ExceptionInInitializerError(e);}}
    static void check(boolean value,String message){if(!value)throw new AssertionError(message);}
    static Object field(Object object,Class<?> clazz,String name)throws Exception{var field=clazz.getDeclaredField(name);field.setAccessible(true);return field.get(object);}
    static Method helper(String name,Class<?>... types)throws Exception{var method=Main.class.getDeclaredMethod(name,types);method.setAccessible(true);return method;}
    static Owner owner()throws Exception{var owner=(Owner)UNSAFE.allocateInstance(Owner.class);owner.components=new HashMap<>();owner.actions=new Stack<>();var component=new zombie.characters.component.StateMachineComponent(owner);component.setECSOwnerEntity(owner);check(owner.getStateMachineComponent()==component,"Native component attachment failed");return owner;}
    @SuppressWarnings("unchecked") static Map<zombie.ai.State.Param<?>,Object> raw(Owner owner)throws Exception{return (Map<zombie.ai.State.Param<?>,Object>)((Map<?,?>)field(owner.getStateMachineComponent(),zombie.characters.component.StateMachineComponent.class,"stateMachineParams")).get(zombie.ai.states.PlayerActionsState.class);}
    static zombie.network.fields.Variables variables()throws Exception{
        var vars=new zombie.network.fields.Variables();var bb=java.nio.ByteBuffer.allocate(256);bb.putInt(1);zombie.GameWindow.WriteString(bb,"PerformingAction");zombie.GameWindow.WriteString(bb,"CartPickup");bb.flip();vars.parse(new zombie.core.network.ByteBufferReader(bb),null);check(!bb.hasRemaining(),"Variables parse left bytes");return vars;
    }
    static void fill(Owner owner,zombie.network.fields.Variables vars){owner.set(zombie.ai.states.PlayerActionsState.STAGE,zombie.ai.State.Stage.Enter);owner.set(zombie.ai.states.PlayerActionsState.VARIABLES,vars);owner.set(zombie.ai.states.PlayerActionsState.PRIMARY,"Cart");owner.set(zombie.ai.states.PlayerActionsState.SECONDARY,"");owner.set(zombie.ai.states.PlayerActionsState.OVERRIDE,true);owner.set(zombie.ai.states.PlayerActionsState.RELOAD_SPEED,1f);owner.set(zombie.ai.states.PlayerActionsState.SITONGROUND,false);}
    static Main.OPCommit artificialCommit(Main.OPLife life)throws Exception{Object snapshot=helper("opSnapshot",Main.OPLife.class).invoke(null,life);check(snapshot!=null,"Fresh native map failed deep snapshot");var constructor=Main.OPCommit.class.getDeclaredConstructor(Main.ObserverPacket.class,long.class,long.class,Main.OPSnapshot.class);constructor.setAccessible(true);var committed=constructor.newInstance(null,17L,life.revision,snapshot);life.committed=committed;return committed;}
    static boolean unchanged(Main.OPLife life,Main.OPCommit committed,Owner owner)throws Exception{return (boolean)helper("opUnchanged",Main.OPLife.class,Main.OPCommit.class,zombie.characters.IsoGameCharacter.class).invoke(null,life,committed,owner);}
    public static void main(String[] args)throws Exception{
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        if(args.length>=2&&args[0].equals("late-load")){
            var loader=Class.forName("me.zed_0xff.zombie_buddy.Loader");var phase=Class.forName("me.zed_0xff.zombie_buddy.Loader$Phase");var mainField=phase.getDeclaredField("MAIN");mainField.setAccessible(true);var main=mainField.get(null);var load=loader.getDeclaredMethod("loadJar",java.nio.file.Path.class,String.class,String.class,phase);load.setAccessible(true);
            check(Boolean.TRUE.equals(load.invoke(null,java.nio.file.Path.of(args[1]),"net.alexredby.cartlab",null,main)),"Faithful MAIN phase CartLab load failed");args=java.util.Arrays.copyOfRange(args,2,args.length);System.out.println("OBSERVER_PARAMS_LATE_BOOTSTRAP_PASS (Rand initialized by test entry; real Loader.loadJar MAIN before first native actor/map)");
        }

        check(Main.observerParamsHealthy(),"Premain installer failed");
        if(args.length>0&&args[0].equals("fail-cleanup")){
            var parent=Main.observerParamsEnter("check-parent",null,new Object[]{new Object()});
            var child=Main.observerParamsEnter("check-child",null,new Object[]{new Object()});
            check(Main.observerParamsEnter("zombie.ai.State.loadFrom(Ljava/util/Map;Lzombie/characters/IsoGameCharacter;)V",zombie.ai.states.PlayerActionsState.instance(),new Object[]{null,"wrong-type"})==null,"Invalid diagnostic entry accepted");
            Main.observerParamsExit(child,null);Main.observerParamsExit(parent,null);
            check(!Main.observerParamsHealthy(),"Diagnostic failure not sealed");
            for(String name:new String[]{"opFrames","opLoads","opConsumers"}){var f=Main.class.getDeclaredField(name);f.setAccessible(true);check(((ThreadLocal<?>)f.get(null)).get()==null,"Failure retained strong ThreadLocal: "+name);}
            System.out.println("OBSERVER_PARAMS_FAIL_CLEANUP_PASS");return;
        }

        if(args.length>0&&args[0].equals("pending-default")){
            if(!testSeedInstalled){var instrumentation=me.zed_0xff.zombie_buddy.Loader.class.getDeclaredField("g_instrumentation");instrumentation.setAccessible(true);installTestSeed((java.lang.instrument.Instrumentation)instrumentation.get(null));}
            var source=owner();var action=new zombie.characters.CharacterTimedActions.BaseAction(source);action.setOverrideHandModelsString("Cart",null,false);source.actions.add(action);var outgoing=new zombie.network.packets.actions.StatePacket();outgoing.setData(source,zombie.ai.states.PlayerActionsState.instance(),zombie.ai.State.Stage.Enter);var wire=(zombie.network.PZNetKahluaTableImpl)field(outgoing,zombie.network.packets.actions.StatePacket.class,"params");var bytes=java.nio.ByteBuffer.allocate(2048);wire.save(bytes);bytes.flip();var parsed=new zombie.network.PZNetKahluaTableImpl(new LinkedHashMap<>());parsed.load(new zombie.core.network.ByteBufferReader(bytes),null);
            var receiver=owner();receiver.ai=new AI(receiver);new Network().setECSOwnerEntity(receiver);zombie.network.GameClient.client=true;
            var packet=new zombie.network.packets.actions.StatePacket();((zombie.network.fields.character.CharacterID)field(packet,zombie.network.packets.actions.StatePacket.class,"characterId")).set(receiver);((zombie.network.fields.StateID)field(packet,zombie.network.packets.actions.StatePacket.class,"state")).set(zombie.ai.states.PlayerActionsState.instance());var stage=zombie.network.packets.actions.StatePacket.class.getDeclaredField("stage");stage.setAccessible(true);stage.set(packet,zombie.ai.State.Stage.Enter);((zombie.network.PZNetKahluaTableImpl)field(packet,zombie.network.packets.actions.StatePacket.class,"params")).delegate.putAll(parsed.delegate);
            var tag=Main.observerAssociationTag("1|01234567-89ab-cdef-0123-456789abcdef|1|2|3|4|5|6");var ctor=Main.ObserverPacket.class.getDeclaredConstructor(zombie.network.packets.actions.StatePacket.class,zombie.characters.IsoPlayer.class,Main.ObserverTag.class);ctor.setAccessible(true);seedInput=ctor.newInstance(packet,receiver,tag);seedInput.processed=true;var records=Main.class.getDeclaredField("observerPackets");records.setAccessible(true);((Main.NativeWeakMap<zombie.network.packets.actions.StatePacket,Main.ObserverPacket>)records.get(null)).put(packet,seedInput);var applying=Main.observerApplyEnter(packet);check(applying!=null,"Original apply scope disabled");seedApply=applying.generation();seedPending=true;
            try{packet.apply();}finally{seedPending=false;Main.observerApplyExit(applying,null);}
            check(seededPending!=null,"Test-only load hook did not seed partial provenance");var defaults=seededPending.getClass().getDeclaredField("defaultMask");defaults.setAccessible(true);check(defaults.getInt(seededPending)==8,"Exact native default supplier not witnessed");var map=raw(receiver);var life=Main.observerParamsInspect(map);check(!life.tainted&&map.size()==7&&"".equals(map.get(zombie.ai.states.PlayerActionsState.SECONDARY)),"Native apply default did not materialize empty secondary");check(life.committed==null,"Test without a transport created a committed source");check(receiver.ai.getAction()!=null&&receiver.ai.getAction().chr==receiver,"Native apply did not construct and assign actual BaseAction");check(Main.observerParamsHealthy(),"Pending native default diagnostic failed");System.out.println("OBSERVER_PARAMS_PENDING_DEFAULT_PASS (actual native StatePacket.apply/setParams/defaultSupplier/constructor/setAction; nativeDefaultMask=8; no transport => no boundload)");return;
        }
        if(args.length>0&&args[0].equals("null-roundtrip")){
            var source=owner();var action=new zombie.characters.CharacterTimedActions.BaseAction(source);action.setOverrideHandModelsString("Cart",null,false);source.actions.add(action);
            var packet=new zombie.network.packets.actions.StatePacket();packet.setData(source,zombie.ai.states.PlayerActionsState.instance(),zombie.ai.State.Stage.Enter);
            var outgoing=(zombie.network.PZNetKahluaTableImpl)field(packet,zombie.network.packets.actions.StatePacket.class,"params");
            var sourceMap=raw(source);check(sourceMap.size()==7&&sourceMap.containsKey(zombie.ai.states.PlayerActionsState.SECONDARY)&&sourceMap.get(zombie.ai.states.PlayerActionsState.SECONDARY)==null,"Native source did not produce present-null secondary");
            check(!outgoing.delegate.containsKey("secondary"),"Native packet retained null secondary");
            var bytes=java.nio.ByteBuffer.allocate(2048);outgoing.save(bytes);int end=bytes.position();bytes.flip();var parsed=new zombie.network.PZNetKahluaTableImpl(new LinkedHashMap<>());parsed.load(new zombie.core.network.ByteBufferReader(bytes),null);check(bytes.position()==end&&!parsed.delegate.containsKey("secondary"),"Wire unexpectedly retained secondary");
            var receiver=owner();receiver.clear(zombie.ai.states.PlayerActionsState.class);zombie.ai.states.PlayerActionsState.instance().loadFrom(parsed.delegate,receiver);var loaded=raw(receiver);var life=Main.observerParamsInspect(loaded);check(loaded.size()==6&&!loaded.containsKey(zombie.ai.states.PlayerActionsState.SECONDARY),"Native receiver load inserted omitted secondary");
            check(zombie.ai.states.PlayerActionsState.SECONDARY.fromDelegate(parsed.delegate)==null,"Native fromDelegate did not accept omitted/null");long revision=life.revision;String value=receiver.get(zombie.ai.states.PlayerActionsState.SECONDARY);check(value.isEmpty()&&loaded.containsKey(zombie.ai.states.PlayerActionsState.SECONDARY)&&life.revision>revision,"Native secondary default transition not observed");
            System.out.println("OBSERVER_PARAMS_NULL_ROUNDTRIP_PASS sourceSlots=7 sourceSecondary=null packetSlots="+outgoing.delegate.size()+" wireSlots="+parsed.delegate.size()+" receiverLoadedSlots=6 fromDelegate=null consumerSecondary=emptyString consumerSlots="+loaded.size()+" defaultRevisionAdvanced=true");return;
        }
        var first=owner();var vars=variables();fill(first,vars);var map=raw(first);var life=Main.observerParamsInspect(map);check(life!=null&&!life.tainted,"Native lambda birth or allowed getter path lost");check(map.size()==7,"Native fill lacks seven distinct params");var committed=artificialCommit(life);check(unchanged(life,committed,first),"Fresh committed value identities not retained");
        long before=life.revision;first.set(zombie.ai.states.PlayerActionsState.PRIMARY,"Cart");check(life.revision>before&&life.committed==null&&!unchanged(life,committed,first),"Same-value native Param.set failed invalidation");
        committed=artificialCommit(life);before=life.revision;first.remove(zombie.ai.states.PlayerActionsState.PRIMARY);check(life.revision>before&&life.committed==null,"Native Param.remove failed invalidation");first.set(zombie.ai.states.PlayerActionsState.PRIMARY,"Cart");
        first.remove(zombie.ai.states.PlayerActionsState.SITONGROUND);before=life.revision;check(!first.get(zombie.ai.states.PlayerActionsState.SITONGROUND),"Native default changed");check(life.revision>before&&map.containsKey(zombie.ai.states.PlayerActionsState.SITONGROUND),"Native inserting Param.get failed invalidation");
        committed=artificialCommit(life);before=life.revision;first.get(zombie.ai.states.PlayerActionsState.SITONGROUND);check(life.revision==before&&unchanged(life,committed,first),"Existing Param.get invalidated unchanged map");
        var nested=Main.observerParamsInspect(field(vars,zombie.network.fields.Variables.class,"variables"));check(nested!=null&&!nested.tainted,"Variables constructor birth lost");before=nested.revision;vars.clear();check(nested.revision>before&&!unchanged(life,committed,first),"Direct native Variables.clear failed invalidation");
        // An untrusted map return permits all mutation routes, including same-value restoration.
        vars=variables();fill(first,vars);committed=artificialCommit(life);var escaped=first.getStateMachineParams(zombie.ai.states.PlayerActionsState.class);check(life.tainted&&!unchanged(life,committed,first),"External params getter did not permanently taint");escaped.put(zombie.ai.states.PlayerActionsState.PRIMARY,"Cart");first.clear(zombie.ai.states.PlayerActionsState.class);fill(first,variables());check(life.tainted&&helper("opSnapshot",Main.OPLife.class).invoke(null,life)==null,"Clear/refill healed escaped params map");
        var second=owner();vars=variables();fill(second,vars);var secondLife=Main.observerParamsInspect(raw(second));committed=artificialCommit(secondLife);var nestedMap=vars.get();nested=Main.observerParamsInspect(nestedMap);check(nested.tainted&&!unchanged(secondLife,committed,second),"Nested mutable map escape failed taint");nestedMap.replaceAll((key,value)->value);vars.clear();check(nested.tainted,"Native clear healed nested escape");
        var third=owner();vars=variables();fill(third,vars);var thirdLife=Main.observerParamsInspect(raw(third));before=thirdLife.revision;var incoming=new LinkedHashMap<Object,Object>();incoming.put("primary","Other");zombie.ai.states.PlayerActionsState.instance().loadFrom(incoming,third);check(thirdLife.revision>before&&thirdLife.committed==null&&!thirdLife.tainted,"Untagged native load did not invalidate");
        // Missing native map birth is never adopted from a later getter.
        var foreign=(zombie.network.fields.Variables)UNSAFE.allocateInstance(zombie.network.fields.Variables.class);var f=zombie.network.fields.Variables.class.getDeclaredField("variables");f.setAccessible(true);var preexisting=new HashMap<String,String>();f.set(foreign,preexisting);check(foreign.get()==preexisting&&Main.observerParamsInspect(preexisting).tainted,"Preexisting Variables map adopted without birth");
        check(Main.observerParamsHealthy(),"Monitoring failed during native regression checks");System.out.println("OBSERVER_PARAMS_CHECK_PASS (native births, seven parameters, same-value set, remove, inserting/read-only get, untagged load, direct nested clear, permanent outer/nested escape, unknown birth)");
    }
}
