package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.iso.BuildingDef;

public final class BasementRoomLookup {
    public static final boolean SUPPORTED = BasementRoomLookupLogic.SUPPORTED;

    private BasementRoomLookup() { }

    public static void prepare() {
        if (SUPPORTED) zombie.basements.Basements.class.getName();
    }

    public static final class State {
        private final BasementRoomLookupLogic.Snapshot snapshot;
        private State(BasementRoomLookupLogic.Snapshot snapshot) { this.snapshot = snapshot; }
    }

    public static State beforeMerge(BuildingDef receiving, boolean supported) {
        var snapshot = BasementRoomLookupLogic.beforeMerge(receiving, supported);
        return snapshot == null ? null : new State(snapshot);
    }

    public static int repair(BuildingDef receiving, State previous, boolean supported) {
        return BasementRoomLookupLogic.repair(receiving, previous == null ? null : previous.snapshot, supported);
    }

    @Patch(className="zombie.basements.Basements", methodName="mergeBuildings", strictMatch=true)
    public static class NativeBasementRoomLookup {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) zombie.iso.BuildingDef incoming,
                                 @Patch.Argument(1) zombie.iso.BuildingDef receiving,
                                 @Patch.Local("toolkitPreviousBuildingID") BasementRoomLookup.State previous) {
            BasementHallKey.beforeMerge(incoming, receiving, BasementHallKey.SUPPORTED);
            previous = BasementRoomLookup.beforeMerge(receiving, BasementRoomLookup.SUPPORTED);
        }

        @Patch.OnExit
        public static void exit(@Patch.Argument(0) zombie.iso.BuildingDef incoming,
                                @Patch.Argument(1) zombie.iso.BuildingDef receiving,
                                @Patch.Local("toolkitPreviousBuildingID") BasementRoomLookup.State previous) {
            BasementRoomLookup.repair(receiving, previous, BasementRoomLookup.SUPPORTED);
        }
    }
}
