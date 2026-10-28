package net.alexredby.cartlab;
import me.zed_0xff.zombie_buddy.Patch;
import net.alexredby.cartlab.ObserverAssociation.ObserverSource;
import net.alexredby.cartlab.ObserverAssociation.ObserverSend;
import net.alexredby.cartlab.ObserverAssociation.ObserverParse;
import net.alexredby.cartlab.ObserverAssociation.ObserverProcess;
import net.alexredby.cartlab.ObserverAssociation.ObserverApply;
import net.alexredby.cartlab.ObserverAssociation.ObserverProxy;
import net.alexredby.cartlab.ObserverAssociation.ObserverQueue;
public final class ObserverAssociationAdvice {
@Patch(className="zombie.characters.CharacterTimedActions.LuaTimedActionNew",methodName="start",warmUp=false)
    public static class ObserverAssociationBegin {
        @Patch.OnEnter public static void enter(@Patch.This zombie.characters.CharacterTimedActions.LuaTimedActionNew action,@Patch.Local("observerSource") ObserverSource source){source=ObserverAssociation.observerBegin(action);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.This zombie.characters.CharacterTimedActions.LuaTimedActionNew action,@Patch.Local("observerSource") ObserverSource source,@Patch.Thrown Throwable failure){ObserverAssociation.observerBeginExit(source,failure);}
    }
@Patch(className="zombie.network.packets.actions.StatePacket",methodName="write",warmUp=false)
    public static class ObserverAssociationWrite {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) zombie.core.network.ByteBufferWriter writer,@Patch.Local("observerBodyBegin") int begin){begin=writer.bb.position();}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.This zombie.network.packets.actions.StatePacket packet,@Patch.Argument(0) zombie.core.network.ByteBufferWriter writer,@Patch.Local("observerBodyBegin") int begin,@Patch.Thrown Throwable failure){ObserverAssociation.observerWritten(packet,writer,begin,failure);}
    }
@Patch(className="zombie.core.raknet.UdpConnection",methodName="endPacket",warmUp=false)
    public static class ObserverAssociationSubmit {
        @Patch.OnEnter public static void enter(@Patch.This zombie.core.raknet.UdpConnection connection,@Patch.Argument(0) int priority,@Patch.Argument(1) int reliability,@Patch.Argument(2) byte channel,@Patch.Local("observerSend") ObserverSend send){send=ObserverAssociation.observerSendEnter(connection);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) int priority,@Patch.Argument(1) int reliability,@Patch.Argument(2) byte channel,@Patch.Local("observerSend") ObserverSend send,@Patch.Thrown Throwable failure){ObserverAssociation.observerSendExit(send,false,failure);}
    }
@Patch(className="zombie.core.raknet.UdpConnection",methodName="cancelPacket",warmUp=false)
    public static class ObserverAssociationCancel {
        @Patch.OnEnter public static void enter(@Patch.This zombie.core.raknet.UdpConnection connection,@Patch.Local("observerSend") ObserverSend send){send=ObserverAssociation.observerSendEnter(connection);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Local("observerSend") ObserverSend send,@Patch.Thrown Throwable failure){ObserverAssociation.observerSendExit(send,true,failure);}
    }
@Patch(className="zombie.network.packets.actions.StatePacket",methodName="parse",warmUp=false)
    public static class ObserverAssociationParse {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) zombie.core.network.ByteBufferReader reader,@Patch.Argument(1) zombie.network.IConnection connection,@Patch.Local("observerParse") ObserverParse scope){scope=ObserverAssociation.observerParseEnter(reader,connection);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.This zombie.network.packets.actions.StatePacket packet,@Patch.Argument(0) zombie.core.network.ByteBufferReader reader,@Patch.Argument(1) zombie.network.IConnection connection,@Patch.Local("observerParse") ObserverParse scope,@Patch.Thrown Throwable failure){ObserverAssociation.observerParsed(packet,reader,scope,failure);}
    }
