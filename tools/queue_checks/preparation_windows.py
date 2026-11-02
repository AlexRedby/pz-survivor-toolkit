"""Own preparation helpers and their descendants without assigning the runner itself.

A helper waits for a private gate before starting the requested command. Only the
runner holds the Job Object handle, so its death also kills assigned helpers and
compilers. A helper orphaned before assignment exits without doing preparation.
"""
from contextlib import contextmanager
import ctypes
import inspect
from pathlib import Path
import pickle
import subprocess
import sys
import tempfile
import time


_KILL_ON_JOB_CLOSE = 0x2000
_GATE_TIMEOUT = 10.0
_STREAM_OPTIONS = {'stdin', 'stdout', 'stderr', 'bufsize', 'text', 'encoding', 'errors',
                   'universal_newlines'}


class _BasicLimits(ctypes.Structure):
    _fields_ = [('process_time', ctypes.c_int64), ('job_time', ctypes.c_int64),
                ('flags', ctypes.c_uint32), ('minimum_working_set', ctypes.c_size_t),
                ('maximum_working_set', ctypes.c_size_t), ('active_limit', ctypes.c_uint32),
                ('affinity', ctypes.c_size_t), ('priority', ctypes.c_uint32),
                ('scheduling', ctypes.c_uint32)]


class _IOCounters(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint64) for name in
                ('read', 'write', 'other', 'read_bytes', 'write_bytes', 'other_bytes')]


class _ExtendedLimits(ctypes.Structure):
    _fields_ = [('basic', _BasicLimits), ('io', _IOCounters),
                *[(name, ctypes.c_size_t) for name in
                  ('process_memory', 'job_memory', 'peak_process', 'peak_job')]]


class _Accounting(ctypes.Structure):
    _fields_ = [(name, ctypes.c_int64) for name in
                ('user_time', 'kernel_time', 'period_user_time', 'period_kernel_time')] + [
                (name, ctypes.c_uint32) for name in
                ('faults', 'total_processes', 'active_processes', 'terminated_processes')]


def _kernel32():
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    signatures = {
        'CreateJobObjectW': ([ctypes.c_void_p, ctypes.c_wchar_p], ctypes.c_void_p),
        'SetInformationJobObject': ([ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p,
                                     ctypes.c_uint32], ctypes.c_int),
        'AssignProcessToJobObject': ([ctypes.c_void_p, ctypes.c_void_p], ctypes.c_int),
        'TerminateJobObject': ([ctypes.c_void_p, ctypes.c_uint32], ctypes.c_int),
        'QueryInformationJobObject': ([ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p,
                                       ctypes.c_uint32, ctypes.c_void_p], ctypes.c_int),
        'CloseHandle': ([ctypes.c_void_p], ctypes.c_int),
    }
    for name, (arguments, result) in signatures.items():
        function = getattr(kernel, name)
        function.argtypes, function.restype = arguments, result
    return kernel


def _windows_error():
    return ctypes.WinError(ctypes.get_last_error())


