package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import org.joml.Matrix4f;
import org.joml.Quaternionf;
import sun.misc.Unsafe;
import zombie.characters.IsoPlayer;
import zombie.characters.CharacterTimedActions.BaseAction;
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
    private static final class NativePass extends RuntimeException {}
    private static void nativePass(Runnable render, String message) {
        try {render.run();throw new AssertionError(message);} catch(NativePass expected) {}
    }
    private static Object invoke(java.lang.reflect.Method method, Object receiver, Object... args) {
        try {return method.invoke(receiver,args);}
        catch(java.lang.reflect.InvocationTargetException error) {throw (RuntimeException)error.getCause();}
        catch(ReflectiveOperationException error) {throw new AssertionError(error);}
    }
    private static final class Player extends IsoPlayer {
        InventoryItem primary,secondary;
        ItemContainer inventory;
        IsoGridSquare square;
        java.util.Map<String,Float> variables;
        java.util.Stack<BaseAction> actions;
        int protection,modelResets,handWrites,clipPilotWrites;
        boolean performing,otherFloor,clipPilot,clipPilotAbsent;
        java.util.Map<String,Boolean> booleanVariables;
        RuntimeException modelError;
        boolean expectedForceNull;
        int modelScopes;
        Player(){super(null,null,0,0,0);}
        @Override public float getX(){return 10.25f;}
        @Override public float getY(){return 20.75f;}
        @Override public float getZ(){return otherFloor?3:2;}
        @Override public IsoGridSquare getCurrentSquare(){return square;}
        @Override public InventoryItem getPrimaryHandItem(){return primary;}
        @Override public InventoryItem getSecondaryHandItem(){return secondary;}
        @Override public ItemContainer getInventory(){return inventory;}
        @Override public void setPrimaryHandItem(InventoryItem item){handWrites++;primary=item;}
        @Override public void setSecondaryHandItem(InventoryItem item){handWrites++;secondary=item;}
        @Override public boolean isLocalPlayer(){return protection!=1;}
        @Override public boolean isDead(){return protection==2;}
        @Override public boolean isAiming(){return protection==3;}
        @Override public boolean hasHitReaction(){return protection==4;}
        @Override public boolean isKnockedDown(){return protection==5;}
        @Override public boolean isGettingUp(){return protection==6;}
        @Override public zombie.vehicles.BaseVehicle getVehicle(){return protection==7?vehicle:null;}
        zombie.vehicles.BaseVehicle vehicle;
        @Override public boolean isGrappling(){return protection==8;}
        @Override public boolean isBeingGrappled(){return protection==9;}
        @Override public boolean isRagdollSimulationActive(){return protection==10;}
        @Override public zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator getAdvancedAnimator(){return null;}
        @Override public boolean containsVariable(String name){
            if("ToolkitWoodCartClipPilot".equals(name)) return !clipPilotAbsent;
            return variables!=null && variables.containsKey(name) || booleanVariables!=null && booleanVariables.containsKey(name);
        }
        @Override public boolean getVariableBoolean(String name){
            if("ToolkitWoodCartClipPilot".equals(name)) return clipPilot;
            return "IsPerformingAnAction".equals(name) && performing;
        }
        @Override public java.util.Stack<BaseAction> getCharacterActions(){
            if(actions==null) actions=new java.util.Stack<>();return actions;
        }
        @Override public void resetEquippedHandsModels(){modelResets++;}
        @Override public void getItemVisuals(zombie.core.skinnedmodel.visual.ItemVisuals visuals){
            if(modelError!=null) {
                check(forceNullOverride==expectedForceNull,"native model scope did not isolate the leased visual");
                modelScopes++;throw modelError;
            }
        }
        @Override public zombie.characters.AttachedItems.AttachedItems getAttachedItems(){
            return new zombie.characters.AttachedItems.AttachedItems(new zombie.characters.AttachedItems.AttachedLocationGroup("fixture"));
        }
        @Override public zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot setVariable(String name,float value){
            if(variables==null) variables=new java.util.HashMap<>();variables.put(name,value);return null;
        }
        @Override public zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot setVariable(String name,boolean value){
            if("ToolkitWoodCartClipPilot".equals(name)) {
                clipPilot=value;clipPilotAbsent=false;clipPilotWrites++;return null;
            }
            check("ToolkitWoodCartClipPickup".equals(name),"unexpected boolean presentation variable: "+name);
            if(booleanVariables==null) booleanVariables=new java.util.HashMap<>();booleanVariables.put(name,value);return null;
        }
        @Override public float getVariableFloat(String name,float fallback){
            return variables==null?fallback:variables.getOrDefault(name,fallback);
        }
        @Override public void clearVariable(String name){
            if(variables!=null) variables.remove(name);
            if(booleanVariables!=null) booleanVariables.remove(name);
        }
    }
    private static final class Cart extends InventoryItem {
        ItemContainer container;
        IsoWorldInventoryObject world;
        String kind;
        float rotation,alpha;
        boolean probeNative;
        Cart(){super(null,null,null,(String)null);}
        @Override public String getFullType(){return kind;}
        @Override public String getStaticModel(){return "WheelbarrowWood";}
        @Override public ItemContainer getContainer(){return container;}
        @Override public IsoWorldInventoryObject getWorldItem(){return world;}
        @Override public void setWorldZRotation(float value){rotation=value;}
        @Override public float getWorldAlpha(){return alpha;}
        @Override public void setWorldAlpha(float value){alpha=value;}
        @Override public zombie.scripting.objects.Item getScriptItem(){if(probeNative) throw new NativePass();return null;}
        @Override public String getWorldStaticItem(){if(probeNative) throw new NativePass();return null;}
    }
    private static final class WorldItem extends IsoWorldInventoryObject {
        int invalidations;
        InventoryItem item;
        IsoGridSquare square;
        boolean probeNative;
        WorldItem(){super((zombie.iso.IsoCell)null);}
        @Override public float getWorldPosX(){return 10.25f;}
        @Override public float getWorldPosY(){return 20.75f;}
        @Override public float getWorldPosZ(){return 2;}
        @Override public InventoryItem getItem(){return item;}
        @Override public IsoGridSquare getSquare(){return square;}
        @Override public IsoGridSquare getRenderSquare(){return square;}
        @Override public zombie.iso.SpriteModel getSpriteModel(){if(probeNative) throw new NativePass();return null;}
        @Override public zombie.iso.IsoDirections getForwardIsoDirection(){throw new NativePass();}
        @Override public void invalidateRenderChunkLevel(long flags){check(flags==256,"wrong visual invalidation flags");invalidations++;}
    }
    private static void groundPasses() throws Exception {
        var player=allocate(Player.class);var cart=allocate(Cart.class);var world=allocate(WorldItem.class);
        cart.kind="SaucedWheelbarrow.WheelbarrowWood";cart.world=world;cart.alpha=.7f;cart.worldScale=1;world.item=cart;
        var renderer=new zombie.core.skinnedmodel.model.ItemModelRenderer();
        var outlineType=zombie.iso.fboRenderChunk.FBORenderObjectOutline.class;
        var outline=allocate(outlineType);
        var outlineRender=outlineType.getDeclaredMethod("renderObject",int.class,zombie.iso.IsoObject.class);
        outlineRender.setAccessible(true);
        Runnable outlinePass=()->invoke(outlineRender,outline,0,world);
        var jobType=Class.forName("zombie.iso.fboRenderChunk.FBORenderItems$RenderJob");
        var job=allocate(jobType);
        var jobWorld=jobType.getDeclaredField("worldInventoryObject");jobWorld.setAccessible(true);jobWorld.set(job,world);
        var jobModels=jobType.getDeclaredField("renderer");jobModels.setAccessible(true);
        jobModels.set(job,new zombie.core.skinnedmodel.model.ItemModelRenderer[]{renderer,renderer,renderer});
        var jobRender=jobType.getDeclaredMethod("renderMain");jobRender.setAccessible(true);
        world.square=allocate(IsoGridSquare.class);
        try {
            check(CartTransition.update(player,cart,true,.6),"pickup ground-pass setup refused");
            check(!CartTransition.hidden(cart),"ground disappeared before a held model rendered");
            var statesField=CartTransition.class.getDeclaredField("states");statesField.setAccessible(true);
            var state=((java.util.Map<?,?>)statesField.get(null)).get(player);
            var rendered=state.getClass().getDeclaredField("rendered");rendered.setAccessible(true);rendered.setBoolean(state,true);
            check(CartTransition.hidden(cart),"rendered held model must hide the exact ground item");
            var other=allocate(Cart.class);other.kind=cart.kind;
            check(!CartTransition.hidden(other),"held visual hid a different cart");
            var sprite=allocate(zombie.iso.sprite.IsoSprite.class);
            var texture=zombie.iso.sprite.IsoSprite.class.getDeclaredField("texture");texture.setAccessible(true);
            texture.set(sprite,allocate(zombie.core.textures.Texture.class));world.sprite=sprite;
            cart.probeNative=true;world.probeNative=true;
            for(int i=0;i<3;i++) {
                check(renderer.renderMain(cart,null,null,0,0,0,0,0,true)
                    ==zombie.core.skinnedmodel.model.ItemModelRenderer.RenderStatus.NoModel,
                    "cached FBO model/depth pass survived held visual");
                check(invoke(jobRender,job)==zombie.core.skinnedmodel.model.ItemModelRenderer.RenderStatus.NoModel,
                    "cached native FBO job survived held visual");
                world.render(0,0,0,null,false,false,null);
                world.renderObjectPicker(0,0,0,null);
                outlinePass.run();
            }
            close(cart.alpha,.7f,"world passes changed serialized alpha");
            CartTransition.end(player);
            check(!CartTransition.hidden(cart),"cancel did not restore the ground visual");
            check(world.invalidations==1,"cancel did not invalidate the ground cache once");
            nativePass(()->renderer.renderMain(cart,null,null,0,0,0,0,0,true),"model pass stayed hidden after cleanup");
            nativePass(()->invoke(jobRender,job),"cached FBO job stayed hidden after cleanup");
            nativePass(()->world.render(0,0,0,null,false,false,null),"sprite pass stayed hidden after cleanup");
            nativePass(()->world.renderObjectPicker(0,0,0,null),"picker stayed hidden after cleanup");
            nativePass(outlinePass,"outline stayed hidden after cleanup");
            cart.world=null;
            check(CartTransition.update(player,cart,false,.6),"setdown setup refused");
            state=((java.util.Map<?,?>)statesField.get(null)).get(player);rendered.setBoolean(state,true);
            check(!CartTransition.hidden(cart),"setdown without a native world item hid a static item");
        } finally {CartTransition.end(player);}
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
    private static Object state(Player player) throws Exception {
        var field=CartTransition.class.getDeclaredField("states");field.setAccessible(true);
        return ((java.util.Map<?,?>)field.get(null)).get(player);
    }
    private static Object value(Object state,String name) throws Exception {
        var field=state.getClass().getDeclaredField(name);field.setAccessible(true);return field.get(state);
    }
    private static void value(Object state,String name,Object value) throws Exception {
        var field=state.getClass().getDeclaredField(name);field.setAccessible(true);field.set(state,value);
    }
    private static Object cancelled(Player player) throws Exception {
        var field=CartTransition.class.getDeclaredField("cancelled");field.setAccessible(true);
        return ((java.util.Map<?,?>)field.get(null)).get(player);
    }
    private record Recovery(Player player,Cart cart,WorldItem world,boolean pickup) {}
    private static Recovery recovery(boolean pickup) throws Exception {
        var player=allocate(Player.class);player.inventory=allocate(ItemContainer.class);player.square=allocate(IsoGridSquare.class);
        player.vehicle=allocate(zombie.vehicles.BaseVehicle.class);
        var cart=allocate(Cart.class);cart.kind="SaucedWheelbarrow.WheelbarrowWood";cart.alpha=.7f;cart.worldScale=1;
        var world=allocate(WorldItem.class);world.item=cart;world.square=player.square;
        if(pickup) cart.world=world;
        else {cart.container=player.inventory;player.primary=cart;player.secondary=cart;}
        check(CartTransition.update(player,cart,pickup,.55),"recovery setup refused");
        var current=state(player);var field=current.getClass().getDeclaredField("rendered");field.setAccessible(true);field.setBoolean(current,true);
        for(String name:new String[]{"nativeRotation","referenceRotation"}) {
            field=current.getClass().getDeclaredField(name);field.setAccessible(true);field.set(current,new Quaternionf());
        }
        return new Recovery(player,cart,world,pickup);
    }
    private static void recovered(Recovery fixture) throws Exception {
        check(state(fixture.player)==null,"recovery state leaked after cleanup");
        check(fixture.player.variables.isEmpty(),"recovery pose variables leaked");
        close(fixture.cart.alpha,.7f,"recovery changed serialized alpha");
        check(fixture.player.handWrites==0,"presentation recovery wrote native hand ownership");
    }
    private static void recoveryLifecycle() throws Exception {
        for(boolean pickup:new boolean[]{true,false}) {
            var fixture=recovery(pickup);var player=fixture.player;var cart=fixture.cart;
            try {
                var stopped=allocate(BaseAction.class);player.getCharacterActions().add(stopped);
                check(CartTransition.cancel(player,cart,pickup,stopped),"exact sole stopped action refused recovery");
                var current=state(player);long start=(Long)value(current,"recoveryStart");
                check((Boolean)value(current,"recovering"),"cancel did not enter recovery");
                check(!(Boolean)value(current,"authored") && !(Boolean)value(current,"movingRecovery"),
                    "default cancellation entered the authored pose recovery pilot");
                close((Float)value(current,"cancelledProgress"),.55f,"cancel lost interrupted progress");
                check(!CartTransition.cancel(player,cart,pickup,stopped),"duplicate cancellation restarted the recovery clock");
                check((Long)value(current,"recoveryStart")==start,"duplicate cancellation changed recovery origin");
                check("WheelbarrowWood".equals(player.overridePrimaryHandModel) && player.modelResets==1,
                    "recovery did not preserve its exact visual model through native override removal");
                if(pickup) check(CartTransition.hidden(cart),"pickup recovery exposed both visual cart copies");
                else check(!CartTransition.hidden(cart),"held setdown recovery hid an unrelated world cart");
                player.actions.clear();
                check(CartTransition.suppressHeldModel(player)==!pickup,"visual suppression did not match exact held recovery");
                CartTransition.tick(player,start);
                close((Float)value(current,"progress"),.55f,"first recovery tick jumped the pose");
                CartTransition.tick(player,start+200_000_000L);
                float intermediate=(Float)value(current,"progress");
                check(intermediate>0 && intermediate<.55f,"recovery did not advance back along the action timeline");
                CartTransition.tick(player,start+600_001_000L);
                recovered(fixture);
                check(player.overridePrimaryHandModel==null,"finished recovery retained its visual lease");
                check(player.modelResets==2,"visual lease did not reset models exactly on acquire/release");
                check(cart.world==(pickup?fixture.world:null) && cart.container==(pickup?null:player.inventory)
                    && player.primary==(pickup?null:cart) && player.secondary==(pickup?null:cart),"recovery transferred the cart");
                check(!CartTransition.hidden(cart),"finished recovery left the real world cart hidden");
                CartTransition.tick(player,start+900_000_000L);CartTransition.end(player);
                check(player.modelResets==2,"repeated cleanup reset another owner's model");
            } finally {CartTransition.end(player);}
        }
    }
    private static void authoredClipDefault() throws Exception {
        boolean client=zombie.network.GameClient.client,server=zombie.network.GameServer.server;
        try {
            for(boolean networkClient:new boolean[]{false,true}) for(boolean networkServer:new boolean[]{false,true})
                for(int choice=-1;choice<=1;choice++) {
                zombie.network.GameClient.client=networkClient;zombie.network.GameServer.server=networkServer;
                var player=allocate(Player.class);player.clipPilotAbsent=choice<0;player.clipPilot=choice==1;
                boolean expected=choice<0?!networkClient && !networkServer:choice==1;
                check(CartTransition.authoredClip(player,true)==expected,"clip default did not distinguish SP from network roles or explicit choice");
                check(!player.clipPilotAbsent && player.clipPilot==expected,"clip default did not publish the matching XML selector");
                check(player.clipPilotWrites==(choice<0?1:0),"clip default rewrote an explicit actor choice");
                check(CartTransition.authoredClip(player,true)==expected && player.clipPilotWrites==(choice<0?1:0),
                    "repeated action initialization rewrote the selected clip mode");
            }
            zombie.network.GameClient.client=false;zombie.network.GameServer.server=false;
            for(int choice=-1;choice<=1;choice++) {
                var player=allocate(Player.class);player.clipPilotAbsent=choice<0;player.clipPilot=choice==1;
                if(choice==1) {
                    try {CartTransition.authoredClip(player,false);throw new AssertionError("explicit unsupported clip opt-in did not fail fast");}
                    catch(IllegalStateException expected) {
                        check(expected.getMessage().contains("native node retirement"),"unsupported clip changed its failure reason");
                    }
                    check(player.clipPilot && !player.clipPilotAbsent && player.clipPilotWrites==0,"unsupported clip fallback erased an explicit opt-in");
                } else {
                    check(!CartTransition.authoredClip(player,false) && !player.clipPilot && !player.clipPilotAbsent,
                        "unsupported absent clip mode did not select the procedural XML node");
                    check(player.clipPilotWrites==(choice<0?1:0),"unsupported fallback rewrote an explicit opt-out");
                }
            }
            for(boolean pickup:new boolean[]{true,false}) {
                var fixture=recovery(pickup);var player=fixture.player;
                try {
                    CartTransition.end(player);player.clipPilotAbsent=true;
                    check(CartTransition.update(player,fixture.cart,pickup,0),"SP default action setup refused");
                    check((Boolean)value(state(player),"authored") && player.clipPilot && !player.clipPilotAbsent,
                        "ordinary SP action did not consume the absent authored-clip default");
                    CartTransition.end(player);
                    check(player.clipPilot && !player.clipPilotAbsent,"presentation cleanup erased the actor's selected clip mode");
                } finally {CartTransition.end(player);}
            }
        } finally {zombie.network.GameClient.client=client;zombie.network.GameServer.server=server;}
    }
    private static void authoredClockAndRecovery() throws Exception {
        var layer=allocate(zombie.core.skinnedmodel.advancedanimation.AnimLayer.class);
        var character=layer.getClass().getDeclaredField("character");character.setAccessible(true);
        var track=zombie.core.skinnedmodel.animation.AnimationTrack.alloc();
        track.currentClip=new zombie.core.skinnedmodel.animation.AnimationClip(2,java.util.List.of(),"ClockFixture",false);
        track.animLayer=layer;track.trackTimeToVariable="ToolkitWoodCartClipTime";track.looping=false;track.setSpeedDelta(0);
        var tick=track.getClass().getDeclaredMethod("TickCurrentTime",float.class);tick.setAccessible(true);
        for(boolean pickup:new boolean[]{true,false}) {
            var fixture=recovery(pickup);var player=fixture.player;
            try {
                check(!(Boolean)value(state(player),"authored"),"clip pilot enabled without actor opt-in");
                check(!player.variables.containsKey("ToolkitWoodCartClipTime") && player.booleanVariables==null,
                    "default presentation published pilot animation variables");
                CartTransition.end(player);player.clipPilot=true;
                character.set(layer,player);track.reverse=!pickup;
                for(float progress:new float[]{-.1f,0,.25f,.75f,1,1.1f}) {
                    check(CartTransition.update(player,fixture.cart,pickup,progress),"authored clock update refused");
                    float clamped=Math.max(0,Math.min(1,progress));
                    close(player.variables.get("ToolkitWoodCartClipTime"),clamped,"clip clock did not clamp job delta");
                    check(player.booleanVariables.get("ToolkitWoodCartClipPickup")==pickup,"clip direction changed");
                    invoke(tick,track,.2f);
                    close(track.getCurrentTimeValue(),2*clamped,"native clock ignored normalized progress at zero speed");
                    close(track.getCurrentTrackTime(),2*(pickup?clamped:1-clamped),"native reverse sampled wrong clip time");
                }
                CartTransition.update(player,fixture.cart,pickup,.55);
                var current=state(player);var rendered=current.getClass().getDeclaredField("rendered");
                rendered.setAccessible(true);rendered.setBoolean(current,true);
                for(String name:new String[]{"nativeRotation","referenceRotation"}) {
                    var field=current.getClass().getDeclaredField(name);field.setAccessible(true);field.set(current,new Quaternionf());
                }
                var pose=new Matrix4f[]{new Matrix4f()};var cart=new Matrix4f();
                var poseField=current.getClass().getDeclaredField("recoveryPose");poseField.setAccessible(true);
                var cartField=current.getClass().getDeclaredField("recoveryCart");cartField.setAccessible(true);
                check(!CartTransition.cancel(player,fixture.cart,pickup,null),"authored recovery accepted a missing final pose and cart capture");
                poseField.set(current,pose);
                check(!CartTransition.cancel(player,fixture.cart,pickup,null),"authored recovery accepted a missing cart capture");
                poseField.set(current,null);cartField.set(current,cart);
                check(!CartTransition.cancel(player,fixture.cart,pickup,null),"authored recovery accepted a missing final body pose capture");
                check(player.overridePrimaryHandModel==null && player.modelResets==0,
                    "captureless cancellation acquired a visual model lease");
                poseField.set(current,pose);
                check(CartTransition.cancel(player,fixture.cart,pickup,null),"authored captured-pose recovery refused");
                check((Boolean)value(current,"movingRecovery"),"authored cancellation re-entered procedural body recovery");
                close((Float)value(current,"movementProgress"),.55f,"authored recovery lost its initial pose weight");
                check(value(current,"recoveryPose")==pose && value(current,"recoveryCart")==cart,
                    "cancellation replaced its final rendered pose capture");
                CartTransition.tick(player,(Long)value(current,"recoveryStart")+200_000_000L);
                close(player.variables.get("ToolkitWoodCartClipTime"),(Float)value(current,"progress"),
                    "recovery clock diverged from presentation progress");
                CartTransition.end(player);recovered(fixture);
                check(player.booleanVariables.isEmpty(),"clip direction leaked after cleanup");
                check(player.clipPilot,"presentation cleanup erased the actor's pilot opt-in");
            } finally {CartTransition.end(player);}
        }
        track.release();
    }
    private static Recovery restartRecovery(boolean pickup) throws Exception {
        var fixture=recovery(pickup);var player=fixture.player;player.clipPilot=true;
        var current=state(player);value(current,"authored",true);
        value(current,"recoveryPose",new Matrix4f[]{new Matrix4f().translation(0,.1f,0)});
        value(current,"recoveryCart",new Matrix4f().translation(0,.2f,0));
        // The displayed recovery frame has already moved away from its immutable cancellation seed.
        value(current,"lastPose",new Matrix4f[]{new Matrix4f().translation(0,.3f,0)});
        value(current,"lastPlacement",new CartTransitionMath.Placement(10.2f,20.7f,2.1f,5,20,0,1));
        value(current,"lastReach",.35f);value(current,"lastGrip",.15f);
        value(current,"lastRender",System.nanoTime());
        check(CartTransition.cancel(player,fixture.cart,pickup,null),"authored restart setup refused");
        check(cancelled(player)==current,"authored cancellation did not retain its latest-frame candidate");
        return fixture;
    }
    private static void authoredRestartHandoff() throws Exception {
        for(boolean pickup:new boolean[]{true,false}) for(int route=0;route<3;route++) {
            var fixture=restartRecovery(pickup);var player=fixture.player;
            try {
                var previous=state(player);var pose=value(previous,"lastPose");var placement=value(previous,"lastPlacement");
                String replacement=null;
                if(route>0) {
                    player.getCharacterActions().add(allocate(BaseAction.class));player.performing=true;
                    if(route==2) {replacement=new String("WheelbarrowWood");player.overridePrimaryHandModel=replacement;}
                    CartTransition.tick(player,System.nanoTime());
                    check(state(player)==null && cancelled(player)==previous,
                        "native queue cleanup discarded the immediate restart candidate");
                }
                check(CartTransition.update(player,fixture.cart,pickup,0),"same-item restart refused");
                var restarted=state(player);
                check(restarted!=previous && !(Boolean)value(restarted,"recovering"),"restart reused cancellation progress");
                check(value(restarted,"restartPose")==pose && value(restarted,"restartPlacement")==placement,
                    "restart did not inherit the last displayed pose and cart placement");
                check(value(restarted,"restartPose")!=value(previous,"recoveryPose"),"restart inherited the stale cancellation seed");
                close((Float)value(restarted,"restartReach"),.35f,"restart lost the displayed reach weight");
                close((Float)value(restarted,"restartGrip"),.15f,"restart lost the displayed grip weight");
                close((Float)value(restarted,"progress"),0,"restart did not reset native action progress");
                check((Long)value(restarted,"restartStart")>0 && cancelled(player)==null,"restart candidate was not consumed once");
                check(player.overridePrimaryHandModel==replacement,"restart cleanup erased a replacement model identity");
                check(player.handWrites==0 && fixture.cart.world==(pickup?fixture.world:null)
                    && fixture.cart.container==(pickup?null:player.inventory)
                    && player.primary==(pickup?null:fixture.cart) && player.secondary==player.primary,
                    "restart handoff changed authoritative item ownership");
            } finally {CartTransition.end(player);}
        }
    }
    private static void authoredRestartRefusals() throws Exception {
        for(boolean pickup:new boolean[]{true,false}) for(String failure:new String[]{
            "stale","pruned","item","direction","world","world-item","world-square","world-unloaded","world-placement",
            "hands","inventory","protected","protected-tick","protected-after-cleanup","explicit","global"}) {
            if(pickup && failure.equals("inventory") || !pickup && failure.startsWith("world")) continue;
            var fixture=restartRecovery(pickup);var player=fixture.player;
            try {
                var previous=state(player);Cart item=fixture.cart;boolean direction=pickup;
                switch(failure) {
                    case "stale" -> value(previous,"lastRender",System.nanoTime()-201_000_000L);
                    case "pruned" -> {
                        CartTransition.tick(player,(Long)value(previous,"lastRender")+200_000_001L);
                        check(cancelled(player)==null,"stale cancelled candidate survived the player tick");
                    }
                    case "item" -> {
                        item=allocate(Cart.class);item.kind=fixture.cart.kind;item.worldScale=1;
                        if(pickup) {var world=allocate(WorldItem.class);world.item=item;world.square=player.square;item.world=world;}
                        else {item.container=player.inventory;player.primary=item;player.secondary=item;}
                    }
                    case "direction" -> {
                        direction=!pickup;
                        if(direction) fixture.cart.world=fixture.world;
                        else {fixture.cart.world=null;fixture.cart.container=player.inventory;player.primary=item;player.secondary=item;}
                    }
                    case "world" -> {
                        var world=allocate(WorldItem.class);world.item=item;world.square=player.square;item.world=world;
                    }
                    case "world-item" -> fixture.world.item=allocate(Cart.class);
                    case "world-square" -> fixture.world.square=allocate(IsoGridSquare.class);
                    case "world-unloaded" -> fixture.world.square=null;
                    case "world-placement" -> item.worldScale=1.1f;
                    case "hands" -> {if(pickup) player.primary=allocate(Cart.class);else player.secondary=null;}
                    case "inventory" -> item.container=allocate(ItemContainer.class);
                    case "protected" -> player.protection=3;
                    case "protected-tick" -> {
                        player.protection=3;CartTransition.tick(player,System.nanoTime());
                        check(state(player)==null && cancelled(player)==null,"protected-state cleanup retained a restart candidate");
                        player.protection=0;
                    }
                    case "protected-after-cleanup" -> {
                        player.getCharacterActions().add(allocate(BaseAction.class));
                        CartTransition.tick(player,System.nanoTime());
                        check(state(player)==null && cancelled(player)==previous,"queue cleanup did not preserve its pending candidate");
                        player.actions.clear();player.protection=3;
                        CartTransition.tick(player,System.nanoTime());
                        check(state(player)==null && cancelled(player)==null,"protected tick retained a candidate without an active state");
                        player.protection=0;
                    }
                    case "explicit" -> CartTransition.end(player);
                    case "global" -> CartTransition.end(null);
                }
                if(failure.equals("explicit") || failure.equals("global"))
                    check(cancelled(player)==null,"explicit cleanup retained a cancelled presentation candidate");
                check(CartTransition.update(player,item,direction,0),"restart refusal fixture did not create a new state: "+failure);
                check(value(state(player),"restartPose")==null && value(state(player),"restartPlacement")==null,
                    "unsafe cancelled snapshot inherited: "+pickup+"/"+failure);
                check(!CartTransition.hidden(item),"rejected snapshot hid the native world cart: "+failure);
                check(cancelled(player)==null && player.handWrites==0,"rejected restart leaked a candidate or changed hands");
            } finally {CartTransition.end(player);}
        }
    }
    private static void authoredRestartRecancellation() throws Exception {
        for(boolean pickup:new boolean[]{true,false}) {
            var fixture=restartRecovery(pickup);var player=fixture.player;
            try {
                check(CartTransition.update(player,fixture.cart,pickup,.35),"recancellation restart setup refused");
                var current=state(player);
                check(value(current,"restartPose")!=null && value(current,"restartPlacement")!=null,
                    "recancellation fixture did not inherit the unfinished handoff");
                var pose=new Matrix4f[]{new Matrix4f().translation(0,.4f,0)};
                var cart=new Matrix4f().translation(0,.5f,0);
                value(current,"rendered",true);value(current,"recoveryPose",pose);value(current,"recoveryCart",cart);
                value(current,"nativeRotation",new Quaternionf());value(current,"referenceRotation",new Quaternionf());
                check(CartTransition.cancel(player,fixture.cart,pickup,null),"cancellation during inherited handoff refused");
                check(value(current,"restartPose")==null && value(current,"restartPlacement")==null,
                    "recancellation retained the old handoff and would blend the recovery cart twice");
                check(value(current,"recoveryPose")==pose && value(current,"recoveryCart")==cart,
                    "recancellation discarded the newly displayed recovery seed");
                check((Boolean)value(current,"movingRecovery") && cancelled(player)==current,
                    "recancellation did not retain its own recovery state");
                check(player.handWrites==0,"recancellation changed authoritative hand ownership");
            } finally {CartTransition.end(player);}
        }
    }
    private static zombie.characters.CharacterTimedActions.LuaTimedActionNew pendingAction(Player player,Cart item,String type) throws Exception {
        var action=allocate(zombie.characters.CharacterTimedActions.LuaTimedActionNew.class);
        var table=new se.krka.kahlua.j2se.KahluaTableImpl(new java.util.HashMap<>());
        var meta=new se.krka.kahlua.j2se.KahluaTableImpl(new java.util.HashMap<>());
        meta.rawset("Type",type);table.setMetatable(meta);table.rawset("character",player);
        if(type.equals("ISWalkToTimedActionF")) table.rawset("toolkitWoodCartItem",item);
        else if(type.equals("ToolkitWoodCartPickup")) table.rawset("itemId",(double)item.getID());
        else table.rawset("item",item);
        value(action,"table",table);action.chr=player;action.maxTime=-1;
        return action;
    }
    private static void authoredPendingHandoff() throws Exception {
        for(String type:new String[]{"ISWalkToTimedActionF","ToolkitWoodCartPickup","ToolkitWoodCartSetdown","ToolkitWoodCartDrop"}) {
            boolean pickup=type.equals("ISWalkToTimedActionF") || type.equals("ToolkitWoodCartPickup");
            var fixture=restartRecovery(pickup);var player=fixture.player;
            try {
                var current=state(player);var lease=player.overridePrimaryHandModel;
                float progress=(Float)value(current,"progress");
                player.actions.add(pendingAction(player,fixture.cart,type));player.performing=true;
                long start=System.nanoTime();CartTransition.tick(player,start);
                check(state(player)==current && cancelled(player)==current,"owned pending action discarded its rendered recovery: "+type);
                CartTransition.tick(null);
                check(state(player)==current && cancelled(player)==current,"null-player tick disturbed another player's pending presentation");
                check((Long)value(current,"pendingStart")==start,"pending action did not establish its first-seen deadline");
                check(player.overridePrimaryHandModel==lease,"pending action lost its exact visual lease");
                check(CartTransition.hidden(fixture.cart)==pickup,"pending pickup exposed its ground model");
                check(CartTransition.suppressHeldModel(player)==!pickup,"pending setdown exposed a duplicate held model");
                CartTransition.tick(player,start+100_000_000L);
                close((Float)value(current,"progress"),progress,"pending action continued returning the cart to an endpoint");
                if(type.equals("ISWalkToTimedActionF")) player.actions.set(0,pendingAction(player,fixture.cart,"ToolkitWoodCartPickup"));
                CartTransition.tick(player,start+150_000_000L);
                check((Long)value(current,"pendingStart")==start,"repeated pending ticks or walk-to-pickup handoff extended the deadline");
                check(CartTransition.update(player,fixture.cart,pickup,0),"owned pending action could not take over presentation");
                var fresh=state(player);
                check(fresh!=current && value(fresh,"restartPose")==value(current,"lastPose"),"pending takeover lost its latest displayed pose");
                check((Boolean)value(fresh,"rendered") && CartTransition.hidden(fixture.cart)==pickup,
                    "fresh inherited pickup exposed the ground cart before its first actor render");
                check(player.handWrites==0 && fixture.cart.world==(pickup?fixture.world:null)
                    && player.primary==(pickup?null:fixture.cart) && player.secondary==player.primary,
                    "pending presentation changed native cart ownership");
            } finally {CartTransition.end(player);}
        }
    }
    private static void authoredPendingDeadline() throws Exception {
        for(boolean pickup:new boolean[]{true,false}) for(boolean admittedBeforeDeadline:new boolean[]{true,false}) {
            var fixture=restartRecovery(pickup);var player=fixture.player;
            try {
                var current=state(player);
                long origin=(Long)value(current,"recoveryStart");
                long deadline=origin+(long)Math.ceil((.4+.2*(Float)value(current,"cancelledProgress"))*1_000_000_000.0);
                long admission=deadline-50_000_000L;
                value(current,"lastRender",admission);
                CartTransition.tick(player,admission-1);
                check(state(player)==current,"late pending fixture ended before its original recovery deadline");
                player.actions.add(pendingAction(player,fixture.cart,pickup?"ToolkitWoodCartPickup":"ToolkitWoodCartSetdown"));
                player.performing=true;
                if(admittedBeforeDeadline) {
                    CartTransition.tick(player,admission);
                    check(state(player)==current && cancelled(player)==current,"valid pending action was rejected before the original deadline");
                    check((Long)value(current,"pendingStart")==admission,"late pending action lost its first-seen time");
                    CartTransition.tick(player,deadline-1);
                    check(state(player)==current,"pending presentation ended before the original recovery deadline");
                }
                CartTransition.tick(player,deadline);
                check(state(player)==null && cancelled(player)==null,"late pending action extended the original recovery deadline");
                check(!CartTransition.hidden(fixture.cart) && !CartTransition.suppressHeldModel(player)
                    && player.overridePrimaryHandModel==null,"recovery deadline leaked its visual lease or model suppression");
                check(CartTransition.update(player,fixture.cart,pickup,0),"native action setup failed after pending expiration");
                check(value(state(player),"restartPose")==null && !CartTransition.hidden(fixture.cart),
                    "expired late pending action reused its cancelled presentation snapshot");
                check(player.handWrites==0,"pending deadline cleanup changed authoritative hand ownership");
            } finally {CartTransition.end(player);}
        }
    }
    private static void authoredPendingRefusals() throws Exception {
        for(String type:new String[]{"ISWalkToTimedActionF","ToolkitWoodCartPickup","ToolkitWoodCartSetdown","ToolkitWoodCartDrop"})
            for(String failure:new String[]{"wrong-item","unmarked","wrong-type","native-owner","lua-owner","multiple","finished","stopped",
                "timeout","expired-update","protected","foreign-model","physical-owner"}) {
            boolean pickup=type.equals("ISWalkToTimedActionF") || type.equals("ToolkitWoodCartPickup");
            var fixture=restartRecovery(pickup);var player=fixture.player;
            try {
                var current=state(player);var action=pendingAction(player,fixture.cart,type);var table=action.getTable();
                player.actions.add(action);player.performing=true;String foreign=null;
                switch(failure) {
                    case "wrong-item" -> {
                        if(type.equals("ISWalkToTimedActionF")) table.rawset("toolkitWoodCartItem",allocate(Cart.class));
                        else if(pickup) table.rawset("itemId",(double)fixture.cart.getID()+1);
                        else table.rawset("item",allocate(Cart.class));
                    }
                    case "unmarked" -> table.rawset(type.equals("ISWalkToTimedActionF")?"toolkitWoodCartItem":pickup?"itemId":"item",null);
                    case "wrong-type" -> table.getMetatable().rawset("Type","ISUnequipAction");
                    case "native-owner" -> action.chr=allocate(Player.class);
                    case "lua-owner" -> table.rawset("character",allocate(Player.class));
                    case "multiple" -> player.actions.add(allocate(BaseAction.class));
                    case "finished" -> action.maxTime=0;
                    case "stopped" -> action.forceStop=true;
                    case "protected" -> player.protection=3;
                    case "foreign-model" -> {foreign=new String("WheelbarrowWood");player.overridePrimaryHandModel=foreign;}
                    case "physical-owner" -> {if(pickup) fixture.world.item=allocate(Cart.class);else player.secondary=null;}
                    case "timeout", "expired-update" -> {
                        long start=System.nanoTime();CartTransition.tick(player,start);
                        check(state(player)==current,"valid pending timeout fixture was not retained");
                        if(failure.equals("expired-update")) {
                            value(current,"pendingStart",System.nanoTime()-201_000_000L);
                            value(current,"lastRender",System.nanoTime());
                            check(CartTransition.update(player,fixture.cart,pickup,0),"expired pending update refused the native action");
                            check(value(state(player),"restartPose")==null && !CartTransition.hidden(fixture.cart),
                                "fresh render timestamp bypassed the fixed pending deadline");
                            continue;
                        }
                        CartTransition.tick(player,start+150_000_000L);
                        CartTransition.tick(player,start+200_000_001L);
                    }
                }
                if(!failure.equals("timeout")) CartTransition.tick(player,System.nanoTime());
                check(state(player)==null && !CartTransition.hidden(fixture.cart) && !CartTransition.suppressHeldModel(player),
                    "unsafe pending action retained cart presentation: "+type+"/"+failure);
                if(failure.equals("timeout") || failure.equals("protected"))
                    check(cancelled(player)==null,"expired/protected pending action retained a restart candidate");
                check(player.overridePrimaryHandModel==foreign,"pending cleanup clobbered a foreign visual identity");
                check(player.handWrites==0,"rejected pending action changed native hand ownership");
            } finally {CartTransition.end(player);}
        }
    }
    private static void authoredNodeRetirement() throws Exception {
        var tick=zombie.core.skinnedmodel.animation.AnimationTrack.class.getDeclaredMethod("TickCurrentTime",float.class);
        tick.setAccessible(true);
        var find=zombie.core.skinnedmodel.advancedanimation.AnimLayer.class.getDeclaredMethod("findLiveNode",
            zombie.core.skinnedmodel.advancedanimation.AnimNode.class);find.setAccessible(true);
        for(boolean pickup:new boolean[]{true,false}) {
            var player=allocate(Player.class);player.setVariable("ToolkitWoodCartClipTime",.55f);
            var layer=allocate(zombie.core.skinnedmodel.advancedanimation.AnimLayer.class);
            var character=layer.getClass().getDeclaredField("character");character.setAccessible(true);character.set(layer,player);
            var nodes=new java.util.ArrayList<zombie.core.skinnedmodel.advancedanimation.LiveAnimNode>();
            var nodesField=layer.getClass().getDeclaredField("liveAnimNodes");nodesField.setAccessible(true);nodesField.set(layer,nodes);
            var source=new zombie.core.skinnedmodel.advancedanimation.AnimNode();
            source.name=pickup?"ToolkitWoodCartClipPickup":"ToolkitWoodCartClipSetdown";
            source.parentState=new zombie.core.skinnedmodel.advancedanimation.AnimState();source.parentState.name="actions";
            var unrelatedSource=new zombie.core.skinnedmodel.advancedanimation.AnimNode();
            unrelatedSource.name="UnrelatedAction";unrelatedSource.parentState=source.parentState;
            var old=zombie.core.skinnedmodel.advancedanimation.LiveAnimNode.alloc(layer,source);
            var unrelated=zombie.core.skinnedmodel.advancedanimation.LiveAnimNode.alloc(layer,unrelatedSource);
            old.setActive(true);nodes.add(old);nodes.add(unrelated);
            var tracks=new zombie.core.skinnedmodel.animation.AnimationTrack[4];
            for(int i=0;i<tracks.length;i++) {
                var track=zombie.core.skinnedmodel.animation.AnimationTrack.alloc();tracks[i]=track;
                track.currentClip=new zombie.core.skinnedmodel.animation.AnimationClip(2,java.util.List.of(),"RetirementFixture",false);
                track.animLayer=layer;track.trackTimeToVariable="ToolkitWoodCartClipTime";
                track.looping=false;track.reverse=!pickup;track.setSpeedDelta(1);
                invoke(tick,track,.2f);
            }
            try {
                old.addMainTrack(tracks[0]);old.addMainTrack(tracks[1]);unrelated.addMainTrack(tracks[2]);
                check(invoke(find,layer,source)==old,"native selection did not find the active pilot node");
                check(!CartTransition.retireAuthoredNode(old,!pickup),"retirement accepted the opposite action direction");
                check(tracks[0].trackTimeToVariable!=null,"opposite-direction retirement changed the clock");
                check(!CartTransition.retireAuthoredNode(unrelated,pickup),"retirement changed an unrelated action node");
                check(CartTransition.retireAuthoredNode(old,pickup),"owned pilot node retirement refused");
                check(!CartTransition.retireAuthoredNode(old,pickup),"already-retired node was retired twice");
                check(invoke(find,layer,source)==null,"native selection reused the retired same-direction node");
                player.setVariable("ToolkitWoodCartClipTime",0f);
                for(int i=0;i<2;i++) {
                    check(tracks[i].trackTimeToVariable==null,"outgoing main track retained the shared clock binding");
                    close(tracks[i].getSpeedDelta(),0,"outgoing main track retained autonomous playback");
                    invoke(tick,tracks[i],.2f);
                    close(tracks[i].getCurrentTrackTime(),2*(pickup?.55f:.45f),"new action clock reset moved the fading pose");
                }
                check("ToolkitWoodCartClipTime".equals(tracks[2].trackTimeToVariable),"unrelated track lost its clock binding");
                close(tracks[2].getSpeedDelta(),1,"unrelated track playback speed changed");
                check(invoke(find,layer,unrelatedSource)==unrelated,"retirement made an unrelated node unselectable");
                var fresh=zombie.core.skinnedmodel.advancedanimation.LiveAnimNode.alloc(layer,source);
                fresh.addMainTrack(tracks[3]);fresh.setActive(true);nodes.add(fresh);tracks[3].setSpeedDelta(0);
                check(invoke(find,layer,source)==fresh,"native selection did not choose the fresh same-direction node");
                player.setVariable("ToolkitWoodCartClipTime",.25f);invoke(tick,tracks[3],.2f);
                close(tracks[3].getCurrentTrackTime(),2*(pickup?.25f:.75f),"fresh track did not follow the restarted action clock");
            } finally {for(var track:tracks) track.release();}
        }
    }
    private static void recoveryRefusals() throws Exception {
        for(boolean pickup:new boolean[]{true,false}) for(int failure=0;failure<20;failure++) {
            var fixture=recovery(pickup);var player=fixture.player;var cart=fixture.cart;
            InventoryItem requested=cart;boolean direction=pickup;
            try {
                switch(failure) {
                    case 0 -> {var field=state(player).getClass().getDeclaredField("rendered");field.setAccessible(true);field.setBoolean(state(player),false);}
                    case 1 -> requested=allocate(Cart.class);
                    case 2 -> direction=!pickup;
                    case 3 -> player.performing=true;
                    case 4 -> player.getCharacterActions().add(allocate(BaseAction.class));
                    case 5 -> {player.getCharacterActions().add(allocate(BaseAction.class));player.actions.add(allocate(BaseAction.class));}
                    case 6 -> player.overridePrimaryHandModel="ForeignPrimary";
                    case 7 -> player.overrideSecondaryHandModel="ForeignSecondary";
                    case 8 -> player.primary=pickup?allocate(Cart.class):null;
                    case 9 -> {if(pickup) cart.world=null;else cart.container=allocate(ItemContainer.class);}
                    case 10 -> {if(pickup) fixture.world.item=allocate(Cart.class);else cart.world=fixture.world;}
                    case 11 -> {if(pickup) fixture.world.square=null;else player.secondary=null;}
                    case 12 -> {if(pickup) player.otherFloor=true;else player.secondary=allocate(Cart.class);}
                    case 13,14 -> {
                        var field=state(player).getClass().getDeclaredField(failure==13?"nativeHeight":"referenceHeight");
                        field.setAccessible(true);field.setFloat(state(player),Float.NaN);
                    }
                    case 15,16,17,18 -> {
                        var field=state(player).getClass().getDeclaredField(failure%2==1?"nativeRotation":"referenceRotation");
                        field.setAccessible(true);field.set(state(player),failure<17?null:new Quaternionf(0,0,0,0));
                    }
                    case 19 -> check(CartTransition.update(player,cart,pickup,0),"zero-progress setup refused");
                }
                check(!CartTransition.cancel(player,requested,direction,null),"invalid recovery accepted: "+pickup+"/"+failure);
                check(!(Boolean)value(state(player),"recovering"),"refused cancellation retained recovery state");
                check(!CartTransition.suppressHeldModel(player),"refused cancellation suppressed an equipped visual");
                check(player.modelResets==0 && player.handWrites==0,"refused cancellation changed models or hand ownership");
                check(java.util.Objects.equals(player.overridePrimaryHandModel,failure==6?"ForeignPrimary":null),"refusal overwrote another primary visual");
                check(java.util.Objects.equals(player.overrideSecondaryHandModel,failure==7?"ForeignSecondary":null),"refusal overwrote another secondary visual");
                close(cart.alpha,.7f,"refused recovery changed serialized alpha");
            } finally {CartTransition.end(player);}
        }
    }
    private static void recoveryInterruptions() throws Exception {
        for(boolean pickup:new boolean[]{true,false}) for(int protection=1;protection<=10;protection++) {
            var fixture=recovery(pickup);var player=fixture.player;
            try {
                player.protection=protection;
                check(!CartTransition.cancel(player,fixture.cart,pickup,null),"protected state accepted recovery: "+protection);
                player.protection=0;
                check(CartTransition.cancel(player,fixture.cart,pickup,null),"valid empty-stack recovery refused");
                long start=(Long)value(state(player),"recoveryStart");
                player.protection=protection;CartTransition.tick(player,start+10_000_000L);
                recovered(fixture);
            } finally {CartTransition.end(player);}
        }
        for(boolean pickup:new boolean[]{true,false}) for(int interruption=0;interruption<6;interruption++) {
            var fixture=recovery(pickup);var player=fixture.player;
            try {
                check(CartTransition.cancel(player,fixture.cart,pickup,null),"valid recovery refused");
                long start=(Long)value(state(player),"recoveryStart");
                switch(interruption) {
                    case 0 -> player.getCharacterActions().add(allocate(BaseAction.class));
                    case 1 -> player.performing=true;
                    case 2 -> {if(pickup) fixture.cart.world=null;else player.secondary=null;}
                    case 3 -> player.overridePrimaryHandModel="ReplacementPrimary";
                    case 4 -> player.overrideSecondaryHandModel="ReplacementSecondary";
                    case 5 -> {
                        var previous=state(player);
                        check(CartTransition.update(player,fixture.cart,pickup,.2),"new same-cart action update refused");
                        check(state(player)!=previous && !(Boolean)value(state(player),"recovering"),"new same-cart action reused recovery state");
                        close((Float)value(state(player),"progress"),.2f,"new action inherited recovery progress");
                        check(player.overridePrimaryHandModel==null && player.modelResets==2,"new action retained the stopped action's model lease");
                        continue;
                    }
                }
                CartTransition.tick(player,start+10_000_000L);recovered(fixture);
                check(java.util.Objects.equals(player.overridePrimaryHandModel,interruption==3?"ReplacementPrimary":null),
                    "recovery cleanup erased a replacement primary model");
                check(java.util.Objects.equals(player.overrideSecondaryHandModel,interruption==4?"ReplacementSecondary":null),
                    "recovery cleanup erased a replacement secondary model");
            } finally {CartTransition.end(player);}
        }
    }
    private static void recoveryLeaseIdentity() throws Exception {
        for(boolean pickup:new boolean[]{true,false}) for(boolean tick:new boolean[]{false,true}) {
            var fixture=recovery(pickup);var player=fixture.player;
            try {
                check(CartTransition.cancel(player,fixture.cart,pickup,null),"identity lease setup refused");
                var current=state(player);var lease=player.overridePrimaryHandModel;
                check(lease==value(current,"visualModel") && lease!=fixture.cart.getStaticModel(),
                    "recovery did not acquire a unique model lease token");
                String foreign=tick?fixture.cart.getStaticModel():new String(lease);
                check(foreign!=lease && foreign.equals(lease),"foreign lease fixture must have equal text and different identity");
                player.overridePrimaryHandModel=foreign;
                check(!CartTransition.suppressHeldModel(player),"equal-text foreign override retained held-model suppression");
                if(tick) {
                    player.getCharacterActions().add(allocate(BaseAction.class));
                    CartTransition.tick(player,(Long)value(current,"recoveryStart")+10_000_000L);
                } else CartTransition.end(player);
                recovered(fixture);
                check(player.overridePrimaryHandModel==foreign,"cleanup erased an equal-text foreign model lease");
                check(player.modelResets==1,"cleanup rebuilt a model owned by an equal-text foreign writer");
                CartTransition.end(player);
                check(player.overridePrimaryHandModel==foreign && player.modelResets==1,"repeated cleanup touched a foreign model lease");
            } finally {CartTransition.end(player);}
        }
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
            var ground=new Matrix4f();
            check(CartTransitionMath.worldToActor(pose,model,10.25f,20.75f,2,angle,ground),"grounded stance projects");
            var axle=new org.joml.Vector3f(CartWheelSpin.CENTER_X,CartWheelSpin.CENTER_Y,CartWheelSpin.CENTER_Z);
            var offset=ground.transformPosition(axle,new org.joml.Vector3f())
                .sub(held.transformPosition(axle,new org.joml.Vector3f()));
            close(offset.x,0,"grounded wheel stays laterally aligned");
            close(offset.z,-.06f,"lowering rolls forward to leave feet behind the handle ends at every heading");
        }
        check(CartTransition.dropPlacement(new Matrix4f().m00(Float.NaN),model,0,0,0,0,1)==null,"invalid held transform accepted");
    }
    private static void recoveryModelScope() throws Exception {
        var manager=allocate(zombie.core.skinnedmodel.ModelManager.class);
        var type=zombie.core.skinnedmodel.ModelManager.ModelSlot.class;
        var method=zombie.core.skinnedmodel.ModelManager.class.getDeclaredMethod("DoCharacterModelEquipped",zombie.characters.IsoGameCharacter.class,type);
        method.setAccessible(true);
        for(boolean previous:new boolean[]{false,true}) {
            var ordinary=allocate(Player.class);ordinary.forceNullOverride=previous;
            invoke(method,manager,ordinary,new zombie.core.skinnedmodel.ModelManager.ModelSlot(0,new zombie.core.skinnedmodel.model.ModelInstance(),ordinary));
            check(ordinary.forceNullOverride==previous,"ordinary native model rebuild changed the caller's override flag");
            for(boolean pickup:new boolean[]{false,true}) for(int guard=0;guard<6;guard++) {
                var fixture=recovery(pickup);var player=fixture.player;
                try {
                    check(CartTransition.cancel(player,fixture.cart,pickup,null),"model-scope recovery setup refused");
                    switch(guard) {
                        case 1 -> player.overridePrimaryHandModel="ForeignPrimary";
                        case 2 -> player.overrideSecondaryHandModel="ForeignSecondary";
                        case 3 -> player.getCharacterActions().add(allocate(BaseAction.class));
                        case 4 -> player.protection=3;
                        case 5 -> player.performing=true;
                    }
                    player.forceNullOverride=previous;
                    player.expectedForceNull=previous || !pickup && guard==0;
                    player.modelError=new NativePass();
                    var slot=new zombie.core.skinnedmodel.ModelManager.ModelSlot(0,new zombie.core.skinnedmodel.model.ModelInstance(),player);
                    try {invoke(method,manager,player,slot);throw new AssertionError("native model error was suppressed");}
                    catch(NativePass error) {check(error==player.modelError,"model scope changed the native exception identity");}
                    check(player.modelScopes==1 && player.forceNullOverride==previous,"native model error leaked its temporary visual suppression");
                    check(player.handWrites==0 && player.primary==(pickup?null:fixture.cart) && player.secondary==(pickup?null:fixture.cart),
                        "visual suppression changed native item ownership");
                    check(fixture.cart.world==(pickup?fixture.world:null) && fixture.cart.container==(pickup?null:player.inventory),
                        "visual suppression moved the exact cart");
                } finally {CartTransition.end(player);}
            }
        }
    }
    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        Field field=Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);unsafe=(Unsafe)field.get(null);
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches",CartTransitionTest.class.getClassLoader());
        check(Main.CART_SUPPORTED,"installed B42.21 bytecode fixture unsupported");
        check(Main.CART_TRANSITION_SUPPORTED,"installed transition render bytecode unsupported");
        for(var name:new String[]{"wooden","hidden","place","suppressHeldModel"}) {
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
        bridge();geometry();groundPasses();recoveryLifecycle();authoredClipDefault();authoredClockAndRecovery();authoredRestartHandoff();authoredRestartRefusals();authoredRestartRecancellation();authoredPendingHandoff();authoredPendingDeadline();authoredPendingRefusals();authoredNodeRetirement();recoveryRefusals();recoveryInterruptions();recoveryLeaseIdentity();recoveryModelScope();
        System.out.println("CART_TRANSITION_PASS (scoped exact-owner validation, native yaw geometry, model/depth/sprite/picker/outline suppression and cleanup)");
    }
}
