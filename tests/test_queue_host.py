from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import host


VM_STAT = '''Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free: 10.
Pages inactive: 20.
Pages speculative: 3.
Pages purgeable: 999.
'''
STATS = '12 2048 125.5 /jdk/bin/java -cp projectzomboid.jar ToolkitSmokeLauncher -cachedir=/tmp/a b\n'
COMMANDS = '12 /jdk/bin/java\n'


class HostParserTests(unittest.TestCase):
    def test_vm_stat_uses_actual_page_size_and_does_not_add_purgeable(self):
        self.assertEqual(33 * 16384, host.parse_vm_stat(VM_STAT))

    def test_vm_stat_rejects_missing_and_invalid_fields(self):
        for text in ('', VM_STAT.replace('16384', '0'),
                     VM_STAT.replace('Pages free: 10.', 'Pages free: -10.'),
                     VM_STAT.replace('Pages inactive: 20.\n', ''),
                     VM_STAT.replace('Pages speculative: 3.', 'Pages speculative: unknown.')):
            with self.subTest(text=text), self.assertRaises(ValueError):
                host.parse_vm_stat(text)

    def test_process_units_and_command_with_spaces_are_preserved(self):
        self.assertEqual([{'pid': 12, 'rss': 2048 * 1024, 'cpu': 1.255,
                           'command': STATS.strip().split(None, 3)[3], 'game': True}],
                         host.parse_processes(STATS, COMMANDS))

    def test_game_detection_checks_actual_executable_not_shell_text(self):
        commands = '''1 /bin/zsh
2 /jdk/bin/java
3 /jdk/bin/javaw
4 /Applications/Project Zomboid.app/Contents/MacOS/JavaAppLauncher
5 /Applications/Other.app/Contents/MacOS/JavaAppLauncher
6 /jdk/bin/java
7 /jdk/bin/java
8 /bin/echo
10 /bin/launchctl
11 /bin/launchctl
'''
        stats = '''1 1 0 zsh -c java ToolkitSmokeLauncher
2 1 0 java zombie.network.GameServer
3 1 0 javaw zombie.gameStates.MainScreenState
4 1 0 /Applications/Project Zomboid.app/Contents/MacOS/JavaAppLauncher
5 1 0 /Applications/Other.app/Contents/MacOS/JavaAppLauncher
6 1 0 java -cp /some game/projectzomboid.jar ToolkitVideoLauncher
7 1 0 java some.OtherClass
8 1 0 echo java ToolkitSmokeLauncher
9 1 0 java ToolkitSmokeLauncher
10 1 0 launchctl asuser 501 /jdk/bin/java ToolkitSmokeLauncher -cachedir=/tmp/client
11 1 0 launchctl list
'''
        self.assertEqual([False, True, True, True, False, True, False, False, False, True, False],
                         [row['game'] for row in host.parse_processes(stats, commands)])

    def test_process_parser_rejects_bad_numbers_and_duplicate_pids(self):
        for stats in ('', '12 -1 0 java', '12 1 nan java', '12 1 inf java',
                      '12 1 -1 java', '12 x 0 java', '0 1 0 java', '12 1', STATS + STATS):
            with self.subTest(stats=stats), self.assertRaises(ValueError):
                host.parse_processes(stats, COMMANDS)
        for commands in ('', 'not-a-pid /bin/java', COMMANDS + COMMANDS):
            with self.subTest(commands=commands), self.assertRaises(ValueError):
                host.parse_processes(STATS, commands)

    def test_missing_args_are_still_counted(self):
        self.assertEqual('', host.parse_processes('12 1 0', COMMANDS)[0]['command'])


