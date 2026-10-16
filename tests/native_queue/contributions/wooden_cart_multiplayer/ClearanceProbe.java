import java.io.BufferedWriter;
import java.lang.instrument.Instrumentation;
import java.nio.file.*;
import net.bytebuddy.agent.builder.AgentBuilder;
import net.bytebuddy.asm.Advice;
import static net.bytebuddy.matcher.ElementMatchers.*;
import org.joml.Matrix4f;
import zombie.core.math.PZMath;
import zombie.core.skinnedmodel.model.*;

/** Read-only final render poses for native body/handle clearance measurements. */
public final class ClearanceProbe {
    private static BufferedWriter output;
    private static long last;
    private static boolean installed;
    private static void matrix(StringBuilder row, Matrix4f value) {
        float[] v=value.get(new float[16]);row.append('[');
        for(int i=0;i<16;i++){if(i>0)row.append(',');row.append(v[i]);}row.append(']');
    }
    public static synchronized void snapshot(ModelSlotRenderData slot) throws Exception {
        if(output==null || System.nanoTime()-last<33_333_333L || !(slot.character instanceof zombie.characters.IsoPlayer player)) return;
        for(var cart:slot.modelData) {
            var instance=cart.modelInstance;
            if(instance==null || instance.parent==null || instance.modelScript==null
                || !"WheelbarrowWood".equals(instance.modelScript.getName()))continue;
            for(var body:slot.modelData) {
                if(body.modelInstance!=instance.parent || body.matrixPalette==null
                    || !(body.modelInstance.model.tag instanceof SkinningData skin))continue;
                var row=new StringBuilder(8192).append("{\"wallTimeMillis\":").append(System.currentTimeMillis())
                    .append(",\"id\":").append(((zombie.characters.IsoPlayer)slot.character).getOnlineID()).append(",\"local\":").append(((zombie.characters.IsoPlayer)slot.character).isLocalPlayer()).append(",\"enabled\":").append(net.alexredby.pztoolkitjavapatches.CartSteeringHooks.enabled((zombie.characters.IsoPlayer)slot.character)).append(",\"female\":").append(slot.character.isFemale())
                    .append(",\"primary\":").append(player.getPrimaryHandItem()==null?-1:player.getPrimaryHandItem().getID())
                    .append(",\"secondary\":").append(player.getSecondaryHandItem()==null?-1:player.getSecondaryHandItem().getID()).append(",\"cart\":");
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
    public static synchronized void agentmain(String args,Instrumentation instrumentation) throws Exception {
        if(output!=null){output.close();output=null;}
        if("stop".equals(args)){System.out.println("[CLEARANCE_PROBE] stopped");return;}
        if(args==null || args.isBlank() || !Path.of(args).isAbsolute())throw new IllegalArgumentException("Agent args: absolute output directory, or stop");
        Path directory=Path.of(args);
        if(!Files.isDirectory(directory))throw new IllegalArgumentException("Output directory must exist");
        Path file=directory.resolve("body-clearance.jsonl");
        if(Files.exists(file))throw new IllegalStateException("Preserve existing clearance output first");
        output=Files.newBufferedWriter(file,java.nio.file.StandardOpenOption.CREATE_NEW);last=0;
        if(!installed){new AgentBuilder.Default().disableClassFormatChanges()
            .with(AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
            .type(named("net.alexredby.pztoolkitjavapatches.CartGrounding"))
            .transform((b,d,l,m,p)->b.visit(Advice.to(Capture.class).on(named("render"))))
            .installOn(instrumentation);installed=true;}
        System.out.println("[CLEARANCE_PROBE] writing "+file);
    }
}
