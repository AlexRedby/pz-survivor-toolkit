package net.alexredby.javapatchfixture;

import java.lang.instrument.Instrumentation;
import java.nio.file.Path;
import java.util.jar.JarFile;

/** Load the mod as ZombieBuddy does, beside the game's older Kotlin runtime. */
public final class KotlinRuntimeChecks {
    private static void require(boolean value, String reason) {
        if (!value) throw new AssertionError(reason);
    }

    public static void main(String[] args) throws Exception {
        var loader = ClassLoader.getSystemClassLoader();
        var gameRuntime = Class.forName("kotlin.jvm.internal.Intrinsics", true, loader);
        var gameVersion = Class.forName("kotlin.KotlinVersion", true, loader).getField("CURRENT").get(null);
        String privateRuntime = "net.alexredby.pztoolkitruntime.kotlin.jvm.internal.Intrinsics";
        try {
            Class.forName(privateRuntime, false, loader);
            throw new AssertionError("fixture leaked the mod's Kotlin runtime onto its initial classpath");
        } catch (ClassNotFoundException expected) { }
        var field = Class.forName("me.zed_0xff.zombie_buddy.Loader").getDeclaredField("g_instrumentation");
        field.setAccessible(true);
        var instrumentation = (Instrumentation)field.get(null);
        var patch = Path.of(System.getProperty("pz.test.patch.jar")).toRealPath();
        try (var jar = new JarFile(patch.toFile())) {
            require(jar.getEntry("META-INF/pz_toolkit_java_patches.kotlin_module") != null,
                "compiled Kotlin module metadata was omitted");
            require(jar.getEntry("META-INF/licenses/kotlin/LICENSE.txt") != null,
                "bundled Kotlin runtime license was omitted");
            instrumentation.appendToSystemClassLoaderSearch(jar);
            // Keep this entry in Java: a Kotlin main would warm Intrinsics before the transformer
            // is installed, hiding recursive class definition on its foreign-class dispatch path.
            var fences = Class.forName("net.alexredby.pztoolkitjavapatches.FenceValidation", true, loader);
            for (var loaded : instrumentation.getAllLoadedClasses())
                require(!loaded.getName().equals(privateRuntime), "cold transformer fixture warmed Intrinsics too early");
            require(Boolean.TRUE.equals(fences.getMethod("install", boolean.class).invoke(null, true)),
                "cold Kotlin transformer installation failed");
            var paths = Class.forName("net.alexredby.pztoolkitjavapatches.TVVideoPaths", true, loader);
            var redirect = paths.getMethod("redirect", String.class, boolean.class);
            require(redirect.invoke(null, null, true) == null, "nullable Java API changed");
            require("unrelated.bik".equals(redirect.invoke(null, "unrelated.bik", true)),
                "unrelated filename changed");
            var prefix = (String)paths.getField("PREFIX").get(null);
            var missing = prefix + "Missing.bik";
            var relative = paths.getMethod("relative", String.class, Path.class, Path.class);
            var cache = Path.of(System.getProperty("pz.test.cache"));
            require(missing.equals(relative.invoke(null, missing, cache, cache)),
                "missing file guard changed after runtime loading");
            var runtime = Class.forName(privateRuntime, false, loader);
            require(Path.of(runtime.getProtectionDomain().getCodeSource().getLocation().toURI())
                .toRealPath().equals(patch), "Kotlin runtime did not come from the distributed mod JAR");
            require(jar.stream().noneMatch(entry -> entry.getName().startsWith("kotlin/")),
                "mod JAR still exports an unrelocated Kotlin runtime");
            require(Class.forName("kotlin.jvm.internal.Intrinsics", false, loader) == gameRuntime
                && Class.forName("kotlin.KotlinVersion", true, loader).getField("CURRENT").get(null) == gameVersion,
                "mod replaced the game's Kotlin runtime");
            var version = Class.forName("net.alexredby.pztoolkitruntime.kotlin.KotlinVersion", true, loader)
                .getField("CURRENT").get(null);
            require("2.4.21".equals(version.toString()), "private runtime version changed");
        }
        var fonts = patch.getParent().getParent().resolve("bootstrap/PZToolkitFonts.jar");
        try (var jar = new JarFile(fonts.toFile())) {
            require(jar.stream().noneMatch(entry -> entry.getName().startsWith("kotlin/")
                || entry.getName().startsWith("net/alexredby/pztoolkitruntime/")),
                "early fonts unexpectedly bundled the Kotlin runtime");
        }
        System.out.println("KOTLIN_RUNTIME_CHECKS_PASS (late mod JAR registration, private stdlib 2.4.21 beside game "
            + gameVersion + ", cold transformer, Java static/null ABI, independent fonts)");
    }
}
