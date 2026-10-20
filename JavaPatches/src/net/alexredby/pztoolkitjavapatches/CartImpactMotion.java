package net.alexredby.pztoolkitjavapatches;

import java.util.WeakHashMap;
import zombie.ai.states.CollideWithWallState;
import zombie.characters.IsoPlayer;
import zombie.inventory.InventoryItem;
import zombie.iso.Vector2;
import zombie.iso.objects.IsoWorldInventoryObject;
import zombie.network.GameClient;
import zombie.network.GameServer;

/** The released cart stops only inward native root motion during this SP wall-impact episode. */
public final class CartImpactMotion {
    static final long MAX_NANOS=4_000_000_000L;
    private record Contact(InventoryItem item,IsoWorldInventoryObject world,float x,float y,float z,
                           float worldX,float worldY,float worldZ,float rotation,double nx,double ny,long started) {}
    private static final WeakHashMap<IsoPlayer,Contact> contacts=new WeakHashMap<>();
    private static final ThreadLocal<Vector2> result=ThreadLocal.withInitial(Vector2::new);

    private static boolean actor(IsoPlayer player) {
        return Main.CART_SUPPORTED && Main.CART_TRANSITION_SUPPORTED && !GameClient.client && !GameServer.server
            && player!=null && player.isLocalPlayer() && !player.isNpc() && !player.isDead()
            && player.isCurrentState(CollideWithWallState.instance()) && !player.isGettingUp()
            && !player.isGrappling() && !player.isBeingGrappled() && !player.isRagdollSimulationActive()
            && player.getVehicle()==null;
    }

    static synchronized void begin(IsoPlayer player,InventoryItem item,IsoWorldInventoryObject world) {
        contacts.remove(player);
        if(!actor(player) || !CartTransition.wooden(item) || world==null || world.getSquare()==null
            || item.getWorldItem()!=world || world.getItem()!=item || player.getPrimaryHandItem()!=null
            || player.getSecondaryHandItem()!=null) return;
        float x=player.getNextX(),y=player.getNextY(),z=player.getZ();
        double dx=world.getWorldPosX()-player.getX(),dy=world.getWorldPosY()-player.getY(),distance=Math.hypot(dx,dy);
        if(!Float.isFinite(x+y+z) || !Double.isFinite(distance) || distance<.15 || distance>1.5
            || Math.hypot(x-player.getX(),y-player.getY())>.5) return;
        // Include already requested movement; never undo a step or teleport the actor backwards.
        contacts.put(player,new Contact(item,world,x,y,z,world.getWorldPosX(),world.getWorldPosY(),world.getWorldPosZ(),
            item.getWorldZRotation(),dx/distance,dy/distance,System.nanoTime()));
    }

    private static boolean valid(IsoPlayer player,Contact contact,long now) {
        var container=contact.item.getContainer();
        float slow=player.getSlowFactor();
        return actor(player) && Float.isFinite(slow) && slow>=0 && slow<=1 && now>=contact.started && now-contact.started<MAX_NANOS
            && player.getPrimaryHandItem()==null && player.getSecondaryHandItem()==null
            && player.getZ()==contact.z && Math.hypot(player.getX()-contact.x,player.getY()-contact.y)<2
            && contact.item.getWorldItem()==contact.world && contact.world.getItem()==contact.item
            && contact.world.getSquare()!=null && (container==null || "floor".equals(container.getType()))
            && Math.abs(contact.world.getWorldPosX()-contact.worldX)<.001
            && Math.abs(contact.world.getWorldPosY()-contact.worldY)<.001
            && Math.abs(contact.world.getWorldPosZ()-contact.worldZ)<.001
            && contact.item.getWorldZRotation()==contact.rotation;
    }

    static Vector2 clip(float x,float y,double nextX,double nextY,double originX,double originY,
                        double nx,double ny,Vector2 out) {
        out.set(x,y);
        if(!Double.isFinite(x+y+nextX+nextY+originX+originY+nx+ny)) return out;
        double inward=x*nx+y*ny,available=Math.max(0,(originX-nextX)*nx+(originY-nextY)*ny);
        if(inward>available) out.set((float)(x-(inward-available)*nx),(float)(y-(inward-available)*ny));
        return out;
    }

    public static synchronized Vector2 movement(IsoPlayer player,float x,float y) {
        var out=result.get().set(x,y);
        var contact=contacts.get(player);
        if(contact==null) return out;
        if(!valid(player,contact,System.nanoTime())) {contacts.remove(player);return out;}
        return clip(x,y,player.getNextX(),player.getNextY(),contact.x,contact.y,contact.nx,contact.ny,out);
    }

    static synchronized void tick() {
        long now=System.nanoTime();
        contacts.entrySet().removeIf(entry->!valid(entry.getKey(),entry.getValue(),now));
    }

    static synchronized void reset() {contacts.clear();}
    private CartImpactMotion() {}
}
