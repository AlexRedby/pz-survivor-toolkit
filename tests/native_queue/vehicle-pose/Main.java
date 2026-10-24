package net.alexredby.vehicleposefixture;

import java.nio.file.Path;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;

/** Read-only measurements, called by Lua on the game thread in an owned test cache. */
public final class Main {
    @LuaMethod(name="vehiclePoseCheck", global=true)
    public static String check(IsoPlayer player) {
        String cache = System.getenv("PZ_POSE_TEST_CACHE");
        if (cache == null || !Path.of(cache).normalize().equals(
                Path.of(ZomboidFileSystem.instance.getCacheDir()).toAbsolutePath().normalize()))
            throw new IllegalStateException("Disposable pose cache required");
        if (player == null || player.getVehicle() == null || !player.hasAnimationPlayer())
            throw new IllegalStateException("No native seated animation player");
        var animation = player.getAnimationPlayer();
        var tracks = animation.getMultiTrack();
        int seated = 0;
        float weight = 0;
        for (int i = 0; i < tracks.getTrackCount(); i++) {
            var track = tracks.getTrackAt(i);
            if (track.getBlendWeight() < .01f) continue;
            String name = track.getName();
            if (!"Bob_IdleDriving".equals(name))
                throw new IllegalStateException("Standing/unexpected track: " + name + " weight=" + track.getBlendWeight());
            if (!track.isLooping()) {
                if (Math.abs(track.getDuration() / track.getSpeedDelta() - .625f) > .00001f)
                    throw new IllegalStateException("Changed native transition duration");
                seated++; weight += track.getBlendWeight();
            }
        }
        if (seated != 1 || weight < .99f)
            throw new IllegalStateException("No fully weighted one-shot seated transition: " + seated + "/" + weight);
        int head = animation.getSkinningBoneIndex("Bip01_Head", -1);
        if (head < 0 || head >= animation.getModelTransformsCount())
            throw new IllegalStateException("No native head pose");
        return "seated=" + seated + " weight=" + weight + " headY=" + animation.getModelTransformAt(head).m13;
    }
}
