package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Accessor
import org.joml.Matrix4f
import zombie.characters.CharacterTimedActions.LuaTimedActionNew
import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.characters.NetworkPlayerAI
import zombie.characters.NetworkZombieAI
import zombie.characters.animals.IsoAnimal
import zombie.core.network.ByteBufferReader
import zombie.core.skinnedmodel.ModelManager
import zombie.core.skinnedmodel.model.ItemModelRenderer
import zombie.core.skinnedmodel.model.ModelSlotRenderData
import zombie.inventory.InventoryItem
import zombie.iso.IsoObject
import zombie.iso.Vector2
import zombie.iso.objects.IsoWorldInventoryObject
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.IConnection
import zombie.network.fields.character.PlayerID
import zombie.network.packets.EquipPacket
import zombie.network.packets.character.AnimalPacket
import zombie.network.packets.character.ZombiePacket
import zombie.pathfind.PathFindBehavior2
import zombie.radio.devices.DeviceData
import zombie.scripting.objects.ModelScript
import zombie.vehicles.VehicleInterpolation

/** Hash policy is evaluated one field at a time by Main, in its original cold-start order. */
internal object MainPolicy {
    @JvmStatic
    fun videoSupported(): Boolean =
        BytecodeSupport.supports(
            "org/lwjglx/opengl/Display.class",
            "15a0c0a3646d4340cd96c47d143a5605bfbae7543410ddaa018e83f45ae1a578",
        )

