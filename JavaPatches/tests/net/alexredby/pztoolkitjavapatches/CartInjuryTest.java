package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Method;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import javax.xml.parsers.DocumentBuilderFactory;
import org.w3c.dom.Element;
import org.lwjgl.util.vector.Vector3f;
import sun.misc.Unsafe;
import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.ModelManager;
import zombie.core.skinnedmodel.advancedanimation.*;
import zombie.core.skinnedmodel.animation.*;
import zombie.core.skinnedmodel.model.ModelMesh;
import zombie.core.skinnedmodel.model.SkinningData;
import zombie.inventory.InventoryItem;
import zombie.iso.Vector2;

/** Uses the installed native blend topology and the actual woven blend-field boundary. */
public final class CartInjuryTest {
    private static Unsafe unsafe;
    private static Method applyField;
    private static final Map<String, AnimNode> nativeNodes = new HashMap<>();
    private static final Map<String, AnimNode> cartNodes = new HashMap<>();
    private static final HashMap<String, AnimationClip> clips = new HashMap<>();

    private static final class Player extends IsoPlayer {
        AdvancedAnimator animator;
        InventoryItem cart;
        boolean run, sprint, enabled, remote;
        float injury, speed, pace;
        Player() { super(null, null, 0, 0, 0); }
        @Override public AdvancedAnimator getAdvancedAnimator() { return animator; }
        @Override public InventoryItem getPrimaryHandItem() { return cart; }
        @Override public boolean isRunning() { return run; }
        @Override public boolean isSprinting() { return sprint; }
        @Override public boolean isLocalPlayer() { return !remote; }
        @Override public boolean getVariableBoolean(String name) { return enabled && name.equals("ToolkitCartMotion"); }
        @Override public float getVariableFloat(String name, float fallback) {
            return switch (name) { case "WalkInjury" -> injury; case "WalkSpeed" -> speed; default -> fallback; };
        }
        @Override public IAnimationVariableSlot setVariable(String name, float value) {
            if (name.equals("ToolkitCartLegPace")) pace = value;
            return null;
        }
    }

    private static final class Cart extends InventoryItem {
        String type;
        Cart() { super(null, null, null, (String) null); }
        @Override public String getFullType() { return type; }
    }

    private record Fixture(Player player, AnimLayer layer, LiveAnimNode live, AnimNode source) {}

    private static <T> T allocate(Class<T> type) throws Exception { return type.cast(unsafe.allocateInstance(type)); }
    private static void check(boolean value, String message) { if (!value) throw new AssertionError(message); }
    private static void close(double actual, double expected, String message) {
        check(Double.isFinite(actual) && Math.abs(actual - expected) < .00003,
            message + ": " + actual + " != " + expected);
    }
    private static String text(Element element, String name) {
        return element.getElementsByTagName(name).item(0).getTextContent().trim();
    }

    private static AnimNode read(Path path) throws Exception {
        var factory = DocumentBuilderFactory.newInstance();
        factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
        var root = factory.newDocumentBuilder().parse(path.toFile()).getDocumentElement();
        var node = new AnimNode(); node.name = text(root, "m_Name");
        node.deferredBoneName = "Translation_Data"; node.deferredBoneAxis = BoneAxis.Y;
        var references = new HashMap<String, Anim2DBlend>();
        var fields = root.getElementsByTagName("m_2DBlends");
        for (int i = 0; i < fields.getLength(); i++) {
            var element = (Element) fields.item(i); var blend = new Anim2DBlend();
            blend.animName = text(element, "m_AnimName");
            blend.posX = Float.parseFloat(text(element, "m_XPos"));
            blend.posY = Float.parseFloat(text(element, "m_YPos"));
            blend.speedScale = Float.parseFloat(text(element, "m_SpeedScale"));
            node.blends2d.add(blend); references.put(element.getAttribute("referenceID"), blend);
            clips.computeIfAbsent(blend.animName, CartInjuryTest::clip);
        }
        var triangles = root.getElementsByTagName("m_2DBlendTri");
        for (int i = 0; i < triangles.getLength(); i++) {
            var element = (Element) triangles.item(i); var triangle = new Anim2DBlendTriangle();
            triangle.node1 = references.get(text(element, "node1"));
            triangle.node2 = references.get(text(element, "node2"));
            triangle.node3 = references.get(text(element, "node3"));
            check(triangle.node1 != null && triangle.node2 != null && triangle.node3 != null, "broken XML reference " + path);
            node.blendTris.add(triangle);
        }
        node.blend2dPicker = new Anim2DBlendPicker(); node.blend2dPicker.SetPickTriangles(node.blendTris);
        return node;
    }