class HostProcessAgeTests(unittest.TestCase):
    NOW = 2_000_000_000_000_000_000
    MONOTONIC = 100_000_000_000

    def probe(self, elapsed, cutoff_ns, *, wall=None, monotonic=None):
        with patch.object(host, '_output', return_value=elapsed) as output, \
             patch.object(host.time, 'time_ns', side_effect=wall or [self.NOW, self.NOW + 10_000_000]), \
             patch.object(host.time, 'monotonic_ns', side_effect=monotonic or [self.MONOTONIC, self.MONOTONIC + 10_000_000]):
            result = host.process_started_after(123, cutoff_ns)
        output.assert_called_once_with(['/bin/ps', '-p', '123', '-o', 'etime='])
        return result

    def test_elapsed_formats_prove_start_after_older_cutoff(self):
        for elapsed, seconds in (('00:00', 0), ('  03:12\n', 192), ('01:02:03', 3723),
                                 ('1:02:03', 3723), ('02-08:32:18', 203538),
                                 ('123-23:59:59', 123 * 86400 + 86399)):
            with self.subTest(elapsed=elapsed):
                self.assertTrue(self.probe(elapsed, self.NOW - (seconds + 3) * 1_000_000_000))

    def test_elapsed_must_be_unique_complete_and_in_range(self):
        for elapsed in ('', ' ', '\n', '00:01\n00:02', '00:01 extra', '1', '1:2',
                        '-00:01', '00:-1', '00:60', '60:00', '24:00:00',
                        '01:60:00', '02-08:32', '2-24:00:00', '1-2-03:04:05',
                        '01:02:03:04', '１２:３４'):
            with self.subTest(elapsed=elapsed):
                self.assertFalse(self.probe(elapsed, 0))

    def test_start_lower_bound_must_be_strictly_after_cutoff(self):
        lower_bound = self.NOW - 62 * 1_000_000_000
        self.assertTrue(self.probe('01:00', lower_bound - 1))
        self.assertFalse(self.probe('01:00', lower_bound))
        self.assertFalse(self.probe('01:00', lower_bound + 1))

    def test_clock_discontinuities_and_backwards_intervals_cannot_prove_reuse(self):
        self.assertTrue(self.probe('00:01', 0,
                                  wall=[self.NOW, self.NOW + 1_010_000_000]))
        for wall, monotonic in (
            ([self.NOW, self.NOW + 1_010_000_001], [self.MONOTONIC, self.MONOTONIC + 10_000_000]),
            ([self.NOW, self.NOW - 1], [self.MONOTONIC, self.MONOTONIC + 10_000_000]),
            ([self.NOW, self.NOW + 10_000_000], [self.MONOTONIC, self.MONOTONIC - 1]),
            ([self.NOW, self.NOW + 10_000_000], [self.MONOTONIC, self.MONOTONIC + 1_010_000_001]),
        ):
            with self.subTest(wall=wall, monotonic=monotonic):
                self.assertFalse(self.probe('00:01', 0, wall=wall, monotonic=monotonic))

    def test_probe_errors_and_timeouts_cannot_prove_reuse(self):
        for error in (OSError('denied'), ValueError('invalid output'),
                      subprocess.CalledProcessError(1, 'ps'), subprocess.TimeoutExpired('ps', 10)):
            with self.subTest(error=error), patch.object(host, '_output', side_effect=error):
                self.assertFalse(host.process_started_after(123, 0))

    def test_invalid_arguments_do_not_probe(self):
        for pid, cutoff in ((0, 0), (-1, 0), (True, 0), ('123', 0), (123, True), (123, 1.5)):
            with self.subTest(pid=pid, cutoff=cutoff), patch.object(host, '_output') as output:
                self.assertFalse(host.process_started_after(pid, cutoff))
                output.assert_not_called()

    def test_elapsed_probe_keeps_existing_timeout_and_locale(self):
        with patch.object(host.subprocess, 'check_output', return_value='00:01') as output:
            self.assertTrue(host.process_started_after(123, 0))
        self.assertEqual(['/bin/ps', '-p', '123', '-o', 'etime='], output.call_args.args[0])
        self.assertEqual(10, output.call_args.kwargs['timeout'])
        self.assertEqual('C', output.call_args.kwargs['env']['LC_ALL'])


