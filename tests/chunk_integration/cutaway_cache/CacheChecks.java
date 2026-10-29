import java.lang.reflect.*;
import java.util.*;
import zombie.iso.*;
import zombie.iso.fboRenderChunk.*;
import zombie.iso.fboRenderChunk.FBORenderCutaways.ChunkLevelData;
import zombie.iso.fboRenderChunk.FBORenderCutaways.ChunkLevelsData;

/** Reuses the full-operation fixture; tests real native producers and dirty lifecycle without game launch. */
public final class CacheChecks {
    public static boolean fast;
    public static final class Cell { public PlayerData[] perPlayerData=new PlayerData[4]; }
    public static final class PlayerData {
        public ArrayList<IsoChunk> onScreenChunks=new ArrayList<>();
        public int occludedGridX1,occludedGridY1,occludedGridX2,occludedGridY2;
        public int[] occludedGrid;
    }
    public static final class State {long[] mask=new long[64];long maskSet;long[][] repairedMask=new long[4][];long[] repairedSet=new long[4];ChunkLevelData data,zero;HashMap<Integer,ChunkLevelData> byLevel=new HashMap<>();}
    static int invalidates;
    static final ArrayList<String> invalidated=new ArrayList<>();
    public static State state(IsoChunk c){return c.cutawayCacheState;}
    public static long[] mask(IsoChunk c){return state(c).mask;}
    public static long maskSet(IsoChunk c){return state(c).maskSet;}
    public static void setMaskSet(IsoChunk c,long set){state(c).maskSet=set;}
    public static ChunkLevelsData levels(IsoChunk c){return state(c).data.levelsData;}
    public static ChunkLevelData level(ChunkLevelsData l,int z){State s=state(l.chunk);ChunkLevelData d=s.byLevel.get(z);if(d==null)throw new AssertionError("level fixture "+z);return d;}
    public static void invalidate(FBORenderOcclusion ignored,int player,IsoChunk c,int z){invalidates++;invalidated.add(player+":"+c.wx+":"+c.wy+":"+z);}
    static void declared(Object o,String name,Object value)throws Exception {Class<?> type=o.getClass();Field f;for(;;){try{f=type.getDeclaredField(name);break;}catch(NoSuchFieldException e){type=type.getSuperclass();if(type==null)throw e;}}f.setAccessible(true);f.set(o,value);}
    static Object constructed(Class<?> c)throws Exception {Constructor<?> ctor=c.getDeclaredConstructor();ctor.setAccessible(true);return ctor.newInstance();}
    static FBORenderCutaways producer()throws Exception {
        FBORenderCutaways cut=CutawayChecks.raw(FBORenderCutaways.class);
        Class<?> pd=Class.forName("zombie.iso.fboRenderChunk.FBORenderCutaways$PerPlayerData");
        Object array=Array.newInstance(pd,4);for(int i=0;i<4;i++)Array.set(array,i,constructed(pd));
        declared(cut,"perPlayerData",array);return cut;
    }
    static IsoChunk chunk()throws Exception {
        CutawayChecks.Fixture f=CutawayChecks.fixture("cache",0,0);IsoChunk original=f.data().levelsData.chunk;
        IsoChunk c=CutawayChecks.raw(IsoChunk.class);c.wx=original.wx;c.wy=original.wy;c.minLevel=original.minLevel;c.maxLevel=original.maxLevel;c.squares=original.squares;
        CutawayChecks.set(f.data().levelsData,"chunk",c);for(IsoGridSquare[] row:c.squares)for(IsoGridSquare q:row)if(q!=null)q.chunk=c;
        for(int i=1;i<64;i++)c.squares[1][i]=null;
        FBORenderLevels[] render=new FBORenderLevels[4];for(int p=0;p<4;p++)render[p]=new FBORenderLevels(p,c);
        declared(c,"renderLevels",render);for(FBORenderLevels r:render)r.setOnScreen(1,true);
        State state=new State();state.data=f.data();state.zero=CutawayChecks.fixture("empty-zero",0,2).data();
        CutawayChecks.set(state.zero,"level",0);state.zero.levelsData=state.data.levelsData;state.byLevel.put(0,state.zero);state.byLevel.put(1,state.data);c.cutawayCacheState=state;return c;
    }
    static PlayerData player(IsoChunk c,int x1,int x2) {
        PlayerData p=new PlayerData();p.onScreenChunks.add(c);
        p.occludedGridX1=x1;p.occludedGridY1=21;p.occludedGridX2=x2;p.occludedGridY2=28;
        p.occludedGrid=new int[(x2-x1+1)*8];Arrays.fill(p.occludedGrid,-32);return p;
    }
    static void run(Cell c,int p,boolean caching){fast=caching;Arrays.fill(c.perPlayerData[p].occludedGrid,-32);PinnedCache.calculateOccludingSquares(c,p);}
    static void originalFailures()throws Exception {
        // Native producer: the same above-ground square is hidden from a basement camera,
        // rendered from a camera on its floor. No flag array mutation is invented as a stimulus.
        IsoChunk target=chunk();IsoGridSquare square=target.squares[1][0];FBORenderCutaways cut=producer();
        IsoCamera.frameState.camCharacterZ=-1;boolean lower=cut.shouldRenderBuildingSquare(0,square);
        IsoCamera.frameState.camCharacterZ=1;boolean same=cut.shouldRenderBuildingSquare(1,square);
        CutawayChecks.require(!lower && same,"native player-specific producer");
        ChunkLevelData data=state(target).data;
        Arrays.fill(data.squareFlags[0],(byte)0);Arrays.fill(data.squareFlags[1],(byte)0);
        data.squareFlags[0][0]=(byte)(lower?1:0);data.squareFlags[1][0]=(byte)(same?1:0);
        Cell cell=new Cell();cell.perPlayerData[0]=player(target,13,20);cell.perPlayerData[1]=player(target,13,20);
        for(int p=0;p<2;p++){target.getRenderLevels(p).invalidateLevel(1,2048L);run(cell,p,true);target.getRenderLevels(p).clearDirty(1,1.0f);}
        CutawayChecks.require(!target.getRenderLevels(0).isDirty(1,1.0f),"native clean lifecycle");
        // Another level can trigger the frame-wide rebuild while this target stays clean.
        IsoChunk trigger=chunk();trigger.wx=5;trigger.squares[1][0].x=40;for(int p=0;p<2;p++)cell.perPlayerData[p].onScreenChunks.add(trigger);
        trigger.getRenderLevels(0).invalidateLevel(1,2048L);
        CutawayChecks.require(trigger.getRenderLevels(0).isDirty(1,1.0f),"independent native trigger");
        run(cell,0,true);int fastHeight=cell.perPlayerData[0].occludedGrid[0];
        run(cell,0,false);int nativeHeight=cell.perPlayerData[0].occludedGrid[0];
        CutawayChecks.require(fastHeight==1 && nativeHeight==-32,"reachable player cache contamination");
        System.out.println("CACHE_PLAYER_REPLAY_MISMATCH native="+nativeHeight+" cached="+fastHeight+" producer="+lower+"/"+same);
        // Ordinary single-player camera clipping changes native clipped-mask/change detection.
        cell.perPlayerData[0]=player(target,13,20);data.squareFlags[0][0]=1;
        target.getRenderLevels(0).invalidateLevel(1,2048L);run(cell,0,true);target.getRenderLevels(0).clearDirty(1,1.0f);
        long before=data.occludingSquares[0];cell.perPlayerData[0]=player(target,14,21);invalidates=0;
        run(cell,0,true);int fastInvalidates=invalidates;long fastMask=data.occludingSquares[0];
        invalidates=0;run(cell,0,false);int nativeInvalidates=invalidates;long nativeMask=data.occludingSquares[0];
        CutawayChecks.require(before==1 && fastMask==1 && nativeMask==0 && fastInvalidates==0 && nativeInvalidates==1,"clip/change lifecycle mismatch");
        System.out.println("CACHE_CLIP_CHANGE_MISMATCH nativeMask="+nativeMask+" cachedMask="+fastMask+" nativeInvalidates="+nativeInvalidates+" cachedInvalidates="+fastInvalidates);

    }

