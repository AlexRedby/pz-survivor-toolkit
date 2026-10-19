package net.alexredby.pztoolkitjavapatches;

import java.util.WeakHashMap;
import zombie.GameTime;
import zombie.ai.states.CollideWithWallState;
import zombie.characters.IsoPlayer;
import zombie.network.GameClient;

/** One bounded cosmetic snapshot; native packets retain movement and equipment authority. */
public final class CartMotionSync {
    static final String KEY="ToolkitCartPose";
    static final long CHANGE_NANOS=100_000_000L, HEARTBEAT_NANOS=1_000_000_000L, STALE_NANOS=3_000_000_000L;
    private static final WeakHashMap<IsoPlayer, Sender> senders=new WeakHashMap<>();
    private static final WeakHashMap<IsoPlayer, Remote> remotes=new WeakHashMap<>();
    private static long pruned;

    static record Pose(int cart, long serial, int flags, float x, float y, float pace, float speed,
                       float brakeRate, float lean, float pressure, float side, float fast) {
        boolean valid() {
            return serial>0 && flags>=0 && flags<=7 && Float.isFinite(x) && Float.isFinite(y)
                && Float.isFinite(pace) && Float.isFinite(speed) && Float.isFinite(brakeRate)
                && Float.isFinite(lean) && Float.isFinite(pressure) && Float.isFinite(side) && Float.isFinite(fast)
                && Math.abs(x)<=1 && Math.abs(y)<=1 && pace>=0 && pace<=2.5f && (speed==-1 || speed>=0 && speed<=50)
                && brakeRate>=0 && brakeRate<=10 && Math.abs(lean)<=1 && pressure>=0 && pressure<=1
                && side>=-.5f && side<=0 && fast>=0 && fast<=1;
        }
        String body() {
            return flags+","+q(x)+","+q(y)+","+q(pace)+","+q(speed)+","+q(brakeRate)
                +","+q(lean)+","+q(pressure)+","+q(side)+","+q(fast);
        }
        String encode() { return "1,"+cart+","+serial+","+body(); }
        private static float q(float value) { return Math.round(value*1000)/1000f; }
    }

    static Pose parse(String value) {
        if(value==null || value.length()>240) return null;
        String[] fields=value.split(",",-1);
        if(fields.length!=13 || !fields[0].equals("1")) return null;
        try {
            int cart=Integer.parseInt(fields[1]), flags=Integer.parseInt(fields[3]);
            long serial=Long.parseLong(fields[2]);
            float[] f=new float[9];
            for(int i=0;i<f.length;i++) {
                f[i]=Float.parseFloat(fields[i+4]);
                if(!Float.isFinite(f[i])) return null;
            }
            var pose=new Pose(cart,serial,flags,f[0],f[1],f[2],f[3],f[4],f[5],f[6],f[7],f[8]);
            return pose.valid()?pose:null;
        } catch(NumberFormatException ignored) { return null; }
    }

    static final class Sender {
        int cart;
        Object item;
        long serial, sent;
        String body;
        boolean due(Pose pose,Object identity,long now) {
            return body==null || item!=identity || cart!=pose.cart || now-sent>=HEARTBEAT_NANOS
                || !body.equals(pose.body()) && now-sent>=CHANGE_NANOS;
        }
        String next(Pose pose,Object identity,long now) {
            item=identity;cart=pose.cart;body=pose.body();sent=now;
            return new Pose(cart,++serial,pose.flags,pose.x,pose.y,pose.pace,pose.speed,
                pose.brakeRate,pose.lean,pose.pressure,pose.side,pose.fast).encode();
        }
    }

    static final class Remote {
        String raw;
        Pose pose;
        long received;
        Pose locomotion;
        long locomotionReceived;
        boolean owned;
        Object item;
        float x,y,pace,speed,lean,pressure,side,fast;
        double heading;
        boolean facing;
        void receive(String value,long now) {
            if(java.util.Objects.equals(raw,value)) return;
            var previous=pose;
            raw=value;pose=parse(value);received=now;
            if(pose==null || locomotion!=null && locomotion.cart!=pose.cart) locomotion=null;
            if(pose!=null && (pose.flags&2)==0 && (pose.x!=0 || pose.y!=0) && pose.pace>0 && pose.speed!=0) {
                locomotion=pose;locomotionReceived=now;
            }
            if(pose!=null && !owned) seed();
            else if(pose!=null && (previous==null || (previous.speed<0)!=(pose.speed<0))) speed=pose.speed;
        }
        void bind(Object identity) {
            if(item==identity) return;
            if(item!=null) locomotion=null;
            item=identity;facing=false;
            seed();
        }
        Pose budget(boolean catchup,long now) {
            if(!catchup) return pose;
            return locomotion!=null && locomotion.cart==pose.cart && now-locomotionReceived<=STALE_NANOS?locomotion:null;
        }
        private void seed() {
            if(pose!=null) {
                x=pose.x;y=pose.y;pace=pose.pace;speed=pose.speed;
                lean=pose.lean;pressure=pose.pressure;side=pose.side;fast=pose.fast;
            }
        }
        boolean matches(int cart,long now) {return pose!=null && pose.cart==cart && now-received<=STALE_NANOS;}
        void blend(float seconds) {
            float t=(float)(1-Math.exp(-Math.max(0,Math.min(.1,seconds))/.06));
            x+=(pose.x-x)*t;y+=(pose.y-y)*t;pace+=(pose.pace-pace)*t;
            if(pose.speed<0) speed=-1;
            else speed+=(pose.speed-speed)*t;
            lean+=(pose.lean-lean)*t;pressure+=(pose.pressure-pressure)*t;side+=(pose.side-side)*t;fast+=(pose.fast-fast)*t;
        }
    }

