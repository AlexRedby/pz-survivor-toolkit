import java.io.BufferedWriter;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Field;
import java.nio.FloatBuffer;
import java.nio.file.*;
import net.bytebuddy.agent.builder.AgentBuilder;
import net.bytebuddy.asm.Advice;
import static net.bytebuddy.matcher.ElementMatchers.*;
import org.joml.Matrix4f;
import zombie.core.math.PZMath;
import zombie.core.skinnedmodel.model.*;
import zombie.inventory.InventoryItem;

/** Read-only final render poses for native body/handle clearance measurements. */
public final class ClearanceProbe {
    private static BufferedWriter output;
    private static BufferedWriter worldOutput, tailOutput, lifecycleOutput;
    private static final java.util.WeakHashMap<zombie.characters.CharacterTimedActions.LuaTimedActionNew,Long> actionIds=new java.util.WeakHashMap<>();
    private record StoppedCart(long actionId, InventoryItem item) {}
    private static final java.util.WeakHashMap<zombie.characters.IsoGameCharacter,StoppedCart> stoppedCarts=new java.util.WeakHashMap<>();
    private static long nextActionId;
    private static long lastTail;
    private static final Field WORLD_TRANSFORM=field("transform"), WORLD_ALPHA=field("alpha");
    private static long last;
    private static boolean installed;
    private static Field field(String name) {
        try {var field=ItemModelRenderer.class.getDeclaredField(name);field.setAccessible(true);return field;}
        catch(ReflectiveOperationException error){throw new ExceptionInInitializerError(error);}
    }
    private static void matrix(StringBuilder row, Matrix4f value) {
        float[] v=value.get(new float[16]);row.append('[');
        for(int i=0;i<16;i++){if(i>0)row.append(',');row.append(v[i]);}row.append(']');
    }
    private static String quoted(String value) {
        return value==null?"null":"\""+value.replace("\\","\\\\").replace("\"","\\\"").replace("\n","\\n").replace("\r","\\r")+"\"";
    }
    private static Matrix4f pose(ModelInstanceRenderData body,SkinningData skin,int index) {
        if((index+1)*16>body.matrixPalette.limit())throw new AssertionError("palette bounds");
        var buffer=body.matrixPalette.duplicate();buffer.position(index*16);
        var raw=new org.lwjgl.util.vector.Matrix4f();raw.load(buffer);
        var result=PZMath.convertMatrix(raw,new Matrix4f()).transpose()
            .mul(PZMath.convertMatrix(skin.boneOffset.get(index),new Matrix4f()).transpose().invert());
        if(!result.isFinite())throw new AssertionError("nonfinite pose");
        return result;
    }
    private static void tail(ModelSlotRenderData slot) throws Exception {
        if(tailOutput==null || System.nanoTime()-lastTail<16_666_667L)return;
        for(var body:slot.modelData) {
            if(body.modelInstance==null || body.modelInstance.parent!=null || body.matrixPalette==null
                || !(body.modelInstance.model.tag instanceof SkinningData skin))continue;
            var row=new StringBuilder(4096).append("{\"wallTimeMillis\":").append(System.currentTimeMillis());
            for(String name:new String[]{"PerformingAction","Weapon","RightHandMask","LeftHandMask"})
                row.append(',').append(quoted(name)).append(':').append(quoted(slot.character.getVariableString(name)));
            row.append(",\"cartModel\":").append(slot.modelData.stream().anyMatch(d->d.modelInstance!=null
                && d.modelInstance.modelScript!=null && "WheelbarrowWood".equals(d.modelInstance.modelScript.getName())))
                .append(",\"bones\":{");
            boolean comma=false;
            for(String side:new String[]{"L","R"})for(String part:new String[]{"UpperArm","Forearm","Hand"}) {
                String name="Bip01_"+side+"_"+part;Integer index=skin.boneIndices.get(name);
                if(index==null)throw new AssertionError("Missing tail bone "+name);
                if(comma)row.append(',');comma=true;row.append(quoted(name)).append(':');matrix(row,pose(body,skin,index));
            }
            row.append("},\"tracks\":[");comma=false;
            for(var track:body.modelInstance.animPlayer.getMultiTrack().getTracks()) {
                if(comma)row.append(',');comma=true;
                row.append("{\"name\":").append(quoted(track.getName())).append(",\"weight\":").append(track.getBlendWeight())
                    .append(",\"field\":").append(track.getBlendFieldWeight()).append(",\"layer\":").append(track.getLayerIdx())
                    .append(",\"priority\":").append(track.getPriority()).append('}');
            }
            row.append("]}\n");tailOutput.write(row.toString());tailOutput.flush();lastTail=System.nanoTime();return;
        }
    }
    public static synchronized void snapshot(ModelSlotRenderData slot) throws Exception {
        tail(slot);
        var stopped=stoppedCarts.get(slot.character);
        boolean afterStop=stopped!=null && slot.character.getPrimaryHandItem()==stopped.item
            && slot.character.getSecondaryHandItem()==stopped.item;
        if(output==null || !afterStop && System.nanoTime()-last<33_333_333L) return;
        for(var cart:slot.modelData) {
            var instance=cart.modelInstance;
            if(instance==null || instance.parent==null || instance.modelScript==null
                || !"WheelbarrowWood".equals(instance.modelScript.getName()))continue;
            for(var body:slot.modelData) {
                if(body.modelInstance!=instance.parent || body.matrixPalette==null
                    || !(body.modelInstance.model.tag instanceof SkinningData skin))continue;
                var row=new StringBuilder(8192).append("{\"wallTimeMillis\":").append(System.currentTimeMillis())
                    .append(",\"female\":").append(slot.character.isFemale())
                    .append(",\"slotX\":").append(slot.x).append(",\"slotY\":").append(slot.y)
                    .append(",\"slotAngle\":").append(slot.animPlayerAngle).append(",\"cart\":");
                matrix(row,new Matrix4f(cart.xfrm).transpose());
                if(afterStop)row.append(",\"afterStopActionId\":").append(stopped.actionId);
                row.append(",\"bones\":{");
                boolean comma=false;
                for(var entry:skin.boneIndices.entrySet()) {
                    var pose=pose(body,skin,entry.getValue());
                    if(comma)row.append(',');comma=true;row.append('"').append(entry.getKey()).append("\":");matrix(row,pose);
                }
                row.append("}}\n");output.write(row.toString());output.flush();
                if(afterStop)stoppedCarts.remove(slot.character,stopped);
                else last=System.nanoTime();
                return;
            }
        }
    }
    public static class Capture {
        @Advice.OnMethodExit(suppress=Throwable.class)
        public static void exit(@Advice.Argument(0) ModelSlotRenderData slot) {
            try{ClearanceProbe.snapshot(slot);}catch(Throwable e){System.err.println("[CLEARANCE_PROBE] ERROR "+e);}
        }
    }

