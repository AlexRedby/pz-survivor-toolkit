package net.alexredby.pztoolkitjavapatches;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import zombie.core.skinnedmodel.model.SkinningData;

/** Sampled native skin contacts, not a claim of complete hand-surface clearance. */
public final class CartMetalGripSurfaceChecks {
    // Native metal VBO SHA-256: 34c9a265bfacdd9235f9094fc7ae158fe5a50d73d6d12b0acc73e007dbecd932.
    // Exact convex XY hulls at native Z52.2465,79.96424,85.63253 are identical.
    // MaleBody.x/FemaleBody.x anchors below each have weight 1 to their named bone.
    // Relative thumb/finger transforms are retained native05 Bob_Cart_Idle full-closure captures.
    // Both sides are measured independently: native right vertices are not assumed mirror copies.
    private static final float SCALE=.0091743395f, Z_MIN=52.2465f, Z_MAX=85.63253f;
    private record Fixture(boolean female, boolean left, int[] sourceVertices, float[][] anchors,
        float[] thumb, float[] finger) {}
    private static final Fixture[] FIXTURES={
        new Fixture(false,true,new int[]{120,163,114},
            new float[][]{{0.0248655972f,0.0219624383f,0.0259085603f},{0.0161775236f,-0.00207611396f,0.009441343f},{0.0323905422f,-0.0227226705f,0.0142481388f}},
            new float[]{0.829255161f,-0.514256197f,0.218806646f,0f,0.558537616f,0.749099525f,-0.356209638f,0f,0.0192748753f,0.417600422f,0.908426128f,0f,0.0576812932f,-0.0236050595f,-0.000272059844f,1f},
            new float[]{-0.22720201f,2.14030522e-07f,0.973847797f,0f,8.44464701e-08f,1.00000002f,-9.97432159e-08f,0f,-0.973847525f,-9.19504561e-09f,-0.227201846f,0f,0.0841022462f,8.30295613e-08f,-3.88431582e-08f,1f}),
        new Fixture(false,false,new int[]{426,469,421},
            new float[][]{{0.0248654113f,-0.0219636051f,0.0259086222f},{0.016177068f,0.00207526418f,0.00944178837f},{0.0323904862f,0.0227212461f,0.0142481574f}},
            new float[]{0.829255579f,0.514254922f,0.218806972f,0f,-0.558536677f,0.749100569f,0.356209029f,0f,0.019273795f,-0.417600137f,0.908426338f,0f,0.0576811166f,0.0236049754f,-0.000271883361f,1f},
            new float[]{-0.227201808f,3.5111047e-08f,0.973847617f,0f,-1.21396522e-07f,0.999999737f,-5.88983684e-08f,0f,-0.973847475f,-4.35063133e-08f,-0.227201846f,0f,0.0841019506f,1.55192061e-09f,-1.28338219e-07f,1f}),
        new Fixture(true,true,new int[]{120,116,114},
            new float[][]{{0.0283566602f,0.0249755458f,0.0133052719f},{0.0347263407f,-0.00533228179f,0.00787691337f},{0.0370693842f,-0.020571923f,0.00481536993f}},
            new float[]{0.829255431f,-0.514256361f,0.218806802f,0f,0.55853781f,0.749099886f,-0.356209661f,0f,0.0192749862f,0.41760045f,0.90842647f,0f,0.0576811864f,-0.0236051224f,-0.000272386438f,1f},
            new float[]{-0.22720201f,-1.898622e-08f,0.973848124f,0f,1.75182754e-07f,1.00000042f,-3.92200822e-08f,0f,-0.973847775f,-3.94408664e-08f,-0.227201989f,0f,0.0841022514f,1.22849676e-07f,-1.49904575e-07f,1f}),
        new Fixture(true,false,new int[]{432,428,427},
            new float[][]{{0.0283568083f,-0.0249765973f,0.0133062246f},{0.0347258987f,0.00533139683f,0.00787735552f},{0.0370263531f,0.0205712974f,0.00483524991f}},
            new float[]{0.829255432f,0.514254776f,0.218807086f,0f,-0.558536687f,0.749100467f,0.356208798f,0f,0.019273591f,-0.417600167f,0.908426135f,0f,0.0576809468f,0.0236050556f,-0.000272091651f,1f},
            new float[]{-0.227202056f,-9.39715673e-08f,0.973847733f,0f,-7.10728224e-08f,1.00000017f,-4.23585983e-09f,0f,-0.973847817f,-1.94040963e-08f,-0.227201953f,0f,0.0841020863f,1.97902718e-08f,-3.67174449e-07f,1f})
    };
    private static final float[][][] RINGS={
        {{-8.67226982f,6.4516654f},{-8.65624714f,6.37006903f},{-8.58681774f,6.02291441f},{-8.55081272f,5.95542812f},{-8.38588619f,5.65220499f},{-8.33470726f,5.6037178f},{-8.08914185f,5.37566042f},{-8.02809429f,5.34911442f},{-7.72563124f,5.22034073f},{-7.66006804f,5.21708584f},{-7.33093166f,5.20140171f},{-6.94369221f,5.32065773f},{-6.60181332f,5.56652308f},{-6.33875656f,5.91496086f},{-6.18027353f,6.33196402f},{-6.14188528f,6.77673674f},{-6.15928078f,6.86530399f},{-6.22733974f,7.20569706f},{-6.26986933f,7.28545189f},{-6.42828417f,7.57688904f},{-6.49302292f,7.63822126f},{-6.72503281f,7.85388041f},{-6.80587673f,7.88905621f},{-7.08854723f,8.00949001f},{-7.17695522f,8.0138607f},{-7.48323488f,8.02847195f},{-7.87047291f,7.90891504f},{-8.21234989f,7.66260338f},{-8.47540951f,7.31366873f},{-8.63388062f,6.89641237f}},
        {{-40.9428253f,6.77673674f},{-40.9044151f,6.33196402f},{-40.7459526f,5.91496086f},{-40.4828873f,5.56652308f},{-40.141037f,5.32065773f},{-39.7537346f,5.20140171f},{-39.424633f,5.21708584f},{-39.3590775f,5.22034073f},{-39.0566216f,5.34911442f},{-38.9955711f,5.37566042f},{-38.7500153f,5.6037178f},{-38.6988525f,5.65220499f},{-38.5339279f,5.95542812f},{-38.4979134f,6.02291441f},{-38.4284821f,6.37006903f},{-38.4124565f,6.45166492f},{-38.4124565f,6.4516654f},{-38.4508095f,6.89641237f},{-38.6093216f,7.31366873f},{-38.8723068f,7.66260338f},{-39.2142334f,7.90891504f},{-39.6014557f,8.02847195f},{-39.9077072f,8.0138607f},{-39.9961014f,8.00949001f},{-40.2788429f,7.88905621f},{-40.3596954f,7.85388041f},{-40.5916901f,7.63822174f},{-40.6564369f,7.57688904f},{-40.8148422f,7.28545189f},{-40.8573608f,7.20569706f},{-40.9254265f,6.86530399f}}
    };