    public static void publish(IsoPlayer player,double lean,double pressure,float side,float fast,double speed) {
        if(!Main.CART_SYNC_SUPPORTED || !connected() || !player.isLocalPlayer()) return;
        if(!CartSteeringHooks.enabled(player)) { reset(player);return; }
        int flags=(player.getVariableBoolean("ToolkitCartPivot")?1:0)
            |(player.getVariableBoolean("ToolkitCartWoodBrake")?2:0)
            |(player.getVariableBoolean("ToolkitCartBrakeSprint")?4:0);
        var brake=CartLegPace.brakeTrack(player);
        var pose=new Pose(player.getPrimaryHandItem().getID(),1,flags,
            player.getVariableFloat("ToolkitCartStepX",0),player.getVariableFloat("ToolkitCartStepY",0),
            player.getVariableFloat("ToolkitCartLegPace",1),(float)speed,
            brake==null?0:brake.getSpeedDelta(),(float)lean,(float)pressure,side,fast);
        if(!pose.valid()) {reset(player);return;}
        var sender=senders.computeIfAbsent(player,ignored->new Sender());
        long now=System.nanoTime();
        if(sender.due(pose,player.getPrimaryHandItem(),now))
            player.setVariable(KEY,sender.next(pose,player.getPrimaryHandItem(),now));
    }

    private static boolean eligible(IsoPlayer player) {
        return !player.isNpc() && player.getVariableBoolean("ToolkitCartMotion")
            && !player.isAiming() && !player.isSneaking() && player.getVehicle()==null
            && CartSteeringHooks.supportedCart(player) && !player.isDead() && !player.hasHitReaction()
            && !player.isKnockedDown() && !player.isGettingUp() && !player.isGrappling()
            && !player.isBeingGrappled() && !player.isRagdollSimulationActive()
            && !player.getVariableBoolean("IsPerformingAnAction")
            && !player.isCurrentState(CollideWithWallState.instance());
    }

    static boolean rootStopped(Pose pose) {
        return pose.speed==0 || pose.pace==0 || (pose.flags&1)!=0 && pose.x==0 && pose.y==0;
    }

    static boolean catchingUp(IsoPlayer player) {
        var network=player.getNetworkCharacterAI();
        if(network==null || !player.isPlayerMoving() || !Float.isFinite(network.targetX) || !Float.isFinite(network.targetY)) return false;
        // IsoPlayer.updateRemotePlayer uses the effective native target and this same arrival test.
        return Math.floor(player.getX())!=Math.floor(network.targetX) || Math.floor(player.getY())!=Math.floor(network.targetY)
            || Math.floor(player.getZ())!=network.targetZ
            || Math.abs(player.getX()-network.targetX)+Math.abs(player.getY()-network.targetY)>.2f;
    }

    /** Called at the animation hook, after native remote interpolation and collisions. */
    public static boolean update(IsoPlayer player) {
        if(Main.CART_SYNC_SUPPORTED && GameClient.client) {
            if(connected()) prune(GameClient.IDToPlayerMap,System.nanoTime());
            else {clearAll();CartActionSync.clearAll();}
        }
        if(player.isLocalPlayer()) return false;
        if(!Main.CART_SYNC_SUPPORTED || !connected()) return true;
        var remote=remotes.computeIfAbsent(player,ignored->new Remote());
        if(CartActionSync.update(player)) {clear(player,remote);return true;}
        long now=System.nanoTime();
        remote.receive(player.getVariableString(KEY),now);
        if(!eligible(player) || !remote.matches(player.getPrimaryHandItem().getID(),now)) {
            clear(player,remote);return true;
        }
        remote.bind(player.getPrimaryHandItem());
        CartGrounding.refreshRemoteModel(player);
        remote.blend(GameTime.getInstance().getRealworldSecondsSinceLastUpdate());
        remote.owned=true;
        applyLocomotion(player,remote,now);
        var network=player.getNetworkCharacterAI();
        if(network!=null && Float.isFinite(network.prediction.direction)) {
            double target=network.prediction.direction;
            if(!remote.facing) {remote.heading=target;remote.facing=true;}
            double dt=Math.max(0,Math.min(.1,GameTime.getInstance().getRealworldSecondsSinceLastUpdate()));
            remote.heading+=CartSteeringMath.wrap(target-remote.heading)*(1-Math.exp(-dt/.06));
            player.setTargetAndCurrentDirection((float)Math.cos(remote.heading),(float)Math.sin(remote.heading));
        }
        return true;
    }

