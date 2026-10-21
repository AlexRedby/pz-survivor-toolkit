package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import zombie.scripting.objects.ModelScript;
import sun.misc.Unsafe;
import zombie.core.skinnedmodel.model.ItemModelRenderer;
import zombie.core.skinnedmodel.model.Model;
import zombie.core.skinnedmodel.model.ModelMesh;
import zombie.core.skinnedmodel.shader.Shader;
import zombie.inventory.InventoryItem;
import zombie.iso.objects.IsoWorldInventoryObject;
import zombie.iso.IsoGridSquare;
import zombie.core.ImmutableColor;

public final class CartWheelWorldTest {
    private static Unsafe unsafe;
    private static <T> T allocate(Class<T> type) throws Exception {return type.cast(unsafe.allocateInstance(type));}
    private static void check(boolean value,String message) {if(!value) throw new AssertionError(message);}
    private static void set(Object target,String name,Object value) throws Exception {
        var field=target.getClass().getDeclaredField(name);field.setAccessible(true);field.set(target,value);
    }
    private static Object current() throws Exception {
        var field=CartWheelWorld.class.getDeclaredField("drawing");field.setAccessible(true);
        return ((ThreadLocal<?>)field.get(null)).get();
    }
    private static double phase() throws Exception {
        var draw=current();var method=draw.getClass().getDeclaredMethod("phase");method.setAccessible(true);
        return (Double)method.invoke(draw);
    }
    private static final class Cart extends InventoryItem {
        IsoWorldInventoryObject world;
        String kind="SaucedWheelbarrow.WheelbarrowWood";
        Cart(){super(null,null,null,(String)null);}
        @Override public String getFullType(){return kind;}
        @Override public IsoWorldInventoryObject getWorldItem(){return world;}
    }
    private static IsoGridSquare litSquare() throws Exception {
        var square=allocate(IsoGridSquare.class);
        var lighting=new IsoGridSquare.ILighting[4];
        for(int player=0;player<lighting.length;player++) {
            var light=new IsoGridSquare.Lighting();
            for(int vertex=0;vertex<8;vertex++) light.lightverts(vertex,0xffffffff);
            lighting[player]=light;
        }
        set(square,"lighting",lighting);
        return square;
    }
    private static final class World extends IsoWorldInventoryObject {
        InventoryItem item;
        World(){super((zombie.iso.IsoCell)null);}
        @Override public InventoryItem getItem(){return item;}
    }
    private static Cart cart() throws Exception {
        var cart=allocate(Cart.class);cart.kind="SaucedWheelbarrow.WheelbarrowWood";
        var world=allocate(World.class);world.item=cart;cart.world=world;return cart;
    }
    private static Model model() throws Exception {
        var model=allocate(Model.class);model.isStatic=true;set(model,"mesh",allocate(ModelMesh.class));return model;
    }
    private static ItemModelRenderer renderer(Model model) throws Exception {
        var renderer=new ItemModelRenderer();set(renderer,"model",model);return renderer;
    }
    private static void prepare(ItemModelRenderer renderer,Cart item,Matrix4f transform,double phase) {
        CartWheelSpin.record(item,renderer.x,renderer.y,(float)Math.PI,
            CartWheelWorld.worldTransform(renderer,transform,new Matrix4f()),phase);
        CartWheelWorld.snapshot(renderer,item,transform);CartWheelWorld.ready(renderer);
    }
    private static void compositionAndPool() throws Exception {
        var model=model();var renderer=renderer(model);var item=cart();
        var transform=new Matrix4f().translation(.1f,.2f,-.3f).rotateX(.4f).scale(.85f);
        CartWheelWorld.snapshot(renderer,item,transform);
        var previous=CartWheelWorld.begin(renderer,model,transform,false);
        check(current()==null,"unfinished init snapshot was drawable before native final rotation/scale");CartWheelWorld.end(previous);
        // Native renderMain applies both scales and rotation after returning from init.
        transform.scale(90f);renderer.angle.set(17,43,-9);renderer.x=10.25f;renderer.y=20.75f;
        var original=new Matrix4f(transform);
        var expected=new Matrix4f().rotationX((float)Math.toRadians(17)).rotateY((float)Math.toRadians(43))
            .rotateZ((float)Math.toRadians(-9)).mul(transform);
        check(CartWheelWorld.worldTransform(renderer,transform,new Matrix4f()).equals(expected,.00001f),
            "world rotation did not follow native Rx/Ry/Rz order");
        check(transform.equals(original),"world composition mutated native root transform");
        CartWheelSpin.record(item,renderer.x,renderer.y,(float)Math.PI,expected,.7);
        CartWheelWorld.ready(renderer);
        previous=CartWheelWorld.begin(renderer,model,transform,false);
        check(current()!=null && Math.abs(phase()-.7)<.00001,"phase used pre-finalization rotation/scale");CartWheelWorld.end(previous);
        check(CartWheelWorld.rendered(renderer)==null,"prepared phase became successful draw evidence");
        renderer.reset();
        previous=CartWheelWorld.begin(renderer,model,transform,false);
        check(current()==null,"pooled native reset retained an old world item phase");CartWheelWorld.end(previous);
        prepare(renderer,item,transform,.4);
        item.kind="SaucedCarts.ShoppingCart";
        CartWheelWorld.snapshot(renderer,item,transform);CartWheelWorld.ready(renderer);
        previous=CartWheelWorld.begin(renderer,model,transform,false);
        check(current()==null,"foreign item retained recycled renderer phase");CartWheelWorld.end(previous);
        item.kind="SaucedWheelbarrow.WheelbarrowWood";item.world=null;
        CartWheelWorld.snapshot(renderer,item,transform);CartWheelWorld.ready(renderer);
        previous=CartWheelWorld.begin(renderer,model,transform,false);
        check(current()==null,"inventory item entered the world wheel draw");CartWheelWorld.end(previous);
        item=cart();((World)item.world).item=cart();
        CartWheelWorld.snapshot(renderer,item,transform);CartWheelWorld.ready(renderer);
        previous=CartWheelWorld.begin(renderer,model,transform,false);
        check(current()==null,"mismatched world object entered the wheel draw");CartWheelWorld.end(previous);
    }
    private static void nestedAndException() throws Exception {
        var outerModel=model();var innerModel=model();var outer=renderer(outerModel);var inner=renderer(innerModel);
        var transform=new Matrix4f().scale(76.5f);prepare(outer,cart(),transform,.3);prepare(inner,cart(),transform,.9);
        var original=CartWheelWorld.begin(outer,outerModel,transform,false);var outerScope=current();
        check(outerScope!=null,"missing exact root world scope");
        var saved=CartWheelWorld.begin(inner,innerModel,transform,false);
        check(current()!=null && current()!=outerScope && Math.abs(phase()-.9)<.00001,"nested root did not use its own snapshot");
        CartWheelWorld.end(saved);check(current()==outerScope,"nested root lost previous scope");
        for(boolean part:new boolean[]{false,true}) {
            saved=CartWheelWorld.begin(outer,part?outerModel:innerModel,transform,part);
            check(current()==null,"foreign/weapon-part pass inherited outer scope");
            check(!CartWheelWorld.render(outerModel.mesh,allocate(Shader.class)),"unmatched pass entered GL");
            CartWheelWorld.end(saved);check(current()==outerScope,"foreign/part exit lost previous scope");
        }
        check(!CartWheelWorld.render(innerModel.mesh,allocate(Shader.class)),"foreign mesh entered GL");
        check(!CartWheelWorld.render(outerModel.mesh,null),"missing shader entered GL");
        check(!CartWheelWorld.render(outerModel.mesh,allocate(Shader.class)),"missing VBO entered GL");
        check(CartWheelWorld.rendered(outer)==null,"failed split draw emitted successful receipt");
        // The real woven native method throws in Asset.isReady on this intentionally uninitialized mesh,
        // before Shader.Start/GL. Its @Patch.OnExit must still restore the enclosing world scope.
        innerModel.effect=allocate(Shader.class);
        Method nativeRender=ItemModelRenderer.class.getDeclaredMethod("renderModel",Model.class,Matrix4f.class,
            boolean.class,boolean.class,boolean.class);nativeRender.setAccessible(true);
        try {nativeRender.invoke(inner,innerModel,transform,false,false,false);throw new AssertionError("native fixture did not throw");}
        catch(InvocationTargetException expected) {check(expected.getCause() instanceof NullPointerException,"wrong native fixture failure");}
        check(current()==outerScope,"ZombieBuddy onThrowable exit did not restore outer scope");
        CartWheelWorld.end(original);check(current()==null,"outer scope leaked after exit");
        try {nativeRender.invoke(inner,innerModel,transform,false,false,false);throw new AssertionError("native fixture did not throw");}
        catch(InvocationTargetException expected) {check(expected.getCause() instanceof NullPointerException,"wrong native fixture failure");}
        check(current()==null,"exception leaked a world wheel scope to later draws");
        outerModel.mesh.Draw(allocate(Shader.class)); // Woven unrelated native draw, no VBO and no GL.
    }
    private static void metalWorld() throws Exception {
        var nativeModel=model();var renderer=renderer(nativeModel);var item=cart();
        item.kind="SaucedWheelbarrow.WheelbarrowMetal";
        var transform=CartWheelbarrow.METAL.held(new Matrix4f());
        prepare(renderer,item,transform,.6);
        var previous=CartWheelWorld.begin(renderer,nativeModel,transform,false);
        check(current()!=null && Math.abs(phase()-.6)<.00001,"metal world phase was not retained");
        check(!CartWheelWorld.render(nativeModel.mesh,allocate(Shader.class)),"metal missing VBO entered GL");
        check(CartWheelWorld.rendered(renderer)==null,"metal failed draw produced successful receipt");
        CartWheelWorld.end(previous);CartWheelWorld.clear(renderer);
    }

