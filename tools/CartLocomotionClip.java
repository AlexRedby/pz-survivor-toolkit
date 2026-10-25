package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Locale;
import java.util.TreeSet;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import javax.xml.parsers.DocumentBuilderFactory;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import jassimp.AiPostProcessSteps;
import jassimp.Jassimp;
import org.joml.Matrix4f;
import zombie.core.math.PZMath;
import zombie.core.skinnedmodel.HelperFunctions;
import zombie.core.skinnedmodel.animation.AnimationPlayer;
import zombie.core.skinnedmodel.animation.AnimationClip;
import zombie.core.skinnedmodel.animation.AnimationTrack;
import zombie.core.skinnedmodel.animation.AnimatorsBoneTransform;
import zombie.core.skinnedmodel.animation.BoneAxis;
import zombie.core.skinnedmodel.animation.Keyframe;
import zombie.core.skinnedmodel.advancedanimation.AnimLayer;
import zombie.core.skinnedmodel.advancedanimation.AnimNode;
import zombie.core.skinnedmodel.advancedanimation.AnimBoneWeight;
import zombie.core.skinnedmodel.advancedanimation.AnimTransition;
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode;
import zombie.core.skinnedmodel.model.SkinningData;
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton;
import zombie.core.skinnedmodel.model.jassimp.ImportedSkeletonParams;
import zombie.core.skinnedmodel.model.jassimp.JAssImpImporter;
import zombie.core.skinnedmodel.model.jassimp.ProcessedAiSceneParams;
import zombie.iso.Vector2;

/** Cart-only root representation; Bip01 motion moves into its children's local keys. */
public final class CartLocomotionClip {
    private static final float TOLERANCE=5e-5f;

    private static Object field(Object object,String name) throws Exception {
        var field=object.getClass().getDeclaredField(name);field.setAccessible(true);return field.get(object);
    }

    /** Native skinnedTo performs the stock 35-to-45 mapping, including absent Nub identity tracks. */
    @SuppressWarnings("unchecked")
    static CartShoppingPickupGenerate.Source read(Path path,SkinningData target) throws Exception {
        var params=ProcessedAiSceneParams.create();
        params.scene=Jassimp.importFile(path.toString(),EnumSet.of(AiPostProcessSteps.MAKE_LEFT_HANDED,
            AiPostProcessSteps.REMOVE_REDUNDANT_MATERIALS));
        params.mode=JAssImpImporter.LoadMode.AnimationOnly;params.animBonesScaleModifier=1;params.skinnedTo=target;
        if(path.toString().toLowerCase(Locale.ROOT).endsWith(".fbx")) {
            params.animBonesScaleModifier=.01f;params.animBonesRotateModifier=new org.lwjgl.util.vector.Quaternion();
            params.animBonesRotateModifier.setFromAxisAngle(new org.lwjgl.util.vector.Vector4f(1,0,0,-(float)Math.PI/2));
        }
        var imported=ImportedSkeleton.process(ImportedSkeletonParams.create(params,params.scene.getMeshes().get(0)));
        var indices=(HashMap<String,Integer>)field(imported,"boneIndices");
        var parents=(ArrayList<Integer>)field(imported,"skeletonHierarchy");
        var clips=(HashMap<String,AnimationClip>)field(imported,"clips");
        if(indices.size()!=45 || clips.size()!=1) throw new IllegalArgumentException("expected native 45-bone skinned Bob clip: "+path);
        var offsets=new ArrayList<org.lwjgl.util.vector.Matrix4f>();
        for(int i=0;i<indices.size();i++) offsets.add(new org.lwjgl.util.vector.Matrix4f());
        return new CartShoppingPickupGenerate.Source(new SkinningData(new HashMap<>(),offsets,offsets,offsets,parents,indices),clips.values().iterator().next());
    }

    static AnimationTrack track(CartShoppingPickupGenerate.Source source) {
        var track=AnimationTrack.alloc();track.startClip(source.clip(),false,0);
        track.setUseDeferredMovement(false);
        return track;
    }

    static Matrix4f model(int index,SkinningData actor,Matrix4f[] local,Matrix4f[] models) {
        if(models[index]!=null) return models[index];
        var parent=actor.getBoneAt(index).parent;
        return models[index]=parent==null?new Matrix4f(local[index])
            :new Matrix4f(model(parent.index,actor,local,models)).mul(local[index]);
    }

