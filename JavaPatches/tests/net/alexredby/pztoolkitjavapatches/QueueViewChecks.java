package net.alexredby.pztoolkitjavapatches;

import java.lang.ref.WeakReference;
import java.lang.management.ManagementFactory;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.nio.file.Files;
import java.nio.file.Path;
import me.zed_0xff.zombie_buddy.Exposer;
import me.zed_0xff.zombie_buddy.PatchEngine;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.j2se.KahluaTableImpl;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaArray;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;
import zombie.Lua.LuaManager;

/** Actual game Kahlua tables and exposed globals; no game state or VM patches. */
public final class QueueViewChecks {
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static KahluaTableImpl table(J2SEPlatform platform) {
        return (KahluaTableImpl) platform.newTable();
    }

    private static KahluaTableImpl action(J2SEPlatform platform, KahluaTableImpl token) {
        KahluaTableImpl action = table(platform);
        action.rawset("toolkitQueueOperation", token);
        return action;
    }

    private static void unsupportedAndLifetime(J2SEPlatform platform) throws Exception {
        KahluaTableImpl token = table(platform);
        KahluaTableImpl action = action(platform, token);
        KahluaTableImpl list = table(platform);
        list.rawset(1, action);
        Object snapshot = QueueViewSnapshot.snapshot(list, null, action);
        check(snapshot != null, "plain direct snapshot");
        KahluaArray array = new KahluaArray();
        array.rawset(1, action);
        check(QueueViewSnapshot.snapshot(array, snapshot, action) == null, "array list accepted");
        list.setRewriteTable(table(platform));
        check(QueueViewSnapshot.snapshot(list, snapshot, action) == null, "list rewrite accepted");
        list.setRewriteTable(null);
        action.setRewriteTable(table(platform));
        check(QueueViewSnapshot.snapshot(list, snapshot, action) == null, "action rewrite accepted");
        action.setRewriteTable(null);
        token.setRewriteTable(table(platform));
        check(QueueViewSnapshot.snapshot(list, snapshot, action) == null, "token rewrite accepted");
        token.setRewriteTable(null);
        KahluaTableImpl classTable = table(platform);
        action.setMetatable(classTable);
        classTable.setRewriteTable(table(platform));
        check(QueueViewSnapshot.snapshot(list, snapshot, action) == null, "action metatable rewrite accepted");
        action.setMetatable(null);
        KahluaTableImpl extra = action(platform, token);
        list.rawset(3, extra);
        check(QueueViewSnapshot.snapshot(list, snapshot, action) == null, "hole/outlier accepted");
        list.rawset(3, null);
        list.rawset("named", extra);
        check(QueueViewSnapshot.snapshot(list, snapshot, action) == null, "non-sequence key accepted");
        list.rawset("named", null);
        KahluaTableImpl cycle = table(platform);
        cycle.setMetatable(cycle);
        action.setMetatable(cycle);
        check(QueueViewSnapshot.snapshot(list, snapshot, action) == null, "cyclic action metatable accepted");
        action.setMetatable(null);
        check(QueueViewSnapshot.snapshot(list, snapshot, action) == snapshot, "unsupported calls mutated saved identities");
        for (Class<?> type : new Class<?>[] {QueueViewSnapshot.class, QueueViewSnapshot.Snapshot.class}) {
            for (Field field : type.getDeclaredFields()) {
                check(!Modifier.isStatic(field.getModifiers()) || field.getType().isPrimitive()
                        || field.getType() == String.class, "static state can retain queue snapshots: " + field);
            }
        }
        WeakReference<?>[] released = releasedSnapshot(platform);
        for (int attempt = 0; attempt < 30 && anyAlive(released); attempt++) {
            System.gc();
            Thread.sleep(10);
        }
        check(!anyAlive(released), "caller-released snapshot retains its list/actions/token");
    }

    private static boolean anyAlive(WeakReference<?>[] values) {
        for (WeakReference<?> value : values) if (value.get() != null) return true;
        return false;
    }

    private static WeakReference<?>[] releasedSnapshot(J2SEPlatform platform) {
        KahluaTableImpl token = table(platform);
        KahluaTableImpl action = action(platform, token);
        KahluaTableImpl list = table(platform);
        list.rawset(1, action);
        Object snapshot = QueueViewSnapshot.snapshot(list, null, action);
        return new WeakReference<?>[] {new WeakReference<>(snapshot), new WeakReference<>(list),
                new WeakReference<>(action), new WeakReference<>(token)};
    }

