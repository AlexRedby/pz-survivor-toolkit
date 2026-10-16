package net.alexredby.animalreplayprobe;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.characters.IsoPlayer;
import zombie.inventory.types.AnimalInventoryItem;
import zombie.network.packets.character.AnimalPacket;
import zombie.vehicles.BaseVehicle;

public final class Main {
    @LuaMethod(name="animalTrailerReplayProbe", global=true)
    public static String replay(IsoPlayer owner, BaseVehicle vehicle) {
        if (!(owner.getPrimaryHandItem() instanceof AnimalInventoryItem item)) return "FAIL no animal in hands";
        var animal = item.getAnimal();
        int identity = animal.getAnimalID(), itemID = item.getID();
        short onlineID = animal.getOnlineID();
        int count = 0; float size = 0;
        for (var other : vehicle.getAnimals()) if (other != animal) { count++; size += other.getAnimalTrailerSize(); }
        var ai = animal.getNetworkCharacterAI();
        AnimalPacket packet = new AnimalPacket();
        ai.set(packet, null);
        packet.location = 2; packet.vehicleId.set(vehicle);
        boolean disabled = net.alexredby.pztoolkitjavapatches.Main.AnimalTrailerLocation.disabled;
        if (disabled) return "FAIL reconciliation already disabled";
        try {
            net.alexredby.pztoolkitjavapatches.Main.AnimalTrailerLocation.disabled = true;
            ai.parse(packet);
            if (!vehicle.getAnimals().contains(animal) || animal.getVehicle() != vehicle) return "FAIL stale snapshot did not reproduce";
            packet.location = 3;
            ai.parse(packet);
        } finally { net.alexredby.pztoolkitjavapatches.Main.AnimalTrailerLocation.disabled = disabled; }
        if (!vehicle.getAnimals().contains(animal) || animal.getVehicle() != vehicle) return "FAIL baseline did not retain stale membership";
        ai.parse(packet); ai.parse(packet);
        if (vehicle.getAnimals().contains(animal) || animal.getVehicle() != null) return "FAIL authoritative item snapshot retained trailer membership";
        if (vehicle.getAnimals().size() != count || Math.abs(vehicle.getCurrentTotalAnimalSize() - size) > 0.001f)
            return "FAIL unrelated animals or capacity changed";
        if (owner.getPrimaryHandItem() != item || owner.getSecondaryHandItem() != item || !owner.getInventory().contains(item)
            || item.getID() != itemID || item.getAnimal() != animal || animal.getAnimalID() != identity || animal.getOnlineID() != onlineID || animal.getItemID() != itemID)
            return "FAIL inventory or animal identity changed";
        return "PASS baseline ghost reproduced; woven stale trailer snapshot repaired by authoritative item snapshot; hands, identities and neighbors preserved";
    }
    public static void main(String[] args) { System.out.println("[ANIMAL_TRAILER] REPLAY_PROBE_LOADED"); }
}