class _Job:
    def __init__(self):
        self._kernel = _kernel32()
        self._handle = self._kernel.CreateJobObjectW(None, None)
        if not self._handle:
            raise _windows_error()
        limits = _ExtendedLimits()
        limits.basic.flags = _KILL_ON_JOB_CLOSE
        if not self._kernel.SetInformationJobObject(
                self._handle, 9, ctypes.byref(limits), ctypes.sizeof(limits)):
            error = _windows_error()
            self._kernel.CloseHandle(self._handle)
            self._handle = None
            raise error

    def _assign(self, process):
        if not self._kernel.AssignProcessToJobObject(self._handle, int(process._handle)):
            raise _windows_error()

    def _terminate(self, wait=True):
        if not self._kernel.TerminateJobObject(self._handle, 1):
            raise _windows_error()
        if wait:
            self._wait_empty()

    def _wait_empty(self):
        # TerminateJobObject is asynchronous. Keep the preparation mutex until
        # accounting confirms that every owned descendant has stopped.
        while True:
            accounting = _Accounting()
            if not self._kernel.QueryInformationJobObject(
                    self._handle, 1, ctypes.byref(accounting), ctypes.sizeof(accounting), None):
                raise _windows_error()
            if not accounting.active_processes:
                return
            time.sleep(0.01)

    def close(self):
        if self._handle is not None:
            try:
                self._terminate()
            finally:
                handle, self._handle = self._handle, None
                if not self._kernel.CloseHandle(handle):
                    raise _windows_error()

    def run(self, *popenargs, input=None, capture_output=False, timeout=None, check=False, **kwargs):
        """Run an owned helper with subprocess.run's command and stream semantics."""
        if self._handle is None:
            raise RuntimeError('Preparation Job Object is closed')
        if input is not None:
            if kwargs.get('stdin') is not None:
                raise ValueError('stdin and input arguments may not both be used.')
            kwargs['stdin'] = subprocess.PIPE
        if capture_output:
            if kwargs.get('stdout') is not None or kwargs.get('stderr') is not None:
                raise ValueError('stdout and stderr arguments may not be used with capture_output.')
            kwargs['stdout'] = kwargs['stderr'] = subprocess.PIPE
        options = dict(inspect.signature(subprocess.Popen).bind(*popenargs, **kwargs).arguments)
        command = options.pop('args')
        # Keep cwd/env on the requested process. Moving them onto the Python
        # launcher changes Windows' executable search directory/environment.
        launcher = {key: options.pop(key) for key in list(options)
                    if key in _STREAM_OPTIONS}
        with tempfile.TemporaryDirectory(prefix='pz-preparation-') as temporary:
            directory = Path(temporary)
            with (directory / 'command').open('wb') as stream:
                pickle.dump((command, options), stream)
            worker = [sys.executable, str(Path(__file__).resolve()), '--worker', str(directory)]
            with subprocess.Popen(worker, **launcher) as process:
                try:
                    self._assign(process)
                    # No requested executable can run before successful assignment.
                    (directory / 'gate').touch()
                    stdout, stderr = process.communicate(input, timeout=timeout)
                except subprocess.TimeoutExpired as error:
                    self._terminate(wait=False)
                    stdout, stderr = process.communicate()
                    _release_process_handle(process)
                    self._wait_empty()
                    raise subprocess.TimeoutExpired(command, timeout, stdout, stderr) from error
                except BaseException:
                    # Includes assignment failure: the unassigned worker has no
                    # authority to start a command, and is the only direct PID killed.
                    process.kill()
                    process.wait()
                    raise
                finally:
                    if process.returncode is not None:
                        _release_process_handle(process)
            result = directory / 'result'
            if not result.exists():
                raise RuntimeError('Preparation worker exited without a result: ' + str(process.returncode))
            with result.open('rb') as stream:
                returncode, error = pickle.load(stream)
            if error is not None:
                raise error
            completed = subprocess.CompletedProcess(command, returncode, stdout, stderr)
            if check:
                completed.check_returncode()
            return completed


def _release_process_handle(process):
    # A live handle can retain Job Object accounting after the worker exits.
    # Popen.wait has already recorded returncode, so no later wait needs it.
    handle = getattr(process, "_handle", None)
    if handle is not None:
        handle.Close()


@contextmanager
def contain():
    """Close the preparation Job Object before the caller releases its lease."""
    job = _Job()
    try:
        yield job
    finally:
        job.close()


def _worker(directory, gate_timeout=_GATE_TIMEOUT):
    directory = Path(directory)
    deadline = time.monotonic() + gate_timeout
    while not (directory / 'gate').exists():
        if time.monotonic() >= deadline or not directory.is_dir():
            return 1
        time.sleep(0.01)
    # The private command is read only after the parent has assigned this worker.
    with (directory / 'command').open('rb') as stream:
        command, options = pickle.load(stream)
    try:
        # Inherit the launcher's OS standard handles, including pipes/file streams.
        returncode, error = subprocess.call(command, **options), None
    except Exception as failure:
        returncode, error = None, failure
    with (directory / 'result.tmp').open('wb') as stream:
        pickle.dump((returncode, error), stream)
    (directory / 'result.tmp').replace(directory / 'result')
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 3 or sys.argv[1] != '--worker':
        raise SystemExit('This module is launched only as a preparation worker')
    raise SystemExit(_worker(sys.argv[2]))