    static Matrix4f[] sample(AnimationTrack track,SkinningData actor,float time) {
        track.setCurrentTimeValue(time);track.setPreviousTimeValue(time);track.UpdateKeyframes(0);
        var local=new Matrix4f[actor.numBones()];var models=new Matrix4f[local.length];
        var p=new org.lwjgl.util.vector.Vector3f();var q=new org.lwjgl.util.vector.Quaternion();
        var scale=new org.lwjgl.util.vector.Vector3f();var matrix=new org.lwjgl.util.vector.Matrix4f();
        for(int i=0;i<local.length;i++) {
            // Match AnimationPlayer's normal position/quaternion mixer. The imported
            // FBX Dummy01 scale metadata is not applied by that native blend path.
            track.get(i,p,q,scale);
            HelperFunctions.CreateFromQuaternion(q,matrix);HelperFunctions.setPosition(matrix,p);
            local[i]=PZMath.convertMatrix(matrix,new Matrix4f()).transpose();
        }
        for(int i=0;i<local.length;i++) model(i,actor,local,models);
        return models;
    }

    private static float error(Matrix4f a,Matrix4f b) {
        var x=a.get(new float[16]);var y=b.get(new float[16]);float error=0;
        for(int i=0;i<x.length;i++) error=Math.max(error,Math.abs(x[i]-y[i]));
        return error;
    }

    private static Matrix4f canonicalRoot(CartShoppingPickupGenerate.Source idle) {
        var root=idle.actor().getBone("Bip01");
        if(root==null || root.parent==null || !"Dummy01".equals(root.parent.name))
            throw new IllegalArgumentException("expected the native Dummy01/Bip01 root chain");
        return sample(track(idle),idle.actor(),0)[root.index];
    }

    private static void generate(Path sourcePath,Path idlePath,Path output) throws Exception {
        var skeleton=read(Path.of(System.getProperty("cart.nativeTemplate")),null).actor();
        var idle=read(idlePath,skeleton);var source=read(sourcePath,skeleton);var actor=source.actor();var clip=source.clip();
        var root=canonicalRoot(idle);
        var times=new TreeSet<Float>();times.add(0f);times.add(clip.getDuration());
        for(int i=0;i<actor.numBones();i++) for(var key:clip.getBoneFramesAt(i)) {
            if(!Float.isFinite(key.time) || key.time<0 || key.time>clip.getDuration())
                throw new IllegalArgumentException("native key time outside the clip");
            times.add(key.time);
        }
        // Direct Bip01 children need more keys after composing their animated parent. Every other
        // joint is pruned back to its original native grid by the Python carrier writer.
        var originalTimes=new ArrayList<Float>(times);
        int subdivisions=sourcePath.getFileName().toString().contains("SprintToStop")?16:8;
        for(int i=1;i<originalTimes.size();i++) for(int step=1;step<subdivisions;step++)
            times.add(originalTimes.get(i-1)+(originalTimes.get(i)-originalTimes.get(i-1))*step/subdivisions);
        var grids=new StringBuilder("{");
        for(int i=0;i<actor.numBones();i++) {
            if(i>0) grids.append(',');String name=actor.getBoneAt(i).name;
            grids.append('"').append(name).append("\":[");var grid=new TreeSet<Float>();
            if(actor.getBoneAt(i).parent!=null && actor.getBoneAt(i).parent.name.equals("Bip01")) grid.addAll(times);
            else if(name.equals("Bip01")) {grid.add(0f);grid.add(clip.getDuration());}
            else for(var key:clip.getBoneFramesAt(i)) grid.add(key.time);
            if(grid.isEmpty()) {grid.add(0f);grid.add(clip.getDuration());}
            boolean sep=false;for(float time:grid) {if(sep)grids.append(',');sep=true;grids.append(time);}
            grids.append(']');
        }
        Files.writeString(Path.of(output+".grid.json"),grids.append("}\n").toString());
        var track=track(source);var json=new StringBuilder("[");boolean comma=false;
        for(float time:times) {
            var poses=sample(track,actor,time);
            // Preserve every other model matrix, including the deferred-motion sibling.
            // The baker recomputes Pelvis local keys against this common parent frame.
            poses[actor.boneIndices.get("Bip01")].set(root);
            if(comma) json.append(',');comma=true;
            json.append("{\"time\":").append(time).append(",\"bones\":{");
            for(int i=0;i<poses.length;i++) {
                if(i>0) json.append(',');json.append('"').append(actor.getBoneAt(i).name).append("\":[");
                var values=poses[i].get(new float[16]);
                for(int j=0;j<values.length;j++) {if(j>0) json.append(',');json.append(values[j]);}
                json.append(']');
            }
            json.append("}}");
        }
        Files.writeString(output,json.append("]\n").toString());
    }

    private static void set(Object object,String name,Object value) throws Exception {
        var field=object.getClass().getDeclaredField(name);field.setAccessible(true);field.set(object,value);
    }

