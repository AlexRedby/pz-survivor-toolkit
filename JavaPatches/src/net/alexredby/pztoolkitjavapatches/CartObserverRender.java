package net.alexredby.pztoolkitjavapatches;

import java.util.WeakHashMap;
import me.zed_0xff.zombie_buddy.Accessor;
import zombie.GameTime;
import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.ModelCamera;
import zombie.core.skinnedmodel.ModelCameraRenderData;
import zombie.core.skinnedmodel.ModelManager;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;
import zombie.inventory.InventoryItem;
import zombie.network.GameClient;

/** Keep the remote wooden cart's camera and model snapshots on one validated cosmetic pose. */
public final class CartObserverRender {
    private static final class Visual {
        final CartObserverPose.State pose=new CartObserverPose.State();
        InventoryItem item;
        int itemId,z;
        Object connection;
        void bind(InventoryItem next,int floor,Object peer) {
            if(item!=next || itemId!=next.getID() || z!=floor || connection!=peer) pose.clear();
            item=next;itemId=next.getID();z=floor;connection=peer;
        }
    }
    private static final WeakHashMap<IsoPlayer,Visual> visuals=new WeakHashMap<>();
    // Only the producer uses pending. initRenderData may run in TextureDraw's slot-init executor.
    private static final ThreadLocal<DrawPose> pending=new ThreadLocal<>();
    private static final WeakHashMap<ModelSlotRenderData,DrawPose> slots=new WeakHashMap<>();
    private static boolean disabled;

    static record DrawPose(ModelManager.ModelSlot source,IsoPlayer player,
                           float nativeX,float nativeY,float nativeZ,float x,float y,float z,float angle) {}

    /** Exact two-argument camera init exit, on the producer before drawModel/initModel. */
    public static synchronized void capture(ModelCameraRenderData data,ModelCamera camera,ModelManager.ModelSlot source) {
        pending.remove();
        if(disabled || source==null || !(source.character instanceof IsoPlayer player)) return;
        try {
            if(player.isLocalPlayer() || !CartMotionSync.connected() || !CartMotionSync.visualEnabled(player)
                || !CartSteeringHooks.supportedCart(player) || !CartTransition.wooden(player.getPrimaryHandItem())
                || source.model==null || source.model.object!=player || player.getCell()==null
                || player.getCurrentSquare()==null || player.isSittingOnFurniture()) {
                forget(player);return;
            }
            float x=Accessor.tryGet(data,"x",Float.NaN),y=Accessor.tryGet(data,"y",Float.NaN);
            float z=Accessor.tryGet(data,"z",Float.NaN),angle=Accessor.tryGet(data,"angle",Float.NaN);
            if(!Float.isFinite(x) || !Float.isFinite(y) || !Float.isFinite(z) || !Float.isFinite(angle)
                || player.getCell().getGridSquare((int)Math.floor(x),(int)Math.floor(y),(int)Math.floor(z))==null) {
                forget(player);return;
            }
            var state=visuals.computeIfAbsent(player,ignored->new Visual());
            state.bind(player.getPrimaryHandItem(),(int)Math.floor(z),GameClient.connection);
            double front=player.isRunning() || player.isSprinting() || CartMotionSync.fastWeight(player)>1e-3f
                || CartLegPace.woodenFastShift(player)<0?CartFootprint.FAST_FRONT:CartFootprint.WALK_FRONT;
            var accepted=state.pose.update(CartFootprint.world(player),x,y,angle-Math.PI/2,front,
                GameTime.getInstance().getRealworldSecondsSinceLastUpdate());
            if(accepted==null) return;
            queue(data,camera,new DrawPose(source,player,x,y,z,(float)accepted.x(),(float)accepted.y(),z,
                (float)(accepted.heading()+Math.PI/2)));
        } catch(RuntimeException error) {
            disabled=true;clearAll();
            System.err.println("[PZToolkitJavaPatches] Remote cart visual clearance disabled: "+error);
        }
    }

    static void queue(ModelCameraRenderData data,ModelCamera camera,DrawPose pose) {
        data.init(camera,pose.angle,true,pose.x,pose.y,pose.z,false);
        pending.set(pose);
    }

    /** Bind on the producer, before native init calculates depth or can be handed to its worker. */
    public static synchronized void bind(ModelSlotRenderData slot,ModelManager.ModelSlot source) {
        slots.remove(slot);
        var pose=pending.get();pending.remove();
        if(pose==null || pose.source!=source || slot.character!=pose.player || slot.object!=pose.player) return;
        slots.put(slot,pose);
        slot.x=pose.x;slot.y=pose.y;slot.z=pose.z;
    }

    /** Native init overwrites angle after initModel; restore before grounding, grip and wheel snapshots. */
    public static synchronized void prepare(ModelSlotRenderData slot) {
        var pose=slots.get(slot);
        if(pose!=null) slot.animPlayerAngle=pose.angle;
    }

    public static synchronized void release(ModelSlotRenderData slot) {slots.remove(slot);}

    static synchronized void forget(IsoPlayer player) {
        var visual=visuals.remove(player);
        if(visual!=null) visual.pose.clear();
        // Already queued camera/slot snapshots retain their matching pose until postRender.
    }

    static synchronized void clearAll() {
        for(var visual:visuals.values()) visual.pose.clear();
        visuals.clear();
    }

    private CartObserverRender() {}
}