    private static long unchangedAllocations(J2SEPlatform platform,
            com.sun.management.ThreadMXBean allocation, int length) {
        KahluaTableImpl token = table(platform);
        KahluaTableImpl list = table(platform);
        // Insert in reverse order: projection must follow numeric Lua order,
        // never the backing map's insertion order.
        for (int index = length; index > 0; index--) list.rawset(index, action(platform, token));
        Object current = list.rawget(length / 2);
        Object snapshot = QueueViewSnapshot.snapshot(list, null, current);
        check(snapshot != null, "large sequence rejected");
        check(QueueViewSnapshot.currentIndex(snapshot).intValue() == length / 2,
                "snapshot follows map insertion order");
        for (int warm = 0; warm < 200; warm++) QueueViewSnapshot.snapshot(list, snapshot, current);
        long thread = Thread.currentThread().threadId();
        long before = allocation.getThreadAllocatedBytes(thread);
        for (int repeat = 0; repeat < 100; repeat++) {
            check(QueueViewSnapshot.snapshot(list, snapshot, current) == snapshot,
                    "unchanged sequence replaced snapshot");
        }
        return (allocation.getThreadAllocatedBytes(thread) - before) / 100;
    }

    private static void allocationScaling(J2SEPlatform platform) {
        if (!(ManagementFactory.getThreadMXBean() instanceof com.sun.management.ThreadMXBean allocation)
                || !allocation.isThreadAllocatedMemorySupported()) {
            System.out.println("QUEUE_VIEW_ALLOCATION_CHECK_UNAVAILABLE");
            return;
        }
        allocation.setThreadAllocatedMemoryEnabled(true);
        long small = unchangedAllocations(platform, allocation, 100);
        long large = unchangedAllocations(platform, allocation, 10000);
        // Kahlua len() boxes O(log N) search keys. Per-entry keys/arrays would
        // exceed this generous fixed allowance by orders of magnitude at 10k.
        check(large < 4096 && large <= small + 2048,
                "unchanged scan allocates per entry: 100=" + small + ", 10000=" + large);
        System.out.println("QUEUE_VIEW_ALLOCATION_BYTES_PER_SCAN 100=" + small + " 10000=" + large);
    }

