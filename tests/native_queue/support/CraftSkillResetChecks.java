package zombie.characters;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.HashMap;
import sun.misc.Unsafe;
import zombie.characters.skills.PerkFactory;
import zombie.characters.skills.PerkFactory.Perk;
import zombie.characters.skills.PerkFactory.Perks;
import zombie.network.GameClient;

/** Real B42 XP/level methods; allocate only inert player state without opening a world or GUI. */
public final class CraftSkillResetChecks {
 public static final class Player extends IsoPlayer {
  boolean local;
  Player(){super(null);}
  @Override public boolean isLocalPlayer(){return local;}
  @Override public boolean isAsleep(){return false;}
  @Override public long playGainExperienceLevelSound(){return 0;}
  void init()throws Exception{
   Field field=IsoGameCharacter.class.getDeclaredField("perkList");field.setAccessible(true);field.set(this,new ArrayList<>());
   xp=new XP(this);
  }
 }
 static void check(boolean ok,String why){if(!ok)throw new AssertionError(why);}
 static void restore(Player player,Perk perk,float originalXp,int originalLevel){
  var xp=player.getXp();
  if(xp.getXP(perk)!=originalXp||player.getPerkLevel(perk)!=originalLevel){
   xp.setXPToLevel(perk,0);xp.AddXP(perk,originalXp,false,false,false,false);player.setPerkLevelDebug(perk,originalLevel);
  }
  check(xp.getXP(perk)==originalXp&&player.getPerkLevel(perk)==originalLevel,"native reset differs: "+perk);
 }
 public static void main(String[] args)throws Exception{
  Field field=Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);Unsafe unsafe=(Unsafe)field.get(null);
  zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();PerkFactory.init();
  zombie.Lua.LuaManager.platform=new se.krka.kahlua.j2se.J2SEPlatform();
  zombie.Lua.LuaManager.env=zombie.Lua.LuaManager.platform.newTable();
  zombie.Lua.LuaManager.env.rawset("Events",zombie.Lua.LuaManager.platform.newTable());
  GameClient.client=false;
  int checks=0;
  for(boolean local:new boolean[]{false,true})for(int changedLevel:new int[]{0,3}){
   Player player=(Player)unsafe.allocateInstance(Player.class);player.init();player.local=local;
   var xp=player.getXp();HashMap<Perk,Float> beforeXp=new HashMap<>();HashMap<Perk,Integer> beforeLevels=new HashMap<>();
   for(Perk perk:PerkFactory.PerkList){
    float value=perk==Perks.Fitness||perk==Perks.Strength?0:12.25f;
    int level=perk==Perks.Fitness||perk==Perks.Strength?5:0;
    if(perk==Perks.Carving){level=1;value=perk.getTotalXpForLevel(level)+12.25f;}
    if(perk==Perks.Woodwork){level=2;value=perk.getTotalXpForLevel(level)+7.75f;}
    xp.xpMap.put(perk,value);player.setPerkLevelDebug(perk,level);beforeXp.put(perk,value);beforeLevels.put(perk,level);
   }
   xp.setTotalXP(123.75f);
   if(!local){
    xp.setXPToLevel(Perks.Carving,0);xp.AddXPNoMultiplier(Perks.Carving,beforeXp.get(Perks.Carving));
    check(xp.getXP(Perks.Carving)==0,"old remote reset did not reproduce its no-op bug");
   }
   for(Perk perk:new Perk[]{Perks.Carving,Perks.Woodwork}){
    xp.xpMap.put(perk,999.25f);player.setPerkLevelDebug(perk,changedLevel);
    float unchanged=xp.getXP(perk);player.setPerkLevelDebug(perk,changedLevel);
    check(xp.getXP(perk)==unchanged,"level setter unexpectedly changed XP");
    restore(player,perk,beforeXp.get(perk),beforeLevels.get(perk));
   }
   xp.setTotalXP(123.75f);check(xp.getTotalXp()==123.75f,"total XP differs");
   for(Perk perk:PerkFactory.PerkList){
    check(xp.getXP(perk)==beforeXp.get(perk)&&player.getPerkLevel(perk)==beforeLevels.get(perk),"unrelated/passive skill changed: "+perk);
    checks++;
   }
  }
  System.out.println("CRAFT_SKILL_RESET_CHECKS_PASS realNative=true localAndRemote=true passiveLevel5Xp0Untouched=true perkChecks="+checks);
 }
}
