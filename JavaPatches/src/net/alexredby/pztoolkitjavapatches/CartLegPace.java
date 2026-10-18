package net.alexredby.pztoolkitjavapatches;

import java.util.Objects;
import java.util.WeakHashMap;
import java.util.function.Function;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.ModelManager;
import zombie.core.skinnedmodel.advancedanimation.AnimNode;
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlendPicker.PickResults;
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode;
import zombie.core.skinnedmodel.animation.AnimationClip;
import zombie.core.skinnedmodel.animation.AnimationTrack;
import zombie.core.skinnedmodel.animation.BoneAxis;
import zombie.iso.Vector2;

/** Game-thread compensation for directional clips with different root-motion speeds. */
public final class CartLegPace {
    private record Velocity(String bone, BoneAxis axis, double x, double y) {}
    // Native getTotalTranslation builds a frame list; clips are immutable after loading.
    private static final WeakHashMap<AnimationClip, Velocity> velocities = new WeakHashMap<>();
    private static final PickResults picks = new PickResults();
    private static final Vector2 translation = new Vector2();
    static final class Ramp {
        double speed, velocity;

        void reset(double target) {
            speed = Double.isFinite(target) ? Math.max(0, target) : 0;
            velocity = 0;
        }

        double update(double target, double seconds, double load) {
            return update(target, seconds, load, false);
        }

        double update(double target, double seconds, double load, boolean coasting) {
            if (!Double.isFinite(speed) || !Double.isFinite(velocity)) reset(target);
            if (!Double.isFinite(target) || target < 0 || !Double.isFinite(seconds) || seconds <= 0)
                return speed;
            double dt = Math.min(.1, seconds);
            load = Double.isFinite(load) ? Math.max(0, Math.min(1, load)) : 0;
            double frequency = 1 / (target > speed ? .13 + .09 * load
                : coasting ? .22 + .16 * load : .04 + .02 * load);
            double previous = speed, offset = speed - target;
            double rate = velocity + frequency * offset, decay = Math.exp(-frequency * dt);
            speed = target + (offset + rate * dt) * decay;
            velocity = (velocity - frequency * rate * dt) * decay;
            double bounded = Math.max(Math.min(previous, target), Math.min(Math.max(previous, target), speed));
            // Releasing Sprint must brake immediately, even while the spring was accelerating.
            if (bounded != speed) { speed = bounded; velocity = 0; }
            return speed;
        }

        boolean settled(double target) {
            return Double.isFinite(target) && Math.abs(speed - target) < 1e-3 && Math.abs(velocity) < 1e-2;
        }
    }

    /** XML reads the variable at track creation; existing tracks need their rate updated. */
    public static void apply(IsoPlayer player, float pace) {
        if (player == null || !Float.isFinite(pace) || pace < 0) return;
        player.setVariable("ToolkitCartLegPace", pace);
        var animator = player.getAdvancedAnimator();
        if (animator != null && animator.getRootLayer() != null)
            applyTracks(animator.getRootLayer().getLiveAnimNodes(), pace,
                player.isSprinting() ? "ToolkitCartPivotSprint"
                    : player.isRunning() ? "ToolkitCartPivotRun" : "ToolkitCartPivotWalk");
    }

    static void applyTracks(Iterable<LiveAnimNode> nodes, float pace, String currentGait) {
        for (var node : nodes) {
            if (!node.isActive()) continue;
            // At postUpdateAnimating entry the outgoing gait can still be active.
            if (!currentGait.equals(node.getName())) continue;
            for (var track : node.getMainAnimationTracks()) track.setSpeedDelta(pace);
        }
    }

