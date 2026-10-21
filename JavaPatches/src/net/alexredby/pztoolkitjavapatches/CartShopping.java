package net.alexredby.pztoolkitjavapatches;

import org.joml.Matrix4f;
import org.joml.Quaternionf;
import org.joml.Vector3f;
import zombie.inventory.InventoryItem;

/** Shopping-cart action geometry; its imported mesh has nonuniform axis scales. */
final class CartShopping {
    static boolean item(InventoryItem item) {
        return item!=null && "SaucedCarts.ShoppingCart".equals(item.getFullType());
    }
    static boolean model(String model) {
        return model!=null && switch(model) {
            case "ShoppingCartModel", "ShoppingCartPartialModel", "ShoppingCartFullModel",
                "ShoppingCartFlashlightModel", "ShoppingCartFlashlightPartialModel", "ShoppingCartFlashlightFullModel" -> true;
            default -> false;
        };
    }
    // Native atlas ItemParams transform, before world yaw, for the current shopping FBX.
    static Matrix4f worldModel(Matrix4f out) {
        out.set(.002273866f,-.00014903705f,0,0,.000111277506f,.0016977666f,-7.437096e-11f,0,
            3.159179e-10f,4.819975e-9f,.11050479f,0,0,0,0,1);
        return support(out,1)?out:null;
    }
    // Measured axle-center separation and lowest tire vertex in the native VBO.
    private static final Vector3f AXLES=new Vector3f(218.725291729f,17.093925655f,-.006239582f);
    private static final Vector3f CONTACT=new Vector3f(110.046699524f,8.371052742f,.983569264f);
    private static final Vector3f BAR=new Vector3f(-150.07166f,343.47412f,-.0000065f);

    /** Level the four tire centers, preserving the bar horizontally; keep the imported axis scales. */
    static boolean support(Matrix4f transform,float laterScale) {
        if(transform==null || !transform.isFinite() || !Float.isFinite(laterScale) || laterScale<=0
            || transform.determinant()<=0) return false;
        var effective=new Matrix4f(transform).scale(laterScale);
        var forward=effective.transformDirection(AXLES,new Vector3f());
        var side=effective.transformDirection(new Vector3f(0,0,1));
        var normal=side.cross(forward,new Vector3f());
        if(normal.lengthSquared()<1e-12f) return false;
        normal.normalize();if(normal.y<0)normal.negate();
        if(normal.y<.9f) return false;
        var pivot=effective.transformPosition(BAR,new Vector3f());
        var rotation=new Quaternionf().rotationTo(normal,new Vector3f(0,1,0));
        var change=new Matrix4f().translation(pivot).rotate(rotation).translate(-pivot.x,-pivot.y,-pivot.z);
        change.mul(effective,effective);
        effective.m31(effective.m31()+.008f-effective.transformPosition(CONTACT,new Vector3f()).y);
        effective.scale(1/laterScale);
        if(!effective.isFinite()) return false;
        transform.set(effective);return true;
    }

    /** Match the world model's actual scale; the native hand attachment otherwise shrinks it about 5%. */
    static boolean align(Matrix4f transform,Matrix4f model,float worldScale,Matrix4f delta) {
        if(transform==null || delta==null || model==null || !model.isFinite() || !Float.isFinite(worldScale) || worldScale<=0
            || Math.abs(model.determinant())<1e-12f) return false;
        var residual=new Matrix4f(transform).mul(new Matrix4f(model).invert());
        if(!CartTransitionMath.blend(residual,residual,0,new Matrix4f())) return false;
        float scale=residual.getColumn(0,new Vector3f()).length();
        var adjusted=new Matrix4f(transform);
        var pivot=adjusted.transformPosition(BAR,new Vector3f());
        new Matrix4f().translation(pivot).scale(worldScale/scale).translate(-pivot.x,-pivot.y,-pivot.z).mul(adjusted,adjusted);
        if(!support(adjusted,1)) return false;
        transform.set(adjusted);
        // The actor keeps the native torso/gait; only the arms solve the corrected bar.
        delta.identity();return true;
    }

    static Matrix4f held(Matrix4f out) {return held(out,worldModel(new Matrix4f()),1);}

    // B42.21 native Bob_Cart_Idle attachment capture, shared by the six fill/light models.
    static Matrix4f held(Matrix4f out,Matrix4f model,float worldScale) {
        out.set(-5.080325e-10f,-.00022194229f,-.0021531826f,0,
            7.381783e-10f,.0016076594f,-.00016571165f,0,
            .104969054f,-6.051497e-8f,-1.0280073e-8f,0,
            -.0016536561f,.0033783615f,-.44702002f,1);
        return align(out,model,worldScale,new Matrix4f())?out:null;
    }
    static CartTransitionMath.Progress progress(double value,boolean setdown) {
        if(!Double.isFinite(value)) return null;
        double t=Math.max(0,Math.min(1,setdown?1-value:value));
        double body=CartTransitionMath.smooth(t);
        return new CartTransitionMath.Progress(0,CartTransitionMath.smooth((t-.10)/.60),
            CartTransitionMath.smooth((t-.55)/.27),body,0,0,0,0);
    }
    private CartShopping() {}
}
