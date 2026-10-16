package net.alexredby.pztoolkitjavapatches;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.lwjgl.util.vector.Vector3f;
import sun.misc.Unsafe;
import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.advancedanimation.AnimNode;
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlend;
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlendPicker;
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlendTriangle;
import zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator;
import zombie.core.skinnedmodel.advancedanimation.AnimLayer;
import zombie.core.skinnedmodel.advancedanimation.AnimTransition;
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode;
import zombie.core.skinnedmodel.animation.AnimationClip;
import zombie.core.skinnedmodel.animation.AnimationPlayer;
import zombie.core.skinnedmodel.animation.AnimationMultiTrack;
import zombie.core.skinnedmodel.animation.AnimationTrack;
import zombie.core.skinnedmodel.animation.BoneAxis;
import zombie.core.skinnedmodel.animation.Keyframe;
import zombie.core.skinnedmodel.model.SkinningData;
import zombie.iso.Vector2;

public final class CartLegPaceTest {
    private static final class Player extends IsoPlayer {
        AnimationPlayer animation;
        AdvancedAnimator animator;
        boolean loaded,run;
        Player() {super(null,null,0,0,0);}
        @Override public boolean hasAnimationPlayer() {return loaded;}
        @Override public boolean isRunning() {return run;}
        @Override public boolean isSprinting() {return false;}
        @Override public AnimationPlayer getAnimationPlayer() {return animation;}
        @Override public AdvancedAnimator getAdvancedAnimator() {return animator;}
    }

    private static void nativePelvisBinding() throws Exception {
        var unsafeField=Unsafe.class.getDeclaredField("theUnsafe");unsafeField.setAccessible(true);
        var unsafe=(Unsafe)unsafeField.get(null);
        var player=(Player)unsafe.allocateInstance(Player.class);
        var animation=(AnimationPlayer)unsafe.allocateInstance(AnimationPlayer.class);
        player.animation=animation;player.loaded=true;player.run=true;
        var skinning=AnimationPlayer.class.getDeclaredField("skinningData");skinning.setAccessible(true);
        var transforms=AnimationPlayer.class.getDeclaredField("modelTransforms");transforms.setAccessible(true);
        close(CartLegPace.woodenGaitShift(player),0,"unloaded native skinning keeps gait fallback");
        var identity=new org.lwjgl.util.vector.Matrix4f();
        var bones=List.of(identity,identity);
        var actor=new SkinningData(new HashMap<>(),bones,bones,bones,List.of(-1,0),
            new HashMap<>(Map.of("root",0,"Bip01_Spine",1)));
        skinning.set(animation,actor);
        var pose=new org.lwjgl.util.vector.Matrix4f();
        pose.m03=.01f;pose.m23=-.02f;
        // Opposite storage entries deliberately disagree so reading untransposed translation cannot pass.
        pose.m30=.8f;pose.m32=.9f;
        var palette=new org.lwjgl.util.vector.Matrix4f[]{identity,pose};transforms.set(animation,palette);
        float[] before=new float[16];pose.store(java.nio.FloatBuffer.wrap(before));
        close(CartLegPace.woodenGaitShift(player),-.08594764,"native transposed Spine x/z drive shaft clearance");
        float[] after=new float[16];pose.store(java.nio.FloatBuffer.wrap(after));
        if(!java.util.Arrays.equals(before,after)) throw new AssertionError("pelvis binding changed the native model pose");
        pose.m03=0;pose.m23=-.03f;
        close(CartLegPace.woodenGaitShift(player),-.06594764,"native pelvis movement updates clearance independently of gait");
        player.run=false;
        close(CartLegPace.woodenGaitShift(player),0,"ordinary Walk retains native cart position despite pelvis sway");
        player.run=true;
        player.loaded=false;
        close(CartLegPace.woodenGaitShift(player),0,"unavailable animation player keeps gait fallback");
        player.loaded=true;player.animation=null;
        close(CartLegPace.woodenGaitShift(player),0,"missing native animation keeps gait fallback");
        player.animation=animation;actor.boneIndices.remove("Bip01_Spine");
        close(CartLegPace.woodenGaitShift(player),0,"rig without Spine keeps gait fallback");
        for(int index:new int[]{-1,2}) {
            actor.boneIndices.put("Bip01_Spine",index);
            close(CartLegPace.woodenGaitShift(player),0,"invalid Spine index keeps gait fallback");
        }
        actor.boneIndices.put("Bip01_Spine",1);
        for(var unloaded:new org.lwjgl.util.vector.Matrix4f[][]{null,new org.lwjgl.util.vector.Matrix4f[0],
            new org.lwjgl.util.vector.Matrix4f[]{identity,null}}) {
            transforms.set(animation,unloaded);
            close(CartLegPace.woodenGaitShift(player),0,"unavailable native model pose keeps gait fallback");
        }
    }

    private static void close(float actual, double expected, String message) {
        if (!Float.isFinite(actual) || Math.abs(actual - expected) > 1e-5)
            throw new AssertionError(message + ": " + actual + " != " + expected);
    }

    private static AnimationClip clip(String name, float duration, float x, float y, String bone) {
        Keyframe start = new Keyframe(), end = new Keyframe();
        start.boneName = end.boneName = bone;
        start.position = new Vector3f();
        end.position = new Vector3f(x, 0, -y);
        end.time = duration;
        return new AnimationClip(duration, List.of(start, end), name, true);
    }