    /** Native requested root speed, before directional compensation or a Sprint ramp. */
    public static float targetSpeed(IsoPlayer player, float stepX, float stepY) {
        double amount = Math.hypot(stepX, stepY);
        if (!Double.isFinite(amount)) return Float.NaN;
        if (amount < 1e-6) return 0;
        AnimNode node = pivotNode(player);
        if (node == null) return Float.NaN;
        boolean sprint = player.isSprinting(), run = player.isRunning();
        var cart = player.getPrimaryHandItem();
        String walk = walkingReference(cart == null ? null : cart.getFullType(), sprint || run, stepY);
        String mode = sprint ? "Sprint" : run ? "Run" : "Walk";
        float blend = player.getVariableFloat("WalkSpeed", 0);
        if (sprint) blend = Math.max(0, (blend - .5f) * 2);
        return targetSpeed(node, clip(sprint ? "Bob_Run" : walk), clip(sprint || run ? "Bob_" + mode : walk),
            run || sprint ? blend : 1, run || sprint ? 1 : (float) amount, sprint ? .96f : 1.04f);
    }

    static String walkingReference(String cartType, boolean fast, float stepY) {
        return !fast && stepY < 0 && "SaucedWheelbarrow.WheelbarrowWood".equals(cartType)
            ? "Bob_WalkBwdNoAim1Hand" : "Bob_Walk";
    }

    static float targetSpeed(AnimNode node, AnimationClip slow, AnimationClip fast,
                             float blend, float amount, float base) {
        if (node == null || slow == null || fast == null || !Float.isFinite(blend)
            || !Float.isFinite(amount) || amount < 0 || !Float.isFinite(base) || base < 0) return Float.NaN;
        Velocity low = velocity(slow, node.getDeferredBoneName(), node.getDeferredBoneAxis());
        Velocity high = velocity(fast, node.getDeferredBoneName(), node.getDeferredBoneAxis());
        if (low == null || high == null) return Float.NaN;
        double weight = Math.max(0, Math.min(1, blend));
        return (float) (base * amount * (Math.hypot(low.x, low.y) * (1 - weight)
            + Math.hypot(high.x, high.y) * weight));
    }

    /** Cadence changes the native extracted movement budget; movement must not scale it again. */
    public static void applySpeed(IsoPlayer player, float speed, float stepX, float stepY) {
        if (player == null) return;
        if (!Float.isFinite(speed) || speed < 0) { apply(player, scale(player, stepX, stepY)); return; }
        AnimNode incoming = pivotNode(player);
        float current = blendedSpeed(incoming, stepX, stepY, CartLegPace::clip);
        float pace = speed == 0 ? 0 : current > 1e-6 ? Math.min(2.5f, speed / current)
            : scale(player, stepX, stepY);
        player.setVariable("ToolkitCartLegPace", pace);
        var animator = player.getAdvancedAnimator();
        if (animator != null && animator.getRootLayer() != null) {
            String currentGait = incoming != null && Math.hypot(stepX, stepY) >= 1e-6 ? incoming.name : null;
            applySpeedTracks(animator.getRootLayer().getLiveAnimNodes(), speed, currentGait, pace, stepY);
        }
    }

    static float brace(IsoPlayer player,float target,float stepX,float stepY,double amount,boolean blocked) {
        float radius=(float)(1-amount*amount*(3-2*amount));
        stepX*=radius;stepY*=radius;
        player.setVariable("ToolkitCartStepX",stepX);
        player.setVariable("ToolkitCartStepY",stepY);
        float speed=blocked?0:target*radius;
        applySpeed(player,speed,stepX,stepY);
        return speed;
    }