    private static CartShoppingPickupGenerate.Source reorder(CartShoppingPickupGenerate.Source source,SkinningData order) {
        if(!source.actor().boneIndices.keySet().equals(order.boneIndices.keySet()))
            throw new IllegalArgumentException("native cart and locomotion bone names differ");
        var keys=new ArrayList<Keyframe>();
        for(int i=0;i<order.numBones();i++) {
            String name=order.getBoneAt(i).name;int index=source.actor().boneIndices.get(name);
            for(var key:source.clip().getBoneFramesAt(index)) {
                var copy=new Keyframe(new org.lwjgl.util.vector.Vector3f(key.position),
                    new org.lwjgl.util.vector.Quaternion(key.rotation),new org.lwjgl.util.vector.Vector3f(key.scale));
                copy.bone=i;copy.boneName=name;copy.time=key.time;keys.add(copy);
            }
        }
        return new CartShoppingPickupGenerate.Source(order,new AnimationClip(source.clip().getDuration(),keys,source.clip().name,true));
    }

    /** Calls the installed engine's normal per-bone allocator and local-transform blend. */
    private static final class NativeMix {
        final AnimationPlayer player;
        final AnimationTrack idle,moving;
        final SkinningData actor;
        final Method update,models;
        NativeMix(CartShoppingPickupGenerate.Source reference,CartShoppingPickupGenerate.Source motion) throws Exception {
            actor=motion.actor();
            // FBX and .x importers enumerate the same Bob bones in different orders.
            reference=reorder(reference,actor);
            var constructor=AnimationPlayer.class.getDeclaredConstructor();constructor.setAccessible(true);
            player=constructor.newInstance();set(player,"skinningData",actor);
            player.boneTransforms=new AnimatorsBoneTransform[actor.numBones()];
            var palette=new org.lwjgl.util.vector.Matrix4f[actor.numBones()];
            for(int i=0;i<palette.length;i++) {
                player.boneTransforms[i]=AnimatorsBoneTransform.alloc();player.boneTransforms[i].setIdentity();
                palette[i]=new org.lwjgl.util.vector.Matrix4f();
            }
            set(player,"modelTransforms",palette);set(player,"boneTransformsNeedFirstFrame",false);
            idle=track(reference);moving=track(motion);idle.priority=10;moving.priority=11;
            player.getMultiTrack().getTracks().add(idle);player.getMultiTrack().getTracks().add(moving);
            update=AnimationPlayer.class.getDeclaredMethod("updateMultiTrackBoneTransformsInternal",float.class);
            models=AnimationPlayer.class.getDeclaredMethod("updateModelTransformsInternal");
            update.setAccessible(true);models.setAccessible(true);
        }
        Matrix4f[] pose(float time,float weight) throws Exception {
            return pose(0,time,1-weight,weight);
        }
        Matrix4f[] pose(float fromTime,float time,float fromWeight,float weight) throws Exception {
            idle.setBlendWeight(fromWeight);moving.setBlendWeight(weight);
            sample(idle,actor,fromTime);sample(moving,actor,time);
            return evaluate();
        }
        Matrix4f[] evaluate() throws Exception {
            update.invoke(player,0f);models.invoke(player);
            var poses=new Matrix4f[actor.numBones()];
            for(int i=0;i<poses.length;i++) poses[i]=PZMath.convertMatrix(player.getModelTransformAt(i),new Matrix4f()).transpose();
            return poses;
        }
    }

    private static Element xml(Path path) throws Exception {
        return DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(path.toFile()).getDocumentElement();
    }
    private static String value(Element element,String name,String fallback) {
        for(Node n=element.getFirstChild();n!=null;n=n.getNextSibling())
            if(n instanceof Element e && e.getTagName().equals(name)) return e.getTextContent();
        return fallback;
    }
    private static void mask(AnimationTrack track,Element element,SkinningData actor) {
        var weights=new ArrayList<AnimBoneWeight>();var nodes=element.getElementsByTagName("m_SubStateBoneWeights");
        for(int i=0;i<nodes.getLength();i++) {
            var e=(Element)nodes.item(i);var w=new AnimBoneWeight(value(e,"boneName",""),Float.parseFloat(value(e,"weight","0")));
            w.includeDescendants=Boolean.parseBoolean(value(e,"includeDescendants","true"));weights.add(w);
        }
        track.setBoneWeights(weights);track.initBoneWeights(actor);
    }
    private static LiveAnimNode bind(AnimLayer layer,AnimationTrack track,Element xml,boolean full) {
        var source=new AnimNode();source.name=value(xml,"m_Name","");source.blendTime=Float.parseFloat(value(xml,"m_BlendTime",".2"));source.isLooped=true;
        var node=LiveAnimNode.alloc(layer,source);node.addMainTrack(track);track.setAnimLayer(layer);
        node.setActive(full);node.update(0);if(full) node.setWeightsToFull();else node.setWeightsToZero();
        return node;
    }
    private static String mode(CartShoppingPickupGenerate.Source source) {
        String name=source.clip().name;
        if(name.endsWith("_Sprint") || name.endsWith("_StopSprint"))return "sprint";
        if(name.endsWith("_Run") || name.endsWith("_StopRun"))return "run";
        if(name.contains("Cart_Idle"))return "idle";
        return "walk";
    }
    private static boolean stop(CartShoppingPickupGenerate.Source source) {return source.clip().name.contains("_Stop");}
    private static Element rootXml(Path animsets,CartShoppingPickupGenerate.Source source) throws Exception {
        String mode=mode(source);
        return xml(animsets.resolve(mode.equals("idle")?"idle/toolkit_cart_idle.xml":
            mode.equals("walk")?"movement/toolkit_cart_wood_pivot_walk.xml":mode+"/toolkit_cart_pivot_"+mode+".xml"));
    }
    private static float stopFade(Path animsets,CartShoppingPickupGenerate.Source source,String field) throws Exception {
        String mode=mode(source);var node=xml(animsets.resolve(mode+"/toolkit_cart_pivot_"+mode+".xml"));
        var candidates=node.getElementsByTagName("m_Transitions");
        for(int i=0;i<candidates.getLength();i++) {
            var e=(Element)candidates.item(i);
            if(value(e,"m_AnimName","").equals(source.clip().name))return Float.parseFloat(value(e,field,"NaN"));
        }
        throw new IllegalArgumentException("heavy stop alias absent from staged cart XML: "+source.clip().name);
    }
    private static boolean graphEdge(CartShoppingPickupGenerate.Source from,CartShoppingPickupGenerate.Source to) {
        if(stop(from)) return mode(to).equals("idle");
        if(stop(to)) return !mode(from).equals("idle") && (mode(from).equals("walk") || mode(from).equals(mode(to)));
        return true;
    }
    private static float time(CartShoppingPickupGenerate.Source source,float phase,float elapsed) {
        float time=phase*source.clip().getDuration()+elapsed;
        return stop(source)?Math.min(time,source.clip().getDuration()):time%source.clip().getDuration();
    }

