package net.alexredby.animaltimerprobe;
import java.util.*;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.vehicles.BaseVehicle;
import zombie.network.GameServer;
public final class Main {
 public static BaseVehicle target;
 public static final Map<Short,Integer> counts=new LinkedHashMap<>();
 public static final ThreadLocal<ArrayDeque<BaseVehicle>> stack=ThreadLocal.withInitial(ArrayDeque::new);
 @LuaMethod(name="animalTimerObserve",global=true)
 public static String observe(BaseVehicle vehicle) {
  target=vehicle; counts.clear();
  for(var animal:vehicle.getAnimals()) counts.put(animal.getOnlineID(),0);
  return "armed="+counts;
 }
 @LuaMethod(name="animalTimerResult",global=true)
 public static String result() { String text="periodicSendCounts="+counts;target=null;return text; }
 public static void countDirectSend(Short id) {
  if(!GameServer.server || target==null || stack.get().peek()!=target || !counts.containsKey(id)) return;
  var frames=new Throwable().getStackTrace();
  if(frames.length>2 && frames[2].getClassName().equals("zombie.vehicles.BaseVehicle") && frames[2].getMethodName().equals("update")) counts.put(id,counts.get(id)+1);
 }
 public static void main(String[] args) {System.out.println("[ANIMAL_TIMER_PROBE] observation only");}
 @Patch(className="zombie.vehicles.BaseVehicle",methodName="update",warmUp=true,strictMatch=true)
 public static class VehicleScope {
  @Patch.OnEnter public static void enter(@Patch.This BaseVehicle vehicle) {stack.get().push(vehicle);}
  @Patch.OnExit public static void exit() {stack.get().pop();}
 }
 @Patch(className="zombie.popman.animal.AnimalSynchronizationManager",methodName="setSendToClients",warmUp=true,strictMatch=true)
 public static class CountSends {
  @Patch.OnEnter public static void enter(@Patch.Argument(0) Short id) {
   Main.countDirectSend(id);
  }
 }
}
