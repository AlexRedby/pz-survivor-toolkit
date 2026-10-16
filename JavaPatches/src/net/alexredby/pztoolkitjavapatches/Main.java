package net.alexredby.pztoolkitjavapatches;

import java.security.MessageDigest;
import java.util.HashMap;
import java.util.HexFormat;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.NetworkZombieAI;
import zombie.characters.NetworkPlayerAI;
import zombie.characters.animals.IsoAnimal;
import zombie.core.BuildAction;
import zombie.core.network.ByteBufferReader;
import zombie.core.raknet.UdpConnection;
import zombie.iso.objects.IsoHutch;
import zombie.network.IConnection;
import zombie.network.fields.character.PlayerID;
import zombie.network.packets.EquipPacket;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.packets.character.ZombiePacket;
import zombie.network.packets.character.AnimalPacket;
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
    public static final boolean ANIMAL_SUPPORTED = supports("zombie/characters/NetworkPlayerAI.class",
        "46df5ede124384e10a848fe9eb6f6ba06cccbb3cc74f51e5e9b0306cd80a628a")
        && supports("zombie/vehicles/BaseVehicle.class",
            "e7ade19e1e6f66450bef2bd37e52b2afccc7377c4e4571d0fa39435ecdb55661")
        && supports("zombie/network/packets/character/AnimalPacket.class",
            "db6954555bb7b270589d406050eecb4dd79f789e8d5627df7fc43c1e8150f169");
    public static final boolean EQUIPMENT_SUPPORTED = supports("zombie/network/packets/EquipPacket.class",
        "35e25895c725c3154d0f1e4b3217c7e19795ed1296441dbcea9283026ec5da89")
        && supports("zombie/network/ZomboidNetData.class",
            "9b81b4f1e3ce8e338f2b8bb838c797353d0b2841396d01325c968051e168419e");
    public static final boolean HUTCH_SUPPORTED = supports("zombie/iso/objects/IsoHutch.class",
        "d9c1944025f6902416c83993199a89b2509bb2af3d09a44ced9c61b28c8589ae");
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
            + ", video=" + VIDEO_SUPPORTED + ", animal=" + ANIMAL_SUPPORTED + ", equipment=" + EQUIPMENT_SUPPORTED
            + ", hutch=" + HUTCH_SUPPORTED);
    }

    @Patch(className="zombie.iso.objects.IsoHutch", methodName="removeFromWorld", warmUp=true, strictMatch=true)
    public static class HutchUnloading {
        @Patch.OnEnter
        public static void enter(@Patch.This IsoHutch hutch,
                                 @Patch.Local("toolkitHutchAnimals") HashMap<Integer, IsoAnimal> original) {
            original = HutchCleanup.begin(hutch, Main.HUTCH_SUPPORTED);
        }

        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.This IsoHutch hutch,
                                @Patch.Local("toolkitHutchAnimals") HashMap<Integer, IsoAnimal> original) {
            // Restore even when native cleanup throws; never suppress unrelated errors.
            if (original != null) hutch.animalInside = original;
        }
    }

    @Patch(className="zombie.network.packets.EquipPacket", methodName="parse", warmUp=true, strictMatch=true)
    public static class EquipmentParsed {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.This EquipPacket packet, @Patch.Argument(0) ByteBufferReader reader,
                                @Patch.Argument(1) IConnection connection) {
            EquipmentEcho.incomplete = null;
            if (!GameClient.client || !Main.EQUIPMENT_SUPPORTED || !reader.bb.hasRemaining()) return;
            var player = Accessor.tryGet(packet, "player", (PlayerID)null);
            if (player != null && player.getPlayer() != null && player.getPlayer().isLocalPlayer())
                EquipmentEcho.incomplete = packet;
        }
    }

    @Patch(className="zombie.network.packets.EquipPacket", methodName="processClient", warmUp=true, strictMatch=true)
    public static class EquipmentEcho {
        public static EquipPacket incomplete;

        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This EquipPacket packet, @Patch.Argument(0) UdpConnection connection) {
            if (!GameClient.client || !Main.EQUIPMENT_SUPPORTED) return false;
            // An early Equip returns before the remaining hand is parsed; acknowledging it would clear the server's new animal.
            boolean skip = incomplete == packet;
            incomplete = null;
            return skip;
        }
    }

    @Patch(className="zombie.characters.NetworkPlayerAI", methodName="parse", warmUp=true, strictMatch=true)
    public static class AnimalTrailerLocation {
        public static boolean disabled;

        @Patch.OnEnter
        public static void enter(@Patch.This NetworkPlayerAI ai, @Patch.Argument(0) AnimalPacket packet) {
            if (disabled || !GameClient.client || !Main.ANIMAL_SUPPORTED || packet == null
                || (packet.location != 0 && packet.location != 1 && packet.location != 3)
                || !(ai.getCharacter() instanceof IsoAnimal animal)) return;
            try {
                var vehicle = animal.getVehicle();
                if (vehicle == null) return;
                // A late trailer snapshot can re-add a grabbed animal; the next real location must detach it.
                while (vehicle.getAnimals().remove(animal)) { }
                animal.setVehicle(null);
                float size = 0;
                for (var remaining : vehicle.getAnimals()) size += remaining.getAnimalTrailerSize();
                vehicle.setCurrentTotalAnimalSize(size);
            } catch (RuntimeException error) {
                disabled = true;
                System.err.println("[PZToolkitJavaPatches] Animal trailer reconciliation disabled: " + error);
            }
        }
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
