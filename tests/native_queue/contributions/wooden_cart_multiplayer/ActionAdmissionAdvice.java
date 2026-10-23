package net.alexredby.cartlab;
import me.zed_0xff.zombie_buddy.Patch;
import net.alexredby.cartlab.ActionAdmission.ActionAdmissionParsed;
import net.alexredby.cartlab.ActionAdmission.ActionAdmissionParseScope;
import net.alexredby.cartlab.ActionAdmission.ActionAdmissionScope;
import net.alexredby.cartlab.ActionAdmission.ActionAdmissionRecord;
public final class ActionAdmissionAdvice {
@Patch(className="zombie.core.NetTimedAction",methodName="parse",warmUp=false)
    public static class ActionAdmissionTimedParse {
        @Patch.OnEnter public static void enter(@Patch.This zombie.core.NetTimedAction packet,@Patch.Argument(0) zombie.core.network.ByteBufferReader reader,@Patch.Argument(1) zombie.network.IConnection connection,@Patch.Local("admissionParse") ActionAdmissionParseScope scope){scope=ActionAdmission.actionAdmissionParseEnter(packet,reader,connection,zombie.network.PacketTypes.PacketType.NetTimedAction.getId());}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) zombie.core.network.ByteBufferReader reader,@Patch.Argument(1) zombie.network.IConnection connection,@Patch.Local("admissionParse") ActionAdmissionParseScope scope,@Patch.Thrown Throwable failure){ActionAdmission.actionAdmissionParseExit(scope,failure);}
    }
@Patch(className="zombie.network.packets.GeneralActionPacket",methodName="parse",warmUp=false)
    public static class ActionAdmissionGeneralParse {
        @Patch.OnEnter public static void enter(@Patch.This zombie.network.packets.GeneralActionPacket packet,@Patch.Argument(0) zombie.core.network.ByteBufferReader reader,@Patch.Argument(1) zombie.network.IConnection connection,@Patch.Local("admissionParse") ActionAdmissionParseScope scope){scope=ActionAdmission.actionAdmissionParseEnter(packet,reader,connection,zombie.network.PacketTypes.PacketType.GeneralAction.getId());}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) zombie.core.network.ByteBufferReader reader,@Patch.Argument(1) zombie.network.IConnection connection,@Patch.Local("admissionParse") ActionAdmissionParseScope scope,@Patch.Thrown Throwable failure){ActionAdmission.actionAdmissionParseExit(scope,failure);}
    }
@Patch(className="zombie.network.packets.NetTimedActionPacket",methodName="processServer",warmUp=false)
    public static class ActionAdmissionTimedProcess {
        @Patch.OnEnter public static void enter(@Patch.This zombie.network.packets.NetTimedActionPacket packet,@Patch.Argument(0) zombie.network.PacketTypes.PacketType type,@Patch.Argument(1) zombie.core.raknet.UdpConnection connection,@Patch.Local("admissionProcess") ActionAdmissionScope scope){scope=ActionAdmission.actionAdmissionProcessEnter(packet,type,connection);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) zombie.network.PacketTypes.PacketType type,@Patch.Argument(1) zombie.core.raknet.UdpConnection connection,@Patch.Local("admissionProcess") ActionAdmissionScope scope,@Patch.Thrown Throwable failure){ActionAdmission.actionAdmissionProcessExit(scope,failure);}
    }
@Patch(className="zombie.network.packets.GeneralActionPacket",methodName="processServer",warmUp=false)
    public static class ActionAdmissionGeneralProcess {
        @Patch.OnEnter public static void enter(@Patch.This zombie.network.packets.GeneralActionPacket packet,@Patch.Argument(0) zombie.network.PacketTypes.PacketType type,@Patch.Argument(1) zombie.core.raknet.UdpConnection connection,@Patch.Local("admissionProcess") ActionAdmissionScope scope){scope=ActionAdmission.actionAdmissionProcessEnter(packet,type,connection);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) zombie.network.PacketTypes.PacketType type,@Patch.Argument(1) zombie.core.raknet.UdpConnection connection,@Patch.Local("admissionProcess") ActionAdmissionScope scope,@Patch.Thrown Throwable failure){ActionAdmission.actionAdmissionProcessExit(scope,failure);ActionAdmission.actionAdmissionSweep("native-remove");}
    }
@Patch(className="zombie.core.ActionManager",methodName="start",warmUp=false)
    public static class ActionAdmissionStarted {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) Object action,@Patch.Local("admissionStart") ActionAdmissionRecord record){record=ActionAdmission.actionAdmissionStartEnter(action);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) Object action,@Patch.Local("admissionStart") ActionAdmissionRecord record,@Patch.Thrown Throwable failure){ActionAdmission.actionAdmissionStartExit(record,failure);}
    }
@Patch(className="zombie.core.ActionManager",methodName="update",warmUp=false)
    public static class ActionAdmissionUpdated {
        @Patch.OnEnter public static void enter(@Patch.Local("admissionPins") java.util.ArrayList<Object> pins){pins=ActionAdmission.actionAdmissionPin();}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Local("admissionPins") java.util.ArrayList<Object> pins){ActionAdmission.actionAdmissionSweepPinned(pins,"native-absent");}
    }
@Patch(className="zombie.core.ActionManager",methodName="remove",warmUp=false)
    public static class ActionAdmissionRemoved {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) zombie.network.fields.character.PlayerID player,@Patch.Argument(1) byte id,@Patch.Argument(2) boolean canceled,@Patch.Local("admissionPins") java.util.ArrayList<Object> pins){pins=ActionAdmission.actionAdmissionPin();}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) zombie.network.fields.character.PlayerID player,@Patch.Argument(1) byte id,@Patch.Argument(2) boolean canceled,@Patch.Local("admissionPins") java.util.ArrayList<Object> pins){ActionAdmission.actionAdmissionSweepPinned(pins,"native-remove");}
    }
}
