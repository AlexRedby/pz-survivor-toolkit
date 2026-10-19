package net.alexredby.pztoolkitjavapatches;

import sun.misc.Unsafe;
import zombie.ai.StateMachine;
import zombie.characters.IsoPlayer;
import zombie.characters.NetworkPlayerAI;
import zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.inventory.types.InventoryContainer;
import zombie.iso.Vector2;
import zombie.network.PacketTypes.PacketType;
import zombie.network.packets.character.PlayerPacket;

public final class CartNetworkHeadingTest {
    private static final class Player extends IsoPlayer {
        InventoryItem primary,secondary;
        ItemContainer inventory;
        NetworkPlayerAI network;
        StateMachine machine;
        float accepted,desired;
        boolean local=true,enabled=true,dead,run=true,sprint;
        Player() {super(null,null,0,0,0);}
        @Override public short getOnlineID() {return 11;}
        @Override public NetworkPlayerAI getNetworkCharacterAI() {return network;}
        @Override public String getActionStateName() {return "movement";}
        @Override public boolean isLocalPlayer() {return local;}
        @Override public java.util.HashMap<Class<? extends zombie.characters.ecs.ECSComponent>,zombie.characters.ecs.ECSComponent> getECSComponentMap() {
            return new java.util.HashMap<>();
        }
        @Override public boolean isNpc() {return false;}
        @Override public boolean isDead() {return dead;}
        @Override public boolean hasHitReaction() {return false;}
        @Override public boolean isKnockedDown() {return false;}
        @Override public boolean isGettingUp() {return false;}
        @Override public boolean isGrappling() {return false;}
        @Override public boolean isBeingGrappled() {return false;}
        @Override public boolean isRagdollSimulationActive() {return false;}
        @Override public boolean hasPath() {return false;}
        @Override public zombie.pathfind.PathFindBehavior2 getPathFindBehavior2() {return null;}
        @Override public StateMachine getStateMachine() {if(machine==null) machine=new StateMachine(this);return machine;}
        @Override public InventoryItem getPrimaryHandItem() {return primary;}
        @Override public InventoryItem getSecondaryHandItem() {return secondary;}
        @Override public ItemContainer getInventory() {return inventory;}
        @Override public Vector2 getAnimForwardDirection(Vector2 out) {return out.set((float)Math.cos(accepted),(float)Math.sin(accepted));}
        @Override public float getDirectionAngleRadians() {return desired;}
        @Override public float getForwardDirectionX() {return (float)Math.cos(desired);}
        @Override public float getForwardDirectionY() {return (float)Math.sin(desired);}
        @Override public boolean isRunning() {return run;}
        @Override public boolean isSprinting() {return sprint;}
        @Override public boolean getVariableBoolean(String name) {return name.equals("ToolkitCartMotion") && enabled;}
        @Override public float getVariableFloat(String name,float fallback) {return name.equals("WalkSpeed")?.8f:fallback;}
        @Override public AdvancedAnimator getAdvancedAnimator() {return null;}
        @Override public zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot setVariable(String name,boolean value) {return null;}
        @Override public zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot setVariable(String name,float value) {return null;}
        @Override public void clearVariable(String name) {}
        @Override public void setTargetAndCurrentDirection(float x,float y) {}
    }

    private static final class NativeAI extends NetworkPlayerAI {
        Player owner;
        float sampled;
        NativeAI(Player owner) {super(owner);}
        @Override public PacketType set(PlayerPacket packet) {
            // This is the native producer's input-facing value before the later collision/animation hook.
            sampled=packet.prediction.direction=owner.getDirectionAngleRadians();
            packet.prediction.x=17;packet.prediction.y=29;packet.prediction.z=2;
            packet.prediction.moveDirection=-.9f;packet.prediction.speed=.75f;packet.prediction.distance=8;
            packet.booleanVariables=123;
            return PacketType.PlayerUpdateReliable;
        }
    }

    private static void check(boolean value,String message) {if(!value) throw new AssertionError(message);}
    private static InventoryContainer cart(Unsafe unsafe,ItemContainer inventory) throws Exception {
        var cart=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
        cart.setModule("SaucedWheelbarrow");cart.setType("WheelbarrowWood");cart.setContainer(inventory);
        return cart;
    }

    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        var field=Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);
        var unsafe=(Unsafe)field.get(null);
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches",CartNetworkHeadingTest.class.getClassLoader());
        check(Main.CART_SYNC_SUPPORTED,"native packet heading fixture is unsupported");
        var player=(Player)unsafe.allocateInstance(Player.class);
        player.local=player.enabled=player.run=true;player.accepted=.7f;
        player.onlineId=11;
        player.inventory=new ItemContainer();player.primary=player.secondary=cart(unsafe,player.inventory);
        var ai=(NativeAI)unsafe.allocateInstance(NativeAI.class);ai.owner=player;player.network=ai;
        // Seed accepted yaw through the existing animation hook, then emulate a later input update before Packet.set.
        CartSteeringHooks.heading(player);
        for(float target:new float[]{player.accepted+(float)Math.PI/4,player.accepted+(float)Math.PI}) {
            player.desired=target;
            var packet=new PlayerPacket();
            check(packet.set(player)==PacketType.PlayerUpdateReliable,"native packet return type changed");
            check(ai.sampled==target && player.desired==target,"packet correction rewrote the local input facing");
            check(Math.abs(packet.prediction.direction-player.accepted)<1e-6,"packet sent turn/reverse intent instead of accepted yaw");
            check(packet.prediction.x==17 && packet.prediction.y==29 && packet.prediction.z==2
                && packet.prediction.moveDirection==-.9f && packet.prediction.speed==.75f && packet.prediction.distance==8,
                "cart heading correction changed native prediction movement");
            check(packet.booleanVariables==123 && packet.id.getID()==11 && packet.variables.getPacketSizeBytes()==11
                && player.run && !player.sprint,"cart heading correction changed native identity/gait/variables");
        }
        for(int guard=0;guard<5;guard++) {
            player.local=guard!=0;player.enabled=guard!=1;player.dead=guard==2;
            var original=player.primary;
            if(guard==3) player.primary=player.secondary=null;
            if(guard==4) player.primary=player.secondary=cart(unsafe,player.inventory);
            var packet=new PlayerPacket();packet.set(player);
            check(packet.prediction.direction==player.desired,"packet correction escaped local enabled same-cart ownership");
            player.primary=player.secondary=original;
        }
        player.local=player.enabled=true;player.dead=false;CartSteeringHooks.reset(player);
        var packet=new PlayerPacket();packet.set(player);
        check(packet.prediction.direction==player.desired,"uninitialized cart state overrode native direction");
        System.out.println("CART_NETWORK_HEADING_PASS");
    }
}
