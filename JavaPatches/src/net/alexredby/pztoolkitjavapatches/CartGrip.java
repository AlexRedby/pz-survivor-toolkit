package net.alexredby.pztoolkitjavapatches;

import java.nio.FloatBuffer;
import java.util.WeakHashMap;
import org.joml.Matrix4f;
import org.joml.Quaternionf;
import org.joml.Vector3f;
import zombie.characters.IsoPlayer;
import zombie.core.math.PZMath;
import zombie.core.skinnedmodel.ModelManager;
import zombie.core.skinnedmodel.animation.AnimationClip;
import zombie.core.skinnedmodel.animation.Keyframe;
import zombie.core.skinnedmodel.model.ModelInstance;
import zombie.core.skinnedmodel.model.ModelInstanceRenderData;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;
import zombie.core.skinnedmodel.model.SkinningBone;
import zombie.core.skinnedmodel.model.SkinningData;

/** Fit hands to the cart handles in this render instance while the native legs keep walking. */
public final class CartGrip {
    private static final class Matrices {
        final Matrix4f[] poses=new Matrix4f[60];
        final Matrix4f attachment=new Matrix4f(), adjustment=new Matrix4f(), target=new Matrix4f();
        final Quaternionf rotation=new Quaternionf();
        final Quaternionf headRotation=new Quaternionf(), headTarget=new Quaternionf();
        final org.lwjgl.util.vector.Matrix4f model=new org.lwjgl.util.vector.Matrix4f();
        final org.lwjgl.util.vector.Matrix4f skin=new org.lwjgl.util.vector.Matrix4f();
    }
    private static final ThreadLocal<Matrices> matrices=ThreadLocal.withInitial(Matrices::new);
    private static final WeakHashMap<AnimationClip,WeakHashMap<SkinningData,Quaternionf>> headNeutrals=new WeakHashMap<>();

    private static boolean upperBody(SkinningBone bone) {
        for(;bone!=null;bone=bone.parent) {
            // Native thighs branch from Spine too; keep their entire walking chains live.
            if("Bip01_L_Thigh".equals(bone.name) || "Bip01_R_Thigh".equals(bone.name)) return false;
            if("Bip01_Spine".equals(bone.name)) return true;
        }
        return false;
    }

    static Matrix4f[] poses(AnimationClip clip, SkinningData actor, Matrix4f delta) {
        var poses=matrices.get().poses;
        if(actor==null || actor.numBones()>poses.length) return null;
        if(actor.getBone("Bip01_Spine")==null || actor.getBone("Bip01_L_Hand")==null
            || actor.getBone("Bip01_R_Hand")==null) return null;
        for(int i=0;i<actor.numBones();i++) {
            var bone=actor.getBoneAt(i);
            if(!upperBody(bone)) continue;
            if(poses[i]==null) poses[i]=new Matrix4f();
            if(!CartGrounding.referencePose(clip,actor,bone.name,poses[i])) return null;
            delta.mul(poses[i],poses[i]);
        }
        return poses;
    }

    static Matrix4f[] livePoses(SkinningData actor, SkinningData body, FloatBuffer palette, Matrix4f delta) {
        return livePoses(actor,body,palette,delta,false);
    }

    static Matrix4f[] livePoses(SkinningData actor, SkinningData body, FloatBuffer palette, Matrix4f delta, boolean full) {
        return livePoses(actor,body,palette,delta,full,(float)Math.abs(Math.atan2(delta.m01(),delta.m00())));
    }

    static Matrix4f[] livePoses(SkinningData actor, SkinningData body, FloatBuffer palette, Matrix4f delta,
        boolean full, float pressure) {
        var state=matrices.get();
        if(actor==null || actor.numBones()>state.poses.length || body==null || palette==null || !delta.isFinite()
            || !Float.isFinite(pressure) || pressure<0) return null;
        var spine=actor.getBone("Bip01_Spine");
        if(spine==null) return null;
        int position=palette.position();
        try {
            for(int i=0;i<actor.numBones();i++) {
                var bone=actor.getBoneAt(i);
                if(!full && !upperBody(bone)) continue;
                Integer index=body.boneIndices.get(bone.name);
                if(index==null || index<0 || (index+1)*16>palette.limit()
                    || index>=body.boneOffset.size() || body.boneOffset.get(index)==null) return null;
                if(state.poses[i]==null) state.poses[i]=new Matrix4f();
                palette.position(index*16);state.skin.load(palette);
                PZMath.convertMatrix(state.skin,state.poses[i]).transpose();
                PZMath.convertMatrix(body.boneOffset.get(index),state.adjustment).transpose().invert();
                state.poses[i].mul(state.adjustment);
                if(!state.poses[i].isFinite()) return null;
            }
        } finally {palette.position(position);}
        float lean=(float)Math.atan2(delta.m01(),delta.m00());
        var base=state.poses[spine.index];
        float extra=CartSteeringMath.woodenBankExtra(lean);
        float roll=Math.max(-.27925268f,Math.min(.27925268f,(2.1f+.2f*extra)*lean));
        state.adjustment.translation(base.m30(),base.m31(),base.m32()).rotateZ(roll)
            .translate(-base.m30(),-base.m31(),-base.m32());
        for(int i=0;i<actor.numBones();i++) if(i!=spine.index && upperBody(actor.getBoneAt(i)))
            state.adjustment.mul(state.poses[i],state.poses[i]);
        var chest=actor.getBone("Bip01_Spine1");
        if(chest==null) return null;
        // Bend above the pelvis around the already banked chest; both native leg chains stay untouched.
        base=state.poses[chest.index];
        state.adjustment.translation(base.m30(),base.m31(),base.m32())
            .rotateX(-(float)Math.toRadians(14*CartSteeringMath.woodenTurnAmount(pressure)
                +6*CartSteeringMath.woodenBankExtra(pressure)))
            .translate(-base.m30(),-base.m31(),-base.m32());
        for(int i=0;i<actor.numBones();i++) if(descendant(actor.getBoneAt(i),chest))
            state.adjustment.mul(state.poses[i],state.poses[i]);
        return state.poses;
    }

