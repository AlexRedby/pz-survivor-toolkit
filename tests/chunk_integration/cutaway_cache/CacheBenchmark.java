import java.lang.management.*;
import java.util.*;
import zombie.iso.*;

/** Bounded CPU diagnostic for complete world-grid rebuilds; no runtime admission. */
public final class CacheBenchmark {
    record World(CacheChecks.Cell cell,int mode,String label){}
    static volatile long sink;
    static World world(int mode,int density,int dirty)throws Exception {
        CacheChecks.Cell cell=new CacheChecks.Cell();CacheChecks.PlayerData p=new CacheChecks.PlayerData();cell.perPlayerData[0]=p;
        p.occludedGridX1=16;p.occludedGridY1=24;p.occludedGridX2=79;p.occludedGridY2=55;p.occludedGrid=new int[64*32];
        long bits=density==0?0:density==1?0x0101010101010101L:-1L;
        for(int i=0;i<32;i++) {
            IsoChunk c=CacheChecks.worldChunk(0,bits);c.minLevel=0;c.squares=new IsoGridSquare[][]{c.squares[1]};
            c.wx=2+i%8;c.wy=3+i/8;
            for(IsoGridSquare q:c.squares[0])if(q!=null){q.x=c.wx*8+(q.x-16);q.y=c.wy*8+(q.y-24);}
            p.onScreenChunks.add(c);CacheChecks.dirty(c,0,0);
        }
        CacheChecks.fast=mode!=0;
        if(mode==2)RepairedCache.calculateOccludingSquares(cell,0);else PinnedCache.calculateOccludingSquares(cell,0);
        for(int i=0;i<32;i++)if(dirty==0 || dirty==1 && i%4!=0)CacheChecks.clean(p.onScreenChunks.get(i),0,0);
        return new World(cell,mode,new String[]{"empty","sparse","dense"}[density]+"-"+new String[]{"clean","mixed25","dirty"}[dirty]);
    }
    static long batch(World w,int n) {
        long sum=0;CacheChecks.fast=w.mode!=0;int[] grid=w.cell.perPlayerData[0].occludedGrid;
        for(int i=0;i<n;i++) {
            Arrays.fill(grid,-32);
            if(w.mode==2)RepairedCache.calculateOccludingSquares(w.cell,0);else PinnedCache.calculateOccludingSquares(w.cell,0);
            sum+=grid[i&(grid.length-1)];
            sum+=CacheChecks.state(w.cell.perPlayerData[0].onScreenChunks.get(i&31)).data.occludingSquares[0];
        }
        sink=sum;return sum;
    }
    public static void main(String[] a)throws Exception {
        ThreadMXBean cpu=ManagementFactory.getThreadMXBean();
        if(!cpu.isCurrentThreadCpuTimeSupported() || !cpu.isThreadCpuTimeEnabled() || cpu.getCurrentThreadCpuTime()<0)
            throw new IllegalStateException("enabled thread CPU timer required");
        ArrayList<World[]> groups=new ArrayList<>();
        for(int density=0;density<3;density++)for(int dirty=0;dirty<3;dirty++){
            World[] group=new World[3];for(int mode=0;mode<3;mode++)group[mode]=world(mode,density,dirty);groups.add(group);
        }
        // Every full operation and helper sees all modes before measured windows.
        for(int round=0;round<24;round++)for(World[] group:groups)for(World w:group)batch(w,120);
        int operations=1200,offset=Integer.parseInt(a[0]);
        for(int round=0;round<7;round++)for(World[] group:groups)for(int at=0;at<3;at++) {
            World w=group[(at+offset+round)%3];long uptime=ManagementFactory.getRuntimeMXBean().getUptime();
            long wall=System.nanoTime(),used=cpu.getCurrentThreadCpuTime();long sum=batch(w,operations);
            used=cpu.getCurrentThreadCpuTime()-used;wall=System.nanoTime()-wall;
            if(used<=0 || wall<=0)throw new IllegalStateException("positive duration required");
            System.out.println("ROW "+w.label+" "+w.mode+" "+round+" "+operations+" "+wall+" "+used+" "+sum);
            System.out.println("WINDOW "+uptime+" "+(uptime+(wall+999999)/1000000));
        }
    }
}
