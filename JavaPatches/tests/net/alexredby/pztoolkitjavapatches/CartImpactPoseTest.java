package net.alexredby.pztoolkitjavapatches;

import java.nio.FloatBuffer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import sun.misc.Unsafe;
import zombie.characters.IsoPlayer;
import zombie.core.math.PZMath;
import zombie.core.skinnedmodel.ModelManager;
import zombie.core.skinnedmodel.animation.AnimationPlayer;
import zombie.core.skinnedmodel.model.Model;
import zombie.core.skinnedmodel.model.ModelInstance;
import zombie.core.skinnedmodel.model.ModelInstanceRenderData;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;
import zombie.core.skinnedmodel.model.SkinningData;

public final class CartImpactPoseTest {
    private static Unsafe unsafe;
    private static final String[] NAMES={"Bip01_Spine","Bip01_R_Thigh","Bip01_R_Calf","Bip01_R_Foot","Bip01_R_Toe0","Bip01_Head"};
    private static <T>T allocate(Class<T> type)throws Exception{return type.cast(unsafe.allocateInstance(type));}
    private static void check(boolean value,String message){if(!value)throw new AssertionError(message);}
    private static void close(double actual,double expected,String message){check(Math.abs(actual-expected)<.00001,message+": "+actual+" != "+expected);}
    private static final class Player extends IsoPlayer {
        boolean worker;
        Player(){super(null,null,0,0,0);}
        @Override public boolean isLocalPlayer(){if(worker)throw new AssertionError("worker read actor state");return true;}
        @Override public boolean isCurrentState(zombie.ai.State state){if(worker)throw new AssertionError("worker read actor state");return false;}
    }
    private record Fixture(Player player,ModelManager.ModelSlot source,ModelSlotRenderData slot,
                           ModelInstanceRenderData body,ModelInstanceRenderData clothes,Matrix4f[] poses) {}

