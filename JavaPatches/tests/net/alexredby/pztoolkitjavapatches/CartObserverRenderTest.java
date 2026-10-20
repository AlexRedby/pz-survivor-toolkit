package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;
import sun.misc.Unsafe;
import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.ModelCamera;
import zombie.core.skinnedmodel.ModelCameraRenderData;
import zombie.core.skinnedmodel.ModelManager;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;

public final class CartObserverRenderTest {
    private static final class Camera extends ModelCamera {
        @Override public void Begin() {}
        @Override public void End() {}
    }
    private static final class Player extends IsoPlayer {
        Player() {super(null,null,0,0,0);}
        @Override public void setTargetAndCurrentDirection(float x,float y) {
            throw new AssertionError("cosmetic snapshot changed native actor direction");
        }
    }
    private static Unsafe unsafe;
    private static void check(boolean value,String message) {if(!value) throw new AssertionError(message);}
    private static void close(float expected,float actual,String message) {
        check(Math.abs(expected-actual)<1e-6f,message+": "+expected+" != "+actual);
    }
    private static void field(Object owner,String name,Object value) throws Exception {
        Field field=owner.getClass().getDeclaredField(name);field.setAccessible(true);field.set(owner,value);
    }
    private static ModelSlotRenderData slot(Player player) {
        var slot=new ModelSlotRenderData();slot.character=player;slot.object=player;
        slot.x=10.75f;slot.y=20.5f;slot.z=0;slot.animPlayerAngle=-.5f;
        return slot;
    }
    private static CartObserverRender.DrawPose pose(ModelManager.ModelSlot source,Player player,float x,float y,float angle) {
        return new CartObserverRender.DrawPose(source,player,10.75f,20.5f,0,x,y,0,angle);
    }
    private static void snapshots() throws Exception {
        var player=(Player)unsafe.allocateInstance(Player.class);player.setX(10.75f);player.setY(20.5f);
        var source=(ModelManager.ModelSlot)unsafe.allocateInstance(ModelManager.ModelSlot.class);
        source.character=player;
        var snapshot=new ModelCameraRenderData();var camera=new Camera();var slot=slot(player);
        CartObserverRender.queue(snapshot,camera,pose(source,player,10.4f,20.3f,2.1f));
        // The actor may advance between the two native snapshots; keep the camera's accepted pose.
        slot.x+=.01f;
        CartObserverRender.bind(slot,source);
        close(10.4f,slot.x,"producer position was not set before native depth init");
        close(20.3f,slot.y,"producer y was not set");
        // The native init prefix computes depth from these fields, before it needs a complete game model.
        field(slot,"camCharacterX",10f);field(slot,"camCharacterY",20f);
        field(slot,"fixJigglyModelsSquareX",.125f);field(slot,"fixJigglyModelsSquareY",-.25f);
        slot.squareDepth=Float.NaN;
        try {slot.init(source);throw new AssertionError("incomplete test model unexpectedly initialized");}
        catch(NullPointerException expectedIncompleteModel) {}
        float expected=zombie.iso.IsoDepthHelper.getSquareDepthData(10,20,10.525f,20.05f,0).depthStart;
        close(expected,slot.squareDepth,"native depth prefix used the uncorrected actor position");
        slot.animPlayerAngle=-.5f;
        var failure=new java.util.concurrent.atomic.AtomicReference<Throwable>();
        final var workerSlot=slot;
        var worker=new Thread(()->{try {CartObserverRender.prepare(workerSlot);} catch(Throwable error) {failure.set(error);}});
        worker.start();worker.join();
        check(failure.get()==null,"worker could not read captured slot pose: "+failure.get());
        snapshot.render();
        close(camera.x,slot.x,"actual consumed camera x differs from slot");
        close(camera.y,slot.y,"actual consumed camera y differs from slot");
        close(camera.z,slot.z,"actual consumed camera z differs from slot");
        close(camera.useAngle,slot.animPlayerAngle,"actual camera heading differs from worker slot");
        check(camera.useWorldIso && !camera.inVehicle,"snapshot lost native cart camera mode");
        close(10.75f,player.getX(),"render changed native actor x");close(20.5f,player.getY(),"render changed native actor y");

        CartObserverRender.forget(player);CartObserverRender.clearAll();
        slot.animPlayerAngle=0;CartObserverRender.prepare(slot);
        close(2.1f,slot.animPlayerAngle,"reset split an already queued camera/slot pair");
        CartObserverRender.release(slot);slot.animPlayerAngle=0;CartObserverRender.prepare(slot);
        close(0,slot.animPlayerAngle,"released pooled slot retained old pose");

        slot=slot(player);
        CartObserverRender.queue(snapshot,camera,pose(source,player,10.2f,20.2f,1.7f));
        CartObserverRender.bind(slot,source);
        // An unpaired reuse must drop the old association even without a previous postRender.
        slot.x=10.75f;slot.y=20.5f;slot.animPlayerAngle=0;
        CartObserverRender.bind(slot,source);CartObserverRender.prepare(slot);
        close(10.75f,slot.x,"unpaired reused slot moved");close(0,slot.animPlayerAngle,"unpaired reused slot retained yaw");

        CartObserverRender.queue(snapshot,camera,pose(source,player,10.2f,20.2f,1.7f));
        var other=(ModelManager.ModelSlot)unsafe.allocateInstance(ModelManager.ModelSlot.class);
        CartObserverRender.bind(slot,other);CartObserverRender.bind(slot,source);CartObserverRender.prepare(slot);
        close(0,slot.animPlayerAngle,"wrong model source did not consume stale producer token");
        CartObserverRender.queue(snapshot,camera,pose(source,player,10.2f,20.2f,1.7f));
        CartObserverRender.capture(snapshot,camera,null);
        CartObserverRender.bind(slot,source);CartObserverRender.prepare(slot);
        close(0,slot.animPlayerAngle,"ineligible camera draw retained a stale producer token");
    }