    private static boolean descendant(SkinningBone bone, SkinningBone ancestor) {
        for(;bone!=null;bone=bone.parent) if(bone==ancestor) return true;
        return false;
    }

    private static void adjust(Matrix4f[] poses, SkinningData actor, SkinningBone root, Matrix4f change) {
        for(int i=0;i<actor.numBones();i++) if(descendant(actor.getBoneAt(i),root)) change.mul(poses[i],poses[i]);
    }

    private static Quaternionf keyRotation(Keyframe frame) {
        if(frame==null || frame.rotation==null) return null;
        var q=frame.rotation;var rotation=new Quaternionf(q.x,q.y,q.z,q.w);
        return rotation.isFinite() && rotation.lengthSquared()>1e-12f?rotation.normalize():null;
    }

    private static Quaternionf meanRunningHead(AnimationClip clip, SkinningData actor) {
        var chest=actor.getBone("Bip01_Spine1");var neck=actor.getBone("Bip01_Neck");var head=actor.getBone("Bip01_Head");
        float duration=clip.getDuration();
        if(chest==null || neck==null || head==null || neck.parent!=chest || head.parent!=neck
            || !Float.isFinite(duration) || duration<=0) return null;
        var neckFrames=clip.getBoneFramesAt(neck.index);var headFrames=clip.getBoneFramesAt(head.index);
        if(neckFrames==null || neckFrames.length==0 || headFrames==null || headFrames.length<2) return null;
        var neckRotation=keyRotation(neckFrames[0]);
        if(neckRotation==null) return null;
        // This authored Run clip has a static Neck; do not silently generalize to another rig/clip.
        for(var frame:neckFrames) {
            var q=keyRotation(frame);
            if(q==null || !Float.isFinite(frame.time) || frame.time<0 || frame.time>duration
                || Math.abs(neckRotation.dot(q))<.999999f) return null;
        }
        var rotations=new Quaternionf[headFrames.length];
        for(int i=0;i<headFrames.length;i++) {
            var frame=headFrames[i];var q=keyRotation(frame);
            if(q==null || !Float.isFinite(frame.time) || frame.time<0 || frame.time>duration
                || (i>0 && frame.time<=headFrames[i-1].time)) return null;
            rotations[i]=q;
        }
        double x=0,y=0,z=0,w=0;
        for(int i=0;i<headFrames.length;i++) {
            var q=rotations[i];
            double previous=i==0?headFrames[headFrames.length-1].time-duration:headFrames[i-1].time;
            double next=i==headFrames.length-1?headFrames[0].time+duration:headFrames[i+1].time;
            // Circular trapezoid weights also handle a duplicated key at both loop endpoints.
            double weight=(next-previous)/2*(rotations[0].dot(q)<0?-1:1);
            x+=weight*q.x;y+=weight*q.y;z+=weight*q.z;w+=weight*q.w;
        }
        var mean=new Quaternionf((float)x,(float)y,(float)z,(float)w);
        return mean.isFinite() && mean.lengthSquared()>1e-12f?neckRotation.mul(mean.normalize()).normalize():null;
    }

    private static synchronized Quaternionf runningHeadNeutral(AnimationClip clip, SkinningData actor) {
        if(clip==null) return null;
        var actors=headNeutrals.computeIfAbsent(clip,key->new WeakHashMap<>());
        if(!actors.containsKey(actor)) actors.put(actor,meanRunningHead(clip,actor));
        return actors.get(actor);
    }

    static void calmRunningHead(Matrix4f[] poses, SkinningData actor, AnimationClip reference, float runWeight) {
        if(!Float.isFinite(runWeight) || runWeight<=0 || actor==null || poses==null) return;
        var head=actor.getBone("Bip01_Head");var chest=actor.getBone("Bip01_Spine1");
        if(head==null || chest==null) return;
        var neutral=runningHeadNeutral(reference,actor);
        if(neutral==null) return;
        var state=matrices.get();
        state.target.rotation(neutral);
        poses[chest.index].mul(state.target,state.target);
        if(!state.target.isFinite()) return;
        state.target.getUnnormalizedRotation(state.headTarget).normalize();
        poses[head.index].getUnnormalizedRotation(state.headRotation).normalize();
        if(!state.headTarget.isFinite() || !state.headRotation.isFinite()) return;
        // The cart chest leaves native Run's head counter-rotation unbalanced; retain a quarter of its sway.
        state.rotation.set(state.headRotation).slerp(state.headTarget,.75f*Math.min(1,runWeight))
            .mul(state.headRotation.conjugate()).normalize();
        var pose=poses[head.index];float x=pose.m30(),y=pose.m31(),z=pose.m32();
        state.adjustment.translation(x,y,z).rotate(state.rotation).translate(-x,-y,-z);
        adjust(poses,actor,head,state.adjustment);
        pose.setTranslation(x,y,z);
    }

    private static void aim(Matrix4f[] poses, SkinningData actor, SkinningBone root,
        Vector3f pivot, Vector3f from, Vector3f to) {
        var state=matrices.get();
        state.rotation.rotationTo(from.sub(pivot,new Vector3f()).normalize(),to.sub(pivot,new Vector3f()).normalize());
        state.adjustment.translation(pivot).rotate(state.rotation).translate(-pivot.x,-pivot.y,-pivot.z);
        adjust(poses,actor,root,state.adjustment);
    }

    // Solve two links without stretching; leg correction keeps the planted foot target.
    static boolean reach(Matrix4f[] poses, SkinningData actor, String handName, Matrix4f target, Matrix4f bodyDelta, boolean wood) {
        return reach(poses,actor,handName,target,bodyDelta,wood,1);
    }

