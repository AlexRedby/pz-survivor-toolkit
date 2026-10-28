import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import sun.misc.Unsafe;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.*;
import zombie.GameTime;
import zombie.SandboxOptions;
import zombie.Lua.*;
import zombie.inventory.*;
import zombie.inventory.types.Food;
import net.alexredby.pztoolkitjavapatches.CleanUIFoodAge;

/** Real Food/Kahlua checks, without a game loop, UI, generator or network. */
public final class FoodAgeChecks {
    static Unsafe unsafe;
    static Field lastFrozenUpdate;
    static int cases;

    static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    static Object lua(String code) throws Exception {
        return LuaManager.thread.call(LuaCompiler.loadstring(code, "food-age-checks", LuaManager.env), new Object[0]);
    }

    static String function(String source, String name, String next) {
        int start = source.indexOf("local function " + name + "(");
        int end = source.indexOf("\nlocal function " + next + "(", start);
        require(start >= 0 && end > start, "CleanUI helper boundary changed: " + name);
        return source.substring(start, end);
    }

    static void loadHelper(String source) throws Exception {
        StringBuilder setup = new StringBuilder("local function CleanUI_getCachedTimestampMs() return Now end\n");
        Matcher constants = Pattern.compile("(?m)^local CLEANUI_COLLAPSED_FOOD_AGE_UPDATE_[A-Z_]+ = [0-9]+\\s*$").matcher(source);
        while (constants.find()) setup.append(constants.group()).append('\n');
        setup.append(function(source, "CleanUI_getStackActualStartIndex", "CleanUI_getStackFirstActualItem"));
        setup.append('\n').append(function(source, "CleanUI_updateCollapsedFoodStackAge", "CleanUI_truncateForWeightColumn"));
        setup.append("\nreturn CleanUI_updateCollapsedFoodStackAge");
        LuaManager.env.rawset("helper", lua(setup.toString()));
    }

    static void clock(float hour) {
        GameTime.getInstance().setNightsSurvived(4);
        GameTime.getInstance().setTimeOfDay(7 + hour - 96);
    }

    static Food food(ItemContainer container, float age) throws Exception {
        // Avoid the asset/script-heavy constructor. All state used by age/freezing
        // below is initialized, with Apple's real five/eight-day thresholds.
        Food item = (Food) unsafe.allocateInstance(Food.class);
        item.setAge(age);
        item.setLastAged(100);
        item.setOffAge(5);
        item.setOffAgeMax(8);
        item.setContainer(container);
        item.setHeat(container.getTemperature());
        item.setCanBeFrozen(true);
        lastFrozenUpdate.setFloat(item, 100);
        return item;
    }

    static KahluaTable group(List<Food> items, boolean optimized) {
        KahluaTable group = LuaManager.platform.newTable(), rows = LuaManager.platform.newTable();
        int offset = optimized ? 1 : 2;
        if (!optimized && !items.isEmpty()) rows.rawset(1, items.get(0)); // Normal dummy duplicates the head.
        for (int i = 0; i < items.size(); i++) rows.rawset(i + offset, items.get(i));
        group.rawset("items", rows);
        group.rawset("cleanUILargeStackOptimized", optimized);
        return group;
    }

    static void update(KahluaTable group, double now, boolean visible) throws Exception {
        LuaManager.env.rawset("Group", group);
        LuaManager.env.rawset("Now", now);
        lua("helper(Group," + visible + ")");
    }

    static double events() { return ((Number) LuaManager.env.rawget("AgeEvents")).doubleValue(); }

    static void boundaries(boolean fixed) throws Exception {
        for (int size : List.of(0, 49, 50, 199)) for (boolean optimized : List.of(false, true)) {
            clock(100);
            ItemContainer container = new ItemContainer();
            container.setType("crate");
            ArrayList<Food> items = new ArrayList<>();
            for (int i = 0; i < size; i++) items.add(food(container, .1f));
            KahluaTable group = group(items, optimized);
            clock(104.8f);
            update(group, 1000, false);
            for (Food item : items) require(item.getAge() == .1f, "hidden group aged");
            update(group, 1000, true);
            for (int i = 0; i < size; i++) {
                boolean visited = fixed || !optimized || i < 50;
                require((items.get(i).getAge() > .1f) == visited, "size/index boundary " + size + "/" + i);
            }
            if (!items.isEmpty()) {
                Food head = items.get(0);
                float age = head.getAge();
                clock(105.8f);
                update(group, 1000, true);
                update(group, 1999, true);
                require(head.getAge() == age, "same clock or subsecond throttle changed age");
                update(group, 2000, true);
                require(head.getAge() > age, "one-second boundary did not update");
                clock(106.8f);
                update(group, 500, true);
                require((head.getLastAged() > 105.8f) == fixed, "clock rollback admission");
            }
            cases++;
        }
    }