    /** Real XML LiveAnimNode schedules and native masked local blending; reports body motion, not collision. */
    private static String maskedGraph(List<CartShoppingPickupGenerate.Source> sources,Path idlePath,Path report) throws Exception {
        var actor=sources.get(0).actor();var animsets=Path.of(System.getProperty("cart.animSetRoot"));
        var uppers=new HashMap<String,CartShoppingPickupGenerate.Source>();
        for(String mode:List.of("idle","walk","run","sprint")) {
            String title=mode.substring(0,1).toUpperCase(Locale.ROOT)+mode.substring(1);
            uppers.put(mode,read(idlePath.resolveSibling("_Bob_Cart_"+title+".fbx"),actor));
        }
        int pelvis=actor.boneIndices.get("Bip01_Pelvis"),spine=actor.boneIndices.get("Bip01_Spine"),root=actor.boneIndices.get("Bip01");
        var canonical=canonicalRoot(uppers.get("idle"));int rows=0;float rootError=0,maxPelvisStep=0,maxSpineStep=0;
        String worst="";var transitions=new HashMap<String,CartShoppingPickupGenerate.Source>();
        try(var trace=Files.newBufferedWriter(Path.of(report+".jsonl"))) {
            for(var from:sources) for(var to:sources) if(from!=to) {
                if(!graphEdge(from,to))continue;
                String fm=mode(from),tm=mode(to);
                var oldRootXml=rootXml(animsets,from);var newRootXml=rootXml(animsets,to);
                var mix=new NativeMix(from,to);
                mix.idle.priority=Integer.parseInt(value(oldRootXml,"m_Priority","11"));
                mix.moving.priority=Integer.parseInt(value(newRootXml,"m_Priority","11"));
                var rootLayer=AnimLayer.alloc(null,null);
                for(float[] phase:new float[][]{{0,.25f},{.125f,.75f},{.5f,.99f},{.99f,0}}) {
                    mix.player.getMultiTrack().getTracks().clear();mix.player.getMultiTrack().getTracks().addAll(List.of(mix.idle,mix.moving));
                    var upperFrom=new ArrayList<AnimationTrack>();var upperTo=new ArrayList<AnimationTrack>();
                    var fromNodes=new ArrayList<LiveAnimNode>();var toNodes=new ArrayList<LiveAnimNode>();var transitionTracks=new ArrayList<AnimationTrack>();
                    var rootFrom=bind(rootLayer,mix.idle,oldRootXml,true);var rootTo=bind(rootLayer,mix.moving,newRootXml,false);
                    if(stop(to)) {
                        float fade=stopFade(animsets,to,"m_blendInTime");rootFrom.getSourceNode().blendTime=fade;rootTo.getSourceNode().blendTime=fade;
                    } else if(stop(from)) {
                        float fade=stopFade(animsets,from,"m_blendOutTime");rootFrom.getSourceNode().blendTime=fade;rootTo.getSourceNode().blendTime=fade;
                    }
                    rootFrom.setActive(false);rootTo.setActive(true);
                    for(String side:List.of("left","right")) {
                        var layer=AnimLayer.alloc(rootLayer,null,null);
                        var oldXml=xml(animsets.resolve("masking"+side+"/toolkit_cart_"+fm+"_"+side+".xml"));
                        var newXml=xml(animsets.resolve("masking"+side+"/toolkit_cart_"+tm+"_"+side+".xml"));
                        var a=track(uppers.get(fm));var b=track(uppers.get(tm));a.priority=b.priority=10;
                        mask(a,oldXml,actor);mask(b,newXml,actor);
                        var outgoing=bind(layer,a,oldXml,true);var incoming=bind(layer,b,newXml,false);
                        outgoing.setActive(false);incoming.setActive(true);AnimationTrack transitionTrack=null;
                        var candidates=oldXml.getElementsByTagName("m_Transitions");
                        for(int i=0;i<candidates.getLength();i++) {
                            var e=(Element)candidates.item(i);if(!value(e,"m_Target","").equals(incoming.getName()))continue;
                            var change=new AnimTransition();change.target=incoming.getName();change.animName=value(e,"m_AnimName","");
                            change.blendInTime=Float.parseFloat(value(e,"m_blendInTime","Infinity"));change.blendOutTime=Float.parseFloat(value(e,"m_blendOutTime","Infinity"));
                            change.speedScale=Float.parseFloat(value(e,"m_speedScale","1"));outgoing.setTransitionOut(change);
                            if(!change.animName.isEmpty()) {
                                if(!transitions.containsKey(change.animName))transitions.put(change.animName,read(idlePath.resolveSibling("_"+change.animName+".fbx"),actor));
                                transitionTrack=track(transitions.get(change.animName));transitionTrack.priority=10;transitionTrack.setAnimLayer(layer);
                                transitionTrack.setSpeedDelta(change.speedScale);mask(transitionTrack,oldXml,actor);
                                mix.player.getMultiTrack().getTracks().add(transitionTrack);
                            }
                            incoming.startTransitionIn(outgoing,change,transitionTrack);break;
                        }
                        mix.player.getMultiTrack().getTracks().addAll(List.of(a,b));upperFrom.add(a);upperTo.add(b);
                        fromNodes.add(outgoing);toNodes.add(incoming);transitionTracks.add(transitionTrack);
                    }
                    Matrix4f[] previous=null;
                    for(int ms=0;ms<=350;ms++) {
                        float elapsed=ms/1000f,dt=ms==0?0:.001f;
                        rootFrom.update(dt);rootTo.update(dt);
                        mix.idle.setBlendWeight(rootFrom.getWeight());mix.moving.setBlendWeight(rootTo.getWeight());
                        float fromPhase=stop(from)?1:phase[0],toPhase=stop(to)?0:phase[1];
                        sample(mix.idle,actor,time(from,fromPhase,elapsed));sample(mix.moving,actor,time(to,toPhase,elapsed));
                        for(int i=0;i<2;i++) {
                            var a=upperFrom.get(i);var b=upperTo.get(i);var an=fromNodes.get(i);var bn=toNodes.get(i);
                            var tr=transitionTracks.get(i);if(tr!=null) {tr.setCurrentTimeValue(Math.min(tr.getDuration(),elapsed*tr.getSpeedDelta()));tr.setPreviousTimeValue(tr.getCurrentTimeValue());tr.UpdateKeyframes(0);}
                            an.update(dt);bn.update(dt);a.setBlendWeight(an.getWeight());b.setBlendWeight(bn.getWeight());
                            sample(a,actor,time(uppers.get(fm),phase[0],elapsed));sample(b,actor,time(uppers.get(tm),phase[1],elapsed));
                            if(tr!=null)tr.setBlendWeight(bn.getTransitionInWeight());
                        }
                        var pose=mix.evaluate();rootError=Math.max(rootError,error(canonical,pose[root]));
                        float ps=0,ss=0;if(previous!=null) {
                            ps=pose[pelvis].getTranslation(new org.joml.Vector3f()).distance(previous[pelvis].getTranslation(new org.joml.Vector3f()));
                            ss=pose[spine].getTranslation(new org.joml.Vector3f()).distance(previous[spine].getTranslation(new org.joml.Vector3f()));
                            maxPelvisStep=Math.max(maxPelvisStep,ps);if(ss>maxSpineStep) {maxSpineStep=ss;worst=from.clip().name+"->"+to.clip().name+"@"+ms;}
                        }
                        trace.write(String.format(Locale.ROOT,"{\"from\":\"%s\",\"to\":\"%s\",\"fromPhase\":%.9g,\"toPhase\":%.9g,\"ms\":%d,\"rootFromWeight\":%.9g,\"rootToWeight\":%.9g,\"spineX\":%.9g,\"spineY\":%.9g,\"spineZ\":%.9g,\"pelvisStep\":%.9g,\"spineStep\":%.9g}%n",from.clip().name,to.clip().name,fromPhase,toPhase,ms,rootFrom.getWeight(),rootTo.getWeight(),pose[spine].m30(),pose[spine].m31(),pose[spine].m32(),ps,ss));
                        previous=pose;rows++;
                    }
                }
            }
        }
        // A 5 mm model-space/1 ms ceiling catches the demonstrated 27 mm allocator
        // handoff pulse. This is a controlled phase regression, not a collision bound.
        if(rootError>TOLERANCE || maxPelvisStep>.005f || maxSpineStep>.005f)
            throw new AssertionError("masked XML handoff regression: root="+rootError+" pelvisStep="+maxPelvisStep+" spineStep="+maxSpineStep+" at "+worst);
        return String.format(Locale.ROOT,"{\"rows\":%d,\"phasePairsPerTransition\":4,\"bodyStepLimit1ms\":0.005,\"maxRootOrbit\":%.9g,\"maxPelvisModelStep1ms\":%.9g,\"maxSpineModelStep1ms\":%.9g,\"worstSpineStep\":\"%s\",\"collisionVerified\":false}",rows,rootError,maxPelvisStep,maxSpineStep,worst);
    }

