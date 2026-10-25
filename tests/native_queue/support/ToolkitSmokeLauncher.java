import org.lwjgl.glfw.GLFW;
import org.lwjgl.glfw.GLFWErrorCallback;
import zombie.GameWindow;
import zombie.gameStates.GameLoadingState;
import zombie.gameStates.MainScreenState;
import zombie.gameStates.TermsOfServiceState;
public class ToolkitSmokeLauncher {
    public static void main(String[] args) throws Exception {
        if (!java.util.Arrays.asList(args).contains("-novoip")) throw new IllegalArgumentException("Native tests require -novoip to leave the microphone closed.");
        ToolkitWindowBootstrap.beforeGlfwInit();
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
        if (monitor == 0) throw new IllegalStateException("GLFW found no connected display. Check the prepared GLFW compatibility input and launch outside the sandbox in the logged-in macOS session; display sleep alone does not require waking the screen.");
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
        if (System.getProperty("toolkit.test.hostCache") != null) {
            Thread commands = new Thread(() -> {
                try {
                    var reader = new java.io.BufferedReader(new java.io.InputStreamReader(System.in));
                    String command;
                    while ((command = reader.readLine()) != null) {
                        if (!command.equals("QUEUE_HOST_SAVE_QUIT")) throw new IllegalArgumentException("Unknown Host lifecycle command");
                        var child = hostChild.get();
                        if (child == null || !child.isAlive() || shuttingDown.get()) throw new IllegalStateException("Host child is not live or shutdown was already requested");
                        var field = zombie.network.CoopMaster.class.getDeclaredField("serverProcess");
                        field.setAccessible(true);
                        var process = (Process)field.get(zombie.network.CoopMaster.instance);
                        if (process == null || !process.isAlive() || process.pid() != child.pid()
                                || !child.parent().map(parent -> parent.pid() == ProcessHandle.current().pid()).orElse(false)) {
                            throw new IllegalStateException("Native Host process differs from the proved child");
                        }
                        // Plain save/quit lines enter GameServer's existing native command queue.
                        // Keep its owner and heartbeat alive until the authority has saved and exited.
                        shuttingDown.set(true);
                        process.getOutputStream().write("save\nquit\n".getBytes(java.nio.charset.StandardCharsets.US_ASCII));
                        process.getOutputStream().flush();
                        if (!process.waitFor(30, java.util.concurrent.TimeUnit.SECONDS)) throw new IllegalStateException("Host child did not save/quit before its deadline");
                        int exit = process.exitValue();
                        System.out.println("[QUEUE_TEST] HOST_SAVED_EXIT pid=" + child.pid() + " exit=" + exit);
                        System.out.flush();
                        if (exit != 0) throw new IllegalStateException("Host child exited unsuccessfully: " + exit);
                    }
                } catch (Exception error) {
                    System.err.println("[QUEUE_TEST] FAIL host save " + error);
                    error.printStackTrace();
                }
            }, "toolkit-owned-host-commands");
            commands.setDaemon(true);
            commands.start();
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
