"""Bounded one-client Windows Host investigation, using sealed shared preparation.

Own the client and its descendants with a Windows Job Object. No discovered user
process is ever signaled. Other suite/platform coverage is deliberately not claimed.
"""
from optimizer_profile import client_classpath
import ctypes
from ctypes import wintypes as W
import json
import os
from pathlib import Path
import subprocess
import time
from . import adapters, admission, coop
from .report import read_json, verify_manifest, write_json


def loader_agent(game, cache, selection):
    from .native import font_preload
    return ('-javaagent:' + str(Path(game) / 'ZombieBuddy.jar') + '=config_dir='
            + str(Path(cache) / 'zombie-buddy') + ',policy=deny-new,verbosity=1'
            + font_preload(cache, selection, game))


def run(root, resource_wait=300):
    from .runner import _verify_live_inputs
    root = Path(root).resolve()
    selection, runtime = read_json(root / 'selection.json'), read_json(root / 'runtime.json')
    if selection['suite'] not in ('forge', 'startup') or not coop.enabled(selection) or selection.get('clients') != 1:
        raise ValueError('Windows launch currently supports one-client forge/startup Host only')
    if selection.get('ports_auto'):
        raise ValueError('Windows investigation requires explicit --ports')
    changed = verify_manifest(root, 'source-manifest.json', True) + verify_manifest(root, 'snapshot-hashes.json')
    if changed:
        raise ValueError('\n'.join(changed))
    if (root / 'execution.json').exists() or list(root.glob('*-launch.log')):
        raise ValueError('Fresh prepared invocation required')
    _verify_live_inputs(root, selection, runtime)
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateMutexW.argtypes = [W.LPVOID, W.BOOL, W.LPCWSTR];kernel.CreateMutexW.restype = W.HANDLE
    kernel.WaitForSingleObject.argtypes = [W.HANDLE, W.DWORD];kernel.WaitForSingleObject.restype = W.DWORD
    kernel.CreateJobObjectW.argtypes = [W.LPVOID, W.LPCWSTR];kernel.CreateJobObjectW.restype = W.HANDLE
    kernel.AssignProcessToJobObject.argtypes = [W.HANDLE, W.HANDLE];kernel.AssignProcessToJobObject.restype = W.BOOL
    kernel.TerminateJobObject.argtypes = [W.HANDLE, W.UINT];kernel.TerminateJobObject.restype = W.BOOL
    kernel.CloseHandle.argtypes = [W.HANDLE];kernel.CloseHandle.restype = W.BOOL
    kernel.ReleaseMutex.argtypes = [W.HANDLE];kernel.ReleaseMutex.restype = W.BOOL
    mutex = kernel.CreateMutexW(None, False, 'Local\\PZToolkitNativeWindowsHost')
    if not mutex:
        raise ctypes.WinError(ctypes.get_last_error())
    result = kernel.WaitForSingleObject(mutex, int(resource_wait * 1000))
    if result not in (0, 0x80):
        kernel.CloseHandle(mutex)
        raise RuntimeError('Another isolated Windows Host run owns the test launch lease')
    job = None;process = None
    execution = dict(status='running', platform='win32', processes={}, limits=['one-client Host; no physical input automation'])
    try:
        class Memory(ctypes.Structure):
            _fields_ = [('length', W.DWORD), ('load', W.DWORD), *[(name, ctypes.c_ulonglong) for name in
                ('total', 'available', 'totalPage', 'availablePage', 'totalVirtual', 'availableVirtual', 'extended')]]
        memory = Memory();memory.length = ctypes.sizeof(memory)
        if not kernel.GlobalMemoryStatusEx(ctypes.byref(memory)):
            raise ctypes.WinError(ctypes.get_last_error())
        budget = admission.budget(selection)
        if memory.available - max(1024**3, memory.total // 10) < budget['memory']:
            raise RuntimeError('Insufficient available memory after the live host and safety margin; no game launched')
        admission.require_disk(root, budget['instances'])
        with admission._udp(selection['ports']):
            pass
        execution['resources'] = dict(budget=budget, available_memory=memory.available, total_memory=memory.total)
        job = kernel.CreateJobObjectW(None, None)
        if not job:
            raise ctypes.WinError(ctypes.get_last_error())
        # KILL_ON_JOB_CLOSE also cleans up if this Python invocation crashes.
        class Basic(ctypes.Structure):
            _fields_ = [('processTime', ctypes.c_longlong), ('jobTime', ctypes.c_longlong), ('flags', W.DWORD),
                        ('minWorking', ctypes.c_size_t), ('maxWorking', ctypes.c_size_t), ('active', W.DWORD),
                        ('affinity', ctypes.c_size_t), ('priority', W.DWORD), ('scheduling', W.DWORD)]
        class IO(ctypes.Structure):
            _fields_ = [(name, ctypes.c_ulonglong) for name in ('read', 'write', 'other', 'readBytes', 'writeBytes', 'otherBytes')]
        class Limits(ctypes.Structure):
            _fields_ = [('basic', Basic), ('io', IO), *[(name, ctypes.c_size_t) for name in ('processMemory', 'jobMemory', 'peakProcess', 'peakJob')]]
        limits = Limits();limits.basic.flags = 0x2000
        kernel.SetInformationJobObject.argtypes = [W.HANDLE, ctypes.c_int, W.LPVOID, W.DWORD]
        if not kernel.SetInformationJobObject(job, 9, ctypes.byref(limits), ctypes.sizeof(limits)):
            raise ctypes.WinError(ctypes.get_last_error())
        game, config = Path(runtime['game']), runtime['roles']['client1']
        cache = Path(config['cache'])
        agent = loader_agent(game, cache, selection)
        command = [runtime['java'], '-Djava.awt.headless=true', '--enable-native-access=ALL-UNNAMED',
                   '--add-exports=java.base/jdk.internal.misc=ALL-UNNAMED', '-Dzomboid.steam=0',
                   '-Djava.library.path=win64;.', '-Xmx' + str(budget['heap_mib']) + 'm', '-XX:+UseZGC',
                   '-XX:-OmitStackTraceInFastThrow', '-Dtoolkit.test.hostCache=' + str(cache),
                   '-cp', client_classpath(config), 'ToolkitSmokeLauncher',
                   '-nosteam', '-novoip', '-cachedir=' + str(cache)]
        environment = {key: value for key, value in os.environ.items() if key not in ('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS')}
        environment['JDK_JAVA_OPTIONS'] = coop.loader_options(agent)
        with (root / 'client1-launch.log').open('w', encoding='utf-8') as stream:
            process = subprocess.Popen(command, cwd=game, env=environment, stdout=stream, stderr=subprocess.STDOUT,
                                       creationflags=0x00000004)  # CREATE_SUSPENDED
            if not kernel.AssignProcessToJobObject(job, W.HANDLE(int(process._handle))):
                process.kill();process.wait()
                raise ctypes.WinError(ctypes.get_last_error())
            resume = ctypes.WinDLL('ntdll').NtResumeProcess
            resume.argtypes = [W.HANDLE];resume.restype = ctypes.c_long
            if resume(W.HANDLE(int(process._handle))) != 0:
                raise RuntimeError('Could not resume the owned job-assigned client')
            execution['processes']['client1'] = {'pid': process.pid}
            write_json(root / 'execution.json', execution)
            print('client1 PID ' + str(process.pid), flush=True)
            deadline = time.monotonic() + selection['timeout_seconds']
            adapter = adapters.get(selection['suite'])
            while time.monotonic() < deadline:
                coop.mirror_logs(root)
                text = (root / 'client1-launch.log').read_text(errors='replace')
                if '[QUEUE_TEST] HOST_CHILD ' in text and 'server' not in execution['processes']:
                    execution['processes']['server'] = {'pid': coop.child(text, process.pid), 'parent_role': 'client1',
                                                        'cache': str(root / 'client1')}
                if '[QUEUE_TEST] FAIL ' in text:
                    raise RuntimeError('Native fixture failed; inspect sealed client/server logs')
                if adapter.complete(selection, 'client1', text):
                    if 'server' not in execution['processes']:
                        raise RuntimeError('Missing owned native Host child evidence')
                    execution['status'] = 'completed';break
                if process.poll() is not None:
                    raise RuntimeError('Owned client exited before fixture completion')
                time.sleep(1)
            else:
                raise RuntimeError('Bounded native Host deadline expired')
    except (Exception, KeyboardInterrupt) as error:
        execution.update(status='failed', error=str(error))
    finally:
        if job:
            kernel.TerminateJobObject(job, 0)
        if process:
            process.wait(timeout=15)
            execution['processes'].setdefault('client1', {'pid': process.pid})['exit_code'] = process.returncode
        coop.mirror_logs(root)
        if job:
            class Accounting(ctypes.Structure):
                _fields_ = [(name, ctypes.c_longlong) for name in ('user', 'system', 'periodUser', 'periodSystem')] + [
                    (name, W.DWORD) for name in ('faults', 'total', 'active', 'terminated')]
            kernel.QueryInformationJobObject.argtypes = [W.HANDLE, ctypes.c_int, W.LPVOID, W.DWORD, W.LPVOID]
            accounting = Accounting();deadline = time.monotonic() + 15
            while True:
                if not kernel.QueryInformationJobObject(job, 1, ctypes.byref(accounting), ctypes.sizeof(accounting), None):
                    execution.update(status='failed', error='Could not audit owned Host job cleanup');break
                if accounting.active == 0:
                    execution['host_cleanup'] = {'remaining_pids': [], 'active_job_processes': 0};break
                if time.monotonic() >= deadline:
                    execution.update(status='failed', error='Owned Host job processes survived cleanup');break
                time.sleep(0.1)
            kernel.CloseHandle(job)
        kernel.ReleaseMutex(mutex);kernel.CloseHandle(mutex)
        write_json(root / 'execution.json', execution)
    return execution
