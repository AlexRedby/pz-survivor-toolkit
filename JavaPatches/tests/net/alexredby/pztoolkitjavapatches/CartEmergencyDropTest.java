package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import java.util.Map;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import sun.misc.Unsafe;
import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.model.ItemModelRenderer;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.iso.objects.IsoWorldInventoryObject;

public final class CartEmergencyDropTest {
    private static Unsafe unsafe;
    private static <T>T allocate(Class<T> type)throws Exception{return type.cast(unsafe.allocateInstance(type));}
    private static void check(boolean value,String message){if(!value)throw new AssertionError(message);}
    private static void close(double a,double b,double tolerance,String message){check(Math.abs(a-b)<=tolerance,message+": "+a+" != "+b);}
    private static Object get(Object object,String name)throws Exception{var f=object.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(object);}
    private static void set(Object object,String name,Object value)throws Exception{var f=object.getClass().getDeclaredField(name);f.setAccessible(true);f.set(object,value);}
    @SuppressWarnings("unchecked") private static Map<InventoryItem,Object> releases()throws Exception{
        var f=CartEmergencyDrop.class.getDeclaredField("releases");f.setAccessible(true);return (Map<InventoryItem,Object>)f.get(null);
    }
    private static final class Player extends IsoPlayer {
        InventoryItem primary,secondary;
        Player(){super(null,null,0,0,0);}
        @Override public boolean isLocalPlayer(){return false;}
        @Override public InventoryItem getPrimaryHandItem(){return primary;}
        @Override public InventoryItem getSecondaryHandItem(){return secondary;}
    }
    private static final class Cart extends InventoryItem {
        IsoWorldInventoryObject world;String kind;
        Cart(){super(null,null,null,(String)null);}
        @Override public String getFullType(){return kind==null?"SaucedWheelbarrow.WheelbarrowWood":kind;}
        @Override public IsoWorldInventoryObject getWorldItem(){return world;}
    }
    private static final class World extends IsoWorldInventoryObject {
        zombie.iso.IsoGridSquare square;
        @Override public zombie.iso.IsoGridSquare getSquare(){return square;}
        InventoryItem item;int invalidations;float x=10,y=20,z=2;
        World(){super((zombie.iso.IsoCell)null);}
        @Override public InventoryItem getItem(){return item;}
        @Override public float getWorldPosX(){return x;}
        @Override public float getWorldPosY(){return y;}
        @Override public float getWorldPosZ(){return z;}
        @Override public void invalidateRenderChunkLevel(long flags){check(flags==256,"wrong invalidation");invalidations++;}
    }
    private record Fixture(Player player,Cart cart,World world,Object release){}
    private static Fixture fixture(String kind)throws Exception{
        var player=allocate(Player.class);var cart=allocate(Cart.class);cart.kind=kind;var world=allocate(World.class);
        world.square=allocate(zombie.iso.IsoGridSquare.class);
        world.x=10;world.y=20;world.z=2;world.item=cart;cart.world=world;
        var source=new CartTransitionMath.Placement(10,20,2.05f,0,30,8,.85f);
        var target=new CartTransitionMath.Placement(10,20,2.00175f,0,30,0,.85f);
        var type=Class.forName(CartEmergencyDrop.class.getName()+"$Release");
        var constructor=type.getDeclaredConstructor(IsoPlayer.class,CartTransitionMath.Placement.class,CartTransitionMath.Placement.class,Matrix4f.class,long.class);
        constructor.setAccessible(true);
        Object release=constructor.newInstance(player,source,target,new Matrix4f().scale(CartWheelbarrow.forType(kind)==CartWheelbarrow.METAL?.0091743395f/.85f:90),System.nanoTime());
        releases().put(cart,release);return new Fixture(player,cart,world,release);
    }
    private static void geometry(){
        for(var profile:new CartWheelbarrow[]{CartWheelbarrow.WOOD,CartWheelbarrow.METAL}) {
        var model=profile==CartWheelbarrow.WOOD?new Matrix4f().rotateX((float)Math.PI/2).scale(90):new Matrix4f().scale(.0091743395f/.85f);
        var axle=profile.center(new Vector3f());
        for(float angle:new float[]{0,.3f,1.57f,3.14f,4.7f,6.1f})for(float bank:new float[]{-.122173f,0,.122173f})for(float shift:new float[]{0,-.24f}){
            var held=profile.held(new Matrix4f());
            check(CartGrounding.alignWheelbarrow(held,profile,bank,Math.abs(bank),shift,new Matrix4f()),"held alignment");
            var landing=CartTransition.dropPlacement(held,model,10.25f,20.75f,2,angle,1,0,profile);
            var ground=new Matrix4f();check(landing!=null && CartTransitionMath.worldToActor(landing,model,10.25f,20.75f,2,angle,ground),"emergency landing missing");
            var first=held.transformPosition(axle,new Vector3f());var last=ground.transformPosition(axle,new Vector3f());
            close(first.x,last.x,.00001,"landing axle lateral jump");close(first.z,last.z,.00001,"landing axle fore-aft jump");
            var out=new Matrix4f();float low0=CartGrounding.wheelbarrowLowest(held,profile),low1=CartGrounding.wheelbarrowLowest(ground,profile);
            for(int i=0;i<=100;i++){
                check(CartEmergencyDrop.settle(held,ground,i/100.0,out,profile),"settle failed");
                var actual=out.transformPosition(axle,new Vector3f());
                close(actual.x,first.x,.00002,"settle axle sideways drift");close(actual.z,first.z,.00002,"settle axle forward drift");
                float low=CartGrounding.wheelbarrowLowest(out,profile);check(low>=Math.min(low0,low1)-.00001 && low<=Math.max(low0,low1)+.00001,"wheel jumped vertically during settle");
            }
            check(out.equals(ground,.000001f),"endpoint differs from stock world transform");
            CartEmergencyDrop.settle(held,ground,0,out,profile);check(out.equals(held,.000001f),"initial pose discontinuous");
        }
        }
        check(!CartEmergencyDrop.settle(new Matrix4f().m00(Float.NaN),new Matrix4f(),.5,new Matrix4f()),"invalid source accepted");
        check(!CartEmergencyDrop.settle(new Matrix4f(),new Matrix4f(),Double.NaN,new Matrix4f()),"invalid clock accepted");
        check(CartEmergencyDrop.fresh(100,99,1,2,3,1.2f,2,3),"fresh source refused");
        check(!CartEmergencyDrop.fresh(100,101,1,2,3,1,2,3),"future source accepted");
        check(!CartEmergencyDrop.fresh(CartEmergencyDrop.FRESH_NANOS+1,0,1,2,3,1,2,3),"stale source accepted");
        check(!CartEmergencyDrop.fresh(100,99,1,2,3,1,2,4),"wrong floor accepted");
        check(!CartEmergencyDrop.fresh(100,99,1,2,3,2,2,3),"teleport accepted");
    }
    private static void ownershipAndPool(String kind)throws Exception{
        var f=fixture(kind);CartEmergencyDrop.finish(f.player,f.cart);
        check(get(f.release,"world")==f.world && f.world.invalidations==1,"exact confirmed drop did not bind");
        long started=(Long)get(f.release,"started");CartEmergencyDrop.finish(f.player,f.cart);
        check((Long)get(f.release,"started")==started && f.world.invalidations==1,"duplicate completion restarted settle");
        var renderer=new ItemModelRenderer();renderer.x=10;renderer.y=20;renderer.z=2.00175f;renderer.angle.set(0,30,0);
        var matrix=new Matrix4f().scale(76.5f);set(renderer,"transform",matrix);
        set(f.release,"started",System.nanoTime()-CartEmergencyDrop.SETTLE_NANOS/2);
        CartEmergencyDrop.render(renderer,f.cart);check(!matrix.equals(new Matrix4f().scale(76.5f),.001f),"active presentation did not render");
        CartEmergencyDrop.clear(renderer);check(matrix.equals(new Matrix4f().scale(76.5f),.000001f) && renderer.angle.y==30,"pooled matrix/angle not restored");
        CartEmergencyDrop.render(renderer,f.cart);
        // Real init advice restores old state before native initialization can replace its values.
        Main.WoodenWorldScale.enter(renderer);matrix.translation(5,6,7);renderer.angle.set(11,12,13);
        CartEmergencyDrop.render(renderer,allocate(Cart.class));check(matrix.equals(new Matrix4f().translation(5,6,7),.000001f) && renderer.angle.y==12,"foreign pooled item inherited pose");
        CartEmergencyDrop.render(renderer,f.cart);set(f.release,"started",System.nanoTime()-CartEmergencyDrop.SETTLE_NANOS-1);
        CartEmergencyDrop.tick();check(!releases().containsKey(f.cart) && f.world.invalidations>=2,"final FBO invalidation or expiry missing");
        CartEmergencyDrop.render(renderer,f.cart);check(matrix.equals(new Matrix4f().translation(5,6,7),.000001f),"expiry did not restore renderer");
        for(int bad=0;bad<7;bad++){
            f=fixture(kind);if(bad==0)f.player.primary=f.cart;
            if(bad==1)f.cart.setContainer(allocate(ItemContainer.class));
            if(bad==2)f.world.item=allocate(Cart.class);
            if(bad==3)f.world.x+=.1f;
            if(bad==5)f.world.square=null;
            if(bad==6)set(f.release,"prepared",System.nanoTime()-CartEmergencyDrop.FRESH_NANOS-1);
            CartEmergencyDrop.finish(bad==4?allocate(Player.class):f.player,f.cart);
            check(!releases().containsKey(f.cart) && f.world.invalidations==0,"invalid authoritative handoff accepted "+bad);
        }
        f=fixture(kind);CartEmergencyDrop.finish(f.player,f.cart);f.cart.world=null;CartEmergencyDrop.tick();check(!releases().containsKey(f.cart),"pickup retained release");
        f=fixture(kind);CartEmergencyDrop.finish(f.player,f.cart);f.world.square=null;CartEmergencyDrop.tick();
        check(!releases().containsKey(f.cart) && f.world.invalidations==1,"removed world retained release or invalidated missing square");
        f=fixture(kind);CartEmergencyDrop.finish(f.player,f.cart);CartEmergencyDrop.render(renderer,f.cart);
        CartEmergencyDrop.reset();check(releases().isEmpty() && matrix.equals(new Matrix4f().translation(5,6,7),.000001f),"session reset retained world or renderer state");
        f=fixture(kind);CartEmergencyDrop.finish(f.player,f.cart);
        var floor=new ItemContainer("floor",null,null);floor.AddItem(f.cart);
        check(f.cart.getContainer()==floor,"native floor projection did not assign container");
        // This assertion isolates ownership; native AddItem class loading is not the settle clock.
        set(f.release,"started",System.nanoTime());
        CartEmergencyDrop.tick();check(releases().containsKey(f.cart),"native floor projection ended settling");
        CartEmergencyDrop.render(renderer,f.cart);check(!matrix.equals(new Matrix4f().translation(5,6,7),.000001f),"floor-projected cart stopped settling");
        CartEmergencyDrop.clear(renderer);f.cart.setContainer(new ItemContainer("inventory",null,null));
        CartEmergencyDrop.tick();check(!releases().containsKey(f.cart),"real inventory transfer retained release");
        f=fixture(kind);zombie.network.GameClient.client=true;
        try{CartEmergencyDrop.finish(f.player,f.cart);check(!releases().containsKey(f.cart),"MP release was altered");}
        finally{zombie.network.GameClient.client=false;releases().clear();}
    }
    public static void main(String[] args)throws Exception{
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        Field u=Unsafe.class.getDeclaredField("theUnsafe");u.setAccessible(true);unsafe=(Unsafe)u.get(null);
        check(Main.CART_TRANSITION_SUPPORTED,"unsupported local source");
        // Class loading must finish before the real 250ms freshness window begins.
        zombie.network.GameClient.client=false;zombie.network.GameServer.server=false;
        geometry();ownershipAndPool("SaucedWheelbarrow.WheelbarrowWood");ownershipAndPool("SaucedWheelbarrow.WheelbarrowMetal");
        System.out.println("CART_EMERGENCY_DROP_PASS (axle/floor continuity, freshness, exact ownership, pooled restoration, expiry and MP fallback)");
    }
}
