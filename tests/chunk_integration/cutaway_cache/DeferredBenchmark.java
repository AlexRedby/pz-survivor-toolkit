import java.lang.management.*;
import java.util.*;
import zombie.iso.*;

/** Complete 32-chunk operation diagnostic, with symmetric invalidation/transition bookkeeping. */
public final class DeferredBenchmark {
    static final String[] PATHS={"clean","mixed25","dirty","clean-miss","cycle4","cycle8"};
    static final class World {
        CacheChecks.Cell cell;int mode,path,tick;String label;
    }
    static volatile long sink;
    static World world(int mode,int density,int path)throws Exception {
        World w=new World();w.mode=mode;w.path=path;w.label=new String[]{"empty","sparse","dense"}[density]+"-"+PATHS[path];
        w.cell=CacheBenchmark.world(mode==3?0:mode,density,path<3?path:0).cell();
        // Capacity is allocated before timing for every mode. clean-miss measures cold validity,
        // not first heap allocation; allocation-free dirty cold behavior is checked separately.
        for(IsoChunk c:w.cell.perPlayerData[0].onScreenChunks) {
            c.cutawayDeferredState=new DeferredCache.State();c.cutawayDeferredState.masks[0]=new long[64];
            if(CacheChecks.state(c).repairedMask[0]==null)CacheChecks.state(c).repairedMask[0]=new long[64];
        }
        return w;
    }
    static long batch(World w,int operations) {
        long sum=0;CacheChecks.fast=w.mode!=0;int[] grid=w.cell.perPlayerData[0].occludedGrid;
        for(int i=0;i<operations;i++) {
            if(w.path==3)for(IsoChunk c:w.cell.perPlayerData[0].onScreenChunks) {
                CacheChecks.state(c).repairedSet[0]=0;c.cutawayDeferredState.valid[0]=0;
            }
            if(w.path>=4) {
                boolean dirty=(w.tick++%(w.path==4?4:8))==0;
                for(IsoChunk c:w.cell.perPlayerData[0].onScreenChunks)if(dirty)CacheChecks.dirty(c,0,0);else CacheChecks.clean(c,0,0);
            }
            Arrays.fill(grid,-32);
            if(w.mode==3)DeferredCache.calculateOccludingSquares(w.cell,0);
            else if(w.mode==2)RepairedCache.calculateOccludingSquares(w.cell,0);
            else PinnedCache.calculateOccludingSquares(w.cell,0);
            sum+=grid[i&(grid.length-1)];
            sum+=CacheChecks.state(w.cell.perPlayerData[0].onScreenChunks.get(i&31)).data.occludingSquares[0];
        }
        sink=sum;return sum;
    }
    public static void main(String[] args)throws Exception {
        ThreadMXBean cpu=ManagementFactory.getThreadMXBean();
        if(!cpu.isCurrentThreadCpuTimeSupported() || !cpu.isThreadCpuTimeEnabled() || cpu.getCurrentThreadCpuTime()<0)throw new IllegalStateException("enabled CPU timer required");
        ArrayList<World[]> groups=new ArrayList<>();
        for(int density=0;density<3;density++)for(int path=0;path<PATHS.length;path++) {
            World[] group=new World[3];int at=0;for(int mode:new int[]{0,2,3})group[at++]=world(mode,density,path);groups.add(group);
        }
        for(int round=0;round<28;round++)for(World[] group:groups)for(World w:group)batch(w,120);
        int offset=Integer.parseInt(args[0]),operations=1200;
        for(int round=0;round<7;round++)for(World[] group:groups)for(int at=0;at<3;at++) {
            World w=group[(offset+round+at)%3];long uptime=ManagementFactory.getRuntimeMXBean().getUptime();
            long wall=System.nanoTime(),used=cpu.getCurrentThreadCpuTime();long checksum=batch(w,operations);
            used=cpu.getCurrentThreadCpuTime()-used;wall=System.nanoTime()-wall;
            if(used<=0 || wall<=0)throw new IllegalStateException("positive duration required");
            System.out.println("ROW "+w.label+" "+w.mode+" "+round+" "+operations+" "+wall+" "+used+" "+checksum);
            System.out.println("WINDOW "+uptime+" "+(uptime+(wall+999999)/1000000));
        }
    }
}
