package zombie.characters;

import java.lang.reflect.Field;
import java.util.ArrayList;
import sun.misc.Unsafe;
import zombie.characters.animals.IsoAnimal;
import zombie.characters.animals.datas.AnimalData;
import zombie.core.skinnedmodel.advancedanimation.AnimationVariableHandle;
import zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot;
import zombie.iso.Vector2;
import zombie.network.GameClient;
import zombie.network.fields.character.Prediction;
import zombie.network.packets.character.AnimalPacket;
import zombie.vehicles.BaseVehicle;

/** Real immutable parser and trailer methods, with inert unrelated world/animation fixture callbacks. */
public final class GhostDecoderChecks {
 static Unsafe unsafe;
 public static final class Animal extends IsoAnimal {
  Animal(){super(null);}
  AnimalData fixtureData;Stats fixtureStats;
  @Override public AnimalData getData(){return fixtureData;}
  @Override public Stats getStats(){return fixtureStats;}
  @Override public float getAnimalTrailerSize(){return 3;}
  @Override public void ensureOnTile(){}
  @Override public void clearVariable(String key){}
  @Override public void setOnFloor(boolean value){}
  @Override public IAnimationVariableSlot setVariable(String key,boolean value){return null;}
  @Override public IAnimationVariableSlot setVariable(AnimationVariableHandle key,boolean value){return null;}
  @Override public void setAnimalAttackingOnClient(boolean value){}
  @Override public void setIsAlerted(boolean value){}
  @Override public boolean isAlerted(){return false;}
  @Override public void setHoursSurvived(double value){}
  @Override public void setWeight(float value){}
  @Override public void setHealth(float value){}
  @Override public void removeFromWorld(){}
  @Override public void removeFromSquare(){}
  @Override public boolean isExistInTheWorld(){return false;}
  @Override public float getX(){return 0;}
  @Override public float getY(){return 0;}
  @Override public float getZ(){return 0;}
  @Override public float setX(float value){return value;}
  @Override public float setY(float value){return value;}
 }
 static void set(Object target,String name,Object value)throws Exception{
  for(Class<?> type=target.getClass();type!=null;type=type.getSuperclass()){
   try{Field field=type.getDeclaredField(name);field.setAccessible(true);field.set(target,value);return;}catch(NoSuchFieldException absent){}
  }
  throw new NoSuchFieldException(name);
 }
 static Animal animal()throws Exception{
  Animal animal=(Animal)unsafe.allocateInstance(Animal.class);
  animal.fixtureData=(AnimalData)unsafe.allocateInstance(AnimalData.class);animal.fixtureStats=new Stats();
  return animal;
 }
 static void require(boolean value,String message){if(!value)throw new AssertionError(message);}
 public static void main(String[] args)throws Exception{
  Field field=Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);unsafe=(Unsafe)field.get(null);
  zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
  boolean patched=args.length==1&&args[0].equals("patched");
  if(patched) me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches",GhostDecoderChecks.class.getClassLoader());
  GameClient.client=true;
  Animal animal=animal(),neighbor=animal();animal.animalId=123;animal.onlineId=42;animal.setItemID(321);
  BaseVehicle trailer=(BaseVehicle)unsafe.allocateInstance(BaseVehicle.class);
  zombie.core.physics.Transform transform=new zombie.core.physics.Transform();transform.setIdentity();set(trailer,"jniTransform",transform);
  set(trailer,"animals",new ArrayList<>(java.util.List.of(neighbor)));neighbor.setVehicle(trailer);trailer.setCurrentTotalAnimalSize(3);
  NetworkPlayerAI ai=(NetworkPlayerAI)unsafe.allocateInstance(NetworkPlayerAI.class);
  set(ai,"player",animal);set(ai,"character",animal);set(ai,"direction",new Vector2());set(ai,"distance",new Vector2());set(ai,"prediction",new Prediction());
  AnimalPacket packet=new AnimalPacket();packet.location=2;packet.vehicleId.set(trailer);
  ai.parse(packet);
  require(animal.getVehicle()==trailer&&trailer.getAnimals().contains(animal)&&trailer.getAnimals().size()==2&&trailer.getCurrentTotalAnimalSize()==6,"real parse2 failed to reproduce stale trailer membership/capacity");
  packet.location=3;ai.parse(packet);ai.parse(packet);
  if(patched){
   require(animal.getVehicle()==null&&!trailer.getAnimals().contains(animal)&&trailer.getAnimals().size()==1&&trailer.getCurrentTotalAnimalSize()==3,"woven real parse3 failed repair");
  }else{
   require(animal.getVehicle()==trailer&&trailer.getAnimals().contains(animal)&&trailer.getAnimals().size()==2&&trailer.getCurrentTotalAnimalSize()==6,"unpatched real parse3 unexpectedly repaired baseline");
  }
  require(animal.getAnimalID()==123&&animal.getOnlineID()==42&&animal.getItemID()==321&&neighbor.getVehicle()==trailer,"identity/neighbors changed");
  System.out.println("GHOST_DECODER_CHECKS_PASS mode="+(patched?"woven":"original")+" realParse2=true realParse3="+(patched?"repaired":"retained-ghost"));
 }
}
