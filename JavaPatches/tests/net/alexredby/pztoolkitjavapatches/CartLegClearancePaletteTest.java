package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.FloatBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.function.Consumer;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import sun.misc.Unsafe;
import zombie.core.math.PZMath;
import zombie.core.skinnedmodel.model.Model;
import zombie.core.skinnedmodel.model.ModelInstance;
import zombie.core.skinnedmodel.model.ModelInstanceRenderData;
import zombie.core.skinnedmodel.model.SkinningData;

/** Exercise the render-palette boundary independently of the geometric solver. */
public final class CartLegClearancePaletteTest {
    private static final String SPINE="Bip01_Spine", CHEST="Bip01_Spine1";
    private static final String THIGH="Bip01_L_Thigh", CALF="Bip01_L_Calf";
    private static final String[] ACTOR_NAMES={SPINE,CHEST,THIGH,CALF};
    private static final String[] TARGET_NAMES={CALF,SPINE,THIGH,CHEST};
    private static final CartLegClearanceData.Skin SOURCE=new CartLegClearanceData.Skin(
        "synthetic/source.x","synthetic",1,new String[]{CHEST,THIGH,CALF,SPINE},5,
        new int[]{0,1,2,3,3,4},new int[]{0,1,2,0,1,3},
        new float[]{1,2,-3,1, -2,.5f,4,1, .25f,-1,2,1,
                    .5f,-.25f,.125f,.25f, 1.5f,-.75f,.375f,.75f, .5f,.25f,-.75f,1},
        new int[]{0,1,2,1,3,4});
    private static final Class<?> SCRATCH;
    private static final Constructor<?> NEW_SCRATCH;
    private static final Method READ;
    private static final Field POINTS;
    private static final Unsafe UNSAFE;

    static {
        try {
            var unsafeField=Unsafe.class.getDeclaredField("theUnsafe");unsafeField.setAccessible(true);
            UNSAFE=(Unsafe)unsafeField.get(null);
            SCRATCH=Class.forName(CartLegClearance.class.getName()+"$Scratch");
            NEW_SCRATCH=SCRATCH.getDeclaredConstructor();NEW_SCRATCH.setAccessible(true);
            READ=CartLegClearance.class.getDeclaredMethod("skin",ModelInstanceRenderData.class,
                CartLegClearanceData.Skin.class,SCRATCH,SkinningData.class,Matrix4f[].class);
            READ.setAccessible(true);
            POINTS=SCRATCH.getDeclaredField("points");POINTS.setAccessible(true);
        } catch(ReflectiveOperationException unavailable) {
            throw new ExceptionInInitializerError(unavailable);
        }
    }

    private static SkinningData skeleton(String[] names,List<Integer> parents,
                                         List<org.lwjgl.util.vector.Matrix4f> offsets) {
        var indices=new HashMap<String,Integer>();
        for(int i=0;i<names.length;i++) indices.put(names[i],i);
        return new SkinningData(new HashMap<>(),offsets,offsets,offsets,parents,indices);
    }

    private static org.lwjgl.util.vector.Matrix4f nativeMatrix(Matrix4f matrix) {
        return PZMath.convertMatrix(new Matrix4f(matrix).transpose(),new org.lwjgl.util.vector.Matrix4f());
    }

    private static final class Fixture {
        final SkinningData actor,target;
        final ModelInstanceRenderData data=new ModelInstanceRenderData();
        final Matrix4f[] nativePoses={
            new Matrix4f().translation(-.2f,.45f,.02f).rotateY(.2f),
            new Matrix4f().translation(-.3f,.6f,.1f).rotateZ(-.1f),
            new Matrix4f().translation(.05f,.4f,.08f).rotateXYZ(.1f,-.3f,.2f),
            new Matrix4f().translation(.07f,.2f,-.06f).rotateXYZ(-.2f,.15f,.35f)
        };
        // Poisoned/absent lower poses must never override the native walking branches.
        final Matrix4f[] pending={new Matrix4f().translation(.04f,.5f,-.01f).rotateY(-.2f),
            new Matrix4f().translation(.1f,.7f,-.2f).rotateXYZ(.2f,.1f,.25f),
            null,new Matrix4f().translation(999,888,777)};
        final Object scratch;