    /** Full lower-body set, both transition directions and native near-zero allocation edges. */
    private static void graph(Path idlePath,Path manifest,Path report) throws Exception {
        var skeleton=read(Path.of(System.getProperty("cart.nativeTemplate")),null).actor();
        var canonical=canonicalRoot(read(idlePath,skeleton));
        var sources=new ArrayList<CartShoppingPickupGenerate.Source>();
        for(String line:Files.readAllLines(manifest)) sources.add(read(Path.of(line),skeleton));
        sources.add(read(idlePath,skeleton)); // Actual held-cart idle is a graph endpoint too.
        float maxRootOrbit=0,maxPelvisChordError=0;
        int samples=0,pairs=0;int root=skeleton.boneIndices.get("Bip01"),pelvis=skeleton.boneIndices.get("Bip01_Pelvis"),spine=skeleton.boneIndices.get("Bip01_Spine");
        for(var from:sources) for(var to:sources) if(from!=to) {
            pairs++;var mix=new NativeMix(from,to);
            for(float phase:new float[]{0,.125f,.5f,.99f}) for(float targetPhase:new float[]{0,.25f,.75f,.99f}) {
                float aTime=phase*from.clip().getDuration(),bTime=targetPhase*to.clip().getDuration();
                var a=sample(track(from),skeleton,aTime)[pelvis].getTranslation(new org.joml.Vector3f());
                var b=sample(track(to),skeleton,bTime)[pelvis].getTranslation(new org.joml.Vector3f());
                for(int step=0;step<=100;step++) {
                    float weight=step/100f;var pose=mix.pose(aTime,bTime,1-weight,weight);samples++;
                    maxRootOrbit=Math.max(maxRootOrbit,error(canonical,pose[root]));
                    var expected=new org.joml.Vector3f(a).lerp(b,weight);
                    maxPelvisChordError=Math.max(maxPelvisChordError,pose[pelvis].getTranslation(new org.joml.Vector3f()).distance(expected));
                }
            }
        }
        if(maxRootOrbit>TOLERANCE || maxPelvisChordError>TOLERANCE)
            throw new AssertionError("canonical native root/local blend orbit: root="+maxRootOrbit+" pelvisChord="+maxPelvisChordError);
        String masked=maskedGraph(sources,idlePath,report);
        Files.writeString(report,String.format(Locale.ROOT,"{\"status\":\"pass\",\"clips\":%d,\"directedPairs\":%d,\"samples\":%d,\"maxRootOrbit\":%.9g,\"maxPelvisChordError\":%.9g,\"masked\":%s,\"nativeDrawVerified\":false}\n",
            sources.size(),pairs,samples,maxRootOrbit,maxPelvisChordError,masked));
    }