    static boolean reach(Matrix4f[] poses, SkinningData actor, String handName, Matrix4f target,
        Matrix4f bodyDelta, boolean wood, float policyWeight) {
        if(!Float.isFinite(policyWeight) || policyWeight<0 || policyWeight>1) return false;
        var hand=actor.getBone(handName);
        if(hand==null || hand.parent==null || hand.parent.parent==null) return false;
        if(policyWeight==0) return true;
        var forearm=hand.parent;var upper=forearm.parent;
        var shoulder=poses[upper.index].getTranslation(new Vector3f());
        var elbow=poses[forearm.index].getTranslation(new Vector3f());
        var wrist=poses[hand.index].getTranslation(new Vector3f());
        var goal=target.getTranslation(new Vector3f());
        float a=shoulder.distance(elbow),b=elbow.distance(wrist),distance=shoulder.distance(goal);
        if(!Float.isFinite(distance) || !Float.isFinite(a+b) || a<.00001f || b<.00001f
            || distance<.00001f || distance<=Math.abs(a-b)) return false;
        var clavicle=upper.parent;
        if(wood && distance>a+b-.01f && clavicle!=null
            && ("Bip01_L_Clavicle".equals(clavicle.name) || "Bip01_R_Clavicle".equals(clavicle.name))) {
            var pivot=poses[clavicle.index].getTranslation(new Vector3f());
            var from=shoulder.sub(pivot,new Vector3f());var to=goal.sub(pivot,new Vector3f());
            float c=from.length(),d=to.length(),reserve=a+b-distance;
            if(c<.00001f || d<.00001f || !Float.isFinite(c+d)) return false;
            // Ease in before full extension; the native clavicle rotates, with 5mm elbow reserve at the limit.
            float correction=reserve<=0?.005f*policyWeight-reserve
                :(.01f-reserve)*(.01f-reserve)/.02f*policyWeight;
            float desired=distance-correction;
            if(desired<=Math.abs(c-d)) return false;
            float angle=(float)Math.acos(Math.max(-1,Math.min(1,from.dot(to)/(c*d))));
            float remaining=(float)Math.acos(Math.max(-1,Math.min(1,(c*c+d*d-desired*desired)/(2*c*d))));
            float turn=angle-remaining;
            if(!Float.isFinite(turn)) return false;
            // The elbow reserve is preferred; a reachable grip can use less at the clavicle limit.
            turn=Math.min(turn,(float)Math.toRadians(30));
            if(turn>.000001f) {
                var axis=from.cross(to,new Vector3f());
                if(axis.lengthSquared()<.00000001f) return false;
                var shifted=new Quaternionf().rotationAxis(turn,axis.normalize()).transform(from).add(pivot);
                if(shifted.distance(goal)>=a+b) return false;
                aim(poses,actor,clavicle,pivot,shoulder,shifted);
                poses[clavicle.index].setTranslation(pivot);
                poses[upper.index].getTranslation(shoulder);poses[forearm.index].getTranslation(elbow);
                poses[hand.index].getTranslation(wrist);distance=shoulder.distance(goal);
            }
        }
        if(distance>=a+b) return false;
        var axis=goal.sub(shoulder,new Vector3f()).div(distance);
        var bend=elbow.sub(shoulder,new Vector3f());
        if(handName.equals("Bip01_L_Foot") || handName.equals("Bip01_R_Foot")) {
            var toe=actor.getBone(handName.replace("_Foot","_Toe0"));
            if(toe==null || toe.parent!=hand) return false;
            // A shifted hip can put the native knee behind the new leg axis; bend toward the toes.
            poses[toe.index].getTranslation(bend).sub(wrist);bend.y=0;
        }
        if(bodyDelta!=null) {
            var nativeBend=policyWeight<1?new Vector3f(bend).fma(-bend.dot(axis),axis):null;
            bend.set(goal).sub(shoulder).fma(-b,new Vector3f(target.m00(),target.m01(),target.m02()));
            bend.fma(-bend.dot(axis),axis).normalize();
            var relaxed=bodyDelta.transformDirection(new Vector3f(0,-1,wood?1f:.25f));
            relaxed.fma(-relaxed.dot(axis),axis).normalize();
            // Keep the elbow down/back instead of lifting it just to minimize the wrist angle.
            float extra=wood?CartSteeringMath.woodenBankExtra((float)Math.atan2(bodyDelta.m01(),bodyDelta.m00())):0;
            bend.lerp(relaxed,.6f-.05f*extra);
            if(nativeBend!=null) {
                if(!nativeBend.isFinite() || nativeBend.lengthSquared()<.00000001f) return false;
                bend.fma(-bend.dot(axis),axis).normalize();nativeBend.normalize();
                new Quaternionf().slerp(new Quaternionf().rotationTo(nativeBend,bend),policyWeight)
                    .transform(nativeBend,bend);
            }
        }
        bend.fma(-bend.dot(axis),axis);
        if(!bend.isFinite() || bend.lengthSquared()<.00000001f) return false;
        float along=(a*a-b*b+distance*distance)/(2*distance);
        var solved=shoulder.fma(along,axis,new Vector3f()).fma((float)Math.sqrt(Math.max(0,a*a-along*along)),bend.normalize());
        aim(poses,actor,upper,shoulder,elbow,solved);
        poses[hand.index].getTranslation(wrist);
        aim(poses,actor,forearm,solved,wrist,goal);
        var adjustment=matrices.get().adjustment;
        if(bodyDelta!=null) {
            // Pronation belongs in the forearm, rather than twisting the entire underhand turn at the wrist.
            var forearmAxis=goal.sub(solved,new Vector3f()).normalize();
            var from=poses[forearm.index].transformDirection(new Vector3f(0,0,1));
            var to=target.transformDirection(new Vector3f(0,0,1));
            from.fma(-from.dot(forearmAxis),forearmAxis).normalize();
            to.fma(-to.dot(forearmAxis),forearmAxis).normalize();
            float roll=(float)Math.atan2(forearmAxis.dot(from.cross(to,new Vector3f())),from.dot(to))*policyWeight;
            adjustment.translation(solved).rotate(roll,forearmAxis).translate(-solved.x,-solved.y,-solved.z);
            adjust(poses,actor,forearm,adjustment);
        }
        poses[hand.index].invert(adjustment);target.mul(adjustment,adjustment);
        adjust(poses,actor,hand,adjustment);
        return true;
    }

