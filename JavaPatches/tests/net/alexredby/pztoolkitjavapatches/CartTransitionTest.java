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
        int protection,modelResets,handWrites;
        boolean performing,otherFloor;
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
        @Override public boolean getVariableBoolean(String name){return "IsPerformingAnAction".equals(name) && performing;}
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
        @Override public void clearVariable(String name){if(variables!=null) variables.remove(name);}
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
        bridge();geometry();groundPasses();recoveryLifecycle();recoveryRefusals();recoveryInterruptions();recoveryLeaseIdentity();recoveryModelScope();
        System.out.println("CART_TRANSITION_PASS (scoped exact-owner validation, native yaw geometry, model/depth/sprite/picker/outline suppression and cleanup)");
    }
}
