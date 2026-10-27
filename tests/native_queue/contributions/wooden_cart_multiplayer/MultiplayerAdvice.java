package net.alexredby.cartlab;
import me.zed_0xff.zombie_buddy.Patch;
/** Writable JVM slots only. */
public final class MultiplayerAdvice {
    @Patch(className="zombie.network.packets.VariableSyncPacket", methodName="write", warmUp=true)
    public static class PoseTraffic {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) zombie.core.network.ByteBufferWriter writer,
                @Patch.Local("position") int position) {
            position=writer.bb.position();
        }
        @Patch.OnExit
        public static void exit(@Patch.This zombie.network.packets.VariableSyncPacket packet,
                @Patch.Argument(0) zombie.core.network.ByteBufferWriter writer,
                @Patch.Local("position") int position) {
            Multiplayer.recordPoseTraffic(packet.key,writer.bb.position()-position);
            Multiplayer.timelinePacket(packet,"variable-write",writer.bb.position()-position);
        }
    }
    @Patch(className="zombie.GameTime",methodName="syncServerTime",warmUp=true)
    public static class TimelineTimeSync {
        @Patch.OnEnter
        public static void enter(@Patch.Local("before") long before,@Patch.Local("readyBefore") boolean readyBefore) {
            before=Multiplayer.timelineAppliedOffset();readyBefore=zombie.GameTime.getServerTimeShiftIsSet();
        }
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.Argument(0) long sent,@Patch.Argument(1) long server,@Patch.Argument(2) long processed,
            @Patch.Local("before") long before,@Patch.Local("readyBefore") boolean readyBefore) {
            Multiplayer.timelineClock(sent,server,processed,before,readyBefore);
        }
    }
}
