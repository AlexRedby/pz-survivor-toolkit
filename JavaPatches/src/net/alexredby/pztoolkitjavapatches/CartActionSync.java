package net.alexredby.pztoolkitjavapatches;

import java.util.Objects;
import java.util.WeakHashMap;
import zombie.GameTime;
import zombie.characters.IsoPlayer;
import zombie.inventory.InventoryItem;
import zombie.network.GameClient;

/** Action presentation has a separate lease from ordinary held-cart locomotion. */
public final class CartActionSync {
    static final String KEY="ToolkitCartActionPose";
    private static final WeakHashMap<IsoPlayer, Sender> senders=new WeakHashMap<>();
    private static final WeakHashMap<IsoPlayer, Remote> remotes=new WeakHashMap<>();
    private static long generation;

    static record Pose(int cart,long action,long serial,int flags,float progress,float cancelled,
                       float x,float y,float z,float xr,float zr,float yr,float scale) {
        boolean pickup() {return (flags&1)!=0;}
        boolean recovering() {return (flags&2)!=0;}
        boolean valid() {
            return action>0 && serial>0 && flags>=0 && flags<=3
                && Float.isFinite(progress) && Float.isFinite(cancelled) && progress>=0 && progress<=1
                && cancelled>=0 && cancelled<=1 && (!recovering() || cancelled>0 && progress<=cancelled)
                && Float.isFinite(x) && Float.isFinite(y) && Math.abs(x)<=1_000_000 && Math.abs(y)<=1_000_000
                && Float.isFinite(z) && z>=-32 && z<=64
                && Float.isFinite(xr) && Float.isFinite(zr) && Float.isFinite(yr)
                && Math.abs(xr)<=360 && Math.abs(zr)<=360 && Math.abs(yr)<=360
                && Float.isFinite(scale) && scale>0 && scale<=100;
        }
        boolean nearby(float px,float py,float pz) {
            return Math.hypot(x-px,y-py)<=2.5 && Math.abs(z-pz)<=.25;
        }
        CartTransitionMath.Placement placement() {return new CartTransitionMath.Placement(x,y,z,xr,zr,yr,scale);}
        String body() {return cart+","+action+","+flags+","+q(progress)+","+q(cancelled)+","+x+","+y+","+z
            +","+xr+","+zr+","+yr+","+scale;}
        String encode(long packet) {return "1,"+packet+","+body();}
        private static float q(float value) {return Math.round(value*1000)/1000f;}
    }

    static Pose parse(String value) {
        if(value==null || value.length()>300) return null;
        var f=value.split(",",-1);
        if(f.length!=14 || !f[0].equals("1")) return null;
        try {
            var pose=new Pose(Integer.parseInt(f[2]),Long.parseLong(f[3]),Long.parseLong(f[1]),Integer.parseInt(f[4]),
                Float.parseFloat(f[5]),Float.parseFloat(f[6]),Float.parseFloat(f[7]),Float.parseFloat(f[8]),
                Float.parseFloat(f[9]),Float.parseFloat(f[10]),Float.parseFloat(f[11]),Float.parseFloat(f[12]),Float.parseFloat(f[13]));
            return pose.valid()?pose:null;
        } catch(NumberFormatException ignored) {return null;}
    }

    static final class Sender {
        Object item;
        long serial,sent,action;
        int flags;
        String body;
        boolean due(Pose pose,Object identity,long now) {
            return body==null || item!=identity || action!=pose.action || flags!=pose.flags
                || now-sent>=CartMotionSync.HEARTBEAT_NANOS
                || !body.equals(pose.body()) && now-sent>=CartMotionSync.CHANGE_NANOS;
        }
        String next(Pose pose,Object identity,long now) {
            item=identity;action=pose.action;flags=pose.flags;body=pose.body();sent=now;
            return pose.encode(++serial);
        }
    }

    static final class Remote {
        String raw;
        Pose pose;
        long received;
        float progress;
        void receive(String value,long now) {
            if(Objects.equals(raw,value)) return;
            var previous=pose;
            raw=value;pose=parse(value);received=now;
            if(pose!=null && (previous==null || previous.action!=pose.action || previous.cart!=pose.cart)) progress=pose.progress;
            if(pose!=null && pose.recovering()) progress=Math.min(progress,pose.cancelled);
        }
        boolean fresh(long now) {return pose!=null && now-received<=CartMotionSync.STALE_NANOS;}
        float progress(float seconds) {
            progress+=(pose.progress-progress)*(float)(1-Math.exp(-Math.max(0,Math.min(.1,seconds))/.06));
            return progress;
        }
    }

    static synchronized long generation() {return ++generation;}

    static void publish(IsoPlayer player,InventoryItem item,long action,boolean pickup,boolean recovering,
                        float progress,float cancelled,CartTransitionMath.Placement placement) {
        if(!Main.CART_SYNC_SUPPORTED || !CartMotionSync.connected() || !player.isLocalPlayer() || placement==null) return;
        var pose=new Pose(item.getID(),action,1,(pickup?1:0)|(recovering?2:0),progress,cancelled,
            placement.x(),placement.y(),placement.z(),placement.xRotation(),placement.zRotation(),placement.yRotation(),placement.worldScale());
        if(!pose.valid() || !pose.nearby(player.getX(),player.getY(),player.getZ())) {end(player);return;}
        var sender=senders.computeIfAbsent(player,ignored->new Sender());
        long now=System.nanoTime();
        if(sender.due(pose,item,now)) player.setVariable(KEY,sender.next(pose,item,now));
    }

    static void end(IsoPlayer player) {
        if(senders.remove(player)!=null && Main.CART_SYNC_SUPPORTED && CartMotionSync.connected() && player.isLocalPlayer())
            player.setVariable(KEY,"");
    }

    static void forget(IsoPlayer player) {remotes.remove(player);}
    static void clearAll() {senders.clear();remotes.clear();}

    static boolean update(IsoPlayer player) {
        if(!Main.CART_SYNC_SUPPORTED || !Main.CART_TRANSITION_SUPPORTED || !CartMotionSync.connected() || player.isLocalPlayer()) return false;
        var remote=remotes.computeIfAbsent(player,ignored->new Remote());
        long now=System.nanoTime();
        remote.receive(player.getVariableString(KEY),now);
        if(remote.fresh(now) && remote.pose.nearby(player.getX(),player.getY(),player.getZ())
            && CartTransition.remote(player,remote.pose,remote.progress(GameTime.getInstance().getRealworldSecondsSinceLastUpdate()))) return true;
        CartTransition.endRemote(player);
        return false;
    }

    private CartActionSync() {}
}
