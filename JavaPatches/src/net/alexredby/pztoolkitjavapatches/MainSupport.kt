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
import zombie.network.fields.character.ConnectionPlayer
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
            "3b49c8639b52dcfe11daa70c3d397ea8b55c22fb09b9ede2f7b523fee3b7b525",
        )

    @JvmStatic
    fun zombieSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/characters/NetworkZombieAI.class",
            "904bb3decce8e4b066d72901efe5605d61db114d7fa22b711b4d15fcb3c91aac",
        )

    @JvmStatic
    fun vehicleOwnershipSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/vehicles/BaseVehicle.class",
            "354b166db919f8de692a5327b7afd01fefdbfb8021f0c99e2b2b44a3fe606de3",
        )

    @JvmStatic
    fun vehicleSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/vehicles/VehicleInterpolation.class",
            "4cca6a3955e65539c91a3f9a5c2a6e13cf552b11358f704f71b9c1124c360a9e",
        )

    @JvmStatic
    fun animalSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/characters/NetworkPlayerAI.class",
            "366bfdcd71006ba898845c504a3482d7aa3665c9ead3c293a349e0bf13be553c",
        ) &&
            BytecodeSupport.supports(
                "zombie/vehicles/BaseVehicle.class",
                "354b166db919f8de692a5327b7afd01fefdbfb8021f0c99e2b2b44a3fe606de3",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/packets/character/AnimalPacket.class",
                "c8f60d21aa1b6418d1868dc09e19c2a0e5df3ce4fab2185b22555d8d51f2dff7",
            )

    @JvmStatic
    fun equipmentSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/network/packets/EquipPacket.class",
            "4b47f5fe7f60eb5c659291f6f4117a332790d970414e9050109002d851493e17",
        ) &&
            BytecodeSupport.supports(
                "zombie/network/ZomboidNetData.class",
                "abb936adab371b793d764f0114edc05fbff0cc35069ccc3cffca0ff98e4d95ea",
            )

    @JvmStatic
    fun medicalBodyDamageSupported(): Boolean =
        QueueManagerSupport.ACTION_SUPPORTED && BytecodeSupport.supports(
            "zombie/network/packets/BodyDamageUpdatePacket.class",
            "9d6160bc79dc1ec2271bfbe0e18d1d87f04d5562e3434bafc2c216739d7b5f0d",
        ) &&
            BytecodeSupport.supports(
                "zombie/network/fields/character/OnlinePlayer.class",
                "e9f370600998964634e186ee02ecf05612e993a4f0b1537d43c64e4b7ca1f208",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/packets/BodyDamageUpdatePacket\$Type.class",
                "bd3a7f11b23ff5c8d578ae9faaa85dd6f399db05dfb096cf01e5c01239dfeede",
            )

    @JvmStatic
    fun medicalTimedActionSupported(): Boolean =
        QueueManagerSupport.ACTION_SUPPORTED && BytecodeSupport.supports(
            "zombie/network/PZNetKahluaTableImpl.class",
            "d57f0a86e74b58afca38a594950010d3f1209cddfca8664683c6f404c72ade6e",
        ) &&
            BytecodeSupport.supports(
                "zombie/core/NetTimedAction.class",
                "d4a3046eeaec409977a756c6ea80b0676229274684012ad51210559ebfcb1090",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/packets/NetTimedActionPacket.class",
                "9cb604c83db6c649df060cf3228b475163aebb1232a8926deaf13a5b3d2394bc",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/Action.class",
                "19eac0c47039721228c35bc23204a34899a7bee4ea97a0564e0d1f8254a3ac31",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/fields/character/PlayerID.class",
                "18b3204bb706364655dfa832390d2473b0c02dbf9bb4936b5e128749932616b7",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/ZomboidNetData.class",
                "abb936adab371b793d764f0114edc05fbff0cc35069ccc3cffca0ff98e4d95ea",
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
            "6c8825dbc39b2a7508a903dd3ef381bbb3dbd9b96f89398d9deeaddde0162bed",
        )

    @JvmStatic
    fun buildSupported(): Boolean =
        QueueManagerSupport.ACTION_SUPPORTED && BytecodeSupport.supports(
            "zombie/core/BuildAction.class",
            "61fc2957833f87611b1095cdfc61a03b18abbce06e633634de841deefc658270",
        ) &&
            BytecodeSupport.supports(
                "zombie/core/ActionManager.class",
                "499b2d6179fc96a49e150f5dcb92ee813973491e4abd50335249430080d7cf25",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/Action.class",
                "19eac0c47039721228c35bc23204a34899a7bee4ea97a0564e0d1f8254a3ac31",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/packets/BuildActionPacket.class",
                "e634b3486cb5216cc826e73db24d9cd9e2718b7182af3a617633119095d40acf",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/packets/GeneralActionPacket.class",
                "e2d14e57520245a85578d6159d0b21815f94729e9a651afcaee92fdd4f69ec41",
            )

    @JvmStatic
    fun cartSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/characters/component/CharacterInputComponent.class",
            "9aa76ce89f40089e57eac9d1429a8d0f3998008262836ca68524cb7ceb93058e",
        ) &&
            BytecodeSupport.supports(
                "zombie/characters/IsoPlayer.class",
                "643585044a88ad1b29e8d5173774f66085c685c363ed10a89c0b79018de2874e",
            ) &&
            BytecodeSupport.supports(
                "zombie/characters/IsoGameCharacter.class",
                "1ccabc492ba130f51486bf38a8400334545852253bbac9c46fff71242ab672f6",
            ) &&
            BytecodeSupport.supports(
                "zombie/pathfind/PathFindBehavior2.class",
                "e3315dfff6b37eeb7a76d39601e365485d100d0ef37ca27a470ee60329e632f5",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/IsoMovingObject.class",
                "70c0249c3bdb7b4c4fc335e644c74bc98c37aa0e4bfdc0665a75521460ea0900",
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
                "3a40b3c8b3f39d2475cfe51fbe1ce32f13b990c8404a79649173e75d986ed155",
            )

    @JvmStatic
    fun cartInjurySupported(): Boolean =
        Main.CART_SUPPORTED &&
            BytecodeSupport.supports(
                "zombie/core/skinnedmodel/advancedanimation/AnimLayer.class",
                "dd53bf0235a8ef65edb71049bbadea742dcfbfaa0c8a1da7781a26b3282feb01",
            )

    @JvmStatic
    fun cartSyncSupported(): Boolean =
        Main.CART_SUPPORTED &&
            BytecodeSupport.supports(
                "zombie/network/packets/character/PlayerPacket.class",
                "060b6081359a9c794478858796ed1029976f3551bb1df77ec1de3b6d83793dfa",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/packets/VariableSyncPacket.class",
                "98610e44c6e0256fd6c3393126d56c3314306dcd3a9912bfad4054d030364444",
            ) &&
            BytecodeSupport.supports(
                "zombie/characters/NetworkPlayerAI.class",
                "366bfdcd71006ba898845c504a3482d7aa3665c9ead3c293a349e0bf13be553c",
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
                "498f94e38b171ed0eb528b3ab3b90cbf0d152cc81bfe9a3e1345825a627a04ce",
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
                "b8cef32a10bb76433bad174397b51f1a046be1eef47997dc1e79dd8547d726c5",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/objects/IsoWorldInventoryObject.class",
                "1019fd27cfce76d84a8db499a71568429e87e95de504e041a202e0ba9c01ee0b",
            ) &&
            BytecodeSupport.supports(
                "zombie/iso/fboRenderChunk/FBORenderObjectOutline.class",
                "7ad0f0cb324a9ead97a2aea9d6a96fbb7057f9617d3cf2d2da071351757be284",
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
                "960f5757af7756e7a0e0090581ba0d70f20d6f8ef895d12e028ebe2a47f0038b",
            )

    @JvmStatic
    fun completionSupported(): Boolean =
        BytecodeSupport.supports(
            "zombie/characters/CharacterTimedActions/LuaTimedActionNew.class",
            "020a9e5c22b25bdffca7f396612d420e9cea6f78f7432015ac146f19728ac1a6",
        ) &&
            BytecodeSupport.supports(
                "zombie/characters/CharacterTimedActions/BaseAction.class",
                "ce23d4ebefaf3f35b15d24e5139a1d5a9e3bdc97d176d20307dafdaf8c3b3392",
            ) &&
            BytecodeSupport.supports(
                "zombie/characters/IsoGameCharacter.class",
                "1ccabc492ba130f51486bf38a8400334545852253bbac9c46fff71242ab672f6",
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
        val itemClock = ItemTransactionClock.install(ItemTransactionClock.SUPPORTED)
        val hostLoader = HostLoader.install()
        val cutawaySouthEdge = !GameServer.server && CutawaySouthEdge.install()
        // Define before patch registration: recursive loads during another transform bypass
        // instrumentation.
        if (Main.CART_TRANSITION_SUPPORTED)
            Class.forName(
                "zombie.core.skinnedmodel.ModelManager",
                false,
                Main::class.java.classLoader,
            )
        System.out.println(
            "[PZToolkitJavaPatches] Experimental B42.22.2 patch: zombie=" +
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
                ", cutawaySouthEdge=" +
                cutawaySouthEdge +
                ", translucentSquareUnion=" +
                translucentSquareUnion +
                ", worldItemTextureDimensions=" +
                worldItemTextureDimensions +
                ", video=" +
                Main.VIDEO_SUPPORTED +
                ", animal=" +
                Main.ANIMAL_SUPPORTED +
                ", equipment=" +
                Main.EQUIPMENT_SUPPORTED +
                ", cart=" +
                Main.CART_SUPPORTED +
                ", cartInjury=" +
                Main.CART_INJURY_SUPPORTED +
                ", cartSync=" +
                Main.CART_SYNC_SUPPORTED +
                ", medicalTimedAction=" +
                Main.MEDICAL_TIMED_ACTION_SUPPORTED +
                ", medicalBodyDamage=" +
                Main.MEDICAL_BODY_DAMAGE_SUPPORTED +
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
                QueueManagerSupport.ITEM_SUPPORTED +
                ", itemBatchAdmission=" +
                itemBatches +
                ", itemTransactionClock=" +
                itemClock +
                ", actionManager=" +
                QueueManagerSupport.ACTION_SUPPORTED +
                ", actionCompletion=" +
                Main.COMPLETION_SUPPORTED +
                ", actionAcknowledgements=" +
                ActionAcknowledgements.SUPPORTED +
                ", craftBench=" +
                CraftBenchReferences.SUPPORTED +
                ", barricadedDoors=" +
                BarricadedDoorPaths.SUPPORTED +
                ", cutawaySouthEdge=" +
                cutawaySouthEdge +
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
        val player = Accessor.tryGet<ConnectionPlayer>(packet, "player", null)
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
