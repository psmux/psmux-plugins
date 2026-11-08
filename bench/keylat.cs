// Keystroke-to-screen latency probe for an attached psmux client.
//
// keylat.exe <client-pid> <nav|type> <count> <out.csv> [gap-ms]
//
// Attaches to the console of the psmux client, writes key events into its
// input buffer (WriteConsoleInput, the same path a real keyboard takes) and
// polls the console cursor until the change shows on screen.
//   nav   two side-by-side panes: sends C-l from the left pane and C-h from
//         the right one, done when the cursor crosses the middle column.
//   type  sends 'x' at a shell prompt, done when the cursor moves one column
//         right; a Backspace then restores the prompt (not timed).
// A change only counts when it is still there 40 ms later, so a cursor that
// merely passes through while a frame is drawn is not mistaken for the result.
// One sample in milliseconds per line goes to out.csv. gap-ms (default 150)
// is the pause after each sample, so a test can space keys the way a person does.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

class KeyLat {
    [StructLayout(LayoutKind.Sequential)] struct COORD { public short X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct SMALL_RECT { public short L, T, R, B; }
    [StructLayout(LayoutKind.Sequential)] struct CSBI { public COORD size, cursor; public ushort attr; public SMALL_RECT win; public COORD max; }
    [StructLayout(LayoutKind.Explicit, CharSet = CharSet.Unicode)] struct KEY_EVENT_RECORD {
        [FieldOffset(0)] public int bKeyDown; [FieldOffset(4)] public ushort wRepeatCount; [FieldOffset(6)] public ushort wVirtualKeyCode;
        [FieldOffset(8)] public ushort wVirtualScanCode; [FieldOffset(10)] public char UnicodeChar; [FieldOffset(12)] public uint dwControlKeyState; }
    [StructLayout(LayoutKind.Explicit)] struct INPUT_RECORD { [FieldOffset(0)] public ushort EventType; [FieldOffset(4)] public KEY_EVENT_RECORD KeyEvent; }
    [DllImport("kernel32.dll")] static extern bool FreeConsole();
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool AttachConsole(uint pid);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateFileW(string n, uint a, uint s, IntPtr sa, uint c, uint f, IntPtr t);
    [DllImport("kernel32.dll")] static extern bool GetConsoleScreenBufferInfo(IntPtr h, out CSBI i);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool WriteConsoleInputW(IntPtr h, INPUT_RECORD[] r, uint n, out uint w);

    static IntPtr hin, hout;

    static INPUT_RECORD Key(bool down, ushort vk, char ch, uint ctrl) {
        var r = new INPUT_RECORD(); r.EventType = 1;
        r.KeyEvent.bKeyDown = down ? 1 : 0; r.KeyEvent.wRepeatCount = 1;
        r.KeyEvent.wVirtualKeyCode = vk; r.KeyEvent.UnicodeChar = ch; r.KeyEvent.dwControlKeyState = ctrl;
        return r;
    }
    static void Press(ushort vk, char ch, uint ctrl) {
        uint w; WriteConsoleInputW(hin, new[] { Key(true, vk, ch, ctrl), Key(false, vk, ch, ctrl) }, 2, out w);
    }
    static CSBI Info() { CSBI c; GetConsoleScreenBufferInfo(hout, out c); return c; }

    // Waits until done(cursor) holds and still holds 40 ms later.
    static double WaitFor(Stopwatch sw, Func<CSBI, bool> done) {
        while (sw.ElapsedMilliseconds < 3000) {
            if (done(Info())) {
                double t = sw.Elapsed.TotalMilliseconds;
                Thread.Sleep(40);
                if (done(Info())) return t;
            }
            Thread.SpinWait(200);
        }
        return -1;
    }

    static int Main(string[] a) {
        uint pid = uint.Parse(a[0]); string mode = a[1]; int n = int.Parse(a[2]); string outPath = a[3];
        int gap = a.Length > 4 ? int.Parse(a[4]) : 150;
        FreeConsole();
        if (!AttachConsole(pid)) { File.WriteAllText(outPath, "error,attach " + Marshal.GetLastWin32Error()); return 2; }
        hin = CreateFileW("CONIN$", 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        hout = CreateFileW("CONOUT$", 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        var samples = new List<string>();
        int half = (Info().win.L + Info().win.R) / 2;
        for (int i = 0; i < n; i++) {
            var sw = new Stopwatch();
            double t;
            if (mode == "nav") {
                bool left = Info().cursor.X < half;
                sw.Start();
                if (left) Press(0x4C, '\x0C', 0x0008); else Press(0x48, '\x08', 0x0008);
                t = WaitFor(sw, c => (c.cursor.X < half) != left);
            } else {
                short x0 = Info().cursor.X;
                sw.Start();
                Press(0x58, 'x', 0);
                t = WaitFor(sw, c => c.cursor.X == x0 + 1);
                Press(0x08, '\b', 0);
                var back = Stopwatch.StartNew();
                WaitFor(back, c => c.cursor.X == x0);
            }
            samples.Add(t < 0 ? "timeout" : t.ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
            Thread.Sleep(gap);
        }
        FreeConsole();
        File.WriteAllLines(outPath, samples);
        return 0;
    }
}