    // shortcut: these are native MaleBody/FemaleBody mesh measurements; recalibrate for another hand mesh/rig.
    record Grasp(float palmX, float palmDepth, float curl) {}
    private static final Grasp MALE_ROUND=new Grasp(.055f,.027f,-1.68f);
    private static final Grasp FEMALE_ROUND=new Grasp(.063f,.025f,-1.55f);
    private static final Grasp MALE_WOOD=new Grasp(.055f,.020f,-1.4f);
    private static final Grasp FEMALE_WOOD=new Grasp(.055f,.024f,-1.75f);
    private static final Grasp MALE_METAL=new Grasp(.063f,.015f,-1.8f);
    private static final Grasp FEMALE_METAL=new Grasp(.055f,.025f,-1.8f);

    static Grasp grasp(boolean female, String model) {
        if("WheelbarrowWood".equals(model)) return female?FEMALE_WOOD:MALE_WOOD;
        if("WheelbarrowMetal".equals(model)) return female?FEMALE_METAL:MALE_METAL;
        return female?FEMALE_ROUND:MALE_ROUND;
    }

    // shortcut: B42 has one mitten segment and one thumb, so individual phalange wrapping needs a detailed rig.
    static void closeFingers(Matrix4f[] poses, SkinningData actor, String side, Grasp grasp, boolean underhand) {
        var hand=actor.getBone("Bip01_"+side+"_Hand");
        var fingers=actor.getBone("Bip01_"+side+"_Finger1");
        var thumb=actor.getBone("Bip01_"+side+"_Finger0");
        if(hand==null || fingers==null || thumb==null) return;
        var handPose=poses[hand.index];
        var local=new Matrix4f(handPose).invert().mul(poses[fingers.index]);
        var target=new Matrix4f(handPose).translate(local.m30(),local.m31(),local.m32()).rotateY(grasp.curl());
        var change=matrices.get().adjustment;
        poses[fingers.index].invert(change);target.mul(change,change);adjust(poses,actor,fingers,change);
        if(grasp==MALE_WOOD || grasp==FEMALE_WOOD) {
            // Follow the steeper wooden grip while keeping the thumb knuckle and native twist.
            handPose.invert(change).mul(poses[thumb.index]);
            var thumbLocal=new Matrix4f(change).setTranslation(0,0,0);
            target.set(handPose).translate(change.m30(),change.m31(),change.m32())
                .rotateY((float)Math.toRadians(grasp==FEMALE_WOOD?10:20))
                .rotateZ((float)Math.toRadians("L".equals(side)?-35:35)).mul(thumbLocal);
            poses[thumb.index].invert(change);target.mul(change,change);adjust(poses,actor,thumb,change);
        }
        // The metal shaft retains the authored thumb opposition/twist.
        if(underhand) return;
        var pivot=poses[thumb.index].getTranslation(new Vector3f());
        var from=poses[thumb.index].transformPosition(new Vector3f(.033f,0,0));
        var to=handPose.transformPosition(new Vector3f(.045f,"L".equals(side)?-.001f:.001f,.025f));
        aim(poses,actor,thumb,pivot,from,to);
    }

    // Mesh-local centers measured from the actual GPU handle rings/end planes, not the authored hand pose.
    static boolean handle(String model, boolean left, Vector3f point) {
        if(model==null) return false;
        switch(model) {
            case "ShoppingCartModel", "ShoppingCartPartialModel", "ShoppingCartFullModel",
                "ShoppingCartFlashlightModel", "ShoppingCartFlashlightPartialModel", "ShoppingCartFlashlightFullModel" ->
                point.set(-150.07166f,343.47412f,left?.809756f:-.809769f);
            case "WheelbarrowWood" -> point.set(left?.00172237f:-.00172238f,.00541905f,-.00342593f);
            case "WheelbarrowMetal" -> point.set(left?-7.409948f:-39.674755f,6.614635f,82.79839f);
            default -> { return false; }
        }
        return true;
    }

    static boolean target(String model, boolean left, boolean female, Matrix4f delta, Matrix4f cart, Matrix4f out) {
        return target(model,left,female,delta,cart,out,(float)Math.abs(Math.atan2(delta.m01(),delta.m00())));
    }

    static boolean target(String model, boolean left, boolean female, Matrix4f delta, Matrix4f cart, Matrix4f out,
        float pressure) {
        if(!Float.isFinite(pressure) || pressure<0) return false;
        var point=new Vector3f();
        if(!handle(model,left,point)) return false;
        cart.transformPosition(point);
        boolean wood="WheelbarrowWood".equals(model),metal="WheelbarrowMetal".equals(model);
        var shape=grasp(female,model);
        out.identity();
        if(wood || metal) {
            var axis=wood?new Vector3f(left?.13444413f:-.13444413f,.98614604f,-.09716362f)
                :new Vector3f(0,0,1);
            var down=wood?new Vector3f(0,.098053805f,.9951811f):new Vector3f(0,-1,0);
            cart.transformDirection(axis).normalize();cart.transformDirection(down).normalize();
            var inward=down.cross(axis,new Vector3f()).normalize().mul(left?1:-1);
            // Diagonal underhand grip: shaft across curled fingers, palm inward/up, wrist above the handle.
            var x=down.mul(.9961947f,new Vector3f()).fma(.08715574f,inward);
            var z=inward.mul(.9961947f,new Vector3f()).fma(-.08715574f,down);
            float beta=(float)Math.toRadians(25+10*CartSteeringMath.woodenTurnAmount(pressure));
            x.mul(wood?(float)Math.cos(beta):.5735200f).fma(wood?-(float)Math.sin(beta):-.8191916f,axis).normalize();
            var y=z.cross(x,new Vector3f()).normalize();z=x.cross(y,new Vector3f()).normalize();
            out.m00(x.x).m01(x.y).m02(x.z).m10(y.x).m11(y.y).m12(y.z).m20(z.x).m21(z.y).m22(z.z);
        } else {
            out.m00(0).m01(0).m02(-1).m10(1).m11(0).m12(0).m20(0).m21(-1).m22(0);
        }
        if(!wood && !metal) delta.mul(out,out);
        out.setTranslation(point.x-out.m00()*shape.palmX()-out.m20()*shape.palmDepth(),
            point.y-out.m01()*shape.palmX()-out.m21()*shape.palmDepth(),
            point.z-out.m02()*shape.palmX()-out.m22()*shape.palmDepth());
        return out.isFinite();
    }

