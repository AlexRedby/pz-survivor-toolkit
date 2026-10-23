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
    private static BufferedWriter handoffEvents;
    private static final boolean INVENTORY_EQUIP="true".equals(System.getenv("PZ_CART_INVENTORY_EQUIP"));
    private static BufferedWriter inventoryEquip;
    private static long inventoryFrame,inventorySample,nextInventoryAction;
    private static final java.util.WeakHashMap<zombie.characters.CharacterTimedActions.LuaTimedActionNew,Long> inventoryActions=new java.util.WeakHashMap<>();
    private static final java.util.WeakHashMap<zombie.characters.CharacterTimedActions.LuaTimedActionNew,Long> inventoryUpdates=new java.util.WeakHashMap<>();
    private record InventoryAttachment(zombie.inventory.InventoryItem item,long first) {}
    private static final java.util.WeakHashMap<zombie.characters.IsoPlayer,InventoryAttachment> inventoryAttachments=new java.util.WeakHashMap<>();
    private static String inventoryActor(zombie.characters.IsoPlayer owner) {
        var local=zombie.characters.IsoPlayer.getInstance();
        if(!INVENTORY_EQUIP || inventoryEquip==null || !zombie.network.GameClient.client || zombie.network.GameServer.server
            || zombie.network.GameClient.connection==null || !zombie.network.GameClient.instance.connected
            || owner==null || !"client1".equals(owner.getUsername()) || owner.getOnlineID()<0 || owner.isDead() || owner.getCurrentSquare()==null
            || local==null || !local.isLocalPlayer() || !("client1".equals(local.getUsername()) || "client2".equals(local.getUsername())))return null;
        return local.getUsername();
    }
    private static long inventoryActionId(zombie.characters.CharacterTimedActions.LuaTimedActionNew action) {
        return inventoryActions.computeIfAbsent(action,key->++nextInventoryAction);
    }
    private static String inventoryPrefix(String kind,zombie.characters.IsoPlayer player,String actor) {
        return "{\"producer\":\"cart-mp-inventory-equip-native-v1\",\"event\":"+jsonString(kind)
            +",\"actor\":"+jsonString(actor)+",\"ownerID\":"+player.getOnlineID()+",\"local\":"+player.isLocalPlayer()
            +",\"female\":"+player.isFemale()+",\"wall\":"+System.currentTimeMillis();
    }
    private static String inventoryReadiness(zombie.characters.IsoPlayer player) {
        var item=player.getPrimaryHandItem();
        return "{\"visualEnabled\":"+net.alexredby.pztoolkitjavapatches.CartMotionSync.visualEnabled(player)
            +",\"steeringEnabled\":"+net.alexredby.pztoolkitjavapatches.CartSteeringHooks.enabled(player)
            +",\"supportedHeldCart\":"+net.alexredby.pztoolkitjavapatches.CartSteeringHooks.supportedCart(player)
            +",\"IsPerformingAnAction\":"+player.getVariableBoolean("IsPerformingAnAction")
            +",\"ToolkitCartMotion\":"+player.getVariableBoolean("ToolkitCartMotion")
            +",\"Weapon\":"+jsonString(player.getVariableString("Weapon"))
            +",\"PerformingAction\":"+jsonString(player.getVariableString("PerformingAction"))
            +",\"ToolkitCartPose\":"+jsonString(player.getVariableString("ToolkitCartPose"))
            +",\"RightHandMask\":"+jsonString(player.getVariableString("RightHandMask"))
            +",\"LeftHandMask\":"+jsonString(player.getVariableString("LeftHandMask"))
            +",\"overridePrimary\":"+jsonString(player.overridePrimaryHandModel)
            +",\"overrideSecondary\":"+jsonString(player.overrideSecondaryHandModel)
            +",\"forceNullOverride\":"+player.forceNullOverride+",\"hideWeapon\":"+player.isHideWeaponModel()
            +",\"inventoryOwnsPrimary\":"+(item!=null && item.getContainer()==player.getInventory())+"}";
    }
    private static String inventoryGroundPose(ModelSlotRenderData slot,ModelInstanceRenderData cart) {
        var player=(zombie.characters.IsoPlayer)slot.character;var item=player.getPrimaryHandItem();
        var row=new StringBuilder("{\"wall\":").append(System.currentTimeMillis()).append(",\"slotToken\":").append(System.identityHashCode(slot))
            .append(",\"cartDataToken\":").append(System.identityHashCode(cart)).append(",\"id\":").append(item.getID())
            .append(",\"primaryID\":").append(item.getID()).append(",\"secondaryID\":").append(player.getSecondaryHandItem()==null?-1:player.getSecondaryHandItem().getID())
            .append(",\"readiness\":").append(inventoryReadiness(player)).append(",\"cart\":");
        matrix(row,new Matrix4f(cart.xfrm).transpose());row.append(",\"bones\":{");boolean comma=false;
        for(var body:slot.modelData)if(body.modelInstance==cart.modelInstance.parent && body.matrixPalette!=null
            && body.modelInstance.model.tag instanceof SkinningData skin) {
            for(var entry:skin.boneIndices.entrySet()) {
                int i=entry.getValue();var buffer=body.matrixPalette.duplicate();buffer.position(i*16);var raw=new org.lwjgl.util.vector.Matrix4f();raw.load(buffer);
                var pose=PZMath.convertMatrix(raw,new Matrix4f()).transpose().mul(PZMath.convertMatrix(skin.boneOffset.get(i),new Matrix4f()).transpose().invert());
                if(!pose.isFinite())throw new IllegalStateException("Nonfinite MP attachment pose");
                if(comma)row.append(',');comma=true;row.append(jsonString(entry.getKey())).append(':');matrix(row,pose);
            }
            break;
        }
        return row.append("}}").toString();
    }
    public static synchronized String inventoryGroundBefore(ModelSlotRenderData slot) {
        if(!(slot.character instanceof zombie.characters.IsoPlayer player) || inventoryActor(player)==null)return null;
        var item=player.getPrimaryHandItem();
        if(item==null || item!=player.getSecondaryHandItem() || !"SaucedWheelbarrow.WheelbarrowWood".equals(item.getFullType()))return null;
        long now=System.nanoTime();var window=inventoryAttachments.get(player);
        if(window==null || window.item()!=item) {window=new InventoryAttachment(item,now);inventoryAttachments.put(player,window);}
        if(now-window.first()>750_000_000L)return null;
        for(var cart:slot.modelData)if(cart.modelInstance!=null && cart.modelInstance.parent!=null
            && cart.modelInstance.modelScript!=null && "WheelbarrowWood".equals(cart.modelInstance.modelScript.getName()))return inventoryGroundPose(slot,cart);
        return null;
    }
    public static synchronized void inventoryGroundAfter(ModelSlotRenderData slot,String before) throws Exception {
        if(before==null || !(slot.character instanceof zombie.characters.IsoPlayer player))return;
        String actor=inventoryActor(player);if(actor==null)return;
        for(var cart:slot.modelData)if(cart.modelInstance!=null && cart.modelInstance.parent!=null
            && cart.modelInstance.modelScript!=null && "WheelbarrowWood".equals(cart.modelInstance.modelScript.getName())) {
            inventoryEquip.write(inventoryPrefix("grounding-pair",player,actor)+",\"before\":"+before+",\"after\":"+inventoryGroundPose(slot,cart)+"}\n");inventoryEquip.flush();return;
        }
    }
    public static class InventoryGrounding {
        @Advice.OnMethodEnter(suppress=Throwable.class)
        public static String enter(@Advice.Argument(0) ModelSlotRenderData slot) {return ClearanceProbe.inventoryGroundBefore(slot);}
        @Advice.OnMethodExit(suppress=Throwable.class)
        public static void exit(@Advice.Argument(0) ModelSlotRenderData slot,@Advice.Enter String before) throws Exception {ClearanceProbe.inventoryGroundAfter(slot,before);}
    }
    public static synchronized void inventoryLifecycle(zombie.characters.CharacterTimedActions.LuaTimedActionNew action,String event,String stage,Throwable thrown) throws Exception {
        if(!(action.chr instanceof zombie.characters.IsoPlayer player))return;
        String actor=inventoryActor(player);
        if(actor==null || !"ISCartEquipAction".equals(action.getMetaType()))return;
        long now=System.nanoTime();
        if("update".equals(event)) {
            // The server-done packet can arrive between enter and exit on the
            // final update. Never decimate that canonical completion receipt.
            long previous=inventoryUpdates.getOrDefault(action,0L);if(!action.forceComplete && now-previous<25_000_000L)return;inventoryUpdates.put(action,now);
        }
        var table=action.getTable();var cartId=table.rawget("cartId");
        if(!(cartId instanceof Number id) || id.intValue()<=0)throw new IllegalStateException("Native inventory equip has no exact cartId");
        var networkPlayer=(zombie.network.fields.character.PlayerID)stateField(action,"playerId");
        byte transaction=((Number)stateField(action,"transactionId")).byteValue();
        var networkAction=zombie.core.ActionManager.getAction(transaction,networkPlayer);
        boolean networkExact=networkAction!=null && networkAction.action==table && "ISCartEquipAction".equals(networkAction.type)
            && networkPlayer.getID()==player.getOnlineID();
        boolean networkDone=networkExact && zombie.core.ActionManager.isDone(networkPlayer,transaction);
        boolean networkRejected=networkExact && zombie.core.ActionManager.isRejected(networkPlayer,transaction);
        var primary=player.getPrimaryHandItem();var secondary=player.getSecondaryHandItem();
        var row=new StringBuilder(inventoryPrefix("lifecycle",player,actor)).append(",\"actionId\":").append(inventoryActionId(action))
            .append(",\"method\":").append(jsonString(event)).append(",\"stage\":").append(jsonString(stage))
            .append(",\"actionType\":").append(jsonString(action.getMetaType())).append(",\"sourceType\":").append(jsonString((String)table.rawget("sourceType")))
            .append(",\"id\":").append(id.intValue()).append(",\"time\":").append(action.getCurrentTime()).append(",\"maxTime\":").append(action.maxTime)
            .append(",\"luaMaxTime\":").append(table.rawget("maxTime") instanceof Number number && Double.isFinite(number.doubleValue())?number:"null")
            .append(",\"luaCharacterExact\":").append(table.rawget("character")==player)
            .append(",\"progress\":").append(action.getJobDelta()).append(",\"finished\":").append(action.finished())
            .append(",\"waitForFinished\":").append(action.waitForFinished)
            .append(",\"transactionId\":").append(transaction).append(",\"networkOwnerID\":").append(networkPlayer.getID())
            .append(",\"networkActionPresent\":").append(networkAction!=null).append(",\"networkActionExact\":").append(networkExact)
            .append(",\"networkActionType\":").append(jsonString(networkAction==null?null:networkAction.type))
            .append(",\"networkDone\":").append(networkDone).append(",\"networkRejected\":").append(networkRejected)
            .append(",\"forceStop\":").append(action.forceStop).append(",\"forceComplete\":").append(action.forceComplete)
            .append(",\"threw\":").append(thrown!=null).append(",\"primaryID\":").append(primary==null?-1:primary.getID())
            .append(",\"secondaryID\":").append(secondary==null?-1:secondary.getID()).append("}\n");
        inventoryEquip.write(row.toString());inventoryEquip.flush();
    }
    public static class InventoryLifecycle {
        @Advice.OnMethodEnter(suppress=Throwable.class)
        public static void enter(@Advice.This zombie.characters.CharacterTimedActions.LuaTimedActionNew action,@Advice.Origin("#m") String method) throws Exception {
            ClearanceProbe.inventoryLifecycle(action,method,"enter",null);
        }
        @Advice.OnMethodExit(onThrowable=Throwable.class,suppress=Throwable.class)
        public static void exit(@Advice.This zombie.characters.CharacterTimedActions.LuaTimedActionNew action,@Advice.Origin("#m") String method,@Advice.Thrown Throwable thrown) throws Exception {
            ClearanceProbe.inventoryLifecycle(action,method,"exit",thrown);
        }
    }
    private static synchronized void inventorySnapshot(ModelSlotRenderData slot) throws Exception {
        if(!(slot.character instanceof zombie.characters.IsoPlayer player))return;
        String actor=inventoryActor(player);long now=System.nanoTime();
        if(actor==null || now-inventorySample<33_333_333L)return;
        for(var body:slot.modelData) {
            var instance=body.modelInstance;
            if(instance==null || instance.parent!=null || body.matrixPalette==null || !(instance.model.tag instanceof SkinningData skin))continue;
            var primary=player.getPrimaryHandItem();var secondary=player.getSecondaryHandItem();
            var row=new StringBuilder(inventoryPrefix("body",player,actor)).append(",\"captureId\":").append(++inventoryFrame)
                .append(",\"primaryID\":").append(primary==null?-1:primary.getID()).append(",\"secondaryID\":").append(secondary==null?-1:secondary.getID())
                .append(",\"x\":").append(player.getX()).append(",\"y\":").append(player.getY()).append(",\"z\":").append(player.getZ())
                .append(",\"moving\":").append(player.isPlayerMoving()).append(",\"nativeActions\":").append(player.getCharacterActions().size())
                .append(",\"readiness\":").append(inventoryReadiness(player))
                .append(",\"models\":[");
            boolean comma=false;
            for(var data:slot.modelData) {
                var model=data.modelInstance==null?null:data.modelInstance.model;
                if(model==null)continue;if(comma)row.append(',');comma=true;
                row.append(jsonString(model.mesh==null?model.name:model.mesh.fullPath));
            }
            row.append("],\"actions\":[");comma=false;
            for(var current:player.getCharacterActions()) {
                if(!(current instanceof zombie.characters.CharacterTimedActions.LuaTimedActionNew action))continue;
                if(comma)row.append(',');comma=true;var id=action.getTable().rawget("cartId");
                row.append("{\"actionId\":").append(inventoryActionId(action)).append(",\"type\":").append(jsonString(action.getMetaType()))
                    .append(",\"id\":").append(id instanceof Number number?number.intValue():-1).append(",\"progress\":").append(action.getJobDelta()).append('}');
            }
            row.append("],\"bones\":{");comma=false;
            for(var entry:skin.boneIndices.entrySet()) {
                int i=entry.getValue();if((i+1)*16>body.matrixPalette.limit())throw new IllegalStateException("Native equip palette bounds");
                var buffer=body.matrixPalette.duplicate();buffer.position(i*16);var raw=new org.lwjgl.util.vector.Matrix4f();raw.load(buffer);
                var pose=PZMath.convertMatrix(raw,new Matrix4f()).transpose().mul(PZMath.convertMatrix(skin.boneOffset.get(i),new Matrix4f()).transpose().invert());
                if(!pose.isFinite())throw new IllegalStateException("Native equip nonfinite pose");
                if(comma)row.append(',');comma=true;row.append(jsonString(entry.getKey())).append(':');matrix(row,pose);
            }
            row.append("},\"tracks\":[");comma=false;
            for(var track:instance.animPlayer.getMultiTrack().getTracks()) {
                if(comma)row.append(',');comma=true;row.append("{\"id\":").append(track.getId()).append(",\"name\":").append(jsonString(track.getName()))
                    .append(",\"time\":").append(track.getCurrentTrackTime()).append(",\"weight\":").append(track.getBlendWeight()).append('}');
            }
            row.append("]}\n");inventoryEquip.write(row.toString());inventoryEquip.flush();inventorySample=now;return;
        }
    }
    private static final Object handoffOutputLock=new Object();
    private static long captureSerial;
    private static final boolean TIMELINE="true".equals(System.getenv("PZ_CART_TIMELINE"));
    private static final boolean OBSERVER_ASSOCIATION="true".equals(System.getenv("PZ_CART_OBSERVER_ASSOCIATION"));
    private static Method timelineBridge,timelineInputBridge,observerBridge;
    // Main is installed by CartLab on server and both clients. Resolve once at
    // attachment; the probe is compiled independently from the composed Main.
    private static void timelineFrame(String event,ModelSlotRenderData slot,DrawFrame frame,String part) {
        if(!TIMELINE || timelineBridge==null)return;
        try {
            String shared=",\"captureId\":"+frame.id+",\"slotToken\":"+System.identityHashCode(slot)
                +",\"preparedPrimary\":"+frame.preparedPrimary+",\"preparedSecondary\":"+frame.preparedSecondary
                +",\"nativeMonoNs\":"+frame.nativePose.mono+",\"nativeServerNs\":"+frame.nativePose.server
                +",\"nativeClockReady\":"+frame.nativePose.ready+",\"part\":"+jsonString(part)+frame.nativePose.inputFields;
            var owner=frame.nativePose.player;
            var main=timelineBridge.getDeclaringClass();
            var pose=main.getMethod("timelinePose",String.class,String.class);
            for(String[] state:new String[][]{{"ToolkitCartPose",frame.motion},{"ToolkitCartActionPose",frame.action}})
                timelineBridge.invoke(null,event,owner,shared+(String)pose.invoke(null,state[0],state[1]));
        } catch(Throwable error){System.err.println("[CART_TIMELINE] ERROR render bridge "+error);}
    }
    private record NativePose(zombie.characters.IsoPlayer player,long wall,long mono,long server,boolean ready,float x,float y,float z,float heading,float angle,String inputFields) {}
    private record Hands(zombie.inventory.InventoryItem item,long changed) {}
    private static final java.util.WeakHashMap<zombie.characters.IsoPlayer,Hands> hands=new java.util.WeakHashMap<>();
    private static void rememberHands(zombie.characters.IsoPlayer player,long now) {
        var item=player.getPrimaryHandItem();var previous=hands.get(player);
        if(previous==null || previous.item()!=item)hands.put(player,new Hands(item,now));
    }
    private record ConsumedCamera(zombie.core.skinnedmodel.ModelCamera camera,long wall,float x,float y,float z,float angle,boolean world,boolean vehicle) {}
    private static final class DrawFrame {
        final long id,wall;
        final NativePose nativePose;
        // Ownership at preparation belongs to this frozen body/cart slot.
        final int preparedPrimary,preparedSecondary;
        final ModelInstance body,cart;
        final String motion,action;
        boolean bodyDrawn,cartDrawn;
        DrawFrame(long id,long wall,NativePose pose,ModelInstance body,ModelInstance cart) {
            this.id=id;this.wall=wall;this.nativePose=pose;this.body=body;this.cart=cart;
            var primary=pose.player.getPrimaryHandItem();var secondary=pose.player.getSecondaryHandItem();
            motion=TIMELINE?pose.player.getVariableString("ToolkitCartPose"):null;action=TIMELINE?pose.player.getVariableString("ToolkitCartActionPose"):null;
            preparedPrimary=primary==null?-1:primary.getID();preparedSecondary=secondary==null?-1:secondary.getID();
        }
    }
    private static final java.util.WeakHashMap<ModelSlotRenderData,NativePose> nativePoses=new java.util.WeakHashMap<>();
    private static final java.util.WeakHashMap<ModelSlotRenderData,DrawFrame> drawFrames=new java.util.WeakHashMap<>();
    private static final ThreadLocal<ConsumedCamera> consumedCamera=new ThreadLocal<>();
    private static float slotField(ModelSlotRenderData slot,String name) throws Exception {
        var field=ModelSlotRenderData.class.getDeclaredField(name);field.setAccessible(true);return field.getFloat(slot);
    }
    private static String nativeInputSnapshot(zombie.characters.IsoPlayer player) {
        if(!TIMELINE)return "";
        // Freeze proxy input provenance with the original native pose and body/cart
        // DrawFrame. This does not exclusively attribute blended skeletal tracks.
        try {return (String)timelineInputBridge.invoke(null,player)
            +(OBSERVER_ASSOCIATION?(String)observerBridge.invoke(null,player):"");}
        catch(Throwable error){System.err.println("[CART_TIMELINE] ERROR native input bridge "+error);return "";}
    }
    public static synchronized void rememberNative(ModelSlotRenderData slot,zombie.core.skinnedmodel.ModelManager.ModelSlot source) {
        nativePoses.remove(slot);drawFrames.remove(slot);
        if(output==null || source==null || !(source.character instanceof zombie.characters.IsoPlayer player))return;
        rememberHands(player,System.nanoTime());
        float heading=player.getDirectionAngleRadians();
        var animation=player.getAnimationPlayer();
        float angle=animation==null?heading+(float)(Math.PI/2):animation.getRenderedAngle();
        String inputFields=nativeInputSnapshot(player);
        nativePoses.put(slot,new NativePose(player,System.currentTimeMillis(),System.nanoTime(),zombie.GameTime.getServerTime(),zombie.GameTime.getServerTimeShiftIsSet(),player.getX(),player.getY(),player.getZ(),heading,angle,inputFields));
    }
    private static DrawFrame prepareDraw(ModelSlotRenderData slot,ModelInstance body,ModelInstance cart) {
        var pose=nativePoses.get(slot);
        if(pose==null || slot.character!=pose.player)throw new IllegalStateException("Missing original native slot pose");
        var frame=new DrawFrame(++captureSerial,System.currentTimeMillis(),pose,body,cart);
        drawFrames.put(slot,frame);timelineFrame("capture-prepared",slot,frame,"both");return frame;
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
        var livePrimary=frame.nativePose.player.getPrimaryHandItem();
        var liveSecondary=frame.nativePose.player.getSecondaryHandItem();
        var row=new StringBuilder(1024).append("{\"renderProbeVersion\":1,\"captureId\":").append(frame.id)
            .append(",\"slotToken\":").append(System.identityHashCode(slot))
            .append(",\"id\":").append(frame.nativePose.player.getOnlineID())
            .append(",\"preparedPrimary\":").append(frame.preparedPrimary)
            .append(",\"preparedSecondary\":").append(frame.preparedSecondary)
            .append(",\"primary\":").append(livePrimary==null?-1:livePrimary.getID())
            .append(",\"secondary\":").append(liveSecondary==null?-1:liveSecondary.getID())
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
        timelineFrame("draw-consumed",slot,frame,body?"body":"cart");
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
    private static Object stateField(Object state,String name)throws Exception {
        var field=state.getClass().getDeclaredField(name);field.setAccessible(true);return field.get(state);
    }
    private static String handoffFields(zombie.characters.IsoPlayer player)throws Exception {
        synchronized(net.alexredby.pztoolkitjavapatches.CartTransition.class) {
            var type=net.alexredby.pztoolkitjavapatches.CartTransition.class;
            var field=type.getDeclaredField("pickupHandoffs");field.setAccessible(true);
            Object token=((java.util.Map<?,?>)field.get(null)).get(player);
            var statesField=type.getDeclaredField("states");statesField.setAccessible(true);
            Object state=((java.util.Map<?,?>)statesField.get(null)).get(player);
            String flags=",\"handoffPresent\":"+(token!=null)+",\"transitionPresent\":"+(state!=null)
                +",\"performing\":"+player.getVariableBoolean("IsPerformingAnAction")
                +",\"performingAction\":"+jsonString(player.getVariableString("PerformingAction"))
                +",\"nativeActionCount\":"+player.getCharacterActions().size()
                +",\"forceNullOverride\":"+player.forceNullOverride;
            if(token==null)return flags;
            Object source=stateField(token,"source");
            return flags+",\"handoffPerformed\":"+stateField(token,"performed")
                +",\"handoffReceipted\":"+stateField(token,"receipted")
                +",\"handoffHeldExact\":"+(stateField(token,"held")==player.getPrimaryHandItem())
                +",\"handoffDeadlineMs\":"+(((Long)stateField(token,"deadline")-System.nanoTime())/1_000_000L)
                +",\"handoffRemote\":"+stateField(source,"remote");
        }
    }
    /** Exact method boundaries; getters/reflection only, never a render or production gateway call. */
    public static void pickupBoundary(String method,String stage,Object[] args,Throwable thrown) {
        try {
            if(handoffEvents==null)return;
            zombie.characters.IsoPlayer player;
            Object state=null,scope=null;
            zombie.characters.CharacterTimedActions.LuaTimedActionNew performed=null;
            if("pickupPerformed".equals(method)) {
                performed=(zombie.characters.CharacterTimedActions.LuaTimedActionNew)args[0];
                if(!(performed.chr instanceof zombie.characters.IsoPlayer actor))return;
                player=actor;scope=args[1];
            } else {
                player=(zombie.characters.IsoPlayer)args[0];
                if("rememberPickup".equals(method))state=args[1];
            }
            if(player==null)return;
            String row;
            synchronized(net.alexredby.pztoolkitjavapatches.CartTransition.class) {
                var type=net.alexredby.pztoolkitjavapatches.CartTransition.class;
                var field=type.getDeclaredField("pickupHandoffs");field.setAccessible(true);
                Object token=((java.util.Map<?,?>)field.get(null)).get(player);
                var statesField=type.getDeclaredField("states");statesField.setAccessible(true);
                Object current=((java.util.Map<?,?>)statesField.get(null)).get(player);
                if(state==null)state=current!=null?current:token==null?null:stateField(token,"source");
                var primary=player.getPrimaryHandItem();var secondary=player.getSecondaryHandItem();
                var network=player.getNetworkCharacterAI();
                var networkAction=network==null?null:network.getAction();
                var actions=player.getCharacterActions();
                var out=new StringBuilder(3000).append("{\"wallTimeMillis\":").append(System.currentTimeMillis())
                    .append(",\"event\":").append(jsonString(method)).append(",\"stage\":").append(jsonString(stage))
                    .append(",\"id\":").append(player.getOnlineID()).append(",\"local\":").append(player.isLocalPlayer())
                    .append(",\"methodThrew\":").append(thrown!=null)
                    .append(",\"scopePresent\":").append(scope!=null)
                    .append(",\"primary\":").append(primary==null?-1:primary.getID())
                    .append(",\"secondary\":").append(secondary==null?-1:secondary.getID())
                    .append(",\"primaryIdentity\":").append(System.identityHashCode(primary))
                    .append(",\"secondaryExact\":").append(primary!=null && primary==secondary)
                    .append(",\"primaryOwned\":").append(primary!=null && primary.getContainer()==player.getInventory() && primary.getWorldItem()==null)
                    .append(",\"overridePrimary\":").append(jsonString(player.overridePrimaryHandModel))
                    .append(",\"overrideSecondary\":").append(jsonString(player.overrideSecondaryHandModel))
                    .append(",\"hideWeapon\":").append(player.isHideWeaponModel())
                    .append(",\"hideHandR\":").append(player.isHideEquippedHandR())
                    .append(",\"npc\":").append(player.isNpc()).append(",\"sneaking\":").append(player.isSneaking())
                    .append(",\"walkInjury\":").append(player.getVariableFloat("WalkInjury",0))
                    .append(",\"unsafe\":").append(player.isDead() || player.isAiming() || player.hasHitReaction()
                        || player.isKnockedDown() || player.isGettingUp() || player.getVehicle()!=null
                        || player.isCurrentState(zombie.ai.states.CollideWithWallState.instance())
                        || player.isGrappling() || player.isBeingGrappled() || player.isRagdollSimulationActive())
                    .append(",\"client\":").append(zombie.network.GameClient.client)
                    .append(",\"connected\":").append(zombie.network.GameClient.client && zombie.network.GameClient.connection!=null && zombie.network.GameClient.instance.connected)
                    .append(",\"onlineExact\":").append(zombie.network.GameClient.IDToPlayerMap.get(player.getOnlineID())==player)
                    .append(",\"receiptConnectionExact\":").append("pickupEquipped".equals(method) && args[1]==zombie.network.GameClient.connection)
                    .append(",\"statePresent\":").append(state!=null).append(",\"stateIsCurrent\":").append(state!=null && state==current)
                    .append(",\"networkActionIdentity\":").append(System.identityHashCode(networkAction))
                    .append(handoffFields(player));
                if(scope!=null)out.append(",\"scopeFailed\":").append(stateField(scope,"failed"))
                    .append(",\"scopeActionExact\":").append(performed!=null && stateField(scope,"action")==performed.getTable())
                    .append(",\"scopeCallbackExact\":").append(performed!=null && stateField(scope,"callback")==performed.getTable().rawget("perform"));
                if(state!=null) {
                    var item=(zombie.inventory.InventoryItem)stateField(state,"item");
                    var owner=(zombie.characters.CharacterTimedActions.BaseAction)stateField(state,"actionOwner");
                    var nativeLua=owner instanceof zombie.characters.CharacterTimedActions.LuaTimedActionNew a?a:null;
                    var table=nativeLua==null?null:nativeLua.getTable();
                    var model=item==null?null:zombie.scripting.ScriptManager.instance.getModelScript(item.getStaticModel());
                    var override=player.overridePrimaryHandModel==null?null:zombie.scripting.ScriptManager.instance.getModelScript(player.overridePrimaryHandModel);
                    long now=System.nanoTime();
                    out.append(",\"stateIdentity\":").append(System.identityHashCode(state))
                        .append(",\"sourceID\":").append(item==null?-1:item.getID())
                        .append(",\"sourceIdentity\":").append(System.identityHashCode(item))
                        .append(",\"sourceType\":").append(jsonString(item==null?null:item.getFullType()))
                        .append(",\"sourceStaticModel\":").append(jsonString(item==null?null:item.getStaticModel()))
                        .append(",\"sourceModelName\":").append(jsonString(model==null?null:model.getName()))
                        .append(",\"sourceModelModule\":").append(jsonString(model==null || model.getModule()==null?null:model.getModule().name))
                        .append(",\"sourceOverrideModelExact\":").append(model!=null && model==override)
                        .append(",\"sourceRemote\":").append(stateField(state,"remote"))
                        .append(",\"sourcePickup\":").append(stateField(state,"pickup"))
                        .append(",\"sourceRecovering\":").append(stateField(state,"recovering"))
                        .append(",\"sourceRendered\":").append(stateField(state,"rendered"))
                        .append(",\"sourceHandoffRemembered\":").append(stateField(state,"handoffRemembered"))
                        .append(",\"sourceWorldPresent\":").append(stateField(state,"world")!=null)
                        .append(",\"sourceRenderAgeMs\":").append((now-(Long)stateField(state,"lastRender"))/1_000_000.0)
                        .append(",\"sourceUpdateAgeMs\":").append((now-(Long)stateField(state,"updated"))/1_000_000.0)
                        .append(",\"sourceConnectionExact\":").append(stateField(state,"connection")==zombie.network.GameClient.connection)
                        .append(",\"ownerPresent\":").append(owner!=null)
                        .append(",\"ownerIdentity\":").append(System.identityHashCode(owner))
                        .append(",\"ownerClass\":").append(jsonString(owner==null?null:owner.getClass().getName()))
                        .append(",\"ownerChrExact\":").append(owner!=null && owner.chr==player)
                        .append(",\"ownerLocalActionExact\":").append(owner!=null && actions.size()==1 && actions.get(0)==owner)
                        .append(",\"ownerNetworkExact\":").append(owner!=null && networkAction==owner)
                        .append(",\"ownerPerformedExact\":").append(owner!=null && performed==owner)
                        .append(",\"ownerMetaType\":").append(jsonString(nativeLua==null?null:nativeLua.getMetaType()))
                        .append(",\"ownerTableCharacterExact\":").append(table!=null && table.rawget("character")==player)
                        .append(",\"ownerTableItemID\":").append(jsonString(table==null?null:String.valueOf(table.rawget("itemId"))));
                }
                row=out.append("}\n").toString();
            }
            synchronized(handoffOutputLock) {if(handoffEvents!=null){handoffEvents.write(row);handoffEvents.flush();}}
        } catch(Throwable error) {System.err.println("[CLEARANCE_PROBE] ERROR pickup boundary "+error);error.printStackTrace();}
    }
    public static class PickupBoundary {
        @Advice.OnMethodEnter
        public static void enter(@Advice.Origin("#m") String method,@Advice.AllArguments Object[] args) {
            ClearanceProbe.pickupBoundary(method,"enter",args,null);
        }
        @Advice.OnMethodExit(onThrowable=Throwable.class)
        public static void exit(@Advice.Origin("#m") String method,@Advice.AllArguments Object[] args,@Advice.Thrown Throwable thrown) {
            ClearanceProbe.pickupBoundary(method,"exit",args,thrown);
        }
    }
    private static zombie.inventory.InventoryItem transitionItem(zombie.characters.IsoPlayer player)throws Exception {
        // A shopping attachment with empty hands is not identity evidence by itself.
        // Read the exact, already-rendered pickup state owned by this native player.
        if(player.getPrimaryHandItem()!=null || player.getSecondaryHandItem()!=null)return null;
        synchronized(net.alexredby.pztoolkitjavapatches.CartTransition.class) {
            var field=net.alexredby.pztoolkitjavapatches.CartTransition.class.getDeclaredField("states");field.setAccessible(true);
            Object state=((java.util.Map<?,?>)field.get(null)).get(player);
            if(state==null || !Boolean.TRUE.equals(stateField(state,"pickup")) || !Boolean.TRUE.equals(stateField(state,"rendered")))return null;
            long updated=(Long)stateField(state,"updated"),age=System.nanoTime()-updated;
            if(age<0 || age>1_000_000_000L)return null;
            var item=(zombie.inventory.InventoryItem)stateField(state,"item");
            var world=stateField(state,"world");
            if(item==null || item.getID()<0 || world==null || item.getWorldItem()!=world
                || ((zombie.iso.objects.IsoWorldInventoryObject)world).getItem()!=item)return null;
            return item;
        }
    }
    private static boolean captureDue(zombie.characters.IsoPlayer player,zombie.inventory.InventoryItem item,long now)throws Exception {
        if(now-last>=33_333_333L)return true;
        // Do not miss a one-slot raw hand attachment during world-to-held handoff.
        var seen=hands.get(player);
        if(item!=null && seen!=null && seen.item()==item && now-seen.changed()>=0
            && now-seen.changed()<=500_000_000L)return true;
        // A remote cancel can expose only ~100ms of active rendering. Capture each
        // original native slot in that bounded action, rather than decimating it.
        synchronized(net.alexredby.pztoolkitjavapatches.CartTransition.class) {
            var field=net.alexredby.pztoolkitjavapatches.CartTransition.class.getDeclaredField("states");field.setAccessible(true);
            Object state=((java.util.Map<?,?>)field.get(null)).get(player);
            if(state==null || item==null || stateField(state,"item")!=item
                || !Boolean.TRUE.equals(stateField(state,"rendered")) || !Boolean.TRUE.equals(stateField(state,"ik"))
                || Boolean.TRUE.equals(stateField(state,"recovering")) || !((Float)stateField(state,"progress")>0))return false;
            long age=now-(Long)stateField(state,"updated");
            if(age<0 || age>1_000_000_000L)return false;
            if(Boolean.TRUE.equals(stateField(state,"pickup"))) {
                var world=stateField(state,"world");
                return player.getPrimaryHandItem()==null && player.getSecondaryHandItem()==null
                    && item.getID()>=0 && world!=null && item.getWorldItem()==world
                    && ((zombie.iso.objects.IsoWorldInventoryObject)world).getItem()==item;
            }
            return player.getPrimaryHandItem()==item && player.getSecondaryHandItem()==item;
        }
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
        if(INVENTORY_EQUIP)inventorySnapshot(slot);
        if(output==null || !(slot.character instanceof zombie.characters.IsoPlayer player)
            || !nativePoses.containsKey(slot) || drawFrames.containsKey(slot)) return;
        for(var cart:slot.modelData) {
            var instance=cart.modelInstance;
            if(instance==null || instance.parent==null || instance.modelScript==null
                || !cartModel(instance.modelScript.getName()))continue;
            var item=player.getPrimaryHandItem();
            String held=item==null?null:item.getStaticModel();
            String actual=instance.modelScript.getName();
            boolean transition=item==null;
            if(transition)item=transitionItem(player);
            if(item==null)continue;
            if(!captureModel(item,actual) || !captureDue(player,item,System.nanoTime()))continue;
            for(var body:slot.modelData) {
                if(body.modelInstance!=instance.parent || body.matrixPalette==null
                    || !(body.modelInstance.model.tag instanceof SkinningData skin))continue;
                int modelCount=0;
                for(var candidate:slot.modelData)if(candidate.modelInstance!=null
                    && candidate.modelInstance.parent!=null && candidate.modelInstance.modelScript!=null
                    && cartModel(candidate.modelInstance.modelScript.getName()))modelCount++;
                var frame=prepareDraw(slot,body.modelInstance,instance);
                var row=new StringBuilder(8192).append("{\"wallTimeMillis\":").append(frame.wall)
                    .append(renderFields(slot,frame))
                    .append(",\"id\":").append(((zombie.characters.IsoPlayer)slot.character).getOnlineID()).append(",\"local\":").append(((zombie.characters.IsoPlayer)slot.character).isLocalPlayer()).append(",\"enabled\":").append(net.alexredby.pztoolkitjavapatches.CartSteeringHooks.enabled((zombie.characters.IsoPlayer)slot.character)).append(",\"female\":").append(slot.character.isFemale())
                    .append(",\"visualEnabled\":").append(net.alexredby.pztoolkitjavapatches.CartMotionSync.visualEnabled(player))
                    .append(",\"cartModelCount\":").append(modelCount)
                    .append(handoffFields(player))
                    .append(",\"slotX\":").append(slot.x).append(",\"slotY\":").append(slot.y)
                    .append(",\"slotZ\":").append(slot.z).append(",\"slotAngle\":").append(slot.animPlayerAngle)
                    .append(",\"primary\":").append(frame.preparedPrimary)
                    .append(",\"secondary\":").append(frame.preparedSecondary)
                    .append(",\"modelProbeVersion\":1,\"model\":").append(jsonString(actual))
                    .append(",\"cartItemId\":").append(item.getID())
                    .append(",\"cartItemSource\":").append(jsonString(transition?"transition":"hands"))
                    .append(",\"cartItemModel\":").append(jsonString(item.getStaticModel()))
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
        if(inventoryEquip!=null){inventoryEquip.close();inventoryEquip=null;}
        inventoryActions.clear();inventoryUpdates.clear();inventoryAttachments.clear();inventorySample=inventoryFrame=nextInventoryAction=0;
        synchronized(handoffOutputLock) {if(handoffEvents!=null){handoffEvents.close();handoffEvents=null;}}
        nativePoses.clear();drawFrames.clear();consumedCamera.remove();
        if("stop".equals(args)){
            if(TIMELINE && timelineBridge!=null)timelineBridge.getDeclaringClass().getMethod("timelineStop").invoke(null);
            System.out.println("[CLEARANCE_PROBE] stopped");return;
        }
        if(args==null || args.isBlank() || !Path.of(args).isAbsolute())throw new IllegalArgumentException("Agent args: absolute output directory, or stop");
        if(TIMELINE) {
            var main=Class.forName("net.alexredby.cartlab.Main");
            timelineBridge=main.getMethod("timelineEvent",String.class,zombie.characters.IsoPlayer.class,String.class);
            timelineInputBridge=main.getMethod("timelineNativeSnapshot",zombie.characters.IsoPlayer.class);
            if(OBSERVER_ASSOCIATION)observerBridge=main.getMethod("observerAssociationSnapshot",zombie.characters.IsoPlayer.class);
        }
        directory=Path.of(args);
        if(!Files.isDirectory(directory))throw new IllegalArgumentException("Output directory must exist");
        Path file=directory.resolve("body-clearance.jsonl");
        for(String name:new String[]{"body-clearance.jsonl","transition-solve.jsonl","render-camera.jsonl","pickup-handoff-events.jsonl","WheelbarrowWood.bin",
            "wood-wheel-mesh-proof.json","wood-wheel-mesh-phase-proof.json","wood-wheel-mesh-error.json"})
            if(Files.exists(directory.resolve(name)))throw new IllegalStateException("Preserve existing clearance output first: "+name);
        output=Files.newBufferedWriter(file,java.nio.file.StandardOpenOption.CREATE_NEW);last=0;
        solves=Files.newBufferedWriter(directory.resolve("transition-solve.jsonl"),java.nio.file.StandardOpenOption.CREATE_NEW);
        cameras=Files.newBufferedWriter(directory.resolve("render-camera.jsonl"),java.nio.file.StandardOpenOption.CREATE_NEW);captureSerial=0;
        if(INVENTORY_EQUIP)inventoryEquip=Files.newBufferedWriter(directory.resolve("inventory-equip-native.jsonl"),java.nio.file.StandardOpenOption.CREATE_NEW);
        synchronized(handoffOutputLock) {handoffEvents=Files.newBufferedWriter(directory.resolve("pickup-handoff-events.jsonl"),java.nio.file.StandardOpenOption.CREATE_NEW);}
        meshProof=phaseMeshProof=meshError=false;firstMeshHash=null;firstMeshPhase=0;
        if(!installed){new AgentBuilder.Default().disableClassFormatChanges()
            .with(AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
            .with(new AgentBuilder.Listener.Adapter() {
                @Override public void onError(String type,ClassLoader loader,net.bytebuddy.utility.JavaModule module,boolean loaded,Throwable error) {
                    System.err.println("[CLEARANCE_PROBE] ERROR transform "+type+" "+error);error.printStackTrace();
                }
            })
            .type(named("zombie.core.skinnedmodel.model.ModelSlotRenderData"))
            .transform((b,d,l,m,p)->b.visit(Advice.to(NativeCapture.class).on(named("initModel").and(takesArguments(1)))))
            .type(named("zombie.core.opengl.CharacterModelCamera"))
            .transform((b,d,l,m,p)->b.visit(Advice.to(CameraBegin.class).on(named("Begin").and(takesArguments(0)))))
            .type(named("zombie.core.skinnedmodel.model.Model"))
            .transform((b,d,l,m,p)->b
                .visit(Advice.to(ActualDraw.class).on(named("DrawSolid").and(takesArguments(2))))
                .visit(Advice.to(CameraEnd.class).on(named("CharacterModelCameraEnd").and(takesArguments(0)))))
            .type(named("net.alexredby.pztoolkitjavapatches.CartTransition"))
            .transform((b,d,l,m,p)->b.visit(Advice.to(PickupBoundary.class).on(namedOneOf("rememberPickup","pickupPerformed","pickupEquipped"))))
            .type(named("zombie.characters.CharacterTimedActions.LuaTimedActionNew"))
            .transform((b,d,l,m,p)->INVENTORY_EQUIP?b.visit(Advice.to(InventoryLifecycle.class).on(takesArguments(0).and(namedOneOf("start","update","perform","complete","stop","interruptWaitToStart")))):b)
            .type(named("net.alexredby.pztoolkitjavapatches.CartGrounding"))
            .transform((b,d,l,m,p)->b.visit(Advice.to(Capture.class).on(named("render")))
                .visit(Advice.to(InventoryGrounding.class).on(named("render"))))
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