    private static Matrix4f[] poses() {
        return new Matrix4f[]{new Matrix4f().translation(.02f,.7f,0),new Matrix4f().translation(0,.5f,0).rotateZ(.1f),
            new Matrix4f().translation(0,.25f,.1f).rotateX(.3f),new Matrix4f().rotateY(.2f),
            new Matrix4f().translation(0,-.03f,.06f),new Matrix4f().translation(0,1,0)};
    }
    private static SkinningData skin(boolean remap) {
        var names=remap?new String[]{NAMES[5],NAMES[3],NAMES[2],NAMES[4],NAMES[0],NAMES[1]}:NAMES;
        var indices=new HashMap<String,Integer>();for(int i=0;i<names.length;i++)indices.put(names[i],i);
        var hierarchy=new ArrayList<Integer>();var offsets=new ArrayList<org.lwjgl.util.vector.Matrix4f>();
        for(int i=0;i<names.length;i++) {
            String name=names[i],parent=name.equals(NAMES[0])?null:name.equals(NAMES[2])?NAMES[1]:name.equals(NAMES[3])?NAMES[2]:name.equals(NAMES[4])?NAMES[3]:NAMES[0];
            hierarchy.add(parent==null?-1:indices.get(parent));
            offsets.add(PZMath.convertMatrix(new Matrix4f().translation(.02f*i,-.01f*i,.015f*i).rotateY(.06f*i).transpose(),new org.lwjgl.util.vector.Matrix4f()));
        }
        return new SkinningData(new HashMap<>(),offsets,offsets,offsets,hierarchy,indices);
    }
    private static ModelInstanceRenderData data(ModelInstance instance,SkinningData skin,Matrix4f[] poses)throws Exception {
        instance.model=allocate(Model.class);instance.model.tag=skin;
        var data=new ModelInstanceRenderData();data.modelInstance=instance;data.matrixPalette=FloatBuffer.allocate(NAMES.length*16);
        var shader=new org.lwjgl.util.vector.Matrix4f[NAMES.length];
        for(int i=0;i<NAMES.length;i++) {
            int index=skin.boneIndices.get(NAMES[i]);
            var raw=PZMath.convertMatrix(new Matrix4f(poses[i]).transpose(),new org.lwjgl.util.vector.Matrix4f());
            org.lwjgl.util.vector.Matrix4f.mul(skin.boneOffset.get(index),raw,raw);
            data.matrixPalette.position(index*16);raw.store(data.matrixPalette);shader[index]=new org.lwjgl.util.vector.Matrix4f(raw);
        }
        data.matrixPalette.position(7);data.properties.SetMatrix4Array("MatrixPalette",shader);return data;
    }
    private static Fixture fixture()throws Exception {
        var player=allocate(Player.class);player.setDescriptor(allocate(zombie.characters.SurvivorDesc.class));player.setFemale(false);
        var owner=new ModelInstance();owner.object=player;owner.animPlayer=allocate(AnimationPlayer.class);
        var poses=poses();var body=data(owner,skin(false),poses);var clothing=new ModelInstance();clothing.animPlayer=owner.animPlayer;
        var clothes=data(clothing,skin(true),poses);var slot=new ModelSlotRenderData();slot.character=player;slot.object=player;
        slot.modelData.add(body);slot.modelData.add(clothes);
        return new Fixture(player,new ModelManager.ModelSlot(0,owner,player),slot,body,clothes,poses);
    }
    private static Matrix4f decode(ModelInstanceRenderData data,String name) {
        var skin=(SkinningData)data.modelInstance.model.tag;int index=skin.boneIndices.get(name);
        var view=data.matrixPalette.duplicate();view.position(index*16);var raw=new org.lwjgl.util.vector.Matrix4f();raw.load(view);
        return PZMath.convertMatrix(raw,new Matrix4f()).transpose().mul(PZMath.convertMatrix(skin.boneOffset.get(index),new Matrix4f()).transpose().invert());
    }
    private static void envelope() {
        for(long age:new long[]{-1,0,450_000_000L,Long.MAX_VALUE})close(CartImpactPose.angle(age),0,"outside envelope");
        close(CartImpactPose.angle(60_000_000L),CartImpactPose.MAX_ANGLE/2,"smooth rise midpoint");
        close(CartImpactPose.angle(120_000_000L),CartImpactPose.MAX_ANGLE,"peak start");
        close(CartImpactPose.angle(280_000_000L),CartImpactPose.MAX_ANGLE,"peak end");
        close(CartImpactPose.angle(365_000_000L),CartImpactPose.MAX_ANGLE/2,"smooth fade midpoint");
        for(long age=0;age<=450_000_000L;age+=1_000_000L)check(CartImpactPose.angle(age)>=0 && CartImpactPose.angle(age)<=CartImpactPose.MAX_ANGLE,"unbounded envelope");
        for(long edge:new long[]{0,120_000_000L,280_000_000L,450_000_000L})
            check(Math.abs(CartImpactPose.angle(edge+1000)-CartImpactPose.angle(edge-1000))<.000001,"envelope edge discontinuity");
    }
    private static void geometry() {
        var poses=poses();var before=java.util.Arrays.stream(poses).map(Matrix4f::new).toArray(Matrix4f[]::new);
        var thigh=new Matrix4f();var calf=new Matrix4f();
        check(CartImpactPose.swivel(poses[1],poses[2],poses[3],CartImpactPose.MAX_ANGLE,thigh,calf),"valid swivel rejected");
        var hip=thigh.getTranslation(new Vector3f());var knee=calf.getTranslation(new Vector3f());var ankle=poses[3].getTranslation(new Vector3f());
        close(hip.distance(poses[1].getTranslation(new Vector3f())),0,"hip moved");
        close(hip.distance(knee),poses[1].getTranslation(new Vector3f()).distance(poses[2].getTranslation(new Vector3f())),"thigh stretched");
        close(knee.distance(ankle),poses[2].getTranslation(new Vector3f()).distance(ankle),"calf stretched");
        close(knee.x,-.1*Math.sin(CartImpactPose.MAX_ANGLE),"swivel sign changed");
        for(int i=0;i<poses.length;i++)check(poses[i].equals(before[i]),"native source pose changed");
        var global=new Matrix4f().translation(.2f,-.1f,.3f).rotateXYZ(.4f,-.7f,.2f);
        var rotatedThigh=new Matrix4f();var rotatedCalf=new Matrix4f();
        check(CartImpactPose.swivel(global.mul(poses[1],new Matrix4f()),global.mul(poses[2],new Matrix4f()),
            global.mul(poses[3],new Matrix4f()),CartImpactPose.MAX_ANGLE,rotatedThigh,rotatedCalf),"rotated leg rejected");
        check(rotatedThigh.equals(global.mul(thigh,new Matrix4f()),.00001f)
            && rotatedCalf.equals(global.mul(calf,new Matrix4f()),.00001f),"swivel depends on global pose axes");
        check(!CartImpactPose.swivel(poses[1],poses[2],poses[1],.05f,thigh,calf),"degenerate hip/ankle accepted");
        check(!CartImpactPose.swivel(poses[1],new Matrix4f().translation(0,.25f,0),poses[3],.05f,thigh,calf),"straight knee accepted");
        check(!CartImpactPose.swivel(poses[1],poses[2],poses[3],Float.NaN,thigh,calf),"NaN angle accepted");
    }
    private static void renderMapping()throws Exception {
        var f=fixture();var beforeBody=f.body.matrixPalette.array().clone();var beforeClothes=f.clothes.matrixPalette.array().clone();
        var expectedThigh=new Matrix4f();var expectedCalf=new Matrix4f();
        CartImpactPose.swivel(f.poses[1],f.poses[2],f.poses[3],CartImpactPose.MAX_ANGLE,expectedThigh,expectedCalf);
        CartImpactPose.capture(f.slot,f.source,200_000_000L);f.player.worker=true;CartImpactPose.render(f.slot);
        for(var data:List.of(f.body,f.clothes)) {
            var skin=(SkinningData)data.modelInstance.model.tag;
            check(data.matrixPalette.position()==7,"palette cursor changed");
            var shader=(org.lwjgl.util.vector.Matrix4f[])data.properties.GetParameter("MatrixPalette").GetValue();
            for(int i=0;i<NAMES.length;i++) {
                var expected=i==1?expectedThigh:i==2?expectedCalf:f.poses[i];
                check(decode(data,NAMES[i]).equals(expected,.00001f),"remapped render pose differs: "+NAMES[i]);
                int index=skin.boneIndices.get(NAMES[i]);var raw=new org.lwjgl.util.vector.Matrix4f();var view=data.matrixPalette.duplicate();view.position(index*16);raw.load(view);
                check(PZMath.convertMatrix(shader[index],new Matrix4f()).equals(PZMath.convertMatrix(raw,new Matrix4f())),"shader and buffer disagree");
                if(i!=1 && i!=2)for(int v=0;v<16;v++)check(Float.floatToIntBits(data.matrixPalette.get(index*16+v))==Float.floatToIntBits((data==f.body?beforeBody:beforeClothes)[index*16+v]),"unrelated bone changed");
            }
        }
        var once=f.body.matrixPalette.array().clone();CartImpactPose.render(f.slot);
        check(java.util.Arrays.equals(once,f.body.matrixPalette.array()),"render accumulated swivel on reused slot");
    }
    private static void fallbackAndLifetime()throws Exception {
        for(int bad=0;bad<10;bad++) {
            var f=fixture();CartImpactPose.capture(f.slot,f.source,200_000_000L);
            switch(bad) {
                case 0 -> CartImpactPose.release(f.slot);
                case 1 -> {f.player.setFemale(true);CartImpactPose.capture(f.slot,f.source,200_000_000L);}
                case 2 -> CartImpactPose.capture(f.slot,f.source,-1);
                case 3 -> CartImpactPose.capture(f.slot,null,200_000_000L);
                case 4 -> f.source.model.model=allocate(Model.class);
                case 5 -> ((SkinningData)f.clothes.modelInstance.model.tag).boneIndices.remove(NAMES[2]);
                case 6 -> f.clothes.matrixPalette=f.clothes.matrixPalette.asReadOnlyBuffer();
                case 7 -> f.clothes.properties.SetFloat("MatrixPalette",1);
                case 8 -> f.body.matrixPalette.put(3*16,Float.NaN);
                case 9 -> f.slot.character=allocate(Player.class);
            }
            var before=f.body.matrixPalette.array().clone();CartImpactPose.render(f.slot);
            check(java.util.Arrays.equals(before,f.body.matrixPalette.array()),"invalid/expired slot changed body: "+bad);
            CartImpactPose.release(f.slot);
        }
        var f=fixture();var before=f.body.matrixPalette.array().clone();f.source.character=allocate(Player.class);
        CartImpactPose.capture(f.slot,f.source,200_000_000L);CartImpactPose.render(f.slot);
        check(java.util.Arrays.equals(before,f.body.matrixPalette.array()),"foreign source accepted");
    }
    public static void main(String[] args)throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        var field=Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);unsafe=(Unsafe)field.get(null);
        envelope();geometry();renderMapping();fallbackAndLifetime();
        System.out.println("CART_IMPACT_POSE_PASS (fixed hip/foot, rigid leg links, remapped clothes/shader palettes, envelope, slot lifecycle and atomic fallback)");
    }
}