    private static Anim2DBlend blend(String name, float x, float y) {
        var blend = new Anim2DBlend();
        blend.animName = name; blend.posX = x; blend.posY = y;
        return blend;
    }

    private static AnimNode node() {
        var node = new AnimNode();
        var idle = blend("idle", 0, 0);
        var forward = blend("forward", 0, 1);
        var right = blend("right", 1, 0);
        var back = blend("back", 0, -1);
        var left = blend("left", -1, 0);
        node.blends2d.addAll(List.of(idle, forward, right, back, left));
        var rim = List.of(forward, right, back, left);
        for (int i = 0; i < rim.size(); i++) {
            var triangle = new Anim2DBlendTriangle();
            triangle.node1 = idle; triangle.node2 = rim.get((i + 1) % rim.size()); triangle.node3 = rim.get(i);
            node.blendTris.add(triangle);
        }
        node.blend2dPicker = new Anim2DBlendPicker();
        node.blend2dPicker.SetPickTriangles(node.blendTris);
        return node;
    }

    private static float blendedSpeed(AnimNode node, Map<String, AnimationClip> clips, float x, float y) {
        var pick = node.blend2dPicker.Pick(x, y, new Anim2DBlendPicker.PickResults());
        double dx = 0, dy = 0;
        for (int i = 0; i < pick.numNodes; i++) {
            var blend = i == 0 ? pick.node1 : i == 1 ? pick.node2 : pick.node3;
            float weight = i == 0 ? pick.scale1 : i == 1 ? pick.scale2 : pick.scale3;
            if (weight < 1e-4f) continue;
            var clip = clips.get(blend.animName);
            var root = clip.getTotalTranslation("Translation_Data", BoneAxis.Y, new Vector2());
            dx += Math.min(1, weight) * root.x / clip.getDuration();
            dy += Math.min(1, weight) * root.y / clip.getDuration();
        }
        return (float) Math.hypot(dx, dy);
    }

    private static LiveAnimNode live(String name, boolean active, AnimationClip clip) {
        var source = new AnimNode(); source.name = name;
        var node = LiveAnimNode.alloc(null, source);
        var track = AnimationTrack.alloc();
        track.startClip(clip, true, 0); track.setSpeedDelta(1.1f);
        track.advance(.25f); track.setBlendWeight(.3f);
        node.addMainTrack(track); node.setActive(active);
        return node;
    }

    private static LiveAnimNode transition(AnimLayer layer, String nodeName, String clipName, float weight) {
        var source=new AnimNode();source.name=nodeName;
        var outgoing=new AnimNode();outgoing.name="ToolkitCartPivotRun";
        var node=LiveAnimNode.alloc(layer,source);
        var track=AnimationTrack.alloc();
        track.startClip(clip(clipName,2,0,1,"Translation_Data"),false,0);
        track.setSpeedDelta(.7f);
        if(layer.getAnimationTrack()!=null) layer.getAnimationTrack().addTrack(track);
        node.startTransitionIn(outgoing,new AnimTransition(),track);
        node.setTransitionInBlendDelta(weight);
        layer.getLiveAnimNodes().add(node);
        return node;
    }

