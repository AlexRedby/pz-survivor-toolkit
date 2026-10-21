package net.alexredby.cartlab;

import java.nio.file.Files;
import java.nio.file.Path;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.characters.IsoPlayer;
import zombie.core.Core;

/** Test-only keyboard input and read-only cart diagnostics; no game launcher. */
public final class Main {
    private static final Path runtime = configuredPath("PZ_CART_RUNTIME_FILE");
    private static final Path commands = configuredPath("PZ_CART_COMMAND_FILE");
    public static int drive = -1, gait;
    private static long lastCommand;
    private static int heldKey = -1;
    private static boolean captureUIHidden;

    private static boolean captureUIWorld() {
        return "true".equals(System.getenv("PZ_CART_TEST_PAD"))
            && zombie.iso.IsoWorld.instance!=null
            && "CartTestArea".equals(zombie.iso.IsoWorld.instance.getWorld())
            && !zombie.network.GameClient.client && !zombie.network.GameServer.server;
    }

    @LuaMethod(name="cartLabCaptureUIKeyBound", global=true)
    public static boolean captureUIKeyBound(int key) {
        return Core.getInstance().getKeyBinding(key)!=Core.KEYBINDING_EMPTY;
    }

    @LuaMethod(name="cartLabCaptureUIVisible", global=true)
    public static boolean captureUIVisible() {return zombie.ui.UIManager.visibleAllUi;}

    @LuaMethod(name="cartLabCaptureUIRender", global=true)
    public static void captureUIRender(boolean hidden) {
        if(hidden && !captureUIWorld())throw new IllegalStateException("Disposable single-player CartTestArea pad required");
        captureUIHidden=hidden;
        // Do not reuse a UI texture drawn before this capture toggle.
        zombie.ui.UIManager.uiTextureContentsValid=false;
    }

    // Advice is inlined into UIManager, which cannot access this class's private state.
    public static boolean hideCaptureUIRender() {
        if(!captureUIWorld())captureUIHidden=false;
        return captureUIHidden;
    }

    /** Render-only fixture gate: native update, key events and public menu callbacks stay active. */
    @Patch(className="zombie.ui.UIManager", methodName="render", warmUp=true)
    public static class CaptureUIRender {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter() { return Main.hideCaptureUIRender(); }
    }

    @Patch(className="zombie.iso.IsoChunkMap", methodName="CalcChunkWidth", warmUp=true)
    public static class PadChunks {
        @Patch.OnExit
        public static void exit() {
            if (!"true".equals(System.getenv("PZ_CART_TEST_PAD"))) return;
            // A 96-tile radius keeps the complete 96x96 pad resident from any safe position.
            zombie.iso.IsoChunkMap.chunkGridWidth = Math.max(25, zombie.iso.IsoChunkMap.chunkGridWidth);
            zombie.iso.IsoChunkMap.chunkWidthInTiles = zombie.iso.IsoChunkMap.chunkGridWidth * 8;
        }
    }

    @LuaMethod(name="cartLabChunkWidth", global=true)
    public static int chunkWidth() {
        return zombie.iso.IsoChunkMap.chunkWidthInTiles;
    }