    private static AnimationClip clip(String name) {
        float x = 0, y = 1;
        if (name.contains("Idle")) y = 0;
        else if (name.contains("Bwd")) y = -.7f;
        else if (name.contains("Right")) { x = .7f; y = 0; }
        else if (name.contains("Left")) { x = -.7f; y = 0; }
        else if (name.contains("HeavyLimp")) { x = name.endsWith("R") ? .015f : -.015f; y = name.endsWith("R") ? .35f : .38f; }
        else if (name.contains("RunLightLimp")) { x = name.endsWith("R") ? .01f : -.01f; y = name.endsWith("R") ? 1.4f : 1.45f; }
        else if (name.contains("LightLimp")) { x = name.endsWith("R") ? .01f : -.01f; y = name.endsWith("R") ? .7f : .73f; }
        else if (name.contains("Sprint")) y = 2.4f;
        else if (name.contains("Run")) y = 1.7f;
        else if (name.contains("Slow")) y = .25f;
        var start = new Keyframe(); var end = new Keyframe();
        start.boneName = end.boneName = "Translation_Data";
        start.position = new Vector3f(); end.position = new Vector3f(x, 0, -y); end.time = 1;
        return new AnimationClip(1, List.of(start, end), name, true);
    }

    private static Fixture fixture(String type, String gait, float injury, boolean remote) throws Exception {
        var player = allocate(Player.class); player.enabled = true; player.remote = remote;
        player.injury = injury; player.speed = gait.equals("Walk") ? .62f : gait.equals("Run") ? .55f : .78f;
        player.run = gait.equals("Run"); player.sprint = gait.equals("Sprint");
        var item = allocate(Cart.class); item.type = type; player.cart = item;
        player.animator = new AdvancedAnimator(); player.animator.animSet = new AnimationSet();
        for (String name : List.of("movement", "run", "sprint")) {
            var state = new AnimState(); state.name = name; state.nodes.add(nativeNodes.get(name));
            for (var node : cartNodes.values()) {
                if (name.equals("movement") && node.name.endsWith("Walk") || name.equals("run") && node.name.endsWith("Run")
                    || name.equals("sprint") && node.name.endsWith("Sprint")) state.nodes.add(node);
            }
            player.animator.animSet.states.put(name, state);
        }
        var source = CartLegPace.pivotNode(player);
        check(source != null, "cart gait selector found no node");
        var layer = AnimLayer.alloc(player, player.animator);
        var root = AdvancedAnimator.class.getDeclaredField("rootLayer"); root.setAccessible(true); root.set(player.animator, layer);
        var live = LiveAnimNode.alloc(layer, source); live.setActive(true); layer.getLiveAnimNodes().add(live);
        for (var blend : source.blends2d) {
            var track = AnimationTrack.alloc(); track.startClip(clips.get(blend.animName), true, 0);
            track.advance(.27f); live.addMainTrack(track);
        }
        return new Fixture(player, layer, live, source);
    }

    private static Map<String, Float> picked(AnimNode node, float x, float y) {
        var picked = node.blend2dPicker.Pick(x, y, new Anim2DBlendPicker.PickResults());
        var result = new HashMap<String, Float>();
        for (int i = 0; i < picked.numNodes; i++) {
            var entry = i == 0 ? picked.node1 : i == 1 ? picked.node2 : picked.node3;
            float weight = i == 0 ? picked.scale1 : i == 1 ? picked.scale2 : picked.scale3;
            if (weight >= .0001f) result.merge(entry.animName, Math.min(1, weight), Float::sum);
        }
        return result;
    }

    private static Map<String, Float> expected(Fixture f, float x, float y) {
        var result = picked(f.source, x, y);
        float alpha = CartInjury.amount(f.player.injury);
        String forward = f.player.sprint ? "Bob_Sprint" : f.player.run ? "Bob_Run" : "Bob_Walk";
        float mass = result.getOrDefault(forward, 0f) * alpha;
        result.merge(forward, -mass, Float::sum);
        String state = f.player.sprint ? "sprint" : f.player.run ? "run" : "movement";
        for (var entry : picked(nativeNodes.get(state), f.player.injury, f.player.speed).entrySet())
            result.merge(entry.getKey(), mass * entry.getValue(), Float::sum);
        return result;
    }