    private static void brakeTracks() throws Exception {
        var unsafeField=Unsafe.class.getDeclaredField("theUnsafe");unsafeField.setAccessible(true);
        var unsafe=(Unsafe)unsafeField.get(null);
        var player=(Player)unsafe.allocateInstance(Player.class);
        player.animation=(AnimationPlayer)unsafe.allocateInstance(AnimationPlayer.class);
        var multi=new AnimationMultiTrack();
        var tracks=AnimationPlayer.class.getDeclaredField("multiTrack");tracks.setAccessible(true);tracks.set(player.animation,multi);
        player.animator=new AdvancedAnimator();
        var layer=AnimLayer.alloc(player,player.animator);
        var root=AdvancedAnimator.class.getDeclaredField("rootLayer");root.setAccessible(true);root.set(player.animator,layer);
        if(CartLegPace.brakeTrack(player)!=null)
            throw new AssertionError("missing cart brake must not claim another animation");
        for(String name:List.of("Bob_RunToStop2H_Heavy","Bob_SprintToStop2h_Heavy")) {
            var unrelated=transition(layer,"ToolkitCartIdle","Bob_IdleToRun",.4f);
            var unrelatedTrack=unrelated.getTransitionInTrack();
            var idle=transition(layer,"ToolkitCartIdle",name,.6f);
            var stop=idle.getTransitionInTrack();
            if(CartLegPace.brakeTrack(player)!=stop)
                throw new AssertionError("native cart transition must own the exact heavy stop: "+name);
            idle.setActive(false);
            close(CartLegPace.woodenGaitShift(layer.getLiveAnimNodes()),0,
                "upright stop cannot inherit the running offset that makes idle grip unreachable");
            var forward=live("ToolkitCartPivotRun",false,clip("forward",1,0,1,"Translation_Data"));
            forward.getMainAnimationTrackAt(0).setBlendWeight(.5f);
            close(CartLegPace.woodenGaitShift(List.of(forward,idle)),-.06,
                "outgoing running gait keeps its actual clearance while the stop uses the live pelvis envelope");
            float time=stop.getCurrentTimeValue();
            CartLegPace.cancelBrake(player,false);
            if(stop.getUseDeferredMovement() || idle.getTransitionInTrack()!=stop || !idle.isTransitioningIn())
                throw new AssertionError("resume cancels only stop translation and keeps its native visual fade");
            close(stop.getSpeedDelta(),.7,"resume must preserve stop cadence");
            close(stop.getCurrentTimeValue(),time,"resume must preserve stop phase");
            close(stop.getBlendWeight(),.6,"resume must preserve stop visual weight");
            CartLegPace.cancelBrake(player,true);
            if(idle.getTransitionInTrack()!=null || idle.isTransitioningIn() || CartLegPace.brakeTrack(player)!=null)
                throw new AssertionError("hard cleanup must release the owned stop transition");
            if(multi.getTracks().contains(stop))
                throw new AssertionError("hard cleanup must remove the stop from the native animation mixer");
            if(unrelated.getTransitionInTrack()!=unrelatedTrack || !unrelatedTrack.getUseDeferredMovement())
                throw new AssertionError("owned stop cleanup must retain the neighboring idle transition");
            layer.getLiveAnimNodes().clear();
            multi.reset();
        }
        for(String[] other:new String[][]{{"IdleHeavy","Bob_RunToStop2H_Heavy"},
            {"ToolkitCartIdle","Bob_RunToStop"},{"ToolkitCartIdle","Bob_SprintToStop_2h_Heavy"}}) {
            var idle=transition(layer,other[0],other[1],.4f);
            var track=idle.getTransitionInTrack();
            if(CartLegPace.brakeTrack(player)!=null)
                throw new AssertionError("unrelated or misspelled stop must stay outside cart ownership");
            CartLegPace.cancelBrake(player,false);CartLegPace.cancelBrake(player,true);
            if(idle.getTransitionInTrack()!=track || !track.getUseDeferredMovement())
                throw new AssertionError("cart cleanup changed an unrelated native transition");
            close(CartLegPace.woodenGaitShift(layer.getLiveAnimNodes()),0,"unrelated transition cannot shift the cart");
            layer.getLiveAnimNodes().clear();
            multi.reset();
        }
    }

    private static void rampChecks() {
        var empty = new CartLegPace.Ramp();
        var full = new CartLegPace.Ramp();
        for (int i = 0; i < 12; i++) {
            empty.update(4, 1.0 / 60, 0);
            full.update(4, 1.0 / 60, 1);
        }
        if (!(full.speed > 0 && full.speed < empty.speed && empty.speed < 4))
            throw new AssertionError("cargo must lengthen Sprint acceleration");
        empty.reset(4); full.reset(4);
        for (int i = 0; i < 12; i++) {
            empty.update(0, 1.0 / 60, 0);
            full.update(0, 1.0 / 60, 1);
        }
        if (!(full.speed > empty.speed && empty.speed > 0))
            throw new AssertionError("cargo must lengthen Sprint braking");
        double referenceSpeed = 0, referenceVelocity = 0;
        for (int fps : new int[]{20, 60, 144}) {
            var ramp = new CartLegPace.Ramp();
            for (int i = 0; i < fps / 2; i++) ramp.update(4, 1.0 / fps, 1);
            if (fps == 20) { referenceSpeed = ramp.speed; referenceVelocity = ramp.velocity; }
            if (Math.abs(ramp.speed - referenceSpeed) > 1e-10 || Math.abs(ramp.velocity - referenceVelocity) > 1e-10)
                throw new AssertionError("Sprint ramp depends on frame rate: " + fps);
        }
        var ramp = new CartLegPace.Ramp(); ramp.reset(0);
        for (int i = 0; i < 5; i++) ramp.update(4, 1.0 / 60, 1);
        double previous = ramp.speed;
        for (int i = 0; i < 100; i++) {
            ramp.update(0, 1.0 / 60, 1);
            if (ramp.speed > previous || ramp.speed < 0)
                throw new AssertionError("Sprint release kept accelerating or reversed movement");
            previous = ramp.speed;
        }
        if (!ramp.settled(0)) throw new AssertionError("Sprint ramp never settles after release");
        ramp.reset(2);
        for (double paused : new double[]{0, -.1, Double.NaN, Double.POSITIVE_INFINITY}) {
            ramp.update(4, paused, 0);
            close((float) ramp.speed, 2, "paused/invalid dt cannot move the ramp");
            close((float) ramp.velocity, 0, "paused/invalid dt cannot accelerate the ramp");
        }
        ramp.update(Double.NaN, .1, 0);
        close((float) ramp.speed, 2, "missing calibration keeps the current speed");
        empty.reset(2); full.reset(2);
        empty.update(4, .1, 0); full.update(4, .5, Double.NaN);
        close((float) full.speed, empty.speed, "long dt is capped and invalid load uses empty cart");
        for (double load : new double[]{-1, 2}) {
            empty.reset(0); full.reset(0);
            empty.update(4, .1, load < 0 ? 0 : 1); full.update(4, .1, load);
            close((float) full.speed, empty.speed, "cargo ratio is bounded to the supported range");
        }
        ramp.reset(Double.NaN);
        close((float) ramp.speed, 0, "invalid reset cannot poison later movement");
        if (!ramp.settled(0) || ramp.settled(Double.NaN)) throw new AssertionError("invalid settled state");
    }

