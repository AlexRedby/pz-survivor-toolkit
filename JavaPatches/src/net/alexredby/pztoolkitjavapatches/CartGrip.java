package net.alexredby.pztoolkitjavapatches;

import java.nio.FloatBuffer;
import org.joml.Matrix4f;
import org.joml.Quaternionf;
import org.joml.Vector3f;
import zombie.core.math.PZMath;
import zombie.core.skinnedmodel.animation.AnimationClip;
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
        final org.lwjgl.util.vector.Matrix4f model=new org.lwjgl.util.vector.Matrix4f();
        final org.lwjgl.util.vector.Matrix4f skin=new org.lwjgl.util.vector.Matrix4f();
    }
    private static final ThreadLocal<Matrices> matrices=ThreadLocal.withInitial(Matrices::new);

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

    private static boolean descendant(SkinningBone bone, SkinningBone ancestor) {
        for(;bone!=null;bone=bone.parent) if(bone==ancestor) return true;
        return false;
    }

    private static void adjust(Matrix4f[] poses, SkinningData actor, SkinningBone root, Matrix4f change) {
        for(int i=0;i<actor.numBones();i++) if(descendant(actor.getBoneAt(i),root)) change.mul(poses[i],poses[i]);
    }

    private static void aim(Matrix4f[] poses, SkinningData actor, SkinningBone root,
        Vector3f pivot, Vector3f from, Vector3f to) {
        var state=matrices.get();
        state.rotation.rotationTo(from.sub(pivot,new Vector3f()).normalize(),to.sub(pivot,new Vector3f()).normalize());
        state.adjustment.translation(pivot).rotate(state.rotation).translate(-pivot.x,-pivot.y,-pivot.z);
        adjust(poses,actor,root,state.adjustment);
    }

    // Solve the two arm links without stretching either link or touching the native leg palette.
    static boolean reach(Matrix4f[] poses, SkinningData actor, String handName, Matrix4f target, Matrix4f bodyDelta) {
        var hand=actor.getBone(handName);
        if(hand==null || hand.parent==null || hand.parent.parent==null) return false;
        var forearm=hand.parent;var upper=forearm.parent;
        var shoulder=poses[upper.index].getTranslation(new Vector3f());
        var elbow=poses[forearm.index].getTranslation(new Vector3f());
        var wrist=poses[hand.index].getTranslation(new Vector3f());
        var goal=target.getTranslation(new Vector3f());
        float a=shoulder.distance(elbow),b=elbow.distance(wrist),distance=shoulder.distance(goal);
        if(!Float.isFinite(distance) || distance<.00001f || distance>=a+b || distance<=Math.abs(a-b)) return false;
        var axis=goal.sub(shoulder,new Vector3f()).div(distance);
        var bend=elbow.sub(shoulder,new Vector3f());
        if(bodyDelta!=null) {
            bend.set(goal).sub(shoulder).fma(-b,new Vector3f(target.m00(),target.m01(),target.m02()));
            bend.fma(-bend.dot(axis),axis).normalize();
            var relaxed=bodyDelta.transformDirection(new Vector3f(0,-1,.25f));
            relaxed.fma(-relaxed.dot(axis),axis).normalize();
            // Keep the elbow down/back instead of lifting it just to minimize the wrist angle.
            bend.lerp(relaxed,.6f);
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
            float roll=(float)Math.atan2(forearmAxis.dot(from.cross(to,new Vector3f())),from.dot(to));
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
    private static final Grasp MALE_WOOD=new Grasp(.055f,.014f,-1.8f);
    private static final Grasp FEMALE_WOOD=new Grasp(.055f,.025f,-1.6f);
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
        // The authored thumb already follows the diagonal shaft; retain its native opposition/twist.
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
            x.mul(.5735200f).fma(-.8191916f,axis).normalize();
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
        for(String side:new String[]{"L","R"}) {
            var target=matrices.get().target;
            if(!target(model,"L".equals(side),female,delta,cart,target)
                || !reach(poses,actor,"Bip01_"+side+"_Hand",target,model.startsWith("Wheelbarrow")?delta:null)) return false;
            closeFingers(poses,actor,side,grasp(female,model),model.startsWith("Wheelbarrow"));
        }
        return true;
    }

    static int skin(FloatBuffer palette, org.lwjgl.util.vector.Matrix4f[] shaderPalette,
        SkinningData target, SkinningData actor, Matrix4f[] poses) {
        var state=matrices.get();
        int position=palette.position(), changed=0;
        try {
            for(var entry:target.boneIndices.entrySet()) {
                var bone=actor.getBone(entry.getKey());
                int index=entry.getValue();
                if(!upperBody(bone) || index<0 || (index+1)*16>palette.limit()
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
        var poses=poses(clip,actor,delta);
        if(poses==null || !grip(poses,actor,model,slot.character.isFemale(),delta,cart)) return false;
        for(var data:slot.modelData) {
            var instance=data.modelInstance;
            if(instance.animPlayer==owner.animPlayer && instance.model!=null && !instance.model.isStatic
                && data.matrixPalette!=null && instance.model.tag instanceof SkinningData target) {
                var parameter=data.properties.GetParameter("MatrixPalette");
                var shaderPalette=parameter!=null && parameter.GetValue() instanceof org.lwjgl.util.vector.Matrix4f[] value?value:null;
                skin(data.matrixPalette,shaderPalette,target,actor,poses);
            } else if(instance.parent==owner && instance.model!=null && instance.model.isStatic) {
                var attachment=owner.getAttachmentById(instance.attachmentNameParent);
                if(attachment==null) attachment=owner.getAttachmentById(instance.parentBoneName);
                String bone=attachment==null?instance.parentBoneName:attachment.getBone();
                if(bone!=null && upperBody(actor.getBone(bone))) {
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
        return true;
    }

    private CartGrip() {}
}
