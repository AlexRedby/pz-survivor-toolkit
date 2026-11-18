import copy
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from textwrap import dedent
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import loot_demand_drive as road


def selection(case='drive', **options):
    return dict(suite='loot-demand-drive', kind='sp', clients=1, mode='native', languages=['EN'],
        cases=[case], mods=['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit', 'PZDrivingBench', 'FurniturePushPull'],
        resources={'exclusive': True}, options=dict(optimizer_enabled=False,
            **({'world_template': 'sealed-world', 'loot_demand_arm': 'observe'} if case == 'drive' else {}),
            driving_perf=dict(scenario='muldraugh-extinction', population_mode='native', vehicle_script='Base.SportsCar', full_throttle=True),
            **options))


class RoadJfrTests(unittest.TestCase):
    def test_default_seed_and_both_drive_arms(self):
        for case in ('seed', 'drive'):
            s = selection(case)
            for enabled in (None, False):
                if enabled is not None: s['options']['road_jfr'] = enabled
                road.validate(s)
                self.assertEqual(road.jfr_arguments(s, 'client1', Path('/run/client1'), {}), [])
        for arm in ('observe', 'defer'):
            s = selection(road_jfr=True)
            s['options']['loot_demand_arm'] = arm
            road.validate(s)

    def test_opt_in_identity_and_scope(self):
        s = selection(road_jfr=True)
        runtime = {'fixture': {'road_jfr': {'owner': 'a' * 32}}}
        args = road.jfr_arguments(s, 'client1', Path('/run/client1'), runtime)
        self.assertIn('name=pz-road-' + 'a' * 32, args[0])
        self.assertIn('settings=/run/client1/classes/road-profile.jfc', args[0])
        self.assertIn('filename=/run/client1/road-runtime.jfr', args[0])
        for mutation in ('seed', 'host', 'role', 'suite', 'owner', 'disabled'):
            bad, rt, role = copy.deepcopy(s), copy.deepcopy(runtime), 'client1'
            if mutation == 'seed': bad = selection('seed', road_jfr=True)
            if mutation == 'host': bad['options']['mp_host'] = True
            if mutation == 'role': role = 'server'
            if mutation == 'suite': bad['suite'] = 'health'
            if mutation == 'owner': rt['fixture']['road_jfr']['owner'] = 'foreign'
            if mutation == 'disabled': bad['options']['road_jfr'] = False
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                road.jfr_arguments(bad, role, Path('/run/client1'), rt)
        for value in ('true', 1, None):
            with self.subTest(value=value), self.assertRaises(ValueError):
                road.validate(selection(road_jfr=value))

    def test_profile_and_source_seal(self):
        paths = road.sources(ROOT, selection(road_jfr=True))
        folder = ROOT / 'tests/native_queue/loot-demand-drive/java'
        for name in ('RoadProfile.java', 'road-profile.jfc'):
            self.assertIn(folder / name, paths)
        events = {x.attrib['name']: {s.attrib['name']: s.text for s in x} for x in ET.parse(folder / 'road-profile.jfc').getroot()}
        self.assertEqual(events['pz.RoadClockAnchor']['enabled'], 'true')
        self.assertEqual(events['jdk.ExecutionSample']['period'], '10 ms')
        # Prepared helper classes and JFC must sit under existing snapshot-sealed trees.
        adapter = Path(road.__file__).read_text()
        self.assertIn("classes / 'road-profile.jfc'", adapter)
        main = (folder / 'Main.java').read_text()
        self.assertLess(main.index('Files.writeString(cache.resolve("Lua/loot-demand-drive-status.txt")'),
                        main.index('roadProfile.finish('))


