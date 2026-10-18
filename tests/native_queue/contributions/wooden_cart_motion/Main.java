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

    public static boolean fixtureKey(int key) {
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
