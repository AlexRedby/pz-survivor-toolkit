package net.alexredby.pztoolkitjavapatches;

import java.util.HashMap;
import java.util.WeakHashMap;
import me.zed_0xff.zombie_buddy.Accessor;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import se.krka.kahlua.integration.annotations.LuaMethod;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.model.ItemModelRenderer;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;
import zombie.inventory.InventoryItem;
import zombie.iso.objects.IsoWorldInventoryObject;
import zombie.network.GameClient;
import zombie.network.GameServer;

/** A short SP presentation handoff. Native InstantDrop owns every inventory/world change. */
public final class CartEmergencyDrop {
    static final long FRESH_NANOS=250_000_000L, SETTLE_NANOS=240_000_000L;
    private record Held(InventoryItem item, Matrix4f cart, float x, float y, float z, float angle, long time) {}
    private static final class Release {
        final IsoPlayer player;
        final CartTransitionMath.Placement source, landing;
        final Matrix4f model;
        final long prepared;
        IsoWorldInventoryObject world;
        long started;
        Release(IsoPlayer player,CartTransitionMath.Placement source, CartTransitionMath.Placement landing, Matrix4f model,long now) {
            this.player=player;this.source=source;this.landing=landing;this.model=model;prepared=now;
        }
    }
    private record Restore(Matrix4f matrix, Matrix4f original, Vector3f angle) {}
    private static final WeakHashMap<IsoPlayer,Held> held=new WeakHashMap<>();
    private static final HashMap<InventoryItem,Release> releases=new HashMap<>();
    private static final WeakHashMap<ItemModelRenderer,Restore> modified=new WeakHashMap<>();

    static synchronized void capture(IsoPlayer player, ModelSlotRenderData slot, Matrix4f cart) {
        if(!Main.CART_TRANSITION_SUPPORTED || GameClient.client || GameServer.server || !player.isLocalPlayer()) return;
        var item=player.getPrimaryHandItem();
        if(!CartTransition.wooden(item) || player.getSecondaryHandItem()!=item || item.getWorldItem()!=null
            || cart==null || !cart.isFinite()) {held.remove(player);return;}
        held.put(player,new Held(item,new Matrix4f(cart),slot.x,slot.y,slot.z,slot.animPlayerAngle,System.nanoTime()));
    }

    static boolean fresh(long now,long time,float x,float y,float z,float currentX,float currentY,float currentZ) {
        return now>=time && now-time<=FRESH_NANOS && Float.isFinite(x+y+z+currentX+currentY+currentZ)
            && z==currentZ && Math.hypot(x-currentX,y-currentY)<=.5;
    }

    @LuaMethod(name="toolkitWoodCartImpactPose",global=true)
    public static synchronized KahluaTable prepare(IsoPlayer player,InventoryItem item) {
        if(item!=null) releases.remove(item);
        if(!Main.CART_TRANSITION_SUPPORTED || GameClient.client || GameServer.server || player==null
            || !player.isLocalPlayer() || !CartTransition.wooden(item) || player.getPrimaryHandItem()!=item
            || player.getSecondaryHandItem()!=item || item.getContainer()!=player.getInventory() || item.getWorldItem()!=null) return null;
        var source=held.remove(player);
        long now=System.nanoTime();
        if(source==null || source.item!=item || !fresh(now,source.time,source.x,source.y,source.z,player.getX(),player.getY(),player.getZ())) return null;
        var model=CartTransition.model(item);
        if(model==null) return null;
        var pose=CartTransitionMath.actorToWorldPlacement(source.cart,model,source.x,source.y,source.z,source.angle);
        // Emergency release does not include the normal set-down action's backward stance adjustment.
        var landing=CartTransition.dropPlacement(source.cart,model,source.x,source.y,source.z,source.angle,item.worldScale,0);
        if(pose==null || landing==null || Math.hypot(landing.x()-player.getX(),landing.y()-player.getY())>1.5
            || CartTransition.target(player,landing.x(),landing.y(),source.z)==null) return null;
        releases.put(item,new Release(player,pose,landing,model,now));
        var result=LuaManager.platform.newTable();
        result.rawset("x",(double)landing.x());result.rawset("y",(double)landing.y());
        result.rawset("z",(double)source.z);result.rawset("rotation",(double)landing.zRotation());
        return result;
    }

