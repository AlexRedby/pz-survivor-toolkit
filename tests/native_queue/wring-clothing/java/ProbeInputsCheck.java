import se.krka.kahlua.integration.LuaCaller;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.j2se.KahluaTableImpl;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;
import zombie.characters.CharacterTimedActions.LuaTimedActionNew;

/** Source-launchable check of the installed engine APIs used by the disposable probe. */
class ProbeInputsCheck {
    public static void main(String[] arguments) throws Exception {
        var platform = new J2SEPlatform();
        KahluaTable parent = platform.newTable();
        KahluaTable action = platform.newTable();
        Object stop = new Object();
        parent.rawset("stop", stop);
        action.setMetatable(parent);
        if (((KahluaTableImpl) action).delegate.containsKey("stop") || action.rawget("stop") != stop)
            throw new AssertionError("Inherited native stop callback did not resolve through rawget");
        var pcall = LuaCaller.class.getMethod("pcall", KahluaThread.class, Object.class, Object.class);
        if (pcall.getReturnType() != Object[].class
                || LuaTimedActionNew.class.getMethod("stop").getReturnType() != void.class)
            throw new AssertionError("Native stop callback advice API changed");
        System.out.println("WRING_STOP_PROBE_INPUTS_PASS");
    }
}