    static void applyLocomotion(IsoPlayer player,Remote remote,long now) {
        boolean catchup=rootStopped(remote.pose) && catchingUp(player);
        var budget=remote.budget(catchup,now);
        float x=catchup && budget!=null?budget.x:remote.x,y=catchup && budget!=null?budget.y:remote.y;
        float speed=catchup && budget!=null?budget.speed:remote.speed,pace=catchup && budget!=null?budget.pace:remote.pace;
        // Native remote catch-up consumes these tracks' extracted root motion. A stopped owner pose must not starve it.
        // Without recent movement history, let the ordinary native cart node supply that budget instead.
        player.setVariable("ToolkitCartPivot",budget!=null && (budget.flags&1)!=0);
        player.setVariable("ToolkitCartStepX",x);player.setVariable("ToolkitCartStepY",y);
        player.setVariable("ToolkitCartWoodBrake",(remote.pose.flags&2)!=0);
        player.setVariable("ToolkitCartBrakeSprint",(remote.pose.flags&4)!=0);
        if(budget!=null) {
            if(CartTransition.wooden(player.getPrimaryHandItem()) && (remote.pose.flags&2)==0 && budget.speed>=0)
                CartLegPace.applySpeed(player,speed,x,y);
            CartLegPace.apply(player,pace);
        }
        var brake=CartLegPace.brakeTrack(player);
        if(!catchup && brake!=null && remote.pose.brakeRate>0) brake.setSpeedDelta(remote.pose.brakeRate);
    }

    private static void clear(IsoPlayer player,Remote remote) {
        remote.locomotion=null;
        if(!remote.owned) return;
        remote.owned=false;remote.facing=false;remote.item=null;
        player.setVariable("ToolkitCartPivot",false);
        player.setVariable("ToolkitCartStepX",0f);player.setVariable("ToolkitCartStepY",0f);
        player.setVariable("ToolkitCartWoodBrake",false);player.setVariable("ToolkitCartBrakeSprint",false);
        player.clearVariable("ToolkitCartLegPace");
    }

    public static void reset(IsoPlayer player) {
        if(senders.remove(player)!=null && Main.CART_SYNC_SUPPORTED && connected() && player.isLocalPlayer()) player.setVariable(KEY,"");
        var remote=remotes.remove(player);
        if(remote!=null) clear(player,remote);
    }

    static boolean connected() {
        // fullyConnected belongs to server-side peers; Host clients use GameClient's handshake flag.
        return GameClient.client && GameClient.connection!=null && GameClient.instance.connected;
    }

    static void prune(java.util.Map<Short,IsoPlayer> online,long now) {
        if(now-pruned<HEARTBEAT_NANOS) return;
        pruned=now;
        for(var player:new java.util.ArrayList<>(remotes.keySet())) {
            if(online.get(player.getOnlineID())==player) continue;
            var remote=remotes.remove(player);
            if(remote!=null) clear(player,remote);
            CartActionSync.forget(player);CartTransition.endRemote(player);
        }
    }

    static void clearAll() {
        senders.clear();
        for(var player:new java.util.ArrayList<>(remotes.keySet())) {
            clear(player,remotes.get(player));CartTransition.endRemote(player);
        }
        remotes.clear();pruned=0;
    }

    private static Remote visual(IsoPlayer player) {
        if(!Main.CART_SYNC_SUPPORTED) return null;
        var remote=remotes.get(player);
        return remote!=null && remote.owned && eligible(player)
            && remote.matches(player.getPrimaryHandItem().getID(),System.nanoTime())?remote:null;
    }
    public static boolean visualEnabled(IsoPlayer player) {
        return player.isLocalPlayer()?CartSteeringHooks.enabled(player):visual(player)!=null;
    }
    public static double lean(IsoPlayer player) {var remote=visual(player);return remote==null?0:remote.lean;}
    public static double pressure(IsoPlayer player) {var remote=visual(player);return remote==null?0:remote.pressure;}
    public static float sideClearance(IsoPlayer player) {var remote=visual(player);return remote==null?0:remote.side;}
    public static float fastWeight(IsoPlayer player) {var remote=visual(player);return remote==null?0:remote.fast;}

    private CartMotionSync() {}
}
