package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.WeakHashMap;
import org.joml.Matrix4f;
import org.lwjgl.BufferUtils;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL15;
import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.model.Model;
import zombie.core.skinnedmodel.model.ModelInstanceRenderData;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;
import zombie.core.skinnedmodel.model.VertexBufferObject;
import zombie.core.skinnedmodel.shader.Shader;
import zombie.core.skinnedmodel.shader.ShaderManager;

/** Draw the authored wooden wheel separately without changing its shared mesh. */
public final class CartWheelSpin {
    // shortcut: source vertex ordering is calibrated to this exact Workshop mesh; a changed mesh falls back to native drawing.
    private static final String MESH_HASH="0f99448cda120bad9f324f38bdbf994f8788ab6731473533475fb6eaf3f4c948";
    static final int WHEEL_VERTICES=1114, VERTICES=8116, STRIDE=32;
    static final float CENTER_X=-6.642862e-6f, CENTER_Y=-.0041269097f, CENTER_Z=-.0010569958f;
    static final float RADIUS=.001062454f;
    static final double WORLD_RADIUS=RADIUS*76.5*1.5;
    private static final WeakHashMap<ModelInstanceRenderData, Double> phases=new WeakHashMap<>();
    private static final WeakHashMap<VertexBufferObject, int[][]> meshes=new WeakHashMap<>();
    private static final Matrix4f wheelTransform=new Matrix4f();
    private static boolean errorLogged;

    static double advance(double phase, double acceptedTravel) {
        if(!Double.isFinite(acceptedTravel) || Math.abs(acceptedTravel)>1) return phase;
        return Math.IEEEremainder(phase-acceptedTravel/WORLD_RADIUS,Math.PI*2);
    }

    /** Snapshot the simulation angle; NaN clears recycled render data before eligibility checks. */
    public static synchronized void prepare(ModelSlotRenderData slot, double phase) {
        for(var data:slot.modelData) {
            phases.remove(data);
            if(Double.isFinite(phase) && data.modelInstance!=null && data.modelInstance.modelScript!=null
                && "WheelbarrowWood".equals(data.modelInstance.modelScript.getName())) phases.put(data,phase);
        }
    }

    private static synchronized Double phase(ModelInstanceRenderData data) { return phases.get(data); }

    static Matrix4f transform(Matrix4f cart, double phase, Matrix4f out) {
        return out.set(cart).transpose().translate(CENTER_X,CENTER_Y,CENTER_Z)
            .rotateX((float)phase).translate(-CENTER_X,-CENTER_Y,-CENTER_Z).transpose();
    }

    /** Each run is [first index, index count, wheel flag]; every triangle belongs to one part. */
    static int[][] ranges(int[] elements) {
        if(elements==null || elements.length==0 || elements.length%3!=0) return null;
        var result=new ArrayList<int[]>();
        int[] run=null;
        boolean wheel=false, body=false;
        for(int i=0;i<elements.length;i+=3) {
            int part=elements[i]<WHEEL_VERTICES?1:0;
            for(int j=0;j<3;j++) if(elements[i+j]<0 || elements[i+j]>=VERTICES
                || (elements[i+j]<WHEEL_VERTICES?1:0)!=part) return null;
            if(part==1) wheel=true; else body=true;
            if(run==null || run[2]!=part) { run=new int[]{i,0,part};result.add(run); }
            run[1]+=3;
        }
        return wheel && body?result.toArray(int[][]::new):null;
    }

    private static Object field(VertexBufferObject buffer, String name) throws ReflectiveOperationException {
        Field field=VertexBufferObject.class.getDeclaredField(name);
        field.setAccessible(true);
        return field.get(buffer);
    }

