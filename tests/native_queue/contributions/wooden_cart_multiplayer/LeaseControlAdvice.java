package net.alexredby.cartlab;
import me.zed_0xff.zombie_buddy.Patch;
import net.alexredby.cartlab.LeaseControl.*;
public final class LeaseControlAdvice {
    @Patch(className="zombie.core.raknet.UdpEngine",methodName="decode",warmUp=false)
    public static class LeaseControlDecode {
        @Patch.OnEnter public static void enter(@Patch.This zombie.core.raknet.UdpEngine engine,@Patch.Argument(0) zombie.core.network.ByteBufferReader reader,@Patch.Local("leaseDecode") LeaseDecodeScope scope){scope=LeaseControl.leaseControlDecodeEnter(engine,reader);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) zombie.core.network.ByteBufferReader reader,@Patch.Local("leaseDecode") LeaseDecodeScope scope){LeaseControl.leaseControlDecodeExit(scope);}
    }
    @Patch(className="zombie.network.ZomboidNetData",methodName="read",warmUp=true)
    public static class LeaseControlRead {
        @Patch.OnEnter public static void enter(@Patch.This zombie.network.ZomboidNetData data,@Patch.Argument(0) short type,@Patch.Argument(1) zombie.core.network.ByteBufferReader reader,@Patch.Argument(2) zombie.core.raknet.UdpConnection connection,@Patch.Local("leaseIngress") LeaseCommandIngress ingress){ingress=LeaseControl.leaseControlReadEnter(data,type,reader,connection);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.This zombie.network.ZomboidNetData data,@Patch.Argument(0) short type,@Patch.Argument(1) zombie.core.network.ByteBufferReader reader,@Patch.Argument(2) zombie.core.raknet.UdpConnection connection,@Patch.Local("leaseIngress") LeaseCommandIngress ingress,@Patch.Thrown Throwable failure){LeaseControl.leaseControlReadExit(data,ingress,failure);}
    }
    @Patch(className="zombie.network.GameClient",methodName="mainLoopHandlePacketInternal",warmUp=false)
    public static class LeaseControlDispatch {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) zombie.network.ZomboidNetData data,@Patch.Local("leaseDispatch") LeaseDispatchScope scope){scope=LeaseControl.leaseControlDispatchEnter(data);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) zombie.network.ZomboidNetData data,@Patch.Local("leaseDispatch") LeaseDispatchScope scope){LeaseControl.leaseControlDispatchExit(scope);}
    }
    @Patch(className="zombie.network.GameClient",methodName="receiveClientCommand",warmUp=false)
    public static class LeaseControlClientCommand {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) zombie.core.network.ByteBufferReader reader,@Patch.Argument(1) short type,@Patch.Local("leaseCallback") LeaseCallbackScope scope){scope=LeaseControl.leaseControlClientEnter(reader,type);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) zombie.core.network.ByteBufferReader reader,@Patch.Argument(1) short type,@Patch.Local("leaseCallback") LeaseCallbackScope scope){LeaseControl.leaseControlCallbackExit(scope);}
    }
    @Patch(className="zombie.network.GameServer",methodName="receiveClientCommand",warmUp=false)
    public static class LeaseControlServerCommand {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) zombie.core.network.ByteBufferReader reader,@Patch.Argument(1) zombie.core.raknet.UdpConnection connection,@Patch.Argument(2) short type,@Patch.Local("leaseCallback") LeaseCallbackScope scope){scope=LeaseControl.leaseControlServerEnter(reader,connection,type);}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) zombie.core.network.ByteBufferReader reader,@Patch.Argument(1) zombie.core.raknet.UdpConnection connection,@Patch.Argument(2) short type,@Patch.Local("leaseCallback") LeaseCallbackScope scope){LeaseControl.leaseControlCallbackExit(scope);}
    }
}
