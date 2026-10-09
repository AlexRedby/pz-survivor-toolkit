package net.alexredby.pznetworkfix;

import java.security.MessageDigest;
import java.util.HexFormat;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.NetworkZombieAI;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.packets.character.ZombiePacket;
import zombie.radio.devices.DeviceData;
import zombie.vehicles.VehicleInterpolation;

public final class Main {
    // Fail closed after an engine update. Hash original class resources, not transformed bytecode.
    public static final boolean ZOMBIE_SUPPORTED = supports("zombie/characters/NetworkZombieAI.class",
        "87e4f6e43d16dec23f685b4ebad68eb12eaea15ed87dce3fc3c3394f96cd1e3d");
    public static final boolean VEHICLE_SUPPORTED = supports("zombie/vehicles/VehicleInterpolation.class",
        "e5096d41b4b94c3eb040c119c1ca35b014bbfe3c742401002b88103a650add56");
    public static final boolean MEDIA_SUPPORTED = supports("zombie/radio/devices/DeviceData.class",
        "492af532cddfe49908a5f479e2749b8dc08334a6b661ab81eb81892926cdb102");

    public static boolean supports(String resource, String expected) {
        try (var stream = Main.class.getClassLoader().getResourceAsStream(resource)) {
            return stream != null && expected.equals(HexFormat.of().formatHex(
                MessageDigest.getInstance("SHA-256").digest(stream.readAllBytes())));
        } catch (Exception error) {
            System.err.println("[PZNetworkFix] Disabled: cannot check " + resource + ": " + error);
            return false;
        }
    }

    public static void main(String[] args) {
        System.out.println("[PZNetworkFix] Experimental B42.21 patch: zombie=" + ZOMBIE_SUPPORTED
            + ", vehicle=" + VEHICLE_SUPPORTED + ", media=" + MEDIA_SUPPORTED);
    }

    @Patch(className="zombie.radio.devices.DeviceData", methodName="StartPlayMedia", warmUp=true)
    public static class MediaRestart {
        @Patch.OnExit
        public static void exit(@Patch.This DeviceData data) {
            // A successful restart must cancel the old stop tail before it silently stops playback again.
            if (GameServer.server && Main.MEDIA_SUPPORTED && data.isPlayingMedia()
                && !Accessor.trySet(data, "isStoppingMedia", false)) {
                System.err.println("[PZNetworkFix] Cannot clear media stop state");
            }
        }
    }

    @Patch(className="zombie.characters.NetworkZombieAI", methodName="parse", warmUp=true)
    public static class ZombieSpeedDecode {
        @Patch.OnExit
        public static void exit(@Patch.This NetworkZombieAI ai, @Patch.Argument(0) ZombiePacket packet) {
            if (GameClient.client && Main.ZOMBIE_SUPPORTED && ai.zombie.isRemoteZombie()) {
                // Sender and initial-spawn decoder use thousandths; update decoder omitted the scale.
                ai.zombie.setSpeedMod(packet.speedMod / 1000.0f);
            }
        }
    }

    @Patch(className="zombie.vehicles.VehicleInterpolation", methodName="interpolationDataCurrentAdd", warmUp=true)
    public static class VehicleRecovery {
        @Patch.OnEnter
        public static void enter(@Patch.This VehicleInterpolation interpolation) {
            // Called only when the buffer is empty. The new seed contains the current displayed pose.
            if (GameClient.client && Main.VEHICLE_SUPPORTED) interpolation.clearLast();
        }
    }
}
