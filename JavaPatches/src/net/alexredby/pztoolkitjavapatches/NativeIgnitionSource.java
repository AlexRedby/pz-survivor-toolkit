package net.alexredby.pztoolkitjavapatches;

import java.io.IOException;
import java.io.Reader;
import java.io.StringReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.List;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.ZomboidFileSystem;

/** Preserve native ignition completion when authoritative consumption already detached its input. */
public final class NativeIgnitionSource {
    public static final String CAMPFIRE_LITERATURE = "media/lua/shared/Camping/TimedActions/ISLightFromLiterature.lua";
    public static final String BBQ_LITERATURE = "media/lua/shared/TimedActions/ISBBQLightFromLiterature.lua";
    public static final String BBQ_KINDLE = "media/lua/shared/TimedActions/ISBBQLightFromKindle.lua";
    public static final List<String> TARGETS = List.of(CAMPFIRE_LITERATURE, BBQ_LITERATURE, BBQ_KINDLE);
    private record Source(String target, String input, String output, String statement) { }
    private static final List<Source> SOURCES = List.of(
        new Source(CAMPFIRE_LITERATURE,
            "6a7c32dbe71434a2809ce91d45a3d0967cc95a652436b907f6c6b1c59d052ad0",
            "7c52dfebee12e7a6badf744f7d75f7520875000bd5385e5883e3b5b9ef02107d",
            "\tself.item:getContainer():setDrawDirty(true);"),
        new Source(BBQ_LITERATURE,
            "3728a9716d6db59e25825c8679ac734a01800e5d10fc812c17f7b7ac9fdf9fdc",
            "8892605eabfac8a1bb04ef4ce6972be79748856dae51bdbec1ec2b6bbf7c4648",
            "\tself.item:getContainer():setDrawDirty(true)"),
        new Source(BBQ_KINDLE,
            "877d91a27f0afe74aeb29f5957b0aaaccc905956cf3344fb0b67fa4e8ecc0a1d",
            "930c5b2ce588ffeed31cebd10de3850046058d9b7cfbcce2cd068f96cc277693",
            "\t\tself.item:getContainer():setDrawDirty(true);")
    );
    private static final int MAX_SOURCE_CHARS = 128 * 1024;
    public static final boolean SUPPORTED =
        BytecodeSupport.supports("zombie/Lua/LuaManager.class", "dcaad0082ca27a15550c7d0a6e14b3aeb71f634a14f32123dec620df180c646d")
        && BytecodeSupport.supports("se/krka/kahlua/luaj/compiler/LuaCompiler.class", "dd2b68ac4ce7a8e65cd7c3b11a3c1672a2471b824a675d4085e7b07041d4cbad")
        && BytecodeSupport.supports("zombie/ZomboidFileSystem.class", "c4e5a5123bc43d03f2585c40f37544c50c1e702eebceb78bec94069e410b6750");
    private static final ThreadLocal<Scope> LOADING = new ThreadLocal<>();

    private NativeIgnitionSource() { }

    public static final class Scope {
        private final String target;
        private final String resolved;
        private final Path provider;
        private boolean claimed;
        private Scope(String target, String resolved, Path provider) {
            this.target = target; this.resolved = resolved; this.provider = provider;
        }
    }

    /** Even an unrelated nested RunLua must temporarily mask its parent's ownership. */
    public static Scope begin(String file, boolean supported) {
        Scope previous = LOADING.get();
        Scope candidate = candidateScope(file, supported);
        LOADING.set(candidate != null ? candidate : new Scope(null, null, null));
        return previous;
    }

    public static void end(Scope previous) {
        if (previous == null) LOADING.remove();
        else LOADING.set(previous);
    }

