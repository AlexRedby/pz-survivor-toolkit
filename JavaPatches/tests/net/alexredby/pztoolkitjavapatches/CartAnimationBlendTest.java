package net.alexredby.pztoolkitjavapatches;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.lwjgl.util.vector.Matrix4f;
import org.lwjgl.util.vector.Vector3f;
import zombie.core.skinnedmodel.advancedanimation.AnimBoneWeight;
import zombie.core.skinnedmodel.advancedanimation.AnimLayer;
import zombie.core.skinnedmodel.advancedanimation.AnimNode;
import zombie.core.skinnedmodel.advancedanimation.AnimState;
import zombie.core.skinnedmodel.advancedanimation.AnimTransition;
import zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator;
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode;
import zombie.core.skinnedmodel.animation.AnimationClip;
import zombie.core.skinnedmodel.animation.AnimationTrack;
import zombie.core.skinnedmodel.animation.Keyframe;
import zombie.core.skinnedmodel.model.SkinningData;

/** Exercises the real native entry sorter with controlled public track/mask inputs. */
public final class CartAnimationBlendTest {
    private static final SkinningData SKINNING=rig();
    private static SkinningData rig() {
        var identity=new Matrix4f();
        var bones=List.of(identity,identity,identity,identity);
        return new SkinningData(new HashMap<>(),bones,bones,bones,List.of(-1,0,1,2),
            new HashMap<>(Map.of("root",0,"pelvis",1,"waist",2,"Bip01_Spine",3)));
    }
    private static AnimationTrack track(String name,float weight) {return track(name,weight,1,11,0);}
    private static AnimationTrack track(String name,float weight,float boneMask,int priority,int depth) {
        var start=new Keyframe();var end=new Keyframe();
        start.boneName=end.boneName="Bip01_Spine";
        start.position=new Vector3f();end.position=new Vector3f();end.time=1;
        var track=AnimationTrack.alloc();
        track.startClip(new AnimationClip(1,List.of(start,end),name,true),true,0);
        track.priority=priority;track.setBlendWeight(weight);
        mask(track,boneMask);
        if(depth>0) {
            var layer=AnimLayer.alloc(null,null);
            for(int i=0;i<depth;i++) layer=AnimLayer.alloc(layer,null,null);
            track.setAnimLayer(layer);
        }
        return track;
    }
    private static void mask(AnimationTrack track,float weight) {
        track.setBoneWeights(List.of(new AnimBoneWeight("Bip01_Spine",weight)));
        track.initBoneWeights(SKINNING);
    }
    private static float weight(List<AnimationTrack> tracks,AnimationTrack... fast) {
        var identities=Set.of(fast);
        return CartAnimationBlend.fastWeight(tracks,3,identities::contains);
    }
    private static void chainMask(AnimationTrack track,float root,float pelvis,float waist,float spine) {
        var weights=new java.util.ArrayList<AnimBoneWeight>();
        String[] names={"root","pelvis","waist","Bip01_Spine"};
        float[] values={root,pelvis,waist,spine};
        for(int i=0;i<names.length;i++) {
            var weight=new AnimBoneWeight(names[i],values[i]);
            weight.includeDescendants=false;
            weights.add(weight);
        }
        track.setBoneWeights(weights);track.initBoneWeights(SKINNING);
    }
    private static float chainWeight(List<AnimationTrack> tracks,AnimationTrack... fast) {
        var identities=Set.of(fast);
        return CartAnimationBlend.fastWeight(tracks,SKINNING.getBone("Bip01_Spine"),identities::contains);
    }
    private static void close(float actual,double expected,String message) {
        if(!Float.isFinite(actual) || Math.abs(actual-expected)>1e-6)
            throw new AssertionError(message+": "+actual+" != "+expected);
    }
    private static void unavailable(float result,String message) {
        if(!Float.isNaN(result)) throw new AssertionError(message+": "+result);
    }

    private static void pickerOverlap() {
        var forward=track("WalkForward",.82f);
        var idle=track("WalkIdle",.82f);
        forward.setBlendFieldWeight(.8f);idle.setBlendFieldWeight(.2f);
        var run=track("RunForward",.5644444f);
        close(weight(List.of(run,idle,forward),run),.344,
            "overlapping raw weights above one must clip Run after the larger Walk track");
        close(weight(List.of(forward,run,idle),run),.344,
            "allocation must use native sort order rather than caller order");
        close(forward.getBlendWeight(),.656,"ownership calculation must not mutate native picker weights");
        close(run.getBlendWeight(),.5644444,"ownership calculation must not mutate an outgoing track");
        run.setBlendWeight(2);
        close(weight(List.of(forward,run,idle),run),1,"raw fast weight above one cannot exceed its bone budget");
        run.setBlendWeight(.8f);
        var sprint=track("SprintForward",.7f);
        close(weight(List.of(forward,run,sprint,idle),run,sprint),1,
            "native Run/Sprint overlap shares one clipped budget");
    }

