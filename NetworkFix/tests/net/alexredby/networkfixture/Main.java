package net.alexredby.networkfixture;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.characters.IsoZombie;
import zombie.iso.IsoWorld;
import zombie.network.GameClient;
import zombie.network.NetworkVariables;
import zombie.network.packets.character.ZombiePacket;

public final class Main {
    @LuaMethod(name="networkFixProbe", global=true)
    public static String probe() {
        boolean patched = Boolean.getBoolean("pz.networkfix.expected");
        IsoZombie z = new IsoZombie(IsoWorld.instance.currentCell);
        ZombiePacket packet = new ZombiePacket();
        packet.target = -1;
        packet.walkType = NetworkVariables.WalkType.values()[0];
        packet.realState = NetworkVariables.ZombieState.values()[0];
        packet.realX = z.getX(); packet.realY = z.getY(); packet.realZ = (byte)z.getZ();
        for (short encoded : new short[]{0, 550, 850, 1200}) {
            z.setOwner(null); z.setSpeedMod(0.25f); packet.speedMod = encoded;
            z.getNetworkCharacterAI().parse(packet);
            float expected = patched ? encoded / 1000.0f : encoded;
            if (z.getSpeedMod() != expected) throw new AssertionError("remote decode " + z.getSpeedMod() + " expected " + expected);
            z.setOwner(GameClient.connection); z.setSpeedMod(0.25f);
            z.getNetworkCharacterAI().parse(packet);
            if (z.getSpeedMod() != 0.25f) throw new AssertionError("owned zombie changed");
            if (packet.speedMod != encoded) throw new AssertionError("wire packet changed");
        }
        return "packet850=" + (patched ? "0.85" : "850") + ", four values checked, owned unchanged, packet unchanged";
    }
    @LuaMethod(name="networkFixObserve", global=true)
    public static String observe() {
        var list = IsoWorld.instance.currentCell.getZombieList();
        int remote=0, owned=0;
        float max=0;
        for (int i=0; i<list.size(); i++) {
            IsoZombie z = list.get(i);
            if (z.isRemoteZombie()) remote++; else owned++;
            max = Math.max(max, z.getSpeedMod());
        }
        return "remote=" + remote + ",owned=" + owned + ",maxSpeed=" + max;
    }
}
