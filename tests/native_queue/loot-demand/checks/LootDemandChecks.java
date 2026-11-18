package net.alexredby.lootdemand;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Proxy;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.zip.ZipFile;
import net.bytebuddy.jar.asm.*;

/** Headless state/provenance/actual transformed-loop checks; never launches the game. */
public final class LootDemandChecks {
    private static int checks;
    private static void check(boolean value,String message) { checks++; if (!value) throw new AssertionError(message); }
    private static void eq(long expected,long actual,String message) { check(expected==actual,message+": "+actual+" != "+expected); }
    static final class Box { boolean target=true,explored; final List<Integer> items=new ArrayList<>(); }
    static final class Access implements DemandState.Access<Box> {
        boolean enabled=true,authority=true,overlayThrows; int overlayCalls;
        public boolean enabled(){return enabled;} public boolean authority(){return authority;}
        public boolean target(Box c){return c!=null && c.target;}
        public boolean explored(Box c){return c.explored;} public void explored(Box c,boolean v){c.explored=v;}
        public void overlay(Box c){overlayCalls++;if(overlayThrows)throw new IllegalStateException("visual");}
    }
    private static void stateChecks() {
        Access a=new Access(); DemandState<Box> state=new DemandState<>(a); Box c=new Box();
        a.enabled=false; eq(DemandState.PASS,state.enter(c),"default disabled passes native"); check(!c.explored,"disabled does not mark");
        check(!state.cancel(c),"disabled trash cannot cancel pending loot");
        a.enabled=true;a.authority=false;eq(DemandState.PASS,state.enter(c),"client cannot own generation");check(!c.explored,"client does not mark");
        check(!state.cancel(c),"client trash cannot cancel authority loot");
        a.authority=true;c.target=false;eq(DemandState.PASS,state.enter(c),"unrelated container native"); c.target=true;
        int token=state.enter(c);eq(DemandState.OWNED,token,"authority owns first fill");check(c.explored,"mark before callback");
        check(state.isActive(c),"marked explored is still actively materializing");
        check(!state.cancel(c),"emptyTrash refuses active fill before deleting partial IDs");
        c.items.add(101);eq(DemandState.REENTRANT,state.enter(c),"recursive direct native fill suppressed");
        c.target=false;eq(DemandState.REENTRANT,state.enter(c),"active identity survives mid-callback provenance change");c.target=true;
        state.exit(c,DemandState.REENTRANT,false);eq(0,a.overlayCalls,"reentrant return cannot finish parent");
        Box nested=new Box();int child=state.enter(nested);eq(DemandState.OWNED,child,"different nested target allowed");
        nested.items.add(102);state.exit(nested,child,false);state.exit(c,token,false);
        eq(2,a.overlayCalls,"one overlay per completed owned fill"); eq(1,c.items.size(),"recursive fill did not add duplicate");
        eq(0,state.counts()[4],"active identities released");check(!state.isActive(c),"completion permits movers to observe ready state");
        // Server request premarks explored before entering public fillContainer.
        Box server=new Box();server.explored=true;token=state.enter(server);eq(DemandState.OWNED,token,"premarked Host fill still guarded");
        eq(DemandState.REENTRANT,state.enter(server),"premarked Host recursion suppressed");state.exit(server,token,false);
        // Native exception retains partial IDs and explored=true; UI demand will not blindly retry.
        Box partial=new Box();token=state.enter(partial);partial.items.add(201);state.exit(partial,token,true);
        check(partial.explored,"failed fill keeps explored");check(partial.items.equals(List.of(201)),"failed partial IDs retained");
        eq(1,state.counts()[2],"failure count");eq(0,state.counts()[4],"failure releases guard");check(!state.isActive(partial),"failed partial object no longer actively mutating");
        a.overlayThrows=true;Box visual=new Box();token=state.enter(visual);visual.items.add(301);
        boolean threw=false;try{state.exit(visual,token,false);}catch(IllegalStateException expected){threw=true;}
        check(threw && visual.explored,"visual failure stays complete and visible");eq(0,state.counts()[4],"overlay failure cannot leak guard");
        state.exit(visual,token,true);eq(1,state.counts()[2],"exception finally cleanup idempotent");
        a.overlayThrows=false;Box trash=new Box();trash.items.add(401);
        long beforeFills=state.counts()[0];
        check(state.cancel(trash),"trash intentionally resolves pending without generation");
        check(trash.explored && trash.items.equals(List.of(401)),"cancellation preserves actual items for native delete listener");
        eq(beforeFills,state.counts()[0],"trash cancellation never creates loot");
        eq(1,state.cancellations(),"first cancellation count");check(state.cancel(trash),"repeated resolved trash safe");
        eq(1,state.cancellations(),"repeat cancellation cannot reopen loot");
        trash.target=false;check(!state.cancel(trash),"non-target trash native no-op");
    }
    private static void censusChecks() {
        Object a=new Object(),b=new Object(),unseen=new Object();
        DemandCensus<Object> legacy=new DemandCensus<>("legacy",1);
        legacy.automatic(a,"bin",1,2,0,3,"sprite",100);legacy.enter(a,110);legacy.exit(a,120,false);
        check(legacy.status().contains("objects=0\n"),"legacy has no measurement identities");
        DemandCensus<Object> observe=new DemandCensus<>("observe",2);
        observe.automatic(a,"bin",1,2,0,3,"name,\"line\n\u044f",100);observe.enter(a,110);
        observe.enter(a,120);observe.exit(a,130,true);observe.exit(a,150,false);
        String csv=observe.csv();
        check(csv.contains(",1,100,110,automatic,40,1,1,0,0\n"),"first native outer interval includes native reentry/failure");
        check(csv.contains("\"name,\"\"line\\u000a\\u044f\""),"CSV escapes comma quote newline and non-ASCII");
        check(csv.chars().allMatch(c->c<=127),"export stays ASCII");
        observe.enter(a,160);observe.exit(a,180,false);
        check(observe.csv().contains(",automatic,40,1,1,1,0\n"),"later fills cannot replace first interval");
        observe.automatic(b,"dumpster",2,3,0,4,"sprite",200);observe.enter(unseen,210);observe.enter(b,220);observe.exit(b,240,false);
        check(observe.csv().contains(",1,200,220,demand,20,0,0,0,0\n"),"intervening native fill consumes automatic adjacency");
        observe.automatic(unseen,"bin",3,4,0,0,"sprite",250);
        check(observe.status().contains("objects=2\noverflow=1\nactive=0\n"),"bounded ledger reports overflow rather than silently dropping scope");
        DemandCensus<Object> defer=new DemandCensus<>("defer",1);
        defer.automatic(a,"bin",1,2,0,3,"sprite",100);defer.automatic(a,"bin",1,2,0,3,"sprite",120);
        check(defer.csv().contains(",2,100,0,none,-1,0,0,0,0\n"),"deferred visits do not imply native fill");
        defer.enter(a,300);defer.suppressedReentry(a);defer.exit(a,350,false);
        check(defer.csv().contains(",2,100,300,demand,50,0,1,0,0\n"),"candidate demand measures first native call and suppressed recursion");
        check(defer.status().contains("active=0\n"),"suppressed candidate recursion cannot leak ledger depth");
    }
    private static void threadedCensusChecks() throws Exception {
        DemandCensus<Object> census=new DemandCensus<>("defer",2);
        Object original=new Object(),replacement=new Object();
        census.automatic(original,"bin",1,2,0,3,"sprite",100);
        check(census.witness(original).contains("identity=1\norigin=automatic-visit\n"),"original exact identity has a stable witness");
        check(census.witness(replacement).contains("known=false\nidentity=0\n"),"same-location replacement cannot inherit original identity");
        census.nativeEnter(replacement,false);census.nativeExit(replacement,false);
        check(census.csv().contains(",100,0,none,-1,"),"untracked replacement fill never changes original meter");
        var entered=new java.util.concurrent.CountDownLatch(1);var release=new java.util.concurrent.CountDownLatch(1);
        var error=new java.util.concurrent.atomic.AtomicReference<Throwable>();
        Thread packet=new Thread(()->{try{
            census.nativeEnter(original,false);entered.countDown();
            if(!release.await(5,java.util.concurrent.TimeUnit.SECONDS))throw new AssertionError("concurrent meter release timeout");
            census.nativeExit(original,false);
        }catch(Throwable failure){error.set(failure);entered.countDown();}},"native-packet-test");
        packet.start();check(entered.await(5,java.util.concurrent.TimeUnit.SECONDS),"foreign native fill entered");
        try {
            String witness=census.witness(original);
            check(witness.contains("first_fill_thread=\"native-packet-test\"\nfirst_fill_authority_thread=false\n"),"foreign native thread captured without claiming authority");
            check(witness.contains("active_depth=1\n"),"concurrent snapshot sees coherent active native call");
            // Observation does not authorize the separate gameplay state machine.
            Access denied=new Access();denied.authority=false;Box box=new Box();DemandState<Box> policy=new DemandState<>(denied);
            eq(DemandState.PASS,policy.enter(box),"foreign packet retains native gameplay path");
            check(!box.explored && denied.overlayCalls==0 && policy.counts()[0]==0,"foreign observation cannot mark explored or refresh overlay");
            census.nativeEnter(original,true);census.nativeExit(original,false);
            check(census.witness(original).contains("concurrent_fills=1\n"),"overlapping native calls are distinguished from recursion");
        } finally { release.countDown();packet.join(6000); }
        check(!packet.isAlive() && error.get()==null,"foreign native completion succeeds");
        String witness=census.witness(original);
        check(!witness.contains("fill_ns=-1\n") && witness.contains("active_depth=0\n"),"foreign fill completes timer and releases depth");
        check(census.watch(replacement,"bin",1,2,0,3,"sprite"),"explicit pristine replacement can have separate watch");
        census.nativeEnter(replacement,false);census.nativeExit(replacement,false);
        check(census.witness(replacement).contains("identity=0\norigin=selected-watch\nauto_visits=0\n"),"selected watch never borrows original automatic visit evidence");
        check(census.status().contains("objects=1\n") && census.status().contains("watched=1\n"),"watch remains separate from original CSV population");
        check(!census.watch(original,"bin",1,2,0,3,"sprite"),"another known identity cannot replace selected watch");
        DemandCensus<Object> promoted=new DemandCensus<>("defer",2);
        check(promoted.watch(replacement,"bin",1,2,0,3,"selected-sprite"),"selected identity can be watched before an automatic visit");
        promoted.enter(replacement,300);
        promoted.automatic(replacement,"dumpster",4,5,1,6,"automatic-sprite",350);
        String promotedWitness=promoted.witness(replacement);
        check(promotedWitness.contains("identity=1\norigin=automatic-visit\nauto_visits=1\nselected_watch=true\n"),"real automatic visit promotes the same selected identity with distinct selection metadata");
        check(promotedWitness.contains("first_fill_ns=300\nfill_ns=-1\n") && promotedWitness.contains("active_depth=1\n"),"promotion preserves the in-flight first interval");
        check(promoted.status().contains("objects=1\noverflow=0\nactive=1\nwatched=1\n"),"selected automatic identity is counted only once while active");
        check(!promoted.watch(original,"bin",1,2,0,3,"sprite"),"promotion cannot free the selected identity slot");
        promoted.exit(replacement,400,false);
        check(promoted.csv().contains("\"dumpster\",4,5,1,6,\"automatic-sprite\",1,350,300,demand,100,0,0,0,0\n"),"CSV uses actual automatic metadata and retains completed watched timing");
        check(promoted.csv().lines().count()==2 && promoted.status().contains("active=0\n"),"promotion exports one automatic row and releases its sole active count");
        DemandCensus<Object> selectedKnown=new DemandCensus<>("defer",2);
        selectedKnown.automatic(original,"bin",1,2,0,3,"sprite",100);
        check(selectedKnown.watch(original,"bin",1,2,0,3,"sprite"),"an already known identity can be selected");
        check(!selectedKnown.watch(replacement,"bin",1,2,0,3,"sprite"),"selecting a known identity consumes the sole selection slot");
        DemandCensus<Object> pair = new DemandCensus<>("defer", 4, 2);
        check(pair.watch(original, "dumpster", 4, 5, 0, 1, "part1"), "select first member");
        check(pair.watch(replacement, "dumpster", 4, 6, 0, 1, "part2"), "select second member");
        check(!pair.watch(new Object(), "dumpster", 4, 7, 0, 1, "third"), "two-member observer stays bounded");
        pair.enter(original, 10);
        pair.enter(replacement, 16);
        pair.automatic(replacement, "dumpster", 4, 6, 0, 1, "part2", 17);
        check(pair.status().contains("objects=1\noverflow=0\nactive=2\nwatched=2\n"),
                "observed member and promoted member each count once");
        pair.exit(replacement, 20, false);
        pair.exit(original, 25, false);
        check(pair.witness(original).contains("fill_ns=15\n")
                && pair.witness(replacement).contains("fill_ns=4\n"), "separate identities retain distinct original timers");
        DemandCensus<Object> observe=new DemandCensus<>("observe",1);
        observe.automatic(original,"bin",1,2,0,3,"sprite",100);
        Thread unrelated=new Thread(()->{observe.nativeEnter(replacement,false);observe.nativeExit(replacement,false);});unrelated.start();unrelated.join();
        observe.enter(original,110);observe.exit(original,120,false);
        check(observe.csv().contains(",automatic,10,"),"foreign unrelated fill cannot consume authority automatic adjacency");
        check(!observe.watch(replacement,"bin",1,2,0,3,"sprite"),"observe cannot arm a selected candidate watch");
    }
    private static void eventFilterChecks() {
        se.krka.kahlua.vm.KahluaTable table=new se.krka.kahlua.j2se.KahluaTableImpl(new java.util.HashMap<>());
        Object[] valid={"object","emptyTrash",null,table};
        check(LootDemand.trashCommand("OnClientCommand",valid),"exact event/module/command/table accepted");
        for(String name:new String[]{null,"OnFillContainer","OnServerCommand","onClientCommand"})
            check(!LootDemand.trashCommand(name,valid),"unrelated event ignored "+name);
        check(!LootDemand.trashCommand("OnClientCommand",null),"null args ignored");
        check(!LootDemand.trashCommand("OnClientCommand",new Object[]{"object","emptyTrash",table}),"wrong arity ignored");
        check(!LootDemand.trashCommand("OnClientCommand",new Object[]{"Object","emptyTrash",null,table}),"module case exact");
        check(!LootDemand.trashCommand("OnClientCommand",new Object[]{"object","EmptyTrash",null,table}),"command case exact");
        check(!LootDemand.trashCommand("OnClientCommand",new Object[]{"object","emptyTrash",null,"bad"}),"malformed table unchanged");
        check(!LootDemand.beforeEvent(null,valid),"disabled event hook harmless");
    }
    @SuppressWarnings("unchecked")
    private static void activeBridgeChecks() throws Exception {
        // Model the exact in-callback state: native container is marked explored but not ready.
        // Only the native trivial container constructor/accessors run; no loot/world/GUI is initialized.
        zombie.inventory.ItemContainer container=new zombie.inventory.ItemContainer();container.setExplored(true);
        var stateField=LootDemand.class.getDeclaredField("state");stateField.setAccessible(true);
        var activeField=DemandState.class.getDeclaredField("active");activeField.setAccessible(true);
        var active=(java.util.IdentityHashMap<zombie.inventory.ItemContainer,Boolean>)activeField.get(stateField.get(null));
        active.put(container,Boolean.TRUE);
        try {
            check(!LootDemand.ensure(container,null),"actual bridge rejects explored-but-active movement readiness");
            boolean rejected=false;try{LootDemand.beforeDump(container);}catch(IllegalStateException expected){rejected=true;}
            check(rejected!=LootDemand.censusStatus().contains("arm=observe\n"),"only mutating policy refuses destructive dumping during fill callback");
        } finally { active.remove(container); }
        check(LootDemand.ensure(container,null),"completed explored container ready after guard release");
    }
    private static Map<String,byte[]> nativeBytes() throws Exception {
        Map<String,byte[]> result=new HashMap<>();
        for(String name:DemandTransform.TARGETS)try(var in=LootDemandChecks.class.getClassLoader().getResourceAsStream(name+".class")){
            check(in!=null,"native target exists");byte[] bytes=in.readAllBytes();
            check(DemandTransform.SOURCE_SHA256.get(name).equals(DemandTransform.sha(bytes)),"whole-class source provenance "+name);
            result.put(name,bytes);
        }
        return result;
    }
    private static Set<String> shape(byte[] bytes) {
        Set<String> shape=new HashSet<>();new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9){
            @Override public FieldVisitor visitField(int a,String n,String d,String s,Object v){shape.add("F"+a+" "+n+d);return null;}
            @Override public MethodVisitor visitMethod(int a,String n,String d,String s,String[] e){shape.add("M"+a+" "+n+d);return null;}
        },ClassReader.SKIP_CODE);return shape;
    }
    private static byte[] mutate(byte[] bytes,String method) {
        ClassReader r=new ClassReader(bytes);ClassWriter w=new ClassWriter(r,0);
        r.accept(new ClassVisitor(Opcodes.ASM9,w){
            @Override public MethodVisitor visitMethod(int a,String n,String d,String s,String[]e){
                MethodVisitor mv=super.visitMethod(a,n,d,s,e);if(!n.equals(method))return mv;
                return new MethodVisitor(Opcodes.ASM9,mv){@Override public void visitCode(){super.visitCode();super.visitInsn(Opcodes.NOP);}};
            }
        },0);return w.toByteArray();
    }
    private static void rejected(String name,byte[] bytes,String message) throws Exception {
        boolean rejected=false;try{DemandTransform.transform(name,bytes);}catch(IllegalArgumentException expected){rejected=true;}
        check(rejected,message);
    }
    private static Map<String,byte[]> transformChecks(Map<String,byte[]> inputs) throws Exception {
        Map<String,byte[]> output=new HashMap<>();
        for(var input:inputs.entrySet()){
            String name=input.getKey();byte[] bytes=DemandTransform.transform(name,input.getValue());output.put(name,bytes);
            check(shape(input.getValue()).equals(shape(bytes)),"retransformation preserves class schema "+name);
            rejected(name,bytes,"duplicate weave rejected "+name);
            String[] methods=name.equals(DemandTransform.PICKER)?new String[]{"fillContainer","doOverlaySprite"}:
                new String[]{name.equals(DemandTransform.LOADER)?"checkObject":"dumpContentsInSquare"};
            for(String method:methods)rejected(name,mutate(input.getValue(),method),"changed target rejected "+method);
            int[] hooks={0};new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9){
                @Override public MethodVisitor visitMethod(int a,String n,String d,String s,String[] e){return new MethodVisitor(Opcodes.ASM9){
                    @Override public void visitMethodInsn(int op,String o,String n,String d,boolean itf){if(o.equals(DemandTransform.BRIDGE))hooks[0]++;}
                };}
            },0);
            eq(name.equals(DemandTransform.PICKER)?4:1,hooks[0],"expected guarded hook count "+name);
            System.out.println("LOOT_DEMAND_BYTES "+name+" input="+DemandTransform.sha(input.getValue())+" output="+DemandTransform.sha(bytes));
        }
        // Guarding selected methods permits independent production Buddy changes elsewhere.
        byte[] unrelated=mutate(inputs.get(DemandTransform.PICKER),"getLootModifier");
        check(DemandTransform.transform(DemandTransform.PICKER,unrelated)!=null,"unrelated method advice composes");
        rejected(DemandTransform.LOADER,inputs.get(DemandTransform.PICKER),"owner mismatch rejected");
        return output;
    }
    public static final class DumpItem { final int id; DumpItem(int id){this.id=id;} }
    public static class DumpBox { public boolean scoped; public final ArrayList<DumpItem> items=new ArrayList<>();public ArrayList<DumpItem> getItems(){return items;} }
    public static final class DumpSquare { final List<Integer> ids=new ArrayList<>();public DumpItem AddWorldInventoryItem(DumpItem item,float x,float y,float z){ids.add(item.id);return item;} }
    public static boolean beforeDump(DumpBox box){return box.scoped;}
    static final class Generated extends ClassLoader { Generated(){super(LootDemandChecks.class.getClassLoader());}Class<?> define(byte[] b){return defineClass(null,b,0,b.length);} }
    private static String remap(String desc){return desc.replace("zombie/inventory/ItemContainer","net/alexredby/lootdemand/LootDemandChecks$DumpBox")
        .replace("zombie/inventory/InventoryItem","net/alexredby/lootdemand/LootDemandChecks$DumpItem")
        .replace("zombie/iso/IsoGridSquare","net/alexredby/lootdemand/LootDemandChecks$DumpSquare");}
    /** Execute the ACTUAL transformed native loop after only adapting native object types. */
    private static void dumpLoopChecks(byte[] container) throws Exception {
        String generated="net/alexredby/lootdemand/GeneratedDemandDump",base="net/alexredby/lootdemand/LootDemandChecks$DumpBox";
        ClassWriter out=new ClassWriter(ClassWriter.COMPUTE_FRAMES|ClassWriter.COMPUTE_MAXS);
        out.visit(Opcodes.V17,Opcodes.ACC_PUBLIC,generated,null,base,null);
        MethodVisitor ctor=out.visitMethod(Opcodes.ACC_PUBLIC,"<init>","()V",null,null);ctor.visitCode();ctor.visitVarInsn(Opcodes.ALOAD,0);
        ctor.visitMethodInsn(Opcodes.INVOKESPECIAL,base,"<init>","()V",false);ctor.visitInsn(Opcodes.RETURN);ctor.visitMaxs(0,0);ctor.visitEnd();
        new ClassReader(container).accept(new ClassVisitor(Opcodes.ASM9){
            @Override public MethodVisitor visitMethod(int a,String n,String d,String s,String[] e){
                if(!n.equals("dumpContentsInSquare"))return null;
                return new MethodVisitor(Opcodes.ASM9,out.visitMethod(Opcodes.ACC_PUBLIC,"dump",remap(d),null,null)){
                    @Override public void visitMethodInsn(int op,String o,String n,String d,boolean itf){
                        if(o.equals(DemandTransform.BRIDGE)){o="net/alexredby/lootdemand/LootDemandChecks";d="(L"+base+";)Z";}
                        else o=remap(o);
                        super.visitMethodInsn(op,o,n,remap(d),itf);
                    }
                    @Override public void visitTypeInsn(int op,String type){super.visitTypeInsn(op,remap(type));}
                };
            }
        },ClassReader.SKIP_DEBUG|ClassReader.SKIP_FRAMES);
        out.visitEnd();Class<?> type=new Generated().define(out.toByteArray());var dump=type.getMethod("dump",DumpSquare.class);
        for(boolean scoped:new boolean[]{false,true})for(int size:new int[]{0,1,2,3,12,31}){
            DumpBox box=(DumpBox)type.getConstructor().newInstance();box.scoped=scoped;DumpSquare square=new DumpSquare();
            for(int i=0;i<size;i++)box.items.add(new DumpItem(1000+i));
            dump.invoke(box,square);
            int expected=scoped?size:(size+1)/2;eq(expected,square.ids.size(),"actual native loop scoped="+scoped+" size="+size);
            eq(size-expected,box.items.size(),"remaining IDs match target/native scope");
            Set<Integer> union=new HashSet<>(square.ids);for(DumpItem item:box.items)check(union.add(item.id),"no duplicate ID in spill union");
            eq(size,union.size(),"all IDs conserved across floor and remaining native container");
            if(scoped){eq(0,box.items.size(),"target dump cannot lose leftovers on destruction");for(int i=0;i<size;i++)eq(1000+i,square.ids.get(i),"target preserves item order");}
        }
    }
    private static void installChecks(Map<String,byte[]> inputs,boolean fail) throws Exception {
        System.setProperty(LootDemand.PROPERTY,"true");
        Map<String,Class<?>> classes=new HashMap<>();for(String n:DemandTransform.TARGETS)classes.put(n,Class.forName(n.replace('/','.'),false,LootDemandChecks.class.getClassLoader()));
        final ClassFileTransformer[] hook={null};final int[] woven={0},removed={0};
        Instrumentation fake=(Instrumentation)Proxy.newProxyInstance(LootDemandChecks.class.getClassLoader(),new Class[]{Instrumentation.class},(proxy,m,args)->{
            return switch(m.getName()){
                case "isRetransformClassesSupported","isModifiableClass" -> true;
                case "getAllLoadedClasses" -> classes.values().toArray(Class<?>[]::new);
                case "addTransformer" -> {hook[0]=(ClassFileTransformer)args[0];yield null;}
                case "removeTransformer" -> {removed[0]++;yield true;}
                case "retransformClasses" -> {
                    Class<?> c=((Class<?>[])args[0])[0];String n=c.getName().replace('.','/');byte[] b=inputs.get(n);
                    if(fail && n.equals(DemandTransform.CONTAINER))b=mutate(b,"dumpContentsInSquare");
                    if(hook[0].transform(c.getClassLoader(),n,c,null,b)!=null)woven[0]++;
                    check(!LootDemand.installed(),"partial installation remains inactive");yield null;
                }
                default -> throw new UnsupportedOperationException(m.getName());
            };
        });
        boolean installed=LootDemand.install(fake);
        check(!installed && !LootDemand.installed(),"fake instrumentation cannot bypass real Event advice activation");
        check(LootDemand.diagnostic().startsWith("install:"),"failed installation readable");
        check(removed[0]>=1,"partial/missing Event install removes its transformer");
        if(!fail) eq(3,woven[0],"native transforms alone do not activate without Event prefix");
    }
    public static void main(String[] args) throws Exception {
        if(args.length>0 && args[0].equals("--partial-install")){installChecks(nativeBytes(),true);System.out.println("LootDemandChecks PARTIAL_INSTALL_PASS ("+checks+")");return;}
        if(args.length>0 && args[0].equals("--install")){installChecks(nativeBytes(),false);System.out.println("LootDemandChecks EVENT_ACTIVATION_GUARD_PASS ("+checks+")");return;}
        System.clearProperty(LootDemand.PROPERTY);check(!LootDemand.install(null),"default disabled even without instrumentation");check(!LootDemand.installed(),"default behavior inactive");
        stateChecks();censusChecks();threadedCensusChecks();eventFilterChecks();activeBridgeChecks();Map<String,byte[]> input=nativeBytes();Map<String,byte[]> output=transformChecks(input);dumpLoopChecks(output.get(DemandTransform.CONTAINER));
        if(args.length==2 && args[0].equals("--official"))try(ZipFile zip=new ZipFile(Path.of(args[1]).toFile())){
            for(String name:DemandTransform.TARGETS) {
                var entry=zip.getEntry(name+".class");
                if(entry!=null) rejected(name,zip.getInputStream(entry).readAllBytes(),"raw official target override is incompatible and rejected "+name);
            }
        }
        System.out.println("LootDemandChecks PASS ("+checks+" checks; native loot generation not executed; bridge readiness checked; transformed spill loop executed with adapted object types)");
    }
}
