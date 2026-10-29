import java.util.*;
import zombie.iso.*;
import zombie.iso.fboRenderChunk.FBORenderCutaways.ChunkLevelData;

/** Canonical-input lifetime transitions plus miss exception and stale-validity sensitivity. */
public final class DeferredChecks {
    static int comparisons;
    static String step(int mode,CacheChecks.Cell cell,int player) {
        CacheChecks.fast=mode!=0;CacheChecks.invalidated.clear();CacheChecks.invalidates=0;
        Arrays.fill(cell.perPlayerData[player].occludedGrid,-32);String outcome="ok";
        try {if(mode==0)PinnedCache.calculateOccludingSquares(cell,player);else if(mode==2)RepairedCache.calculateOccludingSquares(cell,player);else DeferredCache.calculateOccludingSquares(cell,player);}
        catch(RuntimeException e){outcome=e.getClass().getName();}
        StringBuilder result=new StringBuilder(outcome).append('|').append(Arrays.toString(cell.perPlayerData[player].occludedGrid));
        for(IsoChunk c:cell.perPlayerData[player].onScreenChunks)for(int z=c.minLevel;z<=c.maxLevel;z++)result.append('|').append(Arrays.toString(CacheChecks.state(c).byLevel.get(z).occludingSquares));
        return result+"|"+CacheChecks.invalidated;
    }
    static List<String> sequence(int mode,int z,long bits)throws Exception {
        IsoChunk c=CacheChecks.worldChunk(z,bits);ChunkLevelData data=CacheChecks.state(c).data;
        CacheChecks.Cell cell=new CacheChecks.Cell();for(int p=0;p<2;p++)cell.perPlayerData[p]=CacheChecks.view(c,z,0,0);
        ArrayList<String> result=new ArrayList<>();
        // Repeated dirty calls never build an exact mask in the deferred candidate.
        for(int p=0;p<2;p++){CacheChecks.dirty(c,z,p);result.add(step(mode,cell,p));result.add(step(mode,cell,p));}
        if(mode==3)CutawayChecks.require(c.cutawayDeferredState==null || ((c.cutawayDeferredState.valid[0]|c.cutawayDeferredState.valid[1])&(1L<<(z+32)))==0,"dirty target cold path built a cache");
        for(int p=0;p<2;p++){CacheChecks.clean(c,z,p);result.add(step(mode,cell,p));result.add(step(mode,cell,p));}
        for(int[] clip:new int[][]{{1,0},{0,1},{8,8},{0,0}}) {
            for(int p=0;p<2;p++){cell.perPlayerData[p]=CacheChecks.view(c,z,clip[0],clip[1]);result.add(step(mode,cell,p));}
        }
        for(int p=0;p<2;p++) {
            for(int i=0;i<64;i++)data.squareFlags[p][i]^=1;
            CacheChecks.dirty(c,z,p);result.add(step(mode,cell,p));result.add(step(mode,cell,p));
            if(mode==3)CutawayChecks.require((c.cutawayDeferredState.valid[p]&(1L<<(z+32)))==0,"dirty slot retained validity");
            CacheChecks.clean(c,z,p);result.add(step(mode,cell,p));result.add(step(mode,cell,p));
        }
        for(IsoGridSquare square:c.squares[z-c.minLevel])if(square!=null)CacheChecks.declared(square,"visionMatrix",0);
        if(z>-32)for(int i=0;i<64;i++)if(c.squares[z-c.minLevel][i]!=null){IsoGridSquare below=CutawayChecks.raw(IsoGridSquare.class);below.chunk=c;below.x=16+i%8;below.y=24+i/8;below.z=z-1;c.squares[z-c.minLevel-1][i]=below;}
        for(int p=0;p<2;p++){CacheChecks.dirty(c,z,p);result.add(step(mode,cell,p));CacheChecks.clean(c,z,p);result.add(step(mode,cell,p));result.add(step(mode,cell,p));}
        if(z>-32)Arrays.fill(c.squares[z-c.minLevel-1],null);
        for(int p=0;p<2;p++){CacheChecks.dirty(c,z,p);result.add(step(mode,cell,p));CacheChecks.clean(c,z,p);result.add(step(mode,cell,p));}
        DeferredCache.resetValidity(c);RepairedCache.resetValidity(c);
        for(int p=0;p<2;p++){Arrays.fill(data.squareFlags[p],(byte)1);result.add(step(mode,cell,p));result.add(step(mode,cell,p));}
        return result;
    }
    static List<String> nativeException(int mode)throws Exception {
        IsoChunk c=CacheChecks.worldChunk(1,1);CacheChecks.Cell cell=new CacheChecks.Cell();cell.perPlayerData[0]=CacheChecks.view(c,1,0,0);
        CacheChecks.clean(c,1,0);step(mode,cell,0);ChunkLevelData data=CacheChecks.state(c).data;
        byte[] valid=data.squareFlags[0];data.squareFlags[0]=null;CacheChecks.dirty(c,1,0);
        ArrayList<String> results=new ArrayList<>();results.add(step(mode,cell,0));
        data.squareFlags[0]=valid;Arrays.fill(valid,(byte)0);CacheChecks.clean(c,1,0);results.add(step(mode,cell,0));results.add(step(mode,cell,0));return results;
    }
    static void helperException()throws Exception {
        List<String> results=new ArrayList<>();
        for(int mode:new int[]{0,3}) {
            IsoChunk c=CacheChecks.worldChunk(1,1);CacheChecks.Cell cell=new CacheChecks.Cell();cell.perPlayerData[0]=CacheChecks.view(c,1,1,0);
            CacheChecks.state(c).data.squareFlags[0]=null;CacheChecks.state(c).data.occludingSquares[0]=1;CacheChecks.clean(c,1,0);
            results.add(step(mode,cell,0));
            if(mode==3)CutawayChecks.require(c.cutawayDeferredState==null || (c.cutawayDeferredState.valid[0]&(1L<<33))==0,"exceptional helper published cache");
        }
        CutawayChecks.require(results.get(0).equals(results.get(1)),"optional helper exception changed native output");comparisons++;
    }
    public static void main(String[] args)throws Exception {
        IsoChunk cold=CacheChecks.worldChunk(0,-1);cold.minLevel=0;cold.squares=new IsoGridSquare[][]{cold.squares[1]};
        CacheChecks.Cell coldCell=new CacheChecks.Cell();coldCell.perPlayerData[0]=CacheChecks.view(cold,0,0,0);CacheChecks.dirty(cold,0,0);step(3,coldCell,0);
        CutawayChecks.require(cold.cutawayDeferredState==null,"fully dirty cold call allocated cache");
        for(int z=-32;z<=31;z++)for(long mask:new long[]{0,1,1L<<31,1L<<32,1L<<63,-1L,0x8100000180000001L}) {
            List<String> nativeOutput=sequence(0,z,mask),deferred=sequence(3,z,mask);
            CutawayChecks.require(nativeOutput.equals(deferred),"deferred transition z="+z+" mask="+mask);comparisons+=nativeOutput.size();
        }
        List<String> nativeOutput=nativeException(0),deferred=nativeException(3),stale=nativeException(2);
        CutawayChecks.require(nativeOutput.equals(deferred),"native miss exception output mismatch");comparisons+=nativeOutput.size();
        CutawayChecks.require(!nativeOutput.equals(stale),"stale-validity negative control insensitive");helperException();
        System.out.println("DEFERRED_CHECKS_PASS snapshots="+comparisons+" native-miss-exception-preserved helper-failure-unpublished stale-validity-negative-control=detected z=-32..31");
    }
}
