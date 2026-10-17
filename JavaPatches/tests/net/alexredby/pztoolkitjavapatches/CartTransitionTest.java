package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import org.joml.Matrix4f;
import sun.misc.Unsafe;
import zombie.characters.IsoPlayer;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.iso.IsoGridSquare;
import zombie.iso.objects.IsoWorldInventoryObject;

public final class CartTransitionTest {
    private static Unsafe unsafe;
    private static <T> T allocate(Class<T> type) throws Exception {return type.cast(unsafe.allocateInstance(type));}
    private static void check(boolean condition, String message) {if(!condition) throw new AssertionError(message);}
    private static void close(float actual, float expected, String message) {
        check(Math.abs(actual-expected)<.00002f,message+": "+actual+" != "+expected);
    }
    private static final class Player extends IsoPlayer {
        InventoryItem primary,secondary;
        ItemContainer inventory;
        IsoGridSquare square;
        java.util.Map<String,Float> variables;
        Player(){super(null,null,0,0,0);}
        @Override public float getX(){return 10.25f;}
        @Override public float getY(){return 20.75f;}
        @Override public float getZ(){return 2;}
        @Override public IsoGridSquare getCurrentSquare(){return square;}
        @Override public InventoryItem getPrimaryHandItem(){return primary;}
        @Override public InventoryItem getSecondaryHandItem(){return secondary;}
        @Override public ItemContainer getInventory(){return inventory;}
        @Override public boolean isLocalPlayer(){return true;}
        @Override public boolean isDead(){return false;}
        @Override public zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot setVariable(String name,float value){
            if(variables==null) variables=new java.util.HashMap<>();variables.put(name,value);return null;
        }
        @Override public void clearVariable(String name){if(variables!=null) variables.remove(name);}
    }
    private static final class Cart extends InventoryItem {
        ItemContainer container;
        IsoWorldInventoryObject world;
        String kind;
        float rotation,alpha;
        Cart(){super(null,null,null,(String)null);}
        @Override public String getFullType(){return kind;}
        @Override public ItemContainer getContainer(){return container;}
        @Override public IsoWorldInventoryObject getWorldItem(){return world;}
        @Override public void setWorldZRotation(float value){rotation=value;}
        @Override public float getWorldAlpha(){return alpha;}
        @Override public void setWorldAlpha(float value){alpha=value;}
    }
    private static final class WorldItem extends IsoWorldInventoryObject {
        int invalidations;
        WorldItem(){super((zombie.iso.IsoCell)null);}
        @Override public float getWorldPosX(){return 10.25f;}
        @Override public float getWorldPosY(){return 20.75f;}
        @Override public float getWorldPosZ(){return 2;}
        @Override public void invalidateRenderChunkLevel(long flags){check(flags==256,"wrong visual invalidation flags");invalidations++;}
    }
    private static void bridge() throws Exception {
        var player=allocate(Player.class);player.inventory=allocate(ItemContainer.class);player.square=allocate(IsoGridSquare.class);
        var cart=allocate(Cart.class);cart.kind="SaucedWheelbarrow.WheelbarrowWood";cart.container=player.inventory;
        player.primary=cart;player.secondary=cart;
        try {
            check(CartTransition.beginDrop(player,cart,11.1,20.4,2,123),"valid owned placement refused");
            check(CartTransition.place(null,cart)==null,"different caller square bypassed scope");
            CartTransition.endDrop();
            check(CartTransition.place(player.square,cart)==null,"closed context must not redirect later drops");
            for(double[] invalid:new double[][]{{Double.NaN,20,2,0},{11,20,2,Double.POSITIVE_INFINITY},
                    {11,20,2,-1},{11,20,2,360},{50,20,2,0},{11,20,3,0}}) {
                check(!CartTransition.beginDrop(player,cart,invalid[0],invalid[1],invalid[2],invalid[3]),"invalid pose accepted");
                check(CartTransition.place(player.square,cart)==null,"invalid begin retained older pending pose");
            }
            var foreign=allocate(Cart.class);foreign.kind=cart.kind;foreign.container=player.inventory;
            check(!CartTransition.beginDrop(player,foreign,11,20,2,0),"foreign held identity accepted");
            player.secondary=foreign;
            check(!CartTransition.beginDrop(player,cart,11,20,2,0),"one-handed cart accepted");
            player.secondary=cart;cart.container=allocate(ItemContainer.class);
            check(!CartTransition.beginDrop(player,cart,11,20,2,0),"foreign inventory accepted");
            cart.container=player.inventory;cart.kind="SaucedWheelbarrow.WheelbarrowMetal";
            check(!CartTransition.beginDrop(player,cart,11,20,2,0),"other cart type accepted");
            cart.kind="SaucedWheelbarrow.WheelbarrowWood";cart.world=allocate(IsoWorldInventoryObject.class);
            check(!CartTransition.beginDrop(player,cart,11,20,2,0),"already-world cart accepted");
            cart.world=null;
            check(CartTransition.beginDrop(player,cart,11,20,2,0),"valid final context");
            check(CartTransition.place(player.square,foreign)==null,"different item bypassed scope");
            CartTransition.endDrop();
            var world=allocate(WorldItem.class);cart.world=world;cart.alpha=.7f;cart.worldScale=1;
            check(CartTransition.update(player,cart,true,.2),"pickup presentation refused");
            close(cart.alpha,.7f,"presentation must not change serialized item alpha");
            for(int i=0;i<=100;i++) {
                check(CartTransition.update(player,cart,true,i/100.0),"pickup pose update refused");
                float x=player.variables.get("ToolkitWoodCartPoseX"),y=player.variables.get("ToolkitWoodCartPoseY");
                check(y>=0 && y<=x && x<=1 && x-y<=.10001f,"ground action escaped the shallow 2D blend triangle");
                if(i==44) close(x,.10f,"grounded pose must only use a tenth of the deep crouch clip");
            }
            CartTransition.end(player);
            close(cart.alpha,.7f,"cancel leaves item alpha unchanged");
            check(world.invalidations==1,"cancel invalidates cached world rendering once");
            CartTransition.end(player);
            check(world.invalidations==1,"cleanup is idempotent");
        } finally {CartTransition.endDrop();CartTransition.end(player);}
    }
    private static void geometry() {
        Matrix4f model=new Matrix4f().rotateX((float)Math.PI/2).scale(90);
        Matrix4f held=new Matrix4f().translation(-.0060535767f,.097179376f,-.34652624f)
            .rotateX((float)Math.toRadians(74.24)).scale(76.5f);
        for(float angle:new float[]{0,.3f,(float)Math.PI/4,(float)Math.PI/2,(float)Math.PI,3.7f,5.4f}) {
            var pose=CartTransition.dropPlacement(held,model,10.25f,20.75f,2,angle,1);
            check(pose!=null && pose.xRotation()==0 && pose.yRotation()==0,"drop must use native planar orientation");
            double expected=angle+Math.PI,actual=Math.toRadians(pose.zRotation());
            check(Math.abs(Math.atan2(Math.sin(actual-expected),Math.cos(actual-expected)))<.00001,"drop yaw folded across native Euler singularity");
            close(pose.worldScale(),.85f,"world/held scale agreement");
            check(pose.zRotation()>=0 && pose.zRotation()<360,"native yaw normalization");
        }
        check(CartTransition.dropPlacement(new Matrix4f().m00(Float.NaN),model,0,0,0,0,1)==null,"invalid held transform accepted");
    }
    public static void main(String[] args) throws Exception {
        Field field=Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);unsafe=(Unsafe)field.get(null);
        check(Main.CART_SUPPORTED,"installed B42.21 bytecode fixture unsupported");
        check(Main.CART_TRANSITION_SUPPORTED,"installed transition render bytecode unsupported");
        for(var name:new String[]{"wooden","hidden","place"}) {
            boolean exported=false;
            for(var method:CartTransition.class.getDeclaredMethods()) if(name.equals(method.getName()))
                exported=java.lang.reflect.Modifier.isPublic(method.getModifiers());
            check(exported,"inlined native advice cannot call a package-private helper: "+name);
        }
        var atlas=zombie.core.skinnedmodel.model.WorldItemModelDrawer.class.getDeclaredMethod("renderAtlasTexture",
            InventoryItem.class,IsoGridSquare.class,float.class,float.class,float.class,float.class,float.class,boolean.class);
        atlas.setAccessible(true);
        var cart=allocate(Cart.class);cart.kind="SaucedWheelbarrow.WheelbarrowWood";
        check(Boolean.FALSE.equals(atlas.invoke(null,cart,null,0f,0f,0f,0f,0f,false)),
            "wooden cart atlas must defer to the same renderer as FBO without accessing a scene");
        bridge();geometry();
        System.out.println("CART_TRANSITION_PASS (scoped exact-owner validation, native yaw geometry, cancellation cache cleanup)");
    }
}