    private static void masksPriorityAndOutgoing() {
        var run=track("Run",.8f,.5f,11,0);
        var brace=track("Brace",.9f,1,12,0);
        close(weight(List.of(run),run),.4,"Spine bone mask multiplies the entry weight");
        close(weight(List.of(run,brace),run),.1,"higher-priority unknown pose consumes Spine budget first");
        mask(brace,0);
        close(weight(List.of(run,brace),run),.4,"masked upper pose cannot hide the Spine's fast share");
        mask(brace,.5f);
        close(weight(List.of(run,brace),run),.4,"a partial higher-priority mask leaves sufficient lower budget");
        var upper=track("UpperLayer",.8f,1,1,1);
        close(weight(List.of(run,upper),run),.2,"native layer ordering precedes numeric track priority");
        // Native continues drawing weighted outgoing poses even when their clips are paused.
        run.isPlaying=false;
        close(weight(List.of(run),run),.4,"outgoing track activity must not retire a displayed pose");
        var absent=track("MissingFast",1);
        close(weight(List.of(run),absent),0,"a fast identity absent from the actual multi-track is not displayed");
        close(weight(List.of(run)),0,"unknown identities do not become fast by clip name");
    }

    private static void thresholdsAndInvalidInputs() {
        var run=track("Run",.000999f);
        close(weight(List.of(run),run),0,"native threshold omits negligible entries");
        run.setBlendWeight(.001f);
        close(weight(List.of(run),run),0,"bone contribution at exactly the threshold is omitted");
        run.setBlendWeight(.00101f);
        close(weight(List.of(run),run),.00101,"contribution above threshold survives");
        run.setBlendWeight(.9f);mask(run,.001f);
        close(weight(List.of(run),run),0,"mask at native threshold cannot contribute");
        mask(run,1);
        for(float invalid:new float[]{Float.NaN,Float.POSITIVE_INFINITY,-.1f}) {
            run.setBlendWeight(invalid);
            unavailable(weight(List.of(run),run),"invalid raw weight must request conservative fallback");
            run.setBlendWeight(.5f);
            if(invalid>=0 || Float.isNaN(invalid)) {
                mask(run,invalid);
                unavailable(weight(List.of(run),run),"invalid bone mask must request conservative fallback");
            }
            mask(run,1);
        }
        unavailable(CartAnimationBlend.fastWeight(null,3,t->true),"missing multi-track");
        unavailable(CartAnimationBlend.fastWeight(List.of(run),-1,t->true),"negative bone");
        unavailable(CartAnimationBlend.fastWeight(List.of(run),3,null),"missing identity predicate");
        unavailable(weight(Arrays.asList(run,null),run),"missing native track");
        unavailable(weight(List.of(track("BadLayer",1,1,11,16))),"invalid native layer");
        close(weight(List.of()),0,"empty actual multi-track has no fast contribution");
        close(weight(List.of(run),run),.5,"failed checks must clear thread-local native entries");
        close(CartAnimationBlend.fastWeight((zombie.characters.IsoPlayer)null),0,"missing player");
    }

    private static void outgoingAncestorPresence() {
        var sprint=track("Sprint",.5f);
        chainMask(sprint,1,1,1,1);
        var walk=track("WalkUpper",1,1,12,0);
        close(weight(List.of(sprint,walk),sprint),0,"incoming Walk can completely own local Spine");
        close(chainWeight(List.of(sprint,walk),sprint),.5,
            "outgoing pelvis/root still contributes to model-space Spine after its local fast share retires");
        var upper=track("FastUpper",.4f,1,13,0);
        sprint.setBlendWeight(.7f);
        close(chainWeight(List.of(sprint,walk,upper),sprint,upper),.7,
            "chain presence takes the maximum instead of counting the same pose at several joints");
        var unknown=track("UnknownFullBody",1,1,14,0);
        chainMask(unknown,1,1,1,1);
        close(chainWeight(List.of(sprint,walk,upper,unknown),sprint,upper),0,
            "higher-priority full-body owner can retire the entire fast chain");
        sprint.setBlendWeight(0);upper.setBlendWeight(0);
        close(chainWeight(List.of(sprint,walk,upper),sprint,upper),0,
            "ordinary Walk has no reserve once every native fast contributor retires");
        sprint.setBlendWeight(.5f);chainMask(sprint,1,Float.NaN,1,1);
        unavailable(chainWeight(List.of(sprint,walk),sprint),"invalid ancestor mask requests conservative fallback");
        unavailable(CartAnimationBlend.fastWeight(List.of(sprint),
            (zombie.core.skinnedmodel.model.SkinningBone)null,t->true),"missing chain");
        close(walk.getBlendWeight(),1,"chain inspection must not change native track weights");
    }