    private static void apply(Fixture f, float x, float y) throws Exception { applyField.invoke(f.layer, f.live, .4f, x, y); }
    private static Map<String, Float> weights(Fixture f) {
        var result = new HashMap<String, Float>();
        for (var track : f.live.getMainAnimationTracks()) result.merge(track.getName(), track.getBlendFieldWeight(), Float::sum);
        return result;
    }
    private static float speed(Fixture f, boolean cadence) {
        double x = 0, y = 0;
        for (var track : f.live.getMainAnimationTracks()) {
            var root = track.getClip().getTotalTranslation("Translation_Data", BoneAxis.Y, new Vector2());
            float weight = track.getBlendFieldWeight() / track.getClip().getDuration();
            if (cadence) weight *= track.getSpeedDelta();
            x += weight * root.x; y += weight * root.y;
        }
        return (float) Math.hypot(x, y);
    }

    private static float rootSpeed(Map<String, Float> weights) {
        double x = 0, y = 0;
        for (var entry : weights.entrySet()) {
            var clip = clips.get(entry.getKey());
            var root = clip.getTotalTranslation("Translation_Data", BoneAxis.Y, new Vector2());
            x += entry.getValue() * root.x / clip.getDuration();
            y += entry.getValue() * root.y / clip.getDuration();
        }
        return (float) Math.hypot(x, y);
    }

    private static float expectedTarget(Fixture f, float y) {
        boolean fast = f.player.run || f.player.sprint;
        float base = f.player.sprint ? .96f : 1.04f;
        String reference = !fast && y < 0 && !f.player.cart.getFullType().equals("SaucedCarts.ShoppingCart")
            ? "Bob_WalkBwdNoAim1Hand" : "Bob_Walk";
        float healthy = fast ? 0 : f.player.speed * rootSpeed(Map.of(reference, 1f));
        if (fast) {
            float blend = f.player.sprint ? Math.max(0, (f.player.speed - .5f) * 2) : f.player.speed;
            healthy = (1 - blend) * rootSpeed(Map.of(f.player.sprint ? "Bob_Run" : "Bob_Walk", 1f))
                + blend * rootSpeed(Map.of(f.player.sprint ? "Bob_Sprint" : "Bob_Run", 1f));
        }
        String state = f.player.sprint ? "sprint" : f.player.run ? "run" : "movement";
        float nativeRoot = rootSpeed(picked(nativeNodes.get(state), f.player.injury, f.player.speed));
        if (!fast && y < 0) nativeRoot = Math.min(nativeRoot, f.player.speed * rootSpeed(Map.of(reference, 1f)));
        float alpha = CartInjury.amount(f.player.injury);
        return base * ((1 - alpha) * healthy + alpha * nativeRoot);
    }

    private static void directions() throws Exception {
        for (String type : List.of("SaucedCarts.ShoppingCart", "SaucedWheelbarrow.WheelbarrowWood", "SaucedWheelbarrow.WheelbarrowMetal"))
            for (String gait : List.of("Walk", "Run", "Sprint")) for (float injury : new float[]{-.9f, -.5f, -.075f, -.00001f, 0, .00001f, .075f, .15f, .5f, .9f}) {
                var f = fixture(type, gait, injury, false);
                check(f.source.name.equals(CartLegPace.pivotName(type, f.player.run, f.player.sprint)), "wrong cart/gait selector");
                for (int degree = -180; degree <= 180; degree += 30) {
                    float radius = gait.equals("Walk") ? CartInjury.walkMagnitude(f.player, f.player.speed) : 1;
                    float x = radius * (float) Math.sin(Math.toRadians(degree)), y = radius * (float) Math.cos(Math.toRadians(degree));
                    var expected = expected(f, x, y); apply(f, x, y);
                    double sum = 0;
                    for (var track : f.live.getMainAnimationTracks()) {
                        close(track.getBlendFieldWeight(), expected.getOrDefault(track.getName(), 0f), "woven injury field " + gait + "/" + injury + "/" + degree + "/" + track.getName());
                        close(track.getBlendWeight(), .4f * track.getBlendFieldWeight(), "injury changed native node fade");
                        close(track.getCurrentTimeValue(), .27, "injury replacement sought the foot phase");
                        sum += track.getBlendFieldWeight();
                    }
                    close(sum, 1, "injury blend lost directional mass");
                    close(CartLegPace.blendedSpeed(f.source, x, y, clips::get, CartInjury.blend(f.player, f.source)), speed(f, false), "prediction differs from actual blended root");
                    float target = CartLegPace.targetSpeed(f.player, x, y);
                    close(target, expectedTarget(f, y), "cart target lost native injury/gait speed " + type + "/" + gait + "/" + injury + "/" + degree);
                    CartLegPace.applySpeed(f.player, target, x, y);
                    close(speed(f, true), Math.min(target, 2.5f * speed(f, false)),
                        "native extracted root differs from requested budget/cadence cap " + gait + "/" + injury + "/" + degree);
                }
            }
    }

