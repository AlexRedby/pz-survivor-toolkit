import java.lang.reflect.*;
import java.util.*;
import sun.misc.Unsafe;
import pzresearch.AggregationScope;
import zombie.core.TilePropertyAliasMap;
import zombie.core.properties.IsoPropertyType;
import zombie.core.properties.PropertyContainer;
import zombie.iso.*;
import zombie.iso.SpriteDetails.*;
import zombie.iso.sprite.IsoSprite;
import zombie.iso.zones.Zone;
import zombie.network.GameServer;
import zombie.pathfind.CollideWithObstaclesPoly;

/** Real native objects/properties and real guarded method bodies; no game loop or native render context. */
public final class AggregationChecks {
    static final Unsafe U;static final Method CANDIDATE;
    static int checks;static long expectedHits;static boolean reuseReached;
    static {
        try {Field f=Unsafe.class.getDeclaredField("theUnsafe");f.setAccessible(true);U=(Unsafe)f.get(null);
            Method m;try{m=IsoGridSquare.class.getMethod("pztestRecalcProperties");}catch(NoSuchMethodException e){m=null;}CANDIDATE=m;}
        catch(Exception e){throw new ExceptionInInitializerError(e);}
    }
    static <T>T raw(Class<T> c)throws Exception{return c.cast(U.allocateInstance(c));}
    static Field field(Class<?> c,String n)throws Exception{while(c!=null){try{Field f=c.getDeclaredField(n);f.setAccessible(true);return f;}catch(NoSuchFieldException e){c=c.getSuperclass();}}throw new NoSuchFieldException(n);}
    static void set(Object o,String n,Object v)throws Exception{field(o.getClass(),n).set(o,v);}
    static Object get(Object o,String n)throws Exception{return field(o.getClass(),n).get(o);}
    static void require(boolean b,String m){if(!b)throw new AssertionError(m);}
    static final class Fixture {
        final IsoGridSquare s;final IsoChunk chunk;final IsoChunkLevel level;
        Fixture(int seed,int kind)throws Exception {
            s=new IsoGridSquare(null,null,seed%8,seed%8,0);s.zone=raw(Zone.class);
            s.roomId=(kind&1)==0?-1:4;s.haveRoof=(kind&2)!=0;
            set(s,"burntOut",(kind&4)!=0);s.propertiesDirty=(kind&8)!=0;
            chunk=raw(IsoChunk.class);chunk.loaded=(kind&16)==0;chunk.minLevel=0;chunk.maxLevel=0;
            level=new IsoChunkLevel();level.chunk=chunk;level.level=0;
            set(chunk,"levels",new IsoChunkLevel[]{level});set(chunk,"lightCheck",new boolean[4]);
            set(chunk,"collision",new CollideWithObstaclesPoly.ChunkData());s.chunk=chunk;
            if((kind&32)!=0)s.chunk=null;
            if((kind&64)!=0){IsoWaterGeometry water=new IsoWaterGeometry();set(water,"hasWater",true);set(s,"water",water);}
            if((kind&128)!=0)set(s,"rainDrop",raw(zombie.iso.objects.IsoRaindrop.class));
            if((kind&256)!=0)set(s,"rainSplash",raw(zombie.iso.objects.IsoRainSplash.class));
            if((kind&512)==0)set(s,"puddles",new IsoPuddlesGeometry());
            PropertyContainer p=s.getProperties();p.set(IsoFlagType.solid);p.set(IsoFlagType.windowN);
            p.set("Surface","90",false);p.set("ItemHeight","100",false);p.CreateKeySet();
            p.set(IsoPropertyType.FUEL_AMOUNT,(seed&1)==0?"10":"20",false);
            int objectCount=(kind&2048)!=0?32:seed%7;
            for(int i=0;i<objectCount;i++){
                IsoObject o=new IsoObject();IsoSprite sprite=new IsoSprite();o.sprite=sprite;
                sprite.setTileType(i%3==0?IsoObjectType.tree:IsoObjectType.normal);
                sprite.forceRender=(seed+i)%4==0;PropertyContainer sp=sprite.getProperties();
                long bits=new Random(seed*31L+i*73L+kind).nextLong();
                IsoFlagType[] flags={IsoFlagType.solidfloor,IsoFlagType.water,IsoFlagType.solidtrans,
                    IsoFlagType.transparentFloor,IsoFlagType.HoppableN,IsoFlagType.HoppableW,IsoFlagType.canPathN,
                    IsoFlagType.canPathW,IsoFlagType.collideN,IsoFlagType.collideW,IsoFlagType.cutN,IsoFlagType.cutW,
                    IsoFlagType.transparentN,IsoFlagType.transparentW,IsoFlagType.WallSE,IsoFlagType.vegitation};
                for(int f=0;f<flags.length;f++)if((bits&(1L<<f))!=0)sp.set(flags[f]);
                if((seed+i)%19==0)sp.set(IsoFlagType.blueprint);
                sp.set("Surface",i%2==0?"10":"20",false);sp.set("ItemHeight","20",false);
                sp.set("SlopedSurfaceDirection",i%2==0?"N":"S",false);sp.set("SlopedSurfaceHeightMin","0",false);
                sp.set("SlopedSurfaceHeightMax","20",false);sp.set("IsTable","true",false);
                if((seed+i)%3!=0)sp.CreateKeySet();o.setSquare(s);s.getObjects().add(o);
            }
        }
        void resetEffects()throws Exception {
            Arrays.fill(level.lightCheck,false);set(level,"physicsCheck",false);
            Arrays.fill((boolean[])get(chunk,"lightCheck"),false);set(get(chunk,"collision"),"clear",false);
            Object puddles=get(s,"puddles");if(puddles!=null)set(puddles,"recalc",false);
            set(s,"cachedIsFree",true);
        }
    }
    static String snapshot(Fixture f)throws Exception{return snapshot(f.s,f.chunk,f.level);}
    static String snapshot(IsoGridSquare s,IsoChunk chunk,IsoChunkLevel level)throws Exception {
        PropertyContainer p=s.getProperties();TreeMap<Short,Short> entries=new TreeMap<>();
        for(short k:p.keys())entries.put(k,p.get(k));
        StringJoiner flags=new StringJoiner(",");for(IsoFlagType flag:IsoFlagType.values())if(p.has(flag))flags.add(flag.name());
        List<Object> values=new ArrayList<>();values.add(entries);values.add(flags.toString());
        for(String name:new String[]{"cachedIsFree","hasTypes","hasTree","isExteriorCache","isSolidFloorCache","isVegitationCache","propertiesDirty","solidFloorCached","solidFloor"})values.add(name+"="+get(s,name));
        values.add("zone="+(s.zone!=null));values.add("water="+(get(s,"water")!=null));
        Object puddles=get(s,"puddles");values.add("puddles="+(puddles!=null));values.add("puddle-recalc="+(puddles!=null?get(puddles,"recalc"):"absent"));
        values.add(Arrays.toString(level.lightCheck));values.add(Arrays.toString((boolean[])get(chunk,"lightCheck")));
        values.add(get(level,"physicsCheck"));values.add(get(get(chunk,"collision"),"clear"));
        // Public surface getters exercise both native and current official lazy cache paths.
        values.add(List.of(p.getSurface(),p.getItemHeight(),p.getStackReplaceTileOffset(),p.isSurfaceOffset(),p.isTable(),p.isTableTop(),
            String.valueOf(p.getSlopedSurfaceDirection()),p.getSlopedSurfaceHeightMin(),p.getSlopedSurfaceHeightMax()));
        for(String name:new String[]{"surface","surfaceFlags","stackReplaceTileOffset","itemHeight","slopedSurfaceDirection","slopedSurfaceHeightMin","slopedSurfaceHeightMax"})values.add(name+"="+get(p,name));
        return values.toString();
    }
    static Throwable call(boolean reduced,IsoGridSquare s) {
        try {if(reduced)CANDIDATE.invoke(s);else s.RecalcProperties();return null;}
        catch(InvocationTargetException e){return e.getCause();}catch(Throwable e){return e;}
    }
    record Result(List<String> states,Map<String,Integer> calls){}
    static Map<String,Integer> effects(){TreeMap<String,Integer> r=new TreeMap<>();AggregationScope.counts().forEach((k,v)->{if(!k.startsWith("aggregate:"))r.put(k,v);});return r;}
    static String thrown(Throwable t){return t==null?"ok":t.getClass().getName()+":"+t.getMessage();}
    static Result run(boolean reduced,int seed,int kind,int repetitions)throws Exception {
        Fixture f=new Fixture(seed,kind);List<String> states=new ArrayList<>();AggregationScope.resetCounts();
        AggregationScope.enter();try {
            for(int i=0;i<repetitions;i++){
                f.resetEffects();Throwable e=call(reduced,f.s);states.add(thrown(e)+"|"+snapshot(f));
                if(e!=null)throw new AssertionError("Unexpected fixture exception: "+thrown(e));
            }
        }finally{AggregationScope.exit();}
        require(!AggregationScope.active() && AggregationScope.retained()==0,"Scope leaked");
        return new Result(states,effects());
    }
    static void pair(int seed,int kind,int reps)throws Exception {
        Result a=run(false,seed,kind,reps),b=run(true,seed,kind,reps);
        require(a.states.equals(b.states),"STATE_MISMATCH seed="+seed+" kind="+kind+"\nBASE "+a.states+"\nCAND "+b.states);
        require(a.calls.equals(b.calls),"SIDE_EFFECT_CALL_MISMATCH seed="+seed+" kind="+kind+"\nBASE "+a.calls+"\nCAND "+b.calls);checks++;
    }
    static void identitiesAndEdits()throws Exception {
        List<String> expected=null;
        for(boolean reduced:new boolean[]{false,true}) {
            Fixture a=new Fixture(4,64),b=new Fixture(12,4); // Same coordinates, different objects, map and flags.
            List<String> states=new ArrayList<>();AggregationScope.enter();
            try {for(int i=0;i<3;i++)for(Fixture f:new Fixture[]{a,b}){
                require(call(reduced,f.s)==null,"Identity initialization/duplicate");states.add(snapshot(f));}}
            finally{AggregationScope.exit();}
            if(expected==null)expected=states;else require(expected.equals(states),"Separate identities with distinct data diverged");
            a.s.getObjects().clear();a.s.getProperties().set(IsoFlagType.solid);a.s.haveRoof=!a.s.haveRoof;
            a.s.roomId=4;set(a.s,"burntOut",true);a.s.getProperties().CreateKeySet();
            AggregationScope.enter();try {require(call(reduced,a.s)==null,"Mutation next scope");}
            finally{AggregationScope.exit();}
            require(!a.s.getProperties().has(IsoFlagType.solid),"Stale map survived a new scope");
            require(a.s.getProperties().has(IsoFlagType.burntOut),"New burnt flag missed");checks++;
        }
    }
    static final class Custom extends IsoObject {
        int gets;boolean fail=true;
        @Override public PropertyContainer getProperties(){gets++;if(fail)throw new IllegalArgumentException("expected object failure");PropertyContainer p=super.getProperties();p.set("Surface",gets%2==0?"10":"20",false);p.CreateKeySet();return p;}
    }
    static void failureCleanup()throws Exception {
        for(boolean reduced:new boolean[]{false,true}){
            Fixture f=new Fixture(3,0);Custom o=new Custom();o.sprite=new IsoSprite();o.sprite.getProperties().set(IsoFlagType.solidfloor);
            f.s.getObjects().add(o);AggregationScope.enter();try {
                Throwable first=call(reduced,f.s);require(first instanceof IllegalArgumentException,"Failure was swallowed: "+thrown(first));
                o.fail=false;require(call(reduced,f.s)==null,"Recovery failed");
                require(call(reduced,f.s)==null,"Recovery duplicate failed");require(o.gets==3,"Unknown getter was skipped");
            }finally{AggregationScope.exit();}
            require(!AggregationScope.active(),"Failed scope retained");checks++;
            // Failure after aggregation: preserve native exception and invalidate cached masks.
            Fixture g=new Fixture(2,0);set(g.chunk,"collision",null);AggregationScope.enter();
            try {
                require(call(reduced,g.s) instanceof NullPointerException,"Suffix exception swallowed");
                set(g.chunk,"collision",new CollideWithObstaclesPoly.ChunkData());
                g.s.getObjects().clear();require(call(reduced,g.s)==null,"Suffix failure recovery");
                require(!g.s.getProperties().has(IsoFlagType.solidfloor),"Aggregation cache survived suffix failure");
            }finally{AggregationScope.exit();}checks++;
        }
    }
    static void boundedAndNested()throws Exception {
        AggregationScope.enter();try {
            Fixture f=new Fixture(2,0);require(call(true,f.s)==null,"Initial scope");
            AggregationScope.enter();try {require(call(true,f.s)==null,"Nested fallback");}finally{AggregationScope.exit();}
            f.s.getObjects().clear();require(call(true,f.s)==null,"Outer invalidation fallback");
            require(!f.s.getProperties().has(IsoFlagType.solidfloor),"Nested cache invalidation missed edit");
        }finally{AggregationScope.exit();}checks++;
        AggregationScope.enter();try {
            Fixture first=null;for(int i=0;i<AggregationScope.LIMIT+1;i++){
                Fixture f=new Fixture(i,0);if(first==null)first=f;require(call(true,f.s)==null,"Scratch overflow input");}
            require(AggregationScope.retained()==0,"Overflow retained references");
            first.s.getObjects().clear();require(call(true,first.s)==null,"Overflow fallback");
        }finally{AggregationScope.exit();}checks++;
    }
    static void aliases(){
        HashMap<String,ArrayList<String>> defs=new HashMap<>();
        for(String n:new String[]{"Surface","ItemHeight","StackReplaceTileOffset","SlopedSurfaceDirection","SlopedSurfaceHeightMin","SlopedSurfaceHeightMax","IsSurfaceOffset","IsTable","IsTableTop",IsoPropertyType.FUEL_AMOUNT.getName()})
            defs.put(n,new ArrayList<>(List.of("0","1","10","20","90","100","N","S","true","false")));
        TilePropertyAliasMap.instance.Generate(defs);
    }
    public static void main(String[] args)throws Exception {
        aliases();
        if(Boolean.getBoolean("recalc.official")) {
            Class<?> config=Class.forName("pzopt.Config");
            for(String flag:new String[]{"HANDOFF_RECALC_FAST","HANDOFF_RECALC_MEMO","HANDOFF_RECALC_PARALLEL"})require(!config.getField(flag).getBoolean(null),"Unexpected active profile "+flag);
        }
        for(boolean server:new boolean[]{false,true}){GameServer.server=server;
            for(int kind=0;kind<1024;kind+=17)for(int seed=0;seed<14;seed++)pair(seed,kind,4);
        }
        GameServer.server=false;for(int seed=0;seed<12;seed++)pair(seed,2048|64|128,5);
        identitiesAndEdits();failureCleanup();boundedAndNested();
        Fixture noScope=new Fixture(4,0);String before=snapshot(noScope);require(call(true,noScope.s)==null,"No-scope fallback");
        if(Boolean.getBoolean("recalc.official")) {
            Field capture=Class.forName("pzopt.HandoffRecalc").getField("capture");long oldHits=AggregationScope.hits;
            capture.setBoolean(null,true);AggregationScope.enterCandidate();try {
                Fixture f=new Fixture(3,0);require(call(true,f.s)==null && call(true,f.s)==null,"Upstream capture fallback");
                require(AggregationScope.hits==oldHits && AggregationScope.retained()==0,"Capture branch cached properties");
            }finally{AggregationScope.exit();capture.setBoolean(null,false);}checks++;
        }
        require(AggregationScope.hits>0,"Reuse never exercised");
        System.out.println("AGGREGATION_SEMANTICS_PASS checks="+checks+" hits="+AggregationScope.hits+" misses="+AggregationScope.misses+" invalidations="+AggregationScope.invalidations+" scopes="+AggregationScope.scopes);
        System.out.println("LIMITATIONS isolated RecalcProperties sequences; no RecalcAll closure, worker/Host process isolation, runtime or timing qualification");
    }
}
