import java.util.ArrayDeque;

/** Exercises only fixture-owned probe state; production switches are never changed. */
public final class SessionProbeChecks {
    static void require(boolean value) { if (!value) throw new AssertionError("probe reset guard"); }
    @SuppressWarnings({"rawtypes", "unchecked"})
    public static void main(String[] args) {
        require(net.alexredby.animalhandsrace.Main.reset().equals("clean"));
        net.alexredby.animalhandsrace.Main.pending = new zombie.network.packets.character.AnimalCommandPacket();
        require(net.alexredby.animalhandsrace.Main.reset().startsWith("FAIL"));
        require(net.alexredby.animalhandsrace.Main.pending != null);
        net.alexredby.animalhandsrace.Main.pending = null;
        net.alexredby.animalhandsrace.Main.armed = true;
        require(net.alexredby.animalhandsrace.Main.reset().startsWith("FAIL"));
        net.alexredby.animalhandsrace.Main.armed = false;
        net.alexredby.animalhandsrace.Main.releasing = true;
        require(net.alexredby.animalhandsrace.Main.reset().startsWith("FAIL"));
        net.alexredby.animalhandsrace.Main.releasing = false;
        net.alexredby.animalhandsrace.Main.insideEquipParse = true;
        require(net.alexredby.animalhandsrace.Main.reset().startsWith("FAIL"));
        net.alexredby.animalhandsrace.Main.insideEquipParse = false;
        net.alexredby.animalhandsrace.Main.releaseCount = 3;
        require(net.alexredby.animalhandsrace.Main.reset().equals("clean"));
        require(net.alexredby.animalhandsrace.Main.releaseCount == 0);
        net.alexredby.animaltimerprobe.Main.counts.put((short)7, 3);
        ArrayDeque stack = net.alexredby.animaltimerprobe.Main.stack.get();
        stack.push(new Object());
        require(net.alexredby.animaltimerprobe.Main.reset().startsWith("FAIL"));
        require(net.alexredby.animaltimerprobe.Main.counts.get((short)7) == 3);
        stack.clear();
        require(net.alexredby.animaltimerprobe.Main.reset().equals("clean"));
        require(net.alexredby.animaltimerprobe.Main.counts.isEmpty());
        require(net.alexredby.animaltimerprobe.Main.stack.get().isEmpty());
        System.out.println("ANIMAL_SESSION_PROBE_CHECKS_PASS (pending order guards, timer stack, exact probe reset)");
    }
}
