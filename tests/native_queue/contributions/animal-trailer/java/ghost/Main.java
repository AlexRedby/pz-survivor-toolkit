package net.alexredby.animalreplayprobe;

import java.util.ArrayList;
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
        if (vehicle.getAnimals().contains(animal) || animal.getVehicle() != null)
            return "FAIL held animal already has stale trailer membership before replay";
        var neighbors = new ArrayList<>(vehicle.getAnimals());
        float size = 0;
        for (var other : neighbors) size += other.getAnimalTrailerSize();
        if (Math.abs(vehicle.getCurrentTotalAnimalSize() - size) > 0.001f)
            return "FAIL initial trailer capacity differs from its animals";
        var ai = animal.getNetworkCharacterAI();
        AnimalPacket packet = new AnimalPacket();
        ai.set(packet, null);
        packet.location = 2; packet.vehicleId.set(vehicle);
        ai.parse(packet);
        if (!vehicle.getAnimals().contains(animal) || animal.getVehicle() != vehicle
            || vehicle.getAnimals().size() != neighbors.size() + 1
            || Math.abs(vehicle.getCurrentTotalAnimalSize() - size - animal.getAnimalTrailerSize()) > 0.001f)
            return "FAIL stale snapshot did not reproduce exact membership and capacity";
        packet.location = 3;
        ai.parse(packet); ai.parse(packet);
        if (vehicle.getAnimals().contains(animal) || animal.getVehicle() != null) return "FAIL authoritative item snapshot retained trailer membership";
        if (!vehicle.getAnimals().equals(neighbors) || Math.abs(vehicle.getCurrentTotalAnimalSize() - size) > 0.001f)
            return "FAIL unrelated animals or capacity changed";
        if (owner.getPrimaryHandItem() != item || owner.getSecondaryHandItem() != item || !owner.getInventory().contains(item)
            || item.getID() != itemID || item.getAnimal() != animal || animal.getAnimalID() != identity || animal.getOnlineID() != onlineID || animal.getItemID() != itemID)
            return "FAIL inventory or animal identity changed";
        return "PASS stale trailer snapshot reproduced; woven authoritative item snapshot repaired; hands, identities, neighbors and capacity preserved";
    }
    public static void main(String[] args) { System.out.println("[ANIMAL_TRAILER] REPLAY_PROBE_LOADED"); }
}
