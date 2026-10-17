package net.alexredby.pztoolkitjavapatches;

import java.security.MessageDigest;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.Map;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.NetworkZombieAI;
import zombie.characters.NetworkPlayerAI;
import zombie.characters.animals.IsoAnimal;
import zombie.core.BuildAction;
import zombie.core.properties.IsoPropertyType;
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
import zombie.scripting.ScriptParser;
import zombie.scripting.entity.components.fluids.FluidContainerScript;
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
    public static final boolean PROPERTY_SUPPORTED = supports("zombie/core/properties/IsoPropertyType.class",
        "7e7deb55cc8a949a4cab6cf93e0cabef01090229154203730f758526c948ebd3")
        && supports("zombie/core/TilePropertyAliasMap.class",
            "05124f3536bc2026fb29d5f7369dc0d809d1a725477d4733a1e0e827911a0a80");
    public static final boolean FLUID_SUPPORTED = supports("zombie/scripting/entity/components/fluids/FluidContainerScript.class",
        "d3a4191471515e9ec18f29e153559369d13dd448d02747370546f1af75ac5595")
        && supports("zombie/scripting/ScriptParser$Block.class",
            "14a54eee1c27b98431913e8daa28f2dcae58d8fedb9e3b0ed8b6426f717062d2")
        && supports("zombie/scripting/ScriptParser$Value.class",
            "5cf9e1fa32ef946ac194fd8cf2bf7f95da9eda67076eccd3dfc321b31e14a637");
    public static final boolean FENCE_SUPPORTED = supports("zombie/iso/BrokenFences.class",
        "4368bbe6d2ec26198062bced328c3fef349e6be8e0f7184cbb9086de4cccc015")
        && supports("zombie/Lua/Event.class",
            "cf4b0ba953b8f965fbcacb73ebb5d1a173dc3ed140656e15b90ad932eff0e952")
        && supports("zombie/Lua/LuaEventManager.class",
            "9706f17e9b5e095a0e24230dc944de5d552fa62c997214636c4deb4957cf354b")
        && supports("zombie/iso/IsoWorld.class",
            "5b7406a70f33578a47ff417b0b6aa7a2b7a5bebfa00487a60935303f5747fb71")
        && supports("zombie/iso/sprite/IsoSpriteManager.class",
            "2b2a7b9de0ebd5fb4e346a998a1618503422ddffb8098caa365e8b626054e14a")
        && supports("zombie/entity/components/spriteconfig/SpriteConfigManager.class",
            "ef52c9f6406c594784183ac8598db2bf3d4a8db7933981956e1d79d7b40ba10e")
        && supports("zombie/core/properties/PropertyContainer.class",
            "bc236f8e9e4e0da8a86b0d1fd19ad8d44a040fe4f67d1baac77401b3b148bd77")
        && supports("zombie/audio/parameters/ParameterFenceTypeLow$FenceType.class",
            "8b69bc70ce19066b64ec887a049320046c2659b4727dd51d4038e4e756bcfd09");
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
    public static final boolean BASEMENT_ROOMS_SUPPORTED = supports("zombie/basements/Basements.class",
            "769908ad1fdab2fb667d41943fde29e91b2148d365e5993117601c07c854380c")
        && supports("zombie/iso/BuildingID.class",
            "cfb8cb7815a84b5b6b4dc9743df585bb8d14959acd7c23850a9ec62a084c3ed1")
        && supports("zombie/iso/RoomID.class",
            "d3d5bb425c94b2b6b5f03cd1d47fc82c079984563d4a9e6857c64b3809a2d52d")
        && supports("zombie/iso/BuildingDef.class",
            "b1374ab72a3b7668afb554c22e9a4374841613f028712f3f98bf7a461d10faf1")
        && supports("zombie/iso/RoomDef.class",
            "7cf340ad83010a27bb41a7b576d934c795b3a855118fc683ae80dfa02d8be989")
        && supports("zombie/iso/IsoMetaCell.class",
            "ccf99cd2b176b079da51f31a74ae9408b45255a328f6d1ab6fe536600226cdee")
        && supports("zombie/iso/IsoMetaGrid.class",
            "cdd50bb0a393c766d25c9dcbc5f7e929d7e10a6b9c9b95e22c3bae94b3b5b1f9");
    public static final boolean MANNEQUIN_SUPPORTED = supports("zombie/Lua/LuaManager.class",
            "dcaad0082ca27a15550c7d0a6e14b3aeb71f634a14f32123dec620df180c646d")
        && supports("zombie/Lua/LuaManager$GlobalObject.class",
            "80ecbd3bd702db2f992db6cba7cb09c32d775fa6f2a3297e0460874ff5ba20c7")
        && supports("zombie/iso/IsoMetaGrid.class",
            "cdd50bb0a393c766d25c9dcbc5f7e929d7e10a6b9c9b95e22c3bae94b3b5b1f9")
        && supports("zombie/iso/zones/Zone.class",
            "41faa20ceed9764ba0aa32d8fa81f0329d40a1f5da575beb65601e077346e91c")
        && supports("zombie/iso/objects/IsoMannequin.class",
            "158b696a5ff5ee99e7c60cbd17d7055b6d7c9afbc5c1595e34f2fbcb4feef5e1")
        && supports("zombie/iso/objects/IsoMannequin$MannequinZone.class",
            "34d053c48f0522dbeb73f69daa45683c0feb1ff2181b83ef6d8dcfd53aa3848d");
    public static final boolean PIANO_SUPPORTED = supports("zombie/scripting/entity/GameEntityScript.class",
            "2863b3af3a0dcef1163268da1469aaba2104a90c2def4f625811e8364cecab29")
        && supports("zombie/scripting/entity/components/crafting/CraftRecipeComponentScript.class",
            "aa63d944d55d20277de6d28b032367c4badf39161efc04bbae4a003306675258")
        && supports("zombie/scripting/entity/components/crafting/CraftRecipe.class",
            "a5c076d53e68f5cdfcc5bc17239aee1fb2072766471c29070ca84b30bd63c5de")
        && supports("zombie/scripting/entity/components/spriteconfig/SpriteConfigScript.class",
            "f80f3e287cf1945ca220b4c8daf5c67daa35f26906c9f72bbde8f99b88b8eb02")
        && supports("zombie/scripting/ScriptParser.class",
            "5f33328e2551fd40797697c15a9381b770fb547ac027f199e7dfc9172ac78f87")
        && supports("zombie/core/textures/Texture.class",
            "2f4fba9ad6c33a9ba0763a68d16164833a682f7645e61a061f70bfdca33c1f8f");
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

    public static final boolean CART_SUPPORTED = supports("zombie/characters/IsoPlayer.class",
            "3f1c4634d3a8e7e36baf4b33f76cf7ef79d88c3351bd0eb2a6a6bb34c2d9858f")
        && supports("zombie/characters/IsoGameCharacter.class",
            "29040e19c3e420499f73bc0ea0d5b86d7f7d38655acdc13d0107df736eb54c0b")
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
        && supports("zombie/iso/IsoGridSquare.class", "e8192f87d88da607abe0293228c84efbd822ed4ac0a331102c030bc3eeaba467")
        && supports("zombie/core/skinnedmodel/model/ItemModelRenderer.class", "7bca60683441a873571bb4a8e3030de21852916432040a2dcdacc297757fb008")
        && supports("zombie/core/skinnedmodel/model/WorldItemModelDrawer.class", "f9a83f5dbb3a5f897a502e945fb53150aa4cc4fb98c7996f5eb4bd0475d965d2");

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
        // Resolve before advice installation; resolving inside another transformer can miss these targets.
        if (PROPERTY_SUPPORTED) IsoPropertyType.values();
        if (FLUID_SUPPORTED) FluidContainerScript.class.getName();
        if (PIANO_SUPPORTED) {
            zombie.scripting.entity.GameEntityScript.class.getName();
            zombie.scripting.entity.components.crafting.CraftRecipeComponentScript.class.getName();
            zombie.scripting.entity.components.crafting.CraftRecipe.class.getName();
        }
        if (BASEMENT_ROOMS_SUPPORTED) zombie.basements.Basements.class.getName();
        if (MANNEQUIN_SUPPORTED) {
            zombie.Lua.LuaManager.class.getName();
            zombie.iso.IsoMetaGrid.class.getName();
        }
        boolean fences = FenceValidation.install(FENCE_SUPPORTED);
        System.out.println("[PZToolkitJavaPatches] Experimental B42.21 patch: zombie=" + ZOMBIE_SUPPORTED
            + ", vehicle=" + VEHICLE_SUPPORTED + ", vehicleOwnership=" + VEHICLE_OWNERSHIP_SUPPORTED + ", media=" + MEDIA_SUPPORTED + ", build=" + BUILD_SUPPORTED
            + ", video=" + VIDEO_SUPPORTED + ", animal=" + ANIMAL_SUPPORTED + ", equipment=" + EQUIPMENT_SUPPORTED
            + ", cart=" + CART_SUPPORTED + ", medicalTimedAction=" + MEDICAL_TIMED_ACTION_SUPPORTED + ", medicalBodyDamage=" + MEDICAL_BODY_DAMAGE_SUPPORTED + ", medicalVisuals=" + MEDICAL_VISUALS_SUPPORTED + ", hutch=" + HUTCH_SUPPORTED + ", properties=" + PROPERTY_SUPPORTED + ", fluids=" + FLUID_SUPPORTED
            + ", fences=" + fences + ", piano=" + PIANO_SUPPORTED + ", basementRooms=" + BASEMENT_ROOMS_SUPPORTED + ", mannequin=" + MANNEQUIN_SUPPORTED);
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

    @Patch(className="zombie.basements.Basements", methodName="mergeBuildings", strictMatch=true)
    public static class NativeBasementRoomLookup {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) zombie.iso.BuildingDef incoming,
                                 @Patch.Argument(1) zombie.iso.BuildingDef receiving,
                                 @Patch.Local("toolkitPreviousBuildingID") BasementRoomLookup.State previous) {
            previous = BasementRoomLookup.beforeMerge(receiving, Main.BASEMENT_ROOMS_SUPPORTED);
        }

        @Patch.OnExit
        public static void exit(@Patch.Argument(0) zombie.iso.BuildingDef incoming,
                                @Patch.Argument(1) zombie.iso.BuildingDef receiving,
                                @Patch.Local("toolkitPreviousBuildingID") BasementRoomLookup.State previous) {
            BasementRoomLookup.repair(receiving, previous, Main.BASEMENT_ROOMS_SUPPORTED);
        }
    }

    @Patch(className="zombie.Lua.LuaManager", methodName="RunLua", strictMatch=true)
    public static class NativeMannequinZoneData {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) String file, @Patch.Argument(1) boolean rewrite,
                                 @Patch.Local("toolkitPreviousObjects") Object previous) {
            if (Main.MANNEQUIN_SUPPORTED && "media/maps/Muldraugh, KY/objects.lua".equals(file)
                && zombie.Lua.LuaManager.env != null) previous = zombie.Lua.LuaManager.env.rawget("objects");
        }

        @Patch.OnExit
        public static void exit(@Patch.Argument(0) String file, @Patch.Argument(1) boolean rewrite,
                                @Patch.Local("toolkitPreviousObjects") Object previous) {
            MannequinZoneData.loaded(file, previous, Main.MANNEQUIN_SUPPORTED);
        }
    }

    @Patch(className="zombie.iso.IsoMetaGrid", methodName="registerMannequinZone", strictMatch=true)
    public static class NativeMannequinZonePriority {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.iso.IsoMetaGrid grid,
                                @Patch.Argument(0) String name, @Patch.Argument(1) String type,
                                @Patch.Argument(2) int x, @Patch.Argument(3) int y, @Patch.Argument(4) int z,
                                @Patch.Argument(5) int width, @Patch.Argument(6) int height,
                                @Patch.Argument(7) se.krka.kahlua.vm.KahluaTable properties,
                                @Patch.Return zombie.iso.zones.Zone zone) {
            MannequinZoneData.registered(grid, properties, zone);
        }
    }

    @Patch(className="zombie.scripting.entity.GameEntityScript", methodName="Load", strictMatch=true)
    public static class NativePianoDefinition {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.scripting.entity.GameEntityScript entity,
                                @Patch.Argument(0) String name, @Patch.Argument(1) String body) throws Exception {
            PianoIcon.loaded(entity, body, Main.PIANO_SUPPORTED);
        }
    }

    @Patch(className="zombie.scripting.entity.components.crafting.CraftRecipeComponentScript", methodName="getIconTexture", strictMatch=true)
    public static class NativePianoIcon {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This zombie.scripting.entity.components.crafting.CraftRecipeComponentScript component,
                                    @Patch.Local("toolkitPianoIcon") zombie.core.textures.Texture texture,
                                    @Patch.Local("toolkitPianoHandled") boolean handled) throws Exception {
            handled = PianoIcon.headless(component, Main.PIANO_SUPPORTED);
            if (!handled) texture = PianoIcon.resolve(component, Main.PIANO_SUPPORTED);
            handled = handled || texture != null;
            return handled;
        }

        @Patch.OnExit
        public static void exit(@Patch.Local("toolkitPianoIcon") zombie.core.textures.Texture texture,
                                @Patch.Local("toolkitPianoHandled") boolean handled,
                                @Patch.Return(readOnly=false) zombie.core.textures.Texture result) {
            if (handled) result = texture;
        }
    }

    @Patch(className="zombie.scripting.entity.components.crafting.CraftRecipe", methodName="OnScriptsLoaded", strictMatch=true)
    public static class NativePianoIconLifecycle {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.scripting.entity.components.crafting.CraftRecipe recipe,
                                 @Patch.Argument(0) zombie.scripting.ScriptLoadMode mode,
                                 @Patch.Local("toolkitPianoTexture") zombie.core.textures.Texture texture) throws Exception {
            texture = PianoIcon.beginScripts(recipe, Main.PIANO_SUPPORTED);
        }

        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.This zombie.scripting.entity.components.crafting.CraftRecipe recipe,
                                @Patch.Local("toolkitPianoTexture") zombie.core.textures.Texture texture) throws Exception {
            PianoIcon.endScripts(recipe, texture);
        }
    }

    @Patch(className="zombie.Lua.LuaEventManager", methodName="triggerEvent", strictMatch=true)
    public static class FenceTileDefinitionsDispatch {
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) String event, @Patch.Argument(1) Object manager) {
            // Empty events bypass Event.trigger; queued callbacks complete through its separate advice.
            if (Main.FENCE_SUPPORTED && "OnLoadedTileDefinitions".equals(event)
                && manager == zombie.iso.sprite.IsoSpriteManager.instance
                && zombie.Lua.LuaManager.env != null && zombie.Lua.LuaManager.thread != null
                && zombie.Lua.LuaManager.thread.debugOwnerThread == Thread.currentThread())
                FenceValidation.tilesLoaded();
        }
    }

    @Patch(className="zombie.Lua.Event", methodName="trigger", strictMatch=true)
    public static class FenceTileDefinitions {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.Lua.Event event,
                                @Patch.Argument(0) se.krka.kahlua.vm.KahluaTable env,
                                @Patch.Argument(1) se.krka.kahlua.integration.LuaCaller caller,
                                @Patch.Argument(2) Object[] args) {
            if (Main.FENCE_SUPPORTED && "OnLoadedTileDefinitions".equals(event.name)
                && args != null && args.length == 1 && args[0] == zombie.iso.sprite.IsoSpriteManager.instance)
                FenceValidation.tilesLoaded();
        }
    }

    @Patch(className="zombie.scripting.entity.components.fluids.FluidContainerScript", methodName="load", warmUp=true, strictMatch=true)
    public static class NativeFluidName {
        public static void normalize(ScriptParser.Block block, boolean supported) {
            if (!supported || block == null) return;
            var value = block.getValue("ContainerName");
            if (value == null) return;
            String name = value.getValue().trim();
            // Preserve the native parser's result for two malformed shipped tokens.
            if (name.equals("Large Bucket")) block.setValue("ContainerName", "LargeBucket");
            else if (name.equals("Fuel Pump")) block.setValue("ContainerName", "FuelPump");
        }

        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) ScriptParser.Block block) {
            normalize(block, Main.FLUID_SUPPORTED);
        }
    }

    @Patch(className="zombie.core.properties.IsoPropertyType", methodName="lookupOrDefaultStr", warmUp=true, strictMatch=true)
    public static class NativeStringProperty {
        public static boolean accepts(String name, boolean supported) {
            if (!supported || name == null || !(name.equals("ladderW") || name.equals("ladderN")
                || name.equals("ladderE") || name.equals("ladderS") || name.equals("WindowShape"))) return false;
            var types = Accessor.tryGet(IsoPropertyType.class, "BY_NAME", (Map<?, ?>)null);
            // Preserve typed aliases installed by another mod, and fail closed if access fails.
            return types != null && types.get(name) == null;
        }

        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(0) String name,
                                    @Patch.Local("toolkitStringProperty") String fallback) {
            if (!accepts(name, Main.PROPERTY_SUPPORTED)) return false;
            // Shipped tile definitions use these string properties without enum entries.
            fallback = name;
            return true;
        }

        @Patch.OnExit
        public static void exit(@Patch.Local("toolkitStringProperty") String fallback,
                                @Patch.Return(readOnly=false) String result) {
            if (fallback != null) result = fallback;
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
                x=step.x; y=step.y;
            }
        }
    }

    @Patch(className="zombie.characters.IsoGameCharacter", methodName="postUpdateAnimating", warmUp=true)
    public static class CartHeading {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.characters.IsoGameCharacter character) {
            if(Main.CART_SUPPORTED) CartSteeringHooks.heading(character);
        }
    }

    @Patch(className="zombie.core.skinnedmodel.model.ModelSlotRenderData", methodName="initRenderData")
    public static class CartFloor {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.core.skinnedmodel.model.ModelSlotRenderData slot) {
            if(Main.CART_SUPPORTED) CartGrounding.render(slot);
        }
    }

    @Patch(className="zombie.core.skinnedmodel.model.ItemModelRenderer", methodName="init")
    public static class WoodenWorldScale {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.core.skinnedmodel.model.ItemModelRenderer renderer,
            @Patch.Argument(0) zombie.inventory.InventoryItem item) {
            if(Main.CART_TRANSITION_SUPPORTED && CartTransition.wooden(item)) {
                var transform=Accessor.tryGet(renderer,"transform",(org.joml.Matrix4f)null);
                if(transform!=null) transform.scale(.85f);
                if(CartTransition.hidden(item)) Accessor.trySet(renderer,"alpha",0f);
            }
        }
    }

    @Patch(className="zombie.core.skinnedmodel.model.WorldItemModelDrawer", methodName="renderAtlasTexture", warmUp=true)
    public static class WoodenWorldAtlas {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(0) zombie.inventory.InventoryItem item) {
            return Main.CART_TRANSITION_SUPPORTED && CartTransition.wooden(item);
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