    private static void speedChecks(AnimNode source, AnimationClip walk, AnimationClip run, AnimationClip sprint) {
        close(CartLegPace.targetSpeed(source, walk, run, .3f, 1, 1.04f),
            1.04 * (walk.getTotalTranslation("Translation_Data", BoneAxis.Y, new Vector2()).getLength() / walk.getDuration() * .7
                + run.getTotalTranslation("Translation_Data", BoneAxis.Y, new Vector2()).getLength() / run.getDuration() * .3),
            "absolute native target includes the native gait blend and base pace once");
        close(CartLegPace.targetSpeed(source, walk, walk, 1, .4f, 1.04f),
            1.04 * .4 * walk.getTotalTranslation("Translation_Data", BoneAxis.Y, new Vector2()).getLength() / walk.getDuration(),
            "walking target includes the intent magnitude once");
        close(CartLegPace.targetSpeed(null, 0, 0), 0, "idle needs no calibration");
        if (!Float.isNaN(CartLegPace.targetSpeed(null, 0, 1))
            || !Float.isNaN(CartLegPace.targetSpeed(source, walk, null, 1, 1, 1)))
            throw new AssertionError("missing calibration must remain distinguishable from a stop");
        var walking = live("ToolkitCartPivotWalk", true, walk);
        var running = live("ToolkitCartPivotRun", false, run);
        var sprinting = live("ToolkitCartPivotSprint", false, sprint);
        var untouched = live("ToolkitCartSprintRight", true, sprint);
        var nodes = List.of(walking, running, sprinting, untouched);
        for (var node : nodes) node.getMainAnimationTrackAt(0).setBlendFieldWeight(1);
        for (float speed : new float[]{1.2f, .6f, 0}) {
            CartLegPace.applySpeedTracks(nodes, speed, null, 0, 1);
            for (var node : List.of(walking, running, sprinting)) {
                var track = node.getMainAnimationTrackAt(0);
                var clip = track.getClip();
                double velocity = clip.getTotalTranslation("Translation_Data", BoneAxis.Y, new Vector2()).getLength() / clip.getDuration();
                close((float) (track.getSpeedDelta() * velocity), speed,
                    "incoming and inactive outgoing gaits share one smoothed root velocity");
                close(track.getCurrentTimeValue(), .25, "speed ramp preserves animation phase");
                close(track.getBlendWeight(), .3, "speed ramp preserves native fade weights");
            }
            close(untouched.getMainAnimationTrackAt(0).getSpeedDelta(), 1.1, "upper-body cadence remains native");
        }
        var current = live("ToolkitCartPivotSprint", false, sprint);
        var strafe = AnimationTrack.alloc(); strafe.startClip(clip("old-strafe", 1, 1, 0, "Translation_Data"), true, 0);
        strafe.setBlendFieldWeight(1); current.addMainTrack(strafe);
        var forward = current.getMainAnimationTrackAt(0); forward.setBlendFieldWeight(0);
        float sprintVelocity = sprint.getTotalTranslation("Translation_Data", BoneAxis.Y, new Vector2()).getLength() / sprint.getDuration();
        float newPace = 1 / sprintVelocity;
        CartLegPace.applySpeedTracks(List.of(current, running), 1, current.getName(), newPace, 1);
        close(forward.getSpeedDelta(), newPace, "reactivating current gait uses the new picker, not old strafe weights");
        close(strafe.getSpeedDelta(), newPace, "all current gait tracks receive the new directional cadence");
        forward.setBlendFieldWeight(1); strafe.setBlendFieldWeight(0);
        close(forward.getSpeedDelta() * sprintVelocity, 1, "native directional refresh cannot jump the requested speed");
        CartLegPace.applySpeedTracks(List.of(current), .5f, null, 1.04f, 0);
        close(forward.getSpeedDelta() * sprintVelocity, .5, "zero intent keeps every remaining gait on outgoing root speed");
        // An outgoing blend keeps the last directional weights after native deactivation.
        var lateral = AnimationTrack.alloc(); lateral.startClip(clip("outgoing-strafe", 1, 1, 0, "Translation_Data"), true, 0);
        lateral.setBlendFieldWeight(.25f); sprinting.addMainTrack(lateral);
        sprinting.getMainAnimationTrackAt(0).setBlendFieldWeight(.75f);
        CartLegPace.applySpeedTracks(List.of(sprinting), 1, null, 0, 1);
        double intrinsic = Math.hypot(.25,
            .75 * sprint.getTotalTranslation("Translation_Data", BoneAxis.Y, new Vector2()).getLength() / sprint.getDuration());
        close((float) (intrinsic * lateral.getSpeedDelta()), 1, "outgoing blend velocity uses all main track weights");
        close(lateral.getSpeedDelta(), sprinting.getMainAnimationTrackAt(0).getSpeedDelta(), "all blended clips use one node cadence");
    }

