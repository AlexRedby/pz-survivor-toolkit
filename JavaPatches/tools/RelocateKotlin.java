import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.jetbrains.org.objectweb.asm.ClassReader;
import org.jetbrains.org.objectweb.asm.ClassWriter;
import org.jetbrains.org.objectweb.asm.Opcodes;
import org.jetbrains.org.objectweb.asm.commons.ClassRemapper;
import org.jetbrains.org.objectweb.asm.commons.Remapper;

/** Build-time relocation using the compiler distribution's ASM; never shipped in either mod JAR. */
public final class RelocateKotlin {
    private static final String ORIGINAL = "kotlin/";
    private static final String PRIVATE = "net/alexredby/pztoolkitruntime/kotlin/";
    private static final String ORIGINAL_DOTTED = "kotlin.";
    private static final String PRIVATE_DOTTED = "net.alexredby.pztoolkitruntime.kotlin.";

    private static final Remapper REMAPPER = new Remapper() {
        @Override
        public String map(String name) {
            return name.startsWith(ORIGINAL) ? PRIVATE + name.substring(ORIGINAL.length()) : name;
        }

        @Override
        public Object mapValue(Object value) {
            if (value instanceof String name) {
                if (name.startsWith(ORIGINAL)) return map(name);
                if (name.startsWith(ORIGINAL_DOTTED)) {
                    return PRIVATE_DOTTED + name.substring(ORIGINAL_DOTTED.length());
                }
            }
            return super.mapValue(value);
        }
    };

    public static void main(String[] args) throws IOException {
        if (args.length != 1 && !(args.length == 2 && args[1].equals("--tests")))
            throw new IllegalArgumentException("Usage: RelocateKotlin <classes-directory> [--tests]");
        boolean tests = args.length == 2;
        Path classes = Path.of(args[0]).toAbsolutePath().normalize();
        Path runtime = classes.resolve(PRIVATE);
        Path application = classes.resolve("net/alexredby/pztoolkitjavapatches");
        List<Path> sources;
        try (var paths = Files.walk(classes)) {
            sources = paths.filter(Files::isRegularFile)
                .filter(path -> path.toString().endsWith(".class"))
                .filter(path -> tests || path.startsWith(runtime) || path.startsWith(application))
                .sorted().toList();
        }
        for (Path source : sources) {
            ClassReader reader = new ClassReader(Files.readAllBytes(source));
            ClassWriter writer = new ClassWriter(0);
            reader.accept(new ClassRemapper(Opcodes.ASM9, writer, REMAPPER) {}, 0);
            // The build has already staged runtime files under their private destination names.
            Files.write(source, writer.toByteArray());
        }
    }

    private RelocateKotlin() {}
}
