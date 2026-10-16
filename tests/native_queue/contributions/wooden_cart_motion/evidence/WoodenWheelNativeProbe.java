import java.io.BufferedWriter;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.FloatBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.Map;
import java.util.WeakHashMap;
import net.bytebuddy.agent.builder.AgentBuilder;
import net.bytebuddy.asm.Advice;
import static net.bytebuddy.matcher.ElementMatchers.*;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.lwjgl.BufferUtils;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL15;
import zombie.characters.IsoPlayer;
import zombie.core.math.PZMath;
import zombie.core.skinnedmodel.model.*;

/** Read-only native proof: probes copy render snapshots and read GPU bytes without changing production state. */
public final class WoodenWheelNativeProbe {
    private static final float CX=-6.642862e-6f,CY=-.0041269097f,CZ=-.0010569958f,R=.001062454f,H=.00024333253f;
    private static final long INTERVAL=33_333_333L;
    private static final WeakHashMap<ModelInstanceRenderData, double[]> snapshots=new WeakHashMap<>();
    private static final Map<String,Matrix4f> previousBones=new HashMap<>();
    private static final String[] TRANSITION_BONES={"Bip01_Spine","Bip01_Spine1","Bip01_L_Thigh","Bip01_R_Thigh","Bip01_L_Calf","Bip01_R_Calf",
        "Bip01_L_Clavicle","Bip01_R_Clavicle","Bip01_L_UpperArm","Bip01_R_UpperArm","Bip01_L_Forearm","Bip01_R_Forearm","Bip01_L_Hand","Bip01_R_Hand"};
    private static final double[] NO_BONE={Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN};
    private static final double[] NO_TRANSITION={Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,
        Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN};
    static { if (Math.abs(distance(0,0,0,3,4,0)-5)>1e-6) throw new AssertionError("distance self-check"); }
    private record NativeSnapshot(ModelInstanceRenderData cart, Map<String,Matrix4f> bones) {}
    private static BufferedWriter output;
    private static Path directory;
    private static long start,sequence,lastSnapshot,lastDraw;
    private static boolean installed,errorLogged,firstDraw,meshProof,movingMeshProof;
    private static double proofPhase;
    private static Field drive;
    private static Method phase;

