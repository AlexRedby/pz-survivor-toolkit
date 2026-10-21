import java.io.BufferedWriter;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Method;
import java.security.MessageDigest;
import java.util.HexFormat;
import org.lwjgl.BufferUtils;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL15;
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
    private static BufferedWriter solves;
    private static BufferedWriter cameras;
    private static long captureSerial;
    private record NativePose(zombie.characters.IsoPlayer player,long wall,float x,float y,float z,float heading,float angle) {}
    private record ConsumedCamera(zombie.core.skinnedmodel.ModelCamera camera,long wall,float x,float y,float z,float angle,boolean world,boolean vehicle) {}
    private static final class DrawFrame {
        final long id,wall;
        final NativePose nativePose;
        final ModelInstance body,cart;
        boolean bodyDrawn,cartDrawn;
        DrawFrame(long id,long wall,NativePose pose,ModelInstance body,ModelInstance cart) {
            this.id=id;this.wall=wall;this.nativePose=pose;this.body=body;this.cart=cart;
        }
    }
    private static final java.util.WeakHashMap<ModelSlotRenderData,NativePose> nativePoses=new java.util.WeakHashMap<>();
    private static final java.util.WeakHashMap<ModelSlotRenderData,DrawFrame> drawFrames=new java.util.WeakHashMap<>();
    private static final ThreadLocal<ConsumedCamera> consumedCamera=new ThreadLocal<>();
    private static float slotField(ModelSlotRenderData slot,String name) throws Exception {
        var field=ModelSlotRenderData.class.getDeclaredField(name);field.setAccessible(true);return field.getFloat(slot);
    }
    public static synchronized void rememberNative(ModelSlotRenderData slot,zombie.core.skinnedmodel.ModelManager.ModelSlot source) {
        nativePoses.remove(slot);drawFrames.remove(slot);
        if(output==null || source==null || !(source.character instanceof zombie.characters.IsoPlayer player))return;
        float heading=player.getDirectionAngleRadians();
        var animation=player.getAnimationPlayer();
        float angle=animation==null?heading+(float)(Math.PI/2):animation.getRenderedAngle();
        nativePoses.put(slot,new NativePose(player,System.currentTimeMillis(),player.getX(),player.getY(),player.getZ(),heading,angle));
    }
    private static DrawFrame prepareDraw(ModelSlotRenderData slot,ModelInstance body,ModelInstance cart) {
        var pose=nativePoses.get(slot);
        if(pose==null || slot.character!=pose.player)throw new IllegalStateException("Missing original native slot pose");
        var frame=new DrawFrame(++captureSerial,System.currentTimeMillis(),pose,body,cart);
        drawFrames.put(slot,frame);return frame;
    }
    private static String renderFields(ModelSlotRenderData slot,DrawFrame frame) throws Exception {
        var nativePose=frame.nativePose;
        float expected=zombie.iso.IsoDepthHelper.getSquareDepthData(
            (int)Math.floor(slotField(slot,"camCharacterX")),(int)Math.floor(slotField(slot,"camCharacterY")),
            slot.x+slotField(slot,"fixJigglyModelsSquareX"),slot.y+slotField(slot,"fixJigglyModelsSquareY"),slot.z).depthStart;
        return new StringBuilder(512).append(",\"renderProbeVersion\":1,\"captureId\":").append(frame.id)
            .append(",\"slotToken\":").append(System.identityHashCode(slot))
            .append(",\"nativeWallTimeMillis\":").append(nativePose.wall)
            .append(",\"nativeX\":").append(nativePose.x).append(",\"nativeY\":").append(nativePose.y)
            .append(",\"nativeZ\":").append(nativePose.z).append(",\"nativeHeading\":").append(nativePose.heading)
            .append(",\"nativeRenderAngle\":").append(nativePose.angle)
            .append(",\"squareDepth\":").append(slot.squareDepth).append(",\"expectedSquareDepth\":").append(expected).toString();
    }
    public static void beginCamera(zombie.core.skinnedmodel.ModelCamera camera) {
        consumedCamera.set(new ConsumedCamera(camera,System.currentTimeMillis(),camera.x,camera.y,camera.z,camera.useAngle,camera.useWorldIso,camera.inVehicle));
    }
    public static void endCamera() {consumedCamera.remove();}
    public static synchronized void draw(ModelSlotRenderData slot,ModelInstanceRenderData data) throws Exception {
        if(cameras==null || data==null)return;
        var frame=drawFrames.get(slot);if(frame==null)return;
        boolean body=data.modelInstance==frame.body,cart=data.modelInstance==frame.cart;
        if(!body && !cart || body && frame.bodyDrawn || cart && frame.cartDrawn)return;
        var consumed=consumedCamera.get();var camera=zombie.core.skinnedmodel.ModelCamera.instance;
        if(consumed==null || camera!=consumed.camera || slot.character!=frame.nativePose.player)
            throw new IllegalStateException("Draw lacks matching consumed native camera/actor");
        var row=new StringBuilder(1024).append("{\"renderProbeVersion\":1,\"captureId\":").append(frame.id)
            .append(",\"slotToken\":").append(System.identityHashCode(slot))
            .append(",\"id\":").append(frame.nativePose.player.getOnlineID())
            .append(",\"primary\":").append(frame.nativePose.player.getPrimaryHandItem()==null?-1:frame.nativePose.player.getPrimaryHandItem().getID())
            .append(",\"secondary\":").append(frame.nativePose.player.getSecondaryHandItem()==null?-1:frame.nativePose.player.getSecondaryHandItem().getID())
            .append(",\"model\":").append(jsonString(data.modelInstance.modelScript==null?null:data.modelInstance.modelScript.getName()))
            .append(",\"part\":").append(jsonString(body?"body":"cart"))
            .append(",\"captureWallTimeMillis\":").append(frame.wall)
            .append(",\"cameraWallTimeMillis\":").append(consumed.wall)
            .append(",\"wallTimeMillis\":").append(System.currentTimeMillis())
            .append(",\"cameraX\":").append(consumed.x).append(",\"cameraY\":").append(consumed.y)
            .append(",\"cameraZ\":").append(consumed.z).append(",\"cameraAngle\":").append(consumed.angle)
            .append(",\"cameraWorldIso\":").append(consumed.world).append(",\"cameraInVehicle\":").append(consumed.vehicle)
            .append(",\"currentCameraX\":").append(camera.x).append(",\"currentCameraY\":").append(camera.y)
            .append(",\"currentCameraZ\":").append(camera.z).append(",\"currentCameraAngle\":").append(camera.useAngle)
            .append(",\"slotX\":").append(slot.x).append(",\"slotY\":").append(slot.y)
            .append(",\"slotZ\":").append(slot.z).append(",\"slotAngle\":").append(slot.animPlayerAngle)
            .append(",\"squareDepth\":").append(slot.squareDepth).append(",\"depthBias\":").append(data.depthBias).append("}\n");
        cameras.write(row.toString());cameras.flush();
        if(body)frame.bodyDrawn=true;else frame.cartDrawn=true;
    }
    public static class NativeCapture {
        @Advice.OnMethodEnter
        public static void enter(@Advice.This ModelSlotRenderData slot,@Advice.Argument(0) zombie.core.skinnedmodel.ModelManager.ModelSlot source) {
            ClearanceProbe.rememberNative(slot,source);
        }
    }
    public static class CameraBegin {
        @Advice.OnMethodEnter
        public static void enter(@Advice.This zombie.core.skinnedmodel.ModelCamera camera) {ClearanceProbe.beginCamera(camera);}
    }
    public static class CameraEnd {
        @Advice.OnMethodExit
        public static void exit() {ClearanceProbe.endCamera();}
    }
    public static class ActualDraw {
        @Advice.OnMethodEnter
        public static void enter(@Advice.Argument(0) ModelSlotRenderData slot,@Advice.Argument(1) ModelInstanceRenderData data) {
            try{ClearanceProbe.draw(slot,data);}catch(Throwable e){System.err.println("[CLEARANCE_PROBE] ERROR "+e);}
        }
    }
    private static Path directory;
    private static boolean meshProof, phaseMeshProof, meshError;
    private static double firstMeshPhase;
    private static String firstMeshHash;
    private static Method wheelPhase;
    private static final String MESH_SHA="0f99448cda120bad9f324f38bdbf994f8788ab6731473533475fb6eaf3f4c948";
    private static final ThreadLocal<StringBuilder> solve = new ThreadLocal<>();
    private static long last;
    private static boolean installed;
    private static boolean cartModel(String name) {
        if(name==null) return false;
        return switch(name) {
            case "WheelbarrowWood", "WheelbarrowMetal", "ShoppingCartModel", "ShoppingCartPartialModel", "ShoppingCartFullModel",
                "ShoppingCartFlashlightModel", "ShoppingCartFlashlightPartialModel", "ShoppingCartFlashlightFullModel" -> true;
            default -> false;
        };
    }
    private static boolean cartFamily(String type,String model) {
        return switch(type) {
            case "SaucedCarts.ShoppingCart" -> model.startsWith("ShoppingCart");
            case "SaucedWheelbarrow.WheelbarrowWood" -> "WheelbarrowWood".equals(model);
            case "SaucedWheelbarrow.WheelbarrowMetal" -> "WheelbarrowMetal".equals(model);
            default -> false;
        };
    }
    private static boolean captureModel(zombie.inventory.InventoryItem item,String actual) {
        // Pickup presentation renders its exact cart while native hands are still empty.
        return item==null?"WheelbarrowWood".equals(actual) || "WheelbarrowMetal".equals(actual)
            :cartFamily(item.getFullType(),actual);
    }
    private static String jsonString(String value) {
        if(value==null)return "null";
        var out=new StringBuilder("\"");
        for(char c:value.toCharArray()) {
            if(c=='\\' || c=='\"')out.append('\\').append(c);
            else if(c<32)out.append(String.format("\\u%04x",(int)c));
            else out.append(c);
        }
        return out.append('"').toString();
    }
    private static void matrix(StringBuilder row, Matrix4f value) {
        float[] v=value.get(new float[16]);row.append('[');
        for(int i=0;i<16;i++){if(i>0)row.append(',');row.append(v[i]);}row.append(']');
    }
    public static synchronized void snapshot(ModelSlotRenderData slot) throws Exception {
        if(output==null || System.nanoTime()-last<33_333_333L || !(slot.character instanceof zombie.characters.IsoPlayer player)
            || !nativePoses.containsKey(slot)) return;
        for(var cart:slot.modelData) {
            var instance=cart.modelInstance;
            if(instance==null || instance.parent==null || instance.modelScript==null
                || !cartModel(instance.modelScript.getName()))continue;
            var item=player.getPrimaryHandItem();
            String held=item==null?null:item.getStaticModel();
            String actual=instance.modelScript.getName();
            if(!captureModel(item,actual))continue;
            for(var body:slot.modelData) {
                if(body.modelInstance!=instance.parent || body.matrixPalette==null
                    || !(body.modelInstance.model.tag instanceof SkinningData skin))continue;
                var frame=prepareDraw(slot,body.modelInstance,instance);
                var row=new StringBuilder(8192).append("{\"wallTimeMillis\":").append(frame.wall)
                    .append(renderFields(slot,frame))
                    .append(",\"id\":").append(((zombie.characters.IsoPlayer)slot.character).getOnlineID()).append(",\"local\":").append(((zombie.characters.IsoPlayer)slot.character).isLocalPlayer()).append(",\"enabled\":").append(net.alexredby.pztoolkitjavapatches.CartSteeringHooks.enabled((zombie.characters.IsoPlayer)slot.character)).append(",\"female\":").append(slot.character.isFemale())
                    .append(",\"slotX\":").append(slot.x).append(",\"slotY\":").append(slot.y)
                    .append(",\"slotZ\":").append(slot.z).append(",\"slotAngle\":").append(slot.animPlayerAngle)
                    .append(",\"primary\":").append(player.getPrimaryHandItem()==null?-1:player.getPrimaryHandItem().getID())
                    .append(",\"secondary\":").append(player.getSecondaryHandItem()==null?-1:player.getSecondaryHandItem().getID())
                    .append(",\"modelProbeVersion\":1,\"model\":").append(jsonString(actual))
                    .append(",\"heldModel\":").append(jsonString(held))
                    .append(",\"overridePrimary\":").append(jsonString(player.overridePrimaryHandModel))
                    .append(",\"overrideSecondary\":").append(jsonString(player.overrideSecondaryHandModel))
                    .append(",\"cart\":");
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
    /** Read the already drawn wooden VBO without changing it or leaving another GL binding active. */
    public static synchronized void mesh(ModelSlotRenderData slot,ModelInstanceRenderData data,boolean rendered) {
        if(output==null || meshError || phaseMeshProof || !rendered
            || !(slot.character instanceof zombie.characters.IsoPlayer) || data==null
            || data.modelInstance==null || data.modelInstance.modelScript==null
            || !"WheelbarrowWood".equals(data.modelInstance.modelScript.getName()))return;
        try {
            if(wheelPhase==null) {
                wheelPhase=Class.forName("net.alexredby.pztoolkitjavapatches.CartWheelSpin")
                    .getDeclaredMethod("phase",ModelInstanceRenderData.class);
                wheelPhase.setAccessible(true);
            }
            Double value=(Double)wheelPhase.invoke(null,data);
            if(value==null || !Double.isFinite(value))throw new IllegalStateException("Missing native wooden wheel phase");
            double phase=value;
            if(meshProof && Math.abs(Math.IEEEremainder(phase-firstMeshPhase,Math.PI*2))<=.25)return;
            var vb=data.modelInstance.model.mesh.vb;
            var field=vb.getClass().getDeclaredField("handle");field.setAccessible(true);
            var handle=(VertexBufferObject.Vbo)field.get(vb);
            int old=GL11.glGetInteger(GL15.GL_ARRAY_BUFFER_BINDING);
            byte[] raw;
            int bytes;
            try {
                GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER,handle.vboId);
                bytes=GL15.glGetBufferParameteri(GL15.GL_ARRAY_BUFFER,GL15.GL_BUFFER_SIZE);
                if(bytes!=8116*32 || handle.numElements!=16914)
                    throw new IllegalStateException("Unexpected native wooden VBO layout: "+bytes+" / "+handle.numElements);
                var buffer=BufferUtils.createByteBuffer(bytes);
                GL15.glGetBufferSubData(GL15.GL_ARRAY_BUFFER,0,buffer);
                raw=new byte[bytes];buffer.get(raw);
            } finally {GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER,old);}
            String hash=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(raw));
            boolean matches=MESH_SHA.equals(hash);
            if(!meshProof)Files.write(directory.resolve("WheelbarrowWood.bin"),raw,StandardOpenOption.CREATE_NEW);
            var proof=new StringBuilder("{\n  \"wallTimeMillis\": ").append(System.currentTimeMillis())
                .append(",\n  \"id\": ").append(((zombie.characters.IsoPlayer)slot.character).getOnlineID())
                .append(",\n  \"local\": ").append(((zombie.characters.IsoPlayer)slot.character).isLocalPlayer())
                .append(",\n  \"vboId\": ").append(handle.vboId).append(",\n  \"eboId\": ").append(handle.eboId)
                .append(",\n  \"bytes\": ").append(bytes).append(",\n  \"indices\": ").append(handle.numElements)
                .append(",\n  \"phase\": ").append(phase).append(",\n  \"proofAfterPhaseChanged\": ").append(meshProof)
                .append(",\n  \"sha256\": ").append(jsonString(hash)).append(",\n  \"matchesOriginal\": ").append(matches);
            if(meshProof)proof.append(",\n  \"initialPhase\": ").append(firstMeshPhase)
                .append(",\n  \"initialSha256\": ").append(jsonString(firstMeshHash))
                .append(",\n  \"matchesInitial\": ").append(firstMeshHash.equals(hash));
            Files.writeString(directory.resolve(meshProof?"wood-wheel-mesh-phase-proof.json":"wood-wheel-mesh-proof.json"),
                proof.append("\n}\n").toString(),StandardOpenOption.CREATE_NEW);
            if(!matches || meshProof && !firstMeshHash.equals(hash))
                throw new IllegalStateException("Native wooden wheel mesh changed: "+hash);
            if(meshProof)phaseMeshProof=true;
            else {meshProof=true;firstMeshPhase=phase;firstMeshHash=hash;}
        } catch(Throwable error) {
            meshError=true;System.err.println("[CLEARANCE_PROBE] MESH ERROR "+error);error.printStackTrace();
            try {Files.writeString(directory.resolve("wood-wheel-mesh-error.json"),
                "{\"error\":"+jsonString(error.toString())+"}\n",StandardOpenOption.CREATE_NEW);}
            catch(Throwable failure){System.err.println("[CLEARANCE_PROBE] MESH ERROR OUTPUT "+failure);}
        }
    }
    public static class Drawing {
        @Advice.OnMethodExit(suppress=Throwable.class)
        public static void exit(@Advice.Argument(1) ModelSlotRenderData slot,@Advice.Argument(2) ModelInstanceRenderData data,
            @Advice.Return boolean rendered) {ClearanceProbe.mesh(slot,data,rendered);}
    }

    public static void beginSolve(String method, ModelSlotRenderData slot) {
        if(solves==null || !(slot.character instanceof zombie.characters.IsoPlayer player)) return;
        var status=net.alexredby.pztoolkitjavapatches.CartTransition.status(player);
        var row=new StringBuilder(2048).append("{\"wallTimeMillis\":").append(System.currentTimeMillis())
            .append(",\"method\":").append(jsonString(method)).append(",\"id\":").append(player.getOnlineID())
            .append(",\"local\":").append(player.isLocalPlayer())
            .append(",\"x\":").append(player.getX()).append(",\"y\":").append(player.getY())
            .append(",\"progress\":").append(status.rawget("progress"))
            .append(",\"pickup\":").append(status.rawget("pickup"))
            .append(",\"recovering\":").append(status.rawget("recovering"))
            .append(",\"failures\":[");
        solve.set(row);
    }
    public static void refusal(String method, String detail) {
        var row=solve.get();if(row==null)return;
        if(row.charAt(row.length()-1)!='[')row.append(',');
        row.append("{\"method\":").append(jsonString(method));
        if(detail!=null)row.append(',').append(detail);
        row.append('}');
    }
    public static String reachInput(Object[] args) {
        if(solve.get()==null)return null;
        var poses=(Matrix4f[])args[0];var actor=(SkinningData)args[1];
        var row=new StringBuilder(2048).append("\"bone\":").append(jsonString((String)args[2]))
            .append(",\"wood\":").append(args[5]).append(",\"weight\":").append(args[6])
            .append(",\"target\":");matrix(row,(Matrix4f)args[3]);row.append(",\"poses\":{");
        var bone=actor.getBone((String)args[2]);boolean comma=false;
        for(int i=0;bone!=null && i<4;i++,bone=bone.parent) {
            if(comma)row.append(',');comma=true;
            row.append(jsonString(bone.name)).append(':');matrix(row,poses[bone.index]);
        }
        return row.append('}').toString();
    }
    public static synchronized void finishSolve(boolean ok) throws Exception {
        var row=solve.get();solve.remove();if(row==null || solves==null)return;
        solves.write(row.append("],\"ok\":").append(ok).append("}\n").toString());solves.flush();
    }
    public static class Solve {
        @Advice.OnMethodEnter
        public static void enter(@Advice.Origin("#m") String method, @Advice.Argument(0) ModelSlotRenderData slot) {
            ClearanceProbe.beginSolve(method,slot);
        }
        @Advice.OnMethodExit(onThrowable=Throwable.class)
        public static void exit(@Advice.Return boolean ok, @Advice.Thrown Throwable thrown) {
            try {
                if(thrown!=null)ClearanceProbe.refusal("exception",null);
                ClearanceProbe.finishSolve(ok && thrown==null);
            } catch(Throwable e) {System.err.println("[CLEARANCE_PROBE] ERROR "+e);}
        }
    }
    public static class Refusal {
        @Advice.OnMethodExit
        public static void exit(@Advice.Origin("#m") String method, @Advice.Return boolean ok) {
            if(!ok)ClearanceProbe.refusal(method,null);
        }
    }
    public static class Reach {
        @Advice.OnMethodEnter
        public static String enter(@Advice.AllArguments Object[] args) {return ClearanceProbe.reachInput(args);}
        @Advice.OnMethodExit
        public static void exit(@Advice.Enter String input, @Advice.Return boolean ok) {
            if(!ok)ClearanceProbe.refusal("reach",input);
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
        if(solves!=null){solves.close();solves=null;}
        if(cameras!=null){cameras.close();cameras=null;}
        nativePoses.clear();drawFrames.clear();consumedCamera.remove();
        if("stop".equals(args)){System.out.println("[CLEARANCE_PROBE] stopped");return;}
        if(args==null || args.isBlank() || !Path.of(args).isAbsolute())throw new IllegalArgumentException("Agent args: absolute output directory, or stop");
        directory=Path.of(args);
        if(!Files.isDirectory(directory))throw new IllegalArgumentException("Output directory must exist");
        Path file=directory.resolve("body-clearance.jsonl");
        for(String name:new String[]{"body-clearance.jsonl","transition-solve.jsonl","render-camera.jsonl","WheelbarrowWood.bin",
            "wood-wheel-mesh-proof.json","wood-wheel-mesh-phase-proof.json","wood-wheel-mesh-error.json"})
            if(Files.exists(directory.resolve(name)))throw new IllegalStateException("Preserve existing clearance output first: "+name);
        output=Files.newBufferedWriter(file,java.nio.file.StandardOpenOption.CREATE_NEW);last=0;
        solves=Files.newBufferedWriter(directory.resolve("transition-solve.jsonl"),java.nio.file.StandardOpenOption.CREATE_NEW);
        cameras=Files.newBufferedWriter(directory.resolve("render-camera.jsonl"),java.nio.file.StandardOpenOption.CREATE_NEW);captureSerial=0;
        meshProof=phaseMeshProof=meshError=false;firstMeshHash=null;firstMeshPhase=0;
        if(!installed){new AgentBuilder.Default().disableClassFormatChanges()
            .with(AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
            .type(named("zombie.core.skinnedmodel.model.ModelSlotRenderData"))
            .transform((b,d,l,m,p)->b.visit(Advice.to(NativeCapture.class).on(named("initModel").and(takesArguments(1)))))
            .type(named("zombie.core.opengl.CharacterModelCamera"))
            .transform((b,d,l,m,p)->b.visit(Advice.to(CameraBegin.class).on(named("Begin").and(takesArguments(0)))))
            .type(named("zombie.core.skinnedmodel.model.Model"))
            .transform((b,d,l,m,p)->b
                .visit(Advice.to(ActualDraw.class).on(named("DrawSolid").and(takesArguments(2))))
                .visit(Advice.to(CameraEnd.class).on(named("CharacterModelCameraEnd").and(takesArguments(0)))))
            .type(named("net.alexredby.pztoolkitjavapatches.CartGrounding"))
            .transform((b,d,l,m,p)->b.visit(Advice.to(Capture.class).on(named("render"))))
            .type(named("net.alexredby.pztoolkitjavapatches.CartWheelSpin"))
            .transform((b,d,l,m,p)->b.visit(Advice.to(Drawing.class).on(named("render"))))
            .type(named("net.alexredby.pztoolkitjavapatches.CartGrip"))
            .transform((b,d,l,m,p)->b
                .visit(Advice.to(Solve.class).on(namedOneOf("transition","authoredTransition","movingRecovery")))
                .visit(Advice.to(Refusal.class).on(namedOneOf("nativeHeight","nativeRotation","bendTransitionTorso","groundFeet","transitionGrip")))
                .visit(Advice.to(Reach.class).on(named("reach").and(takesArguments(7)))))
            .installOn(instrumentation);installed=true;}
        System.out.println("[CLEARANCE_PROBE] writing "+file);
    }
}
