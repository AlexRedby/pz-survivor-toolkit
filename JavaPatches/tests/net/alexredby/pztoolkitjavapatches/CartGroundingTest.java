package net.alexredby.pztoolkitjavapatches;
import java.lang.reflect.Field;
import java.util.HashMap;
import java.util.List;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import sun.misc.Unsafe;
import zombie.core.math.PZMath;
import zombie.characters.IsoPlayer;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.inventory.types.InventoryContainer;
import zombie.core.skinnedmodel.ModelManager;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;
import zombie.scripting.objects.ModelScript;
import zombie.core.skinnedmodel.advancedanimation.AnimatedModel;
import zombie.core.skinnedmodel.animation.AnimationClip;
import zombie.core.skinnedmodel.animation.AnimationPlayer;
import zombie.core.skinnedmodel.animation.AnimationTrack;
import zombie.core.skinnedmodel.animation.Keyframe;
import zombie.core.skinnedmodel.model.Model;
import zombie.core.skinnedmodel.model.ModelInstance;
import zombie.core.skinnedmodel.model.ModelInstanceRenderData;
import zombie.core.skinnedmodel.model.ModelMesh;
import zombie.core.skinnedmodel.model.SkinningData;
import zombie.scripting.objects.ModelAttachment;
public final class CartGroundingTest {
 private static ModelScript model(String moduleName,String name) throws Exception {
  var manager=zombie.scripting.ScriptManager.instance;
  var module=manager.moduleMap.get(moduleName);
  if(module==null) {
   module=new zombie.scripting.objects.ScriptModule();module.name=moduleName;
   manager.moduleMap.put(moduleName,module);manager.moduleList.add(module);
   var field=manager.getClass().getDeclaredField("models");field.setAccessible(true);
   ((zombie.scripting.ScriptBucketCollection<?>)field.get(manager)).registerModule(module);
  }
  var existing=manager.getModelScript(moduleName+"."+name);
  if(existing!=null) return existing;
  var model=new ModelScript();model.name=name;model.InitLoadPP(name);model.setModule(module);manager.addModelScript(model);
  return model;
 }
 private static final class Player extends IsoPlayer {
  InventoryItem cart;
  ItemContainer inventory;
  boolean remote,action,motionDisabled;
  int resets;
  java.util.Stack<zombie.characters.CharacterTimedActions.BaseAction> actions=new java.util.Stack<>();
  zombie.ai.StateMachine machine;
  Player() {super(null,null,0,0,0);}
  @Override public boolean isLocalPlayer() {return !remote;}
  @Override public void resetEquippedHandsModels() {resets++;}
  @Override public java.util.Stack<zombie.characters.CharacterTimedActions.BaseAction> getCharacterActions() {
   if(actions==null) actions=new java.util.Stack<>();
   return actions;
  }
  @Override public boolean isNpc() {return false;}
  @Override public boolean isAiming() {return false;}
  @Override public boolean isSneaking() {return false;}
  @Override public float getVariableFloat(String name,float fallback) {return fallback;}
  @Override public void clearVariable(String name) {}
  @Override public boolean getVariableBoolean(String name) {
   return !motionDisabled && "ToolkitCartMotion".equals(name) || action && "IsPerformingAnAction".equals(name);
  }
  @Override public boolean isDead() {return false;}
  @Override public boolean hasHitReaction() {return false;}
  @Override public boolean isKnockedDown() {return false;}
  @Override public boolean isGettingUp() {return false;}
  @Override public boolean isGrappling() {return false;}
  @Override public boolean isBeingGrappled() {return false;}
  @Override public boolean isRagdollSimulationActive() {return false;}
  @Override public zombie.ai.StateMachine getStateMachine() {
   if(machine==null) machine=new zombie.ai.StateMachine(this);
   return machine;
  }
  @Override public boolean hasPath() {return false;}
  @Override public InventoryItem getPrimaryHandItem() {return cart;}
  @Override public InventoryItem getSecondaryHandItem() {return cart;}
  @Override public ItemContainer getInventory() {return inventory;}
  @Override public zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator getAdvancedAnimator() {return null;}
 }
 private static final class Cart extends InventoryItem {
  Cart(){super(null,null,null,(String)null);}
  @Override public String getWorldStaticModel(){return getStaticModel();}
 }
 private static final class World extends zombie.iso.objects.IsoWorldInventoryObject {
  World(){super((zombie.iso.IsoCell)null);}
  @Override public void invalidateRenderChunkLevel(long flags){}
 }
 private static void field(Object object,Class<?> owner,String name,Object value)throws Exception {
  var f=owner.getDeclaredField(name);f.setAccessible(true);f.set(object,value);
 }
 private static void handoff(Player player,InventoryItem item,Unsafe unsafe)throws Exception {
  var type=Class.forName("net.alexredby.pztoolkitjavapatches.CartTransition$State");
  var state=unsafe.allocateInstance(type);
  field(state,type,"item",item);field(state,type,"pickup",true);field(state,type,"rendered",true);
  field(state,type,"action",123L);field(state,type,"lastRender",System.nanoTime());field(state,type,"updated",System.nanoTime());
  field(state,type,"world",unsafe.allocateInstance(World.class));
  var action=(zombie.characters.CharacterTimedActions.BaseAction)unsafe.allocateInstance(zombie.characters.CharacterTimedActions.BaseAction.class);
  action.chr=player;field(state,type,"actionOwner",action);
  var states=CartTransition.class.getDeclaredField("states");states.setAccessible(true);
  ((java.util.Map<IsoPlayer,Object>)states.get(null)).put(player,state);
  CartTransition.end(player);
  var pending=CartTransition.class.getDeclaredField("pickupHandoffs");pending.setAccessible(true);
  var token=((java.util.Map<IsoPlayer,Object>)pending.get(null)).get(player);
  field(token,token.getClass(),"performed",true);field(token,token.getClass(),"held",item);
 }
 private static final class Instance extends ModelInstance {
  ModelAttachment attachment;
  @Override public ModelAttachment getAttachmentById(String id) {
   return attachment!=null && attachment.getId().equals(id)?attachment:null;
  }
 }
 private static Keyframe frame(int bone,float time,float x,float y,float z,float angle) {
  var result=new Keyframe(new org.lwjgl.util.vector.Vector3f(x,y,z),
   new org.lwjgl.util.vector.Quaternion(0,(float)Math.sin(angle/2),0,(float)Math.cos(angle/2)),
   new org.lwjgl.util.vector.Vector3f(1,1,1));
  result.bone=bone;result.boneName=bone==0?"root":"prop";result.time=time;
  return result;
 }
 private static void nativeExportPose() {
  // Captured Bob_Cart_Idle locals and live Prop1 model pose from B42.21, not the scaled raw track.
  var dummy=frame(0,0,0,0,0,0);dummy.boneName="Dummy01";
  dummy.rotation.set(-.7071068f,0,0,.7071067f);dummy.scale.set(.01f,.010000001f,.010000001f);
  var root=frame(1,0,0,1.4341615e-8f,-.0880282f,0);root.boneName="Bip01";
  root.rotation.set(.7071069f,0,0,.70710665f);
  var prop=frame(2,0,-.071653344f,.67678964f,-.17752668f,0);prop.boneName="Bip01_Prop1";
  prop.rotation.set(-.5689081f,-.41993275f,.568908f,.41993314f);
  prop.scale.set(.9999997f,.99999976f,.9999998f);
  var idle=new AnimationClip(1,List.of(dummy,root,prop),"Bob_Cart_Idle",true);
  var identity=new org.lwjgl.util.vector.Matrix4f();
  var boneMatrices=List.of(identity,identity,identity);
  var skeleton=new SkinningData(new HashMap<>(),boneMatrices,boneMatrices,boneMatrices,List.of(-1,0,1),
   new HashMap<>(java.util.Map.of("Dummy01",0,"Bip01",1,"Bip01_Prop1",2)));
  Matrix4f expected=new Matrix4f().set(
   -1.4305115e-6f,.95561385f,-.29462528f,0,
   -8.34465e-7f,-.29462644f,-.95561385f,0,
   -1.0000011f,-5.960458e-8f,-2.3841856e-7f,0,
   -.07165334f,.5887615f,-.17752649f,1);
  Matrix4f actual=new Matrix4f();
  if(!CartGrounding.referencePose(idle,skeleton,"Bip01_Prop1",actual) || !actual.equals(expected,.00001f))
   throw new AssertionError("real idle export does not match native live unit-scale pose: "+actual);
 }
 private static void rigidPose() throws Exception {
  Field unsafeField=Unsafe.class.getDeclaredField("theUnsafe");unsafeField.setAccessible(true);
  Unsafe unsafe=(Unsafe)unsafeField.get(null);
  var idle=new AnimationClip(1,List.of(frame(0,0,.2f,0,-.1f,.15f),frame(1,0,.3f,.4f,.5f,-.4f),
   frame(0,1,.8f,.2f,-.5f,.6f),frame(1,1,-.1f,.6f,.4f,.5f)),"Bob_Cart_Idle",true);
  var identity=new org.lwjgl.util.vector.Matrix4f();
  var skeleton=new SkinningData(new HashMap<>(),List.of(identity,identity),List.of(identity,identity),
   List.of(identity,identity),List.of(-1,0),new HashMap<>(java.util.Map.of("root",0,"prop",1)));
  var player=(AnimationPlayer)unsafe.allocateInstance(AnimationPlayer.class);
  Field skinningField=AnimationPlayer.class.getDeclaredField("skinningData");skinningField.setAccessible(true);
  skinningField.set(player,skeleton);
  var track=AnimationTrack.alloc();
  Matrix4f reference=new Matrix4f();
  try {
   track.startClip(idle,true,0);track.UpdateKeyframes(0);
   Matrix4f nativePose=PZMath.convertMatrix(player.getUnweightedModelTransform(track,1,
    new org.lwjgl.util.vector.Matrix4f()),new Matrix4f()).transpose();
   if(!CartGrounding.referencePose(idle,skeleton,"prop",reference) || !reference.equals(nativePose,.00001f))
    throw new AssertionError("reference disagrees with native authored idle pose");
   track.moveCurrentTimeValueTo(.5f);track.UpdateKeyframes(0);
   if(!CartGrounding.referencePose(idle,skeleton,"prop",new Matrix4f()) ||
    reference.equals(PZMath.convertMatrix(player.getUnweightedModelTransform(track,1,
     new org.lwjgl.util.vector.Matrix4f()),new Matrix4f()).transpose(),.00001f))
    throw new AssertionError("fixture must contain moving arms");
  } finally {track.release();}
  for(var frame:idle.getKeyframes()) {
   frame.scale.set(frame.bone==0?.01f:.8f,.01f,.02f);frame.rotation.scale(2);
  }
  float authoredRotation=idle.getKeyframes()[0].rotation.w;
  Matrix4f exported=new Matrix4f();
  if(!CartGrounding.referencePose(idle,skeleton,"prop",exported) || !exported.equals(reference,.00001f))
   throw new AssertionError("FBX export scale collapsed the cart instead of native unit bone scale");
  if(idle.getKeyframes()[0].rotation.w!=authoredRotation) throw new AssertionError("shared clip quaternion changed");
  if(CartGrounding.referencePose(idle,skeleton,"missing",new Matrix4f()) ||
   CartGrounding.referencePose(null,skeleton,"prop",new Matrix4f()))
   throw new AssertionError("missing reference accepted");
  var parent=new Instance();parent.animPlayer=player;
  parent.attachment=new ModelAttachment("parent");parent.attachment.setBone("prop");
  parent.attachment.getOffset().set(.05f,0,.08f);
  var instance=new Instance();instance.parent=parent;instance.parentBoneName="prop";
  instance.attachmentNameParent="parent";instance.attachmentNameSelf="self";instance.scale=.9f;
  instance.attachment=new ModelAttachment("self");instance.attachment.getOffset().set(.1f,.2f,-.3f);
  instance.attachment.getRotate().set(0,15,0);instance.attachment.setScale(.85f);
  instance.model=(Model)unsafe.allocateInstance(Model.class);
  Field meshField=Model.class.getField("mesh");meshField.setAccessible(true);
  meshField.set(instance.model,unsafe.allocateInstance(ModelMesh.class));
  var data=new ModelInstanceRenderData();data.modelInstance=instance;
  data.parent=new AnimatedModel.AnimatedModelInstanceRenderData();
  Matrix4f authoredParent=ModelInstanceRenderData.makeAttachmentTransform(parent.attachment,new Matrix4f());
  Matrix4f authoredSelf=ModelInstanceRenderData.makeAttachmentTransform(instance.attachment,new Matrix4f());
  Matrix4f self=new Matrix4f(authoredSelf);
  if(ModelInstanceRenderData.invertAttachmentSelfTransform) self.invert();
  for(int degree=0;degree<360;degree+=15) {
   Matrix4f root=new Matrix4f().rotateY((float)Math.toRadians(degree));
   data.parent.xfrm.set(root).transpose();
   Matrix4f expected=new Matrix4f(reference).mul(root).mul(authoredParent).mul(self).scale(instance.scale);
   data.xfrm.translation(degree*.01f,-.1f,.2f).rotateXYZ(.1f,.2f,.3f);
   Matrix4f actual=new Matrix4f();
   if(!CartGrounding.rigid(data,idle,actual) || !actual.equals(expected,.00001f))
    throw new AssertionError("moving arm pose changed rigid cart at "+degree);
  }
  if(!authoredParent.equals(ModelInstanceRenderData.makeAttachmentTransform(parent.attachment,new Matrix4f())) ||
   !authoredSelf.equals(ModelInstanceRenderData.makeAttachmentTransform(instance.attachment,new Matrix4f())))
   throw new AssertionError("shared attachment changed");
  // The rigid cart must survive an unavailable body palette instead of following the animated arm/AABB fallback.
  var character=(Player)unsafe.allocateInstance(Player.class);
  var cart=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
  character.inventory=new ItemContainer();character.cart=cart;cart.setContainer(character.inventory);
  cart.setModule("SaucedWheelbarrow");cart.setType("WheelbarrowWood");cart.setStaticModel("Base.WheelbarrowWood");
  instance.modelScript=model("Base","WheelbarrowWood");
  var body=new ModelInstanceRenderData();body.modelInstance=parent;
  var slot=new ModelSlotRenderData();slot.character=character;slot.modelData.add(body);slot.modelData.add(data);
  var mesh=instance.model.mesh;
  Field minimum=ModelMesh.class.getField("minXyz"),maximum=ModelMesh.class.getField("maxXyz");
  minimum.setAccessible(true);maximum.setAccessible(true);
  minimum.set(mesh,new Vector3f(-.01f));maximum.set(mesh,new Vector3f(.01f));
  Field animationModel=ModelManager.class.getDeclaredField("animModel");animationModel.setAccessible(true);
  Object previousModel=animationModel.get(ModelManager.instance);
  var animations=(ModelMesh)unsafe.allocateInstance(ModelMesh.class);animations.skinningData=skeleton;
  skeleton.animationClips.put("Bob_Cart_Idle",idle);
  try {
   animationModel.set(ModelManager.instance,animations);
   data.parent.xfrm.identity();
   Matrix4f expected=new Matrix4f(),delta=new Matrix4f();
   if(!CartGrounding.rigid(data,idle,expected)) throw new AssertionError("render fixture has no rigid reference");
   CartGrounding.lowerHandles(expected,"WheelbarrowWood");
   if(!CartGrounding.alignWood(expected,0,0,delta)) throw new AssertionError("render fixture cannot ground its wheel");
   if(CartGrip.render(slot,parent,idle,delta,"WheelbarrowWood",expected))
    throw new AssertionError("render fixture must reject IK without a body palette");
   for(float arm:new float[]{-.3f,-.1f,0,.2f,.4f}) {
    data.xfrm.translation(arm,.3f+arm*.2f,-.2f-arm).rotateXYZ(arm,arm*.5f,-arm).transpose();
    Matrix4f fallback=new Matrix4f(data.xfrm).transpose();
    if(!CartGrounding.ground(fallback,mesh.minXyz,mesh.maxXyz) || fallback.equals(expected,.00001f))
     throw new AssertionError("render fixture does not distinguish native arm fallback from the rigid cart");
    CartGrounding.render(slot);
    Matrix4f actual=new Matrix4f(data.xfrm).transpose();
    if(!actual.equals(expected,.00001f) || Math.abs(CartGrounding.woodenLowest(actual)-.008f)>.000001f)
     throw new AssertionError("failed IK restored the moving arm cart or lost wheel grounding: "+arm);
   }
   // Reproduce the native successful-pickup gap: an authoritative held cart exists,
   // while ordinary motion is disabled and native attachment data is high/pitched.
   character.motionDisabled=true;
   parent.attachment=null;instance.attachment=null;instance.attachmentNameParent=null;instance.attachmentNameSelf=null;
   instance.parentBoneName="prop";instance.scale=1;
   var worldMesh=(ModelMesh)unsafe.allocateInstance(ModelMesh.class);
   var ready=unsafe.allocateInstance(Class.forName("zombie.asset.Asset$PRIVATE"));
   field(ready,ready.getClass(),"currentState",zombie.asset.Asset.State.READY);
   field(worldMesh,zombie.asset.Asset.class,"priv",ready);
   field(mesh,zombie.asset.Asset.class,"priv",ready);
   var worldModel=(Model)unsafe.allocateInstance(Model.class);field(worldModel,Model.class,"mesh",worldMesh);
   var worldScript=model("Base","ShoppingCartModel");worldScript.scale=1;
   worldScript.setModelManagerKey("handoff-shopping-world");
   var loaded=ModelManager.class.getDeclaredField("modelMap");loaded.setAccessible(true);
   var loadedModels=(java.util.Map<String,Model>)loaded.get(ModelManager.instance);
   Model oldWorld=loadedModels.put(worldScript.getModelManagerKey(),worldModel);
   try {
    for(String name:new String[]{"WheelbarrowWood","WheelbarrowMetal","ShoppingCartModel"}) {
     var item=(Cart)unsafe.allocateInstance(Cart.class);item.worldScale=1;
     item.setModule(name.startsWith("Wheelbarrow")?"SaucedWheelbarrow":"SaucedCarts");
     item.setType(name.startsWith("Wheelbarrow")?name:"ShoppingCart");item.setStaticModel(name);item.setContainer(character.inventory);
     character.cart=item;instance.modelScript=model("Base",name);
     var profile=CartWheelbarrow.forModel(name);
     Matrix4f held=profile==null?CartShopping.held(new Matrix4f()):profile.held(new Matrix4f());
     mesh.transform=new Matrix4f(reference).invert().mul(held).transpose();
     worldMesh.transform=CartShopping.worldModel(new Matrix4f()).transpose();
     Matrix4f neutral=new Matrix4f(),correction=new Matrix4f();
     if(!CartGrounding.rigid(data,idle,neutral)) throw new AssertionError("handoff has no native rigid reference");
     CartGrounding.lowerHandles(neutral,name);
     if(!(profile==null?CartShopping.align(neutral,CartTransition.model(item),1,correction)
        :CartGrounding.alignWheelbarrow(neutral,profile,0,0,0,correction)))
      throw new AssertionError("handoff neutral reference refused: "+name);
     var raw=new Matrix4f(held).rotateLocalX(1.1f).translateLocal(0,.6f,.4f);
     data.xfrm.set(raw).transpose();CartGrounding.render(slot);
     if(!new Matrix4f(data.xfrm).transpose().equals(raw,.00001f))
      throw new AssertionError("disabled motion without a pickup token rewrote native transform");
     handoff(character,item,unsafe);
     if(!CartTransition.pickupHandoff(character) || CartMotionSync.visualEnabled(character))
      throw new AssertionError("fresh completion did not isolate render bridge from motion");
     for(int frame=0;frame<3;frame++) {
      data.xfrm.set(raw).transpose();CartGrounding.render(slot);
      if(!new Matrix4f(data.xfrm).transpose().equals(neutral,.00003f))
       throw new AssertionError("completion exposed high/pitched native attachment for "+name+" frame="+frame);
     }
     if(character.cart!=item || item.getContainer()!=character.inventory || item.getWorldItem()!=null || !character.motionDisabled)
      throw new AssertionError("render bridge changed native authority or locomotion");
     CartTransition.end(character);
    }
   } finally {
    if(oldWorld==null) loadedModels.remove(worldScript.getModelManagerKey());
    else loadedModels.put(worldScript.getModelManagerKey(),oldWorld);
   }
  } finally {animationModel.set(ModelManager.instance,previousModel);}
 }
 private static void capturedContacts() {
  // Actual VBO minima and final matrices captured together in B42.21 before the contact fix.
  String[] models={"ShoppingCartModel","WheelbarrowWood","WheelbarrowMetal"};
  Vector3f[] points={new Vector3f(110.0467f,8.371053f,.98356926f),
   new Vector3f(-2.1228965e-4f,-.004435286f,-4.0280633e-5f),new Vector3f(-23.5423f,-23.2973f,-2.97487f)};
  float[] minima={.045946702f,.03383575f,.054394957f};
  Matrix4f[] captured={
   new Matrix4f().set(-5.080325e-10f,7.381783e-10f,.104969054f,-.0016536561f,
    -2.2194229e-4f,.0016076594f,-6.051497e-8f,.05691298f,
    -.0021531826f,-1.6571165e-4f,-1.0280073e-8f,-.44702002f,0,0,0,1).transpose(),
   new Matrix4f().set(76.5f,2.8023098e-5f,-2.4333809e-5f,-.0060535767f,
    -4.1037783e-5f,30.694286f,-70.07218f,.16715112f,
    -9.11952e-6f,70.07218f,30.694283f,-.41188842f,0,0,0,1).transpose(),
   new Matrix4f().set(.0091743395f,2.9182563e-9f,3.3606993e-9f,.21714664f,
    -4.9214974e-9f,.008403477f,.003681045f,.2611238f,
    -1.0936676e-9f,-.0036810448f,.008403477f,-.8401939f,0,0,0,1).transpose()};
  Vector3f low=new Vector3f(-1000),high=new Vector3f(1000);
  for(int i=0;i<models.length;i++) {
   var contact=CartGrounding.contact(models[i]);
   if(contact==null || !points[i].equals(contact)) throw new AssertionError("wrong calibrated contact for "+models[i]);
   if(Math.abs(captured[i].transformPosition(new Vector3f(points[i])).y-minima[i])>1e-6f)
    throw new AssertionError("captured matrix disagrees with actual VBO minimum for "+models[i]);
   Matrix4f after=new Matrix4f(captured[i]),delta=new Matrix4f();
   if(!CartGrounding.align(after,low,high,contact,0,delta)
    || Math.abs(after.transformPosition(new Vector3f(points[i])).y-.008f)>1e-6f
    || Math.abs(delta.m31()-(.008f-minima[i]))>1e-6f)
    throw new AssertionError("actual wheel geometry still floats for "+models[i]);
   Matrix4f expected=new Matrix4f(captured[i]);expected.m31(after.m31());
   if(!after.equals(expected)) throw new AssertionError("contact correction changed orientation/scale for "+models[i]);
   Matrix4f pitched=new Matrix4f(captured[i]);
   CartGrounding.lowerHandles(pitched,models[i]);
   Vector3f tire=captured[i].transformPosition(new Vector3f(contact));
   if(i==1) tire.z+=.05f;
   if(pitched.transformPosition(new Vector3f(contact)).distance(tire)>1e-6f)
    throw new AssertionError("lowering handles moved wheel contact for "+models[i]);
   if(i==0 && !pitched.equals(captured[i])) throw new AssertionError("shopping cart was pitched");
   if(i>0) {
    Vector3f rawHandle=i==1?new Vector3f(.00172237f,.00541905f,-.00342593f)
      :new Vector3f(-7.409948f,6.614635f,82.79839f);
    Vector3f handle=captured[i].transformPosition(new Vector3f(rawHandle));
    Vector3f lowered=pitched.transformPosition(new Vector3f(rawHandle));
    if(i==1 ? Math.abs(handle.y-lowered.y-.0857464f)>.00001f
     : handle.y-lowered.y<.08f || handle.y-lowered.y>.10f)
     throw new AssertionError("handles not lowered to a relaxed arm height");
    if(i==1 ? !CartGrounding.alignWood(pitched,0,0,delta) || Math.abs(CartGrounding.woodenLowest(pitched)-.008f)>1e-6f
     : !CartGrounding.align(pitched,low,high,contact,0,delta)
       || Math.abs(pitched.transformPosition(new Vector3f(contact)).y-.008f)>1e-6f)
     throw new AssertionError("pitched tire not grounded");
    if(Math.abs(delta.m12())>1e-6f || Math.abs(delta.m21())>1e-6f)
     throw new AssertionError("cart pitch leaked into the actor's torso");
    // The old and new observed wooden tire vertices bracket the new lowest polygon edge.
    if(i==1 && pitched.transformPosition(new Vector3f(-2.1228965e-4f,-.004627711f,-1.199774e-4f)).y<.008f-1e-6f)
     throw new AssertionError("lowered handles put the old tire contact underground");
   }
   for(float lean:new float[]{-.1f,.1f}) {
    if(!CartGrounding.align(after.set(captured[i]),low,high,contact,lean,delta)) throw new AssertionError("lean rejected");
    Vector3f wheel=after.transformPosition(new Vector3f(contact));
    Vector3f fixed=captured[i].transformPosition(new Vector3f(contact));fixed.y=.008f;
    if(wheel.distance(fixed)>1e-6f) throw new AssertionError("bank moved the actual tire contact for "+models[i]);
    Vector3f handle=new Vector3f(points[i]).add(.001f,.002f,.003f);
    Vector3f cartHandle=after.transformPosition(new Vector3f(handle));
    delta.transformPosition(captured[i].transformPosition(handle));
    if(handle.distance(cartHandle)>1e-5f) throw new AssertionError("contact correction separated grip and cart");
   }
  }
  for(String model:new String[]{"ShoppingCartPartialModel","ShoppingCartFullModel","ShoppingCartFlashlightModel",
   "ShoppingCartFlashlightPartialModel","ShoppingCartFlashlightFullModel"})
   if(!points[0].equals(CartGrounding.contact(model))) throw new AssertionError("shop variant not calibrated: "+model);
  if(CartGrounding.contact("ShoppingCartModelExtra")!=null || CartGrounding.contact(null)!=null)
   throw new AssertionError("unverified model accepted");
  low.set(-.35f,0,-.6f);high.set(.35f,1,.6f);
  Matrix4f fallback=new Matrix4f().translation(0,-.15f,0);CartGrounding.ground(fallback,low,high);
  for(Vector3f invalid:new Vector3f[]{new Vector3f(Float.NaN,0,0),new Vector3f(0,Float.POSITIVE_INFINITY,0),new Vector3f(10,0,0)}) {
   Matrix4f actual=new Matrix4f().translation(0,-.15f,0);
   if(!CartGrounding.ground(actual,low,high,invalid) || !actual.equals(fallback))
    throw new AssertionError("invalid/outside calibrated contact did not use AABB fallback");
  }
 }
 private static void metalBankGait() {
  var profile=CartWheelbarrow.METAL;
  var source=profile.held(new Matrix4f());
  for(float bank:new float[]{(float)Math.toRadians(-7),0,(float)Math.toRadians(7)}) for(float gait:new float[]{0,-.24f}) {
   var actual=new Matrix4f(source);var delta=new Matrix4f();
   float pressure=Math.abs(bank);
   if(!CartGrounding.alignWheelbarrow(actual,profile,bank,pressure,gait,delta)
    || !actual.isFinite() || Math.abs(CartGrounding.wheelbarrowLowest(actual,profile)-.008f)>.00001f)
    throw new AssertionError("metal wheel lost cylindrical floor support: bank="+bank+" gait="+gait);
   // Independently sample both sidewalls around the calibrated tire, including every spin phase.
   for(float side:new float[]{-profile.halfWidth(),profile.halfWidth()}) for(int degree=0;degree<360;degree+=5) {
    float phase=(float)Math.toRadians(degree);
    var rim=profile.center(new Vector3f()).add(side,profile.radius()*(float)Math.cos(phase),profile.radius()*(float)Math.sin(phase));
    if(actual.transformPosition(rim).y<.008f-.00001f)
     throw new AssertionError("banked metal tire penetrates floor: bank="+bank+" gait="+gait+" phase="+degree);
   }
   for(boolean left:new boolean[]{true,false}) {
    var handle=new Vector3f();
    if(!CartGrip.handle(profile.model(),left,handle)) throw new AssertionError("metal handle calibration missing");
    var moved=delta.transformPosition(source.transformPosition(new Vector3f(handle)));
    moved.z+=CartSteeringMath.woodenShift(pressure,gait);
    if(moved.distance(actual.transformPosition(handle))>.00001f)
     throw new AssertionError("metal body/cart handle transforms separated: bank="+bank+" gait="+gait);
   }
  }
 }
 private static void remoteFillModel() throws Exception {
  Field field=Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);
  var unsafe=(Unsafe)field.get(null);
  var player=(Player)unsafe.allocateInstance(Player.class);player.remote=true;player.inventory=new ItemContainer();
  var item=(InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);player.cart=item;
  item.setModule("SaucedCarts");item.setType("ShoppingCart");item.setContainer(player.inventory);
  item.setStaticModel("ShoppingCartModel");
  var cached=new ModelInstance();cached.modelScript=model("Base",item.getStaticModel());
  var full=model("Base","ShoppingCartFullModel");
  player.primaryHandModel=cached;
  item.setStaticModel("Base.ShoppingCartFullModel");
  if(!cached.modelScript.getName().equals("ShoppingCartModel"))
   throw new AssertionError("native ModData fixture unexpectedly refreshed its cached model");
  CartGrounding.refreshRemoteModel(player);
  if(player.resets!=1 || player.primaryHandModel!=cached || player.cart!=item
   || !item.getStaticModel().equals("Base.ShoppingCartFullModel"))
   throw new AssertionError("remote fill mismatch must queue refresh without mutating models or equipment");
  cached.modelScript=full;player.resets=0;
  CartGrounding.refreshRemoteModel(player);
  if(player.resets!=0) throw new AssertionError("correct remote fill model was rebuilt");
  item.setStaticModel("ShoppingCartFullModel");CartGrounding.refreshRemoteModel(player);
  if(player.resets!=0 || CartGrounding.resolvedModel(item)!=full)
   throw new AssertionError("qualified and unqualified native names resolved to different model identities");
  for(String gate:new String[]{"local","action","stack","primaryOverride","secondaryOverride","unknownExpected",
   "unknownActual","foreignExpected","foreignActual","differentFamily","unsupportedItem","missingInstance"}) {
   player.remote=true;player.action=false;player.getCharacterActions().clear();
   player.overridePrimaryHandModel=player.overrideSecondaryHandModel=null;player.primaryHandModel=cached;
   item.setModule("SaucedCarts");item.setType("ShoppingCart");item.setStaticModel("ShoppingCartFullModel");
   cached.modelScript=model("Base","ShoppingCartModel");
   switch(gate) {
    case "local" -> player.remote=false;
    case "action" -> player.action=true;
    case "stack" -> player.getCharacterActions().add(null);
    case "primaryOverride" -> player.overridePrimaryHandModel="ShoppingCartModel";
    case "secondaryOverride" -> player.overrideSecondaryHandModel="Mug";
    case "unknownExpected" -> item.setStaticModel("OtherCartFullModel");
    case "unknownActual" -> cached.modelScript=model("Base","OtherCartModel");
    case "foreignExpected" -> {model("Foreign","ShoppingCartFullModel");item.setStaticModel("Foreign.ShoppingCartFullModel");}
    case "foreignActual" -> cached.modelScript=model("Foreign","ShoppingCartModel");
    case "differentFamily" -> {item.setModule("SaucedWheelbarrow");item.setType("WheelbarrowMetal");}
    case "unsupportedItem" -> item.setType("OtherCart");
    case "missingInstance" -> player.primaryHandModel=null;
   }
   CartGrounding.refreshRemoteModel(player);
   if(player.resets!=0) throw new AssertionError("remote fill refresh escaped its exact ownership gate: "+gate);
  }
  for(String name:new String[]{"ShoppingCartModel","ShoppingCartPartialModel","ShoppingCartFullModel",
   "ShoppingCartFlashlightModel","ShoppingCartFlashlightPartialModel","ShoppingCartFlashlightFullModel",
   "WheelbarrowWood","WheelbarrowMetal"}) {
   item.setModule(name.startsWith("Wheelbarrow")?"SaucedWheelbarrow":"SaucedCarts");
   item.setType(name.startsWith("Wheelbarrow")?name:"ShoppingCart");
   var expected=model("Base",name);item.setStaticModel("Base."+name);
   if(CartGrounding.resolvedModel(item)!=expected || !CartGrounding.sameModel(item,name)
    || CartGrounding.sameModel(item,"Foreign."+name))
    throw new AssertionError("native cart-model resolution lost its exact Base identity: "+name);
  }
 }
 public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
  remoteFillModel();
  nativeExportPose();
  rigidPose();
  capturedContacts();
  metalBankGait();
  Matrix4f wooden=new Matrix4f().set(76.5f,2.8023098e-5f,-2.4333809e-5f,-.0060535767f,
   -4.1037783e-5f,30.694286f,-70.07218f,.16715112f,
   -9.11952e-6f,70.07218f,30.694283f,-.41188842f,0,0,0,1).transpose();
  CartGrounding.lowerHandles(wooden,"WheelbarrowWood");
  Matrix4f straight=new Matrix4f(wooden);
  if(!CartGrounding.alignWood(straight,0,0,new Matrix4f())) throw new AssertionError("straight wooden grounding rejected");
  Matrix4f expectedStraight=new Matrix4f(wooden);expectedStraight.m31(straight.m31());
  if(!straight.equals(expectedStraight)) throw new AssertionError("zero bank changed the wooden baseline pose");
  for(int degree=-7;degree<=7;degree++) {
   float lean=(float)Math.toRadians(degree),pressure=(float)Math.toRadians(7);
   var retained=new Matrix4f(wooden);var delta=new Matrix4f();
   if(!CartGrounding.alignWood(retained,lean,pressure,-.12f,delta))
    throw new AssertionError("slalom clearance rejected");
   var center=retained.transformPosition(new Vector3f(CartWheelSpin.CENTER_X,CartWheelSpin.CENTER_Y,CartWheelSpin.CENTER_Z));
   if(Math.abs(-1.5*center.z-CartSteeringMath.woodenAxle(pressure,-.12f))>.00001)
    throw new AssertionError("slalom wheel must use retained clearance, not instantaneous bank");
   if(Math.abs(CartGrounding.woodenLowest(retained)-.008f)>.00001)
    throw new AssertionError("retaining slalom clearance lifted the wheel");
   for(boolean left:new boolean[]{true,false}) {
    var handle=new Vector3f();CartGrip.handle("WheelbarrowWood",left,handle);
    var point=delta.transformPosition(wooden.transformPosition(new Vector3f(handle)));
    point.z+=CartSteeringMath.woodenShift(pressure,-.12f);
    if(point.distance(retained.transformPosition(handle))>.00001)
     throw new AssertionError("slalom body and handle transforms disagree");
   }
  }
  float straightHandleY=0;
  for(boolean left:new boolean[]{true,false}) {
   var handle=new Vector3f();CartGrip.handle("WheelbarrowWood",left,handle);
   straightHandleY+=straight.transformPosition(handle).y/2;
  }
  for(float gaitShift:new float[]{0,-.03f,-.05f,-.06f,-.09f,-.12f,-.18f,-.24f}) for(int tick=-84;tick<=84;tick++) {
   float lean=(float)Math.toRadians(tick/12.0);
   Matrix4f actual=new Matrix4f(wooden),delta=new Matrix4f();
   if(!CartGrounding.alignWood(actual,lean,gaitShift,delta)) throw new AssertionError("wooden bank rejected");
   float minimum=Float.POSITIVE_INFINITY;
   for(int degree=0;degree<360;degree++) for(int side:new int[]{-1,1}) {
    double angle=Math.toRadians(degree);
    var rim=new Vector3f(CartWheelSpin.CENTER_X+side*.00024333253f,
     CartWheelSpin.CENTER_Y+CartWheelSpin.RADIUS*(float)Math.cos(angle),
     CartWheelSpin.CENTER_Z+CartWheelSpin.RADIUS*(float)Math.sin(angle));
    minimum=Math.min(minimum,actual.transformPosition(rim).y);
   }
   if(minimum<.008f-1e-6f || minimum>.008f+.00001f)
    throw new AssertionError("spinning wooden tire must stay grounded through all wheel phases: "+minimum);
   float meanHandleY=0;
   for(boolean left:new boolean[]{true,false}) {
    var handle=new Vector3f();CartGrip.handle("WheelbarrowWood",left,handle);
    var transformed=delta.transformPosition(wooden.transformPosition(new Vector3f(handle)));
    transformed.z+=CartSteeringMath.woodenShift(lean,gaitShift);
    var expected=actual.transformPosition(handle);meanHandleY+=expected.y/2;
    if(transformed.distance(expected)>1e-5f) throw new AssertionError("wooden cart and handle transforms disagree");
   }
   if(Math.abs(meanHandleY-straightHandleY)>(Math.abs(lean)<=Math.toRadians(3)?.0005f:.0012f))
    throw new AssertionError("turning lifted the mean wooden handle height: "+(meanHandleY-straightHandleY));
   var center=actual.transformPosition(new Vector3f(CartWheelSpin.CENTER_X,CartWheelSpin.CENTER_Y,CartWheelSpin.CENTER_Z));
   if(Math.abs(-1.5*center.z-CartSteeringMath.woodenAxle(lean,gaitShift))>.00001)
    throw new AssertionError("steering axle disagrees with the actual wooden wheel center");
   if(tick==0 && gaitShift==0 && !actual.equals(straight)) throw new AssertionError("zero bank is not the exact walking baseline");
   var expectedRun=new Matrix4f(straight);expectedRun.m32(expectedRun.m32()+gaitShift);
   if(tick==0 && !actual.equals(expectedRun,.000001f))
    throw new AssertionError("native Run changed the zero-bank wooden height/pitch");
  }
  Vector3f low=new Vector3f(-.35f,0,-.6f),high=new Vector3f(.35f,1,.6f);
  for(int degree=0;degree<360;degree+=15) {
   Matrix4f before=new Matrix4f().translation(.1f,-.15f,-.8f).rotateY((float)Math.toRadians(degree)).rotateX(.08f);
   Matrix4f after=new Matrix4f(before);
   if(!CartGrounding.ground(after,low,high)) throw new AssertionError("valid transform rejected");
   float lowest=Float.POSITIVE_INFINITY;
   for(int i=0;i<8;i++) {
    Vector3f point=new Vector3f((i&1)==0?low.x:high.x,(i&2)==0?low.y:high.y,(i&4)==0?low.z:high.z);
    after.transformPosition(point);lowest=Math.min(lowest,point.y);
   }
   if(Math.abs(lowest-.008f)>.00001f) throw new AssertionError("cart intersects floor at "+degree);
   before.m31(after.m31());
   if(!before.equals(after)) throw new AssertionError("grounding changed rotation/scale/position on floor");
  }
  Matrix4f far=new Matrix4f().translation(0,-5,0),copy=new Matrix4f(far);
  if(CartGrounding.ground(far,low,high) || !far.equals(copy)) throw new AssertionError("invalid pose was rewritten");
  for(float lean:new float[]{-.1f,0,.1f}) {
   Matrix4f before=new Matrix4f().translation(.2f,-.15f,-.8f),grounded=new Matrix4f(before);
   CartGrounding.ground(grounded,low,high);
   float groundDelta=grounded.m31()-before.m31();
   Matrix4f after=new Matrix4f(before),delta=new Matrix4f();
   if(!CartGrounding.align(after,low,high,lean,delta)) throw new AssertionError("cart lean rejected");
   Vector3f wheel=new Vector3f(.2f,.008f-groundDelta,-1.1f);
   delta.transformPosition(wheel);
   if(wheel.distance(.2f,.008f,-1.1f)>.00001f) throw new AssertionError("wheel contact moved when leaning");
   Vector3f point=new Vector3f(.2f,.7f,-.1f),actual=after.transformPosition(new Vector3f(point));
   delta.transformPosition(before.transformPosition(point));
   if(actual.distance(point)>.00001f) throw new AssertionError("cart and grip transforms disagree");
  }
  System.out.println("CART_GROUNDING_PASS");
 }
}