    private static Object value(Object owner,String name) throws Exception {
        var field=owner.getClass().getDeclaredField(name);field.setAccessible(true);return field.get(owner);
    }
    private static void seed(CartObserverPose.State state) {
        check(state.update((a,b,c,d)->false,10,20,0,CartFootprint.WALK_FRONT,1./60)!=null,"visual reset fixture must seed a pose");
    }
    @SuppressWarnings("unchecked")
    private static void lifecycle() throws Exception {
        var visualType=Class.forName(CartObserverRender.class.getName()+"$Visual");
        var constructor=visualType.getDeclaredConstructor();constructor.setAccessible(true);
        var visual=constructor.newInstance();
        var bind=visualType.getDeclaredMethod("bind",zombie.inventory.InventoryItem.class,int.class,Object.class);
        bind.setAccessible(true);
        var state=(CartObserverPose.State)value(visual,"pose");
        var first=(zombie.inventory.types.InventoryContainer)unsafe.allocateInstance(zombie.inventory.types.InventoryContainer.class);
        var replacement=(zombie.inventory.types.InventoryContainer)unsafe.allocateInstance(zombie.inventory.types.InventoryContainer.class);
        first.setID(71);replacement.setID(71);
        Object connection=new Object(),reconnected=new Object();
        bind.invoke(visual,first,0,connection);seed(state);
        Object accepted=value(state,"accepted");
        bind.invoke(visual,first,0,connection);
        check(value(state,"accepted")==accepted,"stable item/floor/connection discarded current visual continuity");
        bind.invoke(visual,replacement,0,connection);
        check(value(state,"accepted")==null && value(state,"rawPrevious")==null,
            "replaced cart with reused native ID retained the previous cart's pose");
        seed(state);replacement.setID(72);bind.invoke(visual,replacement,0,connection);
        check(value(state,"accepted")==null,"same item object with changed native ID retained old pose");
        seed(state);bind.invoke(visual,replacement,1,connection);
        check(value(state,"accepted")==null,"floor change retained a visual anchor on the old level");
        seed(state);bind.invoke(visual,replacement,1,reconnected);
        check(value(state,"accepted")==null,"replacement client connection retained an old remote pose");

        var player=(Player)unsafe.allocateInstance(Player.class);
        var visualsField=CartObserverRender.class.getDeclaredField("visuals");visualsField.setAccessible(true);
        var visuals=(java.util.Map<IsoPlayer,Object>)visualsField.get(null);
        seed(state);visuals.put(player,visual);CartMotionSync.reset(player);
        check(!visuals.containsKey(player) && value(state,"accepted")==null,
            "motion reset retained the actor's observer state");
        seed(state);visuals.put(player,visual);CartMotionSync.clearAll();
        check(visuals.isEmpty() && value(state,"accepted")==null,"connection cleanup retained observer visual state");
    }