    static boolean grip(Matrix4f[] poses, SkinningData actor, String model, boolean female, Matrix4f delta, Matrix4f cart) {
        return grip(poses,actor,model,female,delta,cart,(float)Math.abs(Math.atan2(delta.m01(),delta.m00())));
    }

    static boolean grip(Matrix4f[] poses, SkinningData actor, String model, boolean female, Matrix4f delta, Matrix4f cart,
        float pressure) {
        for(String side:new String[]{"L","R"}) {
            var target=matrices.get().target;
            if(!target(model,"L".equals(side),female,delta,cart,target,pressure)
                || !reach(poses,actor,"Bip01_"+side+"_Hand",target,model.startsWith("Wheelbarrow")?delta:null,
                    "WheelbarrowWood".equals(model))) return false;
            closeFingers(poses,actor,side,grasp(female,model),model.startsWith("Wheelbarrow"));
        }
        return true;
    }

    static int skin(FloatBuffer palette, org.lwjgl.util.vector.Matrix4f[] shaderPalette,
        SkinningData target, SkinningData actor, Matrix4f[] poses) {
        return skin(palette,shaderPalette,target,actor,poses,false);
    }

    static int skin(FloatBuffer palette, org.lwjgl.util.vector.Matrix4f[] shaderPalette,
        SkinningData target, SkinningData actor, Matrix4f[] poses, boolean full) {
        var state=matrices.get();
        int position=palette.position(), changed=0;
        try {
            for(var entry:target.boneIndices.entrySet()) {
                var bone=actor.getBone(entry.getKey());
                int index=entry.getValue();
                if(bone==null || !full && !upperBody(bone) || index<0 || (index+1)*16>palette.limit()
                    || index>=target.boneOffset.size() || target.boneOffset.get(index)==null) continue;
                PZMath.convertMatrix(poses[bone.index],state.model).transpose();
                // Native skin matrices are inverse-bind * model-pose in transposed LWJGL storage.
                org.lwjgl.util.vector.Matrix4f.mul(target.boneOffset.get(index),state.model,state.skin);
                palette.position(index*16);state.skin.store(palette);
                if(shaderPalette!=null && index<shaderPalette.length) {
                    if(shaderPalette[index]==null) shaderPalette[index]=new org.lwjgl.util.vector.Matrix4f();
                    shaderPalette[index].load(state.skin);
                }
                changed++;
            }
        } finally {palette.position(position);}
        return changed;
    }

    static boolean render(ModelSlotRenderData slot, ModelInstance owner, AnimationClip clip, Matrix4f delta,
        String model, Matrix4f cart) {
        ModelInstanceRenderData body=null;
        for(var data:slot.modelData) if(data.modelInstance==owner) {body=data;break;}
        if(body==null || body.matrixPalette==null || !(owner.model.tag instanceof SkinningData bodySkin)) return false;
        for(String hand:new String[]{"Bip01_L_Hand","Bip01_R_Hand"}) {
            Integer index=bodySkin.boneIndices.get(hand);
            if(index==null || index<0 || (index+1)*16>body.matrixPalette.limit()
                || index>=bodySkin.boneOffset.size() || bodySkin.boneOffset.get(index)==null) return false;
        }
        var actor=owner.animPlayer.getSkinningData();
        float pressure=(float)Math.abs(Math.atan2(delta.m01(),delta.m00()));
        if(slot.character instanceof IsoPlayer player) pressure=Math.max(pressure,(float)CartSteeringHooks.clearanceLean(player));
        // Retain the wooden cart gait's spine/clavicle motion; IK absorbs arm swing at the fixed handles.
        var poses="WheelbarrowWood".equals(model)?livePoses(actor,bodySkin,body.matrixPalette,delta,false,pressure):poses(clip,actor,delta);
        if(poses==null || !grip(poses,actor,model,slot.character.isFemale(),delta,cart,pressure)) return false;
        if("WheelbarrowWood".equals(model)) {
            float runWeight=CartLegPace.runningWeight(slot.character);
            if(runWeight>0) {
                AnimationClip runReference;
                try {runReference=ModelManager.instance.getAnimationClip("Bob_Cart_Run");}
                catch(NullPointerException unavailable) {runReference=null;}
                calmRunningHead(poses,actor,runReference,runWeight);
            }
        }
        skinSlot(slot,owner,clip,actor,poses);
        return true;
    }

    static boolean groundFeet(Matrix4f[] poses, SkinningData actor, AnimationClip idle, AnimationClip cartIdle, float liftWeight) {
        return groundFeet(poses,actor,idle,cartIdle,liftWeight,0,0,0);
    }

    static boolean groundFeet(Matrix4f[] poses, SkinningData actor, AnimationClip idle, AnimationClip cartIdle,
        float liftWeight, float shiftX, float shiftY, float shiftZ) {
        return groundFeet(poses,actor,idle,cartIdle,liftWeight,shiftX,shiftY,shiftZ,false);
    }