    @JvmStatic
    fun zombieSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/characters/NetworkZombieAI.class",
            "87e4f6e43d16dec23f685b4ebad68eb12eaea15ed87dce3fc3c3394f96cd1e3d",
        )

    @JvmStatic
    fun vehicleOwnershipSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/vehicles/BaseVehicle.class",
            "e7ade19e1e6f66450bef2bd37e52b2afccc7377c4e4571d0fa39435ecdb55661",
        )

    @JvmStatic
    fun vehicleSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/vehicles/VehicleInterpolation.class",
            "e5096d41b4b94c3eb040c119c1ca35b014bbfe3c742401002b88103a650add56",
        )

    @JvmStatic
    fun animalSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/characters/NetworkPlayerAI.class",
            "46df5ede124384e10a848fe9eb6f6ba06cccbb3cc74f51e5e9b0306cd80a628a",
        ) &&
            BytecodeSupport.supports(
                "zombie/vehicles/BaseVehicle.class",
                "e7ade19e1e6f66450bef2bd37e52b2afccc7377c4e4571d0fa39435ecdb55661",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/packets/character/AnimalPacket.class",
                "db6954555bb7b270589d406050eecb4dd79f789e8d5627df7fc43c1e8150f169",
            )

    @JvmStatic
    fun equipmentSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/network/packets/EquipPacket.class",
            "35e25895c725c3154d0f1e4b3217c7e19795ed1296441dbcea9283026ec5da89",
        ) &&
            BytecodeSupport.supports(
                "zombie/network/ZomboidNetData.class",
                "9b81b4f1e3ce8e338f2b8bb838c797353d0b2841396d01325c968051e168419e",
            )

    @JvmStatic
    fun hutchSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/iso/objects/IsoHutch.class",
            "d9c1944025f6902416c83993199a89b2509bb2af3d09a44ced9c61b28c8589ae",
        )

    @JvmStatic
    fun medicalBodyDamageSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/network/packets/BodyDamageUpdatePacket.class",
            "2e37ca1add6b8696464285bd498e7c97cd9712c9094c51d1d57daac688145c8c",
        ) &&
            BytecodeSupport.supports(
                "zombie/network/fields/character/PlayerID.class",
                "d40d1b745a70ad3bf562c15765b9f46a117ecb48aeeabf05597ce646a73e0b56",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/packets/BodyDamageUpdatePacket\$Type.class",
                "e7694d5cfa682aa1fb60cdc85fdbb231bd87f758ce82ef0dc3dd0ccdead52c6c",
            )

    @JvmStatic
    fun medicalVisualsSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/characters/IsoGameCharacter\$Bandages.class",
            "bb87836b717355811e6f699377896918b9d4f4d050a5ad7bc1f1a35a70ebdedd",
        ) &&
            BytecodeSupport.supports(
                "zombie/characters/IsoGameCharacter.class",
                "29040e19c3e420499f73bc0ea0d5b86d7f7d38655acdc13d0107df736eb54c0b",
            ) &&
            BytecodeSupport.supports(
                "zombie/characters/WornItems/WornItems.class",
                "3a01a9b5b7e13d0902fcac9342ac0b42e5c2e87284d88ce9a6a01f45294409c1",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/packets/SyncClothingPacket.class",
                "09e83606c9de4555802b2171e26df4739a78c787afeb8b2907d46c19be311dff",
            )

    @JvmStatic
    fun medicalTimedActionSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/network/PZNetKahluaTableImpl.class",
            "201f0e59502fc5a106f8c9021e0b0d13a30dcb8d0beb9e8934cec390231ddba6",
        ) &&
            BytecodeSupport.supports(
                "zombie/core/NetTimedAction.class",
                "d4a3046eeaec409977a756c6ea80b0676229274684012ad51210559ebfcb1090",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/packets/NetTimedActionPacket.class",
                "ce367190ce6158eb88809f3215ebc471e6161896d9d526eb9ef0e73d58de847b",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/Action.class",
                "4a2fe6aaf0cf73235279946e930b40489ec44859aff64cc19d97976bcc75610d",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/fields/character/PlayerID.class",
                "d40d1b745a70ad3bf562c15765b9f46a117ecb48aeeabf05597ce646a73e0b56",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/ZomboidNetData.class",
                "9b81b4f1e3ce8e338f2b8bb838c797353d0b2841396d01325c968051e168419e",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/fields/IDShort.class",
                "852188ce7dceb2a40c32ae233d6fcdbdec3cc74dd45d9d5151334308f514cdcd",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/network/ByteBufferReader.class",
                "1c2731f2a49b57d2ad895069d499705f8492e3cb6ac275a8f1163b4940e370ff",
            )

    @JvmStatic
    fun mediaSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/radio/devices/DeviceData.class",
            "492af532cddfe49908a5f479e2749b8dc08334a6b661ab81eb81892926cdb102",
        )

    @JvmStatic
    fun buildSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/core/BuildAction.class",
            "320afae90b4723456f349787a09c179f53de2533a19393434d34fc569eb4f368",
        ) &&
            BytecodeSupport.supports(
                "zombie/core/ActionManager.class",
                "3e85655f0d287837b17164d2ee4cecb7067ab419ffbe8ce1adb36bd7d54b202f",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/Action.class",
                "4a2fe6aaf0cf73235279946e930b40489ec44859aff64cc19d97976bcc75610d",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/packets/BuildActionPacket.class",
                "c09201418a8aa248ea349314fba21de85fb2d768e0df4afb4bc8d32bfbf524db",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/packets/GeneralActionPacket.class",
                "398a8729da87a4c222f17473cc46c9b5cb7fd9b3f74492d283765619c1d57c8a",
            )

    @JvmStatic
    fun cartSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/characters/component/CharacterInputComponent.class",
            "e3ff79ae666e7809f753cbe7aac4a3e4729f520d4f795009643efc222b22088d",
        ) &&
            BytecodeSupport.supports(
                "zombie/characters/IsoPlayer.class",
                "3f1c4634d3a8e7e36baf4b33f76cf7ef79d88c3351bd0eb2a6a6bb34c2d9858f",
            ) &&
            BytecodeSupport.supports(
                "zombie/characters/IsoGameCharacter.class",
                "29040e19c3e420499f73bc0ea0d5b86d7f7d38655acdc13d0107df736eb54c0b",
            ) &&
            BytecodeSupport.supports(
                "zombie/pathfind/PathFindBehavior2.class",
                "06b4af799cd9e335aee738bcad498215c5068038d8dfc524bb7b6337e923a127",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/IsoMovingObject.class",
                "7e6e84fe9d3cb264e8d8e682d91e0abe919d481b7349d17b997e8a78f2293a5f",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/animation/AnimationPlayer.class",
                "06fc56e5aa626c808e8c6c0870dc87c10a957d86c7c22782be1d437d52b8bc28",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/model/ModelSlotRenderData.class",
                "83fab9cb79f1c2ba270d8b49e8cf2c166ca36e08986c52517ba73d15cd34f76d",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/model/SkinningData.class",
                "1ee3fea347d68d2197f1015201841d5981e8806792168364a837b8b2391dfe7b",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/animation/AnimationClip.class",
                "374d961e0aa023873b726e467101c4be74d65caaafbb9f3e7f8cea148b25c859",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/advancedanimation/AnimNode.class",
                "1b7cdc17098c2db683ab31b77a937b38b04ce275cb4c9582890afb97c5ce4dbe",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/advancedanimation/Anim2DBlendPicker.class",
                "445b3cab515d642eb67ed10b6ff84cc6c5a1ef4cd249d32ce1de6270ffb39446",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/model/ModelInstanceRenderData.class",
                "67702b5ea23d20fb9af7bf44534dd4c48d607be5adf7c14ed3a5628b27f75a5f",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/advancedanimation/AnimatedModel\$AnimatedModelInstanceRenderData.class",
                "c96e48b6d138db930abe557459b2ff81e025a47cba6c3b199700473362e2f04d",
            )

    @JvmStatic
    fun cartSyncSupported(): Boolean =
        Main.CART_SUPPORTED &&
            BytecodeSupport.supports(
                "zombie/network/packets/character/PlayerPacket.class",
                "5284e8225bf513241787276471f20b526b8373a5f22c714f1370b6f013cfe5de",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/packets/VariableSyncPacket.class",
                "4fc2d32a491eb3f9e96aa0069dcd0f322e5d29e04e75c837cd4ec59cda42ef09",
            ) &&
            BytecodeSupport.supports(
                "zombie/characters/NetworkPlayerAI.class",
                "46df5ede124384e10a848fe9eb6f6ba06cccbb3cc74f51e5e9b0306cd80a628a",
            ) &&
            BytecodeSupport.supports(
                "zombie/characters/NetworkCharacterAI.class",
                "7ec30ba9fc20cd90ab14c36907c89ccba11faf29c506739e0998c167c598c4c8",
            )

    @JvmStatic
    fun cartObserverSupported(): Boolean =
        Main.CART_SYNC_SUPPORTED &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/ModelCameraRenderData.class",
                "62fe74b8116809d43c5d798c8d638c632ef6dca22fb37bdbde6dabd8a625f897",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/textures/TextureDraw.class",
                "d602006055d324763e2278416dfef6ca3787b91c070d2ef4c420a950f6d81fb0",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/opengl/CharacterModelCamera.class",
                "2aecdf733008e6558db9a98ea799dcd76e3ee2cad9371a6c790aa780c2877d9f",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/sprite/IsoSprite.class",
                "68c01e6b1c914f662621743e09c8dd8a62c0258392ce1a75654a713e1034067f",
            )

    @JvmStatic
    fun cartWheelSupported(): Boolean =
        Main.CART_SUPPORTED &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/model/Model.class",
                "3dd5e7b618cecf3c27e216a386e07937b1be694a7fc083b1bc2f7c993cbee3d9",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/model/VertexBufferObject.class",
                "9548415619074b6ebba619c2b5ce546b3f0e0812a5e3b6155c5a0892511b53a1",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/model/ModelMesh.class",
                "b12e7b5091f84ef60e72dd358e85d6611063ca5885d3237feda51dfb604f1f20",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/shader/Shader.class",
                "e9377a60cfe66b4907f57ab6a7a6d6275c991035e7326a1c4663520c09a04014",
            )

    @JvmStatic
    fun cartTransitionSupported(): Boolean =
        Main.CART_SUPPORTED &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/ModelManager.class",
                "9bd955ded08c284dd1e1a5f39c84dd8576e7a46186b3c6fdf69ef4b12d8709e5",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/IsoGridSquare.class",
                "e8192f87d88da607abe0293228c84efbd822ed4ac0a331102c030bc3eeaba467",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/objects/IsoWorldInventoryObject.class",
                "7be6f2d54525fa587908ce8efa7da5d26cfd3d19bd1cc02911ee12f7649857b3",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/fboRenderChunk/FBORenderObjectOutline.class",
                "175e9ae7b5307a2ddaa02adb006c18e30823dbae626348c8e73d6613173d8471",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/model/ItemModelRenderer.class",
                "7bca60683441a873571bb4a8e3030de21852916432040a2dcdacc297757fb008",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/model/WorldItemAtlas\$ItemParams.class",
                "c68663042d7995e201c3fb13c2bf429418fe848aeae6ffcc987d5fc3980a8485",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/model/WorldItemModelDrawer.class",
                "f9a83f5dbb3a5f897a502e945fb53150aa4cc4fb98c7996f5eb4bd0475d965d2",
            )

    @JvmStatic
    fun completionSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/characters/CharacterTimedActions/LuaTimedActionNew.class",
            "f10236f1e8be9d0822dc144ebe61c42fa1d0e8ded3279c7aa6dd0ffb7291feb0",
        ) &&
            BytecodeSupport.supports(
                "zombie/characters/CharacterTimedActions/BaseAction.class",
                "ce23d4ebefaf3f35b15d24e5139a1d5a9e3bdc97d176d20307dafdaf8c3b3392",
            ) &&
            BytecodeSupport.supports(
                "zombie/characters/IsoGameCharacter.class",
                "29040e19c3e420499f73bc0ea0d5b86d7f7d38655acdc13d0107df736eb54c0b",
            ) &&
            BytecodeSupport.supports(
                "se/krka/kahlua/integration/LuaCaller.class",
                "0443930027e8f312ae9cb192c628f4b6c10743204597c508f8693cfd7bd79d0b",
            )
}