    public static synchronized void finishWorld(ItemModelRenderer renderer,InventoryItem item,
        ItemModelRenderer.RenderStatus status) throws Exception {
        if(worldOutput==null || item==null || item.getWorldItem()==null
            || !"SaucedWheelbarrow.WheelbarrowWood".equals(item.getFullType())
            ) return;
        if(status==ItemModelRenderer.RenderStatus.NoModel
            && net.alexredby.pztoolkitjavapatches.CartTransition.hidden(item)) {
            worldOutput.write("{\"wallTimeMillis\":"+System.currentTimeMillis()+",\"itemId\":"+item.getID()
                +",\"renderStatus\":\"NoModel\",\"transitionHidden\":true}\n");worldOutput.flush();return;
        }
        if(status!=ItemModelRenderer.RenderStatus.Ready)return;
        var transform=new Matrix4f((Matrix4f)WORLD_TRANSFORM.get(renderer));
        float alpha=WORLD_ALPHA.getFloat(renderer);
        if(!transform.isFinite() || !renderer.angle.isFinite() || !Float.isFinite(renderer.x)
            || !Float.isFinite(renderer.y) || !Float.isFinite(renderer.z) || !Float.isFinite(alpha))
            throw new IllegalStateException("Nonfinite world cart render pose");
        var row=new StringBuilder(768).append("{\"wallTimeMillis\":").append(System.currentTimeMillis())
            .append(",\"itemId\":").append(item.getID())
            .append(",\"renderStatus\":\"Ready\",\"source\":\"ItemModelRenderer.renderMain-exit\",\"matrixOrder\":\"column-major\"")
            .append(",\"x\":").append(renderer.x).append(",\"y\":").append(renderer.y)
            .append(",\"z\":").append(renderer.z).append(",\"angle\":[")
            .append(renderer.angle.x).append(',').append(renderer.angle.y).append(',').append(renderer.angle.z)
            .append("],\"transform\":");
        matrix(row,transform);row.append(",\"alpha\":").append(alpha).append("}\n");
        worldOutput.write(row.toString());worldOutput.flush();
    }

