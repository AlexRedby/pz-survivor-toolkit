package net.alexredby.pztoolkitjavapatches;

import java.security.MessageDigest;
import java.util.HexFormat;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.NetworkZombieAI;
import zombie.core.BuildAction;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.packets.character.ZombiePacket;
import zombie.radio.devices.DeviceData;
import zombie.vehicles.VehicleInterpolation;

public final class Main {
    public static final boolean VIDEO_SUPPORTED = supports("org/lwjglx/opengl/Display.class",
        "15a0c0a3646d4340cd96c47d143a5605bfbae7543410ddaa018e83f45ae1a578");

    @Patch(className="org.lwjglx.opengl.Display", methodName="swapBuffers", warmUp=true)
    public static class VideoPresented {
        @Patch.OnExit
        public static void exit() {
            if (Main.VIDEO_SUPPORTED) VideoRecording.presented();
        }
    }

    // Fail closed after an engine update. Hash original class resources, not transformed bytecode.
    public static final boolean ZOMBIE_SUPPORTED = supports("zombie/characters/NetworkZombieAI.class",
        "87e4f6e43d16dec23f685b4ebad68eb12eaea15ed87dce3fc3c3394f96cd1e3d");
    public static final boolean VEHICLE_SUPPORTED = supports("zombie/vehicles/VehicleInterpolation.class",
        "e5096d41b4b94c3eb040c119c1ca35b014bbfe3c742401002b88103a650add56");
    public static final boolean MEDIA_SUPPORTED = supports("zombie/radio/devices/DeviceData.class",
        "492af532cddfe49908a5f479e2749b8dc08334a6b661ab81eb81892926cdb102");
    public static final boolean BUILD_SUPPORTED = supports("zombie/core/BuildAction.class",
        "320afae90b4723456f349787a09c179f53de2533a19393434d34fc569eb4f368")
        && supports("zombie/core/ActionManager.class",
            "3e85655f0d287837b17164d2ee4cecb7067ab419ffbe8ce1adb36bd7d54b202f")
        && supports("zombie/core/Action.class",
            "4a2fe6aaf0cf73235279946e930b40489ec44859aff64cc19d97976bcc75610d")
        && supports("zombie/network/packets/BuildActionPacket.class",
            "c09201418a8aa248ea349314fba21de85fb2d768e0df4afb4bc8d32bfbf524db")
        && supports("zombie/network/packets/GeneralActionPacket.class",
            "398a8729da87a4c222f17473cc46c9b5cb7fd9b3f74492d283765619c1d57c8a");

    public static boolean supports(String resource, String expected) {
        try (var stream = Main.class.getClassLoader().getResourceAsStream(resource)) {
            return stream != null && expected.equals(HexFormat.of().formatHex(
                MessageDigest.getInstance("SHA-256").digest(stream.readAllBytes())));
        } catch (Exception error) {
            System.err.println("[PZToolkitJavaPatches] Disabled: cannot check " + resource + ": " + error);
            return false;
        }
    }

    public static void main(String[] args) {
        System.out.println("[PZToolkitJavaPatches] Experimental B42.21 patch: zombie=" + ZOMBIE_SUPPORTED
            + ", vehicle=" + VEHICLE_SUPPORTED + ", media=" + MEDIA_SUPPORTED + ", build=" + BUILD_SUPPORTED
            + ", video=" + VIDEO_SUPPORTED);
    }

    @Patch(className="zombie.core.BuildAction", methodName="start", warmUp=true)
    public static class BuildStarted {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.This BuildAction action) {
            if (GameServer.server && Main.BUILD_SUPPORTED) BuildAcknowledgements.started(action);
        }
    }

    @Patch(className="zombie.core.BuildAction", methodName="stop", warmUp=true)
    public static class BuildStopped {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.This BuildAction action) {
            if (GameServer.server && Main.BUILD_SUPPORTED) BuildAcknowledgements.settled(action, "canceled");
        }
    }

    @Patch(className="zombie.core.BuildAction", methodName="perform", warmUp=true)
    public static class BuildCompleted {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.This BuildAction action, @Patch.Return boolean completed) {
            if (GameServer.server && Main.BUILD_SUPPORTED && completed) BuildAcknowledgements.settled(action, "completed");
        }
    }

    @Patch(className="zombie.radio.devices.DeviceData", methodName="StartPlayMedia", warmUp=true)
    public static class MediaRestart {
        @Patch.OnExit
        public static void exit(@Patch.This DeviceData data) {
            // A successful restart must cancel the old stop tail before it silently stops playback again.
            if (GameServer.server && Main.MEDIA_SUPPORTED && data.isPlayingMedia()
                && !Accessor.trySet(data, "isStoppingMedia", false)) {
                System.err.println("[PZToolkitJavaPatches] Cannot clear media stop state");
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