    private static void lifecycle() throws Exception {
        var owner = fixture("SaucedWheelbarrow.WheelbarrowWood", "Walk", -.7f, false);
        var observer = fixture("SaucedWheelbarrow.WheelbarrowWood", "Walk", -.7f, true);
        apply(owner, .25f, .75f); apply(observer, .25f, .75f);
        check(weights(owner).equals(weights(observer)), "owner/observer injury fields differ");
        var retained = weights(owner); owner.live.setActive(false); owner.player.injury = .8f;
        apply(owner, -.8f, -.2f); check(weights(owner).equals(retained), "outgoing node changed its retained injury/direction");
        CartLegPace.applySpeedTracks(List.of(owner.live), .2f, null, 0, 1);
        close(speed(owner, true), .2, "outgoing injured node lost root-speed compensation");
        owner.live.setActive(true); owner.player.injury = 0; apply(owner, .25f, .75f);
        for (var track : owner.live.getMainAnimationTracks())
            close(track.getBlendFieldWeight(), picked(owner.source, .25f, .75f).getOrDefault(track.getName(), 0f), "healing failed to restore exact healthy field");
        owner.player.injury = -.7f; owner.player.enabled = false; apply(owner, .25f, .75f);
        for (var track : owner.live.getMainAnimationTracks())
            close(track.getBlendFieldWeight(), picked(owner.source, .25f, .75f).getOrDefault(track.getName(), 0f), "disabled actor received injured pose");
        var other = read(Path.of("media/AnimSets/player/movement/defaultWalk.xml"));
        check(CartInjury.blend(observer.player, other) == null, "injury hook claimed native non-cart node");
    }

    private static void readiness() throws Exception {
        var f = fixture("SaucedCarts.ShoppingCart", "Walk", -.7f, false);
        var blend = CartInjury.blend(f.player, f.source); check(blend != null, "fixture lacks injury blend");
        check(CartInjury.supported(f.player), "ready injured actor failed capability gate");
        String selected = blend.first().animName;
        var removed = clips.remove(selected);
        try {
            check(CartInjury.blend(f.player, f.source) == null, "missing asset still enabled injury blend");
            check(!CartInjury.supported(f.player), "missing asset did not restore native injury fallback");
            close(CartInjury.walkMagnitude(f.player, .62f), .62, "missing asset expanded healthy stride");
            apply(f, 0, .62f);
            close(weights(f).get("Bob_Walk"), .62, "missing asset consumed forward mass");
        } finally { clips.put(selected, removed); }
        for (var track : f.live.getMainAnimationTracks()) if (selected.equals(track.getName())) {
            var original = track.currentClip; track.currentClip = null;
            try { apply(f, 0, .62f); close(weights(f).get("Bob_Walk"), .62, "missing live track consumed forward mass"); }
            finally { track.currentClip = original; }
            break;
        }
        var missing = f.source.blends2d.stream().filter(entry -> entry.animName.equals(selected)).findFirst().orElseThrow();
        int index = f.source.blends2d.indexOf(missing); f.source.blends2d.remove(index);
        try { check(CartInjury.blend(f.player, f.source) == null, "incomplete cart XML still enabled injury blend"); }
        finally { f.source.blends2d.add(index, missing); }
    }

