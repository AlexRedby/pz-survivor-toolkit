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
    public boolean hasNestedRequest() { return nested; }
    public boolean isCurrent(KahluaTableImpl candidate) { return NativeTransferRequestsLogic.current(this, candidate); }
    public boolean claim(KahluaTableImpl candidate) { return NativeTransferRequestsLogic.claim(this, candidate); }
}
