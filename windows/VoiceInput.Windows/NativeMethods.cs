using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace VoiceInput.Windows;

internal static class NativeMethods
{
    [DllImport("user32.dll", SetLastError = true)] internal static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] internal static extern bool UnregisterHotKey(IntPtr hwnd, int id);
    [DllImport("user32.dll")] internal static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] internal static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool GetGUIThreadInfo(uint thread, ref GuiThreadInfo info);
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern int LCMapStringEx(string locale, uint flags, string source, int sourceLength, StringBuilder destination, int destinationLength, IntPtr version, IntPtr reserved, IntPtr sortHandle);

    [StructLayout(LayoutKind.Sequential)] private struct GuiThreadInfo
    {
        public uint Size, Flags;
        public IntPtr Active, Focus, Capture, MenuOwner, MoveSize, Caret;
        public int Left, Top, Right, Bottom;
    }
    [StructLayout(LayoutKind.Sequential)] private struct KeyboardInput { public ushort Key, Scan; public uint Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] private struct MouseInput { public int X, Y; public uint Data, Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Explicit)] private struct InputUnion
    {
        [FieldOffset(0)] public KeyboardInput Keyboard;
        [FieldOffset(0)] public MouseInput Mouse;
    }
    [StructLayout(LayoutKind.Sequential)] private struct Input { public uint Type; public InputUnion Data; }
    internal readonly record struct InputTarget(IntPtr Window, uint Process, IntPtr Focus);

    internal static IntPtr FocusOf(IntPtr window)
    {
        var thread = GetWindowThreadProcessId(window, out _);
        var info = new GuiThreadInfo { Size = (uint)Marshal.SizeOf<GuiThreadInfo>() };
        return GetGUIThreadInfo(thread, ref info) ? info.Focus : IntPtr.Zero;
    }
    internal static InputTarget CaptureTarget()
    {
        var window = GetForegroundWindow();
        GetWindowThreadProcessId(window, out var process);
        return new(window, process, FocusOf(window));
    }
    internal static bool IsOriginalWindow(InputTarget target)
    {
        if (target.Window == IntPtr.Zero || target.Focus == IntPtr.Zero || !IsWindow(target.Window)) return false;
        GetWindowThreadProcessId(target.Window, out var process);
        return process == target.Process && process != Environment.ProcessId;
    }
    internal static async Task<bool> RestoreTargetAsync(InputTarget target, CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        if (!IsOriginalWindow(target)) return false;
        // Restoring a top-level window never restores an individual browser field.
        if (GetForegroundWindow() != target.Window)
        {
            ShowWindow(target.Window, 9);
            if (!SetForegroundWindow(target.Window)) return false;
            await Task.Delay(150, cancellation);
        }
        for (var i = 0; i < 30; i++)
        {
            cancellation.ThrowIfCancellationRequested();
            if ((GetAsyncKeyState(0x11) & 0x8000) == 0 && (GetAsyncKeyState(0x12) & 0x8000) == 0 && (GetAsyncKeyState(0x10) & 0x8000) == 0 && (GetAsyncKeyState(0x49) & 0x8000) == 0) return true;
            await Task.Delay(50, cancellation);
        }
        return false;
    }
    internal static bool SendPaste(InputTarget target, Func<bool> verifyElement, CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        if (!IsOriginalWindow(target) || GetForegroundWindow() != target.Window || FocusOf(target.Window) != target.Focus || !verifyElement()) return false;
        cancellation.ThrowIfCancellationRequested();
        // UIA may take time; repeat native checks after provider calls return.
        if (!IsOriginalWindow(target) || GetForegroundWindow() != target.Window || FocusOf(target.Window) != target.Focus) return false;
        var inputs = new[] { Key(0x11), Key(0x56), Key(0x56, true), Key(0x11, true) };
        var sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>());
        if (sent == inputs.Length) return true;
        // Release modifiers if the OS accepted only part of the sequence.
        SendInput(2, [Key(0x56, true), Key(0x11, true)], Marshal.SizeOf<Input>());
        return false;
    }
    private static Input Key(ushort key, bool up = false) => new() { Type = 1, Data = new InputUnion { Keyboard = new KeyboardInput { Key = key, Flags = up ? 2u : 0 } } };
    internal static string ToSimplified(string text)
    {
        var needed = LCMapStringEx("zh-CN", 0x02000000, text, text.Length, new StringBuilder(), 0, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
        if (needed == 0) return text;
        var buffer = new StringBuilder(needed);
        if (LCMapStringEx("zh-CN", 0x02000000, text, text.Length, buffer, needed, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero) == 0) return text;
        return buffer.ToString();
    }
}
