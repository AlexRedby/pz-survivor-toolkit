package net.alexredby.pztoolkitjavapatches;

import org.joml.Matrix4f;
import org.joml.Vector3fc;
import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;

/** Keep the held cart above the character's floor without changing shared attachments. */
public final class CartGrounding {
    private static final ThreadLocal<Matrix4f> matrix = ThreadLocal.withInitial(Matrix4f::new);

    public static boolean ground(Matrix4f transform, Vector3fc low, Vector3fc high) {
        float lowest=Float.POSITIVE_INFINITY;
        for(int i=0;i<8;i++) {
            float x=(i&1)==0?low.x():high.x(), y=(i&2)==0?low.y():high.y(), z=(i&4)==0?low.z():high.z();
            lowest=Math.min(lowest,transform.m01()*x+transform.m11()*y+transform.m21()*z+transform.m31());
        }
        if(!Float.isFinite(lowest) || Math.abs(lowest)>=1) return false;
        transform.m31(transform.m31()-lowest+0.008f);
        return true;
    }

    public static void render(ModelSlotRenderData slot) {
        if(!(slot.character instanceof IsoPlayer player) || !player.getVariableBoolean("ToolkitCartMotion")
            || !CartSteeringHooks.supportedCart(player)) return;
        String name=player.getPrimaryHandItem().getStaticModel();
        for(var data:slot.modelData) {
            var instance=data.modelInstance;
            if(instance.parent==null || instance.modelScript==null || !instance.modelScript.getName().equals(name)
                || instance.model==null || instance.model.mesh==null) continue;
            Matrix4f transform=matrix.get().set(data.xfrm).transpose();
            if(ground(transform,instance.model.mesh.minXyz,instance.model.mesh.maxXyz)) data.xfrm.set(transform).transpose();
        }
    }

    private CartGrounding() {}
}