    static void applySpeedTracks(Iterable<LiveAnimNode> nodes, float speed, String currentGait, float currentPace, float stepY) {
        for (var node : nodes) {
            String name = node.getName();
            if (!"ToolkitCartPivotWalk".equals(name) && !"ToolkitCartPivotRun".equals(name)
                && !"ToolkitCartPivotSprint".equals(name)) continue;
            // Native refreshes the current gait's directional weights after this hook.
            if (name.equals(currentGait)) {
                for (var track : node.getMainAnimationTracks()) track.setSpeedDelta(currentPace);
                continue;
            }
            double x = 0, y = 0;
            boolean valid = true;
            for (var track : node.getMainAnimationTracks()) {
                float weight = track.getBlendFieldWeight();
                if (!Float.isFinite(weight)) { valid = false; break; }
                if (weight < 1e-4f) continue;
                Velocity root = velocity(track.getClip(), node.getDeferredBoneName(), node.getDeferredBoneAxis());
                if (root == null) { valid = false; break; }
                x += Math.min(1, weight) * root.x; y += Math.min(1, weight) * root.y;
            }
            double current = Math.hypot(x, y);
            if (speed != 0 && (!valid || current < 1e-6)) continue;
            // Inactive nodes retain their old field weights through a direction change.
            float pace = speed == 0 || y * stepY < -1e-6 ? 0 : (float) Math.min(2.5, speed / current);
            for (var track : node.getMainAnimationTracks()) track.setSpeedDelta(pace);
        }
    }

    private static AnimNode pivotNode(IsoPlayer player) {
        if (player == null) return null;
        var animator = player.getAdvancedAnimator();
        if (animator == null || animator.animSet == null) return null;
        boolean sprint = player.isSprinting(), run = player.isRunning();
        var state = animator.animSet.states.get(sprint ? "sprint" : run ? "run" : "movement");
        if (state == null) return null;
        String name = "ToolkitCartPivot" + (sprint ? "Sprint" : run ? "Run" : "Walk");
        for (var node : state.nodes) if (name.equals(node.name)) return node;
        return null;
    }

    private static AnimationTrack brakeTrack(LiveAnimNode node) {
        if(!"ToolkitCartIdle".equals(node.getName()) || !node.isTransitioningIn()) return null;
        var track=node.getTransitionInTrack();
        if(track==null) return null;
        return switch(track.getName()) {
            case "Bob_RunToStop2H_Heavy", "Bob_SprintToStop2h_Heavy" -> track;
            default -> null;
        };
    }

    static AnimationTrack brakeTrack(IsoPlayer player) {
        var animator=player.getAdvancedAnimator();
        if(animator!=null && animator.getRootLayer()!=null)
            for(var node:animator.getRootLayer().getLiveAnimNodes()) {
                var track=brakeTrack(node);
                if(track!=null) return track;
            }
        return null;
    }

    static void cancelBrake(IsoPlayer player, boolean hard) {
        var animator=player.getAdvancedAnimator();
        if(animator==null || animator.getRootLayer()==null) return;
        for(var node:animator.getRootLayer().getLiveAnimNodes()) {
            var track=brakeTrack(node);
            if(track==null) continue;
            // Stop translation independently of the pose's native fade when a collision interrupts it.
            track.setUseDeferredMovement(false);
            if(hard) node.stopTransitionIn();
        }
    }

    /** Model-Z grip clearance follows each native gait, including outgoing tracks. */
    public static float woodenGaitShift(IsoPlayer player) {
        if (player == null) return 0;
        float side=Math.min(woodenSideShift(player),CartSteeringHooks.sideClearance(player));
        // Bank and Strafe provide the same shaft clearance; do not stack their advances.
        side=Math.min(0,side-CartSteeringMath.woodenShift((float)CartSteeringHooks.clearanceLean(player),0));
        return Math.min(woodenFastShift(player),side);
    }

    static float woodenFastShift(IsoPlayer player) {
        var animator = player.getAdvancedAnimator();
        float gait=animator == null || animator.getRootLayer() == null ? 0
            : woodenGaitShift(animator.getRootLayer().getLiveAnimNodes());
        float weight=gait<0 || player.isRunning() || player.isSprinting()?1:CartSteeringHooks.fastPoseWeight(player);
        if(weight==0) return gait;
        if(!player.hasAnimationPlayer()) return gait;
        var animation=player.getAnimationPlayer();
        if(animation==null || !animation.hasSkinningData()) return gait;
        Integer spine=animation.getSkinningData().boneIndices.get("Bip01_Spine");
        if(spine==null || spine<0 || spine>=animation.getModelTransformsCount()) return gait;
        var pose=animation.getModelTransformAt(spine);
        // AnimationPlayer stores the model pose transposed, as in the native render palette.
        return pose==null?gait:gait+weight*(woodenBodyShift(gait,pose.m03,pose.m23)-gait);
    }