    private static LiveAnimNode node(AnimLayer layer,String name,AnimationTrack track) {
        var source=new AnimNode();source.name=name;
        var node=LiveAnimNode.alloc(layer,source);
        track.setAnimLayer(layer);node.addMainTrack(track);
        node.setActive(false);layer.getLiveAnimNodes().add(node);
        return node;
    }
    private static float classified(AdvancedAnimator animator,List<AnimationTrack> tracks) {
        var fast=CartAnimationBlend.fastTracks(animator);
        return CartAnimationBlend.fastWeight(tracks,3,fast::contains);
    }
    private static void allMaskedLayersAndTransitions() {
        var animator=new AdvancedAnimator();animator.init(null,null);
        var state=new AnimState();state.name="run";
        var leftState=new AnimState();leftState.name="maskingleft";
        var rightState=new AnimState();rightState.name="maskingright";
        animator.setState(state,List.of(leftState,rightState));
        if(animator.getSubLayerCount()!=2) throw new AssertionError("fixture must create both actual animator sublayers");
        var root=track("Bob_Run",1);
        var left=track("Bob_Cart_Run",.50001f);
        var right=track("Bob_Cart_Run",.50001f);
        node(animator.getRootLayer(),"ToolkitCartPivotRun",root);
        var leftNode=node(animator.getSubLayerAt(0),"ToolkitCartRunLeft",left);
        var rightNode=node(animator.getSubLayerAt(1),"ToolkitCartRunRight",right);
        var tracks=new java.util.ArrayList<AnimationTrack>(List.of(root,left,right));
        close(weight(tracks,root),0,"masked upper layers replace root Run at the Spine");
        close(classified(animator,tracks),1,"both masked Run layers must retain fast ownership when root contribution is zero");
        left.setBlendWeight(.15f);right.setBlendWeight(.25f);root.setBlendWeight(.2f);
        close(classified(animator,tracks),.6,"inactive outgoing root and hand-layer poses fade by their actual contributions");
        root.setBlendWeight(0);left.setBlendWeight(0);right.setBlendWeight(0);
        close(classified(animator,tracks),0,"all fast layers must retire after their native fade");
        var sprint=track("Bob_Cart_Sprint",1);
        node(animator.getSubLayerAt(0),"ToolkitCartSprintLeft",sprint);tracks.add(sprint);
        mask(sprint,0);
        close(classified(animator,tracks),0,"actual Sprint hand-only masks cannot invent Spine ownership");
        mask(sprint,1);
        close(classified(animator,tracks),1,"a Sprint sublayer with actual Spine weight is recognized by node identity");
        sprint.setBlendWeight(0);
        for(var owner:List.of(leftNode,rightNode)) for(String name:List.of("Bob_Cart_WalkToRun","Bob_Cart_WalkToSprint")) {
            var transition=track(name,.4f);
            transition.setAnimLayer(owner==leftNode?animator.getSubLayerAt(0):animator.getSubLayerAt(1));
            owner.startTransitionIn(new AnimNode(),new AnimTransition(),transition);
            tracks.add(transition);
            close(classified(animator,tracks),.4,"known upper fast entry transition retains the envelope before main playback");
            transition.setBlendWeight(0);
        }
        var unknown=track("Bob_Cart_Run",1);
        node(animator.getSubLayerAt(1),"UnknownModRun",unknown);tracks.add(unknown);
        root.setBlendWeight(1);
        close(classified(animator,tracks),0,"an unknown upper owner consumes the budget without clip-name promotion");
        unknown.setBlendWeight(0);
        var brace=track("Toolkit_WoodCartBrace",1);
        node(animator.getSubLayerAt(1),"ToolkitWoodCartBraceRight",brace);tracks.add(brace);
        chainMask(root,1,1,1,1);
        for(float outgoing:new float[]{1,.5f,.01f,.00101f,.0001f,0}) {
            root.setBlendWeight(outgoing);
            var fast=CartAnimationBlend.fastTracks(animator);
            close(CartAnimationBlend.fastWeight(tracks,SKINNING.getBone("Bip01_Spine"),fast::contains),
                outgoing>.001f?outgoing:0,"shared brace must not pin the outgoing fast envelope to one");
            close(classified(animator,tracks),0,"shared brace is not a fast-pose identity at the local Spine");
        }
        root.setBlendWeight(0);
        close(classified(animator,tracks),0,"ordinary Walk brace cannot acquire a new fast reserve");
        for(String name:List.of("Bob_RunToStop2H_Heavy","Bob_SprintToStop2h_Heavy",
            "Toolkit_CartPivot_StopRun","Toolkit_CartPivot_StopSprint")) {
            var idle=node(animator.getRootLayer(),"ToolkitCartIdle",track("Idle",0));
            var stop=track(name,.4f);stop.setAnimLayer(animator.getRootLayer());
            idle.startTransitionIn(new AnimNode(),new AnimTransition(),stop);
            close(classified(animator,List.of(stop)),.4,"native and canonical heavy stops retain actual fast ownership");
            stop.setBlendWeight(0);
        }
    }

    public static void main(String[] args) {
        pickerOverlap();masksPriorityAndOutgoing();thresholdsAndInvalidInputs();outgoingAncestorPresence();allMaskedLayersAndTransitions();
        System.out.println("CART_ANIMATION_BLEND_PASS");
    }
}
