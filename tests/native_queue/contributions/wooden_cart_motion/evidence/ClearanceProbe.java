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
    private static BufferedWriter worldOutput;
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
    public static synchronized void snapshot(ModelSlotRenderData slot) throws Exception {
        if(output==null || System.nanoTime()-last<33_333_333L) return;
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
                matrix(row,new Matrix4f(cart.xfrm).transpose());row.append(",\"bones\":{");
                boolean comma=false;
                for(var entry:skin.boneIndices.entrySet()) {
                    int i=entry.getValue();if((i+1)*16>body.matrixPalette.limit())throw new AssertionError("palette bounds");
                    var buffer=body.matrixPalette.duplicate();buffer.position(i*16);
                    var raw=new org.lwjgl.util.vector.Matrix4f();raw.load(buffer);
                    var pose=PZMath.convertMatrix(raw,new Matrix4f()).transpose()
                        .mul(PZMath.convertMatrix(skin.boneOffset.get(i),new Matrix4f()).transpose().invert());
                    if(!pose.isFinite())throw new AssertionError("nonfinite pose");
                    if(comma)row.append(',');comma=true;row.append('"').append(entry.getKey()).append("\":");matrix(row,pose);
                }
                row.append("}}\n");output.write(row.toString());output.flush();last=System.nanoTime();return;
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
            || status!=ItemModelRenderer.RenderStatus.Ready) return;
        var transform=new Matrix4f((Matrix4f)WORLD_TRANSFORM.get(renderer));
        float alpha=WORLD_ALPHA.getFloat(renderer);
        if(!transform.isFinite() || !renderer.angle.isFinite() || !Float.isFinite(renderer.x)
            || !Float.isFinite(renderer.y) || !Float.isFinite(renderer.z) || !Float.isFinite(alpha))
            throw new IllegalStateException("Nonfinite world cart render pose");
        var row=new StringBuilder(768).append("{\"wallTimeMillis\":").append(System.currentTimeMillis())
            .append(",\"itemId\":").append(item.getID())
            .append(",\"source\":\"ItemModelRenderer.renderMain-exit\",\"matrixOrder\":\"column-major\"")
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

    private static void closeOutputs() throws Exception {
        var body=output;var world=worldOutput;output=null;worldOutput=null;
        Exception failure=null;
        try{if(body!=null)body.close();}catch(Exception error){failure=error;}
        try{if(world!=null)world.close();}catch(Exception error){if(failure==null)failure=error;else failure.addSuppressed(error);}
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
        if(Files.exists(file) || Files.exists(worldFile))throw new IllegalStateException("Preserve existing clearance output first");
        try {
            output=Files.newBufferedWriter(file,java.nio.file.StandardOpenOption.CREATE_NEW);
            worldOutput=Files.newBufferedWriter(worldFile,java.nio.file.StandardOpenOption.CREATE_NEW);last=0;
            if(!installed){new AgentBuilder.Default().disableClassFormatChanges()
                .with(AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
                .with(AgentBuilder.Listener.StreamWriting.toSystemError().withErrorsOnly())
                .type(named("net.alexredby.pztoolkitjavapatches.CartGrounding")
                    .or(named("zombie.core.skinnedmodel.model.ItemModelRenderer")))
                .transform((b,d,l,m,p)->d.getName().equals("net.alexredby.pztoolkitjavapatches.CartGrounding")
                    ?b.visit(Advice.to(Capture.class).on(named("render")))
                    :b.visit(Advice.to(WorldRenderCapture.class).on(named("renderMain").and(takesArguments(9)))))
                .installOn(instrumentation);installed=true;}
        } catch(Exception error) {
            try{closeOutputs();}catch(Exception close){error.addSuppressed(close);}
            throw error;
        }
        System.out.println("[CLEARANCE_PROBE] writing "+file+" and "+worldFile);
    }
}
