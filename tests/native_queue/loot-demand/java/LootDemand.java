package net.alexredby.lootdemand;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.security.ProtectionDomain;
import java.util.HashMap;
import java.util.Map;
import me.zed_0xff.zombie_buddy.PatchEngine;
import net.bytebuddy.jar.asm.*;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.Event;
import zombie.iso.IsoWorld;
import zombie.GameWindow;
import zombie.characters.IsoPlayer;
import zombie.inventory.ItemContainer;
import zombie.inventory.ItemPickerJava;
import zombie.iso.IsoObject;
import zombie.network.GameClient;
import zombie.network.GameServer;

/** Explicit opt-in research policy, never shipped or installed into the user's game. */
public final class LootDemand {
    public static final String PROPERTY="pz.lootDemand.enabled";
    private static final ClassLoader GAME=LootDemand.class.getClassLoader();
    private static volatile boolean installed;
    private static volatile String diagnostic="disabled";
    private static Instrumentation instrumentation;
    private static ClassFileTransformer transformer;
    private static long deferred,dumpEnsures;
    private static final String EVENT="zombie/Lua/Event", EVENT_HASH="cf4b0ba953b8f965fbcacb73ebb5d1a173dc3ed140656e15b90ad932eff0e952";
    private static final DemandState<ItemContainer> state=new DemandState<>(new DemandState.Access<>() {
        public boolean enabled() { return installed; }
        public boolean authority() { return authorityThread(); }
        public boolean target(ItemContainer c) { return targetWorld(c); }
        public boolean explored(ItemContainer c) { return c.isExplored(); }
        public void explored(ItemContainer c,boolean value) { c.setExplored(value); }
        public void overlay(ItemContainer c) { ItemPickerJava.updateOverlaySprite(c.getParent()); }
    });
    private LootDemand() {}
    public static boolean installed() { return installed; }
    public static String diagnostic() { return diagnostic; }
    public static long deferredCount() { return deferred; }
    public static long dumpEnsureCount() { return dumpEnsures; }
    /** Query only; fills,reentries,failed fills,overlay updates,active fills. */
    public static long[] counts() { return state.counts(); }
    private static boolean authorityThread() {
        if (GameClient.client) return false;
        Thread expected=GameServer.server ? GameServer.mainThread : GameWindow.gameThread;
        return expected!=null && expected==Thread.currentThread();
    }
    private static boolean targetWorld(ItemContainer c) {
        if (c==null || c.containingItem!=null || c.inventoryContainer!=null || c.vehiclePart!=null) return false;
        String type=c.getType();
        if (!"bin".equals(type) && !"dumpster".equals(type)) return false;
        IsoObject parent=c.getParent();
        // Deliberately exclude subclasses (player constructions/special containers).
        return parent!=null && parent.getClass()==IsoObject.class && parent.getSquare()!=null
                && parent.getObjectIndex()>=0 && parent.getContainer()==c
                && c.getSourceGrid()==parent.getSquare()
                && parent.getSprite()!=null && parent.getSprite().getName()!=null;
    }
    /** Native explored=false is the persistent pending marker; no saved Java references or queue. */
    public static boolean pending(ItemContainer c) {
        return installed && targetWorld(c) && !c.isExplored();
    }
    public static boolean shouldDefer(ItemContainer c) {
        if (!installed || !authorityThread() || !pending(c) || c.getParent().isMovedThumpable()
                || c.getParent().hasModData() || c.isHasBeenLooted() || !c.isEmpty()) return false;
        deferred++;
        return true;
    }
    public static int enterFill(ItemContainer c) { return state.enter(c); }
    public static void exitFill(ItemContainer c,int token,boolean failed) { state.exit(c,token,failed); }
    /** Client demand requests native authority; it never marks local explored or creates items. */
    public static boolean ensure(ItemContainer c,IsoPlayer player) {
        if (c==null || state.isActive(c)) return false;
        if (c.isExplored()) return true;
        if (!targetWorld(c)) {
            // A world target whose location/provenance became ambiguous is not safe to move/dump.
            String type=c.getType();
            return !("bin".equals(type) || "dumpster".equals(type)) || c.getParent()==null;
        }
        // A deferred object can acquire modData/items before interaction. Still ensure the native fill;
        // the stricter pristine predicate is only for deciding whether to skip automatic generation.
        if (!installed) return false;
        if (GameClient.client) { c.requestServerItemsForContainer(); return false; }
        if (!authorityThread()) throw new IllegalStateException("Loot demand requires the native authority thread");
        ItemPickerJava.fillContainer(c,player);
        return c.isExplored();
    }
    public static boolean beforeDump(ItemContainer c) {
        if (state.isActive(c)) throw new IllegalStateException("Cannot dump an actively materializing loot container");
        if (!installed || !authorityThread() || !targetWorld(c)) return false;
        if (!c.isExplored()) {
            dumpEnsures++;
            if (!ensure(c,null)) throw new IllegalStateException("Unresolved loot demand before dump");
        }
        return true;
    }
    /** Cancel uncreated loot intentionally; actual items remain for the native trash-delete listener.
     * False refuses active materialization or an unrelated/non-authoritative request. */
    public static boolean cancelForTrash(ItemContainer c) { return state.cancel(c); }
    public static long trashCancelCount() { return state.cancellations(); }
    static boolean trashCommand(String name,Object[] args) {
        return "OnClientCommand".equals(name) && args!=null && args.length==4
                && "object".equals(args[0]) && "emptyTrash".equals(args[1]) && args[3] instanceof KahluaTable;
    }
    /** True means refuse the command before any listener; false preserves ordinary listener dispatch. */
    public static boolean beforeEvent(Event event,Object[] args) {
        if (!installed || event==null || !trashCommand(event.name,args) || !authorityThread()) return false;
        KahluaTable table=(KahluaTable)args[3];
        Object x=table.rawget("x"),y=table.rawget("y"),z=table.rawget("z"),index=table.rawget("index");
        if (!(x instanceof Number) || !(y instanceof Number) || !(z instanceof Number) || !(index instanceof Number)) return false;
        double i=((Number)index).doubleValue();
        if (!Double.isFinite(i) || i<0 || IsoWorld.instance==null || IsoWorld.instance.getCell()==null) return false;
        var square=IsoWorld.instance.getCell().getGridSquare(((Number)x).doubleValue(),((Number)y).doubleValue(),((Number)z).doubleValue());
        if (square==null || i>=square.getObjects().size()) return false;
        // Same native ClientCommands.lua _getTrashCan predicate; do not cancel ordinary containers.
        IsoObject object=square.getObjects().get((int)i);
        if (object==null || object.getSprite()==null || !object.getSprite().getProperties().has("IsTrashCan")) return false;
        ItemContainer container=object.getContainer();
        if (state.isActive(container)) return true;
        cancelForTrash(container);
        return false;
    }
    private static void installEventGate(Instrumentation supplied) throws Exception {
        try (var resource=GAME.getResourceAsStream(EVENT+".class")) {
            if (resource==null || !EVENT_HASH.equals(DemandTransform.sha(resource.readAllBytes())))
                throw new IllegalStateException("Unreviewed Event resource");
        }
        // Resource guard deliberately admits production FenceValidation's separate OnExit advice.
        // Match Buddy's registered-JAR discovery. Explicit AppClassLoader scanning
        // misses dynamically appended mod JARs even when package resources exist.
        PatchEngine.applyPatches("net.alexredby.lootdemand",null);
        final boolean[] observed={false};
        ClassFileTransformer observer=new ClassFileTransformer() {
            @Override public byte[] transform(ClassLoader loader,String name,Class<?> type,ProtectionDomain domain,byte[] bytes) {
                if (loader!=GAME || !EVENT.equals(name)) return null;
                new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9) {
                    @Override public MethodVisitor visitMethod(int access,String n,String d,String sig,String[] e) {
                        if (!n.equals("trigger") || !d.equals("(Lse/krka/kahlua/vm/KahluaTable;Lse/krka/kahlua/integration/LuaCaller;[Ljava/lang/Object;)Z")) return null;
                        return new MethodVisitor(Opcodes.ASM9) {
                            boolean first=true;
                            @Override public void visitMethodInsn(int op,String owner,String method,String desc,boolean itf) {
                                if (first) observed[0]=owner.equals("net/alexredby/lootdemand/LootDemand") && method.equals("beforeEvent")
                                    && desc.equals("(Lzombie/Lua/Event;[Ljava/lang/Object;)Z");
                                first=false;
                            }
                        };
                    }
                },ClassReader.SKIP_DEBUG);
                return null;
            }
        };
        supplied.addTransformer(observer,true);
        try { supplied.retransformClasses(Class.forName(EVENT.replace('/','.'),false,GAME)); }
        finally { supplied.removeTransformer(observer); }
        if (!observed[0]) throw new IllegalStateException("Event prefix was not woven before listeners");
    }
    private static void fail(String reason) { installed=false; diagnostic=reason; }
    public static synchronized boolean install(Instrumentation supplied) {
        if (installed) return true;
        if (!Boolean.getBoolean(PROPERTY)) { diagnostic="disabled"; return false; }
        if (transformer!=null) { diagnostic="previous-install-failed"; return false; }
        if (supplied==null || !supplied.isRetransformClassesSupported()) { diagnostic="no-retransformation"; return false; }
        // Resolve filter dependencies before registration. Looking up DemandTransform.TARGETS
        // from the callback during its own initial class definition recursively defines it.
        final var targets=DemandTransform.TARGETS;
        instrumentation=supplied;
        Map<String,Boolean> observed=new HashMap<>();
        transformer=new ClassFileTransformer() {
            @Override public byte[] transform(ClassLoader loader,String name,Class<?> type,ProtectionDomain domain,byte[] bytes) {
                if (loader!=GAME || !targets.contains(name)) return null;
                try {
                    byte[] changed=DemandTransform.transform(name,bytes);
                    synchronized (observed) { observed.put(name,Boolean.TRUE); }
                    return changed;
                } catch (Throwable failure) {
                    fail("guard:"+name+":"+failure.getClass().getSimpleName());
                    synchronized (observed) { observed.put(name,Boolean.FALSE); }
                    return null;
                }
            }
        };
        diagnostic="installing";
        supplied.addTransformer(transformer,true);
        try {
            for (String name:targets) {
                Class<?> loaded=null;
                for (Class<?> type:supplied.getAllLoadedClasses())
                    if (type.getClassLoader()==GAME && type.getName().equals(name.replace('/','.'))) { loaded=type; break; }
                if (loaded==null) Class.forName(name.replace('/','.'),false,GAME);
                else {
                    if (!supplied.isModifiableClass(loaded)) throw new IllegalStateException("unmodifiable:"+name);
                    supplied.retransformClasses(loaded);
                }
                if (!Boolean.TRUE.equals(observed.get(name))) throw new IllegalStateException("unwoven:"+name);
            }
            // Publish last: partial transforms are harmless because every runtime hook is gated.
            for (String name:targets)
                if (!Boolean.TRUE.equals(observed.get(name))) throw new IllegalStateException("incomplete:"+name);
            installEventGate(supplied);
            diagnostic="active"; installed=true;
            return true;
        } catch (Throwable failure) {
            fail("install:"+failure.getClass().getSimpleName()+":"+failure.getMessage());
            supplied.removeTransformer(transformer);
            return false;
        }
    }
    /** Disables policy first; woven guards may remain as no-ops until process exit. */
    public static synchronized void remove() {
        installed=false;
        if (instrumentation!=null && transformer!=null) instrumentation.removeTransformer(transformer);
        diagnostic="removed";
    }
}
