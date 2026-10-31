package net.alexredby.native_transfer_request_fixture;

import java.util.List;
import me.zed_0xff.zombie_buddy.Patch;
import net.alexredby.pztoolkitjavapatches.NativeTransferRequestsChecks;
import zombie.characters.IsoPlayer;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.core.Transaction;
import zombie.network.packets.ItemTransactionPacket;

/** Explicitly installed only by NativeTransferRequestsChecks, never the production package scan. */
public final class NativeTransferSenderStub {
    private NativeTransferSenderStub() { }

    @Patch(className="zombie.core.TransactionManager", methodName="createItemTransaction", warmUp=true, strictMatch=true)
    public static final class Sender {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(0) IsoPlayer actor,
                @Patch.Argument(1) List<InventoryItem> items,
                @Patch.Argument(2) ItemContainer source, @Patch.Argument(3) ItemContainer destination,
                @Patch.Local("toolkitTestNativeRequestStubbed") boolean stubbed,
                @Patch.Local("toolkitTestNativeRequestByte") byte value) {
            if (NativeTransferRequestsChecks.useNativeManager()) return false;
            stubbed = true;
            value = NativeTransferRequestsChecks.sender(actor, items, source, destination);
            return true;
        }

        @Patch.OnExit
        public static void exit(@Patch.Local("toolkitTestNativeRequestStubbed") boolean stubbed,
                @Patch.Local("toolkitTestNativeRequestByte") byte value,
                @Patch.Return(readOnly=false) byte result) {
            if (stubbed) result = value;
        }
    }

    /** Only consistency is replaced: the native request builds, writes and adds its own packet. */
    @Patch(className="zombie.core.TransactionManager", methodName="isConsistent", warmUp=true, strictMatch=true)
    public static final class Consistency {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(0) int itemId, @Patch.Argument(1) InventoryItem item,
                @Patch.Argument(2) ItemContainer source, @Patch.Argument(3) ItemContainer destination,
                @Patch.Argument(4) String extra, @Patch.Argument(5) ItemTransactionPacket packet,
                @Patch.Argument(6) IsoPlayer actor,
                @Patch.Local("toolkitTestConsistencyStubbed") boolean stubbed,
                @Patch.Local("toolkitTestConsistencyByte") byte value) {
            if (!NativeTransferRequestsChecks.useNativeManager()) return false;
            stubbed = true;
            value = NativeTransferRequestsChecks.nativeConsistency();
            return true;
        }
        @Patch.OnExit
        public static void exit(@Patch.Local("toolkitTestConsistencyStubbed") boolean stubbed,
                @Patch.Local("toolkitTestConsistencyByte") byte value,
                @Patch.Return(readOnly=false) byte result) {
            if (stubbed) result = value;
        }
    }

    @Patch(className="zombie.core.TransactionManager", methodName="add", warmUp=true, strictMatch=true)
    public static final class AddFaults {
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) Transaction transaction) {
            if (NativeTransferRequestsChecks.useNativeManager())
                NativeTransferRequestsChecks.afterNativeAdd(transaction);
        }
    }
}