class HostSampleTests(unittest.TestCase):
    def test_mac_sample_caps_available_memory_and_reads_both_ps_inventories(self):
        with patch.object(host.sys, 'platform', 'darwin'), \
             patch.object(host.subprocess, 'check_output', side_effect=['100000 8\n', VM_STAT, STATS, COMMANDS]) as output:
            value = host.sample()
        self.assertEqual((100000, 100000, 8),
                         (value['total_memory'], value['available_memory'], value['cpu_count']))
        self.assertEqual(1.255, value['processes'][0]['cpu'])
        self.assertEqual(['/bin/ps', '-axo', 'pid=,rss=,pcpu=,args='], output.call_args_list[-2].args[0])
        self.assertEqual(['/bin/ps', '-axo', 'pid=,comm='], output.call_args_list[-1].args[0])
        self.assertEqual('C', output.call_args.kwargs['env']['LC_ALL'])

    def test_linux_sample_uses_available_memory_and_affinity(self):
        with patch.object(host.sys, 'platform', 'linux'), \
             patch.object(host.Path, 'read_text', return_value='MemTotal: 1000 kB\nMemAvailable: 350 kB\n'), \
             patch.object(host.os, 'sched_getaffinity', return_value={1, 3}, create=True), \
             patch.object(host.subprocess, 'check_output', side_effect=[STATS, COMMANDS]):
            value = host.sample()
        self.assertEqual((1024000, 358400, 2),
                         (value['total_memory'], value['available_memory'], value['cpu_count']))

    def test_linux_sample_uses_cpu_count_when_affinity_is_unavailable(self):
        with patch.object(host.sys, 'platform', 'linux'), \
             patch.object(host.Path, 'read_text', return_value='MemTotal: 1000 kB\nMemAvailable: 350 kB\n'), \
             patch.object(host.os, 'cpu_count', return_value=4), \
             patch.object(host.subprocess, 'check_output', side_effect=[STATS, COMMANDS]):
            affinity = getattr(host.os, 'sched_getaffinity', None)
            if affinity is not None:
                delattr(host.os, 'sched_getaffinity')
            try:
                self.assertEqual(4, host.sample()['cpu_count'])
            finally:
                if affinity is not None:
                    host.os.sched_getaffinity = affinity

    def test_mac_sample_errors_fail_with_resource_diagnostic(self):
        for outputs in ([OSError('sampling denied')], ['invalid'], ['0 8', VM_STAT],
                        ['10000 0', VM_STAT], ['10000 8', 'broken vm_stat'],
                        ['10000 8', VM_STAT, 'bad ps', COMMANDS],
                        [subprocess.CalledProcessError(1, 'ps', stderr='permission denied')]):
            with self.subTest(outputs=outputs), patch.object(host.sys, 'platform', 'darwin'), \
                 patch.object(host.subprocess, 'check_output', side_effect=outputs), \
                 self.assertRaisesRegex(RuntimeError, 'Cannot sample host resources') as raised:
                host.sample()
            self.assertNotIsInstance(raised.exception, host.ProbeTimeout)

    def test_probe_timeout_preserves_diagnostic_and_cause_at_each_stage(self):
        commands = [
            ['/usr/sbin/sysctl', '-n', 'hw.memsize', 'hw.logicalcpu'],
            ['/usr/bin/vm_stat'],
            ['/bin/ps', '-axo', 'pid=,rss=,pcpu=,args='],
            ['/bin/ps', '-axo', 'pid=,comm='],
        ]
        for stage, command in enumerate(commands):
            error = subprocess.TimeoutExpired(command, 10, stderr=b'probe did not finish\n')
            outputs = ['100000 8\n', VM_STAT, STATS, COMMANDS][:stage] + [error]
            with self.subTest(command=command), patch.object(host.sys, 'platform', 'darwin'), \
                 patch.object(host.subprocess, 'check_output', side_effect=outputs) as output, \
                 self.assertRaises(host.ProbeTimeout) as raised:
                host.sample()
            self.assertIs(raised.exception.__cause__, error)
            self.assertIn('Cannot sample host resources: ' + str(error), str(raised.exception))
            self.assertIn('probe did not finish', str(raised.exception))
            self.assertEqual(stage + 1, output.call_count)

    def test_partial_ps_sample_does_not_reuse_previous_capacity_or_inventory(self):
        for prefix, command in (([], 'pid=,rss=,pcpu=,args='), ([STATS], 'pid=,comm=')):
            error = subprocess.TimeoutExpired(['/bin/ps', '-axo', command], 10)
            outputs = ['100000 8', VM_STAT, STATS, COMMANDS,
                       '200000 16', VM_STAT, *prefix, error]
            with self.subTest(command=command), patch.object(host.sys, 'platform', 'darwin'), \
                 patch.object(host.subprocess, 'check_output', side_effect=outputs):
                self.assertEqual(100000, host.sample()['total_memory'])
                with self.assertRaises(host.ProbeTimeout):
                    host.sample()

    def test_keyboard_interrupt_propagates_from_probe(self):
        error = KeyboardInterrupt()
        with patch.object(host.sys, 'platform', 'darwin'), \
             patch.object(host.subprocess, 'check_output', side_effect=['100000 8', VM_STAT, error]), \
             self.assertRaises(KeyboardInterrupt) as raised:
            host.sample()
        self.assertIs(raised.exception, error)

    def test_wrapper_exec_between_inventories_still_identifies_the_game(self):
        # Args may describe launchctl just before it execs Java; the later executable name is Java.
        stats = '12 200 0 launchctl asuser 501 /jdk/bin/java ToolkitSmokeLauncher -cachedir=/tmp/client\n'
        with patch.object(host.sys, 'platform', 'darwin'), \
             patch.object(host.subprocess, 'check_output', side_effect=['100000 8', VM_STAT, stats, COMMANDS]):
            value = host.sample()
        self.assertTrue(value['processes'][0]['game'])
        self.assertEqual(stats.strip().split(None, 3)[3], value['processes'][0]['command'])

    def test_linux_missing_memory_or_access_error_fails_closed(self):
        for value in ('MemTotal: 1000 kB\n', 'MemTotal: 0 kB\nMemAvailable: 0 kB\n', OSError('denied')):
            kwargs = {'side_effect': value} if isinstance(value, OSError) else {'return_value': value}
            with self.subTest(value=value), patch.object(host.sys, 'platform', 'linux'), \
                 patch.object(host.Path, 'read_text', **kwargs), \
                 self.assertRaisesRegex(RuntimeError, 'Cannot sample host resources'):
                host.sample()

    def test_unsupported_host_fails_closed(self):
        with patch.object(host.sys, 'platform', 'win32'), \
             self.assertRaisesRegex(RuntimeError, 'unsupported platform') as raised:
            host.sample()
        self.assertNotIsInstance(raised.exception, host.ProbeTimeout)


if __name__ == '__main__':
    unittest.main()
