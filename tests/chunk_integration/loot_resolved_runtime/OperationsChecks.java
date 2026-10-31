package toolkit.lootresolved.bootstrap;

import java.util.concurrent.atomic.AtomicReference;
import zombie.inventory.InventoryItem;
import zombie.iso.InstanceTracker;

/** Ownership/overflow/exception negatives only; never initialized-game or timing proof. */
public final class OperationsChecks {
    private static void require(boolean value,String why){if(!value)throw new AssertionError(why);}
    private static void refused(Runnable work){try{work.run();throw new AssertionError("unsupported operation accepted");}catch(IllegalStateException expected){}}
    private static InventoryItem item(){return new InventoryItem("Base","OperationsGuard","OperationsGuard","Item_None");}
    public static void run() throws Exception {
        require(!OperationsScope.resolved(),"outside owner candidate");
        OperationsScope.Session owner=OperationsScope.begin(true,2);
        require(!OperationsScope.resolved(),"candidate during setup");OperationsScope.beginWindow();
        require(OperationsScope.resolved(),"owner candidate not selected");
        AtomicReference<Throwable> error=new AtomicReference<>();
        Thread foreign=new Thread(()->{try{
            require(!OperationsScope.resolved(),"foreign candidate selected");OperationsScope.factoryReturned(item());
            OperationsScope.incremented(null,1);refused(()->OperationsScope.begin(false,2));
            refused(OperationsScope::beginWindow);refused(OperationsScope::endWindow);refused(OperationsScope::close);
        }catch(Throwable problem){error.set(problem);}},"operations-foreign-check");
        foreign.start();foreign.join();require(error.get()==null,"foreign check:"+error.get());
        require(owner.itemCount==0 && owner.incrementCount==0 && OperationsScope.resolved(),"foreign observer/takeover affected owner");
        OperationsScope.endWindow();require(!OperationsScope.resolved(),"candidate after window");OperationsScope.close();
        require(!OperationsScope.resolved(),"candidate after close");
        for(boolean candidate:new boolean[]{false,true}) {
            OperationsScope.Session s=OperationsScope.begin(candidate,1);OperationsScope.beginWindow();
            require(OperationsScope.resolved()==candidate,"variant selection");OperationsScope.factoryReturned(item());
            refused(()->OperationsScope.factoryReturned(item()));require(s.poisoned(),"overflow poison missing");
            OperationsScope.endWindow();refused(OperationsScope::close);require(!OperationsScope.resolved(),"overflow close retained route");
            s=OperationsScope.begin(candidate,1);OperationsScope.incremented(item(),1);
            refused(()->OperationsScope.incremented(item(),1));require(s.poisoned(),"increment overflow poison missing");refused(OperationsScope::close);
            s=OperationsScope.begin(candidate,2);OperationsScope.failed(new RuntimeException("swallowed-native-factory"));
            require(s.poisoned(),"swallowed exception not sticky");refused(OperationsScope::close);require(!OperationsScope.resolved(),"failed close retained route");
            OperationsScope.begin(candidate,2);
            try{OperationsScope.beginWindow();throw new RuntimeException("body-failure");}
            catch(RuntimeException expected){OperationsScope.endWindow();}
            finally{OperationsScope.close();}require(!OperationsScope.resolved(),"exception-finally retained selector");
        }
        // Actual transformed private inc still performs the original update exactly once.
        InventoryItem actual=item();int before=InstanceTracker.get("Item Spawns",actual.getFullType());
        var inc=zombie.inventory.ItemSpawner.class.getDeclaredMethod("inc",InventoryItem.class,int.class);inc.setAccessible(true);
        OperationsScope.Session s=OperationsScope.begin(false,2);inc.invoke(null,actual,1);
        require(s.incrementCount==1 && s.increments[0]==actual && s.deltas[0]==1,"native increment observer missing");
        require(InstanceTracker.get("Item Spawns",actual.getFullType())==before+1,"native increment modified");
        InstanceTracker.adj("Item Spawns",actual.getFullType(),-1);OperationsScope.close();
        System.out.println("LOOT_OPERATIONS_SCOPE_CHECK_PASS ownership-overflow-exception-only");
    }
}
