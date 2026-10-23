package net.alexredby.cartlab;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.IsoPlayer;
import net.alexredby.cartlab.EquipmentLifetime.*;
public final class EquipmentLifetimeAdvice {
    @Patch(className="zombie.util.AddCoopPlayer",methodName="update",warmUp=true)
    public static class EquipmentLifetimeCoopBirth {
        @Patch.OnEnter public static void enter(@Patch.This zombie.util.AddCoopPlayer task,@Patch.Local("equipmentBirth") EquipmentBirth scope){scope=EquipmentLifetime.equipmentLifetimeCoopEnter(task);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Local("equipmentBirth") EquipmentBirth scope,@Patch.Thrown Throwable failure){EquipmentLifetime.equipmentLifetimeCoopExit(scope,failure);}
    }
    @Patch(className="zombie.network.packets.EquipPacket",methodName="parse",warmUp=false)
    public static class EquipmentLifetimeEquipParse {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) zombie.core.network.ByteBufferReader reader,@Patch.Argument(1) zombie.network.IConnection connection,@Patch.Local("equipmentParse") EquipmentParse scope){scope=EquipmentLifetime.equipmentLifetimeParseEnter(reader,connection);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Local("equipmentParse") EquipmentParse scope,@Patch.Thrown Throwable failure){EquipmentLifetime.equipmentLifetimeParseExit(scope,failure);}
    }
    @Patch(className="zombie.characters.IsoGameCharacter",methodName="setPrimaryHandItem",warmUp=false)
    public static class EquipmentLifetimePrimary {
        @Patch.OnEnter public static void enter(@Patch.This zombie.characters.IsoGameCharacter actor,@Patch.Argument(0) zombie.inventory.InventoryItem incoming,@Patch.Local("equipmentLife") EquipmentMutation scope){scope=EquipmentLifetime.equipmentLifetimeHands(actor,incoming,true);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Local("equipmentLife") EquipmentMutation scope,@Patch.Thrown Throwable failure){EquipmentLifetime.equipmentLifetimeExit(scope,failure);}
    }
    @Patch(className="zombie.characters.IsoGameCharacter",methodName="setSecondaryHandItem",warmUp=false)
    public static class EquipmentLifetimeSecondary {
        @Patch.OnEnter public static void enter(@Patch.This zombie.characters.IsoGameCharacter actor,@Patch.Argument(0) zombie.inventory.InventoryItem incoming,@Patch.Local("equipmentLife") EquipmentMutation scope){scope=EquipmentLifetime.equipmentLifetimeHands(actor,incoming,false);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Local("equipmentLife") EquipmentMutation scope,@Patch.Thrown Throwable failure){EquipmentLifetime.equipmentLifetimeExit(scope,failure);}
    }
    @Patch(className="zombie.characters.IsoGameCharacter",methodName="load",warmUp=false)
    public static class EquipmentLifetimeCharacterLoad {
        @Patch.OnEnter public static void enter(@Patch.This zombie.characters.IsoGameCharacter actor,@Patch.Local("equipmentLife") EquipmentMutation scope){scope=EquipmentLifetime.equipmentLifetimeLoad(actor,"character-load");}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Local("equipmentLife") EquipmentMutation scope,@Patch.Thrown Throwable failure){EquipmentLifetime.equipmentLifetimeExit(scope,failure);}
    }
    @Patch(className="zombie.characters.IsoPlayer",methodName="load",warmUp=false)
    public static class EquipmentLifetimePlayerLoad {
        @Patch.OnEnter public static void enter(@Patch.This IsoPlayer actor,@Patch.Local("equipmentLife") EquipmentMutation scope){scope=EquipmentLifetime.equipmentLifetimeLoad(actor,"player-load");}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Local("equipmentLife") EquipmentMutation scope,@Patch.Thrown Throwable failure){EquipmentLifetime.equipmentLifetimeExit(scope,failure);}
    }
    @Patch(className="zombie.characters.IsoPlayer",methodName="setOnlineID",warmUp=false)
    public static class EquipmentLifetimeOnlineID {
        @Patch.OnEnter public static void enter(@Patch.This IsoPlayer actor,@Patch.Argument(0) short incoming,@Patch.Local("equipmentLife") EquipmentMutation scope){scope=EquipmentLifetime.equipmentLifetimeOnlineID(actor,incoming);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Local("equipmentLife") EquipmentMutation scope,@Patch.Thrown Throwable failure){EquipmentLifetime.equipmentLifetimeExit(scope,failure);}
    }
    @Patch(className="zombie.inventory.InventoryItem",methodName="setID",warmUp=false)
    public static class EquipmentLifetimeItemID {
        @Patch.OnEnter public static void enter(@Patch.This zombie.inventory.InventoryItem item,@Patch.Argument(0) int incoming,@Patch.Local("equipmentItems") java.util.ArrayList<EquipmentMutation> scopes){scopes=EquipmentLifetime.equipmentLifetimeItem(item,item.getID()!=incoming,"item-id");}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Local("equipmentItems") java.util.ArrayList<EquipmentMutation> scopes,@Patch.Thrown Throwable failure){EquipmentLifetime.equipmentLifetimeItemExit(scopes,failure);}
    }
    @Patch(className="zombie.inventory.InventoryItem",methodName="setWorldItem",warmUp=false)
    public static class EquipmentLifetimeWorldItem {
        @Patch.OnEnter public static void enter(@Patch.This zombie.inventory.InventoryItem item,@Patch.Argument(0) zombie.iso.objects.IsoWorldInventoryObject incoming,@Patch.Local("equipmentItems") java.util.ArrayList<EquipmentMutation> scopes){scopes=EquipmentLifetime.equipmentLifetimeItem(item,item.getWorldItem()!=incoming,"world-item");}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Local("equipmentItems") java.util.ArrayList<EquipmentMutation> scopes,@Patch.Thrown Throwable failure){EquipmentLifetime.equipmentLifetimeItemExit(scopes,failure);}
    }
    @Patch(className="zombie.inventory.InventoryItem",methodName="load",warmUp=false)
    public static class EquipmentLifetimeItemLoad {
        @Patch.OnEnter public static void enter(@Patch.This zombie.inventory.InventoryItem item,@Patch.Local("equipmentItems") java.util.ArrayList<EquipmentMutation> scopes){scopes=EquipmentLifetime.equipmentLifetimeItem(item,true,"item-load");}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Local("equipmentItems") java.util.ArrayList<EquipmentMutation> scopes,@Patch.Thrown Throwable failure){EquipmentLifetime.equipmentLifetimeItemExit(scopes,failure);}
    }
}
