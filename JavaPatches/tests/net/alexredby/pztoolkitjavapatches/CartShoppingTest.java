package net.alexredby.pztoolkitjavapatches;

import org.joml.Matrix4f;
import org.joml.Vector3f;
import zombie.inventory.InventoryItem;
import zombie.core.skinnedmodel.model.Model;
import zombie.scripting.objects.ModelScript;

/** Four native tire samples protect support and mesh scale independently of production contact constants. */
public final class CartShoppingTest {
    // Actual VBO positions from ShoppingCartModel.bin (sha256 2aff1983c0bf843edbf012a33cc2d0d77124d3865b2e9dc35785d31cb08d0aab).
    // These are the lowest vertex of each separate 64-point tire under the measured axle support plane.
    private static final Vector3f[] TIRES={
        new Vector3f(-108.67859649658203f,-8.72284984588623f,-1.097890853881836f),
        new Vector3f(-108.67859649658203f,-8.722865104675293f,1.1834654808044434f),
        new Vector3f(110.04669952392578f,8.371068000793457f,-.910473644733429f),
        new Vector3f(110.04669952392578f,8.371052742004395f,.9835692644119263f)};
    private static final Vector3f BAR=new Vector3f(-150.07166f,343.47412f,-.0000065f);
    private static void check(boolean value,String message){if(!value)throw new AssertionError(message);}
    private static void close(float actual,float expected,float tolerance,String message){
        check(Float.isFinite(actual) && Math.abs(actual-expected)<=tolerance,message+": "+actual+" expected "+expected);
    }
    private static Vector3f at(Matrix4f m,Vector3f p){return m.transformPosition(p,new Vector3f());}
    private static void tires(Matrix4f m,String where){
        for(int i=0;i<TIRES.length;i++)close(at(m,TIRES[i]).y,.008f,.000002f,where+" tire "+i);
    }
    private static void barXZ(Matrix4f before,Matrix4f after,String where){
        var a=at(before,BAR);var b=at(after,BAR);
        close(b.x,a.x,.000002f,where+" bar X");close(b.z,a.z,.000002f,where+" bar Z");
    }
    // Native atlas ItemParams render receipt from atlas01/interaction, not CartShopping.worldModel().
    private static Matrix4f nativeModel(){return new Matrix4f().set(
        .002273866f,-.00014903705f,0,0,.000111277506f,.0016977666f,-7.437096e-11f,0,
        3.159179e-10f,4.819975e-9f,.11050479f,0,0,0,0,1);}
    // Native Bob idle hand attachment before the shopping correction.
    private static Matrix4f nativeHeld(){return new Matrix4f().set(
        -5.080325e-10f,-.00022194229f,-.0021531826f,0,7.381783e-10f,.0016076594f,-.00016571165f,0,
        .104969054f,-6.051497e-8f,-1.0280073e-8f,0,-.0016536561f,.0033783615f,-.44702002f,1);}
    private static void support(){
        for(float size:new float[]{.6f,1,1.7f})for(float later:new float[]{.2f,1,2.5f})for(float yaw:new float[]{0,.7f,2.3f}) {
            // Native outer init applies laterScale to basis only, after the support hook.
            var raw=new Matrix4f().translation(.14f,.21f,-.32f).rotateY(yaw).rotateX(.12f).mul(nativeModel()).scale(size/later);
            var before=new Matrix4f(raw).scale(later);var originalBasis=before.getScale(new Vector3f());
            check(CartShopping.support(raw,later),"valid nonuniform native basis rejected");
            var effective=new Matrix4f(raw).scale(later);tires(effective,"effective world");barXZ(before,effective,"support");
            var afterBasis=effective.getScale(new Vector3f());
            close(afterBasis.x,originalBasis.x,1e-8f,"support changed native X scale");
            close(afterBasis.y,originalBasis.y,1e-8f,"support changed native Y scale");
            close(afterBasis.z,originalBasis.z,1e-6f,"support changed native Z scale");
            var once=new Matrix4f(raw);check(CartShopping.support(raw,later),"second support rejected");
            check(raw.equals(once,.000002f),"support is not idempotent");
        }
    }
    private static void align(){
        var model=nativeModel();check(CartShopping.support(model,1),"canonical support rejected");var modelBefore=new Matrix4f(model);
        for(float worldScale:new float[]{.6f,1,1.7f}) {
            var held=nativeHeld();var before=new Matrix4f(held);var delta=new Matrix4f().translation(2,3,4).rotateY(.2f);
            check(CartShopping.align(held,model,worldScale,delta),"valid held basis rejected");
            tires(held,"held");barXZ(before,held,"align");check(delta.equals(new Matrix4f()),"actor delta contains cart scale/pitch");
            var residual=new Matrix4f(held).mul(new Matrix4f(model).invert());
            for(int axis=0;axis<3;axis++)close(residual.getColumn(axis,new Vector3f()).length(),worldScale,.000002f,"held/world mesh size mismatch");
            var once=new Matrix4f(held);check(CartShopping.align(held,model,worldScale,delta),"second align rejected");
            check(held.equals(once,.000002f),"align is not idempotent");check(model.equals(modelBefore),"align mutated imported model");
        }
    }
    private static void invalid(){
        for(float scale:new float[]{0,-1,Float.NaN,Float.POSITIVE_INFINITY}) {
            var m=nativeModel();var before=new Matrix4f(m);
            check(!CartShopping.support(m,scale),"invalid laterScale accepted");check(m.equals(before),"invalid support changed output");
            var h=nativeHeld();var original=new Matrix4f(h);var delta=new Matrix4f().translation(3,2,1);var d=new Matrix4f(delta);
            check(!CartShopping.align(h,m,scale,delta),"invalid worldScale accepted");check(h.equals(original)&&delta.equals(d),"invalid scale changed held/actor");
        }
        for(Matrix4f invalid:new Matrix4f[]{new Matrix4f().scale(0),new Matrix4f().scale(-1,1,1),new Matrix4f().m00(Float.NaN),new Matrix4f().rotateX((float)Math.PI/2).mul(nativeModel())}) {
            var original=new Matrix4f(invalid);check(!CartShopping.support(invalid,1),"invalid/upside support accepted");
            check(java.util.Arrays.equals(invalid.get(new float[16]),original.get(new float[16])),"failed support mutated input");
        }
        var model=nativeModel();var h=new Matrix4f().rotateZ((float)Math.PI/2).mul(model).scale(.5f);var before=new Matrix4f(h);var delta=new Matrix4f().translation(3,2,1);var deltaBefore=new Matrix4f(delta);
        check(!CartShopping.align(h,model,1,delta),"sideways held pose accepted");
        check(h.equals(before)&&delta.equals(deltaBefore),"failed alignment mutated held/actor");
        h=nativeHeld();before.set(h);check(!CartShopping.align(h,model,1,null),"null actor delta accepted");check(h.equals(before),"null delta changed held");
        check(!CartShopping.support(null,1)&&!CartShopping.align(null,model,1,delta)&&!CartShopping.align(h,null,1,delta),"null input accepted");
        for(Matrix4f badModel:new Matrix4f[]{new Matrix4f().scale(0),new Matrix4f().m00(Float.NaN)}) {
            before.set(h);check(!CartShopping.align(h,badModel,1,delta),"invalid model accepted");check(h.equals(before)&&delta.equals(deltaBefore),"invalid model changed outputs");
        }
    }
    public static final class Params {public final Matrix4f transform;Params(Matrix4f t){transform=t;}}
    private static final class Cart extends InventoryItem {
        Cart(){super(null,null,null,(String)null);}
        @Override public String getFullType(){return "SaucedCarts.ShoppingCart";}
    }
    private static void atlasLaterScale()throws Exception {
        check(Main.CART_TRANSITION_SUPPORTED,"installed shopping atlas bytecode unsupported");
        var field=sun.misc.Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);var unsafe=(sun.misc.Unsafe)field.get(null);
        var item=(Cart)unsafe.allocateInstance(Cart.class);item.worldScale=.7f;
        var script=new ModelScript();script.scale=.4f;
        var params=new Params(nativeModel());var before=new Matrix4f(params.transform).scale(script.scale*item.worldScale);
        Main.ShoppingWorldAtlas.exit(params,item,null,script,1,null,0,false);
        var effective=new Matrix4f(params.transform).scale(script.scale*item.worldScale);tires(effective,"native atlas laterScale");barXZ(before,effective,"atlas");
    }
    private static void field(Object object,String name,Object value)throws Exception {
        var f=object.getClass().getDeclaredField(name);f.setAccessible(true);f.set(object,value);
    }
    private static void wovenAtlas()throws Exception {
        var f=sun.misc.Unsafe.class.getDeclaredField("theUnsafe");f.setAccessible(true);var unsafe=(sun.misc.Unsafe)f.get(null);
        var type=Class.forName("zombie.core.skinnedmodel.model.WorldItemAtlas$ItemParams");
        var init=type.getDeclaredMethod("init",InventoryItem.class,Model.class,ModelScript.class,float.class,
            zombie.core.ImmutableColor.class,float.class,boolean.class);init.setAccessible(true);
        var mesh=(zombie.core.skinnedmodel.model.ModelMesh)unsafe.allocateInstance(zombie.core.skinnedmodel.model.ModelMesh.class);
        var meshState=unsafe.allocateInstance(Class.forName("zombie.asset.Asset$PRIVATE"));
        field(meshState,"currentState",zombie.asset.Asset.State.READY);
        var privateState=zombie.asset.Asset.class.getDeclaredField("priv");privateState.setAccessible(true);privateState.set(mesh,meshState);
        mesh.transform=new Matrix4f(nativeModel()).transpose();
        var model=(Model)unsafe.allocateInstance(Model.class);field(model,"mesh",mesh);
        var script=new ModelScript();script.scale=.4f;var item=(Cart)unsafe.allocateInstance(Cart.class);item.worldScale=.7f;
        var params=unsafe.allocateInstance(type);var transform=new Matrix4f();field(params,"transform",transform);field(params,"angle",new Vector3f());
        init.invoke(params,item,model,script,1,zombie.core.ImmutableColor.white,0,false);
        var baseline=new Matrix4f(transform).scale(script.scale*item.worldScale);
        check(Math.abs(at(baseline,TIRES[3]).y-.008f)>.001f,"native atlas fixture was already supported");
        // Execute the real private native method after production advice is inlined into its own package.
        // A plain call of Main.ShoppingWorldAtlas.exit cannot expose IllegalAccessError from that context.
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches",CartShoppingTest.class.getClassLoader());
        init.invoke(params,item,model,script,1,zombie.core.ImmutableColor.white,0,false);
        var effective=new Matrix4f(transform).scale(script.scale*item.worldScale);
        tires(effective,"woven native atlas");barXZ(baseline,effective,"woven atlas");
    }
    public static void main(String[] args)throws Exception {
        support();align();invalid();atlasLaterScale();wovenAtlas();
        System.out.println("CART_SHOPPING_PASS (four native tire contacts, imported scales, effective laterScale, bar X/Z, idempotence, transactional failures, woven native atlas hook)");
    }
}