    private static void reversalChecks(AnimationClip walk, AnimationClip back) {
        var forward = live("ToolkitCartPivotRun", false, walk);
        var backward = live("ToolkitCartPivotWalk", false, back);
        var current = live("ToolkitCartPivotSprint", false, walk);
        var untouched = live("ToolkitCartRunRight", true, walk);
        var nodes = List.of(forward, backward, current, untouched);
        for (var node : nodes) node.getMainAnimationTrackAt(0).setBlendFieldWeight(1);
        for (float stepY : new float[]{-1, 1, 0, -1e-8f, 1e-8f}) {
            CartLegPace.applySpeedTracks(nodes, .6f, current.getName(), .7f, stepY);
            for (var node : List.of(forward, backward)) {
                var track = node.getMainAnimationTrackAt(0);
                var root = track.getClip().getTotalTranslation("Translation_Data", BoneAxis.Y, new Vector2());
                float velocity = root.getLength() / track.getClip().getDuration();
                boolean opposite = root.y / track.getClip().getDuration() * stepY < -1e-6;
                close(track.getSpeedDelta() * velocity, opposite ? 0 : .6,
                    "only opposite outgoing root motion stops: " + node.getName() + "/" + stepY);
                close(track.getCurrentTimeValue(), .25, "reversal preserves outgoing foot phase");
                close(track.getBlendWeight(), .3, "reversal preserves native fade weight");
                close(track.getBlendFieldWeight(), 1, "reversal preserves latched directional weights");
            }
            close(current.getMainAnimationTrackAt(0).getSpeedDelta(), .7,
                "incoming gait gets new cadence before native directional refresh");
            close(untouched.getMainAnimationTrackAt(0).getSpeedDelta(), 1.1,
                "reversal leaves upper-body tracks untouched");
        }
        // Mixed outgoing fields use their combined root, not the sign of one clip.
        var reverseTrack = AnimationTrack.alloc(); reverseTrack.startClip(back, true, 0);
        forward.addMainTrack(reverseTrack);
        forward.getMainAnimationTrackAt(0).setBlendFieldWeight(.1f);
        reverseTrack.setBlendFieldWeight(.9f);
        CartLegPace.applySpeedTracks(List.of(forward), .2f, null, 0, -1);
        double rootY = .1 * walk.getTotalTranslation("Translation_Data", BoneAxis.Y, new Vector2()).y / walk.getDuration()
            + .9 * back.getTotalTranslation("Translation_Data", BoneAxis.Y, new Vector2()).y / back.getDuration();
        close((float) (Math.abs(rootY) * reverseTrack.getSpeedDelta()), .2,
            "same-sign mixed outgoing root keeps the requested speed");
        CartLegPace.applySpeedTracks(List.of(forward), .2f, null, 0, 1);
        for (var track : forward.getMainAnimationTracks())
            close(track.getSpeedDelta(), 0, "opposite mixed outgoing field stops all its main tracks");
        CartLegPace.applySpeedTracks(nodes, 0, null, 0, -1);
        for (var node : List.of(forward, backward, current))
            for (var track : node.getMainAnimationTracks())
                close(track.getSpeedDelta(), 0, "zero speed stops every owned outgoing gait");
    }

    private static void backwardChecks(AnimNode node, Map<String, AnimationClip> clips) {
        String wood = "SaucedWheelbarrow.WheelbarrowWood";
        if (!CartLegPace.walkingReference(wood, false, -1).equals("Bob_WalkBwdNoAim1Hand"))
            throw new AssertionError("wooden reverse walking must use the authored backward reference");
        for (String other : new String[]{null, "SaucedWheelbarrow.WheelbarrowMetal", "SaucedCarts.ShoppingCart"})
            if (!CartLegPace.walkingReference(other, false, -1).equals("Bob_Walk"))
                throw new AssertionError("reverse walking reference escaped the wooden cart scope");
        if (!CartLegPace.walkingReference(wood, true, -1).equals("Bob_Walk")
            || !CartLegPace.walkingReference(wood, false, 0).equals("Bob_Walk")
            || !CartLegPace.walkingReference(wood, false, 1).equals("Bob_Walk"))
            throw new AssertionError("fast, forward and idle references must stay unchanged");
        AnimationClip back = clips.get("back");
        for (float amount : new float[]{.44f, .72f, 1}) for (int degree : new int[]{135, 150, 180, 210, 225}) {
            float x = amount * (float) Math.sin(Math.toRadians(degree));
            float y = amount * (float) Math.cos(Math.toRadians(degree));
            double expected = 1.04 * .590551 / (2f / 3) * Math.hypot(x, y);
            float pace = CartLegPace.scale(node, back, x, y, 1.04f, clips::get);
            close(blendedSpeed(node, clips, x, y) * pace, expected,
                "backward and diagonal budgets keep the native WalkSpeed magnitude once");
            close(CartLegPace.targetSpeed(node, back, back, 1, (float) Math.hypot(x, y), 1.04f), expected,
                "Sprint settling and ordinary walking share the backward speed target");
        }
        close(CartLegPace.scale(node, back, 0, 0, 1.04f, clips::get), 1.04, "idle backward pace keeps the existing fallback");
        close(CartLegPace.targetSpeed(node, back, back, 1, 0, 1.04f), 0, "idle backward target is zero");
        close(CartLegPace.scale(node, null, 0, -1, 1.04f, clips::get), 1.04, "missing backward reference keeps the existing pace");
        if (!Float.isNaN(CartLegPace.targetSpeed(node, null, null, 1, 1, 1.04f)))
            throw new AssertionError("missing backward calibration must preserve the existing target fallback");
    }

