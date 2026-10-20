package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import org.joml.Matrix4f;
import sun.misc.Unsafe;
import zombie.core.skinnedmodel.model.ItemModelRenderer;
import zombie.core.skinnedmodel.model.Model;
import zombie.core.skinnedmodel.model.ModelMesh;
import zombie.core.skinnedmodel.shader.Shader;
import zombie.inventory.InventoryItem;
import zombie.iso.objects.IsoWorldInventoryObject;

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

    public static void main(String[] args) throws Exception {
        Field field=Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);unsafe=(Unsafe)field.get(null);
        check(me.zed_0xff.zombie_buddy.Patch.OnExit.class.getMethod("onThrowable").getReturnType()==Class.class,
            "ZombieBuddy Patch API lacks onThrowable");
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches",CartWheelWorldTest.class.getClassLoader());
        check(Main.CART_WHEEL_SUPPORTED && Main.CART_TRANSITION_SUPPORTED,"installed world wheel bytecode unsupported");
        compositionAndPool();nestedAndException();metalWorld();
        System.out.println("CART_WHEEL_WORLD_PASS (native matrix order, pooled renderer, exact nested scope and woven exception cleanup; no GL)");
    }
}
