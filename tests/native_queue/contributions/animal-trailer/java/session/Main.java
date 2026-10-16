package net.alexredby.animalsessionprobe;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.characters.IsoPlayer;
import zombie.characters.animals.IsoAnimal;
import zombie.GameWindow;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.popman.animal.AnimalSynchronizationManager;

/** Reads native connection state and deletes only the exact fixture-owned animal. */
public final class Main {
    @LuaMethod(name="animalFixtureRestorePosition", global=true)
    public static String restorePosition(IsoPlayer owner, float x, float y, float z) {
        if (!GameServer.server || owner == null || owner.isDead() || owner.getVehicle() != null
                || GameServer.getConnectionFromPlayer(owner) == null || owner.getNetworkCharacterAI() == null
                || !Float.isFinite(x) || !Float.isFinite(y) || !Float.isFinite(z))
            return "FAIL expected connected server owner and finite origin";
        GameServer.sendTeleport(owner, x, y, z);
        return "issued";
    }
    @LuaMethod(name="animalFixtureDisconnected", global=true)
    public static boolean disconnected() {
        return GameWindow.serverDisconnected || !GameClient.client;
    }
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