    public static class WorldRenderCapture {
        @Advice.OnMethodExit(onThrowable=Throwable.class,suppress=Throwable.class)
        public static void exit(@Advice.This ItemModelRenderer renderer,@Advice.Argument(0) InventoryItem item,
            @Advice.Return ItemModelRenderer.RenderStatus status,@Advice.Thrown Throwable thrown) {
            try{ClearanceProbe.finishWorld(renderer,item,thrown==null?status:null);}
            catch(Throwable error){System.err.println("[CLEARANCE_PROBE] WORLD ERROR "+error);}
        }
    }

    public static synchronized void worldSuppressed(zombie.iso.objects.IsoWorldInventoryObject world) throws Exception {
        var item=world.getItem();
        if(worldOutput!=null && net.alexredby.pztoolkitjavapatches.CartTransition.hidden(item)) {
            worldOutput.write("{\"wallTimeMillis\":"+System.currentTimeMillis()+",\"itemId\":"+item.getID()
                +",\"renderStatus\":\"Suppressed\",\"transitionHidden\":true,\"source\":\"IsoWorldInventoryObject.render-exit\"}\n");
            worldOutput.flush();
        }
    }
    public static class WorldSuppressedCapture {
        @Advice.OnMethodExit(onThrowable=Throwable.class,suppress=Throwable.class)
        public static void exit(@Advice.This zombie.iso.objects.IsoWorldInventoryObject world,@Advice.Thrown Throwable thrown) {
            try{if(thrown==null)ClearanceProbe.worldSuppressed(world);}
            catch(Throwable error){System.err.println("[CLEARANCE_PROBE] SUPPRESSION ERROR "+error);}
        }
    }

    public static synchronized void lifecycle(zombie.characters.CharacterTimedActions.LuaTimedActionNew action,
        String event,Throwable thrown) throws Exception {
        if(lifecycleOutput==null)return;
        long identity=actionIds.computeIfAbsent(action,key->++nextActionId);
        var actor=action.chr;
        var player=actor instanceof zombie.characters.IsoPlayer value?value:null;
        var primary=actor==null?null:actor.getPrimaryHandItem();
        var secondary=actor==null?null:actor.getSecondaryHandItem();
        var actions=actor==null?null:actor.getCharacterActions();
        var current=actions==null || actions.isEmpty()?null:actions.get(0);
        var row=new StringBuilder(768).append("{\"wallTimeMillis\":").append(System.currentTimeMillis())
            .append(",\"event\":").append(quoted(event)).append(",\"phase\":\"exit\",\"nativeActionId\":").append(identity)
            .append(",\"nativeActionIdentity\":").append(System.identityHashCode(action))
            .append(",\"metaType\":").append(quoted(action.getMetaType())).append(",\"nativeName\":").append(quoted(action.getName()))
            .append(",\"finished\":").append(action.finished()).append(",\"started\":").append(action.isStarted())
            .append(",\"forceStop\":").append(action.forceStop).append(",\"forceComplete\":").append(action.forceComplete)
            .append(",\"actorId\":").append(actor==null?-1:actor.getID())
            .append(",\"actorIdentity\":").append(actor==null?0:System.identityHashCode(actor))
            .append(",\"playerNum\":").append(player==null?-1:player.getPlayerNum())
            .append(",\"onlineId\":").append(player==null?-1:player.getOnlineID())
            .append(",\"primaryHandItemId\":").append(primary==null?-1:primary.getID())
            .append(",\"secondaryHandItemId\":").append(secondary==null?-1:secondary.getID())
            .append(",\"nativeStackSize\":").append(actions==null?0:actions.size())
            .append(",\"nativeStackContainsAction\":").append(actions!=null && actions.contains(action))
            .append(",\"nativeStackCurrentIdentity\":").append(current==null?0:System.identityHashCode(current))
            .append(",\"threw\":").append(quoted(thrown==null?null:thrown.getClass().getName())).append("}\n");
        lifecycleOutput.write(row.toString());lifecycleOutput.flush();
        if("stop".equals(event) && thrown==null && primary!=null && primary==secondary
            && "SaucedWheelbarrow.WheelbarrowWood".equals(primary.getFullType())) {
            if(stoppedCarts.putIfAbsent(actor,new StoppedCart(identity,primary))!=null)
                throw new IllegalStateException("Previous stopped cart still has no render receipt");
        }
    }
    public static class LifecycleCapture {
        @Advice.OnMethodExit(onThrowable=Throwable.class,suppress=Throwable.class)
        public static void exit(@Advice.This zombie.characters.CharacterTimedActions.LuaTimedActionNew action,
            @Advice.Origin("#m") String event,@Advice.Thrown Throwable thrown) {
            try{ClearanceProbe.lifecycle(action,event,thrown);}
            catch(Throwable error){System.err.println("[CLEARANCE_PROBE] LIFECYCLE ERROR "+error);}
        }
    }