/** Business logic behind Main's Java annotation and writable-advice adapters. */
internal object MainSupport {
    @JvmStatic
    @Throws(ClassNotFoundException::class)
    fun startup() {
        // Prepare targets before ZombieBuddy installs advice; order is significant for cold
        // startup.
        TilePropertyNames.prepare()
        FluidContainerNames.prepare()
        PianoIcon.prepare()
        BasementRoomLookup.prepare()
        BasementHallKey.prepare()
        MannequinZoneData.prepare()
        BarricadedDoorPaths.prepare()
        val fences = FenceValidation.install(FenceValidation.SUPPORTED)
        val itemBatches = ItemBatchAdmission.install(ItemBatchAdmission.SUPPORTED)
        val hostLoader = HostLoader.install()
        // Define before patch registration: recursive loads during another transform bypass
        // instrumentation.
        if (Main.CART_TRANSITION_SUPPORTED)
            Class.forName(
                "zombie.core.skinnedmodel.ModelManager",
                false,
                Main::class.java.classLoader,
            )
        System.out.println(
            "[PZToolkitJavaPatches] Experimental B42.21 patch: zombie=" +
                Main.ZOMBIE_SUPPORTED +
                ", vehicle=" +
                Main.VEHICLE_SUPPORTED +
                ", vehicleOwnership=" +
                Main.VEHICLE_OWNERSHIP_SUPPORTED +
                ", media=" +
                Main.MEDIA_SUPPORTED +
                ", radioInventoryOff=" +
                RadioInventoryState.SUPPORTED +
                ", build=" +
                Main.BUILD_SUPPORTED +
                ", video=" +
                Main.VIDEO_SUPPORTED +
                ", animal=" +
                Main.ANIMAL_SUPPORTED +
                ", equipment=" +
                Main.EQUIPMENT_SUPPORTED +
                ", cart=" +
                Main.CART_SUPPORTED +
                ", cartSync=" +
                Main.CART_SYNC_SUPPORTED +
                ", medicalTimedAction=" +
                Main.MEDICAL_TIMED_ACTION_SUPPORTED +
                ", medicalBodyDamage=" +
                Main.MEDICAL_BODY_DAMAGE_SUPPORTED +
                ", medicalVisuals=" +
                Main.MEDICAL_VISUALS_SUPPORTED +
                ", hutch=" +
                Main.HUTCH_SUPPORTED +
                ", properties=" +
                TilePropertyNames.SUPPORTED +
                ", fluids=" +
                FluidContainerNames.SUPPORTED +
                ", fences=" +
                fences +
                ", piano=" +
                PianoIcon.SUPPORTED +
                ", basementRooms=" +
                BasementRoomLookup.SUPPORTED +
                ", basementHall=" +
                BasementHallKey.SUPPORTED +
                ", mannequin=" +
                MannequinZoneData.SUPPORTED +
                ", itemTransactions=" +
                QueueManagers.ITEM_SUPPORTED +
                ", itemBatchAdmission=" +
                itemBatches +
                ", actionManager=" +
                QueueManagers.ACTION_SUPPORTED +
                ", actionCompletion=" +
                Main.COMPLETION_SUPPORTED +
                ", actionAcknowledgements=" +
                ActionAcknowledgements.SUPPORTED +
                ", craftBench=" +
                CraftBenchReferences.SUPPORTED +
                ", barricadedDoors=" +
                BarricadedDoorPaths.SUPPORTED +
                ", hostLoader=" +
                hostLoader,
        )
    }

