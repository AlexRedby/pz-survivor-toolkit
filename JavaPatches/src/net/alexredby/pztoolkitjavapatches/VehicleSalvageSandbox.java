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
import zombie.gameStates.ChooseGameInfo;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.ZomboidFileSystem;

/** Correct the reviewed VSO sandbox helper only while its active mod source is compiled. */
public final class VehicleSalvageSandbox {
    public static final String MOD_ID = "VehicleSalvageOverhaulB42";
    public static final String TARGET = "media/lua/shared/VRO_SalvageSandbox.lua";
    public static final String INPUT_SHA256 = "60ee042c1fc032ac4274a5e4b0d62f171638a9fdfaf76a767ab25129f5b38426";
    public static final String OUTPUT_SHA256 = "dcfdfdcf40df95ec26a43bf92ca9ee12ede21fa03376815c2f5cf6b875d1223e";
    private static final int MAX_SOURCE_CHARS = 128 * 1024;
    public static final boolean SUPPORTED =
        BytecodeSupport.supports("zombie/Lua/LuaManager.class", "dcaad0082ca27a15550c7d0a6e14b3aeb71f634a14f32123dec620df180c646d")
        && BytecodeSupport.supports("se/krka/kahlua/luaj/compiler/LuaCompiler.class", "dd2b68ac4ce7a8e65cd7c3b11a3c1672a2471b824a675d4085e7b07041d4cbad")
        && BytecodeSupport.supports("zombie/ZomboidFileSystem.class", "c4e5a5123bc43d03f2585c40f37544c50c1e702eebceb78bec94069e410b6750")
        && BytecodeSupport.supports("zombie/gameStates/ChooseGameInfo.class", "8c4b47ba966f071120feeec090202967e414246e28b5b6fd6a622a6a266af651")
        && BytecodeSupport.supports("zombie/gameStates/ChooseGameInfo$Mod.class", "c91e48400b77015c450a696f2d7c5665fa872f1a76fc05d2c38e72ba2928dc69");
    private static final ThreadLocal<Scope> LOADING = new ThreadLocal<>();

    private VehicleSalvageSandbox() { }

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
        if (!normalized.equals(TARGET) && !normalized.endsWith("/" + TARGET)) return null;
        try {
            ZomboidFileSystem files = ZomboidFileSystem.instance;
            if (Boolean.TRUE.equals(files.ignoreActiveFileMap.get()) || !files.getModIDs().contains(MOD_ID)) return null;
            ChooseGameInfo.Mod mod = ChooseGameInfo.getModDetails(MOD_ID);
            if (mod == null || mod.getVersionDir() == null) return null;
            Path provider = Path.of(mod.getVersionDir()).resolve(TARGET).toRealPath();
            String resolved = files.getString(normalized);
            if (Files.isRegularFile(provider)
                    && Files.isSameFile(provider, Path.of(files.getString(TARGET)))
                    && Files.isSameFile(provider, Path.of(resolved))) return new Scope(TARGET, resolved, provider);
        } catch (IOException | RuntimeException ignored) {
            return null;
        }
        return null;
    }

    /** Both source digests are fixed; unknown upstream revisions retain their original behavior. */
    public static String transformSource(String source) {
        if (source == null || !INPUT_SHA256.equals(sha256(source))) return source;
        String result = replaceOnce(source,
            "    -- normal (top-level) sandbox var",
            "    if SandboxVars.VSO_EnableFullVehicleSalvaging ~= nil then\r\n"
            + "        return SandboxVars.VSO_EnableFullVehicleSalvaging == true\r\n"
            + "    end\r\n\r\n    -- normal (top-level) sandbox var");
        result = replaceOnce(result,
            "    local v = SandboxVars[varName]",
            "    local v\r\n"
            + "    if type(varName) == \"string\" and varName:match(\"^VRO_SalvageTime_\") then\r\n"
            + "        local canonicalKey = varName:gsub(\"^VRO_\", \"VSO_\")\r\n"
            + "        v = SandboxVars[canonicalKey]\r\n"
            + "    end\r\n"
            + "    if v == nil then v = SandboxVars[varName] end");
        return result != null && OUTPUT_SHA256.equals(sha256(result)) ? result : source;
    }

    private static String replaceOnce(String source, String before, String after) {
        if (source == null) return null;
        int at = source.indexOf(before);
        if (at < 0 || source.indexOf(before, at + before.length()) >= 0) return null;
        return source.substring(0, at) + after + source.substring(at + before.length());
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
        String transformed = transformSource(original);
        if (transformed != original) System.out.println("[PZToolkitJavaPatches] VRO salvage sandbox compiler input corrected");
        return transformed == original ? captured.getReader() : new StringReader(transformed);
    }

    @Patch(className="zombie.Lua.LuaManager", methodName="RunLua", warmUp=true, strictMatch=true)
    public static class LoadingSource {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) String file, @Patch.Argument(1) boolean rewrite,
                                 @Patch.Local("toolkitVehicleSalvageSandbox") Scope previous) {
            previous = begin(file, SUPPORTED);
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Argument(0) String file, @Patch.Argument(1) boolean rewrite,
                                @Patch.Local("toolkitVehicleSalvageSandbox") Scope previous) {
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