        Fixture() throws ReflectiveOperationException {
            var identities=new ArrayList<org.lwjgl.util.vector.Matrix4f>();
            for(String ignored:ACTOR_NAMES) identities.add(new org.lwjgl.util.vector.Matrix4f());
            actor=skeleton(ACTOR_NAMES,List.of(-1,0,0,2),identities);
            var offsets=new ArrayList<org.lwjgl.util.vector.Matrix4f>();
            for(int i=0;i<TARGET_NAMES.length;i++) offsets.add(nativeMatrix(new Matrix4f()
                .translation(.11f*(i+1),-.07f*i,.03f*(i+2)).rotateXYZ(.1f*i,-.08f*i,.06f*i)
                .scale(1.2f,.8f,1.1f)));
            target=skeleton(TARGET_NAMES,List.of(2,-1,1,1),offsets);
            var instance=new ModelInstance();
            instance.model=(Model)UNSAFE.allocateInstance(Model.class);
            instance.model.tag=target;
            // No live AnimationPlayer is available: only this render slot owns the input pose.
            data.modelInstance=instance;data.matrixPalette=FloatBuffer.allocate(TARGET_NAMES.length*16);
            for(int i=0;i<ACTOR_NAMES.length;i++) slotPose(ACTOR_NAMES[i],nativePoses[i]);
            data.matrixPalette.position(7);
            scratch=NEW_SCRATCH.newInstance();
        }

        void slotPose(String name,Matrix4f pose) {
            int index=target.boneIndices.get(name);
            var bind=PZMath.convertMatrix(target.boneOffset.get(index),new Matrix4f()).transpose();
            var palette=data.matrixPalette;int before=palette.position();
            try {
                palette.position(index*16);nativeMatrix(new Matrix4f(pose).mul(bind)).store(palette);
            } finally {palette.position(before);}
        }

        boolean read() throws ReflectiveOperationException {
            var palette=data.matrixPalette;
            int position=palette==null?-1:palette.position(),limit=palette==null?-1:palette.limit();
            var bytes=palette==null?null:contents(palette);
            var pendingBefore=new float[pending.length][];
            for(int i=0;i<pending.length;i++) if(pending[i]!=null) pendingBefore[i]=pending[i].get(new float[16]);
            try {
                return (Boolean)READ.invoke(null,data,SOURCE,scratch,actor,pending);
            } catch(InvocationTargetException error) {
                throw new AssertionError("Unavailable render palette must be refused without throwing",error.getCause());
            } finally {
                if(palette!=null && (palette.position()!=position || palette.limit()!=limit
                    || !Arrays.equals(bytes,contents(palette))))
                    throw new AssertionError("Reader changed palette values, limit or position");
                for(int i=0;i<pending.length;i++) if(pending[i]!=null
                    && !Arrays.equals(pendingBefore[i],pending[i].get(new float[16])))
                    throw new AssertionError("Reader changed pending render poses");
            }
        }

        void expectPoints() throws ReflectiveOperationException {
            var chest=pending[1];var thigh=nativePoses[2];var calf=nativePoses[3];
            var expected=new Vector3f[]{
                chest.transformPosition(new Vector3f(1,2,-3)),
                thigh.transformPosition(new Vector3f(-2,.5f,4)),
                calf.transformPosition(new Vector3f(.25f,-1,2)),
                chest.transformPosition(new Vector3f(2,-1,.5f)).mul(.25f)
                    .add(thigh.transformPosition(new Vector3f(2,-1,.5f)).mul(.75f)),
                pending[0].transformPosition(new Vector3f(.5f,.25f,-.75f))
            };
            var actual=(double[])POINTS.get(scratch);
            for(int i=0;i<expected.length;i++) for(int axis=0;axis<3;axis++) {
                double value=actual[i*3+axis],wanted=expected[i].get(axis);
                if(!Double.isFinite(value) || Math.abs(value-wanted)>2e-5)
                    throw new AssertionError("Same-slot/pending pose mismatch at vertex "+i+" axis "+axis
                        +": "+value+" expected "+wanted);
            }
        }
    }

