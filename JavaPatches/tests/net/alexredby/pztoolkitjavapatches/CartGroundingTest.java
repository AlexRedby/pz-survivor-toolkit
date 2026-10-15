package net.alexredby.pztoolkitjavapatches;
import org.joml.Matrix4f;
import org.joml.Vector3f;
public final class CartGroundingTest {
 public static void main(String[] args) {
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
  System.out.println("CART_GROUNDING_PASS");
 }
}