    private static void close(float actual,float expected,String message) {
        check(Math.abs(actual-expected)<.000003f,message+": "+actual+" vs "+expected);
    }

    private static void supportGeometry(Matrix4f transform) {
        // Independent native metal VBO foot vertices and measured tire rim/cylinder, before item yaw.
        float floor=.008f-.00175f*2.44949f/1.5f;
        for(float x:new float[]{-8.86394978f,-38.22069931f}) {
            var foot=transform.transformPosition(new Vector3f(x,-20.28660011f,37.90950012f));
            close(foot.y,floor,"metal support foot does not share the floor");
        }
        // Sample the actual rim through arbitrary shader phases; a single lowest captured vertex is insufficient.
        for(int phase=0;phase<37;phase++) {
            float lowest=Float.POSITIVE_INFINITY;
            for(int vertex=0;vertex<720;vertex++) {
                double a=vertex*Math.PI/360+phase*.137;
                var point=transform.transformPosition(new Vector3f(-23.54235f,
                    -11.737464f+12.154752f*(float)Math.cos(a),.78115034f+12.154752f*(float)Math.sin(a)));
                check(point.y>=floor-.000003f,"retained wheel phase penetrates support floor");
                lowest=Math.min(lowest,point.y);
            }
            check(lowest-floor<.00002f,"wheel envelope floats above both grounded feet");
        }
    }

