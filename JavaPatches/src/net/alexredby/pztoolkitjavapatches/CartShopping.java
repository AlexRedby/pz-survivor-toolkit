package net.alexredby.pztoolkitjavapatches;

import org.joml.Matrix4f;
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
    // B42.21 native Bob_Cart_Idle attachment capture, shared by the six fill/light models.
    static Matrix4f held(Matrix4f out) {
        out.set(-5.080325e-10f,-.00022194229f,-.0021531826f,0,
            7.381783e-10f,.0016076594f,-.00016571165f,0,
            .104969054f,-6.051497e-8f,-1.0280073e-8f,0,
            -.0016536561f,.0033783615f,-.44702002f,1);
        var contact=CartGrounding.contact("ShoppingCartModel");
        out.m31(out.m31()+.008f-out.transformPosition(contact,new Vector3f()).y);
        return out;
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