    public static void main(String[] args) throws Exception {
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", QueueViewChecks.class.getClassLoader());
        Class<?> bridge = Exposer.getClassesWithGlobalLuaMethod().stream()
                .filter(type -> type.getName().equals("net.alexredby.pztoolkitjavapatches.QueueViewSnapshot"))
                .findFirst().orElseThrow(() -> new AssertionError("ZombieBuddy did not discover the queue view bridge"));
        check(Path.of(bridge.getProtectionDomain().getCodeSource().getLocation().toURI())
                .equals(Path.of(System.getProperty("pz.test.patch.jar"))), "bridge did not come from the built JAR");
        J2SEPlatform platform = new J2SEPlatform();
        KahluaTable env = platform.newEnvironment();
        LuaManager.platform = platform;
        LuaManager.env = env;
        LuaManager.exposer = new LuaManager.Exposer(new KahluaConverterManager(), platform, env);
        Exposer.afterExposeAll();
        KahluaThread thread = new KahluaThread(platform, env);
        thread.debugOwnerThread = Thread.currentThread();
        LuaManager.thread = thread;
        String lua = """
            assert(type(toolkitQueueViewSnapshot)=='function')
            assert(type(toolkitQueueViewCurrentIndex)=='function')
            local token={}
            local class={};class.__index=class
            local function action(t)return setmetatable({toolkitQueueOperation=t or token},class)end
            local a,b,c=action(),action(),action()
            local list={a,b,c}
            local snapshot=assert(toolkitQueueViewSnapshot(list,nil,b))
            assert(type(snapshot)=='userdata' and toolkitQueueViewCurrentIndex(snapshot)==2)
            assert(toolkitQueueViewSnapshot(list,snapshot,b)==snapshot)
            assert(toolkitQueueViewSnapshot(list,snapshot,c)==snapshot)
            assert(toolkitQueueViewCurrentIndex(snapshot)==3)
            assert(toolkitQueueViewSnapshot(list,snapshot,{})==snapshot)
            assert(toolkitQueueViewCurrentIndex(snapshot)==nil)
            local function changed(current)
                local next=assert(toolkitQueueViewSnapshot(list,snapshot,current))
                assert(next~=snapshot);snapshot=next
                assert(toolkitQueueViewSnapshot(list,snapshot,current)==snapshot)
            end
            list[1],list[2]=list[2],list[1];changed(a)
            list[2]=action();changed(a)
            list[2].toolkitQueueOperation={};changed(b)
            list[3]=list[1];changed(list[1])
            assert(toolkitQueueViewCurrentIndex(snapshot)==3)
            list[4]=action();changed(list[4])
            table.remove(list,2);changed(b)
            local replacement={list[1],list[2],list[3]}
            assert(toolkitQueueViewSnapshot(replacement,snapshot,b)~=snapshot)
            list={a,a,a};snapshot=assert(toolkitQueueViewSnapshot(list,nil,a))
            assert(toolkitQueueViewCurrentIndex(snapshot)==3)
            list={};snapshot=assert(toolkitQueueViewSnapshot(list,snapshot,a))
            assert(toolkitQueueViewCurrentIndex(snapshot)==nil)
            assert(toolkitQueueViewSnapshot(list,snapshot,nil)==snapshot)
            assert(toolkitQueueViewCurrentIndex({})==nil)
            assert(toolkitQueueViewSnapshot(nil,nil,nil)==nil)
            assert(toolkitQueueViewSnapshot(false,nil,nil)==nil)
            assert(toolkitQueueViewSnapshot({a}, {}, a)~=nil)
            assert(toolkitQueueViewSnapshot(setmetatable({a},{}),nil,a)==nil)
            assert(toolkitQueueViewSnapshot({{}},nil,nil)==nil)
            assert(toolkitQueueViewSnapshot({{toolkitQueueOperation=false}},nil,nil)==nil)
            assert(toolkitQueueViewSnapshot({action(setmetatable({},{}))},nil,nil)==nil)
            local inherited=setmetatable({}, {toolkitQueueOperation=token})
            assert(inherited.toolkitQueueOperation==token)
            assert(toolkitQueueViewSnapshot({inherited},nil,nil)==nil)
            local calls=0
            local functional=setmetatable({}, {__index=function()calls=calls+1;return token end})
            assert(toolkitQueueViewSnapshot({functional},nil,nil)==nil and calls==0)
            functional.toolkitQueueOperation=token
            assert(toolkitQueueViewSnapshot({functional},nil,nil)~=nil and calls==0)
            local eqClass={__eq=function()return true end}
            local eqAction=setmetatable({toolkitQueueOperation=token},eqClass)
            assert(toolkitQueueViewSnapshot({eqAction},nil,nil)==nil)
            local inheritedEq=setmetatable({},eqClass)
            assert(toolkitQueueViewSnapshot({setmetatable({toolkitQueueOperation=token},inheritedEq)},nil,nil)==nil)
            local ordinary=action();local stable={ordinary}
            snapshot=assert(toolkitQueueViewSnapshot(stable,nil,nil))
            class.__eq=function()return true end
            assert(toolkitQueueViewSnapshot(stable,snapshot,nil)==nil)
            class.__eq=nil
            assert(toolkitQueueViewSnapshot(stable,snapshot,nil)==snapshot)
            """;
        Object[] result = thread.pcall(LuaCompiler.loadstring(lua, "QueueViewChecks.lua", env), new Object[0]);
        check(Boolean.TRUE.equals(result[0]), "Kahlua vectors failed: " + java.util.Arrays.toString(result));
        Path project = Path.of(System.getProperty("pz.test.project"));
        env.rawset("TestProjectionSource", Files.readString(project.resolve(
                "PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueProjection.lua")));
        String regression = Files.readString(project.resolve("tests/test_action_queue_projection.lua"));
        result = thread.pcall(LuaCompiler.loadstring(regression, "test_action_queue_projection.lua", env), new Object[0]);
        check(Boolean.TRUE.equals(result[0]), "Native projection integration failed: " + java.util.Arrays.toString(result));
        unsupportedAndLifetime(platform);
        allocationScaling(platform);
        System.out.println("QUEUE_VIEW_CHECKS_PASS (actual Kahlua globals, exact identities, unsupported shapes and caller-owned lifetime)");
    }
}
