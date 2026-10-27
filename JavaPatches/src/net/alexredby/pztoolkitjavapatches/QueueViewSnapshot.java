package net.alexredby.pztoolkitjavapatches;

import se.krka.kahlua.integration.annotations.LuaMethod;
import se.krka.kahlua.j2se.KahluaTableImpl;
import se.krka.kahlua.vm.KahluaTable;

/** Exact ordered identities for display projection only; never an action permission. */
public final class QueueViewSnapshot {
    private QueueViewSnapshot() {}

    /** Opaque, caller-owned state. No queue, action or snapshot is stored globally. */
    public static final class Snapshot {
        private final KahluaTableImpl list;
        private final Double[] keys;
        private final KahluaTableImpl[] actions;
        private final KahluaTableImpl[] tokens;
        private Double currentIndex;

        private Snapshot(KahluaTableImpl list, Double[] keys, KahluaTableImpl[] actions,
                         KahluaTableImpl[] tokens, Double currentIndex) {
            this.list = list;
            this.keys = keys;
            this.actions = actions;
            this.tokens = tokens;
            this.currentIndex = currentIndex;
        }
    }

    private static boolean plain(KahluaTableImpl table) {
        return table.getMetatable() == null && table.getRewriteTable() == null;
    }

    private static boolean identityEquality(KahluaTableImpl action) {
        // PZ rawget also walks metatables. Inspect each own __eq without invoking
        // callbacks or following reload rewrites; reject cycles/deep exotic chains.
        KahluaTable meta = action.getMetatable();
        for (int depth = 0; meta != null; depth++) {
            if (depth >= 64 || !(meta instanceof KahluaTableImpl table)
                    || table.getRewriteTable() != null || table.delegate.get("__eq") != null) {
                return false;
            }
            meta = table.getMetatable();
        }
        return true;
    }

    @LuaMethod(name = "toolkitQueueViewSnapshot", global = true)
    public static Object snapshot(Object value, Object previous, Object current) {
        if (!(value instanceof KahluaTableImpl list) || !plain(list)) return null;
        int length = list.len();
        // Together with non-null numeric entries below, equality excludes holes,
        // outlying numeric entries and named keys, regardless of map iteration order.
        if (length < 0 || list.delegate.size() != length) return null;
        Snapshot saved = previous instanceof Snapshot snapshot ? snapshot : null;
        boolean sameLength = saved != null && saved.keys.length == length;
        boolean unchanged = sameLength && saved.list == list;
        Double[] keys = sameLength ? saved.keys : new Double[length];
        KahluaTableImpl[] actions = unchanged ? null : new KahluaTableImpl[length];
        KahluaTableImpl[] tokens = unchanged ? null : new KahluaTableImpl[length];
        Double currentIndex = null;
        for (int index = 0; index < length; index++) {
            Double key = keys[index];
            if (key == null) keys[index] = key = Double.valueOf(index + 1);
            Object entry = list.delegate.get(key);
            if (!(entry instanceof KahluaTableImpl action) || action.getRewriteTable() != null
                    || !identityEquality(action)) return null;
            // An own non-nil token wins before __index. Inherited/functional
            // token semantics and tokens with __eq belong to the Lua fallback.
            Object operation = action.delegate.get("toolkitQueueOperation");
            if (!(operation instanceof KahluaTableImpl token) || !plain(token)) return null;
            if (unchanged && (saved.actions[index] != action || saved.tokens[index] != token)) {
                unchanged = false;
                actions = new KahluaTableImpl[length];
                tokens = new KahluaTableImpl[length];
                System.arraycopy(saved.actions, 0, actions, 0, index);
                System.arraycopy(saved.tokens, 0, tokens, 0, index);
            }
            if (!unchanged) {
                actions[index] = action;
                tokens[index] = token;
            }
            if (entry == current) currentIndex = key; // Old Lua loop keeps the last duplicate.
        }
        if (unchanged) {
            saved.currentIndex = currentIndex;
            return saved;
        }
        return new Snapshot(list, keys, actions, tokens, currentIndex);
    }

    @LuaMethod(name = "toolkitQueueViewCurrentIndex", global = true)
    public static Double currentIndex(Object value) {
        return value instanceof Snapshot snapshot ? snapshot.currentIndex : null;
    }
}
