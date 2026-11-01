package net.alexredby.bookcontrolsprobe;

import java.util.Arrays;
import java.util.Set;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.j2se.KahluaTableImpl;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.stdlib.BaseLib;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaThread;

/** Correctness only: stock Kahlua calls, with no game, UI, server or native startup. */
public final class MonotonicClockChecks {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Exception {
        var platform = new J2SEPlatform();
        var environment = platform.newTable();
        BaseLib.register(environment);
        Object originalType = environment.rawget("type");
        Main.installTimingClock(environment);
        Object callback = environment.rawget("bookControlsMonotonicMs");
        check(callback instanceof JavaFunction && callback == Main.timingClock(), "actual singleton JavaFunction missing");
        check(callback.getClass() == Main.MonotonicClock.class, "unexpected native callback class");
        Main.installTimingClock(environment);
        check(environment.rawget("bookControlsMonotonicMs") == callback, "reinstallation changed clock identity");
        check(environment.rawget("type") == originalType, "installer replaced an unrelated global");

        var info = (KahluaTableImpl) environment.rawget("bookControlsTimingClockInfo");
        check(info.getMetatable() == null && info.getRewriteTable() == null, "clock metadata must be a plain table");
        check(info.delegate.keySet().equals(Set.of("schema", "timer", "units", "monotonic", "relativeOrigin",
                "source", "functionClass", "nativeClock")), "clock metadata keys changed");
        check(info.delegate.values().stream().allMatch(value -> value instanceof Double
                || value instanceof Boolean || value instanceof String), "clock metadata contains nonscalar data");
        check(Double.valueOf(1).equals(info.rawget("schema")) && "System.nanoTime".equals(info.rawget("timer"))
                && "ms".equals(info.rawget("units")) && Boolean.TRUE.equals(info.rawget("monotonic"))
                && Boolean.TRUE.equals(info.rawget("relativeOrigin"))
                && "disposable-jvm-probe".equals(info.rawget("source"))
                && callback.getClass().getName().equals(info.rawget("functionClass"))
                && Boolean.TRUE.equals(info.rawget("nativeClock")), "clock metadata differs from callback");

        var thread = new KahluaThread(System.out, platform, environment);
        thread.debugOwnerThread = Thread.currentThread();
        var checks = LuaCompiler.loadstring("""
            local clock = bookControlsMonotonicMs
            if type(clock) ~= 'function' then return false end
            local last = clock()
            for i = 1, 64 do
                local value = clock()
                if type(value) ~= 'number' or value - value ~= 0 or value < 0 or value < last then return false end
                last = value
            end
            return true, clock == bookControlsMonotonicMs
            """, "book-controls-monotonic-clock", environment);
        Object[] result = thread.pcall(checks, new Object[0]);
        check(result.length == 3 && Boolean.TRUE.equals(result[0]) && Boolean.TRUE.equals(result[1])
                && Boolean.TRUE.equals(result[2]), "Lua clock checks failed: " + Arrays.toString(result));

        var read = LuaCompiler.loadstring("return bookControlsMonotonicMs()", "book-controls-clock-read", environment);
        var work = LuaCompiler.loadstring("local total=0; for i=1,512 do total=total+i end; return total",
                "book-controls-clock-unit-check", environment);
        long firstStart = System.nanoTime();
        double first = (Double) thread.call(read, new Object[0]);
        long firstEnd = System.nanoTime();
        check(Double.valueOf(131328).equals(thread.call(work, new Object[0])), "bounded Lua work did not execute");
        long lastStart = System.nanoTime();
        double last = (Double) thread.call(read, new Object[0]);
        long lastEnd = System.nanoTime();
        double elapsed = last - first;
        // The callback samples lie within these Java brackets. This checks units,
        // not speed: there is no latency target, sleep or repeated performance bank.
        double rounding = 0.000001;
        check(Double.isFinite(elapsed) && elapsed >= (lastStart - firstEnd) / 1_000_000.0 - rounding
                && elapsed <= (lastEnd - firstStart) / 1_000_000.0 + rounding,
                "Lua clock delta is not native elapsed milliseconds");
        System.out.println("BOOK_CONTROLS_MONOTONIC_CLOCK_PASS singleton=verified luaType=function numeric=finite monotonic=true units=ms nativeScale=verified gameStarted=false");
    }
}
