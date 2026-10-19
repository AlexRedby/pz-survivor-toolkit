package net.alexredby.pztoolkitjavapatches;

public final class CartActionSyncTest {
    private static void check(boolean value,String message) {if(!value) throw new AssertionError(message);}
    public static void main(String[] args) {
        var pose=new CartActionSync.Pose(123,4,1,1,.5f,0,111,222,.00175f,0,90,0,.85f);
        String encoded=pose.encode(1);
        check(pose.equals(CartActionSync.parse(encoded)),"action snapshot roundtrip lost placement or progress");
        check(pose.nearby(110,222,0) && !pose.nearby(107,222,0) && !pose.nearby(111,222,1),
            "action placement escaped owner range/floor");
        for(String malformed:new String[]{"",encoded+",0",encoded.substring(2),encoded.replaceFirst("1,1","2,1"),
            encoded.replace("123,4,1","123,0,1"),encoded.replace("123,4,1","123,4,4"),
            encoded.replace("0.5","NaN"),encoded.replace("0.5","Infinity"),encoded.replace("0.5","1.01"),
            encoded.replace("111.0","1000001"),encoded.replace("0.00175","65"),encoded.replace("90.0","361"),
            encoded.replace("0.85","0"),encoded.replace("0.85","101"),"x".repeat(301)})
            check(CartActionSync.parse(malformed)==null,"accepted malformed action snapshot: "+malformed);
        var recovery=new CartActionSync.Pose(123,4,1,3,.3f,.5f,111,222,.00175f,0,90,0,.85f);
        check(CartActionSync.parse(recovery.encode(2)).recovering(),"recovery mode was lost");
        check(!new CartActionSync.Pose(123,4,1,3,.6f,.5f,111,222,0,0,0,0,1).valid(),"recovery exceeded cancel phase");
        check(!new CartActionSync.Pose(123,4,1,3,0,0,111,222,0,0,0,0,1).valid(),"empty recovery was accepted");
        Object item=new Object(), replacement=new Object();
        var sender=new CartActionSync.Sender();
        check(sender.due(pose,item,0),"action start was delayed");
        String first=sender.next(pose,item,0);
        check(!sender.due(pose,item,CartMotionSync.HEARTBEAT_NANOS-1),"unchanged action flooded packets");
        check(sender.due(pose,item,CartMotionSync.HEARTBEAT_NANOS),"active action heartbeat missing");
        check(sender.due(recovery,item,1),"short cancellation was swallowed by motion throttle");
        check(sender.due(pose,replacement,1),"same-ID action object handoff was delayed");
        var restart=new CartActionSync.Pose(123,5,1,1,.01f,0,111,222,.00175f,0,90,0,.85f);
        check(sender.due(restart,item,1),"same-item action restart inherited the old generation");
        int sent=0;
        var burst=new CartActionSync.Sender();
        for(long now=0;now<1_000_000_000L;now+=1_000_000L) {
            var next=new CartActionSync.Pose(123,4,1,1,now/1_000_000_000f,0,111,222,.00175f,0,90,0,.85f);
            if(burst.due(next,item,now)) {burst.next(next,item,now);sent++;}
        }
        check(sent<=10,"action progress exceeded 10 packets per second");
        var remote=new CartActionSync.Remote();
        remote.receive(first,0);
        check(remote.fresh(CartMotionSync.STALE_NANOS) && !remote.fresh(CartMotionSync.STALE_NANOS+1),"action freshness not bounded");
        remote.receive(first,CartMotionSync.STALE_NANOS+1);
        check(!remote.fresh(CartMotionSync.STALE_NANOS+1),"unchanged stale action revived");
        remote.receive(recovery.encode(2),CartMotionSync.STALE_NANOS+2);
        float before=remote.progress;
        check(remote.progress(.1f)<before && remote.progress>=recovery.progress(),"recovery progress jumped or ran backwards");
        remote.receive(restart.encode(3),CartMotionSync.STALE_NANOS+3);
        check(remote.progress==restart.progress(),"restarted action retained the old recovery phase");
        remote.receive("",CartMotionSync.STALE_NANOS+4);
        check(!remote.fresh(CartMotionSync.STALE_NANOS+4),"finished action retained remote presentation");
        remote.receive(recovery.encode(1),CartMotionSync.STALE_NANOS+5);
        check(remote.progress==recovery.progress(),"late recovery did not keep its received phase for safe native fallback");
        remote.receive("invalid",CartMotionSync.STALE_NANOS+6);
        check(remote.pose==null,"malformed action retained previous presentation");
        System.out.println("CART_ACTION_SYNC_PASS");
    }
}
