package net.alexredby.vehicleposefixture;

import java.nio.file.Path;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;

/** Read-only measurements, called by Lua on the game thread in an owned test cache. */
public final class Main {
    public static volatile String label;
    public static long lastRender;
    @LuaMethod(name="vehiclePoseLabel", global=true)
    public static void label(String value) { label=value; }

    @me.zed_0xff.zombie_buddy.Patch(className="zombie.core.skinnedmodel.model.ModelSlotRenderData", methodName="render", strictMatch=true)
    public static class RenderProbe {
        @me.zed_0xff.zombie_buddy.Patch.OnEnter
        public static void enter(@me.zed_0xff.zombie_buddy.Patch.This zombie.core.skinnedmodel.model.ModelSlotRenderData slot) {
            String current=label;
            long now=System.currentTimeMillis();
            if (current==null || !(slot.character instanceof IsoPlayer p) || !p.isLocalPlayer() || now-lastRender<25) return;
            lastRender=now;
            StepPoseProbe.render(slot,current,now);
            System.out.println("[VEHICLE_POSE] RENDER " + current + " ms=" + now + " x=" + slot.x + " y=" + slot.y
                + " z=" + slot.z + " inVehicle=" + slot.inVehicle + " local=" + slot.inVehicleX + "," + slot.inVehicleY + "," + slot.inVehicleZ);
        }
    }

    @LuaMethod(name="vehicleStartupContents", global=true)
    public static String vehicleContents(zombie.vehicles.BaseVehicle vehicle) { return StartupNetworkProbe.contents(vehicle); }

    @LuaMethod(name="vehiclePoseBoundary", global=true)
    public static String boundary(IsoPlayer player, zombie.vehicles.BaseVehicle vehicle, int seat, boolean entering) {
        var animation=player.getAnimationPlayer();
        var offset=vehicle.getPassengerPosition(seat,entering?"outside":"inside").getOffset();
        float origin=offset.y+vehicle.getScript().getModel().getOffset().y;
        var out=new StringBuilder();
        for (String side:new String[]{"L","R"}) {
            int index=animation.getSkinningBoneIndex("Bip01_"+side+"_Foot",-1);
            out.append(side).append("Y=").append(origin+1.5f*animation.getModelTransformAt(index).m13).append(' ');
        }
        return out.toString();
    }

    @LuaMethod(name="vehiclePoseCleanView", global=true)
    public static String cleanView() {
        int visible=0;
        for (var ui:zombie.ui.UIManager.getUI()) if (ui.isVisible()) visible++;
        return "visible="+visible+" global="+zombie.ui.UIManager.visibleAllUi
            +" names="+zombie.network.ServerOptions.getInstance().displayUserName.getValue();
    }

    @LuaMethod(name="vehiclePoseCheck", global=true)
    public static String check(IsoPlayer player, String expectedClip) {
        String cache = System.getenv("PZ_POSE_TEST_CACHE");
        if (cache == null || !Path.of(cache).normalize().equals(
                Path.of(ZomboidFileSystem.instance.getCacheDir()).toAbsolutePath().normalize()))
            throw new IllegalStateException("Disposable pose cache required");
        if (player == null || player.getVehicle() == null || !player.hasAnimationPlayer())
            throw new IllegalStateException("No native vehicle animation player");
        var animation = player.getAnimationPlayer();
        var tracks = animation.getMultiTrack();
        int seated = 0;
        float weight = 0;
        for (int i = 0; i < tracks.getTrackCount(); i++) {
            var track = tracks.getTrackAt(i);
            if (track.getBlendWeight() < .01f) continue;
            String name = track.getName();
            if (!expectedClip.equals(name))
                throw new IllegalStateException("Unexpected transition track: " + name + " weight=" + track.getBlendWeight());
            if (!track.isLooping()) {
                if (!"Bob_IdleDriving".equals(expectedClip) && track.reverse)
                    throw new IllegalStateException("Transition played in the wrong direction");
                if (Math.abs(track.getDuration() / track.getSpeedDelta() - .625f) > .00001f)
                    throw new IllegalStateException("Changed native transition duration");
                seated++; weight += track.getBlendWeight();
            }
        }
        if (seated != 1 || weight < .99f)
            throw new IllegalStateException("No fully weighted one-shot transition: " + seated + "/" + weight);
        int head = animation.getSkinningBoneIndex("Bip01_Head", -1);
        if (head < 0 || head >= animation.getModelTransformsCount())
            throw new IllegalStateException("No native head pose");
        return "seated=" + seated + " weight=" + weight + " headY=" + animation.getModelTransformAt(head).m13;
    }
    @LuaMethod(name="vehiclePoseSample", global=true)
    public static String sample(IsoPlayer player) {
        String cache = System.getenv("PZ_POSE_TEST_CACHE");
        if (cache == null || !Path.of(cache).normalize().equals(
                Path.of(ZomboidFileSystem.instance.getCacheDir()).toAbsolutePath().normalize()))
            throw new IllegalStateException("Disposable pose cache required");
        var result = new StringBuilder("ms=").append(System.currentTimeMillis())
            .append(" x=").append(player.getX()).append(" y=").append(player.getY())
            .append(" z=").append(player.getZ()).append(" inVehicle=").append(player.getVehicle()!=null);
        if (!player.hasAnimationPlayer()) return result.append(" animation=missing").toString();
        var animation = player.getAnimationPlayer();
        for (String bone : new String[]{"Bip01", "Bip01_Head", "Bip01_Pelvis", "Bip01_L_Foot", "Bip01_R_Foot"}) {
            int index = animation.getSkinningBoneIndex(bone, -1);
            if (index >= 0 && index < animation.getModelTransformsCount()) {
                var m = animation.getModelTransformAt(index);
                result.append(" ").append(bone).append("=").append(m.m03).append(",").append(m.m13).append(",").append(m.m23);
            }
        }
        var tracks = animation.getMultiTrack();
        for (int i=0; i<tracks.getTrackCount(); i++) {
            var track=tracks.getTrackAt(i);
            if (track.getBlendWeight() < .01f) continue;
            result.append(" track=").append(track.getName()).append(",").append(track.getBlendWeight())
                .append(",").append(track.getCurrentTimeFraction()).append(",").append(track.isLooping());
        }
        return result.toString();
    }

}