    static void freshness(boolean fixed, int size, String kind) throws Exception {
        clock(100);
        SandboxOptions.instance.elecShutModifier.setValue(9999);
        ItemContainer container = new ItemContainer();
        container.setType(kind);
        float initialTail = kind.equals("crate") ? 4.9f : 4.99f;
        ArrayList<Food> items = new ArrayList<>();
        for (int i = 0; i < size; i++) items.add(food(container, i == size - 1 ? initialTail : .1f));
        Food head = items.get(0), tail = items.get(size - 1);
        require(head.isFresh() && tail.isFresh() && tail.finishupdate(), "initial freshness/retirement");
        KahluaTable group = group(items, true);
        LuaManager.env.rawset("AgeEvents", 0.0);
        clock(104.8f);
        for (int i = 1; i <= 30; i++) update(group, i * 1000, true);
        float observed = tail.getAge();
        boolean fresh = tail.isFresh();
        double helperEvents = events();
        tail.updateAge(false);
        float caught = tail.getAge();
        require(head.getAge() > .1f && caught > 5 && !tail.isFresh(), "native freshness crossing");
        require(fixed ? observed == caught && !fresh && helperEvents == 1 :
                observed == initialTail && fresh && helperEvents == 0, "tail starvation/fix");
        tail.updateAge(false);
        require(events() == 1, "freshness event must fire exactly once");
        System.out.println("FOOD_AGE_RESULT {\"fixed\":" + fixed + ",\"size\":" + size +
                ",\"container\":\"" + kind + "\",\"tail_after_helper\":" + observed +
                ",\"tail_after_catchup\":" + caught + ",\"helper_events\":" + helperEvents + "}");
        cases++;
    }

    static void nativeControls() throws Exception {
        // Compare delegation with a direct real Food call. These are controlled
        // container/sandbox inputs, not a running refrigerator or generator test.
        for (String scenario : List.of("fridge-power-cut", "freezer-thaw", "cold-transfer")) {
            clock(100);
            ItemContainer container = new ItemContainer();
            container.setType(scenario.equals("freezer-thaw") ? "freezer" : "fridge");
            SandboxOptions.instance.elecShutModifier.setValue(9999);
            ArrayList<Food> items = new ArrayList<>();
            for (int i = 0; i < 200; i++) items.add(food(container, .1f));
            Food tail = items.get(199), control = food(container, .1f);
            if (scenario.equals("freezer-thaw")) {
                tail.setFreezingTime(100); control.setFreezingTime(100);
                tail.setFrozen(true); control.setFrozen(true);
                require(!container.isPowered() && tail.isThawing(), "unpowered freezer fixture");
            } else if (scenario.equals("cold-transfer")) {
                ItemContainer ordinary = new ItemContainer(); ordinary.setType("crate");
                tail.setContainer(ordinary); control.setContainer(ordinary);
                tail.setHeat(.2f); control.setHeat(.2f);
            } else SandboxOptions.instance.elecShutModifier.setValue(-1);
            clock(104.8f);
            control.updateAge(false);
            update(group(items, true), 1000, true);
            require(tail.getAge() == control.getAge() && tail.getHeat() == control.getHeat() &&
                    tail.getFreezingTime() == control.getFreezingTime() && tail.isFrozen() == control.isFrozen(),
                    "native state delegation: " + scenario);
            require(tail.getAge() > .1f, "unpowered/transferred food should age");
            if (scenario.equals("freezer-thaw")) require(!tail.isFrozen(), "freezer food should thaw");
            cases++;
        }
    }

    public static void main(String[] args) throws Exception {
        require(args.length == 2, "expected original pane and private cache");
        String original = Files.readString(Path.of(args[0]));
        String corrected = CleanUIFoodAge.transformSource(original);
        require(!corrected.equals(original), "reviewed original CleanUI input was not corrected by the shipped patch");
        Field field = Unsafe.class.getDeclaredField("theUnsafe"); field.setAccessible(true);
        unsafe = (Unsafe) field.get(null);
        lastFrozenUpdate = Food.class.getDeclaredField("lastFrozenUpdate"); lastFrozenUpdate.setAccessible(true);
        zombie.ZomboidFileSystem.instance.setCacheDir(args[1]);
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init();
        GameTime.setInstance(new GameTime()); clock(100);
        LuaManager.platform = new J2SEPlatform(); LuaManager.env = LuaManager.platform.newEnvironment();
        KahluaConverterManager converters = new KahluaConverterManager(); KahluaNumberConverter.install(converters);
        LuaManager.exposer = new LuaManager.Exposer(converters, LuaManager.platform, LuaManager.env);
        for (Class<?> type : List.of(InventoryItem.class, Food.class)) LuaManager.exposer.setExposed(type);
        for (Class<?> type : List.of(InventoryItem.class, Food.class)) LuaManager.exposer.exposeLikeJava(type, LuaManager.env);
        LuaManager.thread = new KahluaThread(LuaManager.platform, LuaManager.env);
        LuaManager.thread.debugOwnerThread = Thread.currentThread();
        LuaManager.caller = new se.krka.kahlua.integration.LuaCaller(converters);
        LuaEventManager.AddEvent("OnContainerUpdate").callbacks.add((LuaClosure) lua(
                "return function(item) AgeEvents=(AgeEvents or 0)+1 end"));
        zombie.ZomboidFileSystem.instance.init();
        SandboxOptions.instance.daysForRottenFoodRemoval.setValue(-1);
        SandboxOptions.instance.foodRotSpeed.setValue(3); SandboxOptions.instance.fridgeFactor.setValue(3);
        LuaManager.env.rawset("AgeEvents", 0.0);
        for (boolean fixed : List.of(false, true)) {
            loadHelper(fixed ? corrected : original);
            boundaries(fixed);
            for (int size : List.of(200, 10000)) for (String kind : List.of("crate", "fridge")) freshness(fixed, size, kind);
            if (fixed) nativeControls();
        }
        System.out.println("FOOD_AGE_NATIVE_PASS {\"cases\":" + cases + ",\"scope\":\"real_Food_Kahlua_no_game_loop_or_network\"}");
    }
}
