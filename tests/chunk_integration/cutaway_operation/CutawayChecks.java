import java.lang.management.*;
import java.lang.reflect.*;
import java.util.*;
import sun.misc.Unsafe;
import zombie.iso.*;
import zombie.iso.fboRenderChunk.FBORenderCutaways.ChunkLevelData;
import zombie.iso.fboRenderChunk.FBORenderCutaways.ChunkLevelsData;

/** Executes extracted and actual native operations on real game objects, without a game launch. */
public final class CutawayChecks {
    static final Unsafe U;
    static {try {Field f=Unsafe.class.getDeclaredField("theUnsafe");f.setAccessible(true);U=(Unsafe)f.get(null);}catch(Exception e){throw new ExceptionInInitializerError(e);}}
    static volatile long sink;
    static int checks;
    static void set(Object o,String n,Object value)throws Exception {Field f=o.getClass().getField(n);f.setAccessible(true);f.set(o,value);}
    static <T>T raw(Class<T> c)throws Exception{return c.cast(U.allocateInstance(c));}
    static void require(boolean b,String m){if(!b)throw new AssertionError(m);}
    record Fixture(String name,ChunkLevelData data,int player,int minX,int minY,int maxX,int maxY,int[] heights){}
    static Fixture fixture(String name,int seed,int kind)throws Exception {
        Random r=new Random(seed);IsoChunk chunk=raw(IsoChunk.class);chunk.wx=2;chunk.wy=3;chunk.minLevel=0;chunk.maxLevel=1;
        int len=kind==1?seed%64:64;chunk.squares=new IsoGridSquare[][]{new IsoGridSquare[64],new IsoGridSquare[len]};
        for(int i=0;i<len;i++) {
            if(kind==2 || kind==3 && i%8!=0 || kind==4 && !r.nextBoolean())continue;
            IsoGridSquare s=raw(IsoGridSquare.class);s.chunk=chunk;s.x=16+i%8;s.y=24+i/8;s.z=1;
            // Native getVisionMatrix reads this mutable int; zero means check the native below-square path.
            Field vision=IsoGridSquare.class.getDeclaredField("visionMatrix");vision.setAccessible(true);vision.setInt(s,kind==5?-1:0);
            chunk.squares[1][i]=s;
            if(kind==6 && i%3==0)chunk.squares[0][i]=s;
            if(kind==7 && i%5==0)s.chunk=null;
            if(kind==8 && i%3==0)s.z=2;
            if(kind==9) {IsoChunk foreign=raw(IsoChunk.class);foreign.wx=i%2==0?2:3;foreign.wy=3;s.chunk=foreign;}
            if(kind==10)s.x+=100;
            if(kind==11 && i==seed%64) {s.x=Integer.MAX_VALUE;s.y=Integer.MIN_VALUE;s.z=Integer.MAX_VALUE;}
        }
        ChunkLevelData data=raw(ChunkLevelData.class);set(data,"level",1);
        ChunkLevelsData levels=raw(ChunkLevelsData.class);set(levels,"chunk",chunk);data.levelsData=levels;
        byte[][] flags=new byte[4][64];for(byte[] a:flags)for(int i=0;i<a.length;i++)a[i]=(byte)(kind==12?r.nextInt(256):1);
        if(kind==13)flags[seed%4]=new byte[seed%64];if(kind==14)flags[seed%4]=null;
        set(data,"squareFlags",flags);set(data,"occludingSquares",new long[]{seed,seed*7L,-1,Long.MIN_VALUE});
        int player=kind==15?new int[]{-1,4,Integer.MAX_VALUE}[seed%3]:seed%4;
        int minX=13,minY=21,maxX=20,maxY=28;
        if(kind==16) {minX=seed%2==0?Integer.MIN_VALUE:20;maxX=seed%2==0?Integer.MAX_VALUE:13;}
        int[] heights=new int[kind==17?seed%64:64];Arrays.fill(heights,-1);
        if(kind==18)heights=null;if(kind==19)chunk.squares=null;if(kind==20)chunk.squares[1]=null;if(kind==21)data.levelsData=null;
        return new Fixture(name,data,player,minX,minY,maxX,maxY,heights);
    }
    static boolean call(int mode,Fixture f) {
        return mode==0?f.data.calculateOccludingSquares(f.player,f.minX,f.minY,f.maxX,f.maxY,f.heights):
            mode==1?CutawayOperation.stock(f.data,f.player,f.minX,f.minY,f.maxX,f.maxY,f.heights):
            mode==2?CutawayOperation.reduced(f.data,f.player,f.minX,f.minY,f.maxX,f.maxY,f.heights):
            mode==3?OfficialCutawayOperation.stock(f.data,f.player,f.minX,f.minY,f.maxX,f.maxY,f.heights):
            OfficialCutawayOperation.reduced(f.data,f.player,f.minX,f.minY,f.maxX,f.maxY,f.heights);
    }
    static String result(int mode,int seed,int kind)throws Exception {
        Fixture f=fixture("check",seed,kind);Object value;
        try {value=call(mode,f);}catch(Throwable t){value=t.getClass().getName();}
        return value+"|"+Arrays.toString(f.data.occludingSquares)+"|"+Arrays.toString(f.heights);
    }
    static void correctness()throws Exception {
        for(int kind=0;kind<=21;kind++)for(int seed=0;seed<80;seed++) {
            String expected=result(0,seed,kind);
            require(expected.equals(result(1,seed,kind)),"extraction "+kind+"/"+seed);
            for(int mode=2;mode<5;mode++)require(expected.equals(result(mode,seed,kind)),"candidate/official "+mode+"/"+kind+"/"+seed);checks++;
        }
        // Native int shift masks by 31, then i2l sign-extends. Preserve this behavior exactly.
        for(int i=0;i<64;i++) {
            Fixture f=fixture("bit",0,0);IsoGridSquare[] squares=f.data.levelsData.chunk.squares[1];
            for(int j=0;j<64;j++)if(i!=j)squares[j]=null;
            call(2,f);require(f.data.occludingSquares[0]==(long)(1<<i),"native mask width/sign "+i);checks++;
        }
        // State changed between invocations must be read again; no coordinate/chunk/flag cache.
        for(int mode=0;mode<3;mode++) {
            Fixture f=fixture("mutable",0,0);call(mode,f);f.data.squareFlags[0][0]=0;
            f.data.levelsData.chunk.squares[1][1].chunk=null;f.data.levelsData.chunk.squares[1][2].z=0;
            f.data.levelsData.chunk.squares[1][3].x=300;Arrays.fill(f.heights,-1);call(mode,f);
            require(f.heights[0]==-1 && f.heights[1]==-1 && f.heights[2]==-1 && f.heights[3]==-1,"live mutable fields");checks++;
        }
        System.out.println("CUTAWAY_CHECKS_PASS checks="+checks);
    }
    static long batch(boolean reduced,Fixture[] f,int n) {
        long sum=0;
        if(reduced)for(int i=0;i<n;i++) {Fixture a=f[i&31];sum+=call(4,a)?1:0;sum+=a.data.occludingSquares[0];}
        else for(int i=0;i<n;i++) {Fixture a=f[i&31];sum+=call(3,a)?1:0;sum+=a.data.occludingSquares[0];}
        sink=sum;return sum;
    }
    static void cpu(ThreadMXBean b) {if(!b.isCurrentThreadCpuTimeSupported() || !b.isThreadCpuTimeEnabled() || b.getCurrentThreadCpuTime()<0)throw new IllegalStateException("enabled CPU timer required");}
    public static void main(String[] a)throws Exception {
        correctness();if(a.length==0)return;ThreadMXBean b=ManagementFactory.getThreadMXBean();
        if(a[0].equals("check-cpu-guard")) {boolean enabled=b.isThreadCpuTimeEnabled();try {b.setThreadCpuTimeEnabled(false);try{cpu(b);throw new AssertionError("disabled CPU admitted");}catch(IllegalStateException expected){}}finally{b.setThreadCpuTimeEnabled(enabled);}System.out.println("CUTAWAY_CPU_GUARD_PASS");return;}
        cpu(b);String[] labels={"empty","sparse","normal","vision","below","unusual"};int[] kinds={2,3,0,5,6,7};
        List<Fixture[]> fixtures=new ArrayList<>();for(int k=0;k<kinds.length;k++){Fixture[] f=new Fixture[32];for(int i=0;i<32;i++)f[i]=fixture(labels[k],i,kinds[k]);fixtures.add(f);}
        int iterations=200000;
        for(int w=0;w<24;w++)for(Fixture[] f:fixtures){batch(false,f,iterations);batch(true,f,iterations);}
        for(int round=0;round<7;round++)for(int k=0;k<labels.length;k++)for(int m=0;m<2;m++) {
            boolean reduced=(m==1)^a[0].equals("reverse")^(round%2==1);
            long at=ManagementFactory.getRuntimeMXBean().getUptime(),wall=System.nanoTime(),used=b.getCurrentThreadCpuTime();
            long sum=batch(reduced,fixtures.get(k),iterations);used=b.getCurrentThreadCpuTime()-used;wall=System.nanoTime()-wall;
            require(wall>0 && used>0,"positive wall/CPU duration required");
            System.out.println("ROW "+(reduced?"reduced":"stock")+" "+labels[k]+" "+round+" "+iterations+" "+wall+" "+used+" "+sum);
            System.out.println("WINDOW "+at+" "+(at+(wall+999999)/1000000));
        }
    }
}
