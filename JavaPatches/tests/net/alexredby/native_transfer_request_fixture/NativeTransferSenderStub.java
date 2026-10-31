package net.alexredby.native_transfer_request_fixture;

import java.util.List;
import me.zed_0xff.zombie_buddy.Patch;
import net.alexredby.pztoolkitjavapatches.NativeTransferRequestsChecks;
import zombie.characters.IsoPlayer;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;

/** Explicitly installed only by NativeTransferRequestsChecks, never the production package scan. */
public final class NativeTransferSenderStub {
    private NativeTransferSenderStub() { }

    @Patch(className="zombie.core.TransactionManager", methodName="createItemTransaction", warmUp=true, strictMatch=true)
    public static final class Sender {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(0) IsoPlayer actor,
                @Patch.Argument(1) List<InventoryItem> items,
                @Patch.Argument(2) ItemContainer source, @Patch.Argument(3) ItemContainer destination,
                @Patch.Local("toolkitTestNativeRequestByte") byte value) {
            value = NativeTransferRequestsChecks.sender(actor, items, source, destination);
            return true;
        }

        @Patch.OnExit
        public static void exit(@Patch.Local("toolkitTestNativeRequestByte") byte value,
                @Patch.Return(readOnly=false) byte result) {
            result = value;
        }
    }
}
