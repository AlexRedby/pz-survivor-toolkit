package net.alexredby.lootdemand;

import java.util.IdentityHashMap;

/** Once-only/reentry mechanics shared by native hooks and deterministic headless checks. */
final class DemandState<C> {
    interface Access<C> {
        boolean enabled();
        boolean authority();
        boolean target(C container);
        boolean explored(C container);
        void explored(C container,boolean value);
        void overlay(C container);
    }
    static final int PASS=0, OWNED=1, REENTRANT=2;
    private final Access<C> access;
    private final IdentityHashMap<C,Boolean> active=new IdentityHashMap<>();
    private long fills,reentries,failures,overlays,cancellations;
    DemandState(Access<C> access) { this.access=access; }
    synchronized int enter(C container) {
        if (!access.enabled() || !access.authority()) return PASS;
        if (active.containsKey(container)) { reentries++; return REENTRANT; }
        if (!access.target(container)) return PASS;
        active.put(container,Boolean.TRUE);
        // Publish before native callbacks; an error keeps partial contents and forbids blind retry.
        access.explored(container,true); fills++;
        return OWNED;
    }
    void exit(C container,int token,boolean failed) {
        if (token!=OWNED) return;
        synchronized (this) {
            if (active.remove(container)==null) return;
            if (failed) { failures++; return; }
        }
        // Keep completed state even if the visual refresh throws. Never generate again for that.
        access.overlay(container);
        synchronized (this) { overlays++; }
    }
    synchronized boolean cancel(C container) {
        if (!access.enabled() || !access.authority() || !access.target(container) || active.containsKey(container)) return false;
        if (!access.explored(container)) { access.explored(container,true); cancellations++; }
        return true;
    }
    synchronized long cancellations() { return cancellations; }
    synchronized boolean isActive(C container) { return active.containsKey(container); }
    synchronized long[] counts() { return new long[]{fills,reentries,failures,overlays,active.size()}; }
}
