import java.io.BufferedWriter;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;
import java.util.WeakHashMap;
import net.bytebuddy.agent.builder.AgentBuilder;
import net.bytebuddy.asm.Advice;
import static net.bytebuddy.matcher.ElementMatchers.*;
import org.joml.Matrix4f;
import org.lwjgl.BufferUtils;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL15;
import zombie.core.skinnedmodel.model.VertexBufferObject;
import zombie.core.skinnedmodel.shader.Shader;
import zombie.inventory.InventoryItem;

/** Read-only successful draw receipts; every submitted matrix is copied from the real Shader call. */
public final class ShoppingWheelProbe {
    static final long INTERVAL=50_000_000L;
    static final int MAX_CALLS=2048;
    private static final String TARGET="net.alexredby.pztoolkitjavapatches.CartShoppingWheels";
    static final ThreadLocal<Scope> active=new ThreadLocal<>();
    private static final WeakHashMap<VertexBufferObject,Proof> proofs=new WeakHashMap<>();
    private static final WeakHashMap<Object,FollowPose> follows=new WeakHashMap<>();
    private static final HashSet<String> errors=new HashSet<>();
    private static volatile BufferedWriter output;
    private static volatile long generation;
    private static Path directory;
    private static long lastSample,sequence;
    private static int meshSequence;
    private static boolean installed;