    static int repairedComparisons,originalDivergences;
    static IsoChunk worldChunk(int z,long bits)throws Exception {
        IsoChunk c=CutawayChecks.raw(IsoChunk.class);c.wx=2;c.wy=3;c.minLevel=Math.max(-32,z-1);c.maxLevel=z;
        c.squares=new IsoGridSquare[z-c.minLevel+1][64];
        State state=new State();
        ChunkLevelsData levels=CutawayChecks.raw(ChunkLevelsData.class);CutawayChecks.set(levels,"chunk",c);
        for(int at=c.minLevel;at<=z;at++) {
            ChunkLevelData d=CutawayChecks.raw(ChunkLevelData.class);CutawayChecks.set(d,"level",at);d.levelsData=levels;
            CutawayChecks.set(d,"squareFlags",new byte[4][64]);CutawayChecks.set(d,"occludingSquares",new long[4]);
            state.byLevel.put(at,d);if(at==z)state.data=d;
        }
        for(int bit=0;bit<64;bit++)if((bits&(1L<<bit))!=0) {
            IsoGridSquare q=CutawayChecks.raw(IsoGridSquare.class);q.chunk=c;q.x=c.wx*8+bit%8;q.y=c.wy*8+bit/8;q.z=z;
            declared(q,"visionMatrix",-1);c.squares[z-c.minLevel][bit]=q;
            for(int p=0;p<4;p++)state.data.squareFlags[p][bit]=(byte)(p==1 && bit%2==0?0:1);
        }
        FBORenderLevels[] render=new FBORenderLevels[4];for(int p=0;p<4;p++) {
            render[p]=new FBORenderLevels(p,c);for(int at=c.minLevel;at<=z;at++)render[p].setOnScreen(at,true);
        }
        declared(c,"renderLevels",render);c.cutawayCacheState=state;return c;
    }
    static PlayerData view(IsoChunk c,int z,int dx,int dy) {
        PlayerData p=new PlayerData();p.onScreenChunks.add(c);
        p.occludedGridX1=16-z*3+dx;p.occludedGridY1=24-z*3+dy;
        p.occludedGridX2=p.occludedGridX1+7;p.occludedGridY2=p.occludedGridY1+7;p.occludedGrid=new int[64];return p;
    }
    static void dirty(IsoChunk c,int z,int p){c.getRenderLevels(p).invalidateLevel(z,2048L);}
    static void clean(IsoChunk c,int z,int p){c.getRenderLevels(p).clearDirty(z,1.0f);}
    static String step(int mode,Cell cell,int p) {
        fast=mode!=0;invalidates=0;invalidated.clear();Arrays.fill(cell.perPlayerData[p].occludedGrid,-32);
        if(mode==2)RepairedCache.calculateOccludingSquares(cell,p);else PinnedCache.calculateOccludingSquares(cell,p);
        StringBuilder out=new StringBuilder(Arrays.toString(cell.perPlayerData[p].occludedGrid));
        for(IsoChunk c:cell.perPlayerData[p].onScreenChunks)for(int z=c.minLevel;z<=c.maxLevel;z++)out.append('|').append(Arrays.toString(state(c).byLevel.get(z).occludingSquares));
        return out+"|"+invalidated;
    }
    static List<String> scenario(int mode,int z,long bits)throws Exception {
        IsoChunk c=worldChunk(z,bits),trigger=worldChunk(z,0);trigger.wx=5;
        Cell cell=new Cell();for(int p=0;p<2;p++){cell.perPlayerData[p]=view(c,z,0,0);cell.perPlayerData[p].onScreenChunks.add(trigger);dirty(trigger,z,p);}
        ArrayList<String> output=new ArrayList<>();
        for(int p=0;p<2;p++){dirty(c,z,p);output.add(step(mode,cell,p));clean(c,z,p);}
        output.add(step(mode,cell,0));output.add(step(mode,cell,1));
        int[][] clips={{1,0},{0,1},{-7,-7},{8,8},{0,0}};
        for(int[] xy:clips) {
            cell.perPlayerData[0]=view(c,z,xy[0],xy[1]);cell.perPlayerData[0].onScreenChunks.add(trigger);
            output.add(step(mode,cell,0));
        }
        // Dirty native fallback must see live preparation flags and vision/below-square state.
        ChunkLevelData data=state(c).data;
        for(int i=0;i<64;i++)data.squareFlags[0][i]^=1;dirty(c,z,0);output.add(step(mode,cell,0));clean(c,z,0);
        for(int i=0;i<64;i++)data.squareFlags[0][i]^=1;dirty(c,z,0);output.add(step(mode,cell,0));clean(c,z,0);
        for(IsoGridSquare q:c.squares[z-c.minLevel])if(q!=null)declared(q,"visionMatrix",0);
        if(z>-32)for(int bit=0;bit<64;bit++)if(c.squares[z-c.minLevel][bit]!=null){IsoGridSquare q=CutawayChecks.raw(IsoGridSquare.class);q.chunk=c;q.x=16+bit%8;q.y=24+bit/8;q.z=z-1;c.squares[z-c.minLevel-1][bit]=q;}
        dirty(c,z,0);output.add(step(mode,cell,0));clean(c,z,0);output.add(step(mode,cell,0));
        if(z>-32)Arrays.fill(c.squares[z-c.minLevel-1],null);
        dirty(c,z,0);output.add(step(mode,cell,0));clean(c,z,0);output.add(step(mode,cell,0));
        // Reset the exact cache-validity state that resetForStore owns; full chunk unload is outside this no-game fixture.
        State state=state(c);state.maskSet=0;RepairedCache.resetValidity(c);for(long valid:state.repairedSet)CutawayChecks.require(valid==0,"all player validity cleared");
        for(int i=0;i<64;i++)data.squareFlags[0][i]=0;
        output.add(step(mode,cell,0));
        for(int i=0;i<64;i++)data.squareFlags[1][i]=0;output.add(step(mode,cell,1));
        for(int i=0;i<64;i++)data.squareFlags[0][i]=1;
        dirty(c,z,0);output.add(step(mode,cell,0));clean(c,z,0);output.add(step(mode,cell,0));
        for(int i=0;i<64;i++)data.squareFlags[1][i]=1;dirty(c,z,1);output.add(step(mode,cell,1));clean(c,z,1);output.add(step(mode,cell,1));
        return output;
    }
    static void repairedCorrectness()throws Exception {
        long[] masks={0,1,1L<<31,1L<<32,1L<<63,-1L,0x8100000180000001L};
        for(int z=-32;z<=31;z++)for(long bits:masks) {
            List<String> nativeOutput=scenario(0,z,bits),original=scenario(1,z,bits),repaired=scenario(2,z,bits);
            for(int i=0;i<nativeOutput.size();i++) {
                CutawayChecks.require(nativeOutput.get(i).equals(repaired.get(i)),"repaired z="+z+" bits="+bits+" step="+i+" native="+nativeOutput.get(i)+" repaired="+repaired.get(i));
                repairedComparisons++;if(!nativeOutput.get(i).equals(original.get(i)))originalDivergences++;
            }
        }
        CutawayChecks.require(originalDivergences>0,"original divergence sensitivity");
        System.out.println("REPAIRED_CACHE_EQUIVALENT comparisons="+repairedComparisons+" originalDivergences="+originalDivergences+" z=-32..31 bits=0/31/32/63/all/sparse");
    }
    public static void main(String[] a)throws Exception {
        originalFailures();repairedCorrectness();
        System.out.println("CACHE_CHECKS_PASS native-producer real-native-dirty complete-pinned-caller repaired-clipped-legacy-mask");
    }
}
