package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import java.util.Map;
import sun.misc.Unsafe;
import zombie.ai.State;
import zombie.ai.states.CollideWithWallState;
import zombie.characters.IsoPlayer;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.iso.Vector2;
import zombie.iso.objects.IsoWorldInventoryObject;

public final class CartImpactMotionTest {
    private static Unsafe unsafe;
    private static <T>T allocate(Class<T> type)throws Exception{return type.cast(unsafe.allocateInstance(type));}
    private static void check(boolean value,String message){if(!value)throw new AssertionError(message);}
    private static void close(double actual,double expected,String message){check(Math.abs(actual-expected)<.00001,message+": "+actual+" != "+expected);}
    @SuppressWarnings("unchecked") private static Map<IsoPlayer,Object> contacts()throws Exception{
        var field=CartImpactMotion.class.getDeclaredField("contacts");field.setAccessible(true);return (Map<IsoPlayer,Object>)field.get(null);
    }
    private static final class Player extends IsoPlayer {
        boolean collision,dead,remote,getup,grapple,ragdoll;
        InventoryItem primary,secondary;
        float slow;
        Player(){super(null,null,0,0,0);}
        @Override public boolean isLocalPlayer(){return !remote;}
        @Override public boolean isNpc(){return false;}
        @Override public boolean isDead(){return dead;}
        @Override public boolean isCurrentState(State state){return collision && state==CollideWithWallState.instance();}
        @Override public boolean isGettingUp(){return getup;}
        @Override public boolean isGrappling(){return grapple;}
        @Override public boolean isBeingGrappled(){return false;}
        @Override public boolean isRagdollSimulationActive(){return ragdoll;}
        @Override public zombie.vehicles.BaseVehicle getVehicle(){return null;}
        @Override public boolean getVariableBoolean(String name){return false;}
        @Override public InventoryItem getPrimaryHandItem(){return primary;}
        @Override public InventoryItem getSecondaryHandItem(){return secondary;}
        @Override public float getSlowFactor(){return slow;}
        @Override public void setCurrentSquareFromPosition(){}
    }
    private static final class Cart extends InventoryItem {
        IsoWorldInventoryObject world;
        Cart(){super(null,null,null,(String)null);}
        @Override public String getFullType(){return "SaucedWheelbarrow.WheelbarrowWood";}
        @Override public IsoWorldInventoryObject getWorldItem(){return world;}
    }
    private static final class World extends IsoWorldInventoryObject {
        zombie.iso.IsoGridSquare square;
        InventoryItem item;float x,y,z;
        World(){super((zombie.iso.IsoCell)null);}
        @Override public zombie.iso.IsoGridSquare getSquare(){return square;}
        @Override public InventoryItem getItem(){return item;}
        @Override public float getWorldPosX(){return x;}
        @Override public float getWorldPosY(){return y;}
        @Override public float getWorldPosZ(){return z;}
    }
    private record Fixture(Player player,Cart cart,World world){}
    private static Fixture fixture()throws Exception{
        CartImpactMotion.reset();
        var player=allocate(Player.class);player.collision=true;player.setX(10);player.setY(20);player.setZ(0);
        player.setNextX(10.03f);player.setNextY(20);player.reqMovement=new Vector2();
        var cart=allocate(Cart.class);var world=allocate(World.class);cart.world=world;world.item=cart;
        world.x=10.7f;world.y=20;world.square=allocate(zombie.iso.IsoGridSquare.class);
        return new Fixture(player,cart,world);
    }
    private static void geometry(){
        var out=new Vector2();
        for(int i=0;i<16;i++){
            double angle=i*Math.PI/8,nx=Math.cos(angle),ny=Math.sin(angle),tx=-ny,ty=nx;
            CartImpactMotion.clip((float)(.2*nx+.1*tx),(float)(.2*ny+.1*ty),10-.05*nx,20-.05*ny,10,20,nx,ny,out);
            close(out.x*nx+out.y*ny,.05,"inward component exceeds remaining room");
            close(out.x*tx+out.y*ty,.1,"lateral component changed");
            CartImpactMotion.clip((float)(-.2*nx+.1*tx),(float)(-.2*ny+.1*ty),10,20,10,20,nx,ny,out);
            close(out.x*nx+out.y*ny,-.2,"native rebound changed");
            close(out.x*tx+out.y*ty,.1,"backward lateral component changed");
            CartImpactMotion.clip((float)(.2*nx),(float)(.2*ny),10+.01*nx,20+.01*ny,10,20,nx,ny,out);
            close(out.getLength(),0,"already-forward actor was teleported backwards");
        }
    }
    private static void wovenMovement()throws Exception{
        var f=fixture();CartImpactMotion.begin(f.player,f.cart,f.world);
        check(contacts().containsKey(f.player),"confirmed contact not registered");
        f.player.moveUnmodded(.25f,.1f);
        close(f.player.getNextX(),10.03,"woven native hook allowed forward root step");
        close(f.player.getNextY(),20.1,"woven native hook changed lateral step");
        f.player.slow=.5f;f.player.moveUnmodded(-.2f,0);
        close(f.player.getNextX(),9.93,"native slowFactor or rebound lost");
        f.player.moveUnmodded(.5f,0);
        check(f.player.getNextX()<=10.03001f,"re-entry crossed fixed plane");
        var floor=new ItemContainer("floor",null,null);floor.AddItem(f.cart);CartImpactMotion.tick();
        check(contacts().containsKey(f.player),"native floor projection ended contact");
        // Body contact outlives the independent 240ms cart render settle.
        var old=contacts().get(f.player);var components=old.getClass().getRecordComponents();var values=new Object[components.length];
        for(int i=0;i<components.length;i++){
            var accessor=components[i].getAccessor();accessor.setAccessible(true);
            values[i]=components[i].getName().equals("started")?System.nanoTime()-500_000_000L:accessor.invoke(old);
        }
        var constructor=old.getClass().getDeclaredConstructors()[0];constructor.setAccessible(true);
        contacts().put(f.player,constructor.newInstance(values));CartImpactMotion.tick();
        check(contacts().containsKey(f.player),"contact expired with render settle");
        values[values.length-1]=System.nanoTime()-CartImpactMotion.MAX_NANOS-1;
        contacts().put(f.player,constructor.newInstance(values));CartImpactMotion.tick();
        check(!contacts().containsKey(f.player),"expired episode retained restriction");
        float before=f.player.getNextX();f.player.slow=0;f.player.moveUnmodded(.2f,0);
        close(f.player.getNextX()-before,.2,"expiry retained root restriction");
    }
    private static void lifecycle()throws Exception{
        for(int bad=0;bad<14;bad++){
            var f=fixture();CartImpactMotion.begin(f.player,f.cart,f.world);
            switch(bad){
                case 0 -> f.player.collision=false;
                case 1 -> f.player.dead=true;
                case 2 -> f.player.remote=true;
                case 3 -> f.player.getup=true;
                case 4 -> f.player.grapple=true;
                case 5 -> f.player.ragdoll=true;
                case 6 -> f.cart.world=null;
                case 7 -> f.world.square=null;
                case 8 -> f.world.item=allocate(Cart.class);
                case 9 -> f.cart.setContainer(new ItemContainer("inventory",null,null));
                case 10 -> f.player.setZ(1);
                case 11 -> f.player.primary=allocate(Cart.class);
                case 12 -> f.world.x+=.05f;
                case 13 -> f.cart.setWorldZRotation(30);
            }
            var step=CartImpactMotion.movement(f.player,.2f,.1f);
            close(step.x,.2,"invalid episode changed input "+bad);close(step.y,.1,"invalid episode changed lateral "+bad);
            check(!contacts().containsKey(f.player),"invalid episode retained "+bad);
        }
        for(float slow:new float[]{-1,1.5f,Float.NaN,Float.POSITIVE_INFINITY}){
            var f=fixture();CartImpactMotion.begin(f.player,f.cart,f.world);f.player.slow=slow;
            close(CartImpactMotion.movement(f.player,.2f,0).x,.2,"abnormal native slowFactor altered");
            check(contacts().isEmpty(),"abnormal slowFactor contact retained");
        }
        for(int mode=0;mode<2;mode++){
            var f=fixture();CartImpactMotion.begin(f.player,f.cart,f.world);
            zombie.network.GameClient.client=mode==0;zombie.network.GameServer.server=mode==1;
            try{
                close(CartImpactMotion.movement(f.player,.2f,0).x,.2,"MP movement altered");
                CartImpactMotion.begin(f.player,f.cart,f.world);check(contacts().isEmpty(),"MP contact registered");
            }finally{zombie.network.GameClient.client=false;zombie.network.GameServer.server=false;}
        }
        var f=fixture();f.player.primary=f.cart;CartImpactMotion.begin(f.player,f.cart,f.world);
        check(contacts().isEmpty(),"held item started impact contact");
        f.player.primary=null;CartImpactMotion.begin(f.player,f.cart,f.world);CartEmergencyDrop.reset();
        check(contacts().isEmpty(),"world reset retained contact");
    }
    public static void main(String[] args)throws Exception{
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        Field field=Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);unsafe=(Unsafe)field.get(null);
        Main.main(new String[0]);
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches",CartImpactMotionTest.class.getClassLoader());
        check(Main.CART_SUPPORTED && Main.CART_TRANSITION_SUPPORTED,"unsupported native hooks");
        geometry();wovenMovement();lifecycle();
        System.out.println("CART_IMPACT_MOTION_PASS (woven root bound, native rebound/slowFactor, floor ownership, state cleanup and SP scope)");
    }
}
