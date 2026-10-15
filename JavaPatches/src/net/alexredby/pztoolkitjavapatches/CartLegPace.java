package net.alexredby.pztoolkitjavapatches;

import java.util.Objects;
import java.util.WeakHashMap;
import java.util.function.Function;
import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.ModelManager;
import zombie.core.skinnedmodel.advancedanimation.AnimNode;
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlendPicker.PickResults;
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode;
import zombie.core.skinnedmodel.animation.AnimationClip;
import zombie.core.skinnedmodel.animation.BoneAxis;
import zombie.iso.Vector2;

/** Game-thread compensation for directional clips with different root-motion speeds. */
public final class CartLegPace {
    private record Velocity(String bone, BoneAxis axis, double x, double y) {}
    // Native getTotalTranslation builds a frame list; clips are immutable after loading.
    private static final WeakHashMap<AnimationClip, Velocity> velocities = new WeakHashMap<>();
    private static final PickResults picks = new PickResults();
    private static final Vector2 translation = new Vector2();

    /** XML reads the variable at track creation; existing tracks need their rate updated. */
    public static void apply(IsoPlayer player, float pace) {
        if (player == null || !Float.isFinite(pace) || pace <= 0) return;
        player.setVariable("ToolkitCartLegPace", pace);
        var animator = player.getAdvancedAnimator();
        if (animator != null && animator.getRootLayer() != null)
            applyTracks(animator.getRootLayer().getLiveAnimNodes(), pace);
    }

    static void applyTracks(Iterable<LiveAnimNode> nodes, float pace) {
        for (var node : nodes) {
            if (!node.isActive()) continue;
            String name = node.getName();
            if (!"ToolkitCartPivotWalk".equals(name) && !"ToolkitCartPivotRun".equals(name)
                && !"ToolkitCartPivotSprint".equals(name)) continue;
            for (var track : node.getMainAnimationTracks()) track.setSpeedDelta(pace);
        }
    }

    /** Absolute playback rate; the input magnitude already includes cargo slowdown. */
    public static float scale(IsoPlayer player, float stepX, float stepY) {
        boolean sprint = player != null && player.isSprinting();
        boolean run = player != null && player.isRunning();
        float base = sprint || run ? 1.0f : 1.04f;
        if (player == null) return base;
        var animator = player.getAdvancedAnimator();
        if (animator == null || animator.animSet == null) return base;
        var state = animator.animSet.states.get(sprint ? "sprint" : run ? "run" : "movement");
        if (state == null) return base;
        String mode = sprint ? "Sprint" : run ? "Run" : "Walk";
        for (var node : state.nodes) {
            if (("ToolkitCartPivot" + mode).equals(node.name))
                return scale(node, clip("Bob_" + mode), stepX, stepY, base, CartLegPace::clip);
        }
        return base;
    }

    private static AnimationClip clip(String name) {
        try {
            return ModelManager.instance.getAnimationClip(name);
        } catch (NullPointerException notLoaded) {
            // ModelManager has no animation mesh while loading or leaving a world.
            return null;
        }
    }

    static float scale(AnimNode node, AnimationClip forward, float stepX, float stepY,
                       float base, Function<String, AnimationClip> clips) {
        double amount = Math.hypot(stepX, stepY);
        if (!Double.isFinite(amount) || amount < 1e-6 || node == null || forward == null
            || node.blend2dPicker == null || node.blendTris == null || node.blendTris.isEmpty()) return base;
        Velocity reference = velocity(forward, node.getDeferredBoneName(), node.getDeferredBoneAxis());
        if (reference == null) return base;
        node.blend2dPicker.Pick(stepX, stepY, picks);
        if (picks.numNodes < 1 || picks.numNodes > 3) return base;
        double x = 0, y = 0;
        for (int i = 0; i < picks.numNodes; i++) {
            var blend = i == 0 ? picks.node1 : i == 1 ? picks.node2 : picks.node3;
            float weight = i == 0 ? picks.scale1 : i == 1 ? picks.scale2 : picks.scale3;
            if (!Float.isFinite(weight)) return base;
            // Match AnimLayer.applyBlendField's cutoff, including edge rounding.
            weight = weight < 1e-4f ? 0 : Math.min(1, weight);
            if (weight == 0) continue;
            if (blend == null) return base;
            AnimationClip clip = clips.apply(blend.animName);
            if (clip == null) return base;
            Velocity velocity = velocity(clip, node.getDeferredBoneName(), node.getDeferredBoneAxis());
            if (velocity == null) return base;
            x += weight * velocity.x; y += weight * velocity.y;
        }
        double current = Math.hypot(x, y);
        double desired = Math.hypot(reference.x, reference.y) * amount;
        if (!(current > 1e-6) || !(desired > 0)) return base;
        return (float) Math.min(2.5, base * desired / current);
    }

    private static Velocity velocity(AnimationClip clip, String bone, BoneAxis axis) {
        Velocity cached = velocities.get(clip);
        if (cached == null || !Objects.equals(cached.bone, bone) || cached.axis != axis) {
            double x = Double.NaN, y = Double.NaN;
            float duration = clip.getDuration();
            if (duration > 0 && Float.isFinite(duration) && bone != null && axis != null) {
                try {
                    clip.getTotalTranslation(bone, axis, translation);
                    x = translation.x / duration; y = translation.y / duration;
                } catch (IndexOutOfBoundsException | NullPointerException invalidRoot) {
                    // Missing root frames cannot provide a safe compensation factor.
                }
            }
            cached = new Velocity(bone, axis, x, y);
            velocities.put(clip, cached);
        }
        return Double.isFinite(cached.x) && Double.isFinite(cached.y) ? cached : null;
    }

    private CartLegPace() {}
}
