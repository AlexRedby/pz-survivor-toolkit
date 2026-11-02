"""Exclusive headless timing leases with live JVM registration attestations."""
from contextlib import contextmanager
import ctypes
import hmac
import os
from pathlib import Path
import re
import secrets
import socket
import sys
import threading
import time

from . import admission

_CONNECTION_TIMEOUT = 1.0
_REGISTRATION_TIMEOUT = 60.0
_MAX_MESSAGE = 512


def _parent_pid(pid):
    if sys.platform == 'darwin':
        # proc_bsdinfo starts with five uint32 fields: flags/status/xstatus/pid/ppid.
        # Read the native inventory directly; a shell/ps helper is unnecessary.
        library = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
        library.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64,
                                        ctypes.c_void_p, ctypes.c_int]
        library.proc_pidinfo.restype = ctypes.c_int
        info = ctypes.create_string_buffer(136)
        size = library.proc_pidinfo(pid, 3, 0, info, len(info))  # PROC_PIDTBSDINFO
        return ctypes.c_uint32.from_buffer(info, 16).value if size == len(info) else None
    if sys.platform.startswith('linux'):
        try:
            match = re.search(r'^PPid:\s+(\d+)$', (Path('/proc') / str(pid) / 'status').read_text(), re.M)
            return int(match[1]) if match else None
        except OSError:
            return None
    if os.name != 'nt':
        return None
    from ctypes import wintypes as W

    class Entry(ctypes.Structure):
        _fields_ = [('size', W.DWORD), ('usage', W.DWORD), ('pid', W.DWORD),
                    ('heap', ctypes.c_size_t), ('module', W.DWORD), ('threads', W.DWORD),
                    ('parent', W.DWORD), ('priority', W.LONG), ('flags', W.DWORD),
                    ('exe', W.WCHAR * 260)]

    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateToolhelp32Snapshot.argtypes = [W.DWORD, W.DWORD]
    kernel.CreateToolhelp32Snapshot.restype = W.HANDLE
    kernel.Process32FirstW.argtypes = kernel.Process32NextW.argtypes = [W.HANDLE, ctypes.POINTER(Entry)]
    kernel.Process32FirstW.restype = kernel.Process32NextW.restype = W.BOOL
    kernel.CloseHandle.argtypes, kernel.CloseHandle.restype = [W.HANDLE], W.BOOL
    handle = kernel.CreateToolhelp32Snapshot(2, 0)
    if handle == ctypes.c_void_p(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        entry = Entry()
        entry.size = ctypes.sizeof(entry)
        found = kernel.Process32FirstW(handle, ctypes.byref(entry))
        while found:
            if entry.pid == pid:
                return entry.parent
            found = kernel.Process32NextW(handle, ctypes.byref(entry))
    finally:
        kernel.CloseHandle(handle)
    return None


def _owned_pid(pid, owner):
    """Reject nonexistent/unrelated PIDs, independently of the JVM ancestry guard."""
    if pid > (0xffffffff if os.name == 'nt' else 0x7fffffff):
        return False
    seen = {owner}
    deadline = time.monotonic() + 2
    for _ in range(128):
        if pid is None or pid <= 0 or pid in seen or time.monotonic() >= deadline:
            return False
        seen.add(pid)
        pid = _parent_pid(pid)
        if pid == owner:
            return True
    return False


class Registration:
    def __init__(self, bank, resources):
        self.bank = bank
        self.owner = os.getpid()
        self.registration_id = secrets.token_hex(16)
        self._token = secrets.token_hex(32)
        self._resources = resources
        self._served = {}
        self._validated = None
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._connection = None
        self._socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            self._socket.bind(('127.0.0.1', 0))
            self._socket.listen(4)
            self._socket.settimeout(.2)
            self.port = self._socket.getsockname()[1]
            self._active = True
            self._deadline = time.monotonic() + _REGISTRATION_TIMEOUT
            self._thread = threading.Thread(target=self._serve, name='pz-timing-registration', daemon=True)
            self._thread.start()
        except BaseException:
            self._socket.close()
            raise

    @property
    def java_options(self):
        budget = self._resources['budget']
        return ['-Xmx%dm' % budget['heap_mib'],
                '-XX:ActiveProcessorCount=%d' % budget['cpu_per_instance'],
                '-Dpz.timing.port=' + str(self.port), '-Dpz.timing.token=' + self._token,
                '-Dpz.timing.bank=' + self.bank, '-Dpz.timing.owner=' + str(self.owner)]

    def _serve(self):
        try:
            while not self._stop.is_set() and (self._served or time.monotonic() < self._deadline):
                try:
                    connection, address = self._socket.accept()
                except socket.timeout:
                    continue
                except OSError:
                    break
                with connection:
                    try:
                        with self._lock:
                            if self._stop.is_set():
                                continue
                            self._connection = connection
                        if address[0] != '127.0.0.1':
                            continue
                        deadline = time.monotonic() + _CONNECTION_TIMEOUT
                        data = bytearray()
                        while not self._stop.is_set() and len(data) <= _MAX_MESSAGE and not data.endswith(b'\n'):
                            remaining = deadline - time.monotonic()
                            if remaining <= 0:
                                break
                            connection.settimeout(remaining)
                            chunk = connection.recv(min(128, _MAX_MESSAGE + 1 - len(data)))
                            if not chunk:
                                break
                            data.extend(chunk)
                        if self._stop.is_set() or time.monotonic() >= deadline:
                            continue
                        match = re.fullmatch(rb'PZ_TIMING_V1\t([0-9a-f]{64})\t([A-Za-z0-9][A-Za-z0-9._-]{0,127})\t([1-9][0-9]{0,18})\n', data)
                        if match is None:
                            continue
                        token, bank, pid = match[1].decode('ascii'), match[2].decode('ascii'), int(match[3])
                        if (not hmac.compare_digest(token, self._token) or bank != self.bank
                                or not _owned_pid(pid, self.owner)):
                            continue
                        with self._lock:
                            if self._stop.is_set() or time.monotonic() >= deadline:
                                continue
                            # Each lease admits one JVM; retries by that same JVM are harmless.
                            if self._served and pid not in self._served:
                                continue
                            self._served.setdefault(pid, time.time())
                        reply = 'PZ_TIMING_OK\t%s\t%s\t%d\n' % (self.registration_id, self.bank, pid)
                        connection.settimeout(max(.001, deadline - time.monotonic()))
                        connection.sendall(reply.encode('ascii'))
                    except (OSError, ValueError):
                        continue
                    finally:
                        with self._lock:
                            if self._connection is connection:
                                self._connection = None
        finally:
            self._socket.close()

    def evidence(self):
        with self._lock:
            registered = [dict(pid=pid, registered_at=stamp) for pid, stamp in sorted(self._served.items())]
            validated = self._validated
        return dict(schema_version=1, phase='timing', bank=self.bank, owner_pid=self.owner,
                    registration_id=self.registration_id, registration_protocol='PZ_TIMING_V1',
                    registered_processes=registered, validated_pid=validated,
                    attested=validated is not None, admission=dict(self._resources),
                    limits=['Native memory and CPU reservations are estimates, not OS quotas.'])

    def validate(self, outputText):
        """Bind one exact stdout marker to a registration served by this live lease."""
        if not self._active or self.owner != os.getpid() or not self._thread.is_alive():
            raise ValueError('Timing registration is no longer live')
        if not isinstance(outputText, str):
            raise ValueError('Timing output must be text')
        markers = [line for line in outputText.splitlines() if line.startswith('TIMING_ADMISSION')]
        with self._lock:
            expected = {'TIMING_ADMISSION %s %s pid=%d' % (self.registration_id, self.bank, pid): pid
                        for pid in self._served}
            if len(markers) != 1 or markers[0] not in expected:
                raise ValueError('Missing or mismatched live TIMING_ADMISSION marker')
            self._validated = expected[markers[0]]
        return self.evidence()

    def close(self):
        self._active = False
        self._stop.set()
        with self._lock:
            connection = self._connection
        if connection is not None:
            # close() alone need not interrupt a recv() blocked in another thread.
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            connection.close()
        self._socket.close()
        self._thread.join(timeout=_CONNECTION_TIMEOUT + 3)
        if self._thread.is_alive():
            raise RuntimeError('Timing registration server failed to stop')


@contextmanager
def acquire(root, bank, wait=300, heap_mib=2048, native_mib=512, cpu=1):
    with admission.measuring(root, bank, wait, heap_mib, native_mib, cpu) as resources:
        registration = Registration(bank, resources)
        try:
            yield registration
        finally:
            registration.close()
