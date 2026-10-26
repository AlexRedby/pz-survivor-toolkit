# Importing this file is inert. Only waiting registers a hotkey, on Windows PowerShell 5.1.
function Get-TrialHotkeyNativeSource {
    return @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace PZTrialHotkey {
    public sealed class NativeAdapter {
        private const uint WM_HOTKEY = 0x0312;
        private const uint PM_REMOVE = 0x0001;
        private const int HotkeyId = 0x505A;
        private readonly uint ownerThread = GetCurrentThreadId();
        private bool registered;
        public int LastError { get; private set; }

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int x; public int y; }
        [StructLayout(LayoutKind.Sequential)]
        private struct MSG {
            public IntPtr hwnd;
            public uint message;
            public UIntPtr wParam;
            public IntPtr lParam;
            public uint time;
            public POINT pt;
            public uint lPrivate;
        }
        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UnregisterHotKey(IntPtr window, int id);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool PeekMessage(out MSG message, IntPtr window, uint minimum, uint maximum, uint remove);
        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

        private void AssertOwnerThread() {
            if (GetCurrentThreadId() != ownerThread)
                throw new InvalidOperationException("Capture hotkey must stay on its registering thread.");
        }
        public bool Register() {
            AssertOwnerThread();
            MSG message;
            // Ensure this thread owns a message queue before registering its thread hotkey.
            PeekMessage(out message, new IntPtr(-1), WM_HOTKEY, WM_HOTKEY, 0);
            registered = RegisterHotKey(IntPtr.Zero, HotkeyId, 0x0002 | 0x0004 | 0x4000, 0x77);
            LastError = registered ? 0 : Marshal.GetLastWin32Error();
            return registered;
        }
        public bool Poll() {
            AssertOwnerThread();
            MSG message;
            while (PeekMessage(out message, new IntPtr(-1), WM_HOTKEY, WM_HOTKEY, PM_REMOVE)) {
                if (message.wParam.ToUInt64() == (ulong)HotkeyId) return true;
            }
            return false;
        }
        public uint ForegroundPid() {
            AssertOwnerThread();
            uint processId = 0;
            IntPtr window = GetForegroundWindow();
            if (window != IntPtr.Zero) GetWindowThreadProcessId(window, out processId);
            return processId;
        }
        public void Unregister() {
            AssertOwnerThread();
            if (registered) {
                if (!UnregisterHotKey(IntPtr.Zero, HotkeyId))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not release capture hotkey.");
                registered = false;
            }
        }
    }
}
'@
}

function New-TrialHotkeyNativeAdapter {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'The capture hotkey requires Windows. No hotkey was registered.'
    }
    if (-not ('PZTrialHotkey.NativeAdapter' -as [type])) {
        Add-Type -TypeDefinition (Get-TrialHotkeyNativeSource) -ErrorAction Stop
    }
    return New-Object PZTrialHotkey.NativeAdapter
}

function Wait-TrialCaptureHotkey($Process, [string]$ExpectedExecutablePath, [DateTime]$ExpectedStartUtc) {
    $null = Assert-JfrTargetProcess $Process $ExpectedExecutablePath $ExpectedStartUtc
    $native = New-TrialHotkeyNativeAdapter
    $registered = $false
    try {
        $registered = $native.Register()
        if (-not $registered) {
            throw ('Could not register Ctrl+Shift+F8 (Windows error ' + $native.LastError + '). Another application may already use it. Close that binding and restart the trial; no capture was started.')
        }
        while ($true) {
            # Revalidate at every 100 ms poll, including while another application is foreground.
            $null = Assert-JfrTargetProcess $Process $ExpectedExecutablePath $ExpectedStartUtc
            if ($native.Poll()) {
                $foregroundPid = $native.ForegroundPid()
                if ($foregroundPid -eq $Process.Id) {
                    $null = Assert-JfrTargetProcess $Process $ExpectedExecutablePath $ExpectedStartUtc
                    return [pscustomobject]@{Utc=[DateTime]::UtcNow.ToString('o'); foregroundPid=$foregroundPid}
                }
            }
            Start-Sleep -Milliseconds 100
        }
    } finally {
        if ($registered) { $native.Unregister() }
    }
}
