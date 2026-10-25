import java.nio.ByteBuffer;
import org.lwjgl.glfw.GLFW;
import org.lwjgl.glfw.GLFWErrorCallback;
import org.lwjgl.opengl.GL;
import org.lwjgl.opengl.GL11;
import org.lwjgl.system.MemoryUtil;

/** Real NSGL framebuffer readback without showing a window or starting a game. */
public final class ToolkitGlfwProbe {
    public static void main(String[] args) {
        GLFWErrorCallback.createPrint(System.err).set();
        GLFW.glfwInitHint(GLFW.GLFW_COCOA_CHDIR_RESOURCES, GLFW.GLFW_FALSE);
        GLFW.glfwInitHint(GLFW.GLFW_COCOA_MENUBAR, GLFW.GLFW_FALSE);
        if (!GLFW.glfwInit()) throw new IllegalStateException("GLFW init failed");
        long window = 0;
        try {
            long monitor = GLFW.glfwGetPrimaryMonitor();
            if (monitor == 0 || GLFW.glfwGetVideoMode(monitor) == null)
                throw new IllegalStateException("Connected display/video mode unavailable");
            GLFW.glfwDefaultWindowHints();
            GLFW.glfwWindowHint(GLFW.GLFW_VISIBLE, GLFW.GLFW_FALSE);
            GLFW.glfwWindowHint(GLFW.GLFW_FOCUSED, GLFW.GLFW_FALSE);
            GLFW.glfwWindowHint(GLFW.GLFW_FOCUS_ON_SHOW, GLFW.GLFW_FALSE);
            window = GLFW.glfwCreateWindow(32, 32, "Toolkit hidden framebuffer probe", 0, 0);
            if (window == 0) throw new IllegalStateException("Hidden native window unavailable");
            GLFW.glfwMakeContextCurrent(window);
            GL.createCapabilities();
            GL11.glClearColor(0.25f, 0.5f, 0.75f, 1.0f);
            GL11.glClear(GL11.GL_COLOR_BUFFER_BIT);
            ByteBuffer pixel = MemoryUtil.memAlloc(4);
            try {
                GL11.glReadPixels(0, 0, 1, 1, GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, pixel);
                int[] expected = {64, 128, 191, 255};
                for (int i = 0; i < 4; i++) {
                    if (Math.abs(Byte.toUnsignedInt(pixel.get(i)) - expected[i]) > 2)
                        throw new IllegalStateException("Native framebuffer readback mismatch at channel " + i);
                }
                int error = GL11.glGetError();
                if (error != GL11.GL_NO_ERROR) throw new IllegalStateException("OpenGL error: " + error);
                System.out.println("[QUEUE_TEST] GLFW_FRAMEBUFFER_READY monitor=" + monitor
                    + " renderer=" + GL11.glGetString(GL11.GL_RENDERER));
            } finally { MemoryUtil.memFree(pixel); }
        } finally {
            if (window != 0) GLFW.glfwDestroyWindow(window);
            GLFW.glfwTerminate();
        }
    }
}