    private static Scope candidateScope(String file, boolean supported) {
        if (!supported || file == null) return null;
        String normalized = file.replace('\\', '/');
        for (String target : TARGETS) {
            if (!normalized.equals(target) && !normalized.endsWith("/" + target)) continue;
            try {
                ZomboidFileSystem files = ZomboidFileSystem.instance;
                if (Boolean.TRUE.equals(files.ignoreActiveFileMap.get())) return null;
                Path nativeFile = files.getMediaRootFile().toPath().resolve(target.substring("media/".length())).toRealPath();
                String resolved = files.getString(normalized);
                // The active provider and the actual load must both be the physical
                // game source. Identical text from a mod override is not native ownership.
                if (Files.isRegularFile(nativeFile)
                        && Files.isSameFile(nativeFile, Path.of(files.getString(target)))
                        && Files.isSameFile(nativeFile, Path.of(resolved))) return new Scope(target, resolved, nativeFile);
            } catch (IOException | RuntimeException ignored) {
                return null;
            }
        }
        return null;
    }

    /** Source-only gate for differential checks; runtime also requires the native provider scope. */
    public static String transformSource(String target, String source) {
        if (source == null) return null;
        for (Source known : SOURCES) {
            if (!known.target.equals(target) || !known.input.equals(sha256(source))) continue;
            String before = known.statement;
            int at = source.indexOf(before);
            if (at < 0 || source.indexOf(before, at + before.length()) >= 0) return source;
            String indent = before.substring(0, before.indexOf("self"));
            String newline = source.contains("\r\n") ? "\r\n" : "\n";
            String after = indent + "local container = self.item:getContainer()" + newline
                + indent + "if container then container:setDrawDirty(true) end";
            String result = source.substring(0, at) + after + source.substring(at + before.length());
            return known.output.equals(sha256(result)) ? result : source;
        }
        return source;
    }

    private static String sha256(String source) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(source.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException error) { throw new AssertionError(error); }
    }

    /** The native loader retains ownership of closing its original Reader. */
    public static Reader compilerInput(Reader reader, String name, boolean supported) throws IOException {
        Scope scope = LOADING.get();
        if (!supported || scope == null || scope.target == null || scope.claimed
                || !CompilerInputName.matches(name, scope.target.substring(scope.target.lastIndexOf('/') + 1), scope.resolved)) return reader;
        scope.claimed = true;
        Scope current = candidateScope(scope.resolved, supported);
        if (current == null || !scope.target.equals(current.target) || !scope.provider.equals(current.provider)) return reader;
        try {
            if (!Files.isSameFile(scope.provider, Path.of(scope.resolved))) return reader;
        } catch (IOException | RuntimeException ignored) { return reader; }
        CompilerReaderInput.Captured captured = CompilerReaderInput.capture(reader, MAX_SOURCE_CHARS);
        String original = captured.getText();
        if (original == null) return captured.getReader();
        String transformed = transformSource(scope.target, original);
        if (transformed != original) System.out.println("[PZToolkitJavaPatches] Native ignition compiler input corrected: " + scope.target);
        return transformed == original ? captured.getReader() : new StringReader(transformed);
    }

    @Patch(className="zombie.Lua.LuaManager", methodName="RunLua", warmUp=true, strictMatch=true)
    public static class LoadingSource {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) String file, @Patch.Argument(1) boolean rewrite,
                                 @Patch.Local("toolkitNativeIgnitionSource") Scope previous) {
            previous = begin(file, SUPPORTED);
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Argument(0) String file, @Patch.Argument(1) boolean rewrite,
                                @Patch.Local("toolkitNativeIgnitionSource") Scope previous) {
            end(previous);
        }
    }

    @Patch(className="se.krka.kahlua.luaj.compiler.LuaCompiler", methodName="loadis", warmUp=true, strictMatch=true)
    public static class CompilingSource {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(value=0, readOnly=false) Reader reader,
                                 @Patch.Argument(1) String name,
                                 @Patch.Argument(2) se.krka.kahlua.vm.KahluaTable environment) throws IOException {
            reader = compilerInput(reader, name, SUPPORTED);
        }
    }
}
