package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Path;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import zombie.core.math.PZMath;
import zombie.core.skinnedmodel.HelperFunctions;
import zombie.core.skinnedmodel.animation.AnimationTrack;
import zombie.core.skinnedmodel.model.SkinningData;

/** Native authored-clip replay; checks IK/refusals separately from visual quality. */
public final class CartShoppingPickupReplay {
    private static Matrix4f model(Matrix4f[] locals,Matrix4f[] models,SkinningData actor,int i) {
        if(models[i]!=null) return models[i];
        var parent=actor.getBoneAt(i).parent;
        return models[i]=parent==null?new Matrix4f(locals[i]):new Matrix4f(model(locals,models,actor,parent.index)).mul(locals[i]);
    }
    private static Matrix4f[] sample(AnimationTrack track,SkinningData actor,float time) {
        track.setCurrentTimeValue(time);track.setPreviousTimeValue(time);track.UpdateKeyframes(0);
        var locals=new Matrix4f[actor.numBones()];var models=new Matrix4f[actor.numBones()];
        var p=new org.lwjgl.util.vector.Vector3f();var q=new org.lwjgl.util.vector.Quaternion();var scale=new org.lwjgl.util.vector.Vector3f();
        var matrix=new org.lwjgl.util.vector.Matrix4f();
        for(int i=0;i<locals.length;i++) {
            track.get(i,p,q,scale);HelperFunctions.CreateFromQuaternion(q,matrix);HelperFunctions.setPosition(matrix,p);
            locals[i]=PZMath.convertMatrix(matrix,new Matrix4f()).transpose();
        }
        for(int i=0;i<models.length;i++) model(locals,models,actor,i);
        return models;
    }
    public static void main(String[] args) throws Exception {
        if(args.length!=2) throw new IllegalArgumentException("candidate.x originalCartIdle.fbx");
        var source=CartShoppingPickupGenerate.read(Path.of(args[0]));
        var reference=CartShoppingPickupGenerate.read(Path.of(args[1]));
        var actor=source.actor();var track=AnimationTrack.alloc();track.startClip(source.clip(),false,0);track.setUseDeferredMovement(false);
        int count=0;
        for(boolean female:new boolean[]{false,true}) for(boolean drop:new boolean[]{false,true}) for(int frame=0;frame<=200;frame++) {
            double t=frame/200.0;var phase=CartShopping.progress(t,drop);
            var poses=sample(track,actor,(float)(drop?1-t:t));
            var before=java.util.Arrays.stream(poses).map(Matrix4f::new).toArray(Matrix4f[]::new);
            var cart=CartShopping.held(new Matrix4f());
            if(!CartGrip.transitionGrip(poses,actor,female,new Matrix4f(),cart,(float)phase.reach(),(float)phase.grip(),reference.clip(),"ShoppingCartModel"))
                throw new AssertionError("shopping IK refused female="+female+" drop="+drop+" time="+t);
            for(int i=0;i<poses.length;i++) {
                var bone=actor.getBoneAt(i);boolean arm=false;
                for(var b=bone;b!=null;b=b.parent) if(b.name.endsWith("_Clavicle")) arm=true;
                if(!arm && !poses[i].equals(before[i],.000002f)) throw new AssertionError("grip changed standing body/feet "+bone.name);
            }
            if(phase.reach()==1) for(String side:new String[]{"L","R"}) {
                var target=new Matrix4f();CartGrip.transitionTarget("ShoppingCartModel",side.equals("L"),female,new Matrix4f(),cart,target);
                if(!poses[actor.getBone("Bip01_"+side+"_Hand").index].equals(target,.000002f)) throw new AssertionError("full grip misses target");
            }
            count++;
        }
        System.out.println("SHOPPING_NATIVE_IK_PASS samples="+count+" failures=0 visualVerified=false");
    }
}
