package net.alexredby.pztoolkitjavapatches;

import static net.alexredby.pztoolkitjavapatches.BytecodeSupport.supports;

import java.util.HashMap;
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
    public static final boolean VEHICLE_OWNERSHIP_SUPPORTED = supports("zombie/vehicles/BaseVehicle.class",
        "e7ade19e1e6f66450bef2bd37e52b2afccc7377c4e4571d0fa39435ecdb55661");
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
    public static final boolean MEDICAL_BODY_DAMAGE_SUPPORTED = supports("zombie/network/packets/BodyDamageUpdatePacket.class",
            "2e37ca1add6b8696464285bd498e7c97cd9712c9094c51d1d57daac688145c8c")
        && supports("zombie/network/fields/character/PlayerID.class",
            "d40d1b745a70ad3bf562c15765b9f46a117ecb48aeeabf05597ce646a73e0b56")
        && supports("zombie/network/packets/BodyDamageUpdatePacket$Type.class",
            "e7694d5cfa682aa1fb60cdc85fdbb231bd87f758ce82ef0dc3dd0ccdead52c6c");
    public static final boolean MEDICAL_VISUALS_SUPPORTED = supports("zombie/characters/IsoGameCharacter$Bandages.class",
            "bb87836b717355811e6f699377896918b9d4f4d050a5ad7bc1f1a35a70ebdedd")
        && supports("zombie/characters/IsoGameCharacter.class",
            "29040e19c3e420499f73bc0ea0d5b86d7f7d38655acdc13d0107df736eb54c0b")
        && supports("zombie/characters/WornItems/WornItems.class",
            "3a01a9b5b7e13d0902fcac9342ac0b42e5c2e87284d88ce9a6a01f45294409c1")
        && supports("zombie/network/packets/SyncClothingPacket.class",
            "09e83606c9de4555802b2171e26df4739a78c787afeb8b2907d46c19be311dff");
    public static final boolean MEDICAL_TIMED_ACTION_SUPPORTED = supports("zombie/network/PZNetKahluaTableImpl.class",
            "201f0e59502fc5a106f8c9021e0b0d13a30dcb8d0beb9e8934cec390231ddba6")
        && supports("zombie/core/NetTimedAction.class",
            "d4a3046eeaec409977a756c6ea80b0676229274684012ad51210559ebfcb1090")
        && supports("zombie/network/packets/NetTimedActionPacket.class",
            "ce367190ce6158eb88809f3215ebc471e6161896d9d526eb9ef0e73d58de847b")
        && supports("zombie/core/Action.class",
            "4a2fe6aaf0cf73235279946e930b40489ec44859aff64cc19d97976bcc75610d")
        && supports("zombie/network/fields/character/PlayerID.class",
            "d40d1b745a70ad3bf562c15765b9f46a117ecb48aeeabf05597ce646a73e0b56")
        && supports("zombie/network/ZomboidNetData.class",
            "9b81b4f1e3ce8e338f2b8bb838c797353d0b2841396d01325c968051e168419e")
        && supports("zombie/network/fields/IDShort.class",
            "852188ce7dceb2a40c32ae233d6fcdbdec3cc74dd45d9d5151334308f514cdcd")
        && supports("zombie/core/network/ByteBufferReader.class",
            "1c2731f2a49b57d2ad895069d499705f8492e3cb6ac275a8f1163b4940e370ff");
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

    public static final boolean CART_SUPPORTED = supports("zombie/characters/component/CharacterInputComponent.class",
            "e3ff79ae666e7809f753cbe7aac4a3e4729f520d4f795009643efc222b22088d")
        && supports("zombie/characters/IsoPlayer.class",
            "3f1c4634d3a8e7e36baf4b33f76cf7ef79d88c3351bd0eb2a6a6bb34c2d9858f")
        && supports("zombie/characters/IsoGameCharacter.class",
            "29040e19c3e420499f73bc0ea0d5b86d7f7d38655acdc13d0107df736eb54c0b")
        && supports("zombie/pathfind/PathFindBehavior2.class","06b4af799cd9e335aee738bcad498215c5068038d8dfc524bb7b6337e923a127")
        && supports("zombie/iso/IsoMovingObject.class",
            "7e6e84fe9d3cb264e8d8e682d91e0abe919d481b7349d17b997e8a78f2293a5f")
        && supports("zombie/core/skinnedmodel/animation/AnimationPlayer.class",
            "06fc56e5aa626c808e8c6c0870dc87c10a957d86c7c22782be1d437d52b8bc28")
        && supports("zombie/core/skinnedmodel/model/ModelSlotRenderData.class",
            "83fab9cb79f1c2ba270d8b49e8cf2c166ca36e08986c52517ba73d15cd34f76d")
        && supports("zombie/core/skinnedmodel/model/SkinningData.class",
            "1ee3fea347d68d2197f1015201841d5981e8806792168364a837b8b2391dfe7b")
        && supports("zombie/core/skinnedmodel/animation/AnimationClip.class",
            "374d961e0aa023873b726e467101c4be74d65caaafbb9f3e7f8cea148b25c859")
        && supports("zombie/core/skinnedmodel/advancedanimation/AnimNode.class",
            "1b7cdc17098c2db683ab31b77a937b38b04ce275cb4c9582890afb97c5ce4dbe")
        && supports("zombie/core/skinnedmodel/advancedanimation/Anim2DBlendPicker.class",
            "445b3cab515d642eb67ed10b6ff84cc6c5a1ef4cd249d32ce1de6270ffb39446")
        && supports("zombie/core/skinnedmodel/model/ModelInstanceRenderData.class",
            "67702b5ea23d20fb9af7bf44534dd4c48d607be5adf7c14ed3a5628b27f75a5f")
        && supports("zombie/core/skinnedmodel/advancedanimation/AnimatedModel$AnimatedModelInstanceRenderData.class",
            "c96e48b6d138db930abe557459b2ff81e025a47cba6c3b199700473362e2f04d");

    public static final boolean CART_SYNC_SUPPORTED = CART_SUPPORTED
        && supports("zombie/network/packets/character/PlayerPacket.class","5284e8225bf513241787276471f20b526b8373a5f22c714f1370b6f013cfe5de")
        && supports("zombie/network/packets/VariableSyncPacket.class","4fc2d32a491eb3f9e96aa0069dcd0f322e5d29e04e75c837cd4ec59cda42ef09")
        && supports("zombie/characters/NetworkPlayerAI.class","46df5ede124384e10a848fe9eb6f6ba06cccbb3cc74f51e5e9b0306cd80a628a")
        && supports("zombie/characters/NetworkCharacterAI.class","7ec30ba9fc20cd90ab14c36907c89ccba11faf29c506739e0998c167c598c4c8");

    public static final boolean CART_OBSERVER_SUPPORTED = CART_SYNC_SUPPORTED
        && supports("zombie/core/skinnedmodel/ModelCameraRenderData.class",
            "62fe74b8116809d43c5d798c8d638c632ef6dca22fb37bdbde6dabd8a625f897")
        && supports("zombie/core/textures/TextureDraw.class",
            "d602006055d324763e2278416dfef6ca3787b91c070d2ef4c420a950f6d81fb0")
        && supports("zombie/core/opengl/CharacterModelCamera.class",
            "2aecdf733008e6558db9a98ea799dcd76e3ee2cad9371a6c790aa780c2877d9f")
        && supports("zombie/iso/sprite/IsoSprite.class",
            "68c01e6b1c914f662621743e09c8dd8a62c0258392ce1a75654a713e1034067f");

    public static final boolean CART_WHEEL_SUPPORTED = CART_SUPPORTED
        && supports("zombie/core/skinnedmodel/model/Model.class",
            "3dd5e7b618cecf3c27e216a386e07937b1be694a7fc083b1bc2f7c993cbee3d9")
        && supports("zombie/core/skinnedmodel/model/VertexBufferObject.class",
            "9548415619074b6ebba619c2b5ce546b3f0e0812a5e3b6155c5a0892511b53a1")
        && supports("zombie/core/skinnedmodel/model/ModelMesh.class",
            "b12e7b5091f84ef60e72dd358e85d6611063ca5885d3237feda51dfb604f1f20")
        && supports("zombie/core/skinnedmodel/shader/Shader.class",
            "e9377a60cfe66b4907f57ab6a7a6d6275c991035e7326a1c4663520c09a04014");

    public static final boolean CART_TRANSITION_SUPPORTED = CART_SUPPORTED
        && supports("zombie/core/skinnedmodel/ModelManager.class", "9bd955ded08c284dd1e1a5f39c84dd8576e7a46186b3c6fdf69ef4b12d8709e5")
        && supports("zombie/iso/IsoGridSquare.class", "e8192f87d88da607abe0293228c84efbd822ed4ac0a331102c030bc3eeaba467")
        && supports("zombie/iso/objects/IsoWorldInventoryObject.class", "7be6f2d54525fa587908ce8efa7da5d26cfd3d19bd1cc02911ee12f7649857b3")
        && supports("zombie/iso/fboRenderChunk/FBORenderObjectOutline.class", "175e9ae7b5307a2ddaa02adb006c18e30823dbae626348c8e73d6613173d8471")
        && supports("zombie/core/skinnedmodel/model/ItemModelRenderer.class", "7bca60683441a873571bb4a8e3030de21852916432040a2dcdacc297757fb008")
        && supports("zombie/core/skinnedmodel/model/WorldItemAtlas$ItemParams.class", "c68663042d7995e201c3fb13c2bf429418fe848aeae6ffcc987d5fc3980a8485")
        && supports("zombie/core/skinnedmodel/model/WorldItemModelDrawer.class", "f9a83f5dbb3a5f897a502e945fb53150aa4cc4fb98c7996f5eb4bd0475d965d2");

    public static final boolean COMPLETION_SUPPORTED = supports("zombie/characters/CharacterTimedActions/LuaTimedActionNew.class",
        "f10236f1e8be9d0822dc144ebe61c42fa1d0e8ded3279c7aa6dd0ffb7291feb0")
        && supports("zombie/characters/CharacterTimedActions/BaseAction.class", "ce23d4ebefaf3f35b15d24e5139a1d5a9e3bdc97d176d20307dafdaf8c3b3392")
        && supports("zombie/characters/IsoGameCharacter.class", "29040e19c3e420499f73bc0ea0d5b86d7f7d38655acdc13d0107df736eb54c0b")
        && supports("se/krka/kahlua/integration/LuaCaller.class", "0443930027e8f312ae9cb192c628f4b6c10743204597c508f8693cfd7bd79d0b");

    @Patch(className="zombie.core.textures.VideoTexture", methodName="getOrCreate", strictMatch=true)
    public static class TVVideoPath {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(value=0, readOnly=false) String filename,
                @Patch.Argument(1) int width, @Patch.Argument(2) int height, @Patch.Argument(3) boolean async) {
            filename = TVVideoPaths.redirect(filename, TVVideoPaths.SUPPORTED);
        }
    }

    public static void main(String[] args) throws ClassNotFoundException {
        // Prepare targets before ZombieBuddy installs advice; order is significant for cold startup.
        TilePropertyNames.prepare();
        FluidContainerNames.prepare();
        PianoIcon.prepare();
        BasementRoomLookup.prepare();
        BasementHallKey.prepare();
        MannequinZoneData.prepare();
        boolean fences = FenceValidation.install(FenceValidation.SUPPORTED);
        // Define before patch registration: recursive loads during another transform bypass instrumentation.
        if(CART_TRANSITION_SUPPORTED)
            Class.forName("zombie.core.skinnedmodel.ModelManager",false,Main.class.getClassLoader());
        System.out.println("[PZToolkitJavaPatches] Experimental B42.21 patch: zombie=" + ZOMBIE_SUPPORTED
            + ", vehicle=" + VEHICLE_SUPPORTED + ", vehicleOwnership=" + VEHICLE_OWNERSHIP_SUPPORTED + ", media=" + MEDIA_SUPPORTED + ", build=" + BUILD_SUPPORTED
            + ", video=" + VIDEO_SUPPORTED + ", animal=" + ANIMAL_SUPPORTED + ", equipment=" + EQUIPMENT_SUPPORTED
            + ", cart=" + CART_SUPPORTED + ", cartSync=" + CART_SYNC_SUPPORTED + ", medicalTimedAction=" + MEDICAL_TIMED_ACTION_SUPPORTED + ", medicalBodyDamage=" + MEDICAL_BODY_DAMAGE_SUPPORTED + ", medicalVisuals=" + MEDICAL_VISUALS_SUPPORTED + ", hutch=" + HUTCH_SUPPORTED + ", properties=" + TilePropertyNames.SUPPORTED + ", fluids=" + FluidContainerNames.SUPPORTED
            + ", fences=" + fences + ", piano=" + PianoIcon.SUPPORTED + ", basementRooms=" + BasementRoomLookup.SUPPORTED
            + ", basementHall=" + BasementHallKey.SUPPORTED + ", mannequin=" + MannequinZoneData.SUPPORTED
            + ", itemTransactions=" + QueueManagers.ITEM_SUPPORTED + ", actionManager=" + QueueManagers.ACTION_SUPPORTED
            + ", actionCompletion=" + COMPLETION_SUPPORTED + ", actionAcknowledgements=" + ActionAcknowledgements.SUPPORTED
            + ", craftBench=" + CraftBenchReferences.SUPPORTED);
    }

    @Patch(className="zombie.characters.CharacterTimedActions.LuaTimedActionNew", methodName="perform", warmUp=true, strictMatch=true)
    public static class ActionPerformed {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.characters.CharacterTimedActions.LuaTimedActionNew action,
                @Patch.Local("toolkitCompletion") ActionCompletion.Scope scope) {
            scope = ActionCompletion.begin(action, "perform", Main.COMPLETION_SUPPORTED);
            if(scope==null && Main.COMPLETION_SUPPORTED && Main.CART_TRANSITION_SUPPORTED
                && CartTransition.observePickupPerform(action)) scope=ActionCompletion.observeOnly(action,"perform");
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.This zombie.characters.CharacterTimedActions.LuaTimedActionNew action,
                @Patch.Local("toolkitCompletion") ActionCompletion.Scope scope, @Patch.Thrown Throwable failure) {
            ActionCompletion.end(scope, failure);
            if(Main.CART_TRANSITION_SUPPORTED && Main.COMPLETION_SUPPORTED)
                CartTransition.pickupPerformed(action,scope,failure);
        }
    }

    @Patch(className="zombie.characters.CharacterTimedActions.LuaTimedActionNew", methodName="complete", warmUp=true, strictMatch=true)
    public static class ActionCompleted {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.characters.CharacterTimedActions.LuaTimedActionNew action,
                @Patch.Local("toolkitCompletion") ActionCompletion.Scope scope) {
            scope = ActionCompletion.begin(action, "complete", Main.COMPLETION_SUPPORTED);
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Local("toolkitCompletion") ActionCompletion.Scope scope, @Patch.Thrown Throwable failure) {
            ActionCompletion.end(scope, failure);
        }
    }

    @Patch(className="se.krka.kahlua.integration.LuaCaller", methodName="pcall", warmUp=true, strictMatch=true)
    public static class ActionCallbackResult {
        @Patch.OnExit
        public static void exit(@Patch.Argument(1) Object callback, @Patch.Argument(2) Object action, @Patch.Return Object[] result) {
            ActionCompletion.observe(callback, action, result);
        }
    }

    @Patch(className="zombie.characters.IsoGameCharacter$Bandages", methodName="removeBandageModel", warmUp=true, strictMatch=true)
    public static class NativeMedicalVisualRemoval {
        @Patch.OnEnter
        public static void enter(@Patch.This Object models, @Patch.Argument(0) zombie.characters.IsoGameCharacter player,
                                 @Patch.Argument(1) String type,
                                 @Patch.Local("toolkitRemovedVisual") zombie.inventory.InventoryItem removed) {
            removed = MedicalVisuals.before(models, player, type, Main.MEDICAL_VISUALS_SUPPORTED);
        }
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) zombie.characters.IsoGameCharacter player, @Patch.Argument(1) String type,
                                @Patch.Local("toolkitRemovedVisual") zombie.inventory.InventoryItem removed) {
            MedicalVisuals.after(player, removed);
        }
    }

    @Patch(className="zombie.network.packets.BodyDamageUpdatePacket", methodName="processClient", warmUp=true, strictMatch=true)
    public static class NativeMedicalBodyDamage {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This zombie.network.packets.BodyDamageUpdatePacket packet,
                                    @Patch.Argument(0) zombie.core.raknet.UdpConnection connection) {
            return MedicalBodyDamage.skip(packet, Main.MEDICAL_BODY_DAMAGE_SUPPORTED);
        }
    }

    @Patch(className="zombie.core.NetTimedAction", methodName="parse", warmUp=true, strictMatch=true)
    public static class NativeMedicalTimedAction {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.core.NetTimedAction packet, @Patch.Argument(0) ByteBufferReader reader,
                                 @Patch.Argument(1) IConnection connection,
                                 @Patch.Local("medicalScope") MedicalTimedActions.Scope scope) {
            scope = MedicalTimedActions.begin(packet, reader, Main.MEDICAL_TIMED_ACTION_SUPPORTED);
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Local("medicalScope") MedicalTimedActions.Scope scope,
                                @Patch.Thrown(readOnly=false) Throwable failure) {
            if (MedicalTimedActions.end(scope, failure)) failure = null;
        }
    }
    @Patch(className="zombie.network.PZNetKahluaTableImpl", methodName="load", warmUp=true, strictMatch=true)
    public static class NativeMedicalArguments {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.network.PZNetKahluaTableImpl table, @Patch.Argument(0) ByteBufferReader reader,
                                 @Patch.Argument(1) IConnection connection,
                                 @Patch.Local("medicalArguments") MedicalTimedActions.Arguments arguments) {
            arguments = MedicalTimedActions.beginArguments(table, reader);
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Local("medicalArguments") MedicalTimedActions.Arguments arguments) {
            MedicalTimedActions.endArguments(arguments);
        }
    }
    @Patch(className="zombie.network.PZNetKahluaTableImpl", methodName="load", warmUp=true, strictMatch=true)
    public static class NativeMedicalBodyPart {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.network.PZNetKahluaTableImpl table, @Patch.Argument(0) ByteBufferReader reader,
                                 @Patch.Argument(1) IConnection connection, @Patch.Argument(2) byte type) {
            MedicalTimedActions.beforeValue(table, reader, connection, type);
        }
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
            if (!GameClient.client || !Main.EQUIPMENT_SUPPORTED) return;
            var player = Accessor.tryGet(packet, "player", (PlayerID)null);
            if (!reader.bb.hasRemaining()) {
                if(Main.CART_TRANSITION_SUPPORTED && player!=null)
                    CartTransition.pickupEquipped(player.getPlayer(),connection);
                return;
            }
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

    @Patch(className="zombie.pathfind.PathFindBehavior2", methodName="update", warmUp=true)
    public static class CartPathResult {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.pathfind.PathFindBehavior2 path) {
            if(Main.CART_SUPPORTED)
                CartSteeringHooks.beginPath(Accessor.tryGet(path,"chr",(zombie.characters.IsoGameCharacter)null));
        }
        @Patch.OnExit
        public static void exit(@Patch.This zombie.pathfind.PathFindBehavior2 path,
                @Patch.Return(readOnly=false) zombie.pathfind.PathFindBehavior2.BehaviorResult result) {
            if(Main.CART_SUPPORTED)
                result=CartSteeringHooks.pathResult(Accessor.tryGet(path,"chr",(zombie.characters.IsoGameCharacter)null),result);
            if(Main.CART_TRANSITION_SUPPORTED && Main.COMPLETION_SUPPORTED)
                result=CartPickupApproach.result(Accessor.tryGet(path,"chr",(zombie.characters.IsoGameCharacter)null),path,result);
        }
    }

    @Patch(className="zombie.characters.IsoGameCharacter", methodName="isDeferredMovementEnabled", warmUp=true)
    public static class WoodenPickupRootMovement {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.characters.IsoGameCharacter actor,@Patch.Return(readOnly=false) boolean enabled) {
            if(enabled && Main.CART_TRANSITION_SUPPORTED && Main.COMPLETION_SUPPORTED && CartPickupApproach.suppressDeferred(actor))enabled=false;
        }
    }

    @Patch(className="zombie.characters.IsoPlayer", methodName="getInputMoveVector", warmUp=true)
    public static class CartKeyboardMovement {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.characters.IsoPlayer player,
            @Patch.Return zombie.iso.Vector2 movement) {
            if(Main.CART_SUPPORTED) CartSteeringHooks.keyboardMovement(player,movement);
        }
    }

    @Patch(className="zombie.network.packets.character.PlayerPacket", methodName="set", warmUp=true, strictMatch=true)
    public static class CartNetworkHeading {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.network.packets.character.PlayerPacket packet,
            @Patch.Argument(0) zombie.characters.IsoPlayer player) {
            if(!Main.CART_SYNC_SUPPORTED) return;
            float heading=CartSteeringHooks.networkHeading(player);
            if(Float.isFinite(heading)) packet.prediction.direction=heading;
        }
    }

    @Patch(className="zombie.characters.IsoPlayer", methodName="UpdateInputState", warmUp=true)
    public static class CartInput {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.characters.IsoPlayer player,
            @Patch.Argument(0) zombie.characters.IsoPlayer.InputState input) {
            if(Main.CART_SUPPORTED) CartSteeringHooks.input(player,input);
        }
    }

    @Patch(className="zombie.characters.IsoPlayer", methodName="moveUnmodded", warmUp=true)
    public static class CartMovement {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.characters.IsoPlayer player,
            @Patch.Argument(value=0, readOnly=false) float x, @Patch.Argument(value=1, readOnly=false) float y) {
            if(Main.CART_SUPPORTED) {
                var step=CartSteeringHooks.movement(player,x,y);
                var impact=CartImpactMotion.movement(player,step.x,step.y);
                x=impact.x; y=impact.y;
            }
        }
    }

    @Patch(className="zombie.characters.IsoGameCharacter", methodName="postUpdateAnimating", warmUp=true)
    public static class CartHeading {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.characters.IsoGameCharacter character) {
            if(Main.CART_TRANSITION_SUPPORTED) CartTransition.prunePickupHandoffs();
            if(Main.CART_SUPPORTED) CartSteeringHooks.heading(character);
        }
        @Patch.OnExit
        public static void exit(@Patch.This zombie.characters.IsoGameCharacter character) {
            if(Main.CART_SUPPORTED) CartSteeringHooks.finish(character);
        }
    }

    @Patch(className="zombie.core.skinnedmodel.ModelManager", methodName="DoCharacterModelEquipped", warmUp=true, strictMatch=true)
    public static class WoodenRecoveryModel {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) zombie.characters.IsoGameCharacter character,
            @Patch.Local("toolkitCartVisualOnly") boolean active,
            @Patch.Local("toolkitCartForceNull") boolean previous) {
            active=Main.CART_TRANSITION_SUPPORTED && CartTransition.suppressHeldModel(character);
            // Native held-item binding would add a second copy beside the leased string model.
            if(active) {previous=character.forceNullOverride;character.forceNullOverride=true;}
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Argument(0) zombie.characters.IsoGameCharacter character,
            @Patch.Local("toolkitCartVisualOnly") boolean active,
            @Patch.Local("toolkitCartForceNull") boolean previous) {
            if(active) character.forceNullOverride=previous;
        }
    }

    @Patch(className="zombie.core.skinnedmodel.ModelCameraRenderData", methodName="init", strictMatch=true)
    public static class CartObserverCamera {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.core.skinnedmodel.ModelCameraRenderData data,
            @Patch.Argument(0) zombie.core.skinnedmodel.ModelCamera camera,
            @Patch.Argument(1) zombie.core.skinnedmodel.ModelManager.ModelSlot source) {
            if(Main.CART_OBSERVER_SUPPORTED) CartObserverRender.capture(data,camera,source);
        }
    }

    @Patch(className="zombie.core.skinnedmodel.model.ModelSlotRenderData", methodName="initModel", strictMatch=true)
    public static class CartObserverSlot {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.core.skinnedmodel.model.ModelSlotRenderData slot,
            @Patch.Argument(0) zombie.core.skinnedmodel.ModelManager.ModelSlot source) {
            if(Main.CART_OBSERVER_SUPPORTED) CartObserverRender.bind(slot,source);
            if(Main.CART_TRANSITION_SUPPORTED) CartImpactPose.bind(slot,source);
        }
    }

    @Patch(className="zombie.core.skinnedmodel.model.ModelSlotRenderData", methodName="postRender")
    public static class CartObserverRelease {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.core.skinnedmodel.model.ModelSlotRenderData slot) {
            if(Main.CART_OBSERVER_SUPPORTED) CartObserverRender.release(slot);
            CartImpactPose.release(slot);
        }
    }

    @Patch(className="zombie.core.skinnedmodel.model.ModelSlotRenderData", methodName="initRenderData")
    public static class CartFloor {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.core.skinnedmodel.model.ModelSlotRenderData slot) {
            if(Main.CART_OBSERVER_SUPPORTED) CartObserverRender.prepare(slot);
        }
        @Patch.OnExit
        public static void exit(@Patch.This zombie.core.skinnedmodel.model.ModelSlotRenderData slot) {
            if(Main.CART_SUPPORTED) CartGrounding.render(slot);
        }
    }

    @Patch(className="zombie.core.skinnedmodel.model.WorldItemAtlas$ItemParams", methodName="init", strictMatch=true)
    public static class ShoppingWorldAtlas {
        @Patch.OnExit
        public static void exit(@Patch.This Object params,
            @Patch.Argument(0) zombie.inventory.InventoryItem item,
            @Patch.Argument(1) zombie.core.skinnedmodel.model.Model model,
            @Patch.Argument(2) zombie.scripting.objects.ModelScript script,
            @Patch.Argument(3) float scale,@Patch.Argument(4) zombie.core.ImmutableColor tint,
            @Patch.Argument(5) float hue,@Patch.Argument(6) boolean fluid) {
            if(Main.CART_TRANSITION_SUPPORTED && item!=null && "SaucedCarts.ShoppingCart".equals(item.getFullType())) {
                var transform=Accessor.tryGet(params,"transform",(org.joml.Matrix4f)null);
                if(transform!=null && script!=null) CartWorldSupport.apply(item.getFullType(),transform,script.scale*item.worldScale);
            }
        }
    }

    @Patch(className="zombie.core.skinnedmodel.model.ItemModelRenderer", methodName="init")
    public static class WoodenWorldScale {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.core.skinnedmodel.model.ItemModelRenderer renderer) {
            if(Main.CART_TRANSITION_SUPPORTED) CartEmergencyDrop.clear(renderer);
        }
        @Patch.OnExit
        public static void exit(@Patch.This zombie.core.skinnedmodel.model.ItemModelRenderer renderer,
            @Patch.Argument(0) zombie.inventory.InventoryItem item,
            @Patch.Argument(7) zombie.scripting.objects.ModelScript script) {
            if(Main.CART_TRANSITION_SUPPORTED && item!=null && "SaucedCarts.ShoppingCart".equals(item.getFullType())) {
                var transform=Accessor.tryGet(renderer,"transform",(org.joml.Matrix4f)null);
                if(transform!=null && script!=null) {
                    CartWorldSupport.applyDirect(item.getFullType(),transform,script.scale*item.worldScale);
                    if(Main.CART_WHEEL_SUPPORTED) CartWheelWorld.snapshot(renderer,item,transform);
                }
            }
            if(Main.CART_TRANSITION_SUPPORTED && CartTransition.wheelbarrow(item)) {
                var transform=Accessor.tryGet(renderer,"transform",(org.joml.Matrix4f)null);
                if(transform!=null) {
                    transform.scale(.85f);
                    if(script!=null && item.getWorldItem()!=null && item.getWorldItem().getItem()==item)
                        CartWorldSupport.apply(item.getFullType(),transform,script.scale*item.worldScale);
                    if(Main.CART_WHEEL_SUPPORTED) CartWheelWorld.snapshot(renderer,item,transform);
                }
            }
        }
    }

    // Alpha-zero ground models still write depth, and the outline uses a separate sprite/atlas pass.
    @Patch(className="zombie.core.skinnedmodel.model.ItemModelRenderer", methodName="renderMain", warmUp=true)
    public static class WoodenWorldModel {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This zombie.core.skinnedmodel.model.ItemModelRenderer renderer,
            @Patch.Argument(0) zombie.inventory.InventoryItem item,
            @Patch.Local("toolkitHiddenWorldCart") boolean hidden) {
            hidden=Main.CART_TRANSITION_SUPPORTED && CartTransition.hidden(item);
            if(hidden) renderer.reset();
            return hidden;
        }
        @Patch.OnExit
        public static void exit(@Patch.This zombie.core.skinnedmodel.model.ItemModelRenderer renderer,
            @Patch.Argument(0) zombie.inventory.InventoryItem item,
            @Patch.Local("toolkitHiddenWorldCart") boolean hidden,
            @Patch.Return(readOnly=false) zombie.core.skinnedmodel.model.ItemModelRenderer.RenderStatus result) {
            if(hidden) result=zombie.core.skinnedmodel.model.ItemModelRenderer.RenderStatus.NoModel;
            if(Main.CART_TRANSITION_SUPPORTED) {
                if(result==zombie.core.skinnedmodel.model.ItemModelRenderer.RenderStatus.Ready) CartEmergencyDrop.render(renderer,item);
                else CartEmergencyDrop.clear(renderer);
            }
            if(Main.CART_WHEEL_SUPPORTED && Main.CART_TRANSITION_SUPPORTED) {
                if(result==zombie.core.skinnedmodel.model.ItemModelRenderer.RenderStatus.Ready) CartWheelWorld.ready(renderer);
                else CartWheelWorld.clear(renderer);
            }
        }
    }

    @Patch(className="zombie.core.skinnedmodel.model.ItemModelRenderer", methodName="reset")
    public static class WoodenWorldWheelReset {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.core.skinnedmodel.model.ItemModelRenderer renderer) {
            if(Main.CART_TRANSITION_SUPPORTED) CartEmergencyDrop.clear(renderer);
            if(Main.CART_WHEEL_SUPPORTED && Main.CART_TRANSITION_SUPPORTED) CartWheelWorld.clear(renderer);
        }
    }

    @Patch(className="zombie.core.skinnedmodel.model.ItemModelRenderer", methodName="renderModel")
    public static class WoodenWorldWheelScope {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.core.skinnedmodel.model.ItemModelRenderer renderer,
            @Patch.Argument(0) zombie.core.skinnedmodel.model.Model model,
            @Patch.Argument(1) org.joml.Matrix4f transform, @Patch.Argument(4) boolean weaponPart,
            @Patch.Local("toolkitWorldWheelScope") Object previous) {
            if(Main.CART_WHEEL_SUPPORTED && Main.CART_TRANSITION_SUPPORTED)
                previous=CartWheelWorld.begin(renderer,model,transform,weaponPart);
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Local("toolkitWorldWheelScope") Object previous) {
            if(Main.CART_WHEEL_SUPPORTED && Main.CART_TRANSITION_SUPPORTED) CartWheelWorld.end(previous);
        }
    }

    @Patch(className="zombie.core.skinnedmodel.model.ModelMesh", methodName="Draw")
    public static class WoodenWorldWheelDraw {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This zombie.core.skinnedmodel.model.ModelMesh mesh,
            @Patch.Argument(0) zombie.core.skinnedmodel.shader.Shader shader) {
            return Main.CART_WHEEL_SUPPORTED && Main.CART_TRANSITION_SUPPORTED && CartWheelWorld.render(mesh,shader);
        }
    }

    @Patch(className="zombie.iso.objects.IsoWorldInventoryObject", methodName="render", warmUp=true)
    public static class WoodenWorldSprite {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This zombie.iso.objects.IsoWorldInventoryObject world) {
            return Main.CART_TRANSITION_SUPPORTED && CartTransition.hidden(world.getItem());
        }
    }

    @Patch(className="zombie.iso.objects.IsoWorldInventoryObject", methodName="renderObjectPicker", warmUp=true)
    public static class WoodenWorldPicker {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This zombie.iso.objects.IsoWorldInventoryObject world) {
            return Main.CART_TRANSITION_SUPPORTED && CartTransition.hidden(world.getItem());
        }
    }

    @Patch(className="zombie.iso.fboRenderChunk.FBORenderObjectOutline", methodName="renderObject", warmUp=true)
    public static class WoodenWorldOutline {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(1) zombie.iso.IsoObject object) {
            // The custom 3D cart supplies its own tint; the separate outline can flash its inventory icon.
            return Main.CART_TRANSITION_SUPPORTED && object instanceof zombie.iso.objects.IsoWorldInventoryObject world
                && (CartTransition.hidden(world.getItem())
                    || CartTransition.supported(world.getItem()) && zombie.core.Core.getInstance().isOption3DGroundItem());
        }
    }

    @Patch(className="zombie.core.skinnedmodel.model.WorldItemModelDrawer", methodName="renderAtlasTexture", warmUp=true)
    public static class WoodenWorldAtlas {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(0) zombie.inventory.InventoryItem item) {
            return Main.CART_TRANSITION_SUPPORTED && CartTransition.supported(item);
        }
    }

    @Patch(className="zombie.iso.IsoGridSquare", methodName="AddWorldInventoryItem", strictMatch=true, warmUp=true)
    public static class WoodenSetdownPlacement {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This zombie.iso.IsoGridSquare square,
            @Patch.Argument(0) zombie.inventory.InventoryItem item,
            @Patch.Argument(1) float x, @Patch.Argument(2) float y, @Patch.Argument(3) float z,
            @Patch.Argument(4) boolean transmit,
            @Patch.Local("toolkitPlacedCart") zombie.inventory.InventoryItem placed) {
            placed=Main.CART_TRANSITION_SUPPORTED?CartTransition.place(square,item):null;
            return placed!=null;
        }
        @Patch.OnExit
        public static void exit(@Patch.Local("toolkitPlacedCart") zombie.inventory.InventoryItem placed,
            @Patch.Return(readOnly=false) zombie.inventory.InventoryItem result) {
            if(placed!=null) result=placed;
        }
    }

    @Patch(className="zombie.core.skinnedmodel.model.Model", methodName="DrawSolid")
    public static class WoodenWheel {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This zombie.core.skinnedmodel.model.Model model,
            @Patch.Argument(0) zombie.core.skinnedmodel.model.ModelSlotRenderData slot,
            @Patch.Argument(1) zombie.core.skinnedmodel.model.ModelInstanceRenderData data) {
            return Main.CART_WHEEL_SUPPORTED && CartWheelSpin.render(model,slot,data);
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

    @Patch(className="zombie.vehicles.BaseVehicle", methodName="update", warmUp=true)
    public static class VehicleOwnershipRepair {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.This zombie.vehicles.BaseVehicle car) {
            VehicleOwnership.reconcile(car, Main.VEHICLE_OWNERSHIP_SUPPORTED);
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