    static boolean groundFeet(Matrix4f[] poses, SkinningData actor, AnimationClip idle, AnimationClip cartIdle,
        float liftWeight, float shiftX, float shiftY, float shiftZ, boolean preserveFootMotion) {
        if(!Float.isFinite(liftWeight) || liftWeight<0 || liftWeight>1 || !Float.isFinite(shiftX+shiftY+shiftZ)
            || Math.abs(shiftX)>.1f || shiftY>0 || shiftY<-.08f || Math.abs(shiftZ)>.23f) return false;
        if(preserveFootMotion && shiftX==0 && shiftY==0 && shiftZ==0) return true;
        var targets=new Matrix4f[2];String[] sides={"L","R"};
        for(int i=0;i<sides.length;i++) {
            String side=sides[i];
            var foot=actor.getBone("Bip01_"+side+"_Foot");var toe=actor.getBone("Bip01_"+side+"_Toe0");
            if(foot==null || toe==null || toe.parent!=foot || foot.parent==null || foot.parent.parent==null) return false;
            float correction=0;
            if(!preserveFootMotion) {
                var from=new Matrix4f();var to=new Matrix4f();
                if(!CartGrounding.referencePose(idle,actor,toe.name,from)
                    || !CartGrounding.referencePose(cartIdle,actor,toe.name,to)) return false;
                float height=from.m31()+(to.m31()-from.m31())*liftWeight;
                correction=height-poses[toe.index].m31();
            }
            if(Math.abs(correction)>=.0001f || shiftX!=0 || shiftY!=0 || shiftZ!=0) {
                targets[i]=new Matrix4f(poses[foot.index]);targets[i].m31(targets[i].m31()+correction);
            }
        }
        // Shift weight behind/between the low handles while keeping the torso rigid and both feet planted.
        if(shiftX!=0 || shiftY!=0 || shiftZ!=0) for(int i=0;i<actor.numBones();i++) poses[i].translateLocal(shiftX,shiftY,shiftZ);
        for(int i=0;i<sides.length;i++) if(targets[i]!=null) {
            if(!reach(poses,actor,"Bip01_"+sides[i]+"_Foot",targets[i],null,false)) return false;
        }
        return true;
    }

    static boolean bendTransitionTorso(Matrix4f[] poses,SkinningData actor,float angle) {
        if(!Float.isFinite(angle) || angle<0 || angle>Math.PI/2) return false;
        var spine=actor.getBone("Bip01_Spine");
        if(spine==null) return false;
        if(angle==0) return true;
        var base=poses[spine.index];
        var bend=new Matrix4f().translation(base.m30(),base.m31(),base.m32()).rotateX(-angle)
            .translate(-base.m30(),-base.m31(),-base.m32());
        // Native thighs branch from Spine too; a hip hinge must leave both leg chains alone.
        for(int i=0;i<actor.numBones();i++) if(upperBody(actor.getBoneAt(i))) bend.mul(poses[i],poses[i]);
        for(String side:new String[]{"L","R"}) {
            var upper=actor.getBone("Bip01_"+side+"_UpperArm");
            if(upper==null) return false;
            var shoulder=poses[upper.index].getTranslation(new Vector3f());
            // Let the arms hang toward the handles instead of carrying them backward with the torso.
            var hang=new Matrix4f().translation(shoulder).rotateX(angle).translate(-shoulder.x,-shoulder.y,-shoulder.z);
            adjust(poses,actor,upper,hang);
        }
        return true;
    }

    record Posture(float height, Quaternionf rotation) {}

    private static boolean validRotation(Quaternionf rotation) {
        return rotation!=null && rotation.isFinite() && Float.isFinite(rotation.lengthSquared())
            && rotation.lengthSquared()>1e-12f;
    }

    static boolean validPosture(float height, Quaternionf rotation) {
        return Float.isFinite(height) && validRotation(rotation);
    }

    static Posture nativePosture(ModelSlotRenderData slot, ModelInstance owner) {
        for(var body:slot.modelData) if(body.modelInstance==owner && body.matrixPalette!=null
            && owner.model.tag instanceof SkinningData skin) {
            var actor=owner.animPlayer.getSkinningData();
            var spine=actor==null?null:actor.getBone("Bip01_Spine");
            var chest=actor==null?null:actor.getBone("Bip01_Spine1");
            if(spine==null || chest==null) return null;
            var poses=livePoses(actor,skin,body.matrixPalette,new Matrix4f(),true);
            if(poses==null) return null;
            var rotation=poses[chest.index].getUnnormalizedRotation(new Quaternionf());
            float height=poses[spine.index].m31();
            return validPosture(height,rotation)?new Posture(height,rotation.normalize()):null;
        }
        return null;
    }

    static Posture referencePosture(SkinningData actor, CartTransitionMath.Progress phase) {
        var reference=new Matrix4f();var heights=new float[3];var rotations=new Quaternionf[3];
        String[] clips={"Bob_Idle","Bob_IdleLooting_Low","Bob_Cart_Idle"};
        for(int i=0;i<clips.length;i++) {
            var clip=ModelManager.instance.getAnimationClip(clips[i]);
            if(!CartGrounding.referencePose(clip,actor,"Bip01_Spine",reference)) return null;
            heights[i]=reference.m31();
            if(!CartGrounding.referencePose(clip,actor,"Bip01_Spine1",reference)) return null;
            rotations[i]=reference.getUnnormalizedRotation(new Quaternionf());
            if(!validRotation(rotations[i])) return null;
            rotations[i].normalize();
        }
        float height=(float)CartTransitionMath.nativeHeight(phase,heights[0],heights[1],heights[2]);
        // The same shallow low/idle edge and lift weight as the native action's 2D triangle.
        var rotation=rotations[0].slerp(rotations[1],(float)(.10*phase.crouch()))
            .slerp(rotations[2],(float)phase.lift()).normalize();
        return validPosture(height,rotation)?new Posture(height,rotation):null;
    }

    static Posture recoverPosture(Posture start, Posture referenceStart, Posture reference, float amount) {
        if(start==null || referenceStart==null || reference==null || !Float.isFinite(amount) || amount<0 || amount>1
            || !validPosture(start.height(),start.rotation()) || !validPosture(referenceStart.height(),referenceStart.rotation())
            || !validPosture(reference.height(),reference.rotation())) return null;
        var residual=new Quaternionf(referenceStart.rotation()).normalize().conjugate()
            .mul(new Quaternionf(start.rotation()).normalize()).normalize();
        var rotation=new Quaternionf(reference.rotation()).normalize()
            .mul(new Quaternionf().slerp(residual,amount)).normalize();
        float height=reference.height()+(start.height()-referenceStart.height())*amount;
        return validPosture(height,rotation)?new Posture(height,rotation):null;
    }

