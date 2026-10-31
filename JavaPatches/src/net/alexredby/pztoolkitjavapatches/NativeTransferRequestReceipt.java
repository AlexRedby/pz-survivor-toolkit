package net.alexredby.pztoolkitjavapatches;

import se.krka.kahlua.j2se.KahluaTableImpl;
import zombie.characters.IsoPlayer;
import zombie.inventory.ItemContainer;

/** Opaque Lua/JVM carrier: no exposed constructor or writable receipt fields. */
public final class NativeTransferRequestReceipt {
    final KahluaTableImpl action;
    final IsoPlayer actor;
    final KahluaTableImpl items;
    final ItemContainer source;
    final ItemContainer destination;
    final String boundary;
    String phase = "before";
    byte transaction;
    boolean claimed;
    boolean nested;
    Object nativeAction;
    se.krka.kahlua.vm.KahluaThread ownerThread;
    KahluaTableImpl environment;
    zombie.core.Transaction nativeTransaction;
    zombie.core.raknet.UdpConnection connection;
    NativeTransferRequestsLogic.ConnectionHistory history;
    boolean wireAmbiguous = true;
    private NativeTransferRequestReceipt(KahluaTableImpl action, IsoPlayer actor, KahluaTableImpl items,
            ItemContainer source, ItemContainer destination, String boundary) {
        this.action=action; this.actor=actor; this.items=items; this.source=source;
        this.destination=destination; this.boundary=boundary;
    }
    static NativeTransferRequestReceipt create(KahluaTableImpl action, IsoPlayer actor, KahluaTableImpl items,
            ItemContainer source, ItemContainer destination, String boundary) {
        return new NativeTransferRequestReceipt(action, actor, items, source, destination, boundary);
    }
    public KahluaTableImpl getAction() { return action; }
    public IsoPlayer getActor() { return actor; }
    public KahluaTableImpl getItems() { return items; }
    public ItemContainer getSource() { return source; }
    public ItemContainer getDestination() { return destination; }
    public String getBoundary() { return boundary; }
    public String getPhase() { return phase; }
    public int getTransaction() { return transaction; }
    public boolean hasNativeHandle() { return nativeTransaction != null; }
    public boolean isWireAmbiguous() { return NativeTransferRequestsLogic.wireAmbiguous(this); }
    public boolean matchesTransaction(KahluaTableImpl candidate, int value) {
        try { return NativeTransferRequestsLogic.matchesTransaction(this,candidate,value); }
        catch (Throwable ignored) { return false; }
    }
    public boolean hasNestedRequest() { return nested; }
    public boolean isCurrent(KahluaTableImpl candidate) { return NativeTransferRequestsLogic.current(this, candidate); }
    public boolean claim(KahluaTableImpl candidate) { return NativeTransferRequestsLogic.claim(this, candidate); }
}
