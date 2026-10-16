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
                        [subprocess.TimeoutExpired('sysctl', 10)]):
            with self.subTest(outputs=outputs), patch.object(host.sys, 'platform', 'darwin'), \
                 patch.object(host.subprocess, 'check_output', side_effect=outputs), \
                 self.assertRaisesRegex(RuntimeError, 'Cannot sample host resources'):
                host.sample()

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
        with patch.object(host.sys, 'platform', 'win32'), self.assertRaisesRegex(RuntimeError, 'unsupported platform'):
            host.sample()


if __name__ == '__main__':
    unittest.main()
