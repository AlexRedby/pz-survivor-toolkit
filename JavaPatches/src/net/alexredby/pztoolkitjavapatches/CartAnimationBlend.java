package net.alexredby.pztoolkitjavapatches;

import java.util.Collections;
import java.util.ArrayList;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Set;
import java.util.function.Predicate;
import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator;
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode;
import zombie.core.skinnedmodel.animation.AnimationTrack;
import zombie.core.skinnedmodel.animation.LiveAnimationTrackEntries;
import zombie.core.skinnedmodel.model.SkinningBone;

/** Conservative fast-pose presence along the displayed Spine's native transform chain. */
final class CartAnimationBlend {
    private static final float MIN_WEIGHT=.001f;
    private static final ThreadLocal<LiveAnimationTrackEntries> entries=
        ThreadLocal.withInitial(LiveAnimationTrackEntries::new);

    static float fastWeight(IsoPlayer player) {
        if(player==null) return 0;
        var animator=player.getAdvancedAnimator();
        if(animator==null) return 0;
        var fast=fastTracks(animator);
        if(fast.isEmpty()) return 0;
        if(player.hasAnimationPlayer()) {
            var animation=player.getAnimationPlayer();
            if(animation!=null && animation.hasSkinningData()) {
                var spine=animation.getSkinningData().boneIndices.get("Bip01_Spine");
                if(spine!=null && spine>=0 && spine<animation.getModelTransformsCount()
                    && animation.getMultiTrack()!=null) {
                    float weight=fastWeight(animation.getMultiTrack().getTracks(),
                        animation.getSkinningData().getBoneAt(spine),fast::contains);
                    if(Float.isFinite(weight)) return weight;
                }
            }
        }
        // Missing native tracks/skeleton cannot prove retirement. Use conservative
        // raw ownership of the same identified root and masked fast tracks.
        double raw=0;
        for(var track:fast) {
            float weight=track.getBlendWeight();
            if(Float.isFinite(weight) && weight>0) raw+=weight;
        }
        return (float)Math.min(1,raw);
    }

    /**
     * Model-space Spine still contains an outgoing pelvis/root transform after
     * an incoming masked Walk completely owns the local Spine. Keep the largest
     * native fast share along that chain until every contributor has retired.
     * This is presence, not a summed pose weight or a geometric clearance bound.
     */
    static float fastWeight(List<AnimationTrack> tracks,SkinningBone spine,Predicate<AnimationTrack> fast) {
        if(spine==null) return Float.NaN;
        float weight=0;
        for(var bone=spine;bone!=null;bone=bone.parent) {
            float local=fastWeight(tracks,bone.index,fast);
            if(!Float.isFinite(local)) return Float.NaN;
            weight=Math.max(weight,local);
        }
        return weight;
    }

    static Set<AnimationTrack> fastTracks(AdvancedAnimator animator) {
        var nodes=new ArrayList<LiveAnimNode>();
        if(animator.getRootLayer()!=null) nodes.addAll(animator.getRootLayer().getLiveAnimNodes());
        // Both masked hand layers can own the entire Spine while the root Run is
        // still live. Classifying only root identities incorrectly retires clearance.
        for(int i=0;i<animator.getSubLayerCount();i++) {
            var layer=animator.getSubLayerAt(i);
            if(layer!=null) nodes.addAll(layer.getLiveAnimNodes());
        }
        Set<AnimationTrack> fast=Collections.newSetFromMap(new IdentityHashMap<>());
        for(var node:nodes) {
            boolean fastNode=switch(node.getName()) {
                case "ToolkitCartPivotRun", "ToolkitCartPivotSprint", "ToolkitWoodCartBraceRun",
                     "ToolkitWoodCartBraceSprint", "ToolkitCartRun", "ToolkitCartSprint",
                     "ToolkitCartRunLeft", "ToolkitCartRunRight", "ToolkitCartSprintLeft",
                     "ToolkitCartSprintRight" -> true;
                default -> false;
            };
            if(fastNode) for(var track:node.getMainAnimationTracks()) fast.add(track);
            boolean transitionOwner=fastNode || switch(node.getName()) {
                case "ToolkitCartIdle", "ToolkitCartIdleLeft", "ToolkitCartIdleRight",
                     "ToolkitCartWalk", "ToolkitCartWalkLeft", "ToolkitCartWalkRight",
                     "ToolkitCartPivotWalk", "ToolkitWoodCartPivotWalk" -> true;
                default -> false;
            };
            var transition=node.getTransitionInTrack();
            if(transitionOwner && transition!=null) {
                String name=transition.getName();
                if(CartLegPace.brakeClip(name) || "Bob_Cart_WalkToRun".equals(name)
                    || "Bob_Cart_WalkToSprint".equals(name)) fast.add(transition);
            }
        }
        // The shared upper brace is identical in Walk and fast gaits. Promoting
        // its full weight while any outgoing fast track remains would pin the
        // reserve to one, then snap it to zero. The ancestor chain already sees
        // the actual outgoing root/pelvis underneath the brace's Spine mask.
        return fast;
    }

    /**
     * The caller supplies a valid skeleton bone index. Returns NaN when native
     * allocation cannot be established. Non-fast tracks
     * still consume the same bone's budget; a fast identity absent from tracks is
     * not rendered. Node activity/isPlaying do not replace native blend weights.
     *
     * This matches the normal-frame B42.21 allocator. The private first-frame
     * underweight normalization flag is deliberately not guessed. A Spine-local
     * share does not describe ancestor masks or prove complete geometric clearance.
     */
    static float fastWeight(List<AnimationTrack> tracks,int bone,Predicate<AnimationTrack> fast) {
        if(tracks==null || bone<0 || fast==null) return Float.NaN;
        var scratch=entries.get();
        try {
            for(var track:tracks) {
                if(track==null) return Float.NaN;
                float weight=track.getBlendWeight();
                if(!Float.isFinite(weight) || weight<0 || track.getLayerIdx()<0 || track.getLayerIdx()>=16)
                    return Float.NaN;
                if(weight>=MIN_WEIGHT) {
                    float mask=track.getBoneWeight(bone);
                    if(!Float.isFinite(mask) || mask<0) return Float.NaN;
                }
            }
            scratch.setTracks(tracks,MIN_WEIGHT,false);
            float remaining=1,weight=0;
            for(int i=scratch.count()-1;i>=0 && remaining>MIN_WEIGHT;i--) {
                var entry=scratch.get(i);
                float mask=entry.getTrack().getBoneWeight(bone);
                if(mask<=MIN_WEIGHT) continue;
                float raw=entry.getBlendWeight()*mask;
                if(!Float.isFinite(raw)) return Float.NaN;
                if(raw<=MIN_WEIGHT) continue;
                float effective=Math.max(0,Math.min(remaining,raw));
                remaining=Math.max(0,remaining-raw);
                if(fast.test(entry.getTrack())) weight+=effective;
            }
            return Math.max(0,Math.min(1,weight));
        } catch(IndexOutOfBoundsException unavailableBone) {
            return Float.NaN;
        } finally {
            scratch.clear();
        }
    }

    private CartAnimationBlend() {}
}
