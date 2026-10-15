package net.alexredby.pztoolkitjavapatches;
import java.lang.reflect.Field;
import java.util.HashMap;
import java.util.List;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import sun.misc.Unsafe;
import zombie.core.math.PZMath;
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
   if(pitched.transformPosition(new Vector3f(contact)).distance(tire)>1e-6f)
    throw new AssertionError("lowering handles moved wheel contact for "+models[i]);
   if(i==0 && !pitched.equals(captured[i])) throw new AssertionError("shopping cart was pitched");
   if(i>0) {
    Vector3f rawHandle=i==1?new Vector3f(.00172237f,.00541905f,-.00342593f)
      :new Vector3f(-7.409948f,6.614635f,82.79839f);
    Vector3f handle=captured[i].transformPosition(new Vector3f(rawHandle));
    Vector3f lowered=pitched.transformPosition(new Vector3f(rawHandle));
    if(handle.y-lowered.y<.08f || handle.y-lowered.y>.10f)
     throw new AssertionError("handles not lowered to a relaxed arm height");
    if(!CartGrounding.align(pitched,low,high,contact,0,delta)
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
 public static void main(String[] args) throws Exception {
  nativeExportPose();
  rigidPose();
  capturedContacts();
  Matrix4f wooden=new Matrix4f().set(76.5f,2.8023098e-5f,-2.4333809e-5f,-.0060535767f,
   -4.1037783e-5f,30.694286f,-70.07218f,.16715112f,
   -9.11952e-6f,70.07218f,30.694283f,-.41188842f,0,0,0,1).transpose();
  CartGrounding.lowerHandles(wooden,"WheelbarrowWood");
  for(float lean:new float[]{-.18f,0,.18f}) {
   Matrix4f actual=new Matrix4f(wooden),delta=new Matrix4f();
   if(!CartGrounding.alignWood(actual,lean,delta)) throw new AssertionError("wooden bank rejected");
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
   var handle=new Vector3f(.00172237f,.00541905f,-.00342593f);
   if(actual.transformPosition(new Vector3f(handle)).distance(delta.transformPosition(wooden.transformPosition(handle)))>1e-5f)
    throw new AssertionError("wooden bank detached the hands from the handles");
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
