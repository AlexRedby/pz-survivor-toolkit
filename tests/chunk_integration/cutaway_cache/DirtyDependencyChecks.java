import java.lang.reflect.*;
import sun.misc.Unsafe;
import java.util.*;
import zombie.core.PerformanceSettings;
import zombie.iso.*;
import zombie.iso.SpriteDetails.IsoFlagType;
import zombie.core.properties.PropertyContainer;
import zombie.iso.fboRenderChunk.*;
import zombie.iso.fboRenderChunk.FBORenderCutaways.*;

/** API-level native producer regression; no whole-game reachability claim. */
public final class DirtyDependencyChecks {
    static final Unsafe U;
    static {try {Field f=Unsafe.class.getDeclaredField("theUnsafe");f.setAccessible(true);U=(Unsafe)f.get(null);}catch(Exception e){throw new ExceptionInInitializerError(e);}}
    static <T>T raw(Class<T> type)throws Exception{return type.cast(U.allocateInstance(type));}
    static void set(Object object,String name,Object value)throws Exception {Field f=object.getClass().getField(name);f.setAccessible(true);f.set(object,value);}
    static void require(boolean condition,String message){if(!condition)throw new AssertionError(message);}
    static void field(Object o,String name,Object value)throws Exception {Field f=o.getClass().getDeclaredField(name);f.setAccessible(true);f.set(o,value);}
    record World(IsoChunk c,IsoGridSquare upper,IsoGridSquare lower,ChunkLevelData data,FBORenderLevels levels){}
    static World world()throws Exception {
        IsoChunk c=raw(IsoChunk.class);c.wx=2;c.wy=3;c.minLevel=1;c.maxLevel=2;c.jobType=IsoChunk.JobType.None;
        c.squares=new IsoGridSquare[2][64];IsoGridSquare[] pair={raw(IsoGridSquare.class),raw(IsoGridSquare.class)};
        for(int i=0;i<2;i++) {IsoGridSquare s=pair[i];s.x=16;s.y=24;s.z=i+1;s.chunk=c;field(s,"properties",new PropertyContainer());c.squares[i][0]=s;}
        ChunkLevelData d=raw(ChunkLevelData.class);set(d,"level",2);set(d,"squareFlags",new byte[4][64]);d.squareFlags[0][0]=1;set(d,"occludingSquares",new long[4]);
        ChunkLevelsData ld=raw(ChunkLevelsData.class);set(ld,"chunk",c);d.levelsData=ld;
        FBORenderLevels[] levels=new FBORenderLevels[4];for(int p=0;p<4;p++){levels[p]=new FBORenderLevels(p,c);levels[p].setOnScreen(1,true);levels[p].setOnScreen(2,true);levels[p].clearDirty(1,1f);levels[p].clearDirty(2,1f);}
        field(c,"renderLevels",levels);return new World(c,pair[1],pair[0],d,levels[0]);
    }
    static int nativeHeight(World w) {
        int[] h=new int[64];Arrays.fill(h,-32);w.data.calculateOccludingSquares(0,10,18,17,25,h);return h[0];
    }
    public static void main(String[] args)throws Exception {
        PerformanceSettings.fboRenderChunk=true;
        zombie.network.GameServer.server=false;
        require(FBORenderLevels.calculateMinLevel(1)!=FBORenderLevels.calculateMinLevel(2),"cross-group fixture required");
        World w=world();int before=nativeHeight(w);
        w.c.setSquare(0,0,1,null);w.c.invalidateRenderChunkLevel(1,64L);
        int after=nativeHeight(w);
        require(before==-32 && after==2,"below existence affects exact occluder");
        require(w.levels.isDirty(1,1f) && !w.levels.isDirty(2,1f),"native cross-group dirty mismatch");
        System.out.println("NATIVE_SET_SQUARE_GAP before="+before+" after="+after+" dirtyLower="+w.levels.isDirty(1,1f)+" dirtyUpper="+w.levels.isDirty(2,1f));
        w=world();final World fixed=w;IsoGridSquare.GetSquare getter=(x,y,z)->x!=16 || y!=24?null:z==2?fixed.upper:z==1?fixed.lower:null;
        w.upper.ReCalculateVisionBlocked(w.lower,getter);before=nativeHeight(w);
        w.lower.getProperties().set(IsoFlagType.blocksight);w.upper.ReCalculateVisionBlocked(w.lower,getter);w.lower.invalidateRenderChunkLevel(64L);
        after=nativeHeight(w);
        require(before==-32 && after==2,"native vision producer affects exact occluder");
        require(w.upper.getVisionMatrix(0,0,-1) && w.levels.isDirty(1,1f) && !w.levels.isDirty(2,1f),"native vision does not invalidate upper group");
        System.out.println("NATIVE_VISION_PRODUCER_GAP before="+before+" after="+after+" downwardVision="+w.upper.getVisionMatrix(0,0,-1)+" dirtyLower="+w.levels.isDirty(1,1f)+" dirtyUpper="+w.levels.isDirty(2,1f));
        System.out.println("DIRTY_DEPENDENCY_CHECKS_PASS gameplay_reachability_proved=false");
    }
}