    public static void main(String[] args) throws Exception {
        nativePelvisBinding();
        brakeTracks();
        AnimNode node = node();
        Map<String, AnimationClip> clips = new HashMap<>();
        clips.put("idle", clip("idle", 1, 0, 0, "Translation_Data"));
        clips.put("forward", clip("forward", 1, 0, 2, "Translation_Data"));
        clips.put("right", clip("right", 2, 2, 0, "Translation_Data"));
        clips.put("left", clip("left", 1, -1, 0, "Translation_Data"));
        clips.put("back", clip("back", 1, 0, -0.5f, "Translation_Data"));
        AnimationClip forward = clips.get("forward");
        var owned = List.of(live("ToolkitCartPivotWalk", true, forward),
            live("ToolkitCartPivotRun", true, forward), live("ToolkitCartPivotSprint", true, forward));
        var untouched = List.of(live("ToolkitCartPivotWalk", false, forward),
            live("defaultWalk", true, forward), live("ToolkitCartPivotWalkOther", true, forward));
        var all = new java.util.ArrayList<>(owned); all.addAll(untouched);
        for (var current : owned) {
            CartLegPace.applyTracks(all, 2.08f, current.getName());
            for (var live : all) {
                var track = live.getMainAnimationTrackAt(0);
                close(track.getSpeedDelta(), live == current ? 2.08 : 1.1,
                    "only the current active gait changes pace");
                close(track.getCurrentTimeValue(), .25, "pace update must not reset phase");
                close(track.getBlendWeight(), .3, "pace update must not change blend weights");
                track.setSpeedDelta(1.1f);
            }
        }
        // The hook precedes native active-flag refresh: outgoing is still active here.
        var walkTrack = owned.get(0).getMainAnimationTrackAt(0);
        var runTrack = owned.get(1).getMainAnimationTrackAt(0);
        walkTrack.setSpeedDelta(1.04f); runTrack.setSpeedDelta(.57f);
        CartLegPace.applyTracks(owned, .57f, "ToolkitCartPivotRun");
        close(walkTrack.getSpeedDelta(), 1.04, "Walk->Run preserves outgoing walking budget");
        close(runTrack.getSpeedDelta(), .57, "Walk->Run keeps incoming running budget");
        CartLegPace.applyTracks(owned, 1.04f, "ToolkitCartPivotWalk");
        close(runTrack.getSpeedDelta(), .57, "Run->Walk preserves outgoing running budget");
        close(walkTrack.getSpeedDelta(), 1.04, "Run->Walk keeps incoming walking budget");
        CartLegPace.applyTracks(owned, .96f, "ToolkitCartPivotSprint");
        close(runTrack.getSpeedDelta(), .57, "Run->Sprint preserves outgoing running budget");
        close(owned.get(2).getMainAnimationTrackAt(0).getSpeedDelta(), .96, "incoming sprint budget");
        var walkNode = live("ToolkitCartPivotWalk", true, forward);
        var runNode = live("ToolkitCartPivotRun", true, forward);
        var sprintNode = live("ToolkitCartPivotSprint", true, forward);
        var unrelated = live("defaultRun", true, forward);
        var upperBody = live("ToolkitCartRunRight", true, forward);
        close(CartLegPace.woodenGaitShift(List.of(walkNode, unrelated, upperBody)), 0,
            "walk and unrelated/upper-body tracks do not shift the running pose");
        for (float blend : new float[]{.2f, .8f}) {
            runNode.getMainAnimationTrackAt(0).setBlendWeight(blend);
            close(CartLegPace.woodenGaitShift(List.of(walkNode, runNode, upperBody)), -.12 * blend,
                "walking->running uses actual track weights");
        }
        runNode.setActive(false);
        sprintNode.getMainAnimationTrackAt(0).setBlendWeight(.2f);
        close(CartLegPace.woodenGaitShift(List.of(runNode, sprintNode)), -.106,
            "run->sprint weights the distinct incoming and inactive outgoing offsets");
        runNode.getMainAnimationTrackAt(0).setBlendWeight(.3f);
        close(CartLegPace.woodenGaitShift(List.of(walkNode, runNode)), -.036,
            "running->walking keeps the outgoing running pose during fade-out");
        var second = AnimationTrack.alloc(); second.startClip(forward, true, 0); second.setBlendWeight(.4f);
        runNode.addMainTrack(second);
        close(CartLegPace.woodenGaitShift(List.of(runNode)), -.084, "all main track weights contribute");
        sprintNode.getMainAnimationTrackAt(0).setBlendWeight(.8f);
        close(CartLegPace.woodenGaitShift(List.of(runNode, sprintNode)), -.12,
            "gait shift clamps at the running offset");
        for (float invalid : new float[]{Float.NaN, Float.POSITIVE_INFINITY, -.2f}) {
            runNode.getMainAnimationTrackAt(0).setBlendWeight(invalid);
            close(CartLegPace.woodenGaitShift(List.of(runNode)), -.048, "invalid track weights are ignored");
        }
        second.setBlendWeight(0);
        runNode.getMainAnimationTrackAt(0).setBlendWeight(1);
        sprintNode.getMainAnimationTrackAt(0).setBlendWeight(1);
        close(CartLegPace.woodenGaitShift(List.of(runNode)), -.12, "full running clearance stays unchanged");
        close(CartLegPace.woodenGaitShift(List.of(sprintNode)), -.05, "full sprint has its own clearance");
        runNode.getMainAnimationTrackAt(0).setBlendWeight(.25f);
        sprintNode.getMainAnimationTrackAt(0).setBlendWeight(.75f);
        close(CartLegPace.woodenGaitShift(List.of(runNode, sprintNode)), -.0675, "mostly sprint transition");
        runNode.getMainAnimationTrackAt(0).setBlendWeight(.75f);
        sprintNode.getMainAnimationTrackAt(0).setBlendWeight(.25f);
        close(CartLegPace.woodenGaitShift(List.of(runNode, sprintNode)), -.1025, "mostly running transition");
        close(CartLegPace.woodenGaitShift((zombie.characters.IsoPlayer) null), 0, "missing running player");
        close(CartLegPace.woodenBodyShift(0,-4.6785715e-7f,.0109462375f),0,"idle stance is unchanged");
        close(CartLegPace.woodenBodyShift(-.12f,0,-.06f),-.12,"existing sufficient Run clearance is preserved");
        close(CartLegPace.woodenBodyShift(0,0,-.03f),-.06594764,"pelvis advance retains clothing clearance after Run fades");
        close(CartLegPace.woodenBodyShift(-.01f,.01f,-.02f),-.08594764,"lateral pelvis drift cannot enter a fixed shaft");
        close(CartLegPace.woodenBodyShift(0,1,-1),-.24,"extreme pose clearance is bounded");
        for(float invalid:new float[]{Float.NaN,Float.POSITIVE_INFINITY,Float.NEGATIVE_INFINITY}) {
            close(CartLegPace.woodenBodyShift(-.05f,invalid,0),-.05,"invalid lateral pose keeps gait fallback");
            close(CartLegPace.woodenBodyShift(-.05f,0,invalid),-.05,"invalid forward pose keeps gait fallback");
        }
        float lastShift=0;
        for(int i=0;i<=1000;i++) {
            float z=.0109462375f-i*.000001f;
            float shift=CartLegPace.woodenBodyShift(0,-4.6785715e-7f,z);
            if(shift>lastShift+1e-7f || Math.abs(shift-lastShift)>.00001f)
                throw new AssertionError("pelvis clearance must enter continuously without reversing");
            lastShift=shift;
        }
        close(CartLegPace.runningWeight(List.of(walkNode, sprintNode, unrelated, upperBody)), 0,
            "head correction ignores walking, sprinting and upper-body tracks");
        for (float blend : new float[]{.2f, .8f}) {
            runNode.getMainAnimationTrackAt(0).setBlendWeight(blend);
            close(CartLegPace.runningWeight(List.of(runNode, sprintNode)), blend,
                "Run correction follows actual weight, including inactive fade-out");
        }
        second.setBlendWeight(.4f);
        close(CartLegPace.runningWeight(List.of(runNode)), 1, "Run correction sums main tracks and clamps at one");
        for (float invalid : new float[]{Float.NaN, Float.POSITIVE_INFINITY, -.2f}) {
            runNode.getMainAnimationTrackAt(0).setBlendWeight(invalid);
            close(CartLegPace.runningWeight(List.of(runNode)), .4, "Run correction ignores invalid weights");
        }
        close(CartLegPace.runningWeight((zombie.characters.IsoGameCharacter) null), 0, "missing head-correction character");
        for (float base : new float[]{1.04f, 1.0f}) {
            for (float loadPace : new float[]{1.0f, 0.8f, 0.4f}) {
                close(CartLegPace.scale(node, forward, 0, loadPace, base, clips::get), base,
                      "forward pace must stay unchanged at " + loadPace);
                close(CartLegPace.scale(node, forward, loadPace, 0, base, clips::get), base * 2,
                      "slower lateral clip must retain the existing load slowdown once");
                close(CartLegPace.scale(node, forward, -loadPace, 0, base, clips::get), base * 2,
                      "left strafe compensation");
            }
            close(CartLegPace.scale(node, forward, 0.4f, 0.4f, base, clips::get),
                  base * 2 * Math.hypot(0.4, 0.4) / Math.hypot(0.4, 0.8),
                  "diagonal compensation uses the blended vector, not a sum of speeds");
            close(CartLegPace.scale(node, forward, 0, -1, base, clips::get), 2.5,
                  "very slow backward clips must respect the pace ceiling");
            close(CartLegPace.scale(node, forward, 0, 0, base, clips::get), base, "idle");
            close(CartLegPace.scale(node, forward, Float.NaN, 0, base, clips::get), base, "invalid intent");
            close(CartLegPace.scale(node, null, 1, 0, base, clips::get), base, "missing reference");
            close(CartLegPace.scale(null, forward, 1, 0, base, clips::get), base, "missing node");
        }
        // Root translations read from the loaded B42.21 clips by ProbePace.
        var nativeClips = Map.of(
            "idle", clip("idle", 2f / 3, 0, 0, "Translation_Data"),
            "forward", clip("forward", 2f / 3, 0, .944882f, "Translation_Data"),
            "right", clip("right", 2f / 3, -.417323f, 0, "Translation_Data"),
            "left", clip("left", 2f / 3, .417323f, 0, "Translation_Data"),
            "back", clip("back", 2f / 3, 0, -.590551f, "Translation_Data"));
        backwardChecks(node, nativeClips);
        reversalChecks(nativeClips.get("forward"), nativeClips.get("back"));
        for (float amount : new float[]{.44f, .72f, 1}) for (int degree = -180; degree <= 180; degree++) {
            float x = amount * (float) Math.sin(Math.toRadians(degree));
            float y = amount * (float) Math.cos(Math.toRadians(degree));
            float scale = CartLegPace.scale(node, nativeClips.get("forward"), x, y, 1.04f, nativeClips::get);
            double expected = 1.04 * .944882 / (2f / 3) * Math.hypot(x, y);
            float actual = blendedSpeed(node, nativeClips, x, y) * scale;
            if (actual > expected + 1e-5) throw new AssertionError("walking budget exceeded at " + degree);
            if (amount <= .72f) close(actual, expected,
                "cardinal roots retain the measured cart walking budget at " + degree);
        }
        AnimationClip walk = nativeClips.get("forward");
        AnimationClip run = clip("run", 2f / 3, 0, 2.094488f, "Translation_Data");
        AnimationClip sprint = clip("sprint", 2f / 3, 0, 2.755905f, "Translation_Data");
        rampChecks();
        speedChecks(node, walk, run, sprint);
        var runningClips = new HashMap<>(nativeClips);
        runningClips.put("forward", run);
        double walkVelocity = .944882 / (2f / 3), runVelocity = 2.094488 / (2f / 3);
        double previous = Double.POSITIVE_INFINITY;
        // Native calculateBaseSpeed/calculateWalkSpeed counts the held bag in both hands.
        for (float load : new float[]{0, 1}) {
            double modifier = 1 + 2 * (.70 - 1) * (1 + load / 2);
            double walking = 1 - Math.abs(1 - modifier) / 2;
            float running = (float) ((walking - .15) * modifier);
            double expected = 1.04 * (walkVelocity * (1 - running) + runVelocity * running);
            float rate = CartLegPace.runningScale(node, walk, run, running, 0, 1, 1.04f, runningClips::get);
            double actual = blendedSpeed(node, runningClips, 0, 1) * rate;
            close((float) actual, expected, "wooden running keeps the native walk->run budget at load " + load);
            if (actual <= 1.04 * walkVelocity * walking)
                throw new AssertionError("running must be faster than walking at load " + load);
            if (actual >= previous) throw new AssertionError("cargo must still slow running");
            previous = actual;
            for (int degree = -180; degree <= 180; degree++) {
                float x = (float) Math.sin(Math.toRadians(degree)), y = (float) Math.cos(Math.toRadians(degree));
                rate = CartLegPace.runningScale(node, walk, run, running, x, y, 1.04f, runningClips::get);
                actual = blendedSpeed(node, runningClips, x, y) * rate;
                if (actual > expected + 1e-5) throw new AssertionError("running direction exceeded native budget");
                if (y > .8) close((float) actual, expected, "forward turns retain running speed");
            }
        }
        close(CartLegPace.runningScale(node, walk, run, 0, 0, 1, 1.04f, runningClips::get),
            1.04 * walkVelocity / runVelocity, "zero run scalar blends to walking, not idle");
        close(CartLegPace.runningScale(node, walk, run, -1, 0, 1, 1.04f, runningClips::get),
            1.04 * walkVelocity / runVelocity, "negative native scalar clamps to walking");
        close(CartLegPace.runningScale(node, walk, run, 2, 0, 1, 1.04f, runningClips::get),
            1.04, "native scalar clamps to full running");
        runningClips.put("forward", sprint);
        close(CartLegPace.runningScale(node, run, sprint, 0, 0, 1, .96f, runningClips::get),
            .96 * 2.094488 / 2.755905, "low sprint scalar keeps native running floor");
        close(CartLegPace.runningScale(node, run, sprint, 1, 0, 1, .96f, runningClips::get),
            .96, "full native sprint pace");
        close(CartLegPace.runningScale(node, run, sprint, Float.NaN, 0, 1, .96f, runningClips::get),
            .96, "invalid native speed");
        close(CartLegPace.runningScale(node, null, sprint, 1, 0, 1, .96f, runningClips::get),
            .96, "missing slow gait");
        clips.remove("right");
        close(CartLegPace.scale(node, forward, 1, 0, 1.04f, clips::get), 1.04, "missing clip");
        for (AnimationClip invalid : List.of(
                clip("zero duration", 0, 1, 0, "Translation_Data"),
                clip("invalid translation", 1, Float.NaN, 0, "Translation_Data"),
                clip("missing root", 1, 1, 0, "OtherBone"),
                clip("no movement", 1, 0, 0, "Translation_Data"))) {
            clips.put("right", invalid);
            close(CartLegPace.scale(node, forward, 1, 0, 1.04f, clips::get), 1.04, invalid.name);
            close(CartLegPace.scale(node, forward, 1, 0, 1.04f, clips::get), 1.04, "cached " + invalid.name);
        }
        close(forward.getKeyframe(1).position.z, -2, "shared root frames stay unchanged");
        close(forward.getDuration(), 1, "shared clip duration stays unchanged");
        close(CartLegPace.scale(null, 1, 0), 1.04, "missing player");
        System.out.println("CART_LEG_PACE_PASS (native picker, root velocity, outgoing cadence/reversal, Sprint ramp, load, FPS, invalid clips)");
    }
}
