package net.alexredby.vehicleinventoryfixture;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Collections;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.vehicles.BaseVehicle;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;
import zombie.network.PacketTypes.PacketType;
import zombie.network.fields.ContainerID;
import zombie.inventory.ItemContainer;
import zombie.inventory.InventoryItem;
import zombie.network.packets.INetworkPacket;
import zombie.inventory.types.InventoryContainer;

/** Read-only test ledger and observation at the actual native transport boundary. */
public final class Main {
    public static volatile String phase="startup";
    private static long window;
    private static int width,height;
    @LuaMethod(name="vehicleInventoryWindowObservation",global=true)
    public static boolean windowObservation(int w,int h) {
        long current=org.lwjglx.opengl.Display.getWindow();
        if(current==0) throw new IllegalStateException("No owned GLFW window for viewport observation");
        boolean changed=current!=window || w!=width || h!=height;
        window=current;width=w;height=h;return changed;
    }

    @LuaMethod(name="vehicleInventoryTracePhase",global=true)
    public static void phase(String value) {phase=value;}
    @LuaMethod(name="vehicleInventoryContents",global=true)
    public static String contents(BaseVehicle vehicle) {
        StringBuilder out=new StringBuilder();
        for(int i=0;i<vehicle.getPartCount();i++) {
            var part=vehicle.getPartByIndex(i);var c=part.getItemContainer();if(c==null)continue;
            var items=items(c);
            out.append(i).append(':').append(part.getId()).append('=').append(items).append(';');
        }
        return out.toString();
    }
    private static ArrayList<String> items(ItemContainer c) {
        var result=new ArrayList<String>();
        for(var item:c.getItems()) {
            String value=item.getID()+":"+item.getFullType();
            if(item instanceof InventoryContainer bag)value+="{"+items(bag.getItemContainer())+"}";
            result.add(value);
        }
        Collections.sort(result);return result;
    }
    /** GameServer.sendAdd/RemoveItemToContainer skips carried bags with no direct parent/world item. */
    @LuaMethod(name="vehicleInventorySendBag",global=true)
    public static void sendBag(BaseVehicle v,ItemContainer c,InventoryItem item,boolean add) {
        var bag=c.containingItem;
        var root=bag==null?null:bag.getOutermostContainer();
        if(root==null || root.getParent()!=v || root.getItemWithID(bag.getID())!=bag)
            throw new IllegalArgumentException("Probe requires a bag directly in this vehicle");
        INetworkPacket.sendToRelative(add?PacketType.AddInventoryItemToContainer:PacketType.RemoveInventoryItemFromContainer,
                (int)v.getX(),(int)v.getY(),c,item);
    }
    @LuaMethod(name="vehicleInventoryConnection",global=true)
    public static String connection(IsoPlayer p) {
        var c=GameServer.getConnectionFromPlayer(p);
        return c==null?"absent":c.getConnectedGUID()+":"+System.identityHashCode(c);
    }
    public static void wire(ByteBuffer data,byte order,long guid) {
        if(!GameServer.server || data.limit()<5 || data.get(0)!=(byte)134)return;
        short id=data.getShort(1);String kind;short vehicle;
        if(id==PacketType.VehicleFullUpdate.getId()) {kind="full";vehicle=data.getShort(3);}
        else if((id==PacketType.AddInventoryItemToContainer.getId() || id==PacketType.RemoveInventoryItemFromContainer.getId())
                && data.limit()>=17 && (Byte.toUnsignedInt(data.get(3))==ContainerID.ContainerType.Vehicle.ordinal()
                    || data.limit()>=21 && Byte.toUnsignedInt(data.get(3))==ContainerID.ContainerType.ObjectInVehicle.ordinal())) {
            kind=id==PacketType.AddInventoryItemToContainer.getId()?"add":"remove";vehicle=data.getShort(13);
        } else return;
        System.out.println("[VEHICLE_INVENTORY] WIRE phase="+phase+" kind="+kind+" vehicle="+vehicle+" channel="+order+" guid="+guid);
    }
    @Patch(className="zombie.core.raknet.RakNetPeerInterface",methodName="Send",strictMatch=true)
    public static class Wire {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) ByteBuffer data,@Patch.Argument(3) byte order,@Patch.Argument(4) long guid) {Main.wire(data,order,guid);}
    }
}
