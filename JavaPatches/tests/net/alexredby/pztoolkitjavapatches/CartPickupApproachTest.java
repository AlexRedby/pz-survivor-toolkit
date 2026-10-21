package net.alexredby.pztoolkitjavapatches;

import java.util.HashMap;
import zombie.pathfind.PathFindBehavior2.BehaviorResult;
import java.util.Stack;
import org.joml.Vector3f;
import se.krka.kahlua.j2se.KahluaTableImpl;
import sun.misc.Unsafe;
import zombie.characters.CharacterTimedActions.BaseAction;
import zombie.characters.CharacterTimedActions.LuaTimedActionNew;
import zombie.characters.IsoPlayer;
import zombie.inventory.InventoryItem;
import zombie.iso.IsoGridSquare;
import zombie.iso.objects.IsoWorldInventoryObject;
import zombie.pathfind.PathFindBehavior2;

public final class CartPickupApproachTest {
    private static Unsafe unsafe;
    private static <T> T allocate(Class<T> type) throws Exception {return type.cast(unsafe.allocateInstance(type));}
    private static void check(boolean value,String message) {if(!value) throw new AssertionError(message);}
    private static void field(Object owner,String name,Object value) throws Exception {
        var type=owner.getClass();
        while(type!=null) {
            try {var field=type.getDeclaredField(name);field.setAccessible(true);field.set(owner,value);return;}
            catch(NoSuchFieldException missing) {type=type.getSuperclass();}
        }
        throw new NoSuchFieldException(name);
    }
    private static final class Player extends IsoPlayer {
        Stack<BaseAction> actions;
        PathFindBehavior2 path;
        zombie.vehicles.BaseVehicle vehicle;
        int protection,moves;
        boolean turning,wantsTurn;
        zombie.core.skinnedmodel.animation.AnimationPlayer animation;
        @Override public boolean isTurning(){return turning;}
        @Override public boolean shouldBeTurning(){return wantsTurn;}
        @Override public zombie.core.skinnedmodel.animation.AnimationPlayer getAnimationPlayer(){return animation;}
        @Override public boolean hasAnimationPlayer(){return animation!=null;}
        float x=10,y=20,nextX=10,nextY=20;
        @Override public float getX(){return x;}
        @Override public float getY(){return y;}
        @Override public void moveUnmodded(float dx,float dy){moves++;nextX=x+dx;nextY=y+dy;}
        void settle(){x=nextX;y=nextY;}
        Player(){super(null,null,0,0,0);}
        @Override public boolean isLocalPlayer(){return protection!=1;}
        @Override public boolean isDead(){return protection==2;}
        @Override public boolean isAiming(){return protection==3;}
        @Override public boolean hasHitReaction(){return protection==4;}
        @Override public boolean isKnockedDown(){return protection==5;}
        @Override public boolean isGettingUp(){return protection==6;}
        @Override public zombie.vehicles.BaseVehicle getVehicle(){return protection==7?vehicle:null;}
        @Override public boolean isGrappling(){return protection==8;}
        @Override public boolean isBeingGrappled(){return protection==9;}
        @Override public boolean isRagdollSimulationActive(){return protection==10;}
        @Override public Stack<BaseAction> getCharacterActions(){return actions;}
        @Override public PathFindBehavior2 getPathFindBehavior2(){return path;}
    }
    private static final class Cart extends InventoryItem {
        String kind;
        IsoWorldInventoryObject world;
        Cart(){super(null,null,null,(String)null);}
        @Override public String getFullType(){return kind;}
        @Override public IsoWorldInventoryObject getWorldItem(){return world;}
    }
    private static final class World extends IsoWorldInventoryObject {
        InventoryItem item;
        IsoGridSquare square;
        World(){super((zombie.iso.IsoCell)null);}
        @Override public InventoryItem getItem(){return item;}
        @Override public IsoGridSquare getSquare(){return square;}
    }
    private record Fixture(Player player,Cart cart,World world,LuaTimedActionNew action,KahluaTableImpl table) {}
    private static Fixture fixture() throws Exception {return fixture("SaucedWheelbarrow.WheelbarrowWood");}
    private static Fixture fixture(String kind) throws Exception {
        var player=allocate(Player.class);player.actions=new Stack<>();
        player.vehicle=allocate(zombie.vehicles.BaseVehicle.class);
        player.x=player.nextX=10;player.y=player.nextY=20;
        player.path=new PathFindBehavior2(player);
        field(player.path,"goal",PathFindBehavior2.Goal.Location);
        field(player.path,"targetX",10.03f);field(player.path,"targetY",20.04f);field(player.path,"targetZ",0f);
        var cart=allocate(Cart.class);var world=allocate(World.class);
        cart.kind=kind;cart.world=world;world.item=cart;world.square=allocate(IsoGridSquare.class);
        var action=allocate(LuaTimedActionNew.class);action.chr=player;action.maxTime=-1;
        var table=new KahluaTableImpl(new HashMap<>());var meta=new KahluaTableImpl(new HashMap<>());
        meta.rawset("Type","ISWalkToTimedActionF");table.setMetatable(meta);
        table.rawset("character",player);table.rawset("toolkitWoodCartItem",cart);
        table.rawset("location",new Vector3f(10.03f,20.04f,0));field(action,"table",table);player.actions.add(action);
        return new Fixture(player,cart,world,action,table);
    }
    private static void arrival(String kind) throws Exception {
        var f=fixture(kind);var p=f.player;
        for(var nativeResult:new BehaviorResult[]{BehaviorResult.Working,BehaviorResult.Failed})
            check(CartPickupApproach.result(p,p.path,nativeResult)==nativeResult && p.moves==0,"changed unresolved native path");
        check(CartPickupApproach.result(p,p.path,BehaviorResult.Succeeded)==BehaviorResult.Working,"nearby off-center start succeeded");
        check(p.x==10 && p.y==20 && Math.hypot(p.nextX-p.x,p.nextY-p.y)<=.02001,"alignment teleported or exceeded bounded step");
        p.nextX=10.03f;p.nextY=20.04f;
        check(CartPickupApproach.result(p,p.path,BehaviorResult.Succeeded)==BehaviorResult.Working,"accepted unresolved Next position");
        for(int i=1;i<45;i++)check(CartPickupApproach.result(p,p.path,BehaviorResult.Succeeded)
            ==(i==44?BehaviorResult.Failed:BehaviorResult.Working),"blocked correction did not honor its attempted-update budget");
        f=fixture(kind);p=f.player;boolean success=false;
        for(int i=0;i<100;i++) {
            var result=CartPickupApproach.result(p,p.path,BehaviorResult.Succeeded);
            if(result==BehaviorResult.Succeeded){success=true;break;}
            check(result==BehaviorResult.Working,"unblocked final approach failed");p.settle();
        }
        check(success && Math.hypot(p.x-10.03f,p.y-20.04f)<=.002,"approach did not reach actual target");
        for(float x:new float[]{9,Float.NaN}) {
            f=fixture(kind);f.player.x=x;
            check(CartPickupApproach.result(f.player,f.player.path,BehaviorResult.Succeeded)==BehaviorResult.Failed && f.player.moves==0,"unsafe correction moved actor");
        }
        f=fixture(kind);p=f.player;
        f.table.getMetatable().rawset("Type","ToolkitWoodCartPickup");
        check(CartPickupApproach.suppressDeferred(p),"arrived wheelbarrow pickup retained locomotion blend: "+kind);
        p.actions.clear();check(!CartPickupApproach.suppressDeferred(p),"finished wheelbarrow pickup retained movement lease: "+kind);
        f=fixture(kind);f.table.rawset("toolkitWoodCartItem",null);
        check(CartPickupApproach.result(f.player,f.player.path,BehaviorResult.Succeeded)==BehaviorResult.Succeeded && f.player.moves==0,"ordinary path acquired precise movement");
    }

