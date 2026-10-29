import java.lang.reflect.*;
import java.security.MessageDigest;
import java.util.*;
import pzresearch.AggregationScope;
import zombie.characters.IsoPlayer;
import zombie.core.properties.PropertyContainer;
import zombie.iso.*;
import zombie.iso.SpriteDetails.*;
import zombie.iso.sprite.IsoSprite;
import zombie.iso.zones.Zone;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.pathfind.CollideWithObstaclesPoly;

/** Executes the entire actual native/selected-official neighbor operation, exact cellGetSquare callback. */
public final class NeighborChecks {
    static int checks;static long checksum;
    static void set(Object o,String n,Object v)throws Exception{AggregationChecks.set(o,n,v);}
    static <T>T raw(Class<T> c)throws Exception{return AggregationChecks.raw(c);}
    static void require(boolean b,String m){AggregationChecks.require(b,m);}
    static final class World {
        final IsoCell cell;final IsoChunk[] chunks=new IsoChunk[4];
        final List<IsoGridSquare> squares=new ArrayList<>();
        final IdentityHashMap<IsoGridSquare,Integer> ids=new IdentityHashMap<>();
        final IsoGridSquare center;
        World(int shape,int seed)throws Exception {
            GameServer.server=false;GameClient.client=false;IsoPlayer.numPlayers=1;
            IsoMetaGrid meta=IsoWorld.instance.metaGrid;meta.minX=0;meta.minY=0;meta.maxX=1;meta.maxY=1;
            set(meta,"width",2);set(meta,"height",2);set(meta,"grid",new IsoMetaCell[2][2]);
            cell=raw(IsoCell.class);IsoChunkMap map=raw(IsoChunkMap.class);
            map.worldX=IsoChunkMap.chunkGridWidth/2;map.worldY=IsoChunkMap.chunkGridWidth/2;
            IsoChunk[] mapChunks=new IsoChunk[IsoChunkMap.chunkGridWidth*IsoChunkMap.chunkGridWidth];
            for(int cy=0;cy<2;cy++)for(int cx=0;cx<2;cx++){
                IsoChunk chunk=raw(IsoChunk.class);chunk.wx=cx;chunk.wy=cy;chunk.loaded=true;chunk.loadedBits=2;
                set(chunk,"loadId",(short)1);chunk.minLevel=-1;chunk.maxLevel=1;
                IsoChunkLevel[] levels=new IsoChunkLevel[3];chunk.squares=new IsoGridSquare[3][];
                for(int z=-1;z<=1;z++){
                    IsoChunkLevel level=new IsoChunkLevel();level.chunk=chunk;level.level=z;
                    levels[z+1]=level;chunk.squares[z+1]=level.squares;
                }
                set(chunk,"levels",levels);set(chunk,"lightCheck",new boolean[4]);
                set(chunk,"collision",new CollideWithObstaclesPoly.ChunkData());chunks[cy*2+cx]=chunk;
                mapChunks[cy*IsoChunkMap.chunkGridWidth+cx]=chunk;
            }
            set(map,"chunksSwapB",mapChunks);set(map,"chunksSwapA",mapChunks.clone());
            set(cell,"chunkMap",new IsoChunkMap[]{map});IsoWorld.instance.currentCell=cell;
            int centerX=shape==1?3:7,centerY=shape==1?3:7;
            Random r=new Random(seed);
            Zone zone=raw(Zone.class);
            for(int z=-1;z<=1;z++)for(int y=centerY-2;y<=centerY+2;y++)for(int x=centerX-2;x<=centerX+2;x++) {
                if(shape==2 && r.nextInt(4)==0 && !(x==centerX && y==centerY && z==0))continue;
                IsoGridSquare s=new IsoGridSquare(null,null,x,y,z);s.zone=shape==6?null:zone;
                s.roomId=(x+y+seed)%3==0?8:-1;s.haveRoof=(x+z+seed)%4==0;s.propertiesDirty=shape!=7 || r.nextBoolean();
                set(s,"burntOut",(x+y+z+seed)%7==0);
                IsoChunk chunk=chunks[y/8*2+x/8];s.chunk=chunk;chunk.squares[z+1][y%8*8+x%8]=s;
                ids.put(s,squares.size());squares.add(s);
                PropertyContainer stale=s.getProperties();stale.set(IsoFlagType.solid);stale.set(IsoFlagType.water);
                stale.set("Surface","90",false);stale.set("ItemHeight","100",false);stale.CreateKeySet();
                int count=shape==0?0:shape==3?12:2;
                for(int i=0;i<count;i++) {
                    IsoObject o=new IsoObject();o.sprite=new IsoSprite();o.setSquare(s);
                    IsoObjectType type=IsoObjectType.normal;
                    if(shape==4){IsoObjectType[] types={IsoObjectType.stairsTN,IsoObjectType.stairsMN,IsoObjectType.stairsBN,IsoObjectType.stairsTW,IsoObjectType.stairsMW,IsoObjectType.stairsBW};type=types[Math.floorMod(x+y+z+i,6)];}
                    else if(i%3==1)type=IsoObjectType.tree;
                    o.sprite.setTileType(type);o.sprite.forceRender=(i+x+seed)%5==0;
                    PropertyContainer p=o.sprite.getProperties();p.set(IsoFlagType.solidfloor);
                    if((x+y+seed+i)%3==0)p.set(IsoFlagType.collideN);
                    if((x+z+seed+i)%4==0){p.set(IsoFlagType.cutW);p.set(IsoFlagType.transparentW);}
                    if((x+y+z+i)%7==0){p.set(IsoFlagType.HoppableN);p.set(IsoFlagType.canPathN);}
                    if((x+y+i)%5==0)p.set(IsoFlagType.water);
                    if(i%2==1)p.set(IsoFlagType.vegitation);
                    p.set("Surface",i%2==0?"10":"20",false);p.set("ItemHeight","20",false);
                    if(shape==5 || shape==4){p.set("SlopedSurfaceDirection",i%2==0?"N":"S",false);p.set("SlopedSurfaceHeightMin","0",false);p.set("SlopedSurfaceHeightMax","20",false);}
                    p.CreateKeySet();s.getObjects().add(o);
                }
                set(s,"puddles",new IsoPuddlesGeometry());
            }
            center=cell.getGridSquare(centerX,centerY,0);
            require(center!=null,"Native world mapping failed");
            // Native callbacks must return the exact same identities, including across chunk borders/levels.
            require(IsoGridSquare.cellGetSquare.getGridSquare(centerX,centerY,0)==center,"Not the native cell getter");
            require(cell.getGridSquare(centerX+1,centerY,0)==chunks[(centerY/8)*2+(centerX+1)/8].getGridSquare((centerX+1)%8,centerY%8,0),"Border lookup mismatch");
            if(shape==8){
                // Native backing arrays can contain aliases. Keep first coordinates; keying by position would be wrong.
                IsoGridSquare alias=cell.getGridSquare(centerX+1,centerY,0);
                chunks[(centerY+1)/8*2+(centerX+1)/8].squares[1][(centerY+1)%8*8+(centerX+1)%8]=alias;
            }
            if(shape==9){ // A not-yet-loaded center chunk causes the real getter to return null, not a mock substitute.
                center.chunk.loaded=false;
            }
            for(IsoGridSquare s:squares){
                // Seed native nav with stale values so doGridNav's updates are observed.
                s.setAdjacentSquare(IsoDirections.N,center);s.setAdjacentSquare(IsoDirections.S,center);
                s.setAdjacentSquare(IsoDirections.E,center);s.setAdjacentSquare(IsoDirections.W,center);
            }
        }
        String ref(Object o){return o==null?"null":String.valueOf(ids.get((IsoGridSquare)o));}
        List<String> snapshot()throws Exception {
            List<String> result=new ArrayList<>();
            for(IsoGridSquare s:squares) {
                IsoChunk c=s.chunk;IsoChunkLevel level=((IsoChunkLevel[])AggregationChecks.get(c,"levels"))[s.z-c.minLevel];
                StringBuilder row=new StringBuilder(AggregationChecks.snapshot(s,c,level));
                for(String n:new String[]{"collideMatrix","pathMatrix","visionMatrix"})row.append('|').append(n).append('=').append(AggregationChecks.get(s,n));
                for(String n:new String[]{"w","nw","sw","s","n","ne","se","e","u","d"})row.append('|').append(n).append('=').append(ref(AggregationChecks.get(s,n)));
                row.append("|nav=");for(IsoGridSquare n:(IsoGridSquare[])AggregationChecks.get(s,"nav"))row.append(ref(n)).append(',');
                result.add(row.toString());
            }
            return result;
        }
    }
    record Result(List<String> state,Map<String,Integer> effects,long hits,long clears){}
    static Result run(boolean candidate,int shape,int seed,boolean reverse)throws Exception {
        World w=new World(shape,seed);AggregationScope.resetCounts();long oldHits=AggregationScope.hits;
        if(candidate)AggregationScope.enterCandidate();else AggregationScope.enter();
        Throwable failure;
        try {w.center.RecalcAllWithNeighbours(reverse);failure=null;}catch(Throwable t){failure=t;}
        finally{AggregationScope.exit();}
        if(failure!=null)throw new AssertionError("Native full-operation setup/behavior failed shape="+shape+" candidate="+candidate,failure);
        List<String> state=w.snapshot();Map<String,Integer> effects=AggregationChecks.effects();
        long clears=AggregationScope.counts().entrySet().stream().filter(e->e.getKey().equals("aggregate:method:zombie/core/properties/PropertyContainer.Clear()V")).mapToLong(Map.Entry::getValue).sum();
        return new Result(state,effects,AggregationScope.hits-oldHits,clears);
    }
    public static void main(String[] args)throws Exception {
        // Reuse only initialization of real property aliases and the same direct semantic gate first.
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        AggregationChecks.main(new String[0]);
        long hits=0,baselineClears=0,candidateClears=0;
        for(int shape:new int[]{0,1,2,3,4,5,6,7,9})for(int seed=0;seed<8;seed++)for(boolean reverse:new boolean[]{false,true}) {
            Result a=run(false,shape,seed,reverse),b=run(true,shape,seed,reverse);
            if(!a.state.equals(b.state)){
                int at=0;while(at<a.state.size() && a.state.get(at).equals(b.state.get(at)))at++;
                throw new AssertionError("NEIGHBOR_STATE_MISMATCH shape="+shape+" seed="+seed+" reverse="+reverse+" index="+at+"\nBASE "+a.state.get(at)+"\nCAND "+b.state.get(at));
            }
            require(a.effects.equals(b.effects),"NEIGHBOR_SUFFIX_COUNTS shape="+shape+" seed="+seed+" reverse="+reverse+"\nBASE "+a.effects+"\nCAND "+b.effects);
            checks++;hits+=b.hits;baselineClears+=a.clears;candidateClears+=b.clears;checksum+=a.state.hashCode();
        }
        require(hits>0,"Full operation never reused aggregation");
        System.out.println("NEIGHBOR_SEMANTICS_PASS checks="+checks+" hits="+hits+" aggregate_clears="+baselineClears+"/"+candidateClears+" checksum="+checksum);
        System.out.println("LIMITATIONS synchronous isolated native cell, SP getter path; no native workers/Host packet dispatch or runtime admission");
    }
}