    private static void supportCalibration() throws Exception {
        var item=cart();item.kind="SaucedWheelbarrow.WheelbarrowMetal";
        var nativeModel=model();var renderer=renderer(nativeModel);
        var field=ItemModelRenderer.class.getDeclaredField("transform");field.setAccessible(true);
        var nativeTransform=(Matrix4f)field.get(renderer);
        var script=new ModelScript();
        for(float modelScale:new float[]{.5f,1,2}) for(float itemScale:new float[]{.6f,1,1.4f}) {
            item.worldScale=itemScale;script.scale=modelScale;
            var original=new Matrix4f().translation(.2800003f,.28608033f,-.4227159f).scale(.010794421f);
            var axle=new Vector3f(-23.54235f,-11.737464f,.78115034f);
            var before=new Matrix4f(original).scale(.85f*modelScale*itemScale).transformPosition(axle,new Vector3f());
            nativeTransform.set(original);
            Main.WoodenWorldScale.exit(renderer,item,script);
            nativeTransform.scale(modelScale*itemScale); // Actual renderMain post-init order.
            supportGeometry(nativeTransform);
            var after=nativeTransform.transformPosition(axle,new Vector3f());
            close(after.x,before.x,"support calibration moved native axle sideways");
            close(after.z,before.z,"support calibration moved native axle forwards");
            var projected=new Matrix4f(original).scale(modelScale);
            check(CartWorldSupport.apply(item.getFullType(),projected,itemScale*.85f),"transition support calibration refused");
            projected.scale(itemScale*.85f);
            check(projected.equals(nativeTransform,.000003f),"transition/native world pipelines disagree");
            var repeated=new Matrix4f(projected);
            check(CartWorldSupport.apply(item.getFullType(),repeated,1),"repeat support calibration refused");
            check(repeated.equals(projected,.000003f),"repeat support calibration rotated or translated twice");
            for(float yaw:new float[]{0,43,135,270}) {
                renderer.angle.set(0,yaw,0);
                supportGeometry(CartWheelWorld.worldTransform(renderer,nativeTransform,new Matrix4f()));
            }
            renderer.reset(); // Pooled init must start from the newly built native matrix.
        }
        var original=new Matrix4f().translation(.28f,.286f,-.42f).scale(.01f);
        for(String kind:new String[]{"SaucedWheelbarrow.WheelbarrowWood","SaucedWheelbarrow.Unknown","Base.Hammer"}) {
            var transform=new Matrix4f(original);
            check(!CartWorldSupport.apply(kind,transform,1) && transform.equals(original),"foreign model support was changed");
        }
        item.world=null;script.scale=1;item.worldScale=1;nativeTransform.set(original);
        Main.WoodenWorldScale.exit(renderer,item,script);
        check(nativeTransform.equals(new Matrix4f(original).scale(.85f)),"inventory icon received world support calibration");
        for(float invalid:new float[]{0,-1,Float.NaN,Float.POSITIVE_INFINITY}) {
            var transform=new Matrix4f(original);
            check(!CartWorldSupport.apply(item.getFullType(),transform,invalid) && transform.equals(original),"invalid support scale changed model");
        }
    }

