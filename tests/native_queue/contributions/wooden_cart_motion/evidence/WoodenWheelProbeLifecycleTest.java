import java.io.BufferedWriter;
import java.io.IOException;
import java.io.StringWriter;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/** Deterministic stop/callback interleaving against the actual probe, without launching a game. */
public final class WoodenWheelProbeLifecycleTest {
    private static final Field OUTPUT;
    static {
        try {OUTPUT=WoodenWheelNativeProbe.class.getDeclaredField("output");OUTPUT.setAccessible(true);}
        catch(Exception error){throw new ExceptionInInitializerError(error);}
    }
    private static void require(boolean value,String message) {
        if(!value)throw new AssertionError(message);
    }
    private static final class Writer extends BufferedWriter {
        boolean closed,failClose;
        int writes,closes;
        Writer(){super(new StringWriter());}
        @Override public void write(String text,int offset,int length) throws IOException {
            if(closed)throw new IOException("write after close");
            writes++;super.write(text,offset,length);
        }
        @Override public void close() throws IOException {
            try {
                require(Thread.holdsLock(WoodenWheelNativeProbe.class),"close escaped lifecycle monitor");
                require(OUTPUT.get(null)==null,"writer remained published during close");
            }catch(IllegalAccessException error){throw new AssertionError(error);}
            closes++;closed=true;
            if(failClose)throw new IOException("injected close failure");
            super.close();
        }
    }
    public static void main(String[] args) throws Exception {
        require(Modifier.isVolatile(OUTPUT.getModifiers()),"callback active check must observe stop");
        var writer=new Writer();OUTPUT.set(null,writer);
        var checkedActive=new CountDownLatch(1);
        var failure=new AtomicReference<Throwable>();
        var callback=new Thread(()->{
            try {
                require(OUTPUT.get(null)!=null,"callback never observed active capture");
                checkedActive.countDown();
                WoodenWheelNativeProbe.row("grounding",null,null,null);
            }catch(Throwable error){failure.set(error);}
        },"queued-grounding-callback");
        synchronized(WoodenWheelNativeProbe.class) {
            callback.start();
            require(checkedActive.await(2,TimeUnit.SECONDS),"callback did not reach active check");
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(2);
            while(callback.getState()!=Thread.State.BLOCKED && callback.isAlive() && System.nanoTime()<deadline)Thread.onSpinWait();
            require(callback.getState()==Thread.State.BLOCKED,"row did not serialize with stop: "+failure.get());
            WoodenWheelNativeProbe.agentmain("stop",null);
            require(writer.closed && OUTPUT.get(null)==null,"stop did not detach and close writer");
        }
        callback.join(2000);
        require(!callback.isAlive() && failure.get()==null,"late callback failed: "+failure.get());
        require(writer.writes==0 && writer.closes==1,"late callback touched stopped writer");
        WoodenWheelNativeProbe.row("grounding",null,null,null);
        WoodenWheelNativeProbe.agentmain("stop",null);
        require(writer.closes==1,"repeated stop closed writer twice");

        var broken=new Writer();broken.failClose=true;OUTPUT.set(null,broken);
        try {WoodenWheelNativeProbe.agentmain("stop",null);throw new AssertionError("close error was swallowed");}
        catch(IOException expected){require(expected.getMessage().equals("injected close failure"),"wrong close error");}
        require(OUTPUT.get(null)==null,"failed close left writer active");
        WoodenWheelNativeProbe.row("grounding",null,null,null);
        System.out.println("WOOD_WHEEL_NATIVE_PROBE_LIFECYCLE_PASS");
    }
}
