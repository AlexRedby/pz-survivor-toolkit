package net.alexredby.cartlab;
import me.zed_0xff.zombie_buddy.Patch;
/** Only annotated JVM slot writeback remains Java. */
public final class MainAdvice {
    @Patch(className="zombie.input.GameKeyboard", methodName="isKeyDown", warmUp=true)
    public static class Keys {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(0) int key, @Patch.Local("fixture") boolean fixture) {
            fixture = Main.drive >= 0;
            return fixture;
        }
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) int key, @Patch.Local("fixture") boolean fixture,
                                @Patch.Return(readOnly=false) boolean result) {
            if (fixture) result = Main.fixtureKey(key);
        }
    }

    @Patch(className="zombie.input.GameKeyboard", methodName="isKeyDownRaw", warmUp=true)
    public static class RawKeys {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(0) int key, @Patch.Local("fixture") boolean fixture) {
            fixture = Main.drive >= 0;
            return fixture;
        }
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) int key, @Patch.Local("fixture") boolean fixture,
                                @Patch.Return(readOnly=false) boolean result) {
            if (fixture) result = Main.fixtureKey(key);
        }
    }
}