@Patch(className="zombie.network.packets.actions.StatePacket",methodName="processServer",warmUp=false)
    public static class ObserverAssociationServer {
        @Patch.OnEnter public static void enter(@Patch.This zombie.network.packets.actions.StatePacket packet,@Patch.Argument(0) zombie.network.PacketTypes.PacketType type,@Patch.Argument(1) zombie.core.raknet.UdpConnection connection,@Patch.Local("observerProcess") ObserverProcess scope){scope=ObserverAssociation.observerProcessEnter(packet,connection,true);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) zombie.network.PacketTypes.PacketType type,@Patch.Argument(1) zombie.core.raknet.UdpConnection connection,@Patch.Local("observerProcess") ObserverProcess scope,@Patch.Thrown Throwable failure){ObserverAssociation.observerProcessExit(scope,failure);}
    }
@Patch(className="zombie.network.packets.actions.StatePacket",methodName="processClient",warmUp=false)
    public static class ObserverAssociationClient {
        @Patch.OnEnter public static void enter(@Patch.This zombie.network.packets.actions.StatePacket packet,@Patch.Argument(0) zombie.core.raknet.UdpConnection connection,@Patch.Local("observerProcess") ObserverProcess scope){scope=ObserverAssociation.observerProcessEnter(packet,connection,false);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) zombie.core.raknet.UdpConnection connection,@Patch.Local("observerProcess") ObserverProcess scope,@Patch.Thrown Throwable failure){ObserverAssociation.observerProcessExit(scope,failure);}
    }
@Patch(className="zombie.network.packets.actions.StatePacket",methodName="apply",warmUp=false)
    public static class ObserverAssociationApply {
        @Patch.OnEnter public static void enter(@Patch.This zombie.network.packets.actions.StatePacket packet,@Patch.Local("observerApply") ObserverApply scope){scope=ObserverAssociation.observerApplyEnter(packet);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Local("observerApply") ObserverApply scope,@Patch.Thrown Throwable failure){ObserverAssociation.observerApplyExit(scope,failure);}
    }
@Patch(className="zombie.characters.NetworkCharacterAI",methodName="stopAction",warmUp=false)
    public static class ObserverAssociationStop {
        @Patch.OnEnter public static void enter(@Patch.This zombie.characters.NetworkCharacterAI ai,@Patch.Local("observerProxy") ObserverProxy proxy){proxy=ObserverAssociation.observerStopEnter(ai);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Local("observerProxy") ObserverProxy proxy,@Patch.Thrown Throwable failure){ObserverAssociation.observerStopExit(proxy,failure);}
    }
@Patch(className="zombie.characters.NetworkState",methodName="updateState",warmUp=false)
    public static class ObserverAssociationPending {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) java.util.LinkedList<?> queue,@Patch.Argument(1) zombie.network.packets.actions.StatePacket packet,@Patch.Local("observerQueue") ObserverQueue before){before=ObserverAssociation.observerQueueBefore(queue);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) java.util.LinkedList<?> queue,@Patch.Argument(1) zombie.network.packets.actions.StatePacket packet,@Patch.Local("observerQueue") ObserverQueue before){ObserverAssociation.observerQueueAfter(before,queue,packet==null?"pending-cleared":"pending-replaced");}
    }
@Patch(className="zombie.characters.NetworkState",methodName="tryCancelPendingEnterPair",warmUp=false)
    public static class ObserverAssociationPendingCancel {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) java.util.LinkedList<?> queue,@Patch.Argument(1) zombie.network.packets.actions.StatePacket packet,@Patch.Local("observerQueue") ObserverQueue before){before=ObserverAssociation.observerQueueBefore(queue);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) java.util.LinkedList<?> queue,@Patch.Argument(1) zombie.network.packets.actions.StatePacket packet,@Patch.Local("observerQueue") ObserverQueue before){ObserverAssociation.observerQueueAfter(before,queue,"pending-canceled");}
    }
@Patch(className="zombie.characters.NetworkState",methodName="reset",warmUp=false)
    public static class ObserverAssociationReset {
        @Patch.OnEnter public static void enter(@Patch.This zombie.characters.NetworkState state,@Patch.Local("observerReset") java.util.ArrayList<ObserverQueue> before){before=ObserverAssociation.observerResetBefore(state);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Local("observerReset") java.util.ArrayList<ObserverQueue> before,@Patch.Thrown Throwable failure){ObserverAssociation.observerResetAfter(before,failure);}
    }
}
