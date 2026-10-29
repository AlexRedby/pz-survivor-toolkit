package net.alexredby.pztoolkitjavapatches;

import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import me.zed_0xff.zombie_buddy.Patch;

/** Test-only observation of the original stream retained by native RunLua. */
public final class QueueBindingSourceFixture {
    private static final Set<String> watched = new HashSet<>();
    private static final Map<String, TrackedReader> latest = new HashMap<>();

    public static void watch(String path) { watched.add(path.replace('\\', '/')); }
    public static TrackedReader latest(String path) { return latest.get(path.replace('\\', '/')); }

    public static InputStreamReader track(String path, InputStreamReader reader) {
        String normalized = path.replace('\\', '/');
        if (reader == null || !watched.contains(normalized)) return reader;
        TrackedReader tracked = new TrackedReader(reader);
        latest.put(normalized, tracked);
        return tracked;
    }

    public static final class TrackedReader extends InputStreamReader {
        private final InputStreamReader original;
        public int closes;
        public int reads;
        private TrackedReader(InputStreamReader original) {
            super(InputStream.nullInputStream());
            this.original = original;
        }
        @Override public int read(char[] buffer, int offset, int length) throws IOException {
            reads++;
            return original.read(buffer, offset, length);
        }
        @Override public int read() throws IOException { reads++; return original.read(); }
        @Override public boolean ready() throws IOException { return original.ready(); }
        @Override public void close() throws IOException {
            closes++;
            try { original.close(); } finally { super.close(); }
        }
    }

    @Patch(className="zombie.core.IndieFileLoader", methodName="getStreamReader", warmUp=true, strictMatch=true)
    public static class StreamOwner {
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) String path,
                @Patch.Return(readOnly=false) InputStreamReader reader) {
            reader = track(path, reader);
        }
    }
}
