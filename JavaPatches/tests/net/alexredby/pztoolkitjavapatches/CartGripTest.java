package net.alexredby.pztoolkitjavapatches;

import java.nio.FloatBuffer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import zombie.core.math.PZMath;
import zombie.core.skinnedmodel.animation.AnimationClip;
import zombie.core.skinnedmodel.animation.Keyframe;
import zombie.core.skinnedmodel.model.SkinningData;

public final class CartGripTest {
    private static SkinningData skeleton(String[] names, List<Integer> parents,
        List<org.lwjgl.util.vector.Matrix4f> offsets) {
        var indices=new HashMap<String,Integer>();
        for(int i=0;i<names.length;i++) indices.put(names[i],i);
        return new SkinningData(new HashMap<>(),offsets,offsets,offsets,parents,indices);
    }

    public static void main(String[] args) {
        String[] names={"Dummy01","Bip01","Bip01_Spine","Bip01_R_Hand","Bip01_L_Hand","Bip01_R_Thigh"};
        var offsets=new ArrayList<org.lwjgl.util.vector.Matrix4f>();
        var frames=new ArrayList<Keyframe>();
        float[][] positions={{0,0,0},{0,0,0},{0,.5f,0},{.2f,.3f,-.2f},{-.2f,.3f,-.2f},{.1f,-.4f,0}};
        for(int i=0;i<names.length;i++) {
            offsets.add(new org.lwjgl.util.vector.Matrix4f());
            var frame=new Keyframe(new org.lwjgl.util.vector.Vector3f(positions[i][0],positions[i][1],positions[i][2]),
                new org.lwjgl.util.vector.Quaternion(),new org.lwjgl.util.vector.Vector3f(i==0?.01f:1,1,1));
            frame.bone=i;frame.boneName=names[i];frame.time=0;frames.add(frame);
        }
        var actor=skeleton(names,List.of(-1,0,1,2,2,1),offsets);
        var clip=new AnimationClip(1,frames,"Bob_Cart_Idle",true);
        String[] remapped={"Bip01_R_Thigh","Bip01_L_Hand","Dummy01","Bip01_Spine","Bip01_R_Hand","Bip01"};
        offsets=new ArrayList<>();
        for(int i=0;i<remapped.length;i++) {
            var offset=new org.lwjgl.util.vector.Matrix4f();
            offset.m03=-(1+i);offset.m13=-.5f*i;offset.m23=.1f*i;offsets.add(offset);
        }
        var clothing=skeleton(remapped,List.of(-1,0,0,0,0,0),offsets);
        var palette=FloatBuffer.allocate(remapped.length*16);
        var otherActor=FloatBuffer.allocate(remapped.length*16);
        var shaderPalette=new org.lwjgl.util.vector.Matrix4f[remapped.length];
        for(int i=0;i<remapped.length;i++) {
            var moving=new org.lwjgl.util.vector.Matrix4f();moving.m03=40+i;moving.m13=50+i;
            palette.position(i*16);moving.store(palette);shaderPalette[i]=new org.lwjgl.util.vector.Matrix4f(moving);
            otherActor.position(i*16);moving.store(otherActor);
        }
        float[] untouched=palette.array().clone();
        for(float lean:new float[]{-.1f,0,.1f}) {
            Matrix4f delta=new Matrix4f().translation(0,.008f,0).rotateZ(lean).translate(0,-.008f,0).translate(0,.12f,0);
            var poses=CartGrip.poses(clip,actor,delta);
            if(poses==null) throw new AssertionError("authored grip pose rejected");
            palette.position(5);
            if(CartGrip.skin(palette,shaderPalette,clothing,actor,poses)!=3 || palette.position()!=5)
                throw new AssertionError("upper-body mapping or palette cursor changed");
            for(int index:new int[]{0,2,5}) for(int i=0;i<16;i++) {
                if(palette.get(index*16+i)!=untouched[index*16+i]) throw new AssertionError("native legs/root pose changed");
            }
            for(int index:new int[]{1,4}) {
                var raw=new org.lwjgl.util.vector.Matrix4f();
                var view=palette.duplicate();view.position(index*16);raw.load(view);
                Matrix4f skin=PZMath.convertMatrix(raw,new Matrix4f()).transpose();
                Vector3f hand=skin.transformPosition(new Vector3f(1+index,.5f*index,-.1f*index));
                Vector3f handle=delta.transformPosition(new Vector3f(index==1?-.2f:.2f,.8f,-.2f));
                if(hand.distance(handle)>.00001f) throw new AssertionError("hand left cart handle at lean "+lean);
                if(!PZMath.convertMatrix(shaderPalette[index],new Matrix4f()).equals(PZMath.convertMatrix(raw,new Matrix4f())))
                    throw new AssertionError("instanced and ordinary renderer palettes disagree");
            }
            if(!java.util.Arrays.equals(otherActor.array(),untouched)) throw new AssertionError("another actor was changed");
        }
        if(frames.get(0).scale.x!=.01f) throw new AssertionError("shared clip scale changed");
        System.out.println("CART_GRIP_PASS (native skin order, remapped clothing, hands/handles, lean, legs, render isolation)");
    }
}