    @JvmStatic
    fun beginPerformed(action: LuaTimedActionNew?): ActionCompletion.Scope? {
        var scope = ActionCompletion.begin(action, "perform", Main.COMPLETION_SUPPORTED)
        if (
            scope == null &&
                Main.COMPLETION_SUPPORTED &&
                Main.CART_TRANSITION_SUPPORTED &&
                CartTransition.observePickupPerform(action)
        )
            scope = ActionCompletion.observeOnly(action, "perform")
        return scope
    }

    @JvmStatic
    fun performed(action: LuaTimedActionNew?, scope: ActionCompletion.Scope?, failure: Throwable?) {
        ActionCompletion.end(scope, failure)
        if (Main.CART_TRANSITION_SUPPORTED && Main.COMPLETION_SUPPORTED)
            CartTransition.pickupPerformed(action, scope, failure)
    }

    @JvmStatic
    fun equipmentParsed(packet: EquipPacket?, reader: ByteBufferReader?, connection: IConnection?) {
        Main.EquipmentEcho.incomplete = null
        if (!GameClient.client || !Main.EQUIPMENT_SUPPORTED) return
        val player = Accessor.tryGet<PlayerID>(packet, "player", null)
        if (!reader!!.bb.hasRemaining()) {
            if (Main.CART_TRANSITION_SUPPORTED && player != null)
                CartTransition.pickupEquipped(player.getPlayer(), connection)
            return
        }
        if (player != null && player.getPlayer() != null && player.getPlayer().isLocalPlayer())
            Main.EquipmentEcho.incomplete = packet
    }

