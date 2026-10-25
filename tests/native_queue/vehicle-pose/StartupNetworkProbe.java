package net.alexredby.vehicleposefixture;

import java.lang.reflect.Field;
import java.util.concurrent.ConcurrentHashMap;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.network.GameClient;
import zombie.network.fields.ContainerID;
import zombie.vehicles.BaseVehicle;
import zombie.vehicles.VehicleManager;

/** Disposable read-only trace. Native unresolved-container handling and errors still execute. */
public final class StartupNetworkProbe {
    public static final ConcurrentHashMap<Short,Long> missing=new ConcurrentHashMap<>();
    public static short field(ContainerID value,String name) {
        try { Field f=ContainerID.class.getDeclaredField(name);f.setAccessible(true);return f.getShort(value); }
        catch (ReflectiveOperationException e) { throw new IllegalStateException(e); }
    }
    public static void before(ContainerID container) {
        if (!GameClient.client || container.containerType==null || !container.containerType.name().contains("Vehicle")) return;
        short id=field(container,"vid");
        if (VehicleManager.instance.getVehicleByID(id)!=null) return;
        missing.putIfAbsent(id,System.currentTimeMillis());
        System.out.println("[STARTUP_NET] MISSING ms="+System.currentTimeMillis()+" vehicle="+id
            +" type="+container.containerType+" part="+field(container,"index")
            +" xyz="+container.x+","+container.y+","+container.z+" worldItem="+container.worldItemId);
        StackTraceElement[] stack=Thread.currentThread().getStackTrace();
        for(int i=2;i<Math.min(stack.length,16);i++) System.out.println("[STARTUP_NET] CALL "+stack[i]);
    }
    public static void registered(BaseVehicle vehicle) {
        if(!GameClient.client) return;
        Long start=missing.remove(vehicle.getId());
        if(start!=null) System.out.println("[STARTUP_NET] REGISTERED vehicle="+vehicle.getId()
            +" delayMs="+(System.currentTimeMillis()-start)+" script="+vehicle.getScriptName()
            +" xyz="+vehicle.getX()+","+vehicle.getY()+","+vehicle.getZ());
    }
    public static int sends;
    public static void outgoing(String kind,Object[] args) {
        if(!zombie.network.GameServer.server || sends>=32 || args==null || args.length<2 || args[1]==null
            || !(args[0] instanceof zombie.inventory.ItemContainer c)
            || !(c.getParent() instanceof BaseVehicle vehicle) || c.vehiclePart==null) return;
        sends++;
        StringBuilder items=new StringBuilder();
        Iterable<?> values=args[1] instanceof java.util.List<?> list?list:java.util.List.of(args[1]);
        for(Object value:values) {
            if(value instanceof zombie.inventory.InventoryItem item) items.append(item.getID()).append(':').append(item.getFullType());
            else items.append(value);
            items.append(',');
        }
        System.out.println("[STARTUP_NET] SEND "+kind+" vehicle="+vehicle.getId()+" part="+c.vehiclePart.getIndex()+":"+c.vehiclePart.getId()+" items="+items);
        StackTraceElement[] stack=Thread.currentThread().getStackTrace();
        for(int i=2;i<Math.min(stack.length,13);i++) System.out.println("[STARTUP_NET] SEND_CALL "+stack[i]);
    }
    public static String contents(BaseVehicle vehicle) {
        StringBuilder out=new StringBuilder();
        for(int i=0;i<vehicle.getPartCount();i++) {
            var part=vehicle.getPartByIndex(i);var c=part.getItemContainer();
            if(c==null) continue;
            var items=new java.util.ArrayList<String>();
            for(var item:c.getItems()) items.add(item.getID()+":"+item.getFullType());
            java.util.Collections.sort(items);
            out.append(i).append(':').append(part.getId()).append('=').append(items).append(';');
        }
        return out.toString();
    }
    @Patch(className="zombie.network.packets.AddInventoryItemToContainerPacket",methodName="setData",strictMatch=true)
    public static class SendAdd {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) Object[] args) { StartupNetworkProbe.outgoing("add",args); }
    }
    @Patch(className="zombie.network.packets.RemoveInventoryItemFromContainerPacket",methodName="setData",strictMatch=true)
    public static class SendRemove {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) Object[] args) { StartupNetworkProbe.outgoing("remove",args); }
    }
    @Patch(className="zombie.network.fields.ContainerID",methodName="findObject",strictMatch=true,warmUp=true)
    public static class Find {
        @Patch.OnEnter
        public static void enter(@Patch.This ContainerID container) { StartupNetworkProbe.before(container); }
    }
    @Patch(className="zombie.vehicles.VehicleManager",methodName="registerVehicle",strictMatch=true)
    public static class Registered {
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) BaseVehicle vehicle) { StartupNetworkProbe.registered(vehicle); }
    }
}
