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
        if (monitor == 0) throw new IllegalStateException("No awake display is available; wake/connect the display before running the native fixture.");
        var mode = GLFW.glfwGetVideoMode(monitor);
        if (mode == null) throw new IllegalStateException("The primary display has no video mode; native fixture cannot start.");
        System.out.println("[QUEUE_TEST] DISPLAY_READY " + mode.width() + "x" + mode.height());
        var hostChild = new java.util.concurrent.atomic.AtomicReference<ProcessHandle>();
        var shuttingDown = new java.util.concurrent.atomic.AtomicBoolean();
        if (System.getProperty("toolkit.test.hostCache") != null) {
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                shuttingDown.set(true);
                var child = hostChild.get();
                if (child == null || !child.isAlive()) return;
                child.destroy();
                try { child.onExit().get(5, java.util.concurrent.TimeUnit.SECONDS); }
                catch (Exception error) { child.destroyForcibly(); }
            }, "toolkit-owned-host-shutdown"));
        }
        Thread helper = new Thread(() -> {
            try {
                boolean checkedVoice = false;
                while (true) {
                    Thread.sleep(1000);
                    String hostCache = System.getProperty("toolkit.test.hostCache");
                    if (hostCache != null) {
                        if (hostChild.get() == null) {
                            try (var children = ProcessHandle.current().children()) {
                                children.filter(child -> {
                                    var arguments = java.util.Arrays.asList(child.info().arguments().orElse(new String[0]));
                                    return arguments.contains("zombie.network.GameServer") && arguments.contains("-coop")
                                        && arguments.contains("-cachedir=" + hostCache);
                                }).forEach(child -> {
                                    if (!hostChild.compareAndSet(null, child)) throw new IllegalStateException("Multiple Host children");
                                    System.out.println("[QUEUE_TEST] HOST_CHILD pid=" + child.pid() + " parent=" + ProcessHandle.current().pid());
                                });
                            }
                            if (hostChild.get() == null && System.getProperty("os.name").startsWith("Windows")) {
                                // Windows ProcessHandle.Info may omit argv. Read the Process
                                // created by native CoopMaster, never discover an unrelated PID.
                                var field = zombie.network.CoopMaster.class.getDeclaredField("serverProcess");
                                field.setAccessible(true);
                                var process = (Process)field.get(zombie.network.CoopMaster.instance);
                                if (process != null && process.isAlive()) {
                                    var child = process.toHandle();
                                    if (child.parent().map(parent -> parent.pid() == ProcessHandle.current().pid()).orElse(false)
                                            && hostChild.compareAndSet(null, child)) {
                                        System.out.println("[QUEUE_TEST] HOST_CHILD pid=" + child.pid() + " parent=" + ProcessHandle.current().pid());
                                    }
                                }
                            }
                        } else if (!shuttingDown.get() && !hostChild.get().isAlive()) {
                            throw new IllegalStateException("Host child exited before its owner");
                        }
                    }
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
