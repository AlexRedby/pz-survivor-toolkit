import java.lang.management.ManagementFactory;
import java.lang.reflect.Field;
import java.util.*;
import sun.misc.Unsafe;
import zombie.iso.IsoObject;
import zombie.iso.fboRenderChunk.ObjectRenderInfo;
import zombie.iso.fboRenderChunk.ObjectRenderLayer;

/** Headless object-state checks; does not call renderFog or launch the game. */
public final class FogOperationChecks {
    static final Unsafe U;
    static final Field RI;
    static { try {
        Field f=Unsafe.class.getDeclaredField("theUnsafe");f.setAccessible(true);U=(Unsafe)f.get(null);
        RI=IsoObject.class.getDeclaredField("renderInfo");RI.setAccessible(true);
    } catch(Exception e) { throw new ExceptionInInitializerError(e); } }
    static volatile long sink;
    static int checks;
    static class Probe extends IsoObject {
        int id, throwsAt=-1; List<Integer> trace; Runnable effect;
        public ObjectRenderInfo getRenderInfo(int player) {
            trace.add(id);
            if(effect!=null) effect.run();
            if(id==throwsAt) throw failure;
            return super.getRenderInfo(player);
        }
    }
    static final RuntimeException failure=new RuntimeException("owned sentinel");
    static IsoObject object(boolean probe,int id,List<Integer> trace) throws Exception {
        IsoObject o=(IsoObject)U.allocateInstance(probe?Probe.class:IsoObject.class);
        RI.set(o,new ObjectRenderInfo[4]);
        if(probe) { Probe p=(Probe)o;p.id=id;p.trace=trace;p.throwsAt=-1; }
        return o;
    }
    static void require(boolean b,String m) { if(!b)throw new AssertionError(m); }
    static Object call(boolean candidate,IsoObject[] objects,int size,int player) {
        try { return candidate?FogObjectScan.unrolled(objects,size,player):FogObjectScan.stock(objects,size,player); }
        catch(Throwable t) { return t==failure?"sentinel":t.getClass().getName(); }
    }
    static String state(IsoObject[] objects) throws Exception {
        StringBuilder s=new StringBuilder();IdentityHashMap<Object,Integer> ids=new IdentityHashMap<>();
        for(IsoObject o:objects) {
            if(o==null) { s.append("null;");continue; }
            s.append(ids.computeIfAbsent(o,k->ids.size())).append(':');
            for(ObjectRenderInfo r:(ObjectRenderInfo[])RI.get(o))
                s.append(r==null?"null":r.layer+"/"+r.targetAlpha).append(',');
            s.append(';');
        }
        return s.toString();
    }
    static String vector(boolean candidate,int length,int hit,int player,int size,int nullAt,int throwAt,boolean mutate) throws Exception {
        List<Integer> trace=new ArrayList<>();IsoObject[] a=new IsoObject[length];
        for(int i=0;i<length;i++) {
            a[i]=object(true,i,trace);Probe p=(Probe)a[i];p.throwsAt=throwAt;
            if(i==hit) { ObjectRenderInfo r=new ObjectRenderInfo(a[i]);r.layer=ObjectRenderLayer.MinusFloor;((ObjectRenderInfo[])RI.get(a[i]))[player]=r; }
        }
        if(nullAt>=0)a[nullAt]=null;
        if(mutate && length>4) ((Probe)a[0]).effect=()->a[3]=a[1];
        Object result=call(candidate,a,size,player);
        return result+"|"+trace+"|"+state(a);
    }
    static void correctness() throws Exception {
        for(int length=0;length<=32;length++)for(int hit=-1;hit<length;hit++)for(int player=0;player<4;player++) {
            String a=vector(false,length,hit,player,length,-1,-1,false),b=vector(true,length,hit,player,length,-1,-1,false);
            require(a.equals(b),"prefix/state "+length+"/"+hit+"/"+player);checks++;
        }
        for(int n:new int[]{1,3,4,5,7,8,9,16})for(int at=0;at<n;at++)for(int kind=0;kind<3;kind++) {
            String a=vector(false,n,-1,0,n,kind==0?at:-1,kind==1?at:-1,kind==2),b=vector(true,n,-1,0,n,kind==0?at:-1,kind==1?at:-1,kind==2);
            require(a.equals(b),"exception/mutation");checks++;
        }
        for(int size:new int[]{-1,0,1,3,4,5,7,8,9,12,Integer.MAX_VALUE}) {
            require(vector(false,8,-1,0,size,-1,-1,false).equals(vector(true,8,-1,0,size,-1,-1,false)),"size/array bounds");checks++;
        }
        for(int player:new int[]{-1,4,Integer.MAX_VALUE}) {
            IsoObject[] a={object(false,0,null)},b={object(false,0,null)};
            require(call(false,a,1,player).equals(call(true,b,1,player)),"player bounds");checks++;
        }
        require(call(false,null,1,0).equals(call(true,null,1,0)),"null array");checks++;
        // The known lazy-state counterexample remains protected.
        IsoObject[] a={object(false,0,null)};FogObjectScan.unrolled(a,1,0);
        ObjectRenderInfo r=((ObjectRenderInfo[])RI.get(a[0]))[0];require(r!=null && r.targetAlpha==1,"lazy initialize");checks++;
        System.out.println("FOG_OPERATION_CHECKS_PASS checks="+checks);
    }
    record Case(String label,IsoObject[][] arrays,int[] sizes) {}
    static Case fixture(String label,int length,int hit,int variants) throws Exception {
        IsoObject[][] a=new IsoObject[variants][];int[] sizes=new int[variants];
        for(int v=0;v<variants;v++) {
            int n=length<0?(v%9):length;a[v]=new IsoObject[n];sizes[v]=n;
            for(int i=0;i<n;i++) {
                a[v][i]=object(false,i,null);ObjectRenderInfo r=new ObjectRenderInfo(a[v][i]);
                int h=hit==-2?(n-1):hit==-3?(n==0?-1:v%n):hit;
                r.layer=i==h?ObjectRenderLayer.MinusFloor:ObjectRenderLayer.None;((ObjectRenderInfo[])RI.get(a[v][i]))[0]=r;
            }
        }
        return new Case(label,a,sizes);
    }
    static long batch(boolean candidate,Case f,int iterations) {
        long sum=0;int mask=f.arrays.length-1;
        if(candidate) for(int i=0;i<iterations;i++) {int n=i&mask;sum+=FogObjectScan.unrolled(f.arrays[n],f.sizes[n],0);}
        else for(int i=0;i<iterations;i++) {int n=i&mask;sum+=FogObjectScan.stock(f.arrays[n],f.sizes[n],0);}
        sink=sum;return sum;
    }
    static void requireCpuTimer(java.lang.management.ThreadMXBean bean) {
        if (!bean.isCurrentThreadCpuTimeSupported() || !bean.isThreadCpuTimeEnabled())
            throw new IllegalStateException("CPU measurement requires supported and enabled current-thread CPU time");
        if (bean.getCurrentThreadCpuTime() < 0)
            throw new IllegalStateException("Current-thread CPU timer returned an unavailable value");
    }
    static void checkDisabledCpuTimer(java.lang.management.ThreadMXBean bean) {
        boolean supported=bean.isCurrentThreadCpuTimeSupported();
        boolean enabled=supported && bean.isThreadCpuTimeEnabled();
        try {
            if(supported) bean.setThreadCpuTimeEnabled(false);
            try { requireCpuTimer(bean);throw new AssertionError("Unavailable CPU timer was admitted"); }
            catch(IllegalStateException expected) { }
        } finally { if(supported) bean.setThreadCpuTimeEnabled(enabled); }
        System.out.println("FOG_CPU_TIMER_GUARD_PASS");
    }
    public static void main(String[] args) throws Exception {
        correctness();if(args.length==0)return;
        var bean=ManagementFactory.getThreadMXBean();
        if(args[0].equals("check-cpu-guard")) { checkDisabledCpuTimer(bean);return; }
        requireCpuTimer(bean);
        List<Case> cases=List.of(fixture("empty",0,-1,128),fixture("first",8,0,128),fixture("short-mixed",-1,-3,128),
            fixture("short-miss",4,-1,128),fixture("late",32,-2,128),fixture("dense-miss",32,-1,128),fixture("long-miss",128,-1,128));
        int iterations=500000;
        for(int warm=0;warm<24;warm++)for(Case f:cases) {batch(false,f,iterations);batch(true,f,iterations);}
        boolean reverse=args[0].equals("reverse");
        for(int round=0;round<7;round++)for(Case f:cases)for(int m=0;m<2;m++) {
            boolean candidate=(m==1)^reverse^(round%2==1);long uptime=ManagementFactory.getRuntimeMXBean().getUptime(),begin=System.nanoTime(),cpu=bean.getCurrentThreadCpuTime();
            long checksum=batch(candidate,f,iterations);long elapsed=System.nanoTime()-begin,used=bean.getCurrentThreadCpuTime()-cpu;
            System.out.println("ROW "+(candidate?"unrolled":"stock")+" "+f.label+" "+round+" "+iterations+" "+elapsed+" "+used+" "+checksum);
            System.out.println("WINDOW "+uptime+" "+(uptime+(elapsed+999999)/1000000));
        }
    }
}