    static boolean nativeRotation(Matrix4f[] poses, SkinningData actor, Quaternionf target) {
        if(actor==null || poses==null || poses.length<actor.numBones() || !validRotation(target)) return false;
        var spine=actor.getBone("Bip01_Spine");var chest=actor.getBone("Bip01_Spine1");
        if(spine==null || chest==null || poses[spine.index]==null || poses[chest.index]==null
            || !poses[spine.index].isFinite() || !poses[chest.index].isFinite()) return false;
        var current=poses[chest.index].getUnnormalizedRotation(new Quaternionf());
        if(!validRotation(current)) return false;
        var correction=new Quaternionf(target).normalize().mul(current.normalize().conjugate()).normalize();
        float angle=2*(float)Math.acos(Math.min(1,Math.abs(correction.w)));
        if(!Float.isFinite(angle) || angle>(float)Math.toRadians(20)) return false;
        for(int i=0;i<actor.numBones();i++) if(upperBody(actor.getBoneAt(i))
            && (poses[i]==null || !poses[i].isFinite())) return false;
        if(angle<.000001f) return true;
        var pivot=poses[spine.index].getTranslation(new Vector3f());
        var change=new Matrix4f().translation(pivot).rotate(correction).translate(-pivot.x,-pivot.y,-pivot.z);
        if(!change.isFinite()) return false;
        for(int i=0;i<actor.numBones();i++) if(upperBody(actor.getBoneAt(i))) change.mul(poses[i],poses[i]);
        poses[spine.index].setTranslation(pivot);
        return true;
    }

    static boolean nativeHeight(Matrix4f[] poses, SkinningData actor, float target) {
        if(!Float.isFinite(target)) return false;
        var spine=actor.getBone("Bip01_Spine");
        if(spine==null) return false;
        float correction=target-poses[spine.index].m31();
        if(!Float.isFinite(correction) || Math.abs(correction)>.2f) return false;
        for(int i=0;i<actor.numBones();i++) poses[i].translateLocal(0,correction,0);
        return true;
    }

    static boolean transition(ModelSlotRenderData slot, ModelInstance owner, Matrix4f delta,
        Matrix4f cart, float reachWeight, float gripWeight, float liftWeight, float shiftX, float shiftY, float shiftZ, float hinge,
        float baseHeight, Quaternionf baseRotation) {
        ModelInstanceRenderData body=null;
        for(var data:slot.modelData) if(data.modelInstance==owner) {body=data;break;}
        if(body==null || body.matrixPalette==null || !(owner.model.tag instanceof SkinningData bodySkin)) return false;
        var actor=owner.animPlayer.getSkinningData();
        var poses=livePoses(actor,bodySkin,body.matrixPalette,new Matrix4f(),true);
        if(poses==null || Float.isFinite(baseHeight) && !nativeHeight(poses,actor,baseHeight)
            || baseRotation!=null && !nativeRotation(poses,actor,baseRotation)
            || !bendTransitionTorso(poses,actor,hinge)) return false;
        var cartIdle=ModelManager.instance.getAnimationClip("Bob_Cart_Idle");
        if(!groundFeet(poses,actor,ModelManager.instance.getAnimationClip("Bob_Idle"),cartIdle,liftWeight,shiftX,shiftY,shiftZ)) return false;
        if(!transitionGrip(poses,actor,slot.character.isFemale(),delta,cart,reachWeight,gripWeight)) return false;
        skinSlot(slot,owner,cartIdle,actor,poses,true);
        return true;
    }

    static boolean authoredTransition(ModelSlotRenderData slot, ModelInstance owner, AnimationClip clip,
        Matrix4f delta, Matrix4f cart, float reachWeight, float gripWeight, Matrix4f[] restartPose, float restartWeight) {
        ModelInstanceRenderData body=null;
        for(var data:slot.modelData) if(data.modelInstance==owner) {body=data;break;}
        if(body==null || body.matrixPalette==null || !(owner.model.tag instanceof SkinningData bodySkin)) return false;
        var actor=owner.animPlayer.getSkinningData();
        var poses=livePoses(actor,bodySkin,body.matrixPalette,new Matrix4f(),true);
        if(poses==null) return false;
        if(restartPose!=null && !releasePose(poses,actor,restartPose,restartWeight)) return false;
        // The clip owns the approach; constrain hands only after they reach the handles.
        if(restartPose==null && reachWeight<1) return true;
        if(reachWeight>0 && !transitionGrip(poses,actor,slot.character.isFemale(),delta,cart,reachWeight,gripWeight)) return false;
        skinSlot(slot,owner,clip,actor,poses,true);
        return true;
    }

    static boolean transitionGrip(Matrix4f[] poses, SkinningData actor, boolean female, Matrix4f delta,
        Matrix4f cart, float reachWeight, float gripWeight) {
        if(reachWeight==1 && gripWeight==1) {
            if(!grip(poses,actor,"WheelbarrowWood",female,delta,cart)) return false;
        } else for(String side:new String[]{"L","R"}) {
            var hand=actor.getBone("Bip01_"+side+"_Hand");
            var target=new Matrix4f();
            if(!target("WheelbarrowWood","L".equals(side),female,delta,cart,target)
                || !CartTransitionMath.blend(poses[hand.index],target,CartTransitionMath.smooth(reachWeight),target)
                || !reach(poses,actor,hand.name,target,delta,true,reachWeight)) return false;
            var before=new Matrix4f[actor.numBones()];
            for(int i=0;i<before.length;i++) if(descendant(actor.getBoneAt(i),hand)) before[i]=new Matrix4f(poses[i]);
            closeFingers(poses,actor,side,grasp(female,"WheelbarrowWood"),true);
            for(int i=0;i<before.length;i++) if(before[i]!=null)
                CartTransitionMath.blend(before[i],poses[i],CartTransitionMath.smooth(gripWeight),poses[i]);
        }
        return true;
    }

