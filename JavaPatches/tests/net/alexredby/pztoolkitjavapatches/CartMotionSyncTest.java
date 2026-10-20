package net.alexredby.pztoolkitjavapatches;

public final class CartMotionSyncTest {
    private static final class Player extends zombie.characters.IsoPlayer {
        short id;
        float x,y,z;
        boolean moving;
        zombie.inventory.InventoryItem held;
        zombie.characters.NetworkPlayerAI network;
        java.util.Map<String,Float> floats;
        java.util.Map<String,Boolean> booleans;
        zombie.core.skinnedmodel.advancedanimation.AnimNode node;
        java.util.Map<String,zombie.core.skinnedmodel.animation.AnimationClip> clips;
        zombie.iso.Vector2 direction;
        Player() {super(null,null,0,0,0);}
        @Override public short getOnlineID() {return id;}
        @Override public float getX(){return x;}
        @Override public float getY(){return y;}
        @Override public float getZ(){return z;}
        @Override public boolean isPlayerMoving(){return moving;}
        @Override public zombie.characters.NetworkPlayerAI getNetworkCharacterAI(){return network;}
        @Override public zombie.ai.State getCurrentState(){return null;}
        @Override public zombie.inventory.InventoryItem getPrimaryHandItem(){return held;}
        @Override public zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator getAdvancedAnimator(){return null;}
        @Override public zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot setVariable(String key,float value){
            if(floats==null) floats=new java.util.HashMap<>();floats.put(key,value);return null;
        }
        @Override public zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot setVariable(String key,boolean value){
            if(booleans==null) booleans=new java.util.HashMap<>();booleans.put(key,value);return null;
        }
        @Override public float getVariableFloat(String key,float fallback){return floats==null?fallback:floats.getOrDefault(key,fallback);}
        @Override public void clearVariable(String key){if(floats!=null) floats.remove(key);}
        @Override public zombie.iso.Vector2 getDeferredMovement(zombie.iso.Vector2 out){
            var pick=node.blend2dPicker.Pick(getVariableFloat("ToolkitCartStepX",0),getVariableFloat("ToolkitCartStepY",0),
                new zombie.core.skinnedmodel.advancedanimation.Anim2DBlendPicker.PickResults());
            out.set(0,0);
            for(int i=0;i<pick.numNodes;i++) {
                var blend=i==0?pick.node1:i==1?pick.node2:pick.node3;
                float weight=i==0?pick.scale1:i==1?pick.scale2:pick.scale3;
                var clip=clips.get(blend.animName);
                var root=clip.getTotalTranslation("Translation_Data",zombie.core.skinnedmodel.animation.BoneAxis.Y,new zombie.iso.Vector2());
                out.x+=weight*root.x/clip.getDuration();out.y+=weight*root.y/clip.getDuration();
            }
            out.scale(.1f*getVariableFloat("ToolkitCartLegPace",1));return out;
        }
        @Override public void moveUnmodded(float dx,float dy){x+=dx;y+=dy;}
        @Override public boolean faceLocationF(float x,float y){return true;}
        @Override public void setForwardDirection(float x,float y){direction=new zombie.iso.Vector2(x,y);}
        @Override public zombie.iso.Vector2 getForwardDirection(){return direction;}
    }
    private static void check(boolean value,String message) {if(!value) throw new AssertionError(message);}
    private static void connection() throws Exception {
        var field=sun.misc.Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);
        var unsafe=(sun.misc.Unsafe)field.get(null);
        var peer=(zombie.core.raknet.UdpConnection)unsafe.allocateInstance(zombie.core.raknet.UdpConnection.class);
        boolean oldClient=zombie.network.GameClient.client,oldConnected=zombie.network.GameClient.instance.connected;
        var oldPeer=zombie.network.GameClient.connection;
        try {
            zombie.network.GameClient.client=false;zombie.network.GameClient.connection=peer;
            zombie.network.GameClient.instance.connected=true;
            check(!CartMotionSync.connected(),"single-player retained a stale multiplayer connection");
            zombie.network.GameClient.client=true;zombie.network.GameClient.connection=null;
            check(!CartMotionSync.connected(),"missing client transport accepted snapshots");
            zombie.network.GameClient.connection=peer;zombie.network.GameClient.instance.connected=false;
            check(!CartMotionSync.connected(),"client sent snapshots before its native handshake");
            zombie.network.GameClient.instance.connected=true;
            check(!peer.isFullyConnected() && CartMotionSync.connected(),
                "active Host client incorrectly required the server peer's fullyConnected flag");
            zombie.network.GameClient.instance.disconnect(false);
            check(!CartMotionSync.connected(),"native disconnect retained cosmetic snapshot sends");
        } finally {
            zombie.network.GameClient.connection=oldPeer;zombie.network.GameClient.client=oldClient;
            zombie.network.GameClient.instance.connected=oldConnected;
        }
    }
    @SuppressWarnings("unchecked")
    private static void lifecycle() throws Exception {
        var field=sun.misc.Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);
        var unsafe=(sun.misc.Unsafe)field.get(null);
        var first=(Player)unsafe.allocateInstance(Player.class);first.id=1;
        var gone=(Player)unsafe.allocateInstance(Player.class);gone.id=2;
        var replaced=(Player)unsafe.allocateInstance(Player.class);replaced.id=1;
        var motions=CartMotionSync.class.getDeclaredField("remotes");motions.setAccessible(true);
        var actions=CartActionSync.class.getDeclaredField("remotes");actions.setAccessible(true);
        var motionMap=(java.util.Map<Player,CartMotionSync.Remote>)motions.get(null);
        var actionMap=(java.util.Map<Player,CartActionSync.Remote>)actions.get(null);
        motionMap.put(first,new CartMotionSync.Remote());motionMap.put(gone,new CartMotionSync.Remote());
        actionMap.put(first,new CartActionSync.Remote());actionMap.put(gone,new CartActionSync.Remote());
        CartMotionSync.prune(java.util.Map.of((short)1,first),CartMotionSync.HEARTBEAT_NANOS);
        check(motionMap.size()==1 && actionMap.size()==1,"disconnected owner retained sync caches");
        CartMotionSync.prune(java.util.Map.of((short)1,replaced),CartMotionSync.HEARTBEAT_NANOS+1);
        check(motionMap.size()==1,"cleanup exceeded its once-per-second bound");
        CartMotionSync.prune(java.util.Map.of((short)1,replaced),2*CartMotionSync.HEARTBEAT_NANOS);
        check(motionMap.isEmpty() && actionMap.isEmpty(),"reused online ID retained old actor state");
        motionMap.put(first,new CartMotionSync.Remote());actionMap.put(first,new CartActionSync.Remote());
        CartTransition.end(null);
        check(motionMap.isEmpty() && actionMap.isEmpty(),"menu cleanup retained sync state");
    }
    @SuppressWarnings("unchecked")
    private static void nativeCatchup() throws Exception {
        var field=sun.misc.Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);
        var unsafe=(sun.misc.Unsafe)field.get(null);
        var player=(Player)unsafe.allocateInstance(Player.class);
        player.network=(zombie.characters.NetworkPlayerAI)unsafe.allocateInstance(zombie.characters.NetworkPlayerAI.class);
        player.x=10.1f;player.y=20.1f;player.moving=true;
        player.network.targetX=11.2f;player.network.targetY=20.8f;player.network.targetZ=0;
        player.network.moving=false;player.network.predictionType=0;
        var node=new zombie.core.skinnedmodel.advancedanimation.AnimNode();
        var idle=new zombie.core.skinnedmodel.advancedanimation.Anim2DBlend();idle.animName="idle";
        var walk=new zombie.core.skinnedmodel.advancedanimation.Anim2DBlend();walk.animName="walk";walk.posY=1;
        var right=new zombie.core.skinnedmodel.advancedanimation.Anim2DBlend();right.animName="walk";right.posX=1;
        var triangle=new zombie.core.skinnedmodel.advancedanimation.Anim2DBlendTriangle();triangle.node1=idle;triangle.node2=walk;triangle.node3=right;
        node.blend2dPicker=new zombie.core.skinnedmodel.advancedanimation.Anim2DBlendPicker();
        node.blend2dPicker.SetPickTriangles(java.util.List.of(triangle));player.node=node;
        player.clips=new java.util.HashMap<>();
        for(String name:new String[]{"idle","walk"}) {
            var start=new zombie.core.skinnedmodel.animation.Keyframe();var end=new zombie.core.skinnedmodel.animation.Keyframe();
            start.boneName=end.boneName="Translation_Data";start.position=new org.lwjgl.util.vector.Vector3f();
            end.position=new org.lwjgl.util.vector.Vector3f(0,0,name.equals("walk")?-1:0);end.time=1;
            player.clips.put(name,new zombie.core.skinnedmodel.animation.AnimationClip(1,java.util.List.of(start,end),name,true));
        }
        var path=(zombie.pathfind.PathFindBehavior2)unsafe.allocateInstance(zombie.pathfind.PathFindBehavior2.class);
        var owner=path.getClass().getDeclaredField("chr");owner.setAccessible(true);owner.set(path,player);
        var moving=new CartMotionSync.Pose(123,1,1,0,1,1.04f,.8f,0,.1f,0,0,0);
        var stopped=new CartMotionSync.Pose(123,2,1,0,0,1.04f,-1,0,0,0,0,0);
        var remote=new CartMotionSync.Remote();remote.receive(moving.encode(),0);remote.bind(new Object());remote.owned=true;
        remote.receive(stopped.encode(),100_000_000L);remote.blend(.1f);
        player.setVariable("ToolkitCartStepX",0f);player.setVariable("ToolkitCartStepY",0f);
        float beforeX=player.x,beforeY=player.y;
        path.moveToPoint(player.network.targetX,player.network.targetY,1);
        check(player.x==beforeX && player.y==beforeY,"native fixture must reproduce stationary-root catch-up starvation");
        check(CartMotionSync.catchingUp(player),"static owner prediction incorrectly prevented native observer catch-up");
        CartMotionSync.applyLocomotion(player,remote,100_000_000L);
        check(player.getDeferredMovement(new zombie.iso.Vector2()).getLength()>.09f,"stopped aggregate starved native animation root budget");
        check(remote.budget(true,100_000_000L).speed()==.8f,
            "numeric applied root budget was lost during catch-up");
        path.moveToPoint(player.network.targetX,player.network.targetY,1);
        check(player.x>beforeX && player.y>beforeY,"native moveToPoint failed to consume retained animation root budget");
        check(player.network.targetX==11.2f && player.network.targetY==20.8f && !player.network.moving
            && player.network.predictionType==0,"cosmetic catch-up changed native target or packet flags");
        var brake=new CartMotionSync.Pose(123,3,3,0,.001f,.001f,.001f,.8f,-.2f,1,-.1f,1);
        remote.receive(brake.encode(),200_000_000L);
        remote.receive(stopped.encode(),300_000_000L);
        check(remote.budget(true,300_000_000L).y()==1,"tiny braking tail replaced useful catch-up locomotion");
        check(remote.budget(true,CartMotionSync.STALE_NANOS+1)==null,"old moving history retained an unbounded catch-up budget");
        player.x=11.19f;player.y=20.79f;
        check(!CartMotionSync.catchingUp(player),"native same-tile arrival tolerance did not release catch-up");
        player.x=10.99f;player.y=20.8f;player.network.targetX=11.01f;
        check(CartMotionSync.catchingUp(player),"nearby target across a tile boundary was falsely considered arrived");
        player.x=11.01f;player.network.targetZ=1;
        check(CartMotionSync.catchingUp(player),"target on another floor was falsely considered arrived");
        player.network.targetZ=0;player.x=10.1f;player.moving=false;
        check(!CartMotionSync.catchingUp(player),"native action/stopped movement decision was overridden");
        player.moving=true;player.network.targetX=Float.NaN;
        check(!CartMotionSync.catchingUp(player),"invalid native target activated catch-up");
        player.network.targetX=11.2f;
        var late=new CartMotionSync.Remote();late.receive(stopped.encode(),0);
        player.setVariable("ToolkitCartLegPace",.77f);
        CartMotionSync.applyLocomotion(player,late,1);
        check(Boolean.FALSE.equals(player.booleans.get("ToolkitCartPivot")),"late observer without history did not select native locomotion fallback");
        check(player.getVariableFloat("ToolkitCartLegPace",0)==.77f,"native fallback changed custom track cadence");
        var numericStop=new CartMotionSync.Pose(123,4,1,0,1,1,0,0,0,0,0,0);
        check(CartMotionSync.rootStopped(numericStop),"numeric zero budget bypassed catch-up protection");
        remote.bind(new Object());check(remote.budget(true,1)==null,"same-ID cart replacement inherited previous root budget");
        remote.receive(moving.encode(),1);remote.receive("invalid",2);
        check(remote.locomotion==null,"malformed state retained catch-up history");
        remote.receive(moving.encode(),3);remote.receive("",4);
        check(remote.locomotion==null,"explicit release retained catch-up history");
        remote.receive(moving.encode(),5);remote.owned=true;
        var motions=CartMotionSync.class.getDeclaredField("remotes");motions.setAccessible(true);
        ((java.util.Map<Player,CartMotionSync.Remote>)motions.get(null)).put(player,remote);
        CartMotionSync.reset(player);
        check(remote.locomotion==null && !remote.owned,"native cleanup retained borrowed locomotion after action/identity reset");
    }
    @SuppressWarnings("unchecked")
    private static void effortReplication() throws Exception {
        var field=sun.misc.Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);
        var unsafe=(sun.misc.Unsafe)field.get(null);
        var player=(Player)unsafe.allocateInstance(Player.class);
        var cart=(zombie.inventory.types.InventoryContainer)unsafe.allocateInstance(zombie.inventory.types.InventoryContainer.class);
        cart.setModule("SaucedWheelbarrow");cart.setType("WheelbarrowWood");player.held=cart;
        var effort=new CartMotionSync.Pose(123,1,9,0,0,0,0,0,0,0,0,0);
        check(effort.equals(CartMotionSync.parse(effort.encode())),"reserved brace flag lost its bounded v1 roundtrip");
        check(effort.encode().split(",",-1).length==13,"effort added a protocol field");
        for(int flags:new int[]{8,10,11,12,13,14,15,16,-1}) {
            var invalid=new CartMotionSync.Pose(123,1,flags,0,0,0,0,0,0,0,0,0);
            check(!invalid.valid() && CartMotionSync.parse(invalid.encode())==null,"accepted invalid effort flag combination "+flags);
        }
        for(int flags=0;flags<=7;flags++)
            check(CartMotionSync.parse(new CartMotionSync.Pose(123,1,flags,0,0,0,0,0,0,0,0,0).encode())!=null,
                "existing v1 flag combination changed");
        var remote=new CartMotionSync.Remote();remote.receive(effort.encode(),0);remote.owned=true;
        CartMotionSync.applyLocomotion(player,remote,0);
        check(Boolean.TRUE.equals(player.booleans.get("ToolkitCartBrace")),"remote wood did not retain explicit owner effort");
        var stopped=new CartMotionSync.Pose(123,2,1,0,0,0,0,0,0,0,0,0);
        remote.receive(stopped.encode(),1);CartMotionSync.applyLocomotion(player,remote,1);
        check(Boolean.FALSE.equals(player.booleans.get("ToolkitCartBrace")),"ordinary idle inferred effort or retained release");
        remote.receive(effort.encode(),2);cart.setType("WheelbarrowMetal");CartMotionSync.applyLocomotion(player,remote,2);
        check(Boolean.FALSE.equals(player.booleans.get("ToolkitCartBrace")),"wood effort escaped its exact held cart type");
        cart.setType("WheelbarrowWood");player.network=(zombie.characters.NetworkPlayerAI)unsafe.allocateInstance(zombie.characters.NetworkPlayerAI.class);
        player.x=10;player.y=20;player.moving=true;player.network.targetX=11;player.network.targetY=20;
        CartMotionSync.applyLocomotion(player,remote,2);
        check(Boolean.FALSE.equals(player.booleans.get("ToolkitCartBrace")),"effort starved required native remote catch-up");
        player.moving=false;CartMotionSync.applyLocomotion(player,remote,3);
        check(Boolean.TRUE.equals(player.booleans.get("ToolkitCartBrace")),"arrived observer failed to resume owner effort");
        var remotes=CartMotionSync.class.getDeclaredField("remotes");remotes.setAccessible(true);
        ((java.util.Map<Player,CartMotionSync.Remote>)remotes.get(null)).put(player,remote);
        CartMotionSync.reset(player);
        check(Boolean.FALSE.equals(player.booleans.get("ToolkitCartBrace")),"reset retained remote effort");
        var sender=new CartMotionSync.Sender();var identity=new Object();sender.next(stopped,identity,0);
        check(!sender.due(effort,identity,CartMotionSync.CHANGE_NANOS-1)
            && sender.due(effort,identity,CartMotionSync.CHANGE_NANOS),"effort bypassed existing snapshot rate");
    }

    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        var pose=new CartMotionSync.Pose(123,1,7,.25f,-.8f,1.25f,.7f,.85f,-.12f,.14f,-.085f,1);
        check(pose.equals(CartMotionSync.parse(pose.encode())),"snapshot roundtrip lost visual state");
        String encoded=pose.encode();
        for(String malformed:new String[]{"",encoded+",0",encoded.substring(2),encoded.replaceFirst("1,123","2,123"),
            encoded.replace("123,1,7","123,0,7"),encoded.replace("123,1,7","123,1,8"),
            encoded.replace("0.25","NaN"),encoded.replace("0.25","Infinity"),encoded.replace("0.25","1.01"),
            encoded.replace("1.25","-1"),encoded.replace("1.25","2.51"),encoded.replace("0.7","51"),
            encoded.replace("0.7","-0.5"),encoded.replace("0.7","-1.001"),encoded.replace("0.7","-2"),
            encoded.replace("0.85","11"),encoded.replace("-0.12","-1.01"),encoded.replace("0.14","-0.1"),
            encoded.replace("-0.085","-0.501"),"x".repeat(241)})
            check(CartMotionSync.parse(malformed)==null,"accepted malformed snapshot: "+malformed);
        var sender=new CartMotionSync.Sender();
        Object item=new Object(), otherItem=new Object();
        check(sender.due(pose,item,0),"first held snapshot was delayed");
        String first=sender.next(pose,item,0);
        check(!sender.due(pose,item,CartMotionSync.HEARTBEAT_NANOS-1),"idle pose flooded packets");
        check(sender.due(pose,item,CartMotionSync.HEARTBEAT_NANOS),"idle heartbeat missing");
        var changed=new CartMotionSync.Pose(123,1,1,-.2f,.8f,1,1,0,0,0,0,0);
        check(!sender.due(changed,item,CartMotionSync.CHANGE_NANOS-1),"motion exceeded 10 Hz");
        check(sender.due(changed,item,CartMotionSync.CHANGE_NANOS),"changed motion was not published");
        var replacement=new CartMotionSync.Pose(124,1,1,0,1,1,1,0,0,0,0,0);
        check(sender.due(replacement,item,1),"cart identity handoff was throttled");
        check(sender.due(pose,otherItem,1),"same-ID replacement object inherited sender state");
        check(!sender.due(changed,item,-1),"negative elapsed time bypassed the rate cap");
        int sent=0;
        var burst=new CartMotionSync.Sender();
        for(long now=0;now<1_000_000_000L;now+=1_000_000L) {
            var active=now%2_000_000L==0?pose:changed;
            if(burst.due(active,item,now)) {burst.next(active,item,now);sent++;}
        }
        check(sent<=10,"transient input exceeded 10 snapshots per second");
        check(!sender.next(pose,item,CartMotionSync.HEARTBEAT_NANOS).equals(first),"heartbeat cannot refresh receiver age");
        var remote=new CartMotionSync.Remote();
        remote.receive(first,0);
        var modes=new CartMotionSync.Remote();modes.receive(first,0);modes.owned=true;
        String nativeCadence=encoded.replace("0.7","-1");
        check(CartMotionSync.parse(nativeCadence)!=null,"native cadence sentinel rejected");
        modes.receive(nativeCadence,1);modes.blend(.016f);
        check(modes.speed==-1,"native cadence mode interpolated through a numeric root budget");
        modes.receive(encoded,2);modes.blend(.016f);
        check(modes.speed==pose.speed(),"root budget resumed from the negative sentinel");
        remote.bind(item);remote.x=-1;remote.facing=true;
        remote.bind(otherItem);
        check(remote.x==pose.x() && !remote.facing,"same-ID object handoff retained previous visual interpolation");
        check(remote.matches(123,CartMotionSync.STALE_NANOS),"valid snapshot expired too soon");
        check(!remote.matches(124,1),"different cart inherited the old pose");
        check(!remote.matches(123,CartMotionSync.STALE_NANOS+1),"stale snapshot never expired");
        remote.receive(first,CartMotionSync.STALE_NANOS+1);
        check(!remote.matches(123,CartMotionSync.STALE_NANOS+1),"reading unchanged state revived a stale snapshot");
        remote.receive(sender.next(pose,item,CartMotionSync.STALE_NANOS+2),CartMotionSync.STALE_NANOS+2);
        check(remote.matches(123,CartMotionSync.STALE_NANOS+2),"fresh heartbeat failed to resume observer");
        remote.receive("",CartMotionSync.STALE_NANOS+3);
        check(!remote.matches(123,CartMotionSync.STALE_NANOS+3),"release retained the pose");
        remote.receive("invalid",CartMotionSync.STALE_NANOS+4);
        check(remote.pose==null,"malformed packet retained prior pose");
        var restarted=new CartMotionSync.Sender();
        remote.receive(restarted.next(pose,item,1),CartMotionSync.STALE_NANOS+5);
        check(remote.matches(123,CartMotionSync.STALE_NANOS+5),"sender reset serial failed after ordered release");
        effortReplication();
        lifecycle();
        connection();
        nativeCatchup();
        System.out.println("CART_MOTION_SYNC_PASS");
    }
}
