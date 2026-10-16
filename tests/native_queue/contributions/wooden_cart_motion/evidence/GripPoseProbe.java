import java.io.BufferedWriter;
import java.lang.instrument.Instrumentation;
import java.nio.file.Files;
import java.nio.file.Path;
import net.bytebuddy.agent.builder.AgentBuilder;
import net.bytebuddy.asm.Advice;
import static net.bytebuddy.matcher.ElementMatchers.*;
import org.joml.Matrix4f;
import zombie.core.skinnedmodel.model.SkinningData;

/** Copy grip inputs before IK mutates them; never change arguments, return values, or game state. */
public final class GripPoseProbe {
    private static final String[] BONES={"Bip01_Spine","Bip01_Spine1","Bip01_L_Clavicle","Bip01_R_Clavicle",
        "Bip01_L_UpperArm","Bip01_L_Forearm","Bip01_L_Hand","Bip01_R_UpperArm","Bip01_R_Forearm","Bip01_R_Hand"};
    private static BufferedWriter output;
    private static long start,sequence;
    private static boolean installed,errorLogged;

    public static void matrix(StringBuilder row,Matrix4f value) {
        if(value==null){row.append("null");return;}
        float[] copy=value.get(new float[16]);row.append('[');
        for(int i=0;i<copy.length;i++){
            if(i>0)row.append(',');
            if(Float.isFinite(copy[i]))row.append(copy[i]);else row.append("null");
        }
        row.append(']');
    }
    public static synchronized String before(Matrix4f[] poses,SkinningData actor,String model,boolean female,
                                              Matrix4f delta,Matrix4f cart) {
        if(output==null || !"WheelbarrowWood".equals(model))return null;
        try {
            var row=new StringBuilder(4096).append("{\"sequence\":").append(++sequence)
                .append(",\"time\":").append((System.nanoTime()-start)/1e9)
                .append(",\"nanoTime\":").append(System.nanoTime())
                .append(",\"wallTimeMillis\":").append(System.currentTimeMillis())
                .append(",\"thread\":").append(Thread.currentThread().getId())
                .append(",\"model\":\"WheelbarrowWood\",\"female\":").append(female)
                .append(",\"matrixOrder\":\"column-major\",\"delta\":");
            matrix(row,delta);row.append(",\"cart\":");matrix(row,cart);row.append(",\"bones\":{");
            for(int i=0;i<BONES.length;i++) {
                if(i>0)row.append(',');String name=BONES[i];row.append('"').append(name).append("\":");
                var bone=actor==null?null:actor.getBone(name);
                matrix(row,bone==null || poses==null || bone.index<0 || bone.index>=poses.length?null:poses[bone.index]);
            }
            return row.append('}').toString();
        } catch(Throwable error){fail(error);return null;}
    }
    public static synchronized void after(String snapshot,boolean result,Throwable thrown) {
        if(snapshot==null || output==null)return;
        try {
            output.write(snapshot);output.write(",\"result\":");output.write(Boolean.toString(result));
            output.write(",\"threw\":");output.write(Boolean.toString(thrown!=null));output.write("}\n");output.flush();
        } catch(Throwable error){fail(error);}
    }
    private static void fail(Throwable error) {
        if(!errorLogged){errorLogged=true;System.err.println("[GRIP_POSE_PROBE] ERROR "+error);error.printStackTrace();}
    }
    public static class GripAdvice {
        @Advice.OnMethodEnter(suppress=Throwable.class)
        public static String enter(@Advice.Argument(0) Matrix4f[] poses,@Advice.Argument(1) SkinningData actor,
            @Advice.Argument(2) String model,@Advice.Argument(3) boolean female,
            @Advice.Argument(4) Matrix4f delta,@Advice.Argument(5) Matrix4f cart) {
            return GripPoseProbe.before(poses,actor,model,female,delta,cart);
        }
        @Advice.OnMethodExit(onThrowable=Throwable.class,suppress=Throwable.class)
        public static void exit(@Advice.Enter String snapshot,@Advice.Return boolean result,@Advice.Thrown Throwable thrown) {
            GripPoseProbe.after(snapshot,result,thrown);
        }
    }
    public static synchronized void agentmain(String args,Instrumentation instrumentation) throws Exception {
        if(output!=null){output.close();output=null;}
        if("stop".equals(args)){System.out.println("[GRIP_POSE_PROBE] stopped");return;}
        if(args==null || args.isBlank() || !Path.of(args).isAbsolute())throw new IllegalArgumentException("Agent args: absolute output directory, or stop");
        Path directory=Path.of(args);
        if(!Files.isDirectory(directory))throw new IllegalArgumentException("Output directory must exist");
        Path file=directory.resolve("wood-grip-poses.jsonl");
        output=Files.newBufferedWriter(file,java.nio.file.StandardOpenOption.CREATE_NEW);start=System.nanoTime();sequence=0;errorLogged=false;
        if(!installed){
            new AgentBuilder.Default().disableClassFormatChanges()
                .with(AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
                .with(AgentBuilder.Listener.StreamWriting.toSystemError().withErrorsOnly())
                .type(named("net.alexredby.pztoolkitjavapatches.CartGrip"))
                .transform((builder,description,loader,module,protection)->builder.visit(
                    Advice.to(GripAdvice.class).on(named("grip").and(takesArguments(6)))))
                .installOn(instrumentation);installed=true;
        }
        System.out.println("[GRIP_POSE_PROBE] capturing every wooden grip call, including failures: "+file);
    }
}