    static float woodenSideShift(IsoPlayer player) {
        var animator=player.getAdvancedAnimator();
        return animator==null || animator.getRootLayer()==null?0
            : woodenSideShift(animator.getRootLayer().getLiveAnimNodes());
    }

    static float woodenSideShift(Iterable<LiveAnimNode> nodes) {
        double weight=0;
        for(var node:nodes) if("ToolkitCartPivotWalk".equals(node.getName()))
            for(var track:node.getMainAnimationTracks()) {
                if(!"Bob_StrafeNoAim_Left".equals(track.getName()) && !"Bob_StrafeNoAim_Right".equals(track.getName())) continue;
                float blend=track.getBlendWeight();
                if(Float.isFinite(blend) && blend>0) weight+=blend;
            }
        float t=(float)Math.min(1,weight/.2);
        // shortcut: B42 Strafe/backward blend needs 8.5 cm of shaft clearance; recalibrate for another rig/clip.
        return -.085f*t*t*(3-2*t);
    }

    static float releaseSideShift(float current,float target,double seconds) {
        if(!Double.isFinite(seconds) || seconds<=0) return Math.min(current,target);
        float released=current*(float)Math.exp(-Math.min(.1,seconds)/.15);
        return Math.min(target,released<-.0001f?released:0);
    }

    static float woodenBodyShift(float gait, float x, float z) {
        if(!Float.isFinite(x) || !Float.isFinite(z)) return gait;
        // shortcut: B42 idle pelvis and shaft clearance; recalibrate this envelope for another rig/stance.
        float body=z-.0109462375f-3*Math.abs(x+4.6785715e-7f);
        float intrusion=Math.max(0,gait-body),t=Math.min(1,intrusion/.005f);
        // Keep clothing clear as the native pelvis moves across the handles during a gait handoff.
        return Math.max(-.24f,Math.min(gait,body-.025f*t*t*(3-2*t)));
    }

    static float woodenGaitShift(Iterable<LiveAnimNode> nodes) {
        double shift = 0;
        for (var node : nodes) {
            float offset;
            if ("ToolkitCartPivotRun".equals(node.getName())) offset = -.12f;
            else if ("ToolkitCartPivotSprint".equals(node.getName())) offset = -.05f;
            else offset=0;
            if(offset!=0) for (var track : node.getMainAnimationTracks()) {
                float blend = track.getBlendWeight();
                if (Float.isFinite(blend) && blend > 0) shift += offset * blend;
            }
        }
        return (float) Math.max(-.12, shift);
    }

    /** Visual correction follows the rendered Run tracks through their fade-out. */
    public static float runningWeight(IsoGameCharacter character) {
        if (character == null) return 0;
        var animator = character.getAdvancedAnimator();
        return animator == null || animator.getRootLayer() == null ? 0
            : runningWeight(animator.getRootLayer().getLiveAnimNodes());
    }

    static float runningWeight(Iterable<LiveAnimNode> nodes) {
        double weight = 0;
        for (var node : nodes) {
            if (!"ToolkitCartPivotRun".equals(node.getName())) continue;
            for (var track : node.getMainAnimationTracks()) {
                float blend = track.getBlendWeight();
                if (Float.isFinite(blend) && blend > 0) weight += blend;
            }
        }
        return (float) Math.min(1, weight);
    }