    private static Path configuredPath(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) throw new IllegalStateException("Missing required " + name);
        Path path = Path.of(value);
        if (!path.isAbsolute()) throw new IllegalStateException(name + " must be absolute");
        return path;
    }

    @LuaMethod(name="cartLabClipInfo", global=true)
    public static String clipInfo(String name) {
        var clip=zombie.core.skinnedmodel.ModelManager.instance.getAnimationClip(name);
        return clip==null?"missing":"duration:"+clip.getDuration();
    }

    @LuaMethod(name="cartLabNative", global=true)
    public static String nativeState() {
        var p=IsoPlayer.getInstance();var a=p.getAnimationPlayer();var out=new StringBuilder();
        out.append("state:").append(p.getCurrentStateName()).append(",action:").append(p.getActionStateName())
            .append(",momentum:").append(p.getMomentumScalar()).append(",twist:").append(p.getTargetTwist())
            .append(",around:").append(p.isTurningAround()).append(",tracks:");
        for(var t:a.getMultiTrack().getTracks()) out.append(t.getName()).append("@").append(t.getBlendWeight())
            .append("/").append(t.getCurrentTimeValue()).append("/").append(t.getSpeedDelta()).append("/").append(t.isPlaying).append(";");
        out.append(",bones:");
        for(String name:new String[]{"Bip01","Bip01_Pelvis","Bip01_Spine","Bip01_Head","Bip01_L_Thigh","Bip01_L_Calf","Bip01_L_Foot","Bip01_L_Toe0","Bip01_R_Thigh","Bip01_R_Calf","Bip01_R_Foot","Bip01_R_Toe0"}) {
            int i=a.getSkinningBoneIndex(name,-1);if(i<0||i>=a.getModelTransformsCount()) continue;
            var m=a.getModelTransformAt(i);if(m!=null) {
                var world=new zombie.iso.Vector3(m.m03,m.m13,m.m23);
                zombie.core.skinnedmodel.model.Model.vectorToWorldCoords(p,world);
                out.append(name).append(":").append(m.m03).append("/").append(m.m13).append("/").append(m.m23)
                    .append("|").append(world.x).append("/").append(world.y).append("/").append(world.z).append(";");
            }
        }
        return out.toString();
    }

    @LuaMethod(name="cartLabBank", global=true)
    public static double bank() throws Exception {
        var hooks = Class.forName("net.alexredby.pztoolkitjavapatches.CartSteeringHooks");
        return ((Number) hooks.getMethod("lean", IsoPlayer.class).invoke(null, IsoPlayer.getInstance())).doubleValue();
    }

    @LuaMethod(name="cartLabSafety", global=true)
    public static String safety(zombie.inventory.InventoryItem item,double centerX,double centerY) throws Exception {
        var p=IsoPlayer.getInstance();
        var hooks=Class.forName("net.alexredby.pztoolkitjavapatches.CartSteeringHooks");
        var states=hooks.getDeclaredField("states");states.setAccessible(true);
        Object state=((java.util.Map<?,?>)states.get(null)).get(p);
        double brace=0;
        if(state!=null) {var field=state.getClass().getDeclaredField("brace");field.setAccessible(true);brace=field.getDouble(state);}
        var phase=Class.forName("net.alexredby.pztoolkitjavapatches.CartWheelSpin").getDeclaredMethod("itemPhase",zombie.inventory.InventoryItem.class);
        phase.setAccessible(true);
        int inventoryCount=0,worldCount=0,woodCount=0;
        for(var entry:p.getInventory().getItems())if(entry.getID()==item.getID())inventoryCount++;
        var world=item.getWorldItem();boolean worldExact=false;
        for(int x=(int)Math.floor(centerX)-6;x<=(int)Math.floor(centerX)+6;x++)
            for(int y=(int)Math.floor(centerY)-6;y<=(int)Math.floor(centerY)+6;y++) {
                var square=zombie.iso.IsoWorld.instance.currentCell.getGridSquare(x,y,(int)p.getZ());
                if(square==null)throw new IllegalStateException("Impact observation pad unloaded");
                for(var candidate:square.getWorldObjects()) {
                    var entry=candidate.getItem();
                    if(entry!=null && "SaucedWheelbarrow.WheelbarrowWood".equals(entry.getFullType()))woodCount++;
                    if(entry!=null && entry.getID()==item.getID())worldCount++;
                    if(candidate==world && entry==item)worldExact=true;
                }
            }
        var cart=(zombie.inventory.types.InventoryContainer)item;
        var ids=new java.util.ArrayList<String>();
        for(var child:cart.getInventory().getItems())ids.add(Integer.toString(child.getID()));
        java.util.Collections.sort(ids);
        return "state="+p.getCurrentState().getClass().getSimpleName()+" action="+p.getActionStateName()
            +" enabled="+hooks.getMethod("enabled",IsoPlayer.class).invoke(null,p)
            +" steering="+((java.util.Map<?,?>)states.get(null)).containsKey(p)
            +" hit="+p.hasHitReaction()+" knocked="+p.isKnockedDown()+" getup="+p.isGettingUp()
            +" ragdoll="+p.isRagdollSimulationActive()+" ignore="+p.getIgnoreMovement()
            +" pivot="+p.getVariableBoolean("ToolkitCartPivot")+" brake="+p.getVariableBoolean("ToolkitCartWoodBrake")
            +" stepX="+p.getVariableFloat("ToolkitCartStepX",0)+" stepY="+p.getVariableFloat("ToolkitCartStepY",0)
            +" pace="+p.getVariableFloat("ToolkitCartLegPace",0)+" brace="+brace
            +" id="+item.getID()+" primary="+(p.getPrimaryHandItem()==null?-1:p.getPrimaryHandItem().getID())
            +" secondary="+(p.getSecondaryHandItem()==null?-1:p.getSecondaryHandItem().getID())
            +" cargo="+cart.getInventory().getCapacityWeight()+" cargoIds="+(ids.isEmpty()?"empty":String.join(",",ids))
            +" inventoryCount="+inventoryCount+" inInventory="+(item.getContainer()==p.getInventory())
            +" worldCount="+worldCount+" woodCount="+woodCount+" worldExact="+worldExact
            +" worldId="+(world==null?-1:world.getItem().getID())
            +" worldPersistent="+(world!=null && world.isIgnoreRemoveSandbox())
            +" worldX="+(world==null?0:world.getWorldPosX())+" worldY="+(world==null?0:world.getWorldPosY())
            +" worldZ="+(world==null?0:world.getWorldPosZ())+" rotation="+item.getWorldZRotation()
            +" itemPhase="+phase.invoke(null,item);
    }

    // Opt-in provenance only; these fields never participate in movement or action state.
    private static boolean impactWatching;
    private static IsoPlayer impactActor;
    private static long naturalImpactEvents, injectedImpactEvents, otherImpactEvents;
    private static String lastImpactOrigin="none";
    private static final java.util.ArrayList<String> impactReceipts=new java.util.ArrayList<>();

    @LuaMethod(name="cartLabImpactWatch", global=true)
    public static synchronized void impactWatch(boolean enabled) {
        if(enabled) {
            var p=IsoPlayer.getInstance();
            if(p==null || !p.isLocalPlayer()) throw new IllegalStateException("Impact watch requires a local player");
            impactActor=p;
            naturalImpactEvents=injectedImpactEvents=otherImpactEvents=0;
            lastImpactOrigin="none";impactReceipts.clear();
        }
        impactWatching=enabled;
        var row=impactFields(impactActor);
        row.put("kind","watch");row.put("origin","watch-control");
        row.put("movingObjectSha256",classFingerprint(zombie.iso.IsoMovingObject.class));
        row.put("actionContextSha256",classFingerprint(zombie.characters.action.ActionContext.class));
        System.out.println("[CART_NATURAL_HIT] "+impactJson(row));
    }

    @LuaMethod(name="cartLabNaturalImpact", global=true)
    public static synchronized String naturalImpact() {
        var out=new StringBuilder();
        for(var entry:impactFields(IsoPlayer.getInstance()).entrySet()) {
            if(out.length()>0) out.append(' ');
            out.append(entry.getKey()).append('=').append(impactToken(entry.getValue()));
        }
        return out.toString();
    }

    /** Reading receipts never clears counters or game events. */
    @LuaMethod(name="cartLabImpactReceipts", global=true)
    public static synchronized String impactReceipts() { return "["+String.join(",",impactReceipts)+"]"; }

    private static java.util.LinkedHashMap<String,Object> impactFields(IsoPlayer p) {
        var row=new java.util.LinkedHashMap<String,Object>();
        row.put("timeMs",System.currentTimeMillis());row.put("watch",impactWatching);
        row.put("actor",p!=null && p==impactActor);row.put("local",p!=null && p.isLocalPlayer());
        row.put("state",p==null || p.getCurrentState()==null?"none":p.getCurrentState().getClass().getSimpleName());
        row.put("action",p==null?"none":p.getActionStateName());
        row.put("run",p!=null && p.isRunning());row.put("sprint",p!=null && p.isSprinting());
        row.put("ignore",p!=null && p.getIgnoreMovement());row.put("getup",p!=null && p.isGettingUp());
        row.put("hit",p!=null && p.hasHitReaction());row.put("knocked",p!=null && p.isKnockedDown());
        row.put("ragdoll",p!=null && p.isRagdollSimulationActive());
        row.put("primary",p==null || p.getPrimaryHandItem()==null?-1:p.getPrimaryHandItem().getID());
        row.put("secondary",p==null || p.getSecondaryHandItem()==null?-1:p.getSecondaryHandItem().getID());
        row.put("dir",p==null?"none":p.getDir().name());
        row.put("wallType",p==null || p.getCurrentSquare()==null?-1:p.getCurrentSquare().getWallType());
        row.put("collidedN",p!=null && p.isCollidedN());row.put("collidedS",p!=null && p.isCollidedS());
        row.put("collidedE",p!=null && p.isCollidedE());row.put("collidedW",p!=null && p.isCollidedW());
        row.put("collidedDoor",p!=null && p.isCollidedWithDoor());
        row.put("collideType",p==null?"none":p.getCollideType());
        row.put("naturalEvents",naturalImpactEvents);row.put("injectedEvents",injectedImpactEvents);
        row.put("otherEvents",otherImpactEvents);row.put("origin",lastImpactOrigin);
        return row;
    }

    // The one-String overload delegates to (layer,event); observe this exact overload once.
    @Patch(className="zombie.characters.action.ActionContext", methodName="reportEvent", warmUp=true, strictMatch=true)
    public static class ImpactEventReceipt {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.characters.action.ActionContext context,
            @Patch.Argument(0) String layer, @Patch.Argument(1) String event) {
            Main.observeImpact(context,layer,event);
        }
    }

    public static synchronized void observeImpact(zombie.characters.action.ActionContext context,String layer,String event) {
        if(!impactWatching || !"collideWithWall".equals(event) || impactActor==null
            || context.getOwner()!=impactActor || !impactActor.isLocalPlayer()) return;
        var stack=StackWalker.getInstance().walk(frames->frames
            .map(frame->frame.getClassName()+"."+frame.getMethodName()).toList());
        String origin=impactOrigin(stack);
        if("native-checkHitWall".equals(origin)) naturalImpactEvents++;
        else if("injected-cartLabWallEvent".equals(origin)) injectedImpactEvents++;
        else otherImpactEvents++;
        lastImpactOrigin=origin;
        var row=impactFields(impactActor);
        row.put("kind","event");row.put("event",event);row.put("layer",layer==null?"none":layer);
        row.put("stack",String.join(";",stack));
        String receipt=impactJson(row);impactReceipts.add(receipt);
        System.out.println("[CART_NATURAL_HIT] "+receipt);
    }

    static String impactOrigin(java.util.List<String> stack) {
        // An injected wrapper must not become natural merely by running during native update.
        if(stack.contains(Main.class.getName()+".wallEvent")) return "injected-cartLabWallEvent";
        if(stack.contains("zombie.iso.IsoMovingObject.checkHitWall")) return "native-checkHitWall";
        return "other";
    }

    private static String impactToken(Object value) {
        return value==null || value.toString().isEmpty()?"none":value.toString().replaceAll("\\s+","_");
    }

    private static String impactJson(java.util.Map<String,Object> row) {
        var out=new StringBuilder("{");
        for(var entry:row.entrySet()) {
            if(out.length()>1) out.append(',');
            out.append(impactQuote(entry.getKey())).append(':');
            Object value=entry.getValue();
            out.append(value instanceof Number || value instanceof Boolean?value:impactQuote(value==null?"none":value.toString()));
        }
        return out.append('}').toString();
    }

    private static String impactQuote(String value) {
        var out=new StringBuilder("\"");
        for(int i=0;i<value.length();i++) {
            char c=value.charAt(i);
            if(c=='\\' || c=='\"') out.append('\\').append(c);
            else if(c<32) out.append(String.format("\\u%04x",(int)c));
            else out.append(c);
        }
        return out.append('\"').toString();
    }

    private static String classFingerprint(Class<?> type) {
        try(var stream=type.getResourceAsStream("/"+type.getName().replace('.','/')+".class")) {
            if(stream==null) return "missing";
            return java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(stream.readAllBytes()));
        } catch(java.io.IOException | java.security.NoSuchAlgorithmException failure) {
            return "unavailable-"+failure.getClass().getSimpleName();
        }
    }

    @LuaMethod(name="cartLabWallEvent", global=true)
    public static void wallEvent() {
        var p=IsoPlayer.getInstance();
        if(!p.isSprinting() || !"sprint".equals(p.getActionStateName()))
            throw new IllegalStateException("Native wall event requires an actual Sprint state");
        // Explicit injected control; receipts distinguish this stack from vanilla checkHitWall.
        p.getActionContext().reportEvent("collideWithWall");
    }

    @LuaMethod(name="cartLabRamp", global=true)
    public static String ramp() throws Exception {
        var hooks = Class.forName("net.alexredby.pztoolkitjavapatches.CartSteeringHooks");
        var field = hooks.getDeclaredField("states");
        field.setAccessible(true);
        Object state = ((java.util.Map<?, ?>) field.get(null)).get(IsoPlayer.getInstance());
        if (state == null) return "none";
        var out = new StringBuilder();
        for (String key : new String[]{"pace", "sprintMomentum", "load", "heading"}) {
            var member = state.getClass().getDeclaredField(key);
            member.setAccessible(true);
            var value = member.get(state);
            if (key.equals("pace")) {
                for (String part : new String[]{"speed", "velocity"}) {
                    var nested = value.getClass().getDeclaredField(part);
                    nested.setAccessible(true);
                    out.append(part).append(":").append(nested.get(value)).append(",");
                }
            } else out.append(key).append(":").append(value).append(",");
        }
        var player = IsoPlayer.getInstance();
        var pace = Class.forName("net.alexredby.pztoolkitjavapatches.CartLegPace");
        Object target = pace.getMethod("targetSpeed", IsoPlayer.class, float.class, float.class).invoke(null,
            player, player.getVariableFloat("ToolkitCartStepX", 0), player.getVariableFloat("ToolkitCartStepY", 0));
        out.append("target:").append(target).append(",");
        for (var node : player.getAdvancedAnimator().getRootLayer().getLiveAnimNodes())
            if (node.getName().equals("ToolkitCartPivotSprint")) out.append("fade:").append(node.getBlendOutTime()).append(",");
        return out.toString();
    }

    @LuaMethod(name="cartLabReversal", global=true)
    public static String reversal() throws Exception {
        var hooks=Class.forName("net.alexredby.pztoolkitjavapatches.CartSteeringHooks");
        var field=hooks.getDeclaredField("states");field.setAccessible(true);
        Object state=((java.util.Map<?,?>)field.get(null)).get(IsoPlayer.getInstance());
        if(state==null) return "none";
        var member=state.getClass().getDeclaredField("reversal");member.setAccessible(true);
        Object reversal=member.get(state);var out=new StringBuilder();
        for(String key:new String[]{"direction","requested","active","braking","neutral"}) {
            var part=reversal.getClass().getDeclaredField(key);part.setAccessible(true);
            out.append(key).append(":").append(part.get(reversal)).append(",");
        }
        for(String key:new String[]{"actualDistance","brakeTarget"}) {
            var part=state.getClass().getDeclaredField(key);part.setAccessible(true);
            out.append(key).append(":").append(part.get(state)).append(",");
        }
        return out.toString();
    }

    @LuaMethod(name="cartLabBrake", global=true)
    public static String brake() throws Exception {
        var hooks=Class.forName("net.alexredby.pztoolkitjavapatches.CartSteeringHooks");
        var field=hooks.getDeclaredField("states");field.setAccessible(true);
        Object state=((java.util.Map<?,?>)field.get(null)).get(IsoPlayer.getInstance());
        if(state==null) return "none";
        var out=new StringBuilder();
        for(String key:new String[]{"braking","brakeSeen","nativeSpeed","brakeLimit","brakeWait"}) {
            var part=state.getClass().getDeclaredField(key);part.setAccessible(true);
            out.append("stop_").append(key).append(":").append(part.get(state)).append(",");
        }
        var player=IsoPlayer.getInstance();
        var animation=player.getAnimationPlayer();
        int spine=animation.getSkinningBoneIndex("Bip01_Spine",-1);
        var raw=animation.getModelTransformAt(spine);
        Object bodyShift=Class.forName("net.alexredby.pztoolkitjavapatches.CartLegPace")
            .getMethod("woodenGaitShift",IsoPlayer.class).invoke(null,player);
        out.append("tickDt:").append(zombie.GameTime.getInstance().getRealworldSecondsSinceLastUpdate()).append(",");
        out.append("bodyShift:").append(bodyShift).append(",rawX:").append(raw.m03).append(",rawZ:").append(raw.m23).append(",");
        return out.toString();
    }

    @LuaMethod(name="cartLabStationary", global=true)
    public static String stationary() throws Exception {
        var hooks=Class.forName("net.alexredby.pztoolkitjavapatches.CartSteeringHooks");
        var field=hooks.getDeclaredField("states");field.setAccessible(true);
        var player=IsoPlayer.getInstance();
        Object state=((java.util.Map<?,?>)field.get(null)).get(player);
        if(state==null) return "none";
        var out=new StringBuilder();
        for(String key:new String[]{"heading","target","stationary","stationaryRoot","actualDistance"}) {
            var part=state.getClass().getDeclaredField(key);part.setAccessible(true);
            out.append(key).append(":").append(part.get(state)).append(",");
        }
        var axle=hooks.getDeclaredMethod("axle",IsoPlayer.class);axle.setAccessible(true);
        out.append("axle:").append(axle.invoke(null,player)).append(",rootTracks:");
        for(var track:player.getAnimationPlayer().getMultiTrack().getTracks())
            if(track.getLayerIdx()==0) out.append(track.getName()).append("@")
                .append(track.getBlendWeight()).append("/").append(track.getCurrentTimeValue())
                .append("/").append(track.getSpeedDelta()).append(";");
        return out.toString();
    }

    @LuaMethod(name="cartLabPoseHeading", global=true)
    public static void poseHeading(double angle) throws Exception {
        if (!Double.isFinite(angle)) throw new IllegalArgumentException("finite heading required");
        var player = IsoPlayer.getInstance();
        float x = (float) Math.cos(angle), y = (float) Math.sin(angle);
        player.setTargetAndCurrentDirection(x, y);
        player.getAnimationPlayer().setTargetAndCurrentDirection(x, y);
        Class.forName("net.alexredby.pztoolkitjavapatches.CartSteeringHooks")
            .getMethod("reset", IsoPlayer.class).invoke(null, player);
    }

    @LuaMethod(name="cartLabGait", global=true)
    public static void gait(int value) {
        if (value < 0 || value > 2) throw new IllegalArgumentException("gait must be 0, 1 or 2");
        gait = value;
    }

    @LuaMethod(name="cartLabHeading", global=true)
    public static double heading() {
        var direction=IsoPlayer.getInstance().getAnimForwardDirection(new zombie.iso.Vector2());
        return Math.atan2(direction.y,direction.x);
    }

    @LuaMethod(name="cartLabSteeringHeading", global=true)
    public static double steeringHeading() {
        float accepted=net.alexredby.pztoolkitjavapatches.CartSteeringHooks.networkHeading(IsoPlayer.getInstance());
        return Float.isFinite(accepted)?accepted:heading();
    }

    @LuaMethod(name="cartLabFrame", global=true)
    public static int frame() {
        return zombie.iso.IsoWorld.instance.getFrameNo();
    }

    @LuaMethod(name="cartLabWheelPhase", global=true)
    public static double wheelPhase() throws Exception {
        return ((Number)Class.forName("net.alexredby.pztoolkitjavapatches.CartSteeringHooks")
            .getMethod("wheelPhase",IsoPlayer.class).invoke(null,IsoPlayer.getInstance())).doubleValue();
    }

    @LuaMethod(name="cartLabFootprint", global=true)
    public static String footprint() throws Exception {
        var player=IsoPlayer.getInstance();
        var hooks=Class.forName("net.alexredby.pztoolkitjavapatches.CartSteeringHooks");
        var states=hooks.getDeclaredField("states");states.setAccessible(true);
        Object state=((java.util.Map<?,?>)states.get(null)).get(player);
        if(state==null) throw new IllegalStateException("Cart state required");
        var front=state.getClass().getDeclaredField("footprintFront");front.setAccessible(true);
        var heading=state.getClass().getDeclaredField("heading");heading.setAccessible(true);
        var shape=Class.forName("net.alexredby.pztoolkitjavapatches.CartFootprint");
        var world=shape.getDeclaredMethod("world",IsoPlayer.class);world.setAccessible(true);
        var clear=shape.getDeclaredMethod("clear",Class.forName(shape.getName()+"$Query"),double.class,double.class,double.class,double.class);
        clear.setAccessible(true);
        var out=new StringBuilder("front=").append(front.getDouble(state));
        for(String key:new String[]{"cartBlocked","recovering"}) {
            var part=state.getClass().getDeclaredField(key);part.setAccessible(true);
            out.append(' ').append(key.equals("cartBlocked")?"blocked":key).append('=').append(part.getBoolean(state));
        }
        return out.append(" clear=").append(clear.invoke(null,world.invoke(null,player),player.getX(),player.getY(),heading.getDouble(state),front.getDouble(state))).toString();
    }

    @LuaMethod(name="cartLabBrace", global=true)
    public static String brace(double wallX,double y) throws Exception {
        vehicleGuard();
        var player=IsoPlayer.getInstance();int z=(int)Math.floor(player.getZ());
        float x=(float)wallX,fy=(float)y;
        if(!Float.isFinite(x+fy) || z<=0 || Math.abs(x-player.getX())>16 || Math.abs(fy-player.getY())>16)
            throw new IllegalArgumentException("Loaded local upper-pad wall query required");
        var cell=player.getCell();
        if(cell.getGridSquare((int)Math.floor(x-.5),(int)Math.floor(fy),z)==null
            || cell.getGridSquare((int)Math.floor(x+.5),(int)Math.floor(fy),z)==null)
            throw new IllegalStateException("Wall query squares must remain loaded");
        var hooks=Class.forName("net.alexredby.pztoolkitjavapatches.CartSteeringHooks");
        var states=hooks.getDeclaredField("states");states.setAccessible(true);
        Object state=((java.util.Map<?,?>)states.get(null)).get(player);
        if(state==null) throw new IllegalStateException("Cart state required");
        var amount=state.getClass().getDeclaredField("brace");amount.setAccessible(true);
        var intent=state.getClass().getDeclaredField("wantsMove");intent.setAccessible(true);
        double value=amount.getDouble(state);
        if(!Double.isFinite(value) || value<0 || value>1) throw new IllegalStateException("Invalid brace amount");
        boolean blocked=zombie.pathfind.PolygonalMap2.instance.lineClearCollide(x+.5f,fy,x-.5f,fy,z,null,zombie.pathfind.PolygonalMap2.LCC_ZERO);
        return "brace="+value+" nativeBlocked="+blocked+" wantsMove="+intent.getBoolean(state);
    }

    private static zombie.vehicles.BaseVehicle fixtureVehicle;
    private static float[] fixtureHull;
    private static float fixtureZ;

    private static void vehicleGuard() {
        if (!"true".equals(System.getenv("PZ_CART_TEST_PAD"))
            || !"CartTestArea".equals(zombie.iso.IsoWorld.instance.getWorld())
            || zombie.network.GameClient.client || zombie.network.GameServer.server)
            throw new IllegalStateException("Disposable single-player CartTestArea pad required");
    }

    @LuaMethod(name="cartLabVehicleCreate", global=true)
    public static zombie.vehicles.BaseVehicle vehicleCreate(double x,double y,int z,double yaw) {
        vehicleGuard();
        if (fixtureVehicle!=null || !Double.isFinite(x+y+yaw) || z<=0)
            throw new IllegalArgumentException("Empty fixture slot and finite upper-pad pose required");
        var cell=zombie.iso.IsoWorld.instance.currentCell;
        var square=cell.getGridSquare((int)Math.floor(x),(int)Math.floor(y),z);
        if (square==null || square.getFloor()==null || !square.TreatAsSolidFloor())
            throw new IllegalStateException("Loaded fixture floor required");
        var vehicle=new zombie.vehicles.BaseVehicle(cell);
        // addToWorld randomly scatters car keys; this fixture owns only the collision body.
        vehicle.keySpawned=1;
        fixtureVehicle=vehicle;
        try {
            vehicle.setScriptName("Base.CarNormal");vehicle.setScript();
            if(vehicle.getScript()==null) throw new IllegalStateException("Native CarNormal script missing");
            vehicle.setX((float)x);vehicle.setY((float)y);vehicle.setZ(z);
            vehicle.savedRot.setAngleAxis((float)yaw,0,1,0);
            vehicle.jniTransform.setRotation(vehicle.savedRot);
            vehicle.setSquare(square);vehicle.chunk=square.getChunk();
            vehicle.chunk.vehicles.add(vehicle);vehicle.addToWorld();
            vehicle.setPhysicsActive(false);
            vehicle.polyDirty=true;fixtureZ=vehicle.getZ();fixtureHull=vehicleHull(vehicle);
            vehicleState();
            return vehicle;
        } catch(RuntimeException failure) {
            vehicleRemove();throw failure;
        }
    }

    private static float[] vehicleHull(zombie.vehicles.BaseVehicle vehicle) {
        var p=vehicle.getPoly();
        return new float[]{p.x1,p.y1,p.x2,p.y2,p.x3,p.y3,p.x4,p.y4};
    }

    private static zombie.vehicles.BaseVehicle checkedVehicle() {
        vehicleGuard();var v=fixtureVehicle;
        if(v==null || !v.addedToWorld || v.getId()<0 || !v.isStatic || v.isActive || v.isPhysicsActive()
            || v.getZ()!=fixtureZ || v.getPoly().z!=fixtureZ || v.chunk==null || !v.chunk.vehicles.contains(v))
            throw new IllegalStateException("Owned static native vehicle identity/level changed");
        float[] hull=vehicleHull(v);
        for(int i=0;i<hull.length;i++)
            if(!Float.isFinite(hull[i]) || Math.abs(hull[i]-fixtureHull[i])>.002)
                throw new IllegalStateException("Owned native vehicle hull moved");
        return v;
    }

    @LuaMethod(name="cartLabVehicleCheck", global=true)
    public static boolean vehicleCheck() { checkedVehicle();return true; }

    @LuaMethod(name="cartLabVehicleState", global=true)
    public static String vehicleState() {
        var v=checkedVehicle();float[] hull=vehicleHull(v);
        var p=IsoPlayer.getInstance();var map=zombie.pathfind.PolygonalMap2.instance;
        float cx=0,cy=0;for(int i=0;i<8;i+=2){cx+=hull[i]/4;cy+=hull[i+1]/4;}
        var out=new StringBuilder("id=").append(v.getId()).append(" z=").append(v.getZ())
            .append(" static=").append(v.isStatic).append(" active=").append(v.isActive)
            .append(" bodyBlocked=").append(!map.canStandAt(cx,cy,(int)fixtureZ,p,false,false))
            .append(" crossBlocked=").append(map.lineClearCollide(cx-8,cy,cx+8,cy,(int)fixtureZ,p,zombie.pathfind.PolygonalMap2.LCC_ZERO))
            .append(" hull=");
        for(int i=0;i<8;i++){if(i>0)out.append(',');out.append(hull[i]);}
        return out.toString();
    }

    @LuaMethod(name="cartLabVehicleSquareAllowed", global=true)
    public static boolean vehicleSquareAllowed(int x,int y,int z) {
        vehicleGuard();if(fixtureVehicle==null) return false;
        checkedVehicle();boolean owned=false;
        var cell=zombie.iso.IsoWorld.instance.currentCell;
        // The native square query searches neighbouring chunks; inspect the same owners, including pending adds.
        var seen=new java.util.HashSet<zombie.vehicles.BaseVehicle>(cell.getVehicles());
        seen.addAll(cell.addVehicles);
        for(int cx=x-16;cx<=x+16;cx+=8) for(int cy=y-16;cy<=y+16;cy+=8) {
            var chunk=cell.getChunkForGridSquare(cx,cy,0);if(chunk!=null) seen.addAll(chunk.vehicles);
        }
        for(var v:seen) if(v.isIntersectingSquare(x,y,z)) {
            if(v!=fixtureVehicle) return false;owned=true;
        }
        return owned;
    }

    @LuaMethod(name="cartLabVehicleRemove", global=true)
    public static void vehicleRemove() {
        vehicleGuard();var v=fixtureVehicle;if(v==null)return;
        if(v.addedToWorld)v.permanentlyRemove();
        if(v.chunk!=null)v.chunk.vehicles.remove(v);
        fixtureVehicle=null;fixtureHull=null;
    }

    @LuaMethod(name="cartLabMillis", global=true)
    public static double millis() { return System.nanoTime()/1_000_000.0; }

    @LuaMethod(name="cartLabDrive", global=true)
    public static void drive(int value) {
        if (value < -1 || value > 8) throw new IllegalArgumentException("drive must be -1..8");
        drive = value;
    }

    @LuaMethod(name="cartLabTracks", global=true)
    public static String tracks() {
        var out = new StringBuilder();
        for (var track : IsoPlayer.getInstance().getAnimationPlayer().getMultiTrack().getTracks())
            out.append(track.getName()).append("=").append(track.getSpeedDelta()).append("@").append(track.getBlendWeight()).append(";");
        return out.toString();
    }

    @LuaMethod(name="cartLabReload", global=true)
    public static void reload() {
        if (!Files.isRegularFile(runtime)) throw new IllegalStateException("Missing configured runtime Lua: " + runtime);
        zombie.Lua.LuaManager.loaded.remove(runtime.toString());
        zombie.Lua.LuaManager.RunLua(runtime.toString(), false);
    }

    @LuaMethod(name="cartLabPoll", global=true)
    public static void poll() throws Exception {
        if (!Files.exists(commands)) return;
        long changed = Files.getLastModifiedTime(commands).toMillis();
        if (changed == lastCommand) return;
        lastCommand = changed;
        switch (Files.readString(commands).trim()) {
            case "reload" -> reload();
            case "screenshot" -> Core.getInstance().TakeFullScreenshot("cart-lab-live.png");
            default -> throw new IllegalArgumentException("Unknown cart lab command");
        }
    }

    public static void main(String[] args) { System.out.println("[CART_LAB] LOADED"); }

    /** Hold a test key through the native input poll; dispatch the real Lua event handlers. */
    @LuaMethod(name="cartLabKeyState", global=true)
    public static void keyState(int key, boolean down) {
        if (drive < 0 || key <= 0 || key >= 256)
            throw new IllegalStateException("Key fixture requires isolated drive and a keyboard key");
        if (down) {
            if (heldKey == key) return;
            if (heldKey >= 0) throw new IllegalStateException("Release the previous fixture key first");
            heldKey = key;
            zombie.Lua.LuaEventManager.triggerEvent("OnKeyStartPressed", Integer.valueOf(key));
            zombie.Lua.LuaEventManager.triggerEvent("OnCustomUIKeyPressed", Integer.valueOf(key));
        } else {
            if (heldKey < 0) return;
            if (heldKey != key) throw new IllegalStateException("Wrong fixture key release");
            heldKey = -1;
            zombie.Lua.LuaEventManager.triggerEvent("OnKeyPressed", Integer.valueOf(key));
            zombie.Lua.LuaEventManager.triggerEvent("OnCustomUIKey", Integer.valueOf(key));
            zombie.Lua.LuaEventManager.triggerEvent("OnCustomUIKeyReleased", Integer.valueOf(key));
        }
    }

    @LuaMethod(name="cartLabContextSeconds", global=true)
    public static float contextSeconds() { return IsoPlayer.getInstance().timePressedContext; }

    public static boolean fixtureKey(int key) {
        if (heldKey == key) return true;
        if (drive < 0) return false;
        if (gait > 0 && key == Core.getInstance().getKey(gait == 1 ? "Run" : "Sprint")) return true;
        if (drive == 0) return false;
        String first = switch(drive) {
            case 1, 5 -> "Forward"; case 2, 6 -> "Left";
            case 3, 8 -> "Right"; default -> "Backward";
        };
        String second = switch(drive) {
            case 5 -> "Left"; case 6 -> "Backward"; case 7 -> "Right"; case 8 -> "Forward"; default -> null;
        };
        return key == Core.getInstance().getKey(first)
            || second != null && key == Core.getInstance().getKey(second);
    }

    @Patch(className="zombie.input.GameKeyboard", methodName="isKeyDown", warmUp=true)
    public static class Keys {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(0) int key, @Patch.Local("fixture") boolean fixture) {
            fixture = drive >= 0;
            return fixture;
        }
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) int key, @Patch.Local("fixture") boolean fixture,
                                @Patch.Return(readOnly=false) boolean result) {
            if (fixture) result = fixtureKey(key);
        }
    }

    @Patch(className="zombie.input.GameKeyboard", methodName="isKeyDownRaw", warmUp=true)
    public static class RawKeys {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(0) int key, @Patch.Local("fixture") boolean fixture) {
            fixture = drive >= 0;
            return fixture;
        }
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) int key, @Patch.Local("fixture") boolean fixture,
                                @Patch.Return(readOnly=false) boolean result) {
            if (fixture) result = fixtureKey(key);
        }
    }
}