    private static void wovenNativeSupportInit() throws Exception {
        // Call the actual transformed engine method: advice executes from zombie.core...,
        // so a package-private helper fails here even though direct Main.exit calls pass.
        var init=ItemModelRenderer.class.getDeclaredMethod("init",InventoryItem.class,IsoGridSquare.class,
            IsoGridSquare.class,float.class,float.class,float.class,Model.class,ModelScript.class,
            float.class,ImmutableColor.class,float.class,boolean.class,boolean.class);
        init.setAccessible(true);
        var renderer=renderer(model());var square=litSquare();var item=cart();
        var script=new ModelScript();script.scale=.010794421f;item.worldScale=1;
        var nativeModel=model(); // Mesh.transform=null skips readiness and all GPU calls in native init.
        var field=ItemModelRenderer.class.getDeclaredField("transform");field.setAccessible(true);
        for(String kind:new String[]{"SaucedWheelbarrow.WheelbarrowMetal","SaucedWheelbarrow.WheelbarrowWood",
                "SaucedWheelbarrow.WheelbarrowMetal"}) {
            item.kind=kind;
            renderer.reset();
            try {
                init.invoke(renderer,item,square,square,10.25f,20.75f,2.00175f,nativeModel,script,
                    1f,new ImmutableColor(1f,1f,1f,1f),0f,false,false);
            } catch(InvocationTargetException failure) {
                throw new AssertionError("actual woven native init failed for "+kind,failure.getCause());
            }
            var transform=(Matrix4f)field.get(renderer);
            // renderMain applies script/item scales after the private init advice returned.
            transform.scale(script.scale*item.worldScale);
            if(kind.endsWith("Metal")) supportGeometry(transform);
            else check(transform.equals(new Matrix4f().scale(.85f*script.scale),.000001f),
                "pooled wood init inherited the metal support calibration");
            close(renderer.x,10.25f,"native init did not complete actor X assignment");
            close(renderer.z,2.00175f,"native init did not complete level assignment");
        }
    }

    public static void main(String[] args) throws Exception {
        Field field=Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);unsafe=(Unsafe)field.get(null);
        check(me.zed_0xff.zombie_buddy.Patch.OnExit.class.getMethod("onThrowable").getReturnType()==Class.class,
            "ZombieBuddy Patch API lacks onThrowable");
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches",CartWheelWorldTest.class.getClassLoader());
        check(Main.CART_WHEEL_SUPPORTED && Main.CART_TRANSITION_SUPPORTED,"installed world wheel bytecode unsupported");
        compositionAndPool();nestedAndException();metalWorld();supportCalibration();wovenNativeSupportInit();
        System.out.println("CART_WHEEL_WORLD_PASS (native matrix order, pooled renderer, exact nested scope and woven exception cleanup; no GL)");
    }
}
