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
        String[] names={"Dummy01","Bip01","Bip01_Spine","Bip01_R_Hand","Bip01_L_Hand","Bip01_R_Thigh",
            "Bip01_L_Thigh","Bip01_L_Calf","Bip01_L_Foot","Bip01_L_Toe0",
            "Bip01_R_Calf","Bip01_R_Foot","Bip01_R_Toe0"};
        var offsets=new ArrayList<org.lwjgl.util.vector.Matrix4f>();
        var frames=new ArrayList<Keyframe>();
        float[][] positions={{0,0,0},{0,0,0},{0,.5f,0},{.2f,.3f,-.2f},{-.2f,.3f,-.2f},{.1f,-.4f,0},
            {-.1f,-.4f,0},{0,-.2f,0},{0,-.2f,.05f},{0,0,.05f},
            {0,-.2f,0},{0,-.2f,.05f},{0,0,.05f}};
        for(int i=0;i<names.length;i++) {
            offsets.add(new org.lwjgl.util.vector.Matrix4f());
            var frame=new Keyframe(new org.lwjgl.util.vector.Vector3f(positions[i][0],positions[i][1],positions[i][2]),
                new org.lwjgl.util.vector.Quaternion(),new org.lwjgl.util.vector.Vector3f(i==0?.01f:1,1,1));
            frame.bone=i;frame.boneName=names[i];frame.time=0;frames.add(frame);
        }
        // Captured B42.21 hierarchy: both thighs are children of Spine, not Pelvis/Bip01.
        var actor=skeleton(names,List.of(-1,0,1,2,2,2,2,6,7,8,5,10,11),offsets);
        var clip=new AnimationClip(1,frames,"Bob_Cart_Idle",true);
        String[] remapped={"Bip01_R_Thigh","Bip01_L_Hand","Dummy01","Bip01_Spine","Bip01_R_Hand","Bip01",
            "Bip01_L_Thigh","Bip01_L_Calf","Bip01_L_Foot","Bip01_L_Toe0",
            "Bip01_R_Calf","Bip01_R_Foot","Bip01_R_Toe0"};
        offsets=new ArrayList<>();
        for(int i=0;i<remapped.length;i++) {
            var offset=new org.lwjgl.util.vector.Matrix4f();
            offset.m03=-(1+i);offset.m13=-.5f*i;offset.m23=.1f*i;offsets.add(offset);
        }
        var clothing=skeleton(remapped,java.util.Collections.nCopies(remapped.length,-1),offsets);
        var palette=FloatBuffer.allocate(remapped.length*16);
        var otherActor=FloatBuffer.allocate(remapped.length*16);
        var shaderPalette=new org.lwjgl.util.vector.Matrix4f[remapped.length];
        for(int i=0;i<remapped.length;i++) {
            var moving=new org.lwjgl.util.vector.Matrix4f();moving.m03=40+i;moving.m13=50+i;
            palette.position(i*16);moving.store(palette);shaderPalette[i]=new org.lwjgl.util.vector.Matrix4f(moving);
            otherActor.position(i*16);moving.store(otherActor);
        }
        float[] untouched=palette.array().clone();
        int[] nativeBones={0,2,5,6,7,8,9,10,11,12};
        for(float phase:new float[]{0,.25f,.5f}) for(float lean:new float[]{-.1f,0,.1f}) {
            for(int index:nativeBones) {
                var moving=new org.lwjgl.util.vector.Matrix4f();
                moving.rotate(phase,new org.lwjgl.util.vector.Vector3f(1,0,0));
                moving.m03=40+index+phase;moving.m13=50+index-phase;
                palette.position(index*16);moving.store(palette);shaderPalette[index].load(moving);
            }
            float[] nativePose=palette.array().clone();
            Matrix4f delta=new Matrix4f().translation(0,.008f,0).rotateZ(lean).translate(0,-.008f,0).translate(0,.12f,0);
            var poses=CartGrip.poses(clip,actor,delta);
            if(poses==null) throw new AssertionError("authored grip pose rejected");
            palette.position(5);
            int changed=CartGrip.skin(palette,shaderPalette,clothing,actor,poses);
            for(int index:nativeBones) {
                var expected=new org.lwjgl.util.vector.Matrix4f();
                var view=palette.duplicate();view.position(index*16);expected.load(view);
                for(int i=0;i<16;i++) if(palette.get(index*16+i)!=nativePose[index*16+i])
                    throw new AssertionError("native walking chain frozen: "+remapped[index]+" phase="+phase);
                if(!PZMath.convertMatrix(shaderPalette[index],new Matrix4f()).equals(PZMath.convertMatrix(expected,new Matrix4f())))
                    throw new AssertionError("native shader walking chain changed: "+remapped[index]);
            }
            if(changed!=3 || palette.position()!=5)
                throw new AssertionError("upper-body mapping or palette cursor changed");
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
        System.out.println("CART_GRIP_PASS (native skin order, remapped clothing, hands/handles, lean, native Spine/thigh hierarchy, changing leg phases, render isolation)");
    }
}