    private static float[] contents(FloatBuffer buffer) {
        var view=buffer.duplicate();view.clear();var values=new float[view.remaining()];view.get(values);return values;
    }

    private static void sameSlotAndPendingOwnership() throws ReflectiveOperationException {
        var fixture=new Fixture();
        if(!fixture.read()) throw new AssertionError("Valid remapped render palette refused");
        fixture.expectPoints();
        // A second slot can share the model and skeleton while carrying a newer native leg pose.
        var first=fixture.data.matrixPalette;
        var firstValues=contents(first);
        fixture.data.matrixPalette=FloatBuffer.wrap(firstValues.clone());fixture.data.matrixPalette.position(13);
        fixture.nativePoses[2].translation(.17f,.37f,-.03f).rotateY(.45f);
        fixture.nativePoses[3].translation(-.02f,.19f,.09f).rotateX(-.2f);
        fixture.slotPose(THIGH,fixture.nativePoses[2]);fixture.slotPose(CALF,fixture.nativePoses[3]);
        // Upper native motion is intentionally unrelated to the pending displayed upper pose.
        fixture.slotPose(CHEST,new Matrix4f().translation(-20,30,40).rotateZ(.8f));
        fixture.slotPose(SPINE,new Matrix4f().translation(50,-60,70));
        fixture.pending[2]=new Matrix4f().m00(Float.NaN);fixture.pending[3]=null;
        fixture.data.matrixPalette=fixture.data.matrixPalette.asReadOnlyBuffer();
        if(!fixture.read()) throw new AssertionError("Current read-only slot palette refused");
        fixture.expectPoints();
        if(first.position()!=7 || !Arrays.equals(firstValues,contents(first)))
            throw new AssertionError("Reading the newer slot changed another render slot");
        // Reusing scratch must clear previous accumulated points, including weighted mixed vertices.
        if(!fixture.read()) throw new AssertionError("Repeated same-slot read refused");
        fixture.expectPoints();
    }

    private static void unavailable(String label,Consumer<Fixture> mutation) throws ReflectiveOperationException {
        var fixture=new Fixture();mutation.accept(fixture);
        if(fixture.read()) throw new AssertionError("Accepted unavailable render data: "+label);
    }

    private static void unavailableInputs() throws ReflectiveOperationException {
        unavailable("missing target bone after an earlier bone was read",f->f.target.boneIndices.remove(THIGH));
        unavailable("negative palette index",f->f.target.boneIndices.put(THIGH,-1));
        unavailable("palette index outside limit",f->f.target.boneIndices.put(THIGH,100));
        unavailable("short palette",f->f.data.matrixPalette.limit(63));
        unavailable("missing palette",f->f.data.matrixPalette=null);
        unavailable("missing target SkinningData",f->f.data.modelInstance.model.tag=null);
        unavailable("missing inverse-bind offset",f->f.target.boneOffset.set(f.target.boneIndices.get(THIGH),null));
        unavailable("singular inverse-bind offset",f->f.target.boneOffset.set(f.target.boneIndices.get(THIGH),
            nativeMatrix(new Matrix4f().scaling(0,1,1))));
        unavailable("NaN inverse-bind offset",f->f.target.boneOffset.get(f.target.boneIndices.get(THIGH)).m13=Float.NaN);
        unavailable("infinite inverse-bind offset",f->f.target.boneOffset.get(f.target.boneIndices.get(THIGH)).m21=Float.POSITIVE_INFINITY);
        unavailable("NaN native palette",f->f.data.matrixPalette.put(f.target.boneIndices.get(THIGH)*16,Float.NaN));
        unavailable("infinite native palette",f->f.data.matrixPalette.put(f.target.boneIndices.get(THIGH)*16+12,Float.NEGATIVE_INFINITY));
        unavailable("missing pending upper pose",f->f.pending[1]=null);
        unavailable("nonfinite pending upper pose",f->f.pending[1].m31(Float.NaN));
        unavailable("singular native palette",f->f.slotPose(THIGH,new Matrix4f().scaling(0,1,1)));
    }

    public static void main(String[] args) throws ReflectiveOperationException {
        sameSlotAndPendingOwnership();
        unavailableInputs();
        System.out.println("CART_LEG_CLEARANCE_PALETTE_PASS");
    }
}
