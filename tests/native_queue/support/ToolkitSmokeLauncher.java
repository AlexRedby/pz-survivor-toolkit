import org.lwjgl.glfw.GLFW;
import org.lwjgl.glfw.GLFWErrorCallback;
import zombie.GameWindow;
import zombie.gameStates.GameLoadingState;
import zombie.gameStates.MainScreenState;
import zombie.gameStates.TermsOfServiceState;
public class ToolkitSmokeLauncher {
    public static void main(String[] args) throws Exception {
        if (!java.util.Arrays.asList(args).contains("-novoip")) throw new IllegalArgumentException("Native tests require -novoip to leave the microphone closed.");
        GLFWErrorCallback.createPrint(System.err).set();
        // Match Display.init before pre-initializing Cocoa on the first thread.
        GLFW.glfwInitHint(GLFW.GLFW_COCOA_CHDIR_RESOURCES, GLFW.GLFW_FALSE);
        if (!GLFW.glfwInit()) throw new IllegalStateException("GLFW initialization failed; run this fixture in the desktop session outside the sandbox.");
        long deadline = System.nanoTime() + 10_000_000_000L;
        long monitor = GLFW.glfwGetPrimaryMonitor();
        while (monitor == 0 && System.nanoTime() < deadline) {
            Thread.sleep(100);
            GLFW.glfwPollEvents();
            monitor = GLFW.glfwGetPrimaryMonitor();
        }
        if (monitor == 0) throw new IllegalStateException("No awake macOS display is available; wake/connect the display before running the native fixture.");
        var mode = GLFW.glfwGetVideoMode(monitor);
        if (mode == null) throw new IllegalStateException("The primary display has no video mode; native fixture cannot start.");
        System.out.println("[QUEUE_TEST] DISPLAY_READY " + mode.width() + "x" + mode.height());
        Thread helper = new Thread(() -> {
            try {
                boolean checkedVoice = false;
                while (true) {
                    Thread.sleep(1000);
                    var state = GameWindow.states == null ? null : GameWindow.states.current;
                    if (state instanceof TermsOfServiceState terms) {
                        terms.fromLua0("exit");
                        System.out.println("[QUEUE_TEST] TEST_FIXTURE skipped first-run screen without recording acceptance");
                    }
                    if (state instanceof GameLoadingState loading) {
                        if (!checkedVoice) {
                            var voice = zombie.core.raknet.VoiceManager.getInstance();
                            var initialized = voice.getClass().getDeclaredField("initialisedRecDev");
                            var sound = voice.getClass().getDeclaredField("fmodRecordSound");
                            initialized.setAccessible(true);
                            sound.setAccessible(true);
                            if (!zombie.core.raknet.VoiceManager.voipDisabled || initialized.getBoolean(voice) || sound.getLong(voice) != 0) throw new IllegalStateException("Microphone was not disabled.");
                            System.out.println("[QUEUE_TEST] VOICE_DISABLED");
                            checkedVoice = true;
                        }
                        // Resolve only after the engine creates its loading state; do not initialize game classes early.
                        var force = loading.getClass().getDeclaredField("forceDone");
                        force.setAccessible(true);
                        force.setBoolean(loading, true);
                    }
                }
            } catch (Exception error) {
                System.err.println("[QUEUE_TEST] FAIL native launcher " + error);
                error.printStackTrace();
            }
        }, "toolkit-smoke-loading-helper");
        helper.setDaemon(true);
        helper.start();
        MainScreenState.main(args);
    }
}