    @LuaMethod(name="toolkitWoodCartImpactFinish",global=true)
    public static synchronized void finish(IsoPlayer player,InventoryItem item) {
        var release=releases.get(item);
        if(release==null || release.world!=null) return;
        var world=item.getWorldItem();
        if(GameClient.client || GameServer.server || player==null || release.player!=player || player.getPrimaryHandItem()==item
            || player.getSecondaryHandItem()==item || !worldContainer(item) || world==null || world.getSquare()==null || world.getItem()!=item
            || Math.hypot(world.getWorldPosX()-release.landing.x(),world.getWorldPosY()-release.landing.y())>.03
            || Math.abs(world.getWorldPosZ()+.00175f-release.landing.z())>.001) {releases.remove(item);return;}
        long now=System.nanoTime();
        if(now<release.prepared || now-release.prepared>FRESH_NANOS) {releases.remove(item);return;}
        release.world=world;release.started=now;
        world.invalidateRenderChunkLevel(256);
    }

    private static boolean worldContainer(InventoryItem item) {
        // Native loot UI projects the same world item into its per-player floor container.
        var container=item.getContainer();
        return container==null || "floor".equals(container.getType());
    }

    private static boolean owned(InventoryItem item,Release release) {
        return release.world!=null && release.world.getSquare()!=null && item.getWorldItem()==release.world && release.world.getItem()==item && worldContainer(item);
    }

    @LuaMethod(name="toolkitWoodCartImpactTick",global=true)
    public static synchronized void tick() {
        long now=System.nanoTime();
        held.entrySet().removeIf(e->now-e.getValue().time>FRESH_NANOS);
        var entries=releases.entrySet().iterator();
        while(entries.hasNext()) {
            var entry=entries.next();var item=entry.getKey();var release=entry.getValue();
            if(release.world==null) {if(now-release.prepared>FRESH_NANOS) entries.remove();continue;}
            boolean valid=owned(item,release);
            if(!valid || now-release.started>=SETTLE_NANOS || GameClient.client || GameServer.server) entries.remove();
            // Invalidate once more at the endpoint, including removal/pickup, so no intermediate FBO remains cached.
            if(release.world.getSquare()!=null) release.world.invalidateRenderChunkLevel(256);
        }
    }

    static boolean settle(Matrix4f source,Matrix4f ground,double fraction,Matrix4f out) {
        if(!Double.isFinite(fraction)) return false;
        double blend=CartTransitionMath.smooth(fraction);
        if(!CartTransitionMath.blend(source,ground,blend,out)) return false;
        if(fraction<=0 || fraction>=1) return true;
        var axle=new Vector3f(CartWheelSpin.CENTER_X,CartWheelSpin.CENTER_Y,CartWheelSpin.CENTER_Z);
        var start=source.transformPosition(axle,new Vector3f());
        var end=ground.transformPosition(axle,new Vector3f());
        var current=out.transformPosition(axle,new Vector3f());
        // A rigid rotation's interpolated translation otherwise makes the wheel sweep through a small arc.
        out.m30(out.m30()+start.x+(end.x-start.x)*(float)blend-current.x);
        out.m32(out.m32()+start.z+(end.z-start.z)*(float)blend-current.z);
        float low=CartGrounding.woodenLowest(source)+(CartGrounding.woodenLowest(ground)-CartGrounding.woodenLowest(source))*(float)blend;
        out.m31(out.m31()+low-CartGrounding.woodenLowest(out));
        return out.isFinite();
    }

    static synchronized void reset() {
        for(var renderer:new java.util.ArrayList<>(modified.keySet())) clear(renderer);
        held.clear();releases.clear();
    }

    public static synchronized void clear(ItemModelRenderer renderer) {
        var previous=modified.remove(renderer);
        if(previous!=null && Accessor.tryGet(renderer,"transform",(Matrix4f)null)==previous.matrix) {
            previous.matrix.set(previous.original);renderer.angle.set(previous.angle);
        }
    }

    public static synchronized void render(ItemModelRenderer renderer,InventoryItem item) {
        clear(renderer);
        var release=releases.get(item);
        if(release==null || !owned(item,release) || GameClient.client || GameServer.server) return;
        long elapsed=System.nanoTime()-release.started;
        if(elapsed<0 || elapsed>=SETTLE_NANOS) return;
        var transform=Accessor.tryGet(renderer,"transform",(Matrix4f)null);
        if(transform==null || !transform.isFinite()) return;
        var source=new Matrix4f();
        if(!CartTransitionMath.worldToActor(release.source,release.model,renderer.x,renderer.y,renderer.z,(float)Math.PI,source)) return;
        var ground=CartWheelWorld.worldTransform(renderer,transform,new Matrix4f());
        var output=new Matrix4f();
        if(!settle(source,ground,(double)elapsed/SETTLE_NANOS,output)) return;
        modified.put(renderer,new Restore(transform,new Matrix4f(transform),new Vector3f(renderer.angle)));
        transform.set(output);renderer.angle.set(0,0,0);
    }
    private CartEmergencyDrop() {}
}