    private static float deferredTimeline(CartShoppingPickupGenerate.Source original,
        CartShoppingPickupGenerate.Source generated) {
        float maximum=0;double travel=0;
        for(int fps:new int[]{30,60,144}) for(float pace:new float[]{.6f,1,2.2f}) {
            var before=track(original);var after=track(generated);
            before.looping=after.looping=true;before.setSpeedDelta(pace);after.setSpeedDelta(pace);
            before.setDeferredBone(original.actor().getBone("Translation_Data"),BoneAxis.Y);
            after.setDeferredBone(generated.actor().getBone("Translation_Data"),BoneAxis.Y);
            before.setUseDeferredMovement(true);after.setUseDeferredMovement(true);
            var a=new Vector2();var b=new Vector2();
            for(int frame=0;frame<fps*3;frame++) {
                before.Update(1f/fps);after.Update(1f/fps);
                before.getDeferredMovementDiff(a);after.getDeferredMovementDiff(b);
                maximum=Math.max(maximum,(float)Math.hypot(a.x-b.x,a.y-b.y));
                travel+=Math.hypot(a.x,a.y);
            }
        }
        if(maximum>TOLERANCE)
            throw new AssertionError("native looping deferred timeline changed: error="+maximum+" travel="+travel);
        return maximum;
    }

