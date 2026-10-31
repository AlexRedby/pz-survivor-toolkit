package toolkit.lootresolved.runtime;

import java.lang.management.ManagementFactory;
import java.lang.reflect.*;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import com.sun.management.ThreadMXBean;
import se.krka.kahlua.vm.KahluaTable;
import toolkit.lootresolved.bootstrap.*;
import zombie.SandboxOptions;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.core.random.Rand;
import zombie.inventory.*;
import zombie.inventory.ItemPickerJava.*;
import zombie.inventory.types.*;
import zombie.iso.*;
import zombie.network.*;
import zombie.scripting.ScriptManager;
import zombie.scripting.objects.*;

/** Two bounded whole-roll groups. All proof, serialization and disposal occur outside clocks. */
final class OperationsMain {
    private static final int WARMUP=64, PAIRS=24, LIMIT=4096;
    private static String status="not-run",failure="";
    private static long windowId;
    private static final StringBuilder rows=new StringBuilder("phase\tgroup\tpair\torder\tvariant\tbatch\twindow_id\twall_start\twall_end\tcpu_start\tcpu_end\tallocated\tselections\tcreated\tincrements\tnull_returns\tdigest\tnext_rng\tcreated_types\tcold_types\tcleanup\n");
    private static final StringBuilder inputs=new StringBuilder();
    private static final Set<String> types=new TreeSet<>(), warmTypes=new TreeSet<>();
    private static final Map<String,Item> scripts=new TreeMap<>();
    private static Object gasMaskBinding;
    private record Group(String name,boolean bag,int batch,ItemPickerContainer distribution) { }
    private record Result(String digest,int rng,int selections,int created,int increments,int nullReturns) { }
    static String status() { return status; }
    private static void require(boolean value,String message) { Main.require(value,"operations-"+message); }
    private static String sha(String text) throws Exception { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(text.getBytes(java.nio.charset.StandardCharsets.UTF_8))); }
    private static void input(String key,Object value) { inputs.append(key).append('=').append(value).append('\n'); }
    private static Object field(Object owner,String name) throws Exception { return Main.field(owner.getClass(),name).get(owner); }
    private static Object nativeGasMaskBinding() throws Exception {
        Object binding=LuaManager.class.getMethod("getFunctionObject",String.class).invoke(null,"ItemCodeOnCreate.onCreateGasMask"), invoker=binding;
        if (invoker!=null && invoker.getClass()==Class.forName("se.krka.kahlua.integration.expose.MultiLuaJavaInvoker",false,OperationsMain.class.getClassLoader())) {
            List<?> all=(List<?>)invoker.getClass().getMethod("getInvokers").invoke(invoker);
            require(all.size()==1,"ambiguous-gasmask-binding");invoker=all.get(0);
        }
        require(invoker!=null && invoker.getClass()==Class.forName("se.krka.kahlua.integration.expose.LuaJavaInvoker",false,OperationsMain.class.getClassLoader()),"gasmask-not-native-invoker");
        Object caller=field(invoker,"caller");
        require(caller.getClass()==Class.forName("se.krka.kahlua.integration.expose.caller.MethodCaller",false,OperationsMain.class.getClassLoader()),"gasmask-not-method-caller");
        Method actual=(Method)field(caller,"method");
        Method expected=Class.forName("zombie.scripting.logic.ItemCodeOnCreate").getDeclaredMethod("onCreateGasMask",Clothing.class);
        require(actual.equals(expected) && Modifier.isStatic(actual.getModifiers()) && actual.getReturnType()==void.class,"gasmask-native-method-differs");
        return binding;
    }
    private static void admit(String name,boolean setup) throws Exception {
        Item item=ScriptManager.instance.FindItem(name);
        require(item!=null,"missing-registered-script:"+name);
        require(item.getItemConfig()==null,"unsupported-itemconfig:"+name);
        require(item.getItemType()!=ItemType.FOOD && item.getItemType()!=ItemType.MAP
            && (setup || item.getItemType()!=ItemType.CONTAINER),"unsupported-food-map-nested-container:"+name);
        String create=item.getLuaCreate();
        require(create==null || create.isEmpty() || create.equals("ItemCodeOnCreate.onCreateGasMask"),"unsupported-OnCreate:"+name);
        if (create!=null && !create.isEmpty()) {
            Object binding=nativeGasMaskBinding();
            require(gasMaskBinding==null || gasMaskBinding==binding,"gasmask-binding-changed");gasMaskBinding=binding;
        }
        Item old=scripts.putIfAbsent(name,item);require(old==null || old==item,"script-identity-changed:"+name);
        types.add(item.getFullName());
    }
    private static String graph(ItemPickerContainer dist,int depth) throws Exception {
        require(dist!=null && depth<=2 && !dist.procedural && Float.isFinite(dist.rolls) && dist.rolls>0 && dist.rolls<=16,"unsupported-distribution");
        require(dist.items!=null && (depth>0 || dist.items.length>0) && dist.items.length<=256,"distribution-entry-bound");
        StringBuilder out=new StringBuilder();
        for (Field f:ItemPickerContainer.class.getFields()) {
            if (Modifier.isStatic(f.getModifiers()) || f.getName().equals("items") || f.getName().equals("junk")) continue;
            Object value=f.get(dist);
            if(value instanceof Collection<?> collection && collection.isEmpty()){out.append(f.getName()).append(":empty;");continue;}
            require(value==null || value instanceof Number || value instanceof Boolean || value instanceof String,"unsupported-distribution-field:"+f.getName());
            out.append(f.getName()).append(':').append(value instanceof Float n?Main.bits(n):String.valueOf(value)).append(';');
        }
        for (ItemPickerItem item:dist.items) {
            require(item!=null && item.itemName!=null && item.itemName.matches("[A-Za-z0-9_.-]+") && Float.isFinite(item.chance) && item.chance>=0,"nonfinite-distribution-entry");
            admit(item.itemName,false);out.append(item.itemName).append(':').append(Main.bits(item.chance)).append(';');
        }
        if (dist.junk!=null) {
            // Empty native junk is allowed; public bag roll still reaches it normally.
            out.append("junk{").append(graph(dist.junk,depth+1)).append('}');
        }
        return out.toString();
    }
    private static String options() throws Exception {
        TreeMap<String,String> values=new TreeMap<>();
        for (Field f:SandboxOptions.class.getFields()) if (f.getName().endsWith("LootNew") || f.getName().equals("rollsMultiplier") || f.getName().equals("lootItemRemovalList")) {
            Object option=f.get(SandboxOptions.instance); Object value=option.getClass().getMethod("getValue").invoke(option);
            values.put(f.getName(),String.valueOf(value));
        }
        require(SandboxOptions.instance.rollsMultiplier.getValue()==1.0 && SandboxOptions.instance.mementoLootNew.getValue()>0
            && SandboxOptions.instance.medicalLootNew.getValue()>0,"ordinary-initial-loot-options-required");
        return values.toString();
    }
    private static void verifyScripts() throws Exception {
        for (var entry:scripts.entrySet()) {
            require(ScriptManager.instance.FindItem(entry.getKey())==entry.getValue(),"live-script-replaced");
            admit(entry.getKey(),entry.getKey().equals("Base.FirstAidKit"));
        }
        if (gasMaskBinding!=null) require(nativeGasMaskBinding()==gasMaskBinding,"live-callback-replaced");
    }
    private static ItemContainer plain(IsoGridSquare square) {
        ItemContainer out=new ItemContainer("crate",null,null);out.setSourceGrid(square);
        require(out.getCapacity()==50 && out.getAcceptItemFunction()==null,"detached-native-capacity-or-acceptance");return out;
    }
    private static void scalar(StringBuilder out,Object value,int depth) {
        require(depth<=8,"moddata-depth");
        if (value==null) out.append('N');
        else if (value instanceof String text) out.append('S').append(text.length()).append(':').append(text);
        else if (value instanceof Number n) out.append('D').append(Main.doubleBits(n.doubleValue()));
        else if (value instanceof Boolean b) out.append(b?'T':'F');
        else if (value instanceof KahluaTable table) {
            TreeMap<String,Object> entries=new TreeMap<>();var iterator=table.iterator();int count=0;
            while(iterator.advance()) {
                require(++count<=128,"moddata-entry-bound");StringBuilder key=new StringBuilder();scalar(key,iterator.getKey(),depth+1);
                require(entries.put(key.toString(),iterator.getValue())==null,"moddata-key-collision");
            }
            out.append('{');for(var entry:entries.entrySet()){out.append(entry.getKey());scalar(out,entry.getValue(),depth+1);}out.append('}');
        } else throw new IllegalStateException("operations-unsupported-moddata-value:"+value.getClass().getName());
    }
    private static String item(InventoryItem value) {
        require(value.isInitialised(),"uninitialized-native-item");StringBuilder out=new StringBuilder();
        out.append(value.getClass().getName()).append(':').append(value.getFullType()).append(':').append(value.getID())
            .append(':').append(value.getCondition()).append(':').append(value.getUses()).append(':').append(Main.bits(value.getAge()))
            .append(':').append(value.getCurrentUses()).append(':').append(Main.bits(value.getCurrentUsesFloat())).append(':').append(Main.bits(value.getActualWeight()));
        if(value.hasModData()) scalar(out,value.getModData(),0);
        if(value instanceof Clothing clothing) out.append(":clothing=").append(Main.bits(clothing.getUsedDelta()));
        if(value.getFluidContainer()!=null) {
            var fluid=value.getFluidContainer();out.append(":fluid=").append(Main.bits(fluid.getAmount())).append('/').append(Main.bits(fluid.getCapacity()));
            for(var type:zombie.entity.components.fluids.Fluid.getAllFluids()) {
                float amount=fluid.getSpecificFluidAmount(type);if(amount!=0)out.append(':').append(type.getFluidTypeString()).append('=').append(Main.bits(amount));
            }
        }
        return out.toString();
    }
    private static void collect(ItemContainer out,Set<InventoryItem> owned,StringBuilder digest,int depth) {
        require(depth<=8,"output-depth");float weight=out.getCapacityWeight();
        require(Float.isFinite(weight) && weight>=0 && weight<=out.getEffectiveCapacity(null),"output-capacity");
        digest.append("C:").append(out.getItems().size()).append(':').append(out.getCapacity()).append(':').append(Main.bits(weight)).append(';');
        for(InventoryItem value:out.getItems()) {
            require(owned.contains(value),"unobserved-output-identity");digest.append(item(value)).append(';');
            if(value instanceof InventoryContainer bag)collect(bag.getInventory(),owned,digest,depth+1);
        }
    }
    private static void rollBatch(Group group,ItemContainer[] outputs,InventoryContainer[] bags) {
        for(int i=0;i<outputs.length;i++) {
            if(group.bag)ItemPickerJava.rollContainerItem(bags[i],null,group.distribution);
            else ItemPickerJava.doRollItem(group.distribution,outputs[i],0f,null,true,null);
        }
    }
    private static Result half(Group group,IsoGridSquare square,String phase,int pair,String order,boolean candidate,int seed,ThreadMXBean bean) throws Exception {
        verifyScripts();
        Map<String,Integer> baselines=new TreeMap<>();for(String type:types)baselines.put(type,InstanceTracker.get("Item Spawns",type));
        OperationsScope.Session scope=OperationsScope.begin(candidate,LIMIT);
        List<ItemContainer> roots=new ArrayList<>();ItemContainer[] outputs=new ItemContainer[group.batch];InventoryContainer[] bags=new InventoryContainer[group.batch];
        boolean cleaned=false;
        try {
            Bootstrap.seedRng(seed+128);
            for(int i=0;i<group.batch;i++) {
                ItemContainer root=plain(square);roots.add(root);
                if(group.bag) {
                    InventoryItem created=InventoryItemFactory.CreateItem("Base.FirstAidKit");require(created instanceof InventoryContainer,"native-firstaid-kit");
                    bags[i]=(InventoryContainer)created;root.AddItem(created);outputs[i]=bags[i].getInventory();outputs[i].setSourceGrid(square);roots.add(outputs[i]);
                    require(outputs[i].getCapacity()==4 && outputs[i].getItems().isEmpty() && outputs[i].getAcceptItemFunction()==null,"native-bag-setup");
                } else outputs[i]=root;
            }
            require(scope.incrementCount==0,"setup-native-increment");
            int prep=scope.itemCount;Bootstrap.seedRng(seed);
            float multiplier=SandboxOptions.instance.getCurrentLootMultiplier(square);
            OperationsTelemetry.Window marker=new OperationsTelemetry.Window();marker.windowId=windowId++;marker.group=group.name;marker.variant=candidate?"resolved":"native";marker.phase=phase;marker.pair=pair;marker.batch=group.batch;
            long allocated=bean.getThreadAllocatedBytes(Thread.currentThread().threadId());require(allocated>=0,"allocation-counter-unavailable");long wallStart=0,wallEnd=0,cpuStart=0,cpuEnd=0;
            OperationsScope.beginWindow();marker.begin();
            try {
                cpuStart=bean.getCurrentThreadCpuTime();wallStart=System.nanoTime();
                rollBatch(group,outputs,bags);
                wallEnd=System.nanoTime();cpuEnd=bean.getCurrentThreadCpuTime();
            } finally { marker.end();OperationsScope.endWindow();marker.commit(); }
            allocated=bean.getThreadAllocatedBytes(Thread.currentThread().threadId())-allocated;require(allocated>=0,"allocation-counter-moved-backwards");
            require(cpuStart>=0 && cpuEnd>=cpuStart && wallEnd>=wallStart && !scope.poisoned(),"clock-or-poison");
            require(Main.bits(multiplier).equals(Main.bits(SandboxOptions.instance.getCurrentLootMultiplier(square))),"loot-clock-factor-moved");
            int next=Rand.Next(1_000_000);Set<InventoryItem> owned=Collections.newSetFromMap(new IdentityHashMap<>()), inserted=Collections.newSetFromMap(new IdentityHashMap<>());
            for(int i=0;i<scope.itemCount;i++)require(owned.add(scope.items[i]),"duplicate-factory-return");
            Set<ItemContainer> containers=Collections.newSetFromMap(new IdentityHashMap<>());containers.addAll(roots);
            StringBuilder proof=new StringBuilder();
            for(int i=0;i<scope.itemCount;i++) {
                InventoryItem value=scope.items[i];require(types.contains(value.getFullType()),"unreviewed-factory-type:"+value.getFullType());
                require(value.getWorldItem()==null && (value.getContainer()==null || containers.contains(value.getContainer())),"factory-item-escaped-owned-container-or-world");
                proof.append("F:").append(item(value)).append(';');
            }
            for(int i=0;i<scope.incrementCount;i++) {
                InventoryItem value=scope.increments[i];require(scope.deltas[i]==1 && owned.contains(value) && inserted.add(value),"unsupported-native-increment-or-identity");
                proof.append("I:").append(value.getID()).append(':').append(scope.deltas[i]).append(';');
            }
            for(ItemContainer out:outputs)collect(out,owned,proof,0);
            Set<String> createdTypes=new TreeSet<>();for(int i=prep;i<scope.itemCount;i++)createdTypes.add(scope.items[i].getFullType());
            Set<String> coldTypes=new TreeSet<>(createdTypes);coldTypes.removeAll(warmTypes);
            if(phase.equals("warmup"))warmTypes.addAll(createdTypes);
            String digest=sha(proof.toString());
            Result result=new Result(digest,next,scope.selections,scope.itemCount-prep,scope.incrementCount,scope.nullReturns);
            require(!zombie.entity.GameEntityManager.isEngineProcessing(),"entity-engine-processing-at-disposal");
            Main.disposeOperations(roots,owned,inserted,baselines);cleaned=true;
            rows.append(phase).append('\t').append(group.name).append('\t').append(pair).append('\t').append(order).append('\t').append(candidate?"resolved":"native")
                .append('\t').append(group.batch).append('\t').append(marker.windowId).append('\t').append(wallStart).append('\t').append(wallEnd).append('\t').append(cpuStart).append('\t').append(cpuEnd)
                .append('\t').append(allocated).append('\t').append(scope.selections).append('\t').append(result.created).append('\t').append(scope.incrementCount).append('\t').append(scope.nullReturns)
                .append('\t').append(digest).append('\t').append(next).append('\t').append(createdTypes.isEmpty()?"-":String.join(",",createdTypes))
                .append('\t').append(phase.equals("measure")&&!coldTypes.isEmpty()?String.join(",",coldTypes):"-").append("\tverified\n");
            return result;
        } finally {
            // An incomplete factory can leave an uncaptured identity. Preserve failure/discard the
            // profile; never continue/reseed and claim that generic cleanup found that partial item.
            try { OperationsScope.close(); } finally { if(!cleaned)failure+=";incomplete-disposable-half"; }
        }
    }
    static boolean run(IsoPlayer actor) {
        if(!status.equals("not-run"))return status.equals("complete");status="running";boolean rng=false;int cases=0;
        try {
            require(Bootstrap.active() && Bootstrap.bank().equals("operations") && Bootstrap.owned(Bootstrap.cache()),"not-admitted");
            require(Path.of(zombie.ZomboidFileSystem.instance.getCacheDir()).toRealPath().equals(Bootstrap.cache()),"actual-cache");
            require(Files.isRegularFile(Bootstrap.cache().resolve("Lua/smoke-user.txt"),LinkOption.NOFOLLOW_LINKS),"actual-owned-Lua-marker");
            require(!zombie.entity.GameEntityManager.isEngineProcessing(),"entity-engine-processing");
            require(actor!=null && !actor.isDead() && actor.getSquare()!=null && !GameClient.client,"owned-authority-actor");
            Bootstrap.verifyRuntimeProfile(GameServer.server,GameClient.client);
            IsoGridSquare square=actor.getSquare();require(IsoWorld.instance.currentCell.getGridSquare(square.x,square.y,square.z)==square,"actual-loaded-square");
            ThreadMXBean bean=(ThreadMXBean)ManagementFactory.getThreadMXBean();
            require(bean.isCurrentThreadCpuTimeSupported() && bean.isThreadAllocatedMemorySupported(),"thread-CPU-allocation-unavailable");
            if(!bean.isThreadCpuTimeEnabled())bean.setThreadCpuTimeEnabled(true);if(!bean.isThreadAllocatedMemoryEnabled())bean.setThreadAllocatedMemoryEnabled(true);
            String initialOptions=options();admit("Base.FirstAidKit",true);
            Group[] groups={new Group("direct-CrateMetalwork-main",false,2,ItemPickerJava.ProceduralDistributions.get("CrateMetalwork")),
                new Group("bag-FirstAidKit-with-native-junk",true,4,ItemPickerJava.containers.get("FirstAidKit"))};
            Map<String,String> graphs=new TreeMap<>();
            for(Group group:groups){String graph=graph(group.distribution,0);graphs.put(group.name,graph);input(group.name+".graph",graph);input(group.name+".sha256",sha(graph));}
            input("ordinary_options",initialOptions);input("ordinary_options_sha256",sha(initialOptions));input("callback_admission","itemconfig-null;LuaCreate-empty-or-exact-native-gasmask");
            input("callback_binding",gasMaskBinding==null?"none":"native:ItemCodeOnCreate.onCreateGasMask(Clothing)");
            input("source_region",ItemPickerJava.getSquareRegion(square));input("source_x",square.x);input("source_y",square.y);input("source_z",square.z);input("owner_thread_id",Thread.currentThread().threadId());
            input("container_identity","detached-no-native-world-object-id");input("native_identity_logger","unchanged-diagnostics-included-if-emitted");
            input("direct_public_calls",(WARMUP+PAIRS)*2*2);input("bag_public_calls",(WARMUP+PAIRS)*2*4);
            input("direct_arguments","density:0f;character:null;boolean:true;room:null");input("bag_arguments","character:null");
            // API-only warmup, not repeated loot; cannot establish compilation of any loot path.
            long sink=0;for(int i=0;i<20_000;i++)sink+=bean.getCurrentThreadCpuTime()+System.nanoTime()+bean.getThreadAllocatedBytes(Thread.currentThread().threadId());input("timer_warmup_sink",sink);
            long emptyCpu=0,emptyWall=0;for(int i=0;i<1000;i++){long cpu=bean.getCurrentThreadCpuTime(),wall=System.nanoTime();emptyWall+=System.nanoTime()-wall;emptyCpu+=bean.getCurrentThreadCpuTime()-cpu;}input("empty1000_cpu_ns",emptyCpu);input("empty1000_wall_ns",emptyWall);
            Bootstrap.beginRng();rng=true;
            for(String phase:new String[]{"warmup","measure"})for(int pair=0;pair<(phase.equals("warmup")?WARMUP:PAIRS);pair++)for(int position=0;position<groups.length;position++){
                int index=(position+pair)%groups.length;Group group=groups[index];boolean first=((pair+index)&1)!=0;String order=first?"BA":"AB";
                int seed=(phase.equals("warmup")?pair:pair+64)+index*32;
                Result a=half(group,square,phase,pair,order,first,seed,bean),b=half(group,square,phase,pair,order,!first,seed,bean);
                require(a.equals(b),"paired-native-resolved-outputs-RNG-observers-differ");
            }
            for(Group group:groups)require(graph(group.distribution,0).equals(graphs.get(group.name)),"distribution-mutated");
            verifyScripts();require(options().equals(initialOptions),"ordinary-options-mutated");require(Bootstrap.active(),"bootstrap-invalidated");
            cases=2;status="complete";
        } catch(Throwable problem){failure=problem+failure;status="failed";problem.printStackTrace();}
        finally {
            try{if(rng)Bootstrap.endRng();}catch(Throwable problem){failure+=";RNG:"+problem;status="failed";}
            try{
                if(rng)Bootstrap.writeRngReceipt();Bootstrap.writeActivation();
                Files.writeString(Bootstrap.cache().resolve("loot-operations.tsv"),rows,StandardOpenOption.CREATE_NEW);
                Files.writeString(Bootstrap.cache().resolve("loot-operations-inputs.properties"),inputs,StandardOpenOption.CREATE_NEW);
                OperationsTelemetry.finish(Bootstrap.cache(),(int)windowId);
            }catch(Throwable problem){failure+=";receipt:"+problem;status="failed";problem.printStackTrace();}
            try{Files.writeString(Bootstrap.cache().resolve("loot-resolved-runtime-status.txt"),"status="+status+"\nmode="+Bootstrap.mode()+"\nbank=operations\npid="+ProcessHandle.current().pid()+"\ncases="+cases+"\nreason="+failure.replace('\n',' ')+"\nresource_profile="+Bootstrap.resourceProfile()+"\noptimizer_manifest_sha256="+Bootstrap.optimizerManifest()+"\nruntime_profile_checked="+Bootstrap.runtimeProfileChecked()+"\nrng_scope="+Bootstrap.RNG_SCOPE+"\nrng_scope_complete="+(rng&&Bootstrap.rngComplete())+"\noperations_scope="+OperationsScope.KIND+"\nwindows="+windowId+"\n");}catch(Throwable problem){failure+=";status:"+problem;status="failed";}
            System.out.println("[LOOT_RESOLVED_RUNTIME] FINISH status="+status+" cases="+cases+" reason="+failure);
        }
        return status.equals("complete");
    }
}
