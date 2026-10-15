package net.alexredby.pztoolkitjavapatches;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.lwjgl.util.vector.Vector3f;
import zombie.core.skinnedmodel.advancedanimation.AnimNode;
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlend;
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlendPicker;
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlendTriangle;
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode;
import zombie.core.skinnedmodel.animation.AnimationClip;
import zombie.core.skinnedmodel.animation.AnimationTrack;
import zombie.core.skinnedmodel.animation.BoneAxis;
import zombie.core.skinnedmodel.animation.Keyframe;
import zombie.iso.Vector2;

public final class CartLegPaceTest {
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

    public static void main(String[] args) {
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
        CartLegPace.applyTracks(all, 2.08f);
        for (var live : all) {
            var track = live.getMainAnimationTrackAt(0);
            close(track.getSpeedDelta(), owned.contains(live) ? 2.08 : 1.1, "only active owned tracks change pace");
            close(track.getCurrentTimeValue(), .25, "pace update must not reset phase");
            close(track.getBlendWeight(), .3, "pace update must not change blend weights");
        }
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
        System.out.println("CART_LEG_PACE_PASS (native picker, root velocity, direction, load, invalid clips)");
    }
}