@unittest.skipUnless(os.environ.get('PZ_JFR_TEST_JDK'), 'Set PZ_JFR_TEST_JDK to run the JDK25 collector check')
class RoadJfrJvmTests(unittest.TestCase):
    def test_owned_recording_cpu_anchors_and_wrong_owner(self):
        jdk = Path(os.environ['PZ_JFR_TEST_JDK'])
        source = ROOT / 'tests/native_queue/loot-demand-drive/java'
        with tempfile.TemporaryDirectory(prefix='pz-road-jfr-check-') as temporary:
            root = Path(temporary)
            harness = root / 'CollectorCheck.java'
            harness.write_text(dedent("""\
                package net.alexredby.drivingperf;

                import java.nio.file.Files;
                import java.nio.file.Path;
                import java.util.HashSet;
                import java.util.List;
                import java.util.Set;
                import jdk.jfr.consumer.RecordingFile;

                public class CollectorCheck {
                    public static void main(String[] args) throws Exception {
                        Path cache = Path.of(args[0]);
                        if (args[1].equals("wrong")) {
                            System.setProperty("pz.drivingPerf.jfr.owner", "b".repeat(32));
                            try {
                                new RoadProfile(cache, Thread.currentThread(), 4);
                                throw new AssertionError("foreign JFR accepted");
                            } catch (IllegalStateException expected) {
                                return;
                            }
                        }

                        long gameThreadId = Thread.currentThread().threadId();
                        RoadProfile profile = new RoadProfile(cache, Thread.currentThread(), 4);
                        profile.anchor("begin");
                        profile.anchor("measure");
                        long[] gameTimes = new long[1];
                        long[] swapTimes = new long[1];
                        int[] phases = {3};
                        profile.framed(0);
                        gameTimes[0] = System.nanoTime();

                        Throwable[] swapFailure = new Throwable[1];
                        Thread swapThread = new Thread(() -> {
                            try {
                                profile.swapped(0);
                                swapTimes[0] = System.nanoTime();
                            } catch (Throwable failure) {
                                swapFailure[0] = failure;
                            }
                        }, "road-test-swap");
                        long swapThreadId = swapThread.threadId();
                        swapThread.start();
                        swapThread.join();
                        if (swapFailure[0] != null) {
                            throw new AssertionError("swap capture failed", swapFailure[0]);
                        }
                        if (gameThreadId == swapThreadId) {
                            throw new AssertionError("expected distinct game and swap threads");
                        }
                        profile.finish(swapTimes, phases, 1, gameTimes, phases, 1);

                        var events = RecordingFile.readAllEvents(cache.resolve("road-measured.jfr"))
                                .stream()
                                .filter(event -> event.getEventType().getName().equals("pz.RoadClockAnchor"))
                                .toList();
                        var labels = events.stream().map(event -> event.getString("label")).toList();
                        if (!labels.equals(List.of("begin", "measure", "finish"))) {
                            throw new AssertionError("unexpected anchor labels: " + labels);
                        }
                        for (var event : events) {
                            if (event.getLong("nanoBefore") > event.getLong("nanoAfter")) {
                                throw new AssertionError("unordered anchor");
                            }
                            if (!event.getString("owner").equals("a".repeat(32))) {
                                throw new AssertionError("wrong owner");
                            }
                            if (event.getLong("processId") != ProcessHandle.current().pid()) {
                                throw new AssertionError("wrong process ID");
                            }
                            if (event.getLong("threadId") != gameThreadId
                                    || event.getThread().getJavaThreadId() != gameThreadId) {
                                throw new AssertionError("wrong game thread");
                            }
                        }

                        var rows = Files.readAllLines(cache.resolve("road-thread-cpu.csv"));
                        if (rows.size() != 3) {
                            throw new AssertionError("missing CPU samples");
                        }
                        var sampledThreadIds = new HashSet<Long>();
                        for (String row : rows.subList(1, 3)) {
                            String[] fields = row.split(",");
                            long expectedThreadId = switch (fields[0]) {
                                case "game" -> gameThreadId;
                                case "swap" -> swapThreadId;
                                default -> throw new AssertionError("unexpected CPU channel: " + fields[0]);
                            };
                            if (Long.parseLong(fields[3]) < 0) {
                                throw new AssertionError("missing CPU time");
                            }
                            long actualThreadId = Long.parseLong(fields[4]);
                            sampledThreadIds.add(actualThreadId);
                            if (actualThreadId != expectedThreadId) {
                                throw new AssertionError("wrong CPU sample thread: " + row);
                            }
                        }
                        if (!sampledThreadIds.equals(Set.of(gameThreadId, swapThreadId))) {
                            throw new AssertionError("CPU samples must cover both actual threads");
                        }
                    }
                }
                """))
            subprocess.run([str(jdk/'bin/javac'), '--release', '25', '-d', str(root), str(source/'RoadProfile.java'), str(harness)], check=True, capture_output=True)
            for mode in ('on', 'wrong'):
                cache = root / mode; cache.mkdir()
                subprocess.run([str(jdk/'bin/java'), '-Dpz.drivingPerf.jfr.owner=' + 'a'*32,
                    '-XX:StartFlightRecording=name=pz-road-'+'a'*32+',settings='+str(source/'road-profile.jfc')+',filename='+str(cache/'road-runtime.jfr')+',dumponexit=true,maxsize=128m',
                    '-cp', str(root), 'net.alexredby.drivingperf.CollectorCheck', str(cache), mode], check=True, capture_output=True)
                if mode == 'wrong': self.assertFalse((cache/'road-measured.jfr').exists())

    @unittest.skipUnless(os.environ.get('PZ_JFR_TEST_GAME'), 'Set PZ_JFR_TEST_GAME to check normal probe class initialization')
    def test_normal_probe_does_not_initialize_jfr_or_cpu_helper(self):
        jdk, game = Path(os.environ['PZ_JFR_TEST_JDK']), Path(os.environ['PZ_JFR_TEST_GAME'])
        source = ROOT / 'tests/native_queue/loot-demand-drive/java'
        with tempfile.TemporaryDirectory(prefix='pz-road-jfr-off-') as temporary:
            root = Path(temporary)
            cp = os.pathsep.join(str(game/n) for n in ('projectzomboid.jar','ZombieBuddy.jar'))
            harness=root/'NormalCheck.java'
            harness.write_text(dedent("""\
                package net.alexredby.drivingperf;

                import jdk.jfr.FlightRecorder;

                public class NormalCheck {
                    public static void main(String[] args) throws Exception {
                        if (FlightRecorder.isInitialized()) {
                            throw new AssertionError("JFR already initialized");
                        }
                        Main.main(new String[0]);
                        Main.swapped();
                        Main.framed();

                        var profileField = Main.class.getDeclaredField("roadProfile");
                        profileField.setAccessible(true);
                        if (profileField.get(null) != null || FlightRecorder.isInitialized()) {
                            throw new AssertionError("normal path initialized profile");
                        }
                    }
                }
                """))
            subprocess.run([str(jdk/'bin/javac'),'--release','25','-cp',cp,'-d',str(root), str(source/'Main.java'),str(source/'RoadProfile.java'),str(ROOT/'tests/native_queue/optimizer-benchmark/java/ApproachClearance.java'),str(harness)],check=True,capture_output=True)
            subprocess.run([str(jdk/'bin/java'),'-cp',str(root)+os.pathsep+cp,'net.alexredby.drivingperf.NormalCheck'],check=True,capture_output=True)


if __name__ == '__main__': unittest.main()