    @JvmStatic
    fun equipmentEcho(packet: EquipPacket?): Boolean {
        if (!GameClient.client || !Main.EQUIPMENT_SUPPORTED) return false
        // An early Equip returns before the remaining hand is parsed; acknowledging it would clear
        // the server's new animal.
        val skip = Main.EquipmentEcho.incomplete === packet
        Main.EquipmentEcho.incomplete = null
        return skip
    }

    @JvmStatic
    fun animalTrailerLocation(ai: NetworkPlayerAI?, packet: AnimalPacket?) {
        if (
            Main.AnimalTrailerLocation.disabled ||
                !GameClient.client ||
                !Main.ANIMAL_SUPPORTED ||
                packet == null ||
                (packet.location.toInt() != 0 &&
                    packet.location.toInt() != 1 &&
                    packet.location.toInt() != 3)
        )
            return
        val animal = ai!!.getCharacter() as? IsoAnimal ?: return
        try {
            val vehicle = animal.getVehicle() ?: return
            // A late trailer snapshot can re-add a grabbed animal; the next real location must
            // detach it.
            while (vehicle.getAnimals().remove(animal)) {}
            animal.setVehicle(null)
            var size = 0f
            for (remaining in vehicle.getAnimals()) size += remaining.getAnimalTrailerSize()
            vehicle.setCurrentTotalAnimalSize(size)
        } catch (error: RuntimeException) {
            Main.AnimalTrailerLocation.disabled = true
            System.err.println(
                "[PZToolkitJavaPatches] Animal trailer reconciliation disabled: $error",
            )
        }
    }

