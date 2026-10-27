package net.alexredby.cartlab;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.IsoPlayer;
import net.alexredby.cartlab.NativeTime.*;

/** Only writable native advice slots remain Java. */
public final class NativeTimeAdvice {
    @Patch(className="zombie.network.packets.character.PlayerPacket",methodName="set",warmUp=true)
    public static class NativeTimeSource {
        @Patch.OnEnter public static void enter(@Patch.This zombie.network.packets.character.PlayerPacket packet,@Patch.Argument(0) IsoPlayer owner,@Patch.Local("nativeSource") NativeSource source){source=NativeTime.nativeTimeSourceEnter(packet,owner);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.This zombie.network.packets.character.PlayerPacket packet,@Patch.Argument(0) IsoPlayer owner,@Patch.Local("nativeSource") NativeSource source,@Patch.Thrown Throwable failure){NativeTime.nativeTimeSourceExit(packet,owner,source,failure);}
    }
    @Patch(className="zombie.network.packets.character.PlayerPacket",methodName="write",warmUp=true)
    public static class NativeTimeWrite {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) zombie.core.network.ByteBufferWriter writer,@Patch.Local("nativeBegin") int begin){begin=writer.bb.position();}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.This zombie.network.packets.character.PlayerPacket packet,@Patch.Argument(0) zombie.core.network.ByteBufferWriter writer,@Patch.Local("nativeBegin") int begin,@Patch.Thrown Throwable failure){NativeTime.nativeTimeWrite(packet,writer,begin,failure);}
    }
    @Patch(className="zombie.core.raknet.UdpConnection",methodName="endPacket",warmUp=true)
    public static class NativeTimeEnd {
        @Patch.OnEnter public static void enter(@Patch.This zombie.core.raknet.UdpConnection connection,@Patch.Argument(0) int priority,@Patch.Argument(1) int reliability,@Patch.Argument(2) byte channel,@Patch.Local("nativeActive") NativeActiveSend active){active=NativeTime.nativeTimeFinishEnter(connection);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.This zombie.core.raknet.UdpConnection connection,@Patch.Argument(0) int priority,@Patch.Argument(1) int reliability,@Patch.Argument(2) byte channel,@Patch.Local("nativeActive") NativeActiveSend active,@Patch.Thrown Throwable failure){NativeTime.nativeTimeFinish(connection,active,false,failure);}
    }
    @Patch(className="zombie.core.raknet.UdpConnection",methodName="cancelPacket",warmUp=true)
    public static class NativeTimeCancel {
        @Patch.OnEnter public static void enter(@Patch.This zombie.core.raknet.UdpConnection connection,@Patch.Local("nativeActive") NativeActiveSend active){active=NativeTime.nativeTimeFinishEnter(connection);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.This zombie.core.raknet.UdpConnection connection,@Patch.Local("nativeActive") NativeActiveSend active,@Patch.Thrown Throwable failure){NativeTime.nativeTimeFinish(connection,active,true,failure);}
    }
    @Patch(className="zombie.network.ZomboidNetData",methodName="read",warmUp=true)
    public static class NativeTimeIngressRead {
        @Patch.OnEnter public static void enter(@Patch.Argument(1) zombie.core.network.ByteBufferReader input,@Patch.Local("nativeBegin") int begin,@Patch.Local("nativeMono") long mono){begin=input.position();mono=System.nanoTime();}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.This zombie.network.ZomboidNetData data,@Patch.Argument(0) short type,@Patch.Argument(1) zombie.core.network.ByteBufferReader input,@Patch.Argument(2) zombie.core.raknet.UdpConnection connection,@Patch.Local("nativeBegin") int begin,@Patch.Local("nativeMono") long mono,@Patch.Thrown Throwable failure){NativeTime.nativeTimeIngressRead(data,type,input,connection,begin,input.position(),mono,failure);}
    }
    @Patch(className="zombie.network.packets.character.PlayerPacket",methodName="parse",warmUp=true)
    public static class NativeTimeParse {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) zombie.core.network.ByteBufferReader reader,@Patch.Local("nativeBegin") int begin){begin=reader.position();}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.This zombie.network.packets.character.PlayerPacket packet,@Patch.Argument(0) zombie.core.network.ByteBufferReader reader,@Patch.Argument(1) zombie.network.IConnection connection,@Patch.Local("nativeBegin") int begin,@Patch.Thrown Throwable failure){NativeTime.nativeTimeParse(packet,reader,connection,begin,failure);}
    }
    @Patch(className="zombie.network.packets.character.PlayerPacket",methodName="processServer",warmUp=true)
    public static class NativeTimeServerScope {
        @Patch.OnEnter public static void enter(@Patch.This zombie.network.packets.character.PlayerPacket packet,@Patch.Argument(0) zombie.network.PacketTypes.PacketType type,@Patch.Argument(1) zombie.core.raknet.UdpConnection connection,@Patch.Local("nativeScope") NativeServerScope scope){scope=NativeTime.nativeTimeServerEnter(packet,type,connection);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) zombie.network.PacketTypes.PacketType type,@Patch.Argument(1) zombie.core.raknet.UdpConnection connection,@Patch.Local("nativeScope") NativeServerScope scope){NativeTime.nativeTimeServerExit(scope);}
    }
    @Patch(className="zombie.characters.NetworkPlayerAI",methodName="parse",warmUp=true)
    public static class NativeTimeCopyScope {
        @Patch.OnEnter public static void enter(@Patch.This zombie.characters.NetworkPlayerAI ai,@Patch.Argument(0) zombie.network.packets.character.PlayerPacket packet,@Patch.Local("nativeScope") NativeCopyScope scope){scope=NativeTime.nativeTimeCopyEnter(ai,packet);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) zombie.network.packets.character.PlayerPacket packet,@Patch.Local("nativeScope") NativeCopyScope scope){NativeTime.nativeTimeCopyExit(scope);}
    }
}
