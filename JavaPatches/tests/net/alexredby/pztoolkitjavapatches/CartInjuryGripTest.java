package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import zombie.core.skinnedmodel.model.SkinningData;

/** Measured pre-IK failures from both sexes and injured sides, plus successful neighboring poses. */
public final class CartInjuryGripTest {
    private static final String[] NAMES={"Bip01_Spine","Bip01_Spine1","Bip01_L_Clavicle","Bip01_L_UpperArm",
        "Bip01_L_Forearm","Bip01_L_Hand","Bip01_R_Clavicle","Bip01_R_UpperArm","Bip01_R_Forearm","Bip01_R_Hand",
        "Bip01_L_Thigh","Bip01_L_Calf","Bip01_L_Foot","Bip01_R_Thigh","Bip01_R_Calf","Bip01_R_Foot"};

    private static SkinningData skeleton() {
        var indices=new HashMap<String,Integer>();var offsets=new ArrayList<org.lwjgl.util.vector.Matrix4f>();
        for(int i=0;i<NAMES.length;i++) {indices.put(NAMES[i],i);offsets.add(new org.lwjgl.util.vector.Matrix4f());}
        return new SkinningData(new HashMap<>(),offsets,offsets,offsets,List.of(-1,0,1,2,3,4,1,6,7,8,0,10,11,0,13,14),indices);
    }
    private static void check(boolean result,String message) {if(!result) throw new AssertionError(message);}
    private static void close(float actual,float expected,float tolerance,String message) {
        check(Float.isFinite(actual) && Math.abs(actual-expected)<tolerance,message+": "+actual+" != "+expected);
    }
    private static Matrix4f[] copy(Matrix4f[] source) {return Arrays.stream(source).map(Matrix4f::new).toArray(Matrix4f[]::new);}
    private static Matrix4f matrix(String[] values,int offset) {
        var data=new float[16];for(int i=0;i<16;i++) data[i]=Float.parseFloat(values[offset+i]);
        return new Matrix4f().set(data);
    }
    private static float link(Matrix4f[] poses,int a,int b) {
        return poses[a].getTranslation(new Vector3f()).distance(poses[b].getTranslation(new Vector3f()));
    }
    private static void lengths(Matrix4f[] actual,Matrix4f[] expected,String label) {
        for(int[] pair:new int[][]{{2,3},{3,4},{4,5},{6,7},{7,8},{8,9}})
            close(link(actual,pair[0],pair[1]),link(expected,pair[0],pair[1]),.00001f,label+" stretched arm/clavicle");
    }
    private static void unchanged(Matrix4f[] actual,Matrix4f[] expected,String label) {
        for(int i=0;i<actual.length;i++) check(actual[i].equals(expected[i]),label+" changed "+NAMES[i]);
    }

    private static void captured(String[] values,SkinningData actor,float bank) {
        String model=values.length>52+16*NAMES.length?values[52+16*NAMES.length]:"WheelbarrowWood";
        String label=model+" capture="+values[0]+" bank="+bank;
        boolean female=values[1].equals("1"),failed=values[3].equals("1");
        float weight=Float.parseFloat(values[2]),pressure=Math.abs(bank);
        var rotation=new Matrix4f().rotationZ(bank);
        var delta=rotation.mul(matrix(values,4),new Matrix4f());
        var cart=rotation.mul(matrix(values,20),new Matrix4f());
        var reference=delta.mul(matrix(values,36),new Matrix4f());
        var poses=new Matrix4f[NAMES.length];
        for(int i=0;i<poses.length;i++) poses[i]=rotation.mul(matrix(values,52+16*i),new Matrix4f());
        var before=copy(poses);var cartBefore=new Matrix4f(cart);var deltaBefore=new Matrix4f(delta);
        if(bank==0) check(CartGrip.grip(copy(poses),actor,model,female,delta,cart,pressure)!=failed,
            label+" no longer reproduces its measured original reach result");
        close(CartGrip.injuryTorso(poses,actor,female,delta,cart,pressure,0,reference,model),0,.000001f,label+" healthy ownership");
        unchanged(poses,before,label+" healthy injury correction");
        close(CartGrip.injuryTorso(poses,actor,female,delta,cart,pressure,weight,null,model),0,.000001f,label+" missing reference");
        unchanged(poses,before,label+" unavailable reference");
        close(CartGrip.injuryTorso(poses,actor,female,delta,cart,pressure,weight,reference,"ShoppingCartModel"),0,.000001f,label+" shopping scope");
        unchanged(poses,before,label+" shopping cart correction");
        boolean originallyReachable=CartGrip.grip(copy(poses),actor,model,female,delta,cart,pressure);
        float amount=CartGrip.injuryTorso(poses,actor,female,delta,cart,pressure,weight,reference,model);
        check(amount>=0 && amount<=1,label+" correction escaped its measured envelope");
        if(originallyReachable) {
            close(amount,0,.000001f,label+" corrected an already reachable pose");
            unchanged(poses,before,label+" unnecessary torso correction");
        } else check(amount>0,label+" could not fit the measured injury torso");
        for(int i:new int[]{0,10,11,12,13,14,15}) check(poses[i].equals(before[i]),label+" moved hip/native legs "+NAMES[i]);
        check(poses[1].m30()==before[1].m30() && poses[1].m31()==before[1].m31() && poses[1].m32()==before[1].m32(),label+" moved chest pivot");
        lengths(poses,before,label+" torso correction");
        check(cart.equals(cartBefore) && delta.equals(deltaBefore),label+" changed grounded cart");
        check(CartGrip.grip(poses,actor,model,female,delta,cart,pressure),label+" corrected pose still cannot reach both handles");
        lengths(poses,before,label+" IK");
        for(int i:new int[]{0,10,11,12,13,14,15}) check(poses[i].equals(before[i]),label+" IK changed native hip/legs");
        for(int side=0;side<2;side++) {
            var shape=CartGrip.grasp(female,model);
            var palm=poses[side==0?5:9].transformPosition(new Vector3f(shape.palmX(),0,shape.palmDepth()));
            var handle=new Vector3f();CartGrip.handle(model,side==0,handle);cart.transformPosition(handle);
            close(palm.distance(handle),0,.00002f,label+" palm missed handle");
        }
    }

    public static void main(String[] args) throws Exception {
        var fixture=args.length==0?Path.of(System.getProperty("pz.test.project"),"JavaPatches/tests/fixtures/cart-injury-grip.csv"):Path.of(args[0]);
        var actor=skeleton();int count=0;
        for(String line:Files.readAllLines(fixture)) if(!line.startsWith("#") && !line.isBlank()) {
            var values=line.split(",");check(values.length==52+16*NAMES.length || values.length==53+16*NAMES.length,"incomplete recorded injury fixture");
            for(float bank:new float[]{0,(float)Math.toRadians(-3),(float)Math.toRadians(3)}) captured(values,actor,bank);
            count++;
        }
        check(count==(args.length>1?Integer.parseInt(args[1]):26),"missing representative injury captures");
        check(CartGrip.injuryTorso(new Matrix4f[0],null,false,new Matrix4f(),new Matrix4f(),0,1,new Matrix4f(),"WheelbarrowWood")==0,
            "missing actor did not preserve the native fallback");
        System.out.println("CART_INJURY_GRIP_PASS");
    }
}