    public static final class Scope {
        Scope parent;
        VertexBufferObject buffer;
        Shader shader;
        Object frame;
        long generation,nanoTime,wallTime,itemId;
        boolean sample,transpose;
        String error;
        float[] cart;
        float[][] relative;
        double[] phases,casters;
        FollowPose follow;
        final List<Submitted> submitted=new ArrayList<>();
    }
    static final class Submitted {
        final Scope scope;
        final float[] matrix;
        final boolean transpose;
        Submitted(Scope scope,float[] matrix,boolean transpose){this.scope=scope;this.matrix=matrix;this.transpose=transpose;}
    }
    private record Proof(int id,int vboId,int eboId,int indices,String json) {}
    static record FollowPose(float x,float y,float angle,long producerNanoTime,long returnNanoTime,long wallTimeMillis,float[] cart) {}
    private record Point(int x,int y,int z) implements Comparable<Point> {
        public int compareTo(Point b){int c=Integer.compareUnsigned(x,b.x);if(c==0)c=Integer.compareUnsigned(y,b.y);return c==0?Integer.compareUnsigned(z,b.z):c;}
    }
    static Object field(Object object,String name)throws Exception {
        Field f=object.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(object);
    }
    static void require(boolean valid,String reason){if(!valid)throw new IllegalStateException(reason);}
    static float[] copy(Matrix4f matrix) {
        require(matrix!=null&&matrix.isFinite(),"missing/nonfinite matrix");return matrix.get(new float[16]);
    }
    static double[] finite(double[] values,int count) {
        require(values!=null&&values.length==count,"missing/wrong-sized motion snapshot");
        var result=values.clone();for(double value:result)require(Double.isFinite(value),"nonfinite motion snapshot");return result;
    }
    static void snapshot(Scope scope,Object frame,Matrix4f cart)throws Exception {
        require(frame!=null,"missing Frame");scope.cart=copy(cart);scope.frame=frame;
        Object item=field(frame,"item");
        require(item instanceof InventoryItem&&"SaucedCarts.ShoppingCart".equals(((InventoryItem)item).getFullType()),"missing/non-shopping item");
        scope.itemId=((InventoryItem)item).getID();
        scope.phases=finite((double[])field(frame,"phases"),4);scope.casters=finite((double[])field(frame,"casters"),2);
        var relative=(Matrix4f[])field(frame,"relative");require(relative!=null&&relative.length==7,"missing part transforms");
        scope.relative=new float[7][];for(int i=0;i<7;i++)scope.relative[i]=copy(relative[i]);
    }
    static boolean eligible(long now,long previous){return previous==0||now-previous>=INTERVAL;}
    static FollowPose followPose(float x,float y,float angle,Matrix4f cart,long producerNanoTime) {
        require(Float.isFinite(x)&&Float.isFinite(y)&&Float.isFinite(angle)&&producerNanoTime>=0,"nonfinite/invalid native follow pose");
        return new FollowPose(x,y,angle,producerNanoTime,System.nanoTime(),System.currentTimeMillis(),copy(cart));
    }
    public static synchronized void recordFollow(Object frame,float x,float y,float angle,Matrix4f cart,long producerNanoTime,Throwable thrown) {
        if(output==null)return;
        try {
            require(thrown==null,"CartShoppingWheels.follow failed: "+thrown);
            if(frame!=null)follows.put(frame,followPose(x,y,angle,cart,producerNanoTime));
        }catch(Throwable error){fail(error);}
    }
    public static Object begin(VertexBufferObject buffer,Shader shader,Matrix4f cart,Object frame,boolean transpose) {
        var scope=new Scope();scope.parent=active.get();scope.buffer=buffer;scope.shader=shader;scope.transpose=transpose;
        scope.nanoTime=System.nanoTime();scope.wallTime=System.currentTimeMillis();active.set(scope);
        try {
            synchronized(ShoppingWheelProbe.class) {
                scope.generation=generation;
                if(output==null||!eligible(scope.nanoTime,lastSample))return scope;
                lastSample=scope.nanoTime;scope.sample=true;
            }
            require(buffer!=null&&shader!=null,"missing draw buffer/shader");snapshot(scope,frame,cart);
            synchronized(ShoppingWheelProbe.class){scope.follow=follows.get(frame);}
            require(scope.follow!=null,"draw Frame has no exact native follow identity");
        }catch(Throwable error){scope.error=error.toString();fail(error);}
        return scope;
    }
    public static Object beforeTransform(Shader shader,Matrix4f matrix,boolean transpose) {
        var scope=active.get();
        if(scope==null||!scope.sample||scope.error!=null||output==null||scope.generation!=generation||scope.shader!=shader)return null;
        try{return new Submitted(scope,copy(matrix),transpose);}
        catch(Throwable error){scope.error=error.toString();fail(error);return null;}
    }
    public static void afterTransform(Object token,Throwable thrown) {
        if(!(token instanceof Submitted submitted))return;
        var scope=submitted.scope;
        if(scope.generation!=generation||output==null)return;
        try {
            require(active.get()==scope,"unbalanced nested transform scope");
            require(thrown==null,"Shader.setTransformMatrix failed: "+thrown);
            require(scope.submitted.size()<MAX_CALLS,"too many submitted matrices");scope.submitted.add(submitted);
        }catch(Throwable error){scope.error=error.toString();fail(error);}
    }
    static boolean equal(float[] a,float[] b) {
        if(a==null||b==null||a.length!=16||b.length!=16)return false;
        for(int i=0;i<16;i++)if(!Float.isFinite(a[i])||!Float.isFinite(b[i])||Math.abs(a[i]-b[i])>2e-6f)return false;
        return true;
    }
    static float[] expected(Scope scope,int part) {
        var cart=new Matrix4f().set(scope.cart);
        if(scope.transpose)cart.transpose();cart.mul(new Matrix4f().set(scope.relative[part]));
        if(scope.transpose)cart.transpose();return copy(cart);
    }
    static float[][] validate(Scope scope,int[][] runs,int indices) {
        require(scope.error==null,"invalid sampled scope: "+scope.error);
        require(runs!=null&&runs.length>0&&scope.submitted.size()==runs.length+1,"missing/unexpected Shader submissions");
        var parts=new float[7][];int offset=0;
        for(int i=0;i<runs.length;i++) {
            int[] run=runs[i];require(run!=null&&run.length==3&&run[0]==offset&&run[1]>0&&run[1]%3==0&&run[2]>=0&&run[2]<7,"invalid cached index run");
            offset+=run[1];require(offset<=indices,"index runs exceed native EBO");
            var call=scope.submitted.get(i);require(call.transpose==scope.transpose,"submitted transpose differs from draw");
            require(equal(call.matrix,expected(scope,run[2])),"actual submitted matrix differs for part "+run[2]);
            if(parts[run[2]]==null)parts[run[2]]=call.matrix.clone();
            else require(equal(parts[run[2]],call.matrix),"same part received inconsistent matrices");
        }
        require(offset==indices,"index runs omit native EBO triangles");
        for(int part=0;part<7;part++)require(parts[part]!=null,"part "+part+" was not submitted");
        var restored=scope.submitted.get(scope.submitted.size()-1);
        require(restored.transpose==scope.transpose&&equal(restored.matrix,scope.cart),"cart transform was not restored");
        return parts;
    }
    static int[][] runs(Scope scope)throws Exception {
        Class<?> owner=scope.frame.getClass().getEnclosingClass();require(owner!=null&&TARGET.equals(owner.getName()),"unexpected Frame owner");
        Field cache=owner.getDeclaredField("meshes");cache.setAccessible(true);Object mesh=((Map<?,?>)cache.get(null)).get(scope.buffer);
        require(mesh!=null,"successful draw has no verified mesh cache");var source=(int[][])field(mesh,"runs");require(source!=null,"missing verified index runs");
        var result=new int[source.length][];for(int i=0;i<result.length;i++)result[i]=source[i].clone();return result;
    }
    static String sha(byte[] bytes)throws Exception{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));}
    static String positionHash(float[] xyz)throws Exception {
        var points=new TreeSet<Point>();
        for(int i=0;i<xyz.length;i+=3) {
            require(Float.isFinite(xyz[i])&&Float.isFinite(xyz[i+1])&&Float.isFinite(xyz[i+2]),"nonfinite native VBO position");
            points.add(new Point(Float.floatToRawIntBits(xyz[i]),Float.floatToRawIntBits(xyz[i+1]),Float.floatToRawIntBits(xyz[i+2])));
        }
        var digest=MessageDigest.getInstance("SHA-256");var bytes=ByteBuffer.allocate(12).order(ByteOrder.LITTLE_ENDIAN);
        for(var p:points){bytes.clear();bytes.putInt(p.x).putInt(p.y).putInt(p.z);digest.update(bytes.array());}
        return HexFormat.of().formatHex(digest.digest());
    }
    private static byte[] gpu(int target,int handle,int maximum) {
        GL15.glBindBuffer(target,handle);int length=GL15.glGetBufferParameteri(target,GL15.GL_BUFFER_SIZE);
        require(length>0&&length<=maximum,"unexpected GPU buffer size: "+length);
        var copy=BufferUtils.createByteBuffer(length);GL15.glGetBufferSubData(target,0,copy);var bytes=new byte[length];copy.get(bytes);return bytes;
    }
    private static Proof proof(VertexBufferObject buffer)throws Exception {
        var handle=(VertexBufferObject.Vbo)field(buffer,"handle");require(handle!=null&&handle.vboId>0&&handle.eboId>0&&handle.numElements>0,"missing native GPU handles");
        var cached=proofs.get(buffer);
        if(cached!=null&&cached.vboId==handle.vboId&&cached.eboId==handle.eboId&&cached.indices==handle.numElements)return cached;
        var format=(VertexBufferObject.VertexFormat)field(buffer,"vertexFormat");int position=format.indexOf(VertexBufferObject.VertexType.VertexArray);
        require(format.getStride()==32&&position>=0&&format.getElement(position).byteOffset==0,"unsupported native VBO format");
        int oldArray=GL11.glGetInteger(GL15.GL_ARRAY_BUFFER_BINDING),oldElements=GL11.glGetInteger(GL15.GL_ELEMENT_ARRAY_BUFFER_BINDING);
        byte[] vertices,indices;
        try{vertices=gpu(GL15.GL_ARRAY_BUFFER,handle.vboId,2_000_000);indices=gpu(GL15.GL_ELEMENT_ARRAY_BUFFER,handle.eboId,4_000_000);}
        finally{GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER,oldArray);GL15.glBindBuffer(GL15.GL_ELEMENT_ARRAY_BUFFER,oldElements);}
        require(vertices.length%32==0&&indices.length==(long)handle.numElements*4,"native GPU byte/count mismatch");
        var source=ByteBuffer.wrap(vertices).order(ByteOrder.nativeOrder());float[] xyz=new float[vertices.length/32*3];
        var packed=ByteBuffer.allocate(xyz.length*4).order(ByteOrder.LITTLE_ENDIAN);
        for(int i=0;i<xyz.length/3;i++)for(int j=0;j<3;j++){float value=source.getFloat(i*32+j*4);xyz[i*3+j]=value;packed.putFloat(value);}
        String positionsHash=positionHash(xyz);var nativeIndices=ByteBuffer.wrap(indices).order(ByteOrder.nativeOrder());
        while(nativeIndices.hasRemaining()){int index=nativeIndices.getInt();require(index>=0&&index<xyz.length/3,"native EBO index out of range");}
        int id=++meshSequence;String stem="shopping-wheel-"+id;
        String vboHash=sha(vertices),eboHash=sha(indices),xyzHash=sha(packed.array());
        String json="{\"meshId\":"+id+",\"vboId\":"+handle.vboId+",\"eboId\":"+handle.eboId+",\"vboBytes\":"+vertices.length
            +",\"eboBytes\":"+indices.length+",\"vertices\":"+xyz.length/3+",\"indices\":"+handle.numElements+",\"stride\":32,\"positionOffset\":0,\"gpuByteOrder\":\""
            +(ByteOrder.nativeOrder()==ByteOrder.LITTLE_ENDIAN?"little-endian":"big-endian")+"\",\"positionsByteOrder\":\"little-endian\",\"vboSha256\":\""+vboHash
            +"\",\"eboSha256\":\""+eboHash+"\",\"positionsSha256\":\""+xyzHash+"\",\"positionSetSha256\":\""+positionsHash
            +"\",\"vboFile\":\""+stem+"-vertices.bin\",\"eboFile\":\""+stem+"-indices.bin\",\"positionsFile\":\""+stem+"-positions.bin\"}";
        Files.write(directory.resolve(stem+"-vertices.bin"),vertices,StandardOpenOption.CREATE_NEW);
        Files.write(directory.resolve(stem+"-indices.bin"),indices,StandardOpenOption.CREATE_NEW);
        Files.write(directory.resolve(stem+"-positions.bin"),packed.array(),StandardOpenOption.CREATE_NEW);
        Files.writeString(directory.resolve(stem+"-mesh.json"),json+"\n",StandardOpenOption.CREATE_NEW);
        var result=new Proof(id,handle.vboId,handle.eboId,handle.numElements,json);proofs.put(buffer,result);return result;
    }
    static void array(StringBuilder out,float[] values){out.append('[');for(int i=0;i<values.length;i++){if(i>0)out.append(',');out.append(values[i]);}out.append(']');}
    static void array(StringBuilder out,double[] values){out.append('[');for(int i=0;i<values.length;i++){if(i>0)out.append(',');out.append(values[i]);}out.append(']');}
    static void matrices(StringBuilder out,float[][] values){out.append('[');for(int i=0;i<values.length;i++){if(i>0)out.append(',');array(out,values[i]);}out.append(']');}
    public static void end(Object token,boolean result,Throwable thrown) {
        if(!(token instanceof Scope scope))return;
        try {
            synchronized(ShoppingWheelProbe.class) {
                if(output==null||scope.generation!=generation)return;
                require(result&&thrown==null,"CartShoppingWheels.draw failed: result="+result+" thrown="+thrown);
                if(!scope.sample)return;
                require(active.get()==scope,"unbalanced nested draw scope");
                int[][] runs=runs(scope);var handle=(VertexBufferObject.Vbo)field(scope.buffer,"handle");
                var parts=validate(scope,runs,handle.numElements);var mesh=proof(scope.buffer);
                var row=new StringBuilder(8192).append("{\"sequence\":").append(++sequence).append(",\"nanoTime\":").append(scope.nanoTime)
                    .append(",\"wallTimeMillis\":").append(scope.wallTime).append(",\"drawDurationNanos\":").append(System.nanoTime()-scope.nanoTime)
                    .append(",\"thread\":").append(Thread.currentThread().getId()).append(",\"source\":\"").append(scope.transpose?"held":"world")
                    .append("\",\"sourceMeaning\":\"draw transpose call context\",\"itemId\":").append(scope.itemId)
                    .append(",\"transpose\":").append(scope.transpose).append(",\"result\":true,\"matrixOrder\":\"column-major\",\"cart\":");
                array(row,scope.cart);row.append(",\"phases\":");array(row,scope.phases);row.append(",\"casters\":");array(row,scope.casters);
                row.append(",\"relative\":");matrices(row,scope.relative);row.append(",\"submittedParts\":");matrices(row,parts);
                var follow=scope.follow;require(follow!=null,"missing producer pose");
                row.append(",\"nativeFollow\":{\"x\":").append(follow.x).append(",\"y\":").append(follow.y).append(",\"angle\":").append(follow.angle)
                    .append(",\"producerNanoTime\":").append(follow.producerNanoTime).append(",\"returnNanoTime\":").append(follow.returnNanoTime)
                    .append(",\"wallTimeMillis\":").append(follow.wallTimeMillis).append(",\"matrixOrder\":\"column-major\",\"cart\":");
                array(row,follow.cart);row.append('}');
                row.append(",\"calls\":[");
                for(int i=0;i<scope.submitted.size();i++) {
                    if(i>0)row.append(',');var call=scope.submitted.get(i);boolean restore=i==runs.length;
                    row.append("{\"part\":").append(restore?-1:runs[i][2]).append(",\"restore\":").append(restore)
                        .append(",\"transpose\":").append(call.transpose);
                    if(!restore)row.append(",\"firstIndex\":").append(runs[i][0]).append(",\"indexCount\":").append(runs[i][1]);
                    row.append(",\"matrix\":");array(row,call.matrix);row.append('}');
                }
                row.append("],\"mesh\":").append(mesh.json).append("}\n");output.write(row.toString());output.flush();
            }
        }catch(Throwable error){fail(error);}
        finally {
            if(active.get()==scope){if(scope.parent==null)active.remove();else active.set(scope.parent);}
            else{active.remove();fail(new IllegalStateException("draw scope restoration mismatch"));}
        }
    }
    private static synchronized void fail(Throwable error) {
        String key=error.getClass().getName()+": "+error.getMessage();
        if(errors.size()<32&&errors.add(key))System.err.println("[SHOPPING_WHEEL_PROBE] ERROR "+key);
    }
    public static class Drawing {
        @Advice.OnMethodEnter(suppress=Throwable.class)
        public static Object enter(@Advice.Argument(0) VertexBufferObject buffer,@Advice.Argument(1) Shader shader,
            @Advice.Argument(2) Matrix4f cart,@Advice.Argument(3) Object frame,@Advice.Argument(4) boolean transpose) {
            return ShoppingWheelProbe.begin(buffer,shader,cart,frame,transpose);
        }
        @Advice.OnMethodExit(onThrowable=Throwable.class,suppress=Throwable.class)
        public static void exit(@Advice.Enter Object token,@Advice.Return boolean result,@Advice.Thrown Throwable thrown){ShoppingWheelProbe.end(token,result,thrown);}
    }
    public static class Transforming {
        @Advice.OnMethodEnter(suppress=Throwable.class)
        public static Object enter(@Advice.This Shader shader,@Advice.Argument(0) Matrix4f matrix,@Advice.Argument(1) boolean transpose){return ShoppingWheelProbe.beforeTransform(shader,matrix,transpose);}
        @Advice.OnMethodExit(onThrowable=Throwable.class,suppress=Throwable.class)
        public static void exit(@Advice.Enter Object token,@Advice.Thrown Throwable thrown){ShoppingWheelProbe.afterTransform(token,thrown);}
    }
    public static class Following {
        @Advice.OnMethodExit(onThrowable=Throwable.class,suppress=Throwable.class)
        public static void exit(@Advice.Argument(1) float x,@Advice.Argument(2) float y,@Advice.Argument(3) float angle,
            @Advice.Argument(4) Matrix4f cart,@Advice.Argument(5) long now,@Advice.Return Object frame,@Advice.Thrown Throwable thrown) {
            ShoppingWheelProbe.recordFollow(frame,x,y,angle,cart,now,thrown);
        }
    }
    public static synchronized void agentmain(String args,Instrumentation instrumentation)throws Exception {
        generation++;var previous=output;output=null;if(previous!=null)previous.close();proofs.clear();follows.clear();lastSample=sequence=0;meshSequence=0;errors.clear();
        if("stop".equals(args)){System.out.println("[SHOPPING_WHEEL_PROBE] stopped");return;}
        require(args!=null&&!args.isBlank()&&Path.of(args).isAbsolute(),"Agent args: absolute output directory, or stop");directory=Path.of(args);
        require(Files.isDirectory(directory),"output directory must exist");
        output=Files.newBufferedWriter(directory.resolve("shopping-wheel-draws.jsonl"),StandardOpenOption.CREATE_NEW);
        try {
            if(!installed) {
                new AgentBuilder.Default().disableClassFormatChanges().with(AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
                    .with(new AgentBuilder.Listener.Adapter(){
                        @Override public void onError(String type,ClassLoader loader,net.bytebuddy.utility.JavaModule module,boolean loaded,Throwable error){fail(new IllegalStateException("instrumentation "+type,error));}
                    })
                    .type(named(TARGET)).transform((b,d,l,m,p)->b.visit(Advice.to(Drawing.class).on(named("draw").and(isStatic()).and(takesArguments(5))))
                        .visit(Advice.to(Following.class).on(named("follow").and(isStatic()).and(takesArguments(6)))))
                    .type(named("zombie.core.skinnedmodel.shader.Shader")).transform((b,d,l,m,p)->b.visit(Advice.to(Transforming.class)
                        .on(named("setTransformMatrix").and(takesArguments(Matrix4f.class,boolean.class)))))
                    .installOn(instrumentation);installed=true;
                require(errors.isEmpty(),"instrumentation installation failed");
                System.out.println("[SHOPPING_WHEEL_PROBE] CAPTURE_READY "+directory.resolve("shopping-wheel-draws.jsonl"));
            }else System.out.println("[SHOPPING_WHEEL_PROBE] capturing "+directory.resolve("shopping-wheel-draws.jsonl"));
        }catch(Throwable error){var writer=output;output=null;generation++;if(writer!=null)writer.close();fail(error);throw error;}
    }
}
