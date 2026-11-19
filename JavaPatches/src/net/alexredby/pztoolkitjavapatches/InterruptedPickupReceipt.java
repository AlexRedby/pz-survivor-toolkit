package net.alexredby.pztoolkitjavapatches;

/** Opaque passive authority observation; neither a transfer nor cleanup permission. */
public final class InterruptedPickupReceipt {
    final InterruptedPickupObservation.Watch watch;
    InterruptedPickupReceipt(InterruptedPickupObservation.Watch watch) { this.watch = watch; }
    public boolean isConfirmed() { return InterruptedPickupObservation.confirmed(this); }
    public boolean isExpired() { return InterruptedPickupObservation.expired(this); }
    public void release() { InterruptedPickupObservation.release(this); }
}