    private static void heavyPoseWeights() throws Exception {
        var f = fixture("SaucedWheelbarrow.WheelbarrowWood", "Walk", 1, false);
        close(CartInjury.poseWeight(f.player), 1, "current injury lost its non-limp Sprint pose guard");
        f.player.injury = 0;
        close(CartInjury.poseWeight(f.player), 0, "dormant clips acquired torso correction after healing");
        for (var track : f.live.getMainAnimationTracks()) {
            track.setBlendFieldWeight(track.getName().equals("Bob_WalkHeavyLimpR") ? .75f : 0);
            track.setBlendWeight(.4f);
        }
        close(CartInjury.poseWeight(f.player), .3, "heavy correction ignored effective node/field weights");
        f.live.setActive(false);
        close(CartInjury.poseWeight(f.player), .3, "outgoing heavy pose lost torso correction during fade");
        for (var track : f.live.getMainAnimationTracks()) {
            track.setBlendFieldWeight(track.getName().equals("Bob_WalkLightLimpL") ? .5f : 0);
            track.setBlendWeight(.4f);
        }
        close(CartInjury.poseWeight(f.player), .2, "outgoing light limp lost torso correction after healing");
        f.source.name = "defaultRun";
        try {
            close(CartInjury.poseWeight(f.player), 0, "native outgoing clips acquired cart-owned correction after healing");
            f.player.injury = -.228f;
            close(CartInjury.poseWeight(f.player), 1, "native catch-up fallback lost current cart injury support");
        } finally { f.source.name = "ToolkitWoodCartPivotWalk"; }
        close(CartInjury.poseWeight(null), 0, "missing actor acquired torso correction");
    }

    private static void stationaryContinuity() throws Exception {
        for (String type : List.of("SaucedCarts.ShoppingCart", "SaucedWheelbarrow.WheelbarrowWood", "SaucedWheelbarrow.WheelbarrowMetal")) {
            var f = fixture(type, "Walk", 0, false);
            float healthy = CartLegPace.targetSpeed(f.player, 1, 0) * f.player.speed;
            for (float injury : new float[]{-.000001f, .000001f}) {
                f.player.injury = injury;
                float radius = CartInjury.walkMagnitude(f.player, f.player.speed);
                close(CartLegPace.targetSpeed(f.player, 1, 0) * radius, healthy, "tiny injury changed stationary pivot speed");
            }
        }
        close(CartInjury.amount(Float.NaN), 0, "invalid injury acquired blend ownership");
        close(CartInjury.amount(.075f), .5, "injury onset must remain continuous");
        close(CartInjury.amount(-.075f), .5, "left/right injury onset differs");
    }

    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init();
        var field = Unsafe.class.getDeclaredField("theUnsafe"); field.setAccessible(true); unsafe = (Unsafe) field.get(null);
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", CartInjuryTest.class.getClassLoader());
        check(Main.CART_INJURY_SUPPORTED, "installed native injury hook fingerprint unsupported");
        var project = Path.of(System.getProperty("pz.test.project"));
        nativeNodes.put("movement", read(Path.of("media/AnimSets/player/movement/defaultWalk.xml")));
        nativeNodes.put("run", read(Path.of("media/AnimSets/player/run/defaultRun.xml")));
        nativeNodes.put("sprint", read(Path.of("media/AnimSets/player/sprint/defaultSprint.xml")));
        for (String relative : List.of("movement/toolkit_cart_pivot_walk.xml", "movement/toolkit_cart_wood_pivot_walk.xml",
                "run/toolkit_cart_pivot_run.xml", "sprint/toolkit_cart_pivot_sprint.xml")) {
            var node = read(project.resolve("PZSurvivorToolkit/42/media/AnimSets/player").resolve(relative)); cartNodes.put(node.name, node);
        }
        var model = ModelManager.class.getDeclaredField("animModel"); model.setAccessible(true); var previous = model.get(ModelManager.instance);
        var mesh = allocate(ModelMesh.class);
        mesh.skinningData = new SkinningData(clips, List.of(), List.of(), List.of(), List.of(), new HashMap<>());
        model.set(ModelManager.instance, mesh);
        applyField = AnimLayer.class.getDeclaredMethod("applyBlendField", LiveAnimNode.class, float.class, float.class, float.class);
        applyField.setAccessible(true);
        try { directions(); lifecycle(); readiness(); stationaryContinuity(); heavyPoseWeights(); }
        finally { model.set(ModelManager.instance, previous); }
        System.out.println("CART_INJURY_PASS");
    }
}