    private static SkinningData actor(String side) {
        String[] names={"Bip01_Spine","Bip01_"+side+"_Hand","Bip01_"+side+"_Finger0","Bip01_"+side+"_Finger1"};
        var indices=new HashMap<String,Integer>();
        var offsets=new ArrayList<org.lwjgl.util.vector.Matrix4f>();
        for(int i=0;i<names.length;i++) {indices.put(names[i],i);offsets.add(new org.lwjgl.util.vector.Matrix4f());}
        return new SkinningData(new HashMap<>(),offsets,offsets,offsets,List.of(-1,0,1,1),indices);
    }

    // Independent finite native shaft, with outward convex face distances in actor units.
    private static float gap(Vector3f raw, int side) {
        float value=Math.max((Z_MIN-raw.z)*SCALE,(raw.z-Z_MAX)*SCALE);
        var ring=RINGS[side];
        for(int i=0;i<ring.length;i++) {
            var a=ring[i];var b=ring[(i+1)%ring.length];
            double dx=b[0]-a[0],dy=b[1]-a[1];
            value=Math.max(value,(float)(((raw.x-a[0])*dy-(raw.y-a[1])*dx)/Math.hypot(dx,dy)*SCALE));
        }
        return value;
    }

    public static void check() {
        // Translation and rotation exercise real target() in world coordinates, independent of its palm offset.
        var cart=new Matrix4f().translation(.13f,.24f,-.71f).rotateX(.4f).rotateZ(-.08f).scale(SCALE);
        var inverseCart=new Matrix4f(cart).invert();
        for(var f:FIXTURES) {
            String side=f.left?"L":"R";int sideIndex=f.left?0:1;
            var hand=new Matrix4f();
            if(!CartGrip.target("WheelbarrowMetal",f.left,f.female,new Matrix4f(),cart,hand))
                throw new AssertionError("metal target rejected");
            Matrix4f[] poses={new Matrix4f(),hand,new Matrix4f(hand).mul(new Matrix4f().set(f.thumb)),
                new Matrix4f(hand).mul(new Matrix4f().set(f.finger))};
            var thumbBefore=new Matrix4f(poses[2]);
            var fingerKnuckle=poses[3].getTranslation(new Vector3f());
            CartGrip.closeFingers(poses,actor(side),side,CartGrip.grasp(f.female,"WheelbarrowMetal"),true);
            if(!poses[2].equals(thumbBefore,.000002f)
                || poses[3].getTranslation(new Vector3f()).distance(fingerKnuckle)>.000002f)
                throw new AssertionError("metal closure moved native thumb or finger knuckle");
            var rawContacts=new Vector3f[3];
            for(int i=0;i<3;i++) {
                var a=f.anchors[i];
                var raw=inverseCart.transformPosition(poses[i+1].transformPosition(new Vector3f(a[0],a[1],a[2])));
                rawContacts[i]=raw;
                // The independent source point must contact the physical finite shaft, including the cap.
                float signed=gap(raw,sideIndex);
                if(Math.abs(signed)>.0025f || raw.z<Z_MIN || raw.z>Z_MAX)
                    throw new AssertionError("metal skin contact missed finite shaft: female="+f.female+" side="+side
                        +" bone="+i+" sourceVertex="+f.sourceVertices[i]+" gap="+signed+" rawZ="+raw.z);
            }
            // Finger mitten and thumb must oppose each other across the measured shaft, not lie along it.
            float cx=f.left?-7.409948f:-39.674755f,cy=6.614635f;
            var thumb=new Vector3f(rawContacts[1]).sub(cx,cy,rawContacts[1].z).normalize();
            var finger=new Vector3f(rawContacts[2]).sub(cx,cy,rawContacts[2].z).normalize();
            if(thumb.dot(finger)>-.25f) throw new AssertionError("metal thumb/fingers no longer oppose shaft");
            var handX=inverseCart.transformDirection(hand.transformDirection(new Vector3f(1,0,0))).normalize();
            if(Math.abs(handX.z)>.7072f || Math.abs(handX.z)<.342f)
                throw new AssertionError("metal shaft no longer crosses palm at 45..70 degrees");
        }
    }

    public static void main(String[] args) {check();System.out.println("CART_METAL_GRIP_SURFACE_PASS");}
}
