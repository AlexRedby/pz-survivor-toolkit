import java.util.Arrays;
import org.joml.Matrix4f;
import sun.misc.Unsafe;
import zombie.inventory.InventoryItem;

/** In-memory probe checks only; never writes synthetic native evidence or touches OpenGL. */
public final class ShoppingWheelProbeCheck {
    public static final class Frame {
        InventoryItem item;
        Matrix4f[] relative;
        double[] phases={.1,.2,.3,.4},casters={.2,-.3};
    }
    private static void check(boolean condition,String reason){if(!condition)throw new AssertionError(reason);}
    private static void rejected(Runnable operation){
        boolean rejected=false;try{operation.run();}catch(IllegalStateException expected){rejected=true;}
        check(rejected,"invalid receipt accepted");
    }
    private static Frame frame()throws Exception {
        var f=Unsafe.class.getDeclaredField("theUnsafe");f.setAccessible(true);var unsafe=(Unsafe)f.get(null);
        var frame=new Frame();frame.item=(InventoryItem)unsafe.allocateInstance(InventoryItem.class);
        frame.item.setModule("SaucedCarts");frame.item.setType("ShoppingCart");frame.relative=new Matrix4f[7];
        for(int i=0;i<7;i++)frame.relative[i]=new Matrix4f().translation(i*.01f,i*.02f,-i*.03f).rotateY(i*.1f);
        frame.relative[0].identity();return frame;
    }
    private static ShoppingWheelProbe.Scope scope(boolean transpose)throws Exception {
        var scope=new ShoppingWheelProbe.Scope();scope.transpose=transpose;
        var cart=new Matrix4f().translation(.1f,.2f,.3f).rotateXYZ(.2f,.3f,.4f).scale(.7f);
        if(transpose)cart.transpose();ShoppingWheelProbe.snapshot(scope,frame(),cart);return scope;
    }
    private static float[] matrix(ShoppingWheelProbe.Scope scope,int part){
        // Independent API convention: native stored xfrm is transposed before relative multiplication.
        var parent=new Matrix4f().set(scope.cart);if(scope.transpose)parent.transpose();
        parent.mul(new Matrix4f().set(scope.relative[part]));if(scope.transpose)parent.transpose();return parent.get(new float[16]);
    }
    private static void submitted(ShoppingWheelProbe.Scope scope,int[][] runs){
        scope.submitted.clear();
        for(int[] run:runs)scope.submitted.add(new ShoppingWheelProbe.Submitted(scope,matrix(scope,run[2]),scope.transpose));
        scope.submitted.add(new ShoppingWheelProbe.Submitted(scope,scope.cart.clone(),scope.transpose));
    }
    public static void main(String[] args)throws Exception {
        int[][] runs={{0,3,0},{3,3,1},{6,3,2},{9,3,3},{12,3,4},{15,3,5},{18,3,6},{21,3,0}};
        for(boolean transpose:new boolean[]{false,true}) {
            var scope=scope(transpose);submitted(scope,runs);var parts=ShoppingWheelProbe.validate(scope,runs,24);
            for(int i=0;i<7;i++)check(ShoppingWheelProbe.equal(parts[i],matrix(scope,i)),"submitted part matrix changed");
            parts[1][0]+=3;check(!ShoppingWheelProbe.equal(parts[1],scope.submitted.get(1).matrix),"receipt exposed original call storage");
            scope.submitted.remove(scope.submitted.size()-1);rejected(()->ShoppingWheelProbe.validate(scope,runs,24));
            submitted(scope,runs);scope.submitted.set(2,new ShoppingWheelProbe.Submitted(scope,matrix(scope,3),transpose));
            rejected(()->ShoppingWheelProbe.validate(scope,runs,24));
            submitted(scope,runs);scope.submitted.set(2,new ShoppingWheelProbe.Submitted(scope,matrix(scope,2),!transpose));
            rejected(()->ShoppingWheelProbe.validate(scope,runs,24));
            submitted(scope,runs);scope.submitted.get(scope.submitted.size()-1).matrix[12]+=.1f;
            rejected(()->ShoppingWheelProbe.validate(scope,runs,24));
            submitted(scope,runs);scope.submitted.get(1).matrix[0]=Float.NaN;
            rejected(()->ShoppingWheelProbe.validate(scope,runs,24));
            submitted(scope,runs);rejected(()->ShoppingWheelProbe.validate(scope,runs,25));
            int[][] missing={{0,3,0},{3,3,1},{6,3,2},{9,3,3},{12,3,4},{15,3,5}};submitted(scope,missing);
            rejected(()->ShoppingWheelProbe.validate(scope,missing,18));
        }
        var original=new Matrix4f().translation(1,2,3);float[] copied=ShoppingWheelProbe.copy(original);original.identity();
        check(copied[12]==1&&copied[13]==2&&copied[14]==3,"copy retained mutable matrix");
        rejected(()->ShoppingWheelProbe.copy(new Matrix4f().m00(Float.NaN)));
        rejected(()->ShoppingWheelProbe.copy(null));
        rejected(()->ShoppingWheelProbe.finite(new double[]{0,Double.POSITIVE_INFINITY},2));
        rejected(()->ShoppingWheelProbe.finite(new double[]{0},2));
        var captured=scope(false);var source=frame();ShoppingWheelProbe.snapshot(captured,source,new Matrix4f());
        source.phases[0]=9;source.relative[0].translation(7,8,9);
        check(captured.phases[0]==.1&&captured.relative[0][12]==0,"Frame snapshot retained mutable input");
        var producerCart=new Matrix4f().translation(1,2,3);var producer=ShoppingWheelProbe.followPose(10,20,.4f,producerCart,1234);
        producerCart.identity();check(producer.x()==10&&producer.y()==20&&producer.angle()==.4f&&producer.producerNanoTime()==1234
            &&producer.cart()[12]==1&&producer.cart()[13]==2&&producer.cart()[14]==3,"native follow pose was not independently copied");
        rejected(()->ShoppingWheelProbe.followPose(Float.NaN,0,0,new Matrix4f(),1));
        String hash=ShoppingWheelProbe.positionHash(new float[]{1,2,3,-1,0,-0f});
        check(hash.equals(ShoppingWheelProbe.positionHash(new float[]{-1,0,-0f,1,2,3,1,2,3})),"point-set hash depends on UV duplication/order");
        rejected(()->{try{ShoppingWheelProbe.positionHash(new float[]{Float.NaN,0,0});}catch(RuntimeException e){throw e;}catch(Exception e){throw new AssertionError(e);}});
        check(ShoppingWheelProbe.eligible(100,0)&&!ShoppingWheelProbe.eligible(1_000_000_000L+ShoppingWheelProbe.INTERVAL-1,1_000_000_000L)
            &&ShoppingWheelProbe.eligible(1_000_000_000L+ShoppingWheelProbe.INTERVAL,1_000_000_000L),"sampling exceeds 20Hz");
        // With capture stopped, nested callbacks still mask and restore their parent scope.
        check(ShoppingWheelProbe.active.get()==null,"unexpected active capture");
        Object outer=ShoppingWheelProbe.begin(null,null,null,null,false);Object inner=ShoppingWheelProbe.begin(null,null,null,null,true);
        check(ShoppingWheelProbe.active.get()==inner,"nested scope was not installed");ShoppingWheelProbe.end(inner,true,null);
        check(ShoppingWheelProbe.active.get()==outer,"nested scope did not restore parent");ShoppingWheelProbe.end(outer,true,null);
        check(ShoppingWheelProbe.active.get()==null,"stopped callback leaked draw scope");
        System.out.println("SHOPPING_WHEEL_PROBE_CHECK_PASS (copied actual submissions, transpose, restoration, missing/failed/nonfinite rejection, nested stopped scopes, 20Hz)");
    }
}