    private static void scopeAndCleanup() throws Exception {
        for(int guard=1;guard<=10;guard++) {
            var f=fixture();f.player.protection=guard;
            check(CartPickupApproach.result(f.player,f.player.path,BehaviorResult.Succeeded)==BehaviorResult.Succeeded && f.player.moves==0,"moved protected player "+guard);
            f.table.getMetatable().rawset("Type","ToolkitWoodCartPickup");
            check(!CartPickupApproach.suppressDeferred(f.player),"suppressed protected player "+guard);
        }
        for(int guard=0;guard<16;guard++) {
            var f=fixture();
            switch(guard) {
                case 0 -> f.table.getMetatable().rawset("Type","ISWalkToTimedAction");
                case 1 -> f.table.rawset("character",allocate(Player.class));
                case 2 -> f.cart.kind="Other.Cart";
                case 3 -> f.cart.world=null;
                case 4 -> f.world.item=allocate(Cart.class);
                case 5 -> f.world.square=null;
                case 6 -> ((Vector3f)f.table.rawget("location")).x+=.001f;
                case 7 -> f.action.forceStop=true;
                case 8 -> f.action.forceComplete=true;
                case 9 -> f.action.maxTime=0;
                case 10 -> f.player.actions.add(allocate(BaseAction.class));
                case 11 -> f.player.actions.clear();
                case 12 -> field(f.player.path,"goal",PathFindBehavior2.Goal.None);
                case 13 -> ((Vector3f)f.table.rawget("location")).y=Float.NaN;
                case 14 -> f.action.chr=allocate(Player.class);
                case 15 -> field(f.action,"table",null);
            }
            check(CartPickupApproach.result(f.player,f.player.path,BehaviorResult.Succeeded)==BehaviorResult.Succeeded && f.player.moves==0,"corrected unrelated/invalid action "+guard);
        }
        var f=fixture();
        f.player.setDeferredMovementEnabled(false);
        check(!CartPickupApproach.suppressDeferred(f.player) && !f.player.isDeferredMovementEnabled(),
            "cart walk changed native movement policy");
        f.player.actions.clear();
        check(!f.player.isDeferredMovementEnabled(),"scope rewrote stored disabled movement flag");
        f.player.setDeferredMovementEnabled(true);f.player.actions.add(f.action);
        check(f.player.isDeferredMovementEnabled(),"cart walk suppressed native climbing translation");
        f.table.getMetatable().rawset("Type","ToolkitWoodCartPickup");
        check(!f.player.isDeferredMovementEnabled(),"pickup allowed residual deferred motion");
        f.player.actions.clear();
        check(!CartPickupApproach.suppressDeferred(f.player) && f.player.isDeferredMovementEnabled(),
            "cancel retained cart movement suppression");
        f.player.actions.add(f.action);f.action.forceStop=true;
        check(!CartPickupApproach.suppressDeferred(f.player) && f.player.isDeferredMovementEnabled(),
            "stopped pickup retained movement suppression");
        f.action.forceStop=false;f.table.getMetatable().rawset("Type","ToolkitWoodCartPickup");
        f.table.rawset("toolkitWoodCartItem",null);f.table.rawset("location",null);
        check(CartPickupApproach.suppressDeferred(f.player) && !f.player.isDeferredMovementEnabled(),
            "native pickup hook allowed locomotion blend translation");
        f.action.maxTime=0;
        check(!CartPickupApproach.suppressDeferred(f.player) && f.player.isDeferredMovementEnabled(),
            "finished pickup retained movement suppression");
    }
    private static Fixture facing() throws Exception {
        var f=fixture("SaucedWheelbarrow.WheelbarrowMetal");
        f.table.getMetatable().rawset("Type","ToolkitWoodCartPickup");f.table.rawset("itemId",(double)f.cart.getID());
        f.player.animation=allocate(zombie.core.skinnedmodel.animation.AnimationPlayer.class);
        field(f.player.animation,"targetDir",new zombie.iso.Vector2());
        field(f.player,"forwardDirection",new zombie.iso.Vector2());
        f.player.animation.setMaxTwistAngle((float)Math.toRadians(45));
        f.player.setTargetAndCurrentDirection((float)Math.cos(1.3847381-Math.PI/2),(float)Math.sin(1.3847381-Math.PI/2));
        return f;
    }
    private static void facingCompletion() throws Exception {
        var f=facing();float target=(float)Math.PI/2;
        float before=f.player.animation.getRenderedAngle();boolean aligned=false;
        for(int i=0;i<60;i++) {
            aligned=CartPickupApproach.face(f.player,f.world,10,20,target);
            float now=f.player.animation.getRenderedAngle();
            check(now>=before && now-before<=.030001f,"idle facing snapped or rotated away from handles");
            check(f.player.x==10 && f.player.y==20 && f.player.moves==0,"facing completion moved actor");
            check(Math.abs(f.player.getForwardDirectionX()-1)<.00001 && Math.abs(f.player.getForwardDirectionY())<.00001,
                "bounded completion lost full native facing request");
            before=now;if(aligned)break;
        }
        check(aligned && Math.abs(target-before)<Math.toRadians(1),"recorded yaw270 idle remainder did not finish");
        for(int guard=0;guard<12;guard++) {
            f=facing();
            switch(guard) {
                case 0 -> f.player.turning=true;
                case 1 -> f.player.wantsTurn=true;
                case 2 -> f.player.x+=.003f;
                case 3 -> f.table.rawset("itemId",(double)f.cart.getID()+1);
                case 4 -> f.cart.world=null;
                case 5 -> f.table.getMetatable().rawset("Type","ISWalkToTimedActionF");
                case 6 -> f.player.protection=1;
                case 7 -> f.action.forceStop=true;
                case 8 -> f.player.protection=2;
                case 9 -> f.player.actions.clear();
                case 10 -> f.player.animation.setMaxTwistAngle(.01f);
                case 11 -> f.world.square=null;
            }
            before=f.player.animation.getRenderedAngle();
            check(!CartPickupApproach.face(f.player,f.world,10,20,target)
                && f.player.animation.getRenderedAngle()==before,"facing completion bypassed native/action/position gate "+guard);
        }
        f=facing();
        f.player.animation.setMaxTwistAngle(target-f.player.animation.getRenderedAngle()-.005f);
        before=f.player.animation.getRenderedAngle();
        CartPickupApproach.face(f.player,f.world,10,20,target);
        check(f.player.animation.getRenderedAngle()>before,"native one-degree excess-twist dead zone remained stuck");
        var time=zombie.GameTime.getInstance();float saved=time.getTrueMultiplier();
        try {
            time.setMultiplier(100);f=facing();before=f.player.animation.getRenderedAngle();
            CartPickupApproach.face(f.player,f.world,10,20,target);
            check(f.player.animation.getRenderedAngle()-before<=.030001f,"fast game speed snapped final facing");
            time.setMultiplier(0);f=facing();before=f.player.animation.getRenderedAngle();
            check(!CartPickupApproach.face(f.player,f.world,10,20,target)
                && f.player.animation.getRenderedAngle()==before,"paused game advanced facing");
        } finally {time.setMultiplier(saved);}
        var method=CartTransition.class.getMethod("face",IsoPlayer.class,IsoWorldInventoryObject.class);
        var exposed=method.getAnnotation(se.krka.kahlua.integration.annotations.LuaMethod.class);
        check(exposed!=null && exposed.global() && exposed.name().equals("toolkitWoodCartFace"),"pickup face bridge is not exposed to Lua");
    }

    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        var field=Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);unsafe=(Unsafe)field.get(null);
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches",CartPickupApproachTest.class.getClassLoader());
        check(Main.CART_TRANSITION_SUPPORTED && Main.COMPLETION_SUPPORTED,"native cart approach fixture is unsupported");
        arrival("SaucedWheelbarrow.WheelbarrowWood");arrival("SaucedWheelbarrow.WheelbarrowMetal");arrival("SaucedCarts.ShoppingCart");scopeAndCleanup();facingCompletion();
        System.out.println("CART_PICKUP_APPROACH_PASS");
    }
}
