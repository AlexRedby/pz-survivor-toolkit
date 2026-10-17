import java.nio.file.Files;
import java.nio.file.Path;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.asm.Advice;
import static net.bytebuddy.matcher.ElementMatchers.*;
import zombie.characters.CharacterTimedActions.LuaTimedActionNew;
import zombie.core.skinnedmodel.model.*;
import zombie.inventory.InventoryItem;

/** Instrumentation generation and output safety only; never connects to a game process. */
public final class ClearanceProbeCheck {
    private static <T> T allocate(Class<T> type) throws Exception {
        var field=sun.misc.Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);
        return type.cast(((sun.misc.Unsafe)field.get(null)).allocateInstance(type));
    }
    private static void probeField(String name,Object value) throws Exception {
        var field=ClearanceProbe.class.getDeclaredField(name);field.setAccessible(true);field.set(null,value);
    }
    private static final class Player extends zombie.characters.IsoPlayer {
        InventoryItem primary,secondary;
        Player(){super(null,null,0,0,0);}
        @Override public InventoryItem getPrimaryHandItem(){return primary;}
        @Override public InventoryItem getSecondaryHandItem(){return secondary;}
        @Override public java.util.Stack<zombie.characters.CharacterTimedActions.BaseAction> getCharacterActions(){return new java.util.Stack<>();}
        @Override public boolean isLocalPlayer(){return true;}
        @Override public boolean isDead(){return false;}
        @Override public zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot setVariable(String name,float value){return null;}
        @Override public void clearVariable(String name){}
    }
    private static final class Cart extends InventoryItem {
        zombie.iso.objects.IsoWorldInventoryObject world;
        Cart(){super(null,null,null,(String)null);}
        @Override public String getFullType(){return "SaucedWheelbarrow.WheelbarrowWood";}
        @Override public zombie.iso.objects.IsoWorldInventoryObject getWorldItem(){return world;}
    }
    private static final class WorldItem extends zombie.iso.objects.IsoWorldInventoryObject {
        InventoryItem item;
        WorldItem(){super((zombie.iso.IsoCell)null);}
        @Override public InventoryItem getItem(){return item;}
        @Override public float getWorldPosX(){return 0;}
        @Override public float getWorldPosY(){return 0;}
        @Override public float getWorldPosZ(){return 0;}
        @Override public void invalidateRenderChunkLevel(long flags){}
    }
    private static ModelSlotRenderData renderSlot(Player actor) throws Exception {
        var offsets=java.util.List.of(new org.lwjgl.util.vector.Matrix4f());
        var skin=new SkinningData(new java.util.HashMap<>(),offsets,offsets,offsets,java.util.List.of(-1),
            new java.util.HashMap<>(java.util.Map.of("probe",0)));
        var parent=new ModelInstance();parent.model=allocate(Model.class);parent.model.tag=skin;
        var instance=new ModelInstance();instance.parent=parent;instance.modelScript=new zombie.scripting.objects.ModelScript();
        instance.modelScript.name="WheelbarrowWood";
        var body=new ModelInstanceRenderData();body.modelInstance=parent;
        body.matrixPalette=java.nio.FloatBuffer.wrap(new org.joml.Matrix4f().get(new float[16]));
        var held=new ModelInstanceRenderData();held.modelInstance=instance;
        var slot=new ModelSlotRenderData();slot.character=actor;slot.modelData.add(body);slot.modelData.add(held);
        return slot;
    }
    private static void firstStopRender(Path directory) throws Exception {
        var actor=allocate(Player.class);var otherActor=allocate(Player.class);var cart=allocate(Cart.class);
        actor.primary=cart;actor.secondary=cart;
        var action=allocate(LuaTimedActionNew.class);action.chr=actor;
        var otherAction=allocate(LuaTimedActionNew.class);
        var bodyFile=directory.resolve("body-clearance.jsonl");var lifecycleFile=directory.resolve("action-lifecycle.jsonl");
        probeField("output",Files.newBufferedWriter(bodyFile));
        probeField("lifecycleOutput",Files.newBufferedWriter(lifecycleFile));
        // Keep normal frames throttled without depending on how quickly the test machine runs.
        probeField("last",System.nanoTime()+10_000_000_000L);
        var slot=renderSlot(actor);var held=slot.modelData.get(1);
        try {
            ClearanceProbe.lifecycle(action,"start",null);ClearanceProbe.lifecycle(action,"stop",null);
            ClearanceProbe.lifecycle(otherAction,"start",new IllegalStateException("sentinel"));
            slot.character=otherActor;ClearanceProbe.snapshot(slot);
            if(Files.size(bodyFile)!=0)throw new AssertionError("other actor consumed the first-render exception");
            slot.character=actor;slot.modelData.remove(held);ClearanceProbe.snapshot(slot);
            actor.secondary=allocate(Cart.class);slot.modelData.add(held);ClearanceProbe.snapshot(slot);
            if(Files.size(bodyFile)!=0)throw new AssertionError("missing model or replacement hand item consumed the receipt");
            actor.secondary=cart;ClearanceProbe.snapshot(slot);ClearanceProbe.snapshot(slot);
            var frames=Files.readAllLines(bodyFile);
            if(frames.size()!=1 || !frames.get(0).contains("\"afterStopActionId\":1"))
                throw new AssertionError("first exact held render was not forced and tagged exactly once");
            probeField("last",0L);slot.character=otherActor;ClearanceProbe.snapshot(slot);
            frames=Files.readAllLines(bodyFile);
            if(frames.size()!=2 || frames.get(1).contains("afterStopActionId"))throw new AssertionError("ordinary actor rendering changed");
        } finally {ClearanceProbe.agentmain("stop",null);}
        var lifecycle=Files.readAllLines(lifecycleFile);
        if(lifecycle.size()!=3 || !lifecycle.get(0).contains("\"nativeActionId\":1")
            || !lifecycle.get(1).contains("\"nativeActionId\":1") || !lifecycle.get(2).contains("\"nativeActionId\":2")
            || !lifecycle.get(2).contains("java.lang.IllegalStateException"))throw new AssertionError("action identity or throwable receipt lost");
        ClearanceProbe.lifecycle(action,"perform",null);
        if(Files.readAllLines(lifecycleFile).size()!=3)throw new AssertionError("closed capture still wrote a receipt");
    }
    private static void firstPickupStopRender(Path directory) throws Exception {
        var actor=allocate(Player.class);var otherActor=allocate(Player.class);var cart=allocate(Cart.class);
        var world=allocate(WorldItem.class);cart.world=world;world.item=cart;
        var action=allocate(LuaTimedActionNew.class);action.chr=actor;
        var table=new se.krka.kahlua.j2se.KahluaTableImpl(new java.util.HashMap<>());
        var metatable=new se.krka.kahlua.j2se.KahluaTableImpl(new java.util.HashMap<>());
        metatable.rawset("Type","ToolkitWoodCartPickup");table.setMetatable(metatable);
        var actionTable=LuaTimedActionNew.class.getDeclaredField("table");actionTable.setAccessible(true);actionTable.set(action,table);
        if(!"ToolkitWoodCartPickup".equals(action.getMetaType()))throw new AssertionError("pickup lifecycle fixture lost its real metatype");
        var bodyFile=directory.resolve("body-clearance.jsonl");var lifecycleFile=directory.resolve("action-lifecycle.jsonl");
        probeField("output",Files.newBufferedWriter(bodyFile));probeField("lifecycleOutput",Files.newBufferedWriter(lifecycleFile));
        probeField("last",System.nanoTime()+10_000_000_000L);
        var slot=renderSlot(actor);var held=slot.modelData.get(1);
        try {
            if(!net.alexredby.pztoolkitjavapatches.CartTransition.update(actor,cart,true,.55))
                throw new AssertionError("pickup lifecycle fixture could not create its exact transition state");
            ClearanceProbe.lifecycle(action,"start",null);ClearanceProbe.lifecycle(action,"stop",null);
            slot.character=otherActor;ClearanceProbe.snapshot(slot);
            slot.character=actor;slot.modelData.remove(held);ClearanceProbe.snapshot(slot);
            slot.modelData.add(held);world.item=allocate(Cart.class);ClearanceProbe.snapshot(slot);
            world.item=cart;actor.primary=allocate(Cart.class);ClearanceProbe.snapshot(slot);
            if(Files.size(bodyFile)!=0)throw new AssertionError("foreign actor, missing model, replacement world item or occupied hand consumed pickup receipt");
            actor.primary=null;ClearanceProbe.snapshot(slot);ClearanceProbe.snapshot(slot);
            var frames=Files.readAllLines(bodyFile);
            if(frames.size()!=1 || !frames.get(0).contains("\"afterStopActionId\":1"))
                throw new AssertionError("first exact world-pickup render with empty hands was not forced and tagged exactly once");
            probeField("last",0L);ClearanceProbe.snapshot(slot);
            frames=Files.readAllLines(bodyFile);
            if(frames.size()!=2 || frames.get(1).contains("afterStopActionId"))
                throw new AssertionError("pickup first-render tag leaked into ordinary frames");
        } finally {
            net.alexredby.pztoolkitjavapatches.CartTransition.end(actor);
            ClearanceProbe.agentmain("stop",null);
        }
        var lifecycle=Files.readAllLines(lifecycleFile);
        if(lifecycle.size()!=2 || !lifecycle.get(1).contains("\"metaType\":\"ToolkitWoodCartPickup\"")
            || !lifecycle.get(1).contains("\"primaryHandItemId\":-1,\"secondaryHandItemId\":-1"))
            throw new AssertionError("pickup stop receipt did not come from the real empty-hand lifecycle branch");
    }
    public static void main(String[] args) throws Exception {
        var target=Class.forName("net.alexredby.pztoolkitjavapatches.CartGrounding");
        if(new ByteBuddy().redefine(target).visit(Advice.to(ClearanceProbe.Capture.class)
            .on(named("render"))).make().getBytes().length==0)throw new AssertionError("empty instrumentation");
        if(new ByteBuddy().redefine(LuaTimedActionNew.class).visit(Advice.to(ClearanceProbe.LifecycleCapture.class)
            .on(takesArguments(0).and(namedOneOf("start","stop","perform","complete","interruptWaitToStart"))))
            .make().getBytes().length==0)throw new AssertionError("empty lifecycle instrumentation");
        for(String invalid:new String[]{"", "relative-output"}) {
            try { ClearanceProbe.agentmain(invalid,null);throw new AssertionError("accepted invalid output directory"); }
            catch(IllegalArgumentException expected) { }
        }
        Path directory=Files.createTempDirectory("clearance-probe-check-");
        Path file=directory.resolve("body-clearance.jsonl");
        try {
            Files.writeString(file,"preserve me");
            try { ClearanceProbe.agentmain(directory.toString(),null);throw new AssertionError("overwrote existing capture"); }
            catch(IllegalStateException expected) { }
            if(!Files.readString(file).equals("preserve me"))throw new AssertionError("capture changed");
            firstStopRender(directory);
            firstPickupStopRender(directory);
        } finally {
            ClearanceProbe.agentmain("stop",null);
            Files.deleteIfExists(file);Files.deleteIfExists(directory.resolve("action-lifecycle.jsonl"));Files.delete(directory);
        }
        System.out.println("CLEARANCE_PROBE_CHECK_PASS (advice transforms, output safety, lifecycle identities, exact first stopped-cart render)");
    }
}