    private static void closeOutputs() throws Exception {
        var body=output;var world=worldOutput;var tails=tailOutput;var lifecycle=lifecycleOutput;
        output=null;worldOutput=null;tailOutput=null;lifecycleOutput=null;actionIds.clear();stoppedCarts.clear();nextActionId=0;
        Exception failure=null;
        try{if(body!=null)body.close();}catch(Exception error){failure=error;}
        try{if(world!=null)world.close();}catch(Exception error){if(failure==null)failure=error;else failure.addSuppressed(error);}
        try{if(tails!=null)tails.close();}catch(Exception error){if(failure==null)failure=error;else failure.addSuppressed(error);}
        try{if(lifecycle!=null)lifecycle.close();}catch(Exception error){if(failure==null)failure=error;else failure.addSuppressed(error);}
        if(failure!=null)throw failure;
    }

    public static synchronized void agentmain(String args,Instrumentation instrumentation) throws Exception {
        closeOutputs();
        if("stop".equals(args)){System.out.println("[CLEARANCE_PROBE] stopped");return;}
        if(args==null || args.isBlank() || !Path.of(args).isAbsolute())throw new IllegalArgumentException("Agent args: absolute output directory, or stop");
        Path directory=Path.of(args);
        if(!Files.isDirectory(directory))throw new IllegalArgumentException("Output directory must exist");
        Path file=directory.resolve("body-clearance.jsonl");
        Path worldFile=directory.resolve("world-cart-poses.jsonl");
        Path tailFile=directory.resolve("action-tail-poses.jsonl");
        Path lifecycleFile=directory.resolve("action-lifecycle.jsonl");
        if(Files.exists(file) || Files.exists(worldFile) || Files.exists(tailFile) || Files.exists(lifecycleFile))throw new IllegalStateException("Preserve existing clearance output first");
        try {
            output=Files.newBufferedWriter(file,java.nio.file.StandardOpenOption.CREATE_NEW);
            worldOutput=Files.newBufferedWriter(worldFile,java.nio.file.StandardOpenOption.CREATE_NEW);
            tailOutput=Files.newBufferedWriter(tailFile,java.nio.file.StandardOpenOption.CREATE_NEW);last=0;lastTail=0;
            lifecycleOutput=Files.newBufferedWriter(lifecycleFile,java.nio.file.StandardOpenOption.CREATE_NEW);
            if(!installed){new AgentBuilder.Default().disableClassFormatChanges()
                .with(AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
                .with(AgentBuilder.Listener.StreamWriting.toSystemError().withErrorsOnly())
                .type(named("net.alexredby.pztoolkitjavapatches.CartGrounding")
                    .or(named("zombie.core.skinnedmodel.model.ItemModelRenderer"))
                    .or(named("zombie.characters.CharacterTimedActions.LuaTimedActionNew"))
                    .or(named("zombie.iso.objects.IsoWorldInventoryObject")))
                .transform((b,d,l,m,p)->d.getName().equals("net.alexredby.pztoolkitjavapatches.CartGrounding")
                    ?b.visit(Advice.to(Capture.class).on(named("render")))
                    :d.getName().equals("zombie.characters.CharacterTimedActions.LuaTimedActionNew")
                    ?b.visit(Advice.to(LifecycleCapture.class).on(takesArguments(0).and(namedOneOf("start","stop","perform","complete","interruptWaitToStart"))))
                    :d.getName().equals("zombie.iso.objects.IsoWorldInventoryObject")
                    ?b.visit(Advice.to(WorldSuppressedCapture.class).on(named("render")))
                    :b.visit(Advice.to(WorldRenderCapture.class).on(named("renderMain").and(takesArguments(9)))))
                .installOn(instrumentation);installed=true;}
        } catch(Exception error) {
            try{closeOutputs();}catch(Exception close){error.addSuppressed(close);}
            throw error;
        }
        System.out.println("[CLEARANCE_PROBE] writing "+file+" and "+worldFile);
    }
}
