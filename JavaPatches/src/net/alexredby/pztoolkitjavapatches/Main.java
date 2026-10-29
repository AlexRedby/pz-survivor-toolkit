package net.alexredby.pztoolkitjavapatches;

import java.util.HashMap;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.NetworkZombieAI;
import zombie.characters.NetworkPlayerAI;
import zombie.characters.animals.IsoAnimal;
import zombie.core.BuildAction;
import zombie.core.network.ByteBufferReader;
import zombie.core.raknet.UdpConnection;
import zombie.iso.objects.IsoHutch;
import zombie.network.IConnection;
import zombie.network.packets.EquipPacket;
import zombie.network.GameServer;
import zombie.network.packets.character.ZombiePacket;
import zombie.network.packets.character.AnimalPacket;
import zombie.radio.devices.DeviceData;
import zombie.vehicles.VehicleInterpolation;

public final class Main {
    public static final boolean VIDEO_SUPPORTED = MainPolicy.videoSupported();

    @Patch(className="zombie.Lua.LuaManager", methodName="RunLua", warmUp=true, strictMatch=true)
    public static class QueueBindingLoading {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) String file, @Patch.Argument(1) boolean rewrite,
                @Patch.Local("toolkitQueueBindingSource") QueueBindingSource.Scope previous) {
            previous = QueueBindingSource.begin(file, QueueBindingHooks.SUPPORTED);
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Argument(0) String file, @Patch.Argument(1) boolean rewrite,
                @Patch.Local("toolkitQueueBindingSource") QueueBindingSource.Scope previous) {
            QueueBindingSource.end(previous);
        }
    }

    @Patch(className="se.krka.kahlua.luaj.compiler.LuaCompiler", methodName="loadis", warmUp=true, strictMatch=true)
    public static class QueueBindingCompiling {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(value=0, readOnly=false) java.io.Reader reader,
                @Patch.Argument(1) String name, @Patch.Argument(2) se.krka.kahlua.vm.KahluaTable environment,
                @Patch.Local("toolkitQueueBindingCompiled") se.krka.kahlua.vm.LuaClosure compiled) throws java.io.IOException {
            QueueBindingHooks.Compilation result = QueueBindingHooks.compilerInput(reader, name, environment, QueueBindingHooks.SUPPORTED);
            reader = result.getReader();
            compiled = result.getClosure();
            return compiled != null;
        }
        @Patch.OnExit
        public static void exit(@Patch.Local("toolkitQueueBindingCompiled") se.krka.kahlua.vm.LuaClosure compiled,
                @Patch.Return(readOnly=false) se.krka.kahlua.vm.LuaClosure result) {
            if (compiled != null) result = compiled;
        }
    }

    @Patch(className="se.krka.kahlua.vm.Prototype", methodName="dump", warmUp=true, strictMatch=true)
    public static class QueueBindingDump {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This se.krka.kahlua.vm.Prototype prototype,
                @Patch.Argument(0) java.io.OutputStream output) throws java.io.IOException {
            return QueueBindingHooks.SUPPORTED && QueueBindingCompiler.dumpOriginal(prototype, output);
        }
    }

    @Patch(className="org.lwjglx.opengl.Display", methodName="swapBuffers", warmUp=true)
    public static class VideoPresented {
        @Patch.OnExit
        public static void exit() {
            if (Main.VIDEO_SUPPORTED) VideoRecording.presented();
        }
    }

    @Patch(className="zombie.network.packets.INetworkPacket", methodName="send", warmUp=true, strictMatch=true)
    public static class VehicleInventorySend {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(0) IConnection connection,
                @Patch.Argument(1) zombie.network.PacketTypes.PacketType type,
                @Patch.Argument(2) Object[] values,
                @Patch.Local("toolkitVehicleInventory") VehicleInventoryOrdering.Scope scope) {
            scope = VehicleInventoryOrdering.begin(connection, type, values, VehicleInventoryOrdering.SUPPORTED);
            return scope.coalesce;
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Local("toolkitVehicleInventory") VehicleInventoryOrdering.Scope scope,
                @Patch.Thrown Throwable failure) {
            VehicleInventoryOrdering.end(scope, failure);
        }
    }

    @Patch(className="zombie.core.raknet.UdpConnection", methodName="endPacket", warmUp=true, strictMatch=true)
    public static class VehicleInventoryChannel {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This UdpConnection connection, @Patch.Argument(0) int priority,
                @Patch.Argument(1) int reliability, @Patch.Argument(value=2, readOnly=false) byte ordering,
                @Patch.Local("toolkitWrittenInventory") VehicleInventoryOrdering.Scope scope) {
            scope = VehicleInventoryOrdering.written(connection, VehicleInventoryOrdering.SUPPORTED);
            ordering = VehicleInventoryOrdering.ordering(connection, reliability, ordering);
            return scope != null && scope.coalesce;
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Argument(0) int priority, @Patch.Argument(1) int reliability,
                @Patch.Argument(2) byte ordering,
                @Patch.Local("toolkitWrittenInventory") VehicleInventoryOrdering.Scope scope,
                @Patch.Thrown Throwable failure) {
            VehicleInventoryOrdering.end(scope, failure);
        }
    }

    @Patch(className="zombie.network.packets.vehicle.VehicleFullUpdatePacket", methodName="write", warmUp=true, strictMatch=true)
    public static class VehicleInventoryFullWrite {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) zombie.core.network.ByteBufferWriter writer) { VehicleInventoryOrdering.writing(true, null); }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Argument(0) zombie.core.network.ByteBufferWriter writer, @Patch.Thrown Throwable failure) { VehicleInventoryOrdering.writing(false, failure); }
    }

    @Patch(className="zombie.network.fields.vehicle.VehicleAuthorization", methodName="write", warmUp=true, strictMatch=true)
    public static class VehicleInventoryFullAuthorization {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) zombie.core.network.ByteBufferWriter writer) {
            VehicleInventoryOrdering.authorization(writer, false, null);
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Argument(0) zombie.core.network.ByteBufferWriter writer, @Patch.Thrown Throwable failure) {
            VehicleInventoryOrdering.authorization(writer, true, failure);
        }
    }

    @Patch(className="zombie.network.fields.vehicle.VehiclePassengers", methodName="write", warmUp=true, strictMatch=true)
    public static class VehicleInventoryFullTail {
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Argument(0) zombie.core.network.ByteBufferWriter writer, @Patch.Thrown Throwable failure) { VehicleInventoryOrdering.passengersWritten(failure); }
    }

    @Patch(className="zombie.core.raknet.RakNetPeerInterface", methodName="Send", warmUp=true, strictMatch=true)
    public static class VehicleInventoryTransport {
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.This zombie.core.raknet.RakNetPeerInterface peer,
                @Patch.Argument(0) java.nio.ByteBuffer bytes, @Patch.Argument(1) int priority,
                @Patch.Argument(2) int reliability, @Patch.Argument(3) byte ordering,
                @Patch.Argument(4) long guid, @Patch.Argument(5) boolean broadcast,
                @Patch.Return int result, @Patch.Thrown Throwable failure) {
            VehicleInventoryOrdering.sent(peer, bytes, guid, broadcast, result, failure);
        }
    }

    @Patch(className="zombie.vehicles.VehicleManager", methodName="sendVehicles", warmUp=true, strictMatch=true)
    public static class VehicleInventoryFullRetry {
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Argument(0) UdpConnection connection) { VehicleInventoryOrdering.retry(connection); }
    }

    @Patch(className="zombie.core.raknet.UdpEngine", methodName="removeConnection", warmUp=true, strictMatch=true)
    public static class VehicleInventoryDisconnect {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) long guid) { VehicleInventoryOrdering.disconnected(guid); }
    }

    @Patch(className="zombie.vehicles.VehicleManager", methodName="unregisterVehicle", warmUp=true, strictMatch=true)
    public static class VehicleInventoryDelete {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) zombie.vehicles.BaseVehicle car) { VehicleInventoryOrdering.deleted(car); }
    }

    // Fail closed after an engine update. Hash original class resources, not transformed bytecode.
    public static final boolean ZOMBIE_SUPPORTED = MainPolicy.zombieSupported();
    public static final boolean VEHICLE_OWNERSHIP_SUPPORTED = MainPolicy.vehicleOwnershipSupported();
    public static final boolean VEHICLE_SUPPORTED = MainPolicy.vehicleSupported();
    public static final boolean ANIMAL_SUPPORTED = MainPolicy.animalSupported();
    public static final boolean EQUIPMENT_SUPPORTED = MainPolicy.equipmentSupported();
    public static final boolean HUTCH_SUPPORTED = MainPolicy.hutchSupported();
    public static final boolean MEDICAL_BODY_DAMAGE_SUPPORTED = MainPolicy.medicalBodyDamageSupported();
    public static final boolean MEDICAL_VISUALS_SUPPORTED = MainPolicy.medicalVisualsSupported();
    public static final boolean MEDICAL_TIMED_ACTION_SUPPORTED = MainPolicy.medicalTimedActionSupported();
    public static final boolean MEDIA_SUPPORTED = MainPolicy.mediaSupported();
    public static final boolean BUILD_SUPPORTED = MainPolicy.buildSupported();

    public static final boolean CART_SUPPORTED = MainPolicy.cartSupported();

    public static final boolean CART_INJURY_SUPPORTED = MainPolicy.cartInjurySupported();

    public static final boolean CART_SYNC_SUPPORTED = MainPolicy.cartSyncSupported();

    public static final boolean CART_OBSERVER_SUPPORTED = MainPolicy.cartObserverSupported();

    public static final boolean CART_WHEEL_SUPPORTED = MainPolicy.cartWheelSupported();

    public static final boolean CART_TRANSITION_SUPPORTED = MainPolicy.cartTransitionSupported();

    public static final boolean COMPLETION_SUPPORTED = MainPolicy.completionSupported();

    @Patch(className="zombie.core.textures.VideoTexture", methodName="getOrCreate", strictMatch=true)
    public static class TVVideoPath {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(value=0, readOnly=false) String filename,
                @Patch.Argument(1) int width, @Patch.Argument(2) int height, @Patch.Argument(3) boolean async) {
            filename = TVVideoPaths.redirect(filename, TVVideoPaths.SUPPORTED);
        }
    }

    @Patch(className="zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton", methodName="process", warmUp=true, strictMatch=true)
    public static class DamnLibraryAnimationInput {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) zombie.core.skinnedmodel.model.jassimp.ImportedSkeletonParams params) {
            DamnLibraryAnimationBindings.prepare(params);
        }
    }

    public static void main(String[] args) throws ClassNotFoundException {
        MainSupport.startup();
    }

    @Patch(className="zombie.characters.CharacterTimedActions.LuaTimedActionNew", methodName="valid", warmUp=true, strictMatch=true)
    public static class RemoteActionValidity {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.characters.CharacterTimedActions.LuaTimedActionNew action,
                @Patch.Return(readOnly=false) boolean valid) {
            valid = ActionCompletion.restoreNativeCompletion(action, valid, Main.COMPLETION_SUPPORTED);
        }
    }

    @Patch(className="zombie.characters.CharacterTimedActions.LuaTimedActionNew", methodName="start", warmUp=true, strictMatch=true)
    public static class RemoteActionStarted {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.characters.CharacterTimedActions.LuaTimedActionNew action) {
            ActionCompletion.nativeStarted(action, Main.COMPLETION_SUPPORTED);
        }
    }

    @Patch(className="zombie.characters.CharacterTimedActions.LuaTimedActionNew", methodName="update", warmUp=true, strictMatch=true)
    public static class RemoteActionUpdate {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This zombie.characters.CharacterTimedActions.LuaTimedActionNew action) {
            return ActionCompletion.skipNativeUpdate(action, Main.COMPLETION_SUPPORTED);
        }
    }

    @Patch(className="zombie.characters.CharacterTimedActions.LuaTimedActionNew", methodName="perform", warmUp=true, strictMatch=true)
    public static class ActionPerformed {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.characters.CharacterTimedActions.LuaTimedActionNew action,
                @Patch.Local("toolkitCompletion") ActionCompletion.Scope scope) {
            scope = MainSupport.beginPerformed(action);
            if (scope == null && ActionCompletion.needsNativeWaitObservation(action, Main.COMPLETION_SUPPORTED))
                scope = ActionCompletion.observeOnly(action, "perform");
            ActionCompletion.captureNativePerform(action, scope);
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.This zombie.characters.CharacterTimedActions.LuaTimedActionNew action,
                @Patch.Local("toolkitCompletion") ActionCompletion.Scope scope, @Patch.Thrown Throwable failure) {
            try {
                MainSupport.performed(action, scope, failure);
            } finally {
                ActionCompletion.nativePerformed(action, scope, failure);
            }
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
            MainSupport.equipmentParsed(packet, reader, connection);
        }
    }

    @Patch(className="zombie.network.packets.EquipPacket", methodName="processClient", warmUp=true, strictMatch=true)
    public static class EquipmentEcho {
        public static EquipPacket incomplete;

        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This EquipPacket packet, @Patch.Argument(0) UdpConnection connection) {
            return MainSupport.equipmentEcho(packet);
        }
    }

    @Patch(className="zombie.characters.NetworkPlayerAI", methodName="parse", warmUp=true, strictMatch=true)
    public static class AnimalTrailerLocation {
        public static boolean disabled;

        @Patch.OnEnter
        public static void enter(@Patch.This NetworkPlayerAI ai, @Patch.Argument(0) AnimalPacket packet) {
            MainSupport.animalTrailerLocation(ai, packet);
        }
    }

    @Patch(className="zombie.pathfind.PathFindBehavior2", methodName="update", warmUp=true)
    public static class CartPathResult {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.pathfind.PathFindBehavior2 path) {
            MainSupport.beginCartPath(path);
        }
        @Patch.OnExit
        public static void exit(@Patch.This zombie.pathfind.PathFindBehavior2 path,
                @Patch.Return(readOnly=false) zombie.pathfind.PathFindBehavior2.BehaviorResult result) {
            result = MainSupport.cartPathResult(path, result);
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
                var impact = MainSupport.cartMovement(player, x, y);
                x=impact.x; y=impact.y;
            }
        }
    }

    @Patch(className="zombie.characters.IsoGameCharacter", methodName="calcRunSpeedModByBag", warmUp=true, strictMatch=true)
    public static class CartBagSpeed {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.characters.IsoGameCharacter character,
                @Patch.Argument(0) zombie.inventory.types.InventoryContainer bag,
                @Patch.Return(readOnly=false) float result) {
            result = CartSpeedParity.bagPenalty(character, bag, result);
        }
    }

    @Patch(className="zombie.characters.IsoGameCharacter", methodName="postUpdateAnimating", warmUp=true)
    public static class CartHeading {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.characters.IsoGameCharacter character) {
            MainSupport.cartHeading(character);
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
            MainSupport.bindCartSlot(slot, source);
        }
    }

    @Patch(className="zombie.core.skinnedmodel.model.ModelSlotRenderData", methodName="init", strictMatch=true)
    public static class VehicleTransitionSlot {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.core.skinnedmodel.model.ModelSlotRenderData slot,
            @Patch.Argument(0) zombie.core.skinnedmodel.ModelManager.ModelSlot source) {
            VehicleTransitionRender.capture(slot, source, VehicleTransitionRender.SUPPORTED);
        }
    }

    @Patch(className="zombie.core.skinnedmodel.model.ModelSlotRenderData", methodName="postRender")
    public static class CartObserverRelease {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.core.skinnedmodel.model.ModelSlotRenderData slot) {
            MainSupport.releaseCartSlot(slot);
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
            MainSupport.shoppingWorldAtlas(params, item, script);
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
            MainSupport.worldScale(renderer, item, script);
        }
    }

    // Alpha-zero ground models still write depth, and the outline uses a separate sprite/atlas pass.
    @Patch(className="zombie.core.skinnedmodel.model.ItemModelRenderer", methodName="renderMain", warmUp=true)
    public static class WoodenWorldModel {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This zombie.core.skinnedmodel.model.ItemModelRenderer renderer,
            @Patch.Argument(0) zombie.inventory.InventoryItem item,
            @Patch.Local("toolkitHiddenWorldCart") boolean hidden) {
            hidden = MainSupport.hideWorldModel(renderer, item);
            return hidden;
        }
        @Patch.OnExit
        public static void exit(@Patch.This zombie.core.skinnedmodel.model.ItemModelRenderer renderer,
            @Patch.Argument(0) zombie.inventory.InventoryItem item,
            @Patch.Local("toolkitHiddenWorldCart") boolean hidden,
            @Patch.Return(readOnly=false) zombie.core.skinnedmodel.model.ItemModelRenderer.RenderStatus result) {
            if(hidden) result=zombie.core.skinnedmodel.model.ItemModelRenderer.RenderStatus.NoModel;
            MainSupport.worldModelReady(renderer, item, result);
        }
    }

    @Patch(className="zombie.core.skinnedmodel.model.ItemModelRenderer", methodName="reset")
    public static class WoodenWorldWheelReset {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.core.skinnedmodel.model.ItemModelRenderer renderer) {
            MainSupport.resetWorldModel(renderer);
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
            return MainSupport.hideWorldOutline(object);
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
            MainSupport.mediaRestart(data);
        }
    }

    @Patch(className="zombie.characters.NetworkZombieAI", methodName="parse", warmUp=true)
    public static class ZombieSpeedDecode {
        @Patch.OnExit
        public static void exit(@Patch.This NetworkZombieAI ai, @Patch.Argument(0) ZombiePacket packet) {
            MainSupport.zombieSpeedDecode(ai, packet);
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
            MainSupport.vehicleRecovery(interpolation);
        }
    }
}