    static Matrix4f[] capture(SkinningData actor, Matrix4f[] saved) {
        var poses=matrices.get().poses;
        if(actor==null || actor.numBones()>poses.length) return null;
        if(saved==null || saved.length!=actor.numBones()) saved=new Matrix4f[actor.numBones()];
        for(int i=0;i<saved.length;i++) {
            if(poses[i]==null || !poses[i].isFinite()) return null;
            if(saved[i]==null) saved[i]=new Matrix4f();
            saved[i].set(poses[i]);
        }
        return saved;
    }

    static boolean releasePose(Matrix4f[] poses, SkinningData actor, Matrix4f[] start, float amount) {
        if(actor==null || poses==null || start==null || poses.length<actor.numBones()
            || start.length!=actor.numBones() || !Float.isFinite(amount) || amount<0 || amount>1) return false;
        var local=new Matrix4f[actor.numBones()];
        for(int i=0;i<local.length;i++) {
            var parent=actor.getBoneAt(i).parent;
            if(poses[i]==null || start[i]==null || !poses[i].isFinite() || !start[i].isFinite()
                || parent!=null && parent.index>=i) return false;
            var from=new Matrix4f(start[i]);var to=new Matrix4f(poses[i]);
            if(parent!=null) {
                new Matrix4f(start[parent.index]).invert().mul(from,from);
                new Matrix4f(poses[parent.index]).invert().mul(to,to);
            }
            local[i]=new Matrix4f();
            // Blend joint rotations in their parent frame; global matrix blending shortens bent limbs.
            if(!CartTransitionMath.blend(to,from,amount,local[i])) return false;
            // Native idle/walk transfer root translation between Bip01 and Pelvis; neither offset is a fixed bone.
            String name=actor.getBoneAt(i).name;
            if(parent!=null && !"Bip01".equals(name) && !"Bip01_Pelvis".equals(name)) {
                float length=from.getTranslation(new Vector3f()).length()*amount
                    +to.getTranslation(new Vector3f()).length()*(1-amount);
                var offset=local[i].getTranslation(new Vector3f());
                if(length>0 && offset.lengthSquared()==0) return false;
                if(length>0) local[i].setTranslation(offset.normalize(length));
            }
        }
        for(int i=0;i<local.length;i++) {
            var parent=actor.getBoneAt(i).parent;
            if(parent==null) poses[i].set(local[i]);
            else poses[parent.index].mul(local[i],poses[i]);
        }
        return true;
    }

    static boolean movingRecovery(ModelSlotRenderData slot, ModelInstance owner, AnimationClip clip,
        Matrix4f delta, Matrix4f cart, Matrix4f held, Matrix4f[] start, float amount, boolean carrying,
        float startReach, float startGrip, float clearance) {
        if(!Float.isFinite(clearance) || clearance<0 || clearance>.25f) return false;
        ModelInstanceRenderData body=null;
        for(var data:slot.modelData) if(data.modelInstance==owner) {body=data;break;}
        if(body==null || body.matrixPalette==null || !(owner.model.tag instanceof SkinningData bodySkin)) return false;
        var actor=owner.animPlayer.getSkinningData();
        var poses=livePoses(actor,bodySkin,body.matrixPalette,new Matrix4f(),true);
        // Clear the descending shaft with a small weight shift against this frame's walking feet.
        if(poses==null || carrying && !grip(poses,actor,"WheelbarrowWood",slot.character.isFemale(),delta,held)
            || !releasePose(poses,actor,start,amount)
            || !carrying && clearance>0 && !groundFeet(poses,actor,null,null,0,-.18f*clearance,-.04f*clearance,.12f*clearance,true)
            || carrying && !transitionGrip(poses,actor,slot.character.isFemale(),delta,cart,
                1-amount*(1-startReach),1-amount*(1-startGrip))) return false;
        skinSlot(slot,owner,clip,actor,poses,true);
        return true;
    }

    private static void skinSlot(ModelSlotRenderData slot, ModelInstance owner, AnimationClip clip,
        SkinningData actor, Matrix4f[] poses) {
        skinSlot(slot,owner,clip,actor,poses,false);
    }

    private static void skinSlot(ModelSlotRenderData slot, ModelInstance owner, AnimationClip clip,
        SkinningData actor, Matrix4f[] poses, boolean full) {
        for(var data:slot.modelData) {
            var instance=data.modelInstance;
            if(instance.animPlayer==owner.animPlayer && instance.model!=null && !instance.model.isStatic
                && data.matrixPalette!=null && instance.model.tag instanceof SkinningData target) {
                var parameter=data.properties.GetParameter("MatrixPalette");
                var shaderPalette=parameter!=null && parameter.GetValue() instanceof org.lwjgl.util.vector.Matrix4f[] value?value:null;
                skin(data.matrixPalette,shaderPalette,target,actor,poses,full);
            } else if(instance.parent==owner && instance.model!=null && instance.model.isStatic) {
                var attachment=owner.getAttachmentById(instance.attachmentNameParent);
                if(attachment==null) attachment=owner.getAttachmentById(instance.parentBoneName);
                String bone=attachment==null?instance.parentBoneName:attachment.getBone();
                if(bone!=null && actor.getBone(bone)!=null && (full || upperBody(actor.getBone(bone)))) {
                    var transform=matrices.get().attachment;
                    var adjustment=matrices.get().adjustment;
                    if(CartGrounding.rigid(data,clip,transform)
                        && CartGrounding.referencePose(clip,actor,bone,adjustment)) {
                        adjustment.invert();poses[actor.getBone(bone).index].mul(adjustment,adjustment);
                        adjustment.mul(transform,transform);data.xfrm.set(transform).transpose();
                    }
                }
            }
        }
    }

    private CartGrip() {}
}