    static Object field(Object object,String name) throws Exception {
        Field f=object.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(object);
    }
    static double phase(ModelInstanceRenderData data) throws Exception {
        if(phase==null) {
            phase=Class.forName("net.alexredby.pztoolkitjavapatches.CartWheelSpin").getDeclaredMethod("phase",ModelInstanceRenderData.class);
            phase.setAccessible(true);
        }
        Double value=(Double)phase.invoke(null,data);return value==null?Double.NaN:value;
    }
    static int drive() {
        try {if(drive==null)drive=Class.forName("net.alexredby.cartlab.Main").getField("drive");return drive.getInt(null);}
        catch(Exception unavailable) {return Integer.MIN_VALUE;}
    }
    static double[] world(ModelSlotRenderData slot,Vector3f local,boolean direction) {
        double cos=Math.cos(slot.animPlayerAngle),sin=Math.sin(slot.animPlayerAngle);
        return new double[]{1.5*(-local.x*cos-local.z*sin)+(direction?0:slot.x),
            1.5*(-local.x*sin+local.z*cos)+(direction?0:slot.y),
            .61237234*local.y+(direction?0:slot.z)};
    }
    static double[] normal(double[] y,double[] z) {
        double[] n={y[1]*z[2]-y[2]*z[1],y[2]*z[0]-y[0]*z[2],y[0]*z[1]-y[1]*z[0]};
        double length=Math.sqrt(n[0]*n[0]+n[1]*n[1]+n[2]*n[2]);
        for(int i=0;i<3;i++)n[i]/=length;return n;
    }
    static Matrix4f pose(FloatBuffer palette,SkinningData skin,String name) {
        Integer index=skin.boneIndices.get(name);
        if(index==null || (index+1)*16>palette.limit())return null;
        FloatBuffer buffer=palette.duplicate();buffer.position(index*16);
        var matrix=new org.lwjgl.util.vector.Matrix4f();matrix.load(buffer);
        return PZMath.convertMatrix(matrix,new Matrix4f()).transpose()
            .mul(PZMath.convertMatrix(skin.boneOffset.get(index),new Matrix4f()).transpose().invert());
    }
    static double distance(double ax,double ay,double az,double bx,double by,double bz) {
        return Math.sqrt((ax-bx)*(ax-bx)+(ay-by)*(ay-by)+(az-bz)*(az-bz));
    }
    static double segment(Matrix4f a,Matrix4f b) {
        return a==null||b==null?Double.NaN:distance(a.m30(),a.m31(),a.m32(),b.m30(),b.m31(),b.m32());
    }
    static double arm(Map<String,Matrix4f> bones,String side) {
        String root="Bip01_"+side+"_";
        double a=segment(bones.get(root+"Clavicle"),bones.get(root+"UpperArm"));
        double b=segment(bones.get(root+"UpperArm"),bones.get(root+"Forearm"));
        double c=segment(bones.get(root+"Forearm"),bones.get(root+"Hand"));
        return Double.isFinite(a)&&Double.isFinite(b)&&Double.isFinite(c)?a+b+c:Double.NaN;
    }
    static double orientationDifference(Matrix4f a,Matrix4f b) {
        if(a==null||b==null)return Double.NaN;
        return Math.max(Math.max(Math.max(Math.abs(a.m00()-b.m00()),Math.abs(a.m01()-b.m01())),Math.abs(a.m02()-b.m02())),
            Math.max(Math.max(Math.max(Math.abs(a.m10()-b.m10()),Math.abs(a.m11()-b.m11())),Math.abs(a.m12()-b.m12())),
            Math.max(Math.max(Math.abs(a.m20()-b.m20()),Math.abs(a.m21()-b.m21())),Math.abs(a.m22()-b.m22()))));
    }
    static Map<String,Matrix4f> nativeBones(ModelSlotRenderData slot,ModelInstanceRenderData cart) {
        Map<String,Matrix4f> values=new HashMap<>();
        for(var body:slot.modelData) if(body.modelInstance==cart.modelInstance.parent && body.matrixPalette!=null
            && body.modelInstance.model.tag instanceof SkinningData skin) {
            for(String name:TRANSITION_BONES) { Matrix4f value=pose(body.matrixPalette,skin,name); if(value!=null)values.put(name,value); }
            break;
        }
        return values;
    }
    public static NativeSnapshot beforeGrounding(ModelSlotRenderData slot) {
        try {
            if(output==null || !(slot.character instanceof IsoPlayer player) || player!=IsoPlayer.getInstance())return null;
            for(var data:slot.modelData) if(data.modelInstance!=null && data.modelInstance.modelScript!=null
                && "WheelbarrowWood".equals(data.modelInstance.modelScript.getName()))
                return new NativeSnapshot(data,nativeBones(slot,data));
        } catch(Throwable error) { fail(error); }
        return null;
    }
    static double matrixDifference(Map<String,Matrix4f> before,Map<String,Matrix4f> after,String bone) {
        return difference(before.get(bone),after.get(bone));
    }
    public static void afterGrounding(ModelSlotRenderData slot,NativeSnapshot before) {
        if(before==null||output==null)return;
        try {
            var old=before.bones();var now=nativeBones(slot,before.cart());
            Matrix4f spine0=old.get("Bip01_Spine"),spine1=now.get("Bip01_Spine");
            Matrix4f torso0=old.get("Bip01_Spine1"),torso1=now.get("Bip01_Spine1");
            double torsoBefore=segment(spine0,torso0),torsoAfter=segment(spine1,torso1);
            double[] metrics={spine1==null||spine0==null?Double.NaN:spine1.m30()-spine0.m30(),
                spine1==null||spine0==null?Double.NaN:spine1.m31()-spine0.m31(),
                spine1==null||spine0==null?Double.NaN:spine1.m32()-spine0.m32(),orientationDifference(spine0,spine1),
                matrixDifference(old,now,"Bip01_L_Thigh"),matrixDifference(old,now,"Bip01_R_Thigh"),
                matrixDifference(old,now,"Bip01_L_Calf"),matrixDifference(old,now,"Bip01_R_Calf"),
                arm(old,"L"),arm(now,"L"),arm(old,"R"),arm(now,"R"),torsoBefore,torsoAfter,torsoAfter-torsoBefore,
                Math.max(Math.max(matrixDifference(old,now,"Bip01_L_Thigh"),matrixDifference(old,now,"Bip01_R_Thigh")),
                    Math.max(matrixDifference(old,now,"Bip01_L_Calf"),matrixDifference(old,now,"Bip01_R_Calf")))};
            row("grounding",slot,before.cart(),NO_BONE,metrics);
        } catch(Throwable error) { fail(error); }
    }
    static double difference(Matrix4f a,Matrix4f b) {
        if(a==null || b==null)return Double.NaN;
        float[] x=a.get(new float[16]),y=b.get(new float[16]);double max=0;
        for(int i=0;i<16;i++)max=Math.max(max,Math.abs(x[i]-y[i]));return max;
    }
    static double[] bones(ModelSlotRenderData slot,ModelInstanceRenderData cart,Matrix4f transform) {
        double[] result={Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN};
        for(var body:slot.modelData) {
            if(body.modelInstance!=cart.modelInstance.parent || body.matrixPalette==null
                || !(body.modelInstance.model.tag instanceof SkinningData skin))continue;
            double upper=0,legs=0,spine=0,clavicle=0;boolean compared=false;
            for(String name:new String[]{"Bip01_Spine","Bip01_Spine1","Bip01_L_Clavicle","Bip01_R_Clavicle","Bip01_L_Hand","Bip01_R_Hand","Bip01_L_Forearm","Bip01_R_Forearm","Bip01_L_Thigh","Bip01_R_Thigh","Bip01_L_Calf","Bip01_R_Calf"}) {
                Matrix4f value=pose(body.matrixPalette,skin,name);if(value==null)continue;
                boolean leg=name.contains("Thigh")||name.contains("Calf");
                if(!leg)value=new Matrix4f(transform).invert().mul(value);
                Matrix4f previous=previousBones.put(name,new Matrix4f(value));
                if(previous!=null) {
                    compared=true;double change=difference(value,previous);
                    if(leg)legs=Math.max(legs,change);else upper=Math.max(upper,change);
                    if(name.contains("Spine"))spine=Math.max(spine,change);
                    if(name.contains("Clavicle"))clavicle=Math.max(clavicle,change);
                }
                if(name.endsWith("Hand")) {
                    int at=name.contains("_L_")?0:3;
                    result[at]=value.m30();result[at+1]=value.m31();result[at+2]=value.m32();
                }
            }
            if(compared){result[6]=upper;result[7]=legs;result[8]=spine;result[9]=clavicle;}break;
        }
        return result;
    }
    static void row(String event,ModelSlotRenderData slot,ModelInstanceRenderData data,double[] bone) throws Exception { row(event,slot,data,bone,NO_TRANSITION); }
    static void row(String event,ModelSlotRenderData slot,ModelInstanceRenderData data,double[] bone,double[] transition) throws Exception {
        var player=(IsoPlayer)slot.character;
        Matrix4f transform=new Matrix4f(data.xfrm).transpose();
        double[] center=world(slot,transform.transformPosition(new Vector3f(CX,CY,CZ)),false);
        double radial=Math.hypot(transform.m11(),transform.m21());
        Vector3f support=new Vector3f(CX+(transform.m01()>0?-H:H),CY,CZ);
        if(radial>0)support.add(0,(float)(-R*transform.m11()/radial),(float)(-R*transform.m21()/radial));
        Vector3f contactLocal=transform.transformPosition(support);
        double[] contact=world(slot,new Vector3f(contactLocal),false);
        double[] alongY=world(slot,transform.transformDirection(new Vector3f(0,1,0)),true);
        double[] alongZ=world(slot,transform.transformDirection(new Vector3f(0,0,1)),true);
        double[] normal=normal(alongY,alongZ);
        double planeLength=Math.hypot(normal[0],normal[1]);
        double forwardX=-normal[1]/planeLength,forwardY=normal[0]/planeLength;
        var row=new StringBuilder(1024).append(++sequence).append(',').append((System.nanoTime()-start)/1e9)
            .append(',').append(event).append(',').append(drive()).append(',')
            .append(player.getPrimaryHandItem()==null?"none":player.getPrimaryHandItem().getFullType());
        for(double value:new double[]{phase(data),zombie.GameTime.getInstance().getRealworldSecondsSinceLastUpdate(),
            player.getX(),player.getY(),player.getZ(),slot.x,slot.y,slot.z,slot.animPlayerAngle,
            player.getAnimationPlayer().getAngle(),net.alexredby.pztoolkitjavapatches.CartSteeringHooks.lean(player),
            center[0],center[1],center[2],contact[0],contact[1],contact[2],contactLocal.y,
            normal[0],normal[1],normal[2],forwardX,forwardY,Math.atan2(forwardY,forwardX),
            player.getVariableFloat("ToolkitCartStepX",0),player.getVariableFloat("ToolkitCartStepY",0)})row.append(',').append(value);
        row.append(',').append(player.isJustMoved()?1:0);
        for(double value:bone)row.append(',').append(value);
        for(double value:transition)row.append(',').append(value);
        row.append(',').append(System.currentTimeMillis()).append('\n');output.write(row.toString());output.flush();
    }
    static void fail(Throwable error) {
        if(!errorLogged){errorLogged=true;System.err.println("[WOOD_WHEEL_NATIVE_PROBE] ERROR "+error);error.printStackTrace();}
    }
    public static synchronized void snapshot(ModelSlotRenderData slot) {
        if(output==null || !(slot.character instanceof IsoPlayer player) || player!=IsoPlayer.getInstance())return;
        long now=System.nanoTime();if(now-lastSnapshot<INTERVAL)return;
        try {for(var data:slot.modelData) {
            var instance=data.modelInstance;
            if(instance==null || instance.parent==null || instance.modelScript==null
                || !"WheelbarrowWood".equals(instance.modelScript.getName()) || !Double.isFinite(phase(data)))continue;
            lastSnapshot=now;double[] bone=bones(slot,data,new Matrix4f(data.xfrm).transpose());snapshots.put(data,bone);
            row("snapshot",slot,data,bone);break;
        }}catch(Throwable error){fail(error);}
    }
    static void proof(ModelInstanceRenderData data) throws Exception {
        var vb=data.modelInstance.model.mesh.vb;
        var handle=(VertexBufferObject.Vbo)field(vb,"handle");
        int old=GL11.glGetInteger(GL15.GL_ARRAY_BUFFER_BINDING);
        try {
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER,handle.vboId);
            int bytes=GL15.glGetBufferParameteri(GL15.GL_ARRAY_BUFFER,GL15.GL_BUFFER_SIZE);
            var buffer=BufferUtils.createByteBuffer(bytes);GL15.glGetBufferSubData(GL15.GL_ARRAY_BUFFER,0,buffer);
            byte[] raw=new byte[bytes];buffer.get(raw);
            if(!meshProof)Files.write(directory.resolve("WheelbarrowWood.bin"),raw,java.nio.file.StandardOpenOption.CREATE_NEW);
            String hash=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(raw));
            Files.writeString(directory.resolve("wood-wheel-mesh-proof.json"),"{\n  \"vboId\": "+handle.vboId+",\n  \"eboId\": "+handle.eboId+",\n  \"bytes\": "+bytes+",\n  \"indices\": "+handle.numElements+",\n  \"phase\": "+phase(data)+",\n  \"proofAfterPhaseChanged\": "+meshProof+",\n  \"sha256\": \""+hash+"\",\n  \"matchesOriginal\": "+hash.equals("0f99448cda120bad9f324f38bdbf994f8788ab6731473533475fb6eaf3f4c948")+"\n}\n");
        } finally {GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER,old);}
    }
    public static synchronized void draw(ModelSlotRenderData slot,ModelInstanceRenderData data,boolean rendered) {
        if(output==null || !rendered || !(slot.character instanceof IsoPlayer player) || player!=IsoPlayer.getInstance())return;
        try {
            if(!meshProof){proof(data);meshProof=true;proofPhase=phase(data);}
            else if(!movingMeshProof && Math.abs(Math.IEEEremainder(phase(data)-proofPhase,Math.PI*2))>.25){proof(data);movingMeshProof=true;}
            if(!firstDraw){firstDraw=true;System.out.println("[WOOD_WHEEL_NATIVE_PROBE] successful native split draw phase="+phase(data));}
            long now=System.nanoTime();if(now-lastDraw<INTERVAL)return;lastDraw=now;
            double[] bone=snapshots.get(data);if(bone==null)bone=new double[]{Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN,Double.NaN};
            row("draw",slot,data,bone);
        }catch(Throwable error){fail(error);}
    }
    public static class Grounding {
        @Advice.OnMethodEnter(suppress=Throwable.class)
        public static NativeSnapshot enter(@Advice.Argument(0) ModelSlotRenderData slot){return WoodenWheelNativeProbe.beforeGrounding(slot);}
        @Advice.OnMethodExit(suppress=Throwable.class)
        public static void exit(@Advice.Argument(0) ModelSlotRenderData slot,@Advice.Enter NativeSnapshot before){
            WoodenWheelNativeProbe.afterGrounding(slot,before);WoodenWheelNativeProbe.snapshot(slot);
        }
    }
    public static class Drawing {
        @Advice.OnMethodExit(suppress=Throwable.class)
        public static void exit(@Advice.Argument(1) ModelSlotRenderData slot,@Advice.Argument(2) ModelInstanceRenderData data,
            @Advice.Return boolean rendered){WoodenWheelNativeProbe.draw(slot,data,rendered);}
    }
    public static synchronized void agentmain(String args,Instrumentation instrumentation) throws Exception {
        if(output!=null){output.close();output=null;}
        if("stop".equals(args)){System.out.println("[WOOD_WHEEL_NATIVE_PROBE] stopped");return;}
        if(args==null || args.isBlank() || !Path.of(args).isAbsolute())throw new IllegalArgumentException("Agent args: absolute output directory, or stop");
        directory=Path.of(args);
        if(!Files.isDirectory(directory))throw new IllegalArgumentException("Output directory must exist");
        output=Files.newBufferedWriter(directory.resolve("wood-wheel-native.csv"),java.nio.file.StandardOpenOption.CREATE_NEW);
        output.write("sequence,time,event,drive,type,phase,dt,playerX,playerY,playerZ,slotX,slotY,slotZ,slotAngle,actorHeading,lean,wheelX,wheelY,wheelZ,contactX,contactY,contactZ,contactLocalY,planeX,planeY,planeZ,forwardX,forwardY,wheelYaw,stepX,stepY,justMoved,leftHandX,leftHandY,leftHandZ,rightHandX,rightHandY,rightHandZ,upperDelta,legDelta,spineDelta,clavicleDelta,spineRootDx,spineRootDy,spineRootDz,spineRootOrientationMaxDelta,leftThighMatrixDelta,rightThighMatrixDelta,leftCalfMatrixDelta,rightCalfMatrixDelta,leftArmLengthBefore,leftArmLengthAfter,rightArmLengthBefore,rightArmLengthAfter,torsoLengthBefore,torsoLengthAfter,torsoLengthDelta,maxLegMatrixDelta,wallTimeMillis\n");output.flush();
        start=System.nanoTime();sequence=lastSnapshot=lastDraw=0;firstDraw=meshProof=movingMeshProof=errorLogged=false;snapshots.clear();previousBones.clear();
        if(!installed){
            new AgentBuilder.Default().disableClassFormatChanges().with(AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
                .type(named("net.alexredby.pztoolkitjavapatches.CartGrounding"))
                .transform((b,d,l,m,p)->b.visit(Advice.to(Grounding.class).on(named("render"))))
                .type(named("net.alexredby.pztoolkitjavapatches.CartWheelSpin"))
                .transform((b,d,l,m,p)->b.visit(Advice.to(Drawing.class).on(named("render"))))
                .installOn(instrumentation);installed=true;
        }
        System.out.println("[WOOD_WHEEL_NATIVE_PROBE] capturing "+directory.resolve("wood-wheel-native.csv"));
    }
}