    /** These are ordering contracts required by the producer/worker bridge, checked on the real jar. */
    private static java.util.List<String> instructions(Class<?> type,String method,String descriptor) throws Exception {
        var result=new java.util.ArrayList<String>();
        try(var stream=type.getResourceAsStream("/"+type.getName().replace('.','/')+".class")) {
            new ClassReader(stream).accept(new ClassVisitor(Opcodes.ASM9) {
                @Override public MethodVisitor visitMethod(int access,String name,String desc,String signature,String[] exceptions) {
                    if(!name.equals(method) || descriptor!=null && !descriptor.equals(desc)) return null;
                    return new MethodVisitor(Opcodes.ASM9) {
                        @Override public void visitMethodInsn(int opcode,String owner,String name,String desc,boolean itf) {
                            result.add(owner+"."+name);
                        }
                        @Override public void visitFieldInsn(int opcode,String owner,String name,String desc) {
                            if(opcode==Opcodes.PUTFIELD) result.add("set:"+name);
                        }
                    };
                }
            },ClassReader.SKIP_DEBUG|ClassReader.SKIP_FRAMES);
        }
        return result;
    }
    private static void before(java.util.List<String> code,String first,String second) {
        check(code.indexOf(first)>=0 && code.indexOf(second)>code.indexOf(first),"native ordering changed: "+first+" before "+second);
    }
    private static void ordering() throws Exception {
        var sprite=instructions(zombie.iso.sprite.IsoSprite.class,"renderActiveModel",null);
        before(sprite,"zombie/core/skinnedmodel/ModelCameraRenderData.init","zombie/core/SpriteRenderer.drawModel");
        var draw=instructions(zombie.core.textures.TextureDraw.class,"drawModel",null);
        before(draw,"zombie/core/skinnedmodel/model/ModelSlotRenderData.initModel","java/util/concurrent/ExecutorService.submit");
        before(draw,"zombie/core/skinnedmodel/model/ModelSlotRenderData.initModel","zombie/core/skinnedmodel/model/ModelSlotRenderData.init");
        var init=instructions(ModelSlotRenderData.class,"init",null);
        before(init,"set:squareDepth","zombie/core/skinnedmodel/model/ModelSlotRenderData.initRenderData");
        before(init,"set:animPlayerAngle","zombie/core/skinnedmodel/model/ModelSlotRenderData.initRenderData");
        var hook=instructions(Main.CartFloor.class,"enter",null);
        check(hook.contains("net/alexredby/pztoolkitjavapatches/CartObserverRender.prepare"),"pre-grounding pose hook missing");
    }
    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        var field=Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);unsafe=(Unsafe)field.get(null);
        check(Main.CART_OBSERVER_SUPPORTED,"observer render bytecode is unsupported");
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches",CartObserverRenderTest.class.getClassLoader());
        snapshots();lifecycle();ordering();
        System.out.println("CART_OBSERVER_RENDER_PASS (real camera consumption, async slot pairing, pooling, item/connection lifecycle and native depth/order)");
        System.exit(0);
    }
}