    private static int[][] mesh(VertexBufferObject buffer) {
        if(meshes.containsKey(buffer)) return meshes.get(buffer);
        int[][] runs=null;
        boolean ready=false;
        int binding=GL11.glGetInteger(GL15.GL_ARRAY_BUFFER_BINDING);
        try {
            var handle=(VertexBufferObject.Vbo)field(buffer,"handle");
            var format=(VertexBufferObject.VertexFormat)field(buffer,"vertexFormat");
            int position=format.indexOf(VertexBufferObject.VertexType.VertexArray);
            if(handle==null || handle.vboId<=0 || handle.eboId<=0) return null;
            ready=true;
            if(format.getStride()!=STRIDE || position<0 || format.getElement(position).byteOffset!=0) return null;
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER,handle.vboId);
            int bytes=GL15.glGetBufferParameteri(GL15.GL_ARRAY_BUFFER,GL15.GL_BUFFER_SIZE);
            if(bytes!=VERTICES*STRIDE) return null;
            ByteBuffer raw=BufferUtils.createByteBuffer(bytes);
            GL15.glGetBufferSubData(GL15.GL_ARRAY_BUFFER,0,raw);
            byte[] vertices=new byte[bytes];raw.get(vertices);
            if(!MESH_HASH.equals(HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(vertices)))) return null;
            var elements=(int[])field(buffer,"elements");
            if(elements!=null && elements.length==handle.numElements) runs=ranges(elements);
            if(runs!=null) System.out.println("[PZToolkitJavaPatches] Wooden wheel mesh verified: "+runs.length+" original index ranges");
        } catch(Exception error) {
            ready=true;
            if(!errorLogged) { errorLogged=true;System.err.println("[PZToolkitJavaPatches] Wooden wheel disabled: "+error); }
        } finally {
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER,binding);
            if(ready) meshes.put(buffer,runs);
            if(ready && runs==null && !errorLogged) {
                errorLogged=true;
                System.err.println("[PZToolkitJavaPatches] Wooden wheel disabled: source mesh does not match calibrated geometry");
            }
        }
        return runs;
    }

    /** OnEnter for Model.DrawSolid; true skips the original draw after rendering both parts. */
    public static boolean render(Model model, ModelSlotRenderData slot, ModelInstanceRenderData data) {
        if(!(slot.character instanceof IsoPlayer) || data.modelInstance==null
            || data.modelInstance.modelScript==null
            || !"WheelbarrowWood".equals(data.modelInstance.modelScript.getName())
            || data.modelInstance.parent==null || !model.isStatic || model.mesh==null || model.mesh.vb==null) return false;
        Double phase=phase(data);
        if(phase==null) return false;
        int[][] runs=mesh(model.mesh.vb);
        if(runs==null) return false;
        Shader shader=ShaderManager.instance.getOrCreateShader("basicEffect",true,false);
        if(shader==null || shader.getID()==0) return false;
        int oldArray=GL11.glGetInteger(GL15.GL_ARRAY_BUFFER_BINDING);
        int oldElements=GL11.glGetInteger(GL15.GL_ELEMENT_ARRAY_BUFFER_BINDING);
        shader.Start();
        try {
            shader.startCharacter(slot,data);
            shader.setScale(slot.finalScale);
            transform(data.xfrm,phase,wheelTransform);
            boolean blend=model.mesh.vb.BeginDraw(shader);
            try {
                for(int[] run:runs) {
                    shader.setTransformMatrix(run[2]==1?wheelTransform:data.xfrm,true);
                    GL11.glDrawElements(GL11.GL_TRIANGLES,run[1],GL11.GL_UNSIGNED_INT,(long)run[0]*Integer.BYTES);
                }
            } finally {
                shader.setTransformMatrix(data.xfrm,true);
                model.mesh.vb.FinishDraw(shader,blend);
            }
        } finally {
            shader.setScale(1);
            shader.End();
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER,oldArray);
            GL15.glBindBuffer(GL15.GL_ELEMENT_ARRAY_BUFFER,oldElements);
        }
        return true;
    }

    private CartWheelSpin() {}
}
