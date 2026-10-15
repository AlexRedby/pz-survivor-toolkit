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

    private static void checkNativeHandles() {
        // Read-only GPU/reference-pose capture on B42.21; expected centers come from actual handle geometry.
        String[] names={"Bip01_Spine","Bip01_L_UpperArm","Bip01_L_Forearm","Bip01_L_Hand","Bip01_L_Finger0","Bip01_L_Finger1","Bip01_R_UpperArm","Bip01_R_Forearm","Bip01_R_Hand","Bip01_R_Finger0","Bip01_R_Finger1","Bip01_L_Thigh","Bip01_R_Thigh"};
        float[][] nativePose={
            {1.4521669e-06f,0.9981916f,0.060114563f,0f,1.0000002f,-1.9386694e-06f,1.1680957e-07f,0f,2.0447396e-07f,0.060114548f,-0.99819183f,0f,-4.6785718e-07f,0.5619899f,0.010946241f,1f},
            {0.22074102f,-0.96914154f,-0.10972244f,0f,0.9438717f,0.24060604f,-0.2263077f,0f,0.245724f,-0.053608667f,0.9678573f,0f,0.099654004f,0.7496011f,0.037673183f,1f},
            {-0.23472725f,0.006653134f,-0.9720396f,0f,0.94387156f,0.24063396f,-0.22627845f,0f,0.2324011f,-0.97059363f,-0.06276309f,0f,0.12990883f,0.6167684f,0.022634603f,1f},
            {0.021503776f,-0.0014302081f,-0.9997688f,0f,0.99298733f,0.11630844f,0.021191625f,0f,0.11625216f,-0.9932127f,0.003921243f,0f,0.09773772f,0.6176799f,-0.110594966f,1f},
            {-0.46738097f,-0.27832007f,-0.8391033f,0f,0.7144472f,0.44011968f,-0.54393053f,0f,0.52069277f,-0.8537176f,-0.0068584834f,0f,0.07550589f,0.6151214f,-0.16876407f,1f},
            {0.037895966f,-0.5487234f,-0.8351459f,0f,0.99307954f,0.11365253f,-0.02961228f,0f,0.11116614f,-0.8282434f,0.5492327f,0f,0.099545844f,0.61752886f,-0.19481423f,1f},
            {-0.26295483f,-0.95945466f,-0.101500414f,0f,0.9419383f,-0.27806738f,0.18823288f,0f,-0.20882466f,-0.046110272f,0.9768661f,0f,-0.09930119f,0.7483584f,0.03767302f,1f},
            {0.19763497f,0.0060330657f,-0.980258f,0f,0.941936f,-0.27809924f,0.1881972f,0f,-0.2714733f,-0.96053404f,-0.060644936f,0f,-0.13534217f,0.61685395f,0.02376148f,1f},
            {-0.021503098f,-0.009127207f,-0.99972796f,0f,0.9929871f,-0.11647228f,-0.020294784f,0f,-0.11625524f,-0.99315256f,0.011567622f,0f,-0.10825461f,0.617681f,-0.11059443f,1f},
            {0.4673793f,-0.2847743f,-0.83693594f,0f,0.7144465f,-0.43592146f,0.54730225f,0f,-0.5206954f,-0.8537431f,-0.00028474675f,0f,-0.08602331f,0.6146745f,-0.16874194f,1f},
            {-0.037896737f,-0.55513775f,-0.8308956f,0f,0.9930795f,-0.11342328f,0.030486476f,0f,-0.111166954f,-0.82398903f,0.5555941f,0f,-0.11006309f,0.6169446f,-0.1945371f,1f},
            {0.11579696f,-0.99196726f,0.050919585f,0f,-0.9932541f,-0.11596133f,-0.000285426f,0f,0.006187858f,-0.05054301f,-0.998703f,0f,0.055224918f,0.51036054f,0.010862686f,1f},
            {-0.1157871f,-0.9919687f,0.050918005f,0f,-0.9932564f,0.1159451f,0.00014129901f,0f,-0.006043833f,-0.050558247f,-0.9987031f,0f,-0.055225775f,0.51036084f,0.010862409f,1f}};
        float[][] nativeCart={
            {-5.080325e-10f,-0.00022194229f,-0.0021531826f,0f,7.381783e-10f,0.0016076594f,-0.00016571165f,0f,0.104969054f,-6.051497e-08f,-1.0280073e-08f,0f,-0.0016536561f,0.0033783615f,-0.44702002f,1f},
            {76.5f,-4.1037783e-05f,-9.11952e-06f,0f,2.8023098e-05f,30.694286f,70.07218f,0f,-2.4333809e-05f,-70.07218f,30.694283f,-0f,-0.0060535767f,0.16740987f,-0.41188842f,1f},
            {0.0091743395f,-4.9214974e-09f,-1.0936676e-09f,0f,2.9182563e-09f,0.008403477f,-0.0036810448f,0f,3.3606993e-09f,0.003681045f,0.008403477f,0f,0.21714664f,0.25123572f,-0.8401939f,1f}};
        String[] models={"ShoppingCartModel","WheelbarrowWood","WheelbarrowMetal"};
        float[][] centers={{.083346f,.58887534f,-.18080575f,-.086654f},
            {.12570822f,.57380583f,-.13731986f,-.13781538f},
            {.14916556f,.61160583f,-.16874814f,-.14684275f}};
        var offsets=new ArrayList<org.lwjgl.util.vector.Matrix4f>();
        for(String name:names) offsets.add(new org.lwjgl.util.vector.Matrix4f());
        var actor=skeleton(names,List.of(-1,0,1,2,3,3,0,6,7,8,8,0,0),offsets);
        for(int model=0;model<models.length;model++) for(boolean female:new boolean[]{false,true})
            for(float lean:new float[]{-.1f,0,.1f})
            for(float phase:model==1?new float[]{-1,0,1}:new float[]{0}) {
            var delta=new Matrix4f().translation(.01f,.03f,0).rotateZ(lean);
            var pitched=new Matrix4f().set(nativeCart[model]);
            CartGrounding.lowerHandles(pitched,models[model]);
            var cart=delta.mul(pitched,new Matrix4f());
            if(model==1 && !CartGrounding.alignWood(cart.set(pitched),lean,delta))
                throw new AssertionError("native wooden cart grounding rejected");
            var poses=new Matrix4f[names.length];
            for(int i=0;i<poses.length;i++) {
                poses[i]=new Matrix4f().set(nativePose[i]);
                if(model!=1) delta.mul(poses[i],poses[i]);
            }
            var gait=new Matrix4f().translation(0,.006f*phase,0).rotateY(.04f*phase);
            for(var pose:poses) gait.mul(pose,pose);
            var nativeSpine=new Matrix4f(poses[0]);
            if(model==1) {
                var palette=FloatBuffer.allocate(names.length*16);
                for(var pose:poses) PZMath.convertMatrix(new Matrix4f(pose).transpose(),new org.lwjgl.util.vector.Matrix4f()).store(palette);
                var live=CartGrip.livePoses(actor,actor,palette,delta);
                if(live==null) throw new AssertionError("native wooden torso rejected");
                for(int i=0;i<11;i++) poses[i].set(live[i]);
                if(!poses[0].equals(nativeSpine,.00001f)) throw new AssertionError("wooden pelvis left native hip anchor");
                for(int upper:new int[]{1,6}) {
                    float old=new Matrix4f().set(nativePose[0]).getTranslation(new Vector3f())
                        .distance(new Matrix4f().set(nativePose[upper]).getTranslation(new Vector3f()));
                    float now=poses[0].getTranslation(new Vector3f()).distance(poses[upper].getTranslation(new Vector3f()));
                    if(Math.abs(old-now)>.00001f) throw new AssertionError("wooden torso length changed");
                }
            }
            var before=java.util.Arrays.stream(poses).map(Matrix4f::new).toArray(Matrix4f[]::new);
            var handleDelta=new Matrix4f(cart).mul(new Matrix4f().set(nativeCart[model]).invert());
            if(!CartGrip.grip(poses,actor,models[model],female,delta,cart))
                throw new AssertionError("native handles unreachable: "+models[model]+" female="+female+" bank="+lean+" phase="+phase);
            for(int side=0;side<2;side++) {
                int upper=side==0?1:6,forearm=upper+1,hand=upper+2;
                var shape=CartGrip.grasp(female,models[model]);
                var actual=poses[hand].transformPosition(new Vector3f(shape.palmX(),0,shape.palmDepth()));
                var c=centers[model];var expected=handleDelta.transformPosition(new Vector3f(side==0?c[0]:c[3],c[1],c[2]));
                if(actual.distance(expected)>.00002f) throw new AssertionError("grip missed measured mesh handle: "+models[model]);
                if(model>0) {
                    // Wooden hips stay native: judge arm posture against the actor's vertical, not the banked cart.
                    var inverseDelta=model==1?new Matrix4f():new Matrix4f(delta).invert();
                    var elbow=inverseDelta.transformPosition(poses[forearm].getTranslation(new Vector3f()));
                    var wrist=inverseDelta.transformPosition(poses[hand].getTranslation(new Vector3f()));
                    var shoulder=inverseDelta.transformPosition(poses[upper].getTranslation(new Vector3f()));
                    var forearmAxis=poses[hand].getTranslation(new Vector3f()).sub(poses[forearm].getTranslation(new Vector3f())).normalize();
                    var handAxis=poses[hand].transformDirection(new Vector3f(1,0,0)).normalize();
                    float bend=(float)Math.toDegrees(Math.acos(Math.max(-1,Math.min(1,forearmAxis.dot(handAxis)))));
                    var forearmPalm=poses[forearm].transformDirection(new Vector3f(0,0,1));
                    var handPalm=poses[hand].transformDirection(new Vector3f(0,0,1));
                    forearmPalm.fma(-forearmPalm.dot(forearmAxis),forearmAxis).normalize();
                    handPalm.fma(-handPalm.dot(forearmAxis),forearmAxis).normalize();
                    float roll=(float)Math.toDegrees(Math.acos(Math.max(-1,Math.min(1,forearmPalm.dot(handPalm)))));
                    float abduction=(float)Math.toDegrees(Math.atan2(Math.abs(elbow.x-shoulder.x),shoulder.y-elbow.y));
                    // A grounded wooden cart rolls its handles around the tire while the native pelvis stays put.
                    float forward=(float)Math.toDegrees(Math.atan2(elbow.z-wrist.z,elbow.y-wrist.y));
                    // Preserve reach through native shoulder bob instead of forcing almost straight elbows.
                    if(bend>(model==1?38:30) || roll>10 || abduction>(model==1?30:25)
                        || elbow.y>shoulder.y-(model==1?.11f:.12f)
                        || (model==1 ? forward<0 || forward>36 : elbow.z<wrist.z+.09f))
                        throw new AssertionError("unnatural arm/wrist: "+models[model]+" female="+female+" bank="+lean+" phase="+phase
                            +" bend="+bend+" roll="+roll+" abduction="+abduction+" forward="+forward);
                    var measuredAxis=model==1?new Vector3f(side==0?.13444453f:-.13444453f,.48467334f,.86430112f)
                        :new Vector3f(0,.4012329f,.9159761f);
                    handleDelta.transformDirection(measuredAxis).normalize();
                    float shaftAngle=(float)Math.toDegrees(Math.acos(Math.abs(handAxis.dot(measuredAxis))));
                    var palm=inverseDelta.transformDirection(poses[hand].transformDirection(new Vector3f(0,0,1))).normalize();
                    if(Math.abs(shaftAngle-(model==1?65:35))>1 || palm.x*(side==0?-1:1)<.9f || palm.y<.02f)
                        throw new AssertionError("shaft no longer crosses fingers or palm is not inward/up");
                }
                for(int[] link:new int[][]{{upper,forearm},{forearm,hand}}) {
                    float old=before[link[0]].getTranslation(new Vector3f()).distance(before[link[1]].getTranslation(new Vector3f()));
                    float now=poses[link[0]].getTranslation(new Vector3f()).distance(poses[link[1]].getTranslation(new Vector3f()));
                    if(Math.abs(old-now)>.00001f) throw new AssertionError("native arm length changed");
                }
                if(model==1) {
                    var shoulder=before[upper].getTranslation(new Vector3f());
                    var elbow=before[forearm].getTranslation(new Vector3f());
                    float length=shoulder.distance(elbow)+elbow.distance(before[hand].getTranslation(new Vector3f()));
                    if(length-shoulder.distance(poses[hand].getTranslation(new Vector3f()))<.005f)
                        throw new AssertionError("wooden grip has less than 5mm reach reserve");
                }
            }
            for(int i:new int[]{0,11,12}) if(!poses[i].equals(before[i])) throw new AssertionError("native thigh/torso pose changed");
        }
        if(CartGrip.handle("unknown",true,new Vector3f())) throw new AssertionError("unknown cart accepted");
    }

    private static void checkCapturedWoodGait() {
        // B42.21 pre-IK gait captures: failed male/female grips in both bank directions, including the final worst reach.
        int[] sequences={17148,17274,19338,19610};
        float[] banks={-0.0999981173f,0.00106326414f,-0.0999460947f,0.00058612529f};
        String[] names={"Bip01_Spine","Bip01_L_UpperArm","Bip01_L_Forearm","Bip01_L_Hand","Bip01_R_UpperArm","Bip01_R_Forearm","Bip01_R_Hand"};
        float[][][] nativePoses={
            { // 17148 male
                {-0.11888384f,0.94015837f,-0.31932732f,0f,0.9605267f,0.027432673f,-0.2768318f,0f,-0.25150537f,-0.33963323f,-0.9063086f,0f,-0.006235276f,0.5449088f,0.0035289347f,1f},
                {0.036779642f,-0.99164385f,0.12362647f,0f,0.8487476f,-0.03430172f,-0.5276798f,0f,0.52751184f,0.124335825f,0.84039587f,0f,0.104641914f,0.7323843f,-0.07820514f,1f},
                {-0.5283854f,-0.017019294f,-0.84883034f,0f,0.84876287f,-0.03426656f,-0.52765733f,0f,-0.020109028f,-0.99926466f,0.03255319f,0f,0.109682694f,0.5964676f,-0.061260387f,1f},
                {-0.34721488f,-0.036548745f,-0.93706983f,0f,0.93763095f,-0.031486377f,-0.3461958f,0f,-0.016854823f,-0.99883264f,0.045203745f,0f,0.03726203f,0.59413415f,-0.17760295f,1f},
                {-0.27336496f,-0.8935142f,0.35623646f,0f,0.9203595f,-0.35063013f,-0.17319556f,0f,0.27965972f,0.28052005f,0.91820455f,0f,-0.08886408f,0.7496022f,-0.018052157f,1f},
                {-0.19155002f,-0.017968383f,-0.9813188f,0f,0.92033696f,-0.35067424f,-0.17322573f,0f,-0.34101018f,-0.9363255f,0.08370858f,0f,-0.12633175f,0.62713534f,0.0307744f,1f},
                {-0.38780686f,-0.037783176f,-0.9209662f,0f,0.8930136f,-0.26290324f,-0.3652511f,0f,-0.22832435f,-0.9640825f,0.13569653f,0f,-0.15258649f,0.62467283f,-0.103726655f,1f}
            },
            { // 17274 male
                {0.062458593f,0.96455777f,-0.2563743f,0f,0.9903079f,-0.027966445f,0.13604352f,0f,0.1240519f,-0.2623866f,-0.956956f,0f,0.010893265f,0.55614334f,-0.0061778263f,1f},
                {0.123355605f,-0.9192064f,0.37395623f,0f,0.9909571f,0.13414583f,0.0028537475f,0f,-0.052787747f,0.37022266f,0.92744184f,0f,0.11953572f,0.74052507f,-0.02741612f,1f},
                {0.10368779f,-0.7519578f,-0.65100527f,0f,0.99095374f,0.13417049f,0.0028563738f,0f,0.08519758f,-0.64541274f,0.7590675f,0f,0.13644287f,0.6145369f,0.023839086f,1f},
                {0.14644681f,-0.82622486f,-0.54397196f,0f,0.7313391f,-0.2798537f,0.6219521f,0f,-0.66610503f,-0.48891142f,0.56326705f,0f,0.15065503f,0.5114719f,-0.065388545f,1f},
                {-0.26372778f,-0.9587913f,0.105677515f,0f,0.9085306f,-0.21009682f,0.36115262f,0f,-0.3240673f,0.19125725f,0.92649984f,0f,-0.07974493f,0.7539415f,-0.05374226f,1f},
                {0.3184206f,-0.21136265f,-0.9240864f,0f,0.9085324f,-0.21013716f,0.36112517f,0f,-0.27051315f,-0.9545519f,0.12511775f,0f,-0.11589185f,0.62252796f,-0.03925766f,1f},
                {0.13368095f,-0.18855466f,-0.9729224f,0f,0.97754335f,-0.13629027f,0.16072932f,0f,-0.16290617f,-0.9725601f,0.1661009f,0f,-0.07224916f,0.5935582f,-0.1659147f,1f}
            },
            { // 19338 female
                {-0.1179415f,0.9443835f,-0.30697063f,0f,0.9612056f,0.03094948f,-0.27409118f,0f,-0.24934635f,-0.32738864f,-0.91139686f,0f,-0.0070283893f,0.5454942f,0.0025529382f,1f},
                {0.032045245f,-0.9955731f,0.08817508f,0f,0.8489216f,-0.01943767f,-0.5281385f,0f,0.5275213f,0.09177884f,0.84455395f,0f,0.10432699f,0.7328631f,-0.074071206f,1f},
                {-0.5284703f,-0.031158857f,-0.8483642f,0f,0.8489362f,-0.019402727f,-0.5281162f,0f,-1.5944242e-05f,-0.9993095f,0.03671304f,0f,0.1087188f,0.59640783f,-0.061985433f,1f},
                {-0.34510332f,-0.0370291f,-0.9378202f,0f,0.93845624f,-0.027746812f,-0.34424415f,0f,-0.013285652f,-0.9989123f,0.044333294f,0f,0.036286544f,0.59213626f,-0.17826408f,1f},
                {-0.27501938f,-0.90405774f,0.32716987f,0f,0.922959f,-0.3435622f,-0.17351285f,0f,0.26926968f,0.25424588f,0.92889917f,0f,-0.08910142f,0.7506344f,-0.015346451f,1f},
                {-0.19730273f,-0.03514718f,-0.9797129f,0f,0.9229374f,-0.34360558f,-0.17354228f,0f,-0.33053514f,-0.93845415f,0.10023224f,0f,-0.12679578f,0.62672246f,0.029496223f,1f},
                {-0.38572627f,-0.038431667f,-0.9218128f,0f,0.89473647f,-0.2593198f,-0.3635865f,0f,-0.22507107f,-0.96502465f,0.13441212f,0f,-0.15383899f,0.62190545f,-0.1047848f,1f}
            },
            { // 19610 female
                {-0.096246004f,0.9375126f,-0.33437726f,0f,0.97380656f,0.01916256f,-0.22656941f,0f,-0.20600393f,-0.34742528f,-0.9148002f,0f,-0.0021287978f,0.5455567f,0.004319218f,1f},
                {0.19226225f,-0.9707336f,0.14390206f,0f,0.8692816f,0.10042189f,-0.48400652f,0f,0.45539072f,0.21814796f,0.8631493f,0f,0.08064566f,0.747892f,-0.07528164f,1f},
                {-0.4734494f,-0.11213207f,-0.87364453f,0f,0.8692897f,0.10045929f,-0.48398402f,0f,0.142034f,-0.988594f,0.049914017f,0f,0.10699723f,0.61484134f,-0.055557936f,1f},
                {-0.28717363f,-0.10258676f,-0.9523606f,0f,0.94689f,0.11974004f,-0.29842573f,0f,0.14464833f,-0.98748255f,0.06275335f,0f,0.042106327f,0.5994717f,-0.17530146f,1f},
                {-0.14151156f,-0.9226032f,0.35885748f,0f,0.973122f,-0.19617675f,-0.12061833f,0f,0.18168214f,0.3321432f,0.92556655f,0f,-0.115938336f,0.73362964f,-0.025159173f,1f},
                {-0.13452159f,-0.058935393f,-0.9891489f,0f,0.9731085f,-0.19622426f,-0.12064878f,0f,-0.18698394f,-0.9787789f,0.083746806f,0f,-0.13533394f,0.60717595f,0.024026707f,1f},
                {-0.32780418f,-0.11032137f,-0.9382745f,0f,0.9418359f,-0.116046675f,-0.31540096f,0f,-0.07408606f,-0.9870907f,0.14194486f,0f,-0.15377223f,0.5990983f,-0.11154771f,1f}
            }
        };
        var offsets=new ArrayList<org.lwjgl.util.vector.Matrix4f>();
        for(String name:names) offsets.add(new org.lwjgl.util.vector.Matrix4f());
        var actor=skeleton(names,List.of(-1,0,1,2,0,4,5),offsets);
        for(int frame=0;frame<nativePoses.length;frame++) {
            // Rebuild the attachment through production geometry so this checks future pitch/offset changes too.
            var cart=new Matrix4f().set(new float[]{76.5f,-4.1037783e-5f,-9.11952e-6f,0f,2.8023098e-5f,30.694286f,70.07218f,0f,
                -2.4333809e-5f,-70.07218f,30.694283f,0f,-.0060535767f,.16740987f,-.41188842f,1f});
            var delta=new Matrix4f();
            CartGrounding.lowerHandles(cart,"WheelbarrowWood");
            if(!CartGrounding.alignWood(cart,banks[frame],delta)) throw new AssertionError("captured wood grounding rejected");
            var poses=new Matrix4f[names.length];
            for(int i=0;i<poses.length;i++) poses[i]=new Matrix4f().set(nativePoses[frame][i]);
            var before=java.util.Arrays.stream(poses).map(Matrix4f::new).toArray(Matrix4f[]::new);
            boolean female=frame>=2;
            if(!CartGrip.grip(poses,actor,"WheelbarrowWood",female,delta,cart))
                throw new AssertionError("captured native wood grip unreachable: sequence="+sequences[frame]);
            for(int upper:new int[]{1,4}) {
                int forearm=upper+1,hand=upper+2;
                float length=before[upper].getTranslation(new Vector3f()).distance(before[forearm].getTranslation(new Vector3f()))
                    +before[forearm].getTranslation(new Vector3f()).distance(before[hand].getTranslation(new Vector3f()));
                float reserve=length-before[upper].getTranslation(new Vector3f()).distance(poses[hand].getTranslation(new Vector3f()));
                if(reserve<.005f) throw new AssertionError("captured native wood grip has less than 5mm reach reserve: sequence="
                    +sequences[frame]+" reserve="+reserve);
                var shape=CartGrip.grasp(female,"WheelbarrowWood");
                var actual=poses[hand].transformPosition(new Vector3f(shape.palmX(),0,shape.palmDepth()));
                var expected=new Vector3f();CartGrip.handle("WheelbarrowWood",upper==1,expected);cart.transformPosition(expected);
                if(actual.distance(expected)>.00002f) throw new AssertionError("captured native wood palm missed handle");
                for(int[] link:new int[][]{{upper,forearm},{forearm,hand}}) {
                    float old=before[link[0]].getTranslation(new Vector3f()).distance(before[link[1]].getTranslation(new Vector3f()));
                    float now=poses[link[0]].getTranslation(new Vector3f()).distance(poses[link[1]].getTranslation(new Vector3f()));
                    if(Math.abs(old-now)>.00001f) throw new AssertionError("captured native wood arm stretched");
                }
            }
            if(!poses[0].equals(before[0])) throw new AssertionError("captured native wood hip anchor changed");
        }
    }

    private static void checkMeshClearance(Matrix4f hand, Matrix4f finger, boolean female, String model) {
        // Actual weighted MaleBody/FemaleBody.x vertices, expressed in each bone's bind coordinates.
        float[][] palm=female?new float[][]{{0.0020998f,-0.0091214f,0.0071902f},{0.0014231f,-0.0076770f,-0.0063046f},{0.0016326f,0.0178379f,0.0075661f},{0.0020998f,-0.0091214f,0.0071902f},{0.0007937f,0.0184254f,-0.0038792f},{0.0283567f,0.0249755f,0.0133053f},{0.0616472f,-0.0226788f,0.0060821f},{0.0706890f,0.0282415f,0.0130508f},{0.0294907f,-0.0224944f,0.0138331f},{0.0747490f,0.0294749f,0.0043946f},{0.0312226f,0.0277455f,-0.0067923f},{0.0328328f,-0.0213634f,-0.0117772f},{0.0697984f,-0.0171041f,-0.0078210f},{0.0294907f,-0.0224944f,0.0138331f},{0.0697984f,-0.0171041f,-0.0078210f},{0.0730657f,-0.0277366f,0.0092307f},{0.0676227f,-0.0221999f,-0.0045658f},{0.0676227f,-0.0221999f,-0.0045658f}}
            :new float[][]{{-0.0047011f,-0.0166808f,0.0149844f},{-0.0062986f,-0.0140933f,-0.0107094f},{-0.0065602f,0.0228221f,0.0122680f},{-0.0047011f,-0.0166808f,0.0149844f},{-0.0061939f,0.0234710f,-0.0065123f},{0.0248656f,0.0219624f,0.0259086f},{0.0557897f,-0.0245963f,0.0030804f},{0.0605094f,0.0264435f,0.0156451f},{0.0267577f,-0.0275660f,0.0219811f},{0.0685401f,0.0286272f,-0.0024884f},{0.0240095f,0.0266243f,-0.0116279f},{0.0250810f,-0.0250940f,-0.0167333f},{0.0632623f,-0.0203972f,-0.0148921f},{0.0267577f,-0.0275660f,0.0219811f},{0.0632623f,-0.0203972f,-0.0148921f}};
        float[][] tips=female?new float[][]{{0.0403683f,-0.0188581f,-0.0047107f},{0.0255160f,0.0224891f,0.0088530f},{0.0370694f,-0.0205719f,0.0048154f},{0.0288193f,0.0237946f,0.0000331f},{0.0403683f,-0.0188581f,-0.0047107f},{0.0288193f,0.0237946f,0.0000331f}}
            :new float[][]{{0.0433459f,-0.0198121f,-0.0046032f},{0.0184177f,0.0220647f,0.0250893f},{0.0323905f,-0.0227227f,0.0142481f},{0.0292507f,0.0244001f,0.0064256f},{0.0433459f,-0.0198121f,-0.0046032f},{0.0292507f,0.0244001f,0.0064256f}};
        boolean wood="WheelbarrowWood".equals(model),wheel=wood || "WheelbarrowMetal".equals(model);
        var shape=CartGrip.grasp(female,model);
        var relative=new Matrix4f(hand).invert().mul(finger);
        for(int part=0;part<2;part++) {
            float closest=Float.POSITIVE_INFINITY;
            for(float[] vertex:part==0?palm:tips) {
                var point=new Vector3f(vertex[0],vertex[1],vertex[2]);
                if(part==1) relative.transformPosition(point);
                float x=point.x-shape.palmX(),z=point.z-shape.palmDepth();
                if(wheel) x=(wood?.9063078f:.5735200f)*x+(wood?.4226183f:.8191916f)*point.y;
                // Project the diagonal underhand grip into the measured shaft cross-section.
                float clearance=wood?Math.max(Math.abs(.9961947f*x-.08715574f*z)-.01579f,
                    Math.abs(.08715574f*x+.9961947f*z)-.0125f):(float)Math.hypot(x,z)-.0128f;
                closest=Math.min(closest,clearance);
            }
            if(closest<-.0025f || closest>.0025f)
                throw new AssertionError("mesh lost handle surface contact: part="+part+" female="+female+" wood="+wood+" clearance="+closest);
        }
    }

    private static void checkWoodThumb(Matrix4f hand, Matrix4f thumb, boolean female, String side) {
        // Native thumb vertices in bind coordinates; the right-hand mesh mirrors local Y.
        float[][] vertices=female?new float[][]{{.0065814f,.0081348f,-.0031218f},{.0161162f,-.0130958f,.0085766f},
            {.016562f,-.0098148f,-.006701f},{.0169611f,.002113f,.007204f},{.0337963f,.0062153f,.0009176f},
            {.0342135f,-.0059551f,-.0015731f},{.0347263f,-.0053323f,.0078769f},{.0369234f,.0037346f,.0088547f}}
            :new float[][]{{.0026303f,.0052141f,-.0097699f},{.0117025f,-.0146732f,-.0140302f},
            {.0161775f,-.0020761f,.0094413f},{.0165286f,-.0198129f,.0108953f},{.02937f,.0045533f,-.006813f},
            {.0304491f,-.0101035f,-.0091006f},{.0312257f,-.0092361f,.0025076f},{.0333949f,.0017564f,.0030381f}};
        var local=new Matrix4f(hand).invert().mul(thumb);
        var shape=CartGrip.grasp(female,"WheelbarrowWood");
        float mirror="L".equals(side)?1:-1,closest=Float.POSITIVE_INFINITY;
        for(var vertex:vertices) {
            var point=local.transformPosition(new Vector3f(vertex[0],mirror*vertex[1],vertex[2]));
            float x=.9063078f*(point.x-shape.palmX())+.4226183f*mirror*point.y,z=point.z-shape.palmDepth();
            closest=Math.min(closest,Math.max(Math.abs(.9961947f*x-.08715574f*z)-.01579f,
                Math.abs(.08715574f*x+.9961947f*z)-.0125f));
        }
        if(Math.abs(closest)>.0025f) throw new AssertionError("wood thumb misses shaft surface: "+closest);
    }

    private static void checkFingers() {
        for(String side:new String[]{"L","R"}) for(boolean female:new boolean[]{false,true}) for(String model:new String[]{"ShoppingCartModel","WheelbarrowWood","WheelbarrowMetal"}) {
            String[] names={"Bip01_Spine","Bip01_"+side+"_Hand","Bip01_"+side+"_Finger0","Bip01_"+side+"_Finger1"};
            var offsets=new ArrayList<org.lwjgl.util.vector.Matrix4f>();
            for(String name:names) offsets.add(new org.lwjgl.util.vector.Matrix4f());
            var actor=skeleton(names,List.of(-1,0,1,1),offsets);
            var hand=new Matrix4f().translation(.14f,.6f,-.15f).rotateZ(.1f).rotateY(.5f);
            float sign="L".equals(side)?-1:1;
            // Native MaleBody/FemaleBody.x inverse-binds: these knuckles coincide in both meshes.
            Matrix4f[] poses={new Matrix4f(),hand,new Matrix4f(hand).translate(.0576815f,sign*.023606f,-.000272f),
                new Matrix4f(hand).translate(.084102f,0,0).rotateY(-.1444f)};
            poses[2].m00(.82926f).m01(sign*.51426f).m02(.21881f)
                .m10(-sign*.55854f).m11(.74910f).m12(sign*.35621f)
                .m20(.01927f).m21(-sign*.41760f).m22(.90843f);
            // The measured thumb basis is relative to the palm, including its native twist.
            var thumbLocal=new Matrix4f(poses[2]).setTranslation(.0576815f,sign*.023606f,-.000272f);
            hand.mul(thumbLocal,poses[2]);
            var fingerKnuckle=poses[3].getTranslation(new Vector3f());
            var thumbKnuckle=poses[2].getTranslation(new Vector3f());
            var shape=CartGrip.grasp(female,model);
            boolean underhand=model.startsWith("Wheelbarrow");
            CartGrip.closeFingers(poses,actor,side,shape,underhand);
            checkMeshClearance(hand,poses[3],female,model);
            if(model.equals("WheelbarrowWood")) checkWoodThumb(hand,poses[2],female,side);
            if(poses[3].getTranslation(new Vector3f()).distance(fingerKnuckle)>.000001f
                || poses[2].getTranslation(new Vector3f()).distance(thumbKnuckle)>.000001f)
                throw new AssertionError("finger closure moved a knuckle");
            // Independent mesh measurements: centroids of vertices weighted to each native finger.
            var fingerVertex=female?new Vector3f(.0334934f,-sign*.001965f,.0007189f)
                :new Vector3f(.0326669f,-sign*.0014197f,.0071637f);
            var thumbVertex=female?new Vector3f(.0247165f,sign*.0018487f,.00267f)
                :new Vector3f(.0216679f,sign*.0056741f,-.0020086f);
            var inverse=new Matrix4f(hand).invert();
            var finger=inverse.transformPosition(poses[3].transformPosition(fingerVertex));
            var thumb=inverse.transformPosition(poses[2].transformPosition(thumbVertex));
            float depth=shape.palmDepth();
            float radial=(float)Math.hypot(finger.x-shape.palmX(),finger.z-depth);
            if(radial<.01f || radial>.04f || finger.x<=shape.palmX() || (!underhand && thumb.x>=shape.palmX()+.005f))
                throw new AssertionError("native finger meshes do not enclose the grip: female="+female+" side="+side);
            if(underhand) {
                var thumbAxis=new Matrix4f(hand).invert().mul(poses[2]).transformDirection(new Vector3f(1,0,0)).normalize();
                var shaft=model.equals("WheelbarrowWood")?new Vector3f(.4226183f,sign*.9063078f,0)
                    :new Vector3f(.8191916f,sign*.5735200f,0);
                if(thumbAxis.dot(shaft)<.95f)
                    throw new AssertionError("underhand thumb does not follow the shaft");
            }
            var palette=FloatBuffer.allocate(names.length*16);
            var shader=new org.lwjgl.util.vector.Matrix4f[names.length];
            if(CartGrip.skin(palette,shader,actor,actor,poses)!=names.length) throw new AssertionError("finger palette not updated");
            for(int i=0;i<names.length;i++) {
                var raw=new org.lwjgl.util.vector.Matrix4f();var view=palette.duplicate();view.position(i*16);raw.load(view);
                if(!PZMath.convertMatrix(raw,new Matrix4f()).transpose().equals(poses[i],.00001f)
                    || !PZMath.convertMatrix(shader[i],new Matrix4f()).equals(PZMath.convertMatrix(raw,new Matrix4f())))
                    throw new AssertionError("body/clothing finger palette disagrees");
            }
        }
    }

    private static void checkReach() {
        String[] names={"Bip01_Spine","Bip01_L_UpperArm","Bip01_L_Forearm","Bip01_L_Hand",
            "Bip01_L_Finger1","Bip01_L_Thigh","Bip01_L_Calf"};
        var offsets=new ArrayList<org.lwjgl.util.vector.Matrix4f>();
        for(String name:names) offsets.add(new org.lwjgl.util.vector.Matrix4f());
        var actor=skeleton(names,List.of(-1,0,1,2,3,0,5),offsets);
        for(float lean:new float[]{-.1f,0,.1f}) {
            var delta=new Matrix4f().translation(0,.03f,0).rotateZ(lean);
            Matrix4f[] poses={new Matrix4f().translation(0,.5f,0),new Matrix4f().translation(.10f,.75f,.04f),
                new Matrix4f().translation(.13f,.62f,.02f),new Matrix4f().translation(.10f,.62f,-.11f),
                new Matrix4f().translation(.10f,.62f,-.16f),new Matrix4f().translation(.08f,.4f,0),
                new Matrix4f().translation(.08f,.2f,.04f)};
            for(var pose:poses) delta.mul(pose,pose);
            var before=java.util.Arrays.stream(poses).map(Matrix4f::new).toArray(Matrix4f[]::new);
            float upper=poses[1].getTranslation(new Vector3f()).distance(poses[2].getTranslation(new Vector3f()));
            float lower=poses[2].getTranslation(new Vector3f()).distance(poses[3].getTranslation(new Vector3f()));
            var relative=new Matrix4f(poses[3]).invert().mul(poses[4]);
            var goal=delta.mul(new Matrix4f().translation(.15f,.58f,-.13f).rotateY(.3f),new Matrix4f());
            if(!CartGrip.reach(poses,actor,"Bip01_L_Hand",goal,null,false)) throw new AssertionError("reachable grip rejected");
            if(!poses[3].equals(goal,.00001f)) throw new AssertionError("palm missed independent target");
            if(Math.abs(upper-poses[1].getTranslation(new Vector3f()).distance(poses[2].getTranslation(new Vector3f())))>.00001f
                || Math.abs(lower-poses[2].getTranslation(new Vector3f()).distance(poses[3].getTranslation(new Vector3f())))>.00001f)
                throw new AssertionError("reach stretched an arm link");
            if(!new Matrix4f(poses[3]).invert().mul(poses[4]).equals(relative,.00001f))
                throw new AssertionError("reach detached finger from hand");
            for(int i:new int[]{0,5,6}) if(!poses[i].equals(before[i])) throw new AssertionError("reach changed native torso/leg");
            before=java.util.Arrays.stream(poses).map(Matrix4f::new).toArray(Matrix4f[]::new);
            if(CartGrip.reach(poses,actor,"Bip01_L_Hand",new Matrix4f().translation(5,5,5),null,false))
                throw new AssertionError("unreachable target accepted");
            for(int i=0;i<poses.length;i++) if(!poses[i].equals(before[i])) throw new AssertionError("failed reach changed poses");
        }
    }

    private static void checkLivePoses() {
        String[] names={"Bip01_Spine","Bip01_Spine1","Bip01_L_Clavicle","Bip01_L_Hand",
            "Bip01_R_Hand","Bip01_Head","Bip01_L_Thigh"};
        var offsets=new ArrayList<org.lwjgl.util.vector.Matrix4f>();
        for(String name:names) offsets.add(new org.lwjgl.util.vector.Matrix4f());
        var actor=skeleton(names,List.of(-1,0,1,2,1,1,0),offsets);
        String[] remapped={names[6],names[3],names[5],names[1],names[0],names[4],names[2]};
        offsets=new ArrayList<>();
        for(int i=0;i<names.length;i++) offsets.add(PZMath.convertMatrix(
            new Matrix4f().translation(.1f*i,-.03f*i,.02f*i).rotateY(.07f*i).transpose(),
            new org.lwjgl.util.vector.Matrix4f()));
        var body=skeleton(remapped,java.util.Collections.nCopies(names.length,-1),offsets);
        var palette=FloatBuffer.allocate(names.length*16);
        for(float phase:new float[]{-.5f,0,.5f}) for(float bank:new float[]{-.5f,-.18f,0,.18f,.5f}) {
            var expected=new Matrix4f[names.length];
            for(int i=0;i<names.length;i++) {
                expected[i]=new Matrix4f().translation(.02f*i,.5f+.01f*phase,-.03f*i).rotateZ(.05f*phase*i);
                int index=body.boneIndices.get(names[i]);
                var raw=PZMath.convertMatrix(new Matrix4f(expected[i]).transpose(),new org.lwjgl.util.vector.Matrix4f());
                org.lwjgl.util.vector.Matrix4f.mul(body.boneOffset.get(index),raw,raw);
                palette.position(index*16);raw.store(palette);
            }
            float[] before=palette.array().clone();palette.position(7);
            var delta=new Matrix4f().translation(.07f,.025f,-.03f).rotateZ(bank);
            var actual=CartGrip.livePoses(actor,body,palette,delta);
            if(actual==null) throw new AssertionError("live upper body rejected");
            if(!actual[0].equals(expected[0],.00001f)) throw new AssertionError("native hip anchor changed");
            for(int i=1;i<names.length-1;i++) {
                var base=expected[0].getTranslation(new Vector3f());
                float old=expected[i].getTranslation(new Vector3f()).distance(base);
                float now=actual[i].getTranslation(new Vector3f()).distance(base);
                if(Math.abs(old-now)>.00001f) throw new AssertionError("torso detached or stretched: "+names[i]);
                var parent=actor.getBoneAt(i).parent;
                if(parent.index!=0 && !new Matrix4f(actual[parent.index]).invert().mul(actual[i])
                    .equals(new Matrix4f(expected[parent.index]).invert().mul(expected[i]),.00001f))
                    throw new AssertionError("native torso/shoulder motion lost: "+names[i]);
                var response=new Matrix4f(actual[i]).mul(new Matrix4f(expected[i]).invert());
                float angle=(float)Math.atan2(response.m01(),response.m00());
                if(Math.abs(angle)>.17454f || angle*bank<0 || (bank!=0 && Math.abs(angle)<.0001f)
                    || (bank==0 && !actual[i].equals(expected[i],.00001f)))
                    throw new AssertionError("torso bank is unbounded or does not return to native gait");
            }
            if(palette.position()!=7 || !java.util.Arrays.equals(palette.array(),before))
                throw new AssertionError("live pose capture changed the native palette");
            var clothing=FloatBuffer.wrap(before.clone());clothing.position(7);
            var shader=new org.lwjgl.util.vector.Matrix4f[names.length];
            if(CartGrip.skin(clothing,shader,body,actor,actual)!=names.length-1 || clothing.position()!=7)
                throw new AssertionError("live clothing mapping/cursor changed");
            for(int i=0;i<names.length;i++) {
                int index=body.boneIndices.get(names[i]);
                if(i==names.length-1) {
                    for(int value=0;value<16;value++) if(clothing.get(index*16+value)!=before[index*16+value])
                        throw new AssertionError("live clothing changed native thigh gait");
                    continue;
                }
                var raw=new org.lwjgl.util.vector.Matrix4f();var view=clothing.duplicate();view.position(index*16);raw.load(view);
                var decoded=PZMath.convertMatrix(raw,new Matrix4f()).transpose()
                    .mul(PZMath.convertMatrix(body.boneOffset.get(index),new Matrix4f()).transpose().invert());
                if(!decoded.equals(actual[i],.00001f)
                    || !PZMath.convertMatrix(shader[index],new Matrix4f()).equals(PZMath.convertMatrix(raw,new Matrix4f())))
                    throw new AssertionError("live remapped clothing pose disagrees: "+names[i]);
            }
        }
        palette.limit(16);
        if(CartGrip.livePoses(actor,body,palette,new Matrix4f())!=null || palette.position()!=7)
            throw new AssertionError("truncated live palette accepted or cursor changed");
        palette.limit(palette.capacity());palette.put(body.boneIndices.get(names[0])*16,Float.NaN);
        if(CartGrip.livePoses(actor,body,palette,new Matrix4f())!=null)
            throw new AssertionError("non-finite live pose accepted");
    }

    public static void main(String[] args) {
        checkReach();
        checkFingers();
        checkNativeHandles();
        checkCapturedWoodGait();
        checkLivePoses();
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
        System.out.println("CART_GRIP_PASS (live wooden torso/shoulders, anchored gait grip, natural arms/wrists, measured mesh contact, clothing, bank, walking legs, render isolation)");
    }
}
