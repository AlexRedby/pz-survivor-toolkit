package net.alexredby.animalsessionprobe;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.characters.animals.IsoAnimal;
import zombie.network.GameServer;
import zombie.popman.animal.AnimalSynchronizationManager;

/** Deletes only the exact fixture-owned animal, using native world and replication cleanup. */
public final class Main {
    @LuaMethod(name="animalFixtureDelete", global=true)
    public static String delete(IsoAnimal animal) {
        if (!GameServer.server || animal == null || animal.getVehicle() != null || animal.getHutch() != null)
            return "FAIL expected owned dropped server animal";
        short id = animal.getOnlineID();
        animal.remove();
        AnimalSynchronizationManager.getInstance().delete(id);
        if (animal.isExistInTheWorld() || animal.getSquare() != null || animal.getVehicle() != null)
            return "FAIL owned animal survived native removal";
        return "removed=" + id;
    }
    public static void main(String[] args) { System.out.println("[ANIMAL_SESSION_PROBE] exact ownership cleanup only"); }
}