    @JvmStatic
    fun beginCartPath(path: PathFindBehavior2?) {
        if (Main.CART_SUPPORTED)
            CartSteeringHooks.beginPath(Accessor.tryGet<IsoGameCharacter>(path, "chr", null))
    }

    @JvmStatic
    fun cartPathResult(
        path: PathFindBehavior2?,
        original: PathFindBehavior2.BehaviorResult?,
    ): PathFindBehavior2.BehaviorResult? {
        var result = original
        if (Main.CART_SUPPORTED)
            result =
                CartSteeringHooks.pathResult(
                    Accessor.tryGet<IsoGameCharacter>(path, "chr", null),
                    result,
                )
        if (Main.CART_TRANSITION_SUPPORTED && Main.COMPLETION_SUPPORTED)
            result =
                CartPickupApproach.result(
                    Accessor.tryGet<IsoGameCharacter>(path, "chr", null),
                    path,
                    result,
                )
        return result
    }

    @JvmStatic
    fun cartMovement(player: IsoPlayer?, x: Float, y: Float): Vector2 {
        val step = CartSteeringHooks.movement(player, x, y)
        return CartImpactMotion.movement(player, step.x, step.y)
    }

    @JvmStatic
    fun cartHeading(character: IsoGameCharacter?) {
        if (Main.CART_TRANSITION_SUPPORTED) CartTransition.prunePickupHandoffs()
        if (Main.CART_SUPPORTED) CartSteeringHooks.heading(character)
    }

    @JvmStatic
    fun bindCartSlot(slot: ModelSlotRenderData?, source: ModelManager.ModelSlot?) {
        if (Main.CART_OBSERVER_SUPPORTED) CartObserverRender.bind(slot, source)
        if (Main.CART_TRANSITION_SUPPORTED) CartImpactPose.bind(slot, source)
        if (Main.CART_SUPPORTED) CartShoppingTurn.bind(slot, source)
    }

    @JvmStatic
    fun releaseCartSlot(slot: ModelSlotRenderData?) {
        if (Main.CART_OBSERVER_SUPPORTED) CartObserverRender.release(slot)
        CartImpactPose.release(slot)
        CartShoppingTurn.release(slot)
    }

    @JvmStatic
    fun shoppingWorldAtlas(params: Any?, item: InventoryItem?, script: ModelScript?) {
        if (
            Main.CART_TRANSITION_SUPPORTED &&
                item != null &&
                "SaucedCarts.ShoppingCart".equals(item.getFullType())
        ) {
            val transform = Accessor.tryGet<Matrix4f>(params, "transform", null)
            if (transform != null && script != null)
                CartWorldSupport.apply(
                    item.getFullType(),
                    transform,
                    script.scale * item.worldScale,
                )
        }
    }