    private static void replay(Path originalPath,Path idlePath,Path generatedPath,Path reportPath) throws Exception {
        var skeleton=read(Path.of(System.getProperty("cart.nativeTemplate")),null).actor();
        var idle=read(idlePath,skeleton);
        var original=read(originalPath,idle.actor());
        var generated=read(generatedPath,idle.actor());
        var actor=original.actor();
        if(!actor.boneIndices.equals(generated.actor().boneIndices))
            throw new AssertionError("generated root representation changed bone order");
        int root=actor.boneIndices.get("Bip01");var canonical=canonicalRoot(idle);
        var sourceTrack=track(original);var targetTrack=track(generated);
        float duration=original.clip().getDuration(),durationError=Math.abs(duration-generated.clip().getDuration());
        if(durationError>1e-6f) throw new AssertionError("native clip duration changed");
        float maxModelError=0,maxRootError=0,maxScaleError=0,minRootQuatDot=1,maxTranslationError=0,sourceRootMismatch=0;
        var previous=new org.lwjgl.util.vector.Quaternion();boolean havePrevious=false;
        int samples=1441,missingNubs=0;String worst="";
        for(int i=0;i<actor.numBones();i++) if(original.clip().getBoneFramesAt(i).length==0) {
            if(!actor.getBoneAt(i).name.endsWith("Nub") || actor.getBoneAt(i).children.length!=0)
                throw new AssertionError("native skinnedTo is missing a non-leaf Nub");
            missingNubs++;
            for(float t:new float[]{0,duration/2,duration}) {
                sample(sourceTrack,actor,t);var p=new org.lwjgl.util.vector.Vector3f();var q=new org.lwjgl.util.vector.Quaternion();var s=new org.lwjgl.util.vector.Vector3f();
                sourceTrack.get(i,p,q,s);
                if(p.lengthSquared()!=0 || q.x!=0 || q.y!=0 || q.z!=0 || q.w!=1 || s.x!=1 || s.y!=1 || s.z!=1)
                    throw new AssertionError("native absent Nub fallback is not local identity");
            }
        }
        for(int frame=0;frame<samples;frame++) {
            float time=duration*frame/(samples-1);
            var from=sample(sourceTrack,actor,time);var to=sample(targetTrack,generated.actor(),time);
            for(int i=0;i<from.length;i++) if(i!=root) {
                float e=error(from[i],to[i]);if(e>maxModelError) {maxModelError=e;worst=actor.getBoneAt(i).name+"@"+time+" from="+from[i]+" to="+to[i];}
                maxTranslationError=Math.max(maxTranslationError,(float)Math.sqrt(
                    Math.pow(from[i].m30()-to[i].m30(),2)+Math.pow(from[i].m31()-to[i].m31(),2)
                        +Math.pow(from[i].m32()-to[i].m32(),2)));
            }
            maxRootError=Math.max(maxRootError,error(canonical,to[root]));
            sourceRootMismatch=Math.max(sourceRootMismatch,error(canonical,from[root]));
            var p=new org.lwjgl.util.vector.Vector3f();var q=new org.lwjgl.util.vector.Quaternion();
            var scale=new org.lwjgl.util.vector.Vector3f();targetTrack.get(root,p,q,scale);
            maxScaleError=Math.max(maxScaleError,Math.max(Math.abs(scale.x-1),Math.max(Math.abs(scale.y-1),Math.abs(scale.z-1))));
            if(havePrevious) minRootQuatDot=Math.min(minRootQuatDot,org.lwjgl.util.vector.Quaternion.dot(previous,q));
            previous.set(q);havePrevious=true;
        }
        if(maxModelError>TOLERANCE || maxTranslationError>TOLERANCE || maxRootError>TOLERANCE || maxScaleError>1e-5 || minRootQuatDot<.99999f)
            throw new AssertionError("native pose/root continuity changed: model="+maxModelError+" root="+maxRootError
                +" translation="+maxTranslationError+" scale="+maxScaleError+" quaternionDot="+minRootQuatDot+" worst="+worst);
        var source0=sample(sourceTrack,actor,0);var source1=sample(sourceTrack,actor,duration);
        var target0=sample(targetTrack,actor,0);var target1=sample(targetTrack,actor,generated.clip().getDuration());
        var q0=new org.lwjgl.util.vector.Quaternion();var q1=new org.lwjgl.util.vector.Quaternion();
        sample(targetTrack,actor,0);targetTrack.get(root,new org.lwjgl.util.vector.Vector3f(),q0,new org.lwjgl.util.vector.Vector3f());
        sample(targetTrack,actor,generated.clip().getDuration());targetTrack.get(root,new org.lwjgl.util.vector.Vector3f(),q1,new org.lwjgl.util.vector.Vector3f());
        float rootLoopQuaternionDot=org.lwjgl.util.vector.Quaternion.dot(q0,q1);
        if(rootLoopQuaternionDot<.99999f)throw new AssertionError("canonical root quaternion loop hemisphere changed");
        float loopSeamError=0,endpointError=0;
        for(int i=0;i<actor.numBones();i++) if(i!=root) {
            endpointError=Math.max(endpointError,Math.max(error(source0[i],target0[i]),error(source1[i],target1[i])));
            loopSeamError=Math.max(loopSeamError,Math.abs(error(source0[i],source1[i])-error(target0[i],target1[i])));
        }
        if(endpointError>TOLERANCE || loopSeamError>TOLERANCE) throw new AssertionError("native loop endpoints/seam changed");
        var before=original.clip().getTotalTranslation("Translation_Data",BoneAxis.Y,new Vector2());
        var after=generated.clip().getTotalTranslation("Translation_Data",BoneAxis.Y,new Vector2());
        float deferredError=(float)Math.hypot(before.x-after.x,before.y-after.y);
        float speedError=Math.abs(before.getLength()/duration-after.getLength()/generated.clip().getDuration());
        if(deferredError>TOLERANCE || speedError>TOLERANCE) throw new AssertionError("native deferred movement changed");
        float deferredTimelineError=deferredTimeline(original,generated);
        var oldMix=new NativeMix(idle,original);var newMix=new NativeMix(idle,generated);
        float oldBulge=0,newBulge=0,mixEndpointError=0;int spine=actor.boneIndices.get("Bip01_Spine");
        // The startup phase straddles Bob_Run's loop boundary. Test the reported phase and both sides.
        for(float phase:new float[]{0,.01f,.05f,.3f,.6f,.99f,1}) for(int step=0;step<=100;step++) {
            float time=duration*phase;
            float weight=step/100f;var old=oldMix.pose(time,weight);var fixed=newMix.pose(time,weight);
            oldBulge=Math.max(oldBulge,Math.abs(old[spine].m30()));newBulge=Math.max(newBulge,Math.abs(fixed[spine].m30()));
            if(step==0 || step==100) for(int i=0;i<old.length;i++) if(i!=root)
                mixEndpointError=Math.max(mixEndpointError,error(old[i],fixed[i]));
        }
        if(mixEndpointError>TOLERANCE)
            throw new AssertionError("native cart-idle blending changed endpoints: "+mixEndpointError);
        var report=String.format(Locale.ROOT,
            "{\"status\":\"pass\",\"samples\":%d,\"unchangedModelBones\":44,\"changedUnskinnedFrame\":\"Bip01\","
            +"\"maxModelMatrixError\":%.9g,\"maxRootMatrixError\":%.9g,\"durationError\":%.9g,"
            +"\"maxModelTranslationError\":%.9g,"
            +"\"sourceRootMismatch\":%.9g,"
            +"\"nativeSkinnedToBones\":45,\"nativeAbsentLeafNubs\":%d,"
            +"\"maxRootScaleError\":%.9g,\"minimumRootQuaternionDot\":%.9g,\"endpointMatrixError\":%.9g,"
            +"\"rootLoopQuaternionDot\":%.9g,"
            +"\"loopSeamMatrixError\":%.9g,\"deferredTranslationError\":%.9g,\"deferredSpeedError\":%.9g,"
            +"\"nativeDeferredTimelineError\":%.9g,"
            +"\"nativeBlendOriginalLateralBulge\":%.9g,\"nativeBlendCanonicalLateralBulge\":%.9g,"
            +"\"nativeBlendEndpointError\":%.9g,\"nativeDrawVerified\":false}\n",
            samples,maxModelError,maxRootError,durationError,maxTranslationError,sourceRootMismatch,missingNubs,maxScaleError,minRootQuatDot,endpointError,rootLoopQuaternionDot,loopSeamError,
            deferredError,speedError,deferredTimelineError,oldBulge,newBulge,mixEndpointError);
        Files.writeString(reportPath,report);System.out.print(report);
    }

    public static void main(String[] args) throws Exception {
        if(args.length==4 && args[0].equals("generate"))
            generate(Path.of(args[1]),Path.of(args[2]),Path.of(args[3]));
        else if(args.length==5 && args[0].equals("replay"))
            replay(Path.of(args[1]),Path.of(args[2]),Path.of(args[3]),Path.of(args[4]));
        else if(args.length==5 && args[0].equals("graph")) {
            System.setProperty("cart.animSetRoot",args[4]);graph(Path.of(args[1]),Path.of(args[2]),Path.of(args[3]));
        }
        else throw new IllegalArgumentException("generate Bob_Run.x cart_idle.fbx output.json | replay Bob_Run.x cart_idle.fbx generated.x report.json");
    }
}
