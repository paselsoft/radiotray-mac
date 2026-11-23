using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace RadioTray
{
    internal enum HotKey { TogglePlay = 1, Favorite, NextStation, PreviousStation, VolumeUp, VolumeDown, MediaPlayPause, MediaNext, MediaPrevious, MediaStop }

    /// <summary>
    /// Scorciatoie da tastiera valide in qualsiasi programma (Ctrl+Alt+P, F, frecce) e tasti multimediali,
    /// con RegisterHotKey: nessun permesso speciale. Se un tasto è già usato da un altro programma si salta.
    /// </summary>
    internal sealed class HotKeys : NativeWindow, IDisposable
    {
        private const int WM_HOTKEY = 0x0312;
        private const uint MOD_ALT = 0x1, MOD_CONTROL = 0x2, MOD_NOREPEAT = 0x4000;
        private readonly List<int> _registered = new List<int>();
        public event Action<HotKey> Pressed;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint vk);

        [DllImport("user32.dll")]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        public static readonly (HotKey key, uint mods, Keys vk, string text)[] All =
        {
            (HotKey.TogglePlay, MOD_CONTROL | MOD_ALT, Keys.P, "Ctrl+Alt+P   Accendi / spegni"),
            (HotKey.Favorite, MOD_CONTROL | MOD_ALT, Keys.F, "Ctrl+Alt+F   Aggiungi ai brani preferiti"),
            (HotKey.NextStation, MOD_CONTROL | MOD_ALT, Keys.Right, "Ctrl+Alt+→   Stazione successiva"),
            (HotKey.PreviousStation, MOD_CONTROL | MOD_ALT, Keys.Left, "Ctrl+Alt+←   Stazione precedente"),
            (HotKey.VolumeUp, MOD_CONTROL | MOD_ALT, Keys.Up, "Ctrl+Alt+↑   Volume +5"),
            (HotKey.VolumeDown, MOD_CONTROL | MOD_ALT, Keys.Down, "Ctrl+Alt+↓   Volume −5"),
            (HotKey.MediaPlayPause, 0, Keys.MediaPlayPause, "Tasto ⏯   Accendi / spegni"),
            (HotKey.MediaNext, 0, Keys.MediaNextTrack, "Tasto ⏭   Stazione successiva"),
            (HotKey.MediaPrevious, 0, Keys.MediaPreviousTrack, "Tasto ⏮   Stazione precedente"),
            (HotKey.MediaStop, 0, Keys.MediaStop, "Tasto ⏹   Spegni"),
        };

        public HotKeys() { CreateHandle(new CreateParams()); }

        /// <summary>Registra le scorciatoie; restituisce quelle non disponibili (già usate da altri programmi).</summary>
        public List<string> Register()
        {
            Unregister();
            var failed = new List<string>();
            foreach (var (key, mods, vk, text) in All)
            {
                if (RegisterHotKey(Handle, (int)key, mods | MOD_NOREPEAT, (uint)vk)) _registered.Add((int)key);
                else failed.Add(text);
            }
            return failed;
        }

        public void Unregister()
        {
            foreach (int id in _registered) UnregisterHotKey(Handle, id);
            _registered.Clear();
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY) Pressed?.Invoke((HotKey)m.WParam.ToInt32());
            base.WndProc(ref m);
        }

        public void Dispose()
        {
            Unregister();
            DestroyHandle();
        }
    }
}