    /** Walk magnitude includes slowdown; running uses the native Walk->Run speed blend. */
    public static float scale(IsoPlayer player, float stepX, float stepY) {
        boolean sprint = player != null && player.isSprinting();
        boolean run = player != null && player.isRunning();
        float base = sprint ? .96f : 1.04f;
        if (player == null) return base;
        AnimNode node = pivotNode(player);
        if (node == null) return base;
        String mode = sprint ? "Sprint" : run ? "Run" : "Walk";
        if (sprint || run) {
            float speed = player.getVariableFloat("WalkSpeed", 0);
            // Native defaultSprint blends Run->Sprint only above WalkSpeed=.5.
            if (sprint) speed = Math.max(0, (speed - .5f) * 2);
            return runningScale(node, clip(sprint ? "Bob_Run" : "Bob_Walk"),
                clip("Bob_" + mode), speed, stepX, stepY, base, CartLegPace::clip);
        }
        var cart = player.getPrimaryHandItem();
        return scale(node, clip(walkingReference(cart == null ? null : cart.getFullType(), false, stepY)),
            stepX, stepY, base, CartLegPace::clip);
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
        return compensate(node, Math.hypot(reference.x, reference.y) * amount,
            stepX, stepY, base, clips);
    }

    static float runningScale(AnimNode node, AnimationClip slow, AnimationClip fast, float speed,
                              float stepX, float stepY, float base,
                              Function<String, AnimationClip> clips) {
        if (node == null || slow == null || fast == null || !Float.isFinite(speed)) return base;
        Velocity low = velocity(slow, node.getDeferredBoneName(), node.getDeferredBoneAxis());
        Velocity high = velocity(fast, node.getDeferredBoneName(), node.getDeferredBoneAxis());
        if (low == null || high == null) return base;
        double blend = Math.max(0, Math.min(1, speed));
        double desired = Math.hypot(low.x, low.y) * (1 - blend) + Math.hypot(high.x, high.y) * blend;
        return compensate(node, desired, stepX, stepY, base, clips);
    }

    private static float compensate(AnimNode node, double desired, float stepX, float stepY,
                                    float base, Function<String, AnimationClip> clips) {
        float current = blendedSpeed(node, stepX, stepY, clips);
        if (!(current > 1e-6) || !(desired > 0)) return base;
        return (float) Math.min(2.5, base * desired / current);
    }

    private static float blendedSpeed(AnimNode node, float stepX, float stepY,
                                      Function<String, AnimationClip> clips) {
        if (node == null || !Float.isFinite(stepX) || !Float.isFinite(stepY) || Math.hypot(stepX, stepY) < 1e-6
            || node.blend2dPicker == null || node.blendTris == null || node.blendTris.isEmpty()) return Float.NaN;
        node.blend2dPicker.Pick(stepX, stepY, picks);
        if (picks.numNodes < 1 || picks.numNodes > 3) return Float.NaN;
        double x = 0, y = 0;
        for (int i = 0; i < picks.numNodes; i++) {
            var blend = i == 0 ? picks.node1 : i == 1 ? picks.node2 : picks.node3;
            float weight = i == 0 ? picks.scale1 : i == 1 ? picks.scale2 : picks.scale3;
            if (!Float.isFinite(weight)) return Float.NaN;
            // Match AnimLayer.applyBlendField's cutoff, including edge rounding.
            weight = weight < 1e-4f ? 0 : Math.min(1, weight);
            if (weight == 0) continue;
            if (blend == null) return Float.NaN;
            AnimationClip clip = clips.apply(blend.animName);
            if (clip == null) return Float.NaN;
            Velocity velocity = velocity(clip, node.getDeferredBoneName(), node.getDeferredBoneAxis());
            if (velocity == null) return Float.NaN;
            x += weight * velocity.x; y += weight * velocity.y;
        }
        return (float) Math.hypot(x, y);
    }

    private static Velocity velocity(AnimationClip clip, String bone, BoneAxis axis) {
        if (clip == null) return null;
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