    @JvmStatic
    fun worldScale(renderer: ItemModelRenderer?, item: InventoryItem?, script: ModelScript?) {
        if (
            Main.CART_TRANSITION_SUPPORTED &&
                item != null &&
                "SaucedCarts.ShoppingCart".equals(item.getFullType())
        ) {
            val transform = Accessor.tryGet<Matrix4f>(renderer, "transform", null)
            if (transform != null && script != null) {
                CartWorldSupport.applyDirect(
                    item.getFullType(),
                    transform,
                    script.scale * item.worldScale,
                )
                if (Main.CART_WHEEL_SUPPORTED) CartWheelWorld.snapshot(renderer, item, transform)
            }
        }
        if (Main.CART_TRANSITION_SUPPORTED && CartTransition.wheelbarrow(item)) {
            val transform = Accessor.tryGet<Matrix4f>(renderer, "transform", null)
            if (transform != null) {
                transform.scale(.85f)
                if (
                    script != null &&
                        item!!.getWorldItem() != null &&
                        item.getWorldItem().getItem() === item
                )
                    CartWorldSupport.apply(
                        item.getFullType(),
                        transform,
                        script.scale * item.worldScale,
                    )
                if (Main.CART_WHEEL_SUPPORTED) CartWheelWorld.snapshot(renderer, item, transform)
            }
        }
    }

    @JvmStatic
    fun hideWorldModel(renderer: ItemModelRenderer?, item: InventoryItem?): Boolean {
        val hidden = Main.CART_TRANSITION_SUPPORTED && CartTransition.hidden(item)
        if (hidden) renderer!!.reset()
        return hidden
    }

    @JvmStatic
    fun worldModelReady(
        renderer: ItemModelRenderer?,
        item: InventoryItem?,
        result: ItemModelRenderer.RenderStatus?,
    ) {
        if (Main.CART_TRANSITION_SUPPORTED) {
            if (result === ItemModelRenderer.RenderStatus.Ready)
                CartEmergencyDrop.render(renderer, item)
            else CartEmergencyDrop.clear(renderer)
        }
        if (Main.CART_WHEEL_SUPPORTED && Main.CART_TRANSITION_SUPPORTED) {
            if (result === ItemModelRenderer.RenderStatus.Ready) CartWheelWorld.ready(renderer)
            else CartWheelWorld.clear(renderer)
        }
    }

    @JvmStatic
    fun resetWorldModel(renderer: ItemModelRenderer?) {
        if (Main.CART_TRANSITION_SUPPORTED) CartEmergencyDrop.clear(renderer)
        if (Main.CART_WHEEL_SUPPORTED && Main.CART_TRANSITION_SUPPORTED)
            CartWheelWorld.clear(renderer)
    }

    @JvmStatic
    fun hideWorldOutline(obj: IsoObject?): Boolean {
        // The custom 3D cart supplies its own tint; the separate outline can flash its inventory
        // icon.
        if (!Main.CART_TRANSITION_SUPPORTED) return false
        val world = obj as? IsoWorldInventoryObject ?: return false
        return CartTransition.hidden(world.getItem()) ||
            CartTransition.supported(world.getItem()) &&
                zombie.core.Core.getInstance().isOption3DGroundItem()
    }

    @JvmStatic
    fun mediaRestart(data: DeviceData?) {
        // A successful restart must cancel the old stop tail before it silently stops playback
        // again.
        if (
            GameServer.server &&
                Main.MEDIA_SUPPORTED &&
                data!!.isPlayingMedia() &&
                !Accessor.trySet(data, "isStoppingMedia", false)
        )
            System.err.println("[PZToolkitJavaPatches] Cannot clear media stop state")
    }

    @JvmStatic
    fun zombieSpeedDecode(ai: NetworkZombieAI?, packet: ZombiePacket?) {
        if (GameClient.client && Main.ZOMBIE_SUPPORTED && ai!!.zombie.isRemoteZombie()) {
            // Sender and initial-spawn decoder use thousandths; update decoder omitted the scale.
            ai.zombie.setSpeedMod(packet!!.speedMod / 1000.0f)
        }
    }

    @JvmStatic
    fun vehicleRecovery(interpolation: VehicleInterpolation?) {
        // Called only when the buffer is empty. The new seed contains the current displayed pose.
        if (GameClient.client && Main.VEHICLE_SUPPORTED) interpolation!!.clearLast()
    }
}
