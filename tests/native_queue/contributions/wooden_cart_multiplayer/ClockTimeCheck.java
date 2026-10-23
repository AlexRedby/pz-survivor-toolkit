public final class ClockTimeCheck {
    private static void require(boolean value,String message){if(!value)throw new AssertionError(message);}
    public static void main(String[] args)throws Exception {
        var schedule=new net.alexredby.cartlab.Main.TimelineClockSchedule();
        require(schedule.due(100,1,2,42,0),"First request");
        for(int i=0;i<1000;i++)require(!schedule.due(101+i,1,2,42,i/1000.0),"Tick spam");
        require(schedule.due(2_000_000_100L,1,2,42,2000),"Minimum spacing");
        require(!schedule.due(4_000_000_100L,3,2,42,4000) && schedule.closed(),"Connection fence");
        require(!schedule.due(6_000_000_100L,1,2,42,6000),"No old epoch revival");
        for(int changed=0;changed<4;changed++) {
            var s=new net.alexredby.cartlab.Main.TimelineClockSchedule();require(s.due(100,1,2,42,0),"Initial");
            require(!s.due(changed==3?99:2_000_000_100L,1,changed==0?3:2,changed==1?43:42,changed==2?-1:2000),"Actor/cart/time fence");
            require(s.closed(),"Terminal fence");
        }
        var delayed=new net.alexredby.cartlab.Main.TimelineClockSchedule();
        require(delayed.due(100,1,2,42,0),"Initial delayed request");delayed.prepared(1_000_000_100L);
        require(!delayed.due(2_000_000_100L,1,2,42,2000),"Actual prepared timestamp spacing");
        require(delayed.due(3_000_000_100L,1,2,42,3000),"Spacing after actual preparation");
        var cap=new net.alexredby.cartlab.Main.TimelineClockSchedule();
        for(int i=0;i<14;i++)require(cap.due(i*2_000_000_000L,1,2,42,i*2000),"Finite cap input");
        require(!cap.due(28_000_000_000L,1,2,42,26000) && cap.count()==14,"Finite cap");
        var deadline=new net.alexredby.cartlab.Main.TimelineClockSchedule();require(deadline.due(100,1,2,42,0),"Initial");
        require(!deadline.due(33_000_000_100L,1,2,42,1000),"Monotonic deadline");
        var invalid=new net.alexredby.cartlab.Main.TimelineClockSchedule();
        require(!invalid.due(100,1,2,42,Double.NaN) && invalid.closed(),"Nonfinite experiment input");
        var scope=zombie.network.packets.INetworkPacket.class.getDeclaredMethod("send",zombie.network.IConnection.class,zombie.network.PacketTypes.PacketType.class,Object[].class);
        require(java.lang.reflect.Modifier.isStatic(scope.getModifiers()),"Native explicit connection API");
        zombie.network.packets.service.TimeSyncPacket.class.getDeclaredField("clientTime");
        zombie.GameWindow.class.getDeclaredField("gameThread");
        System.out.println("CLOCK_TIME_CHECK_PASS");
    }
}
