using System;
using System.Windows.Forms;
using Microsoft.Win32;

namespace RadioTray
{
    /// <summary>Avvio con Windows: la voce "RadioTray" in HKCU\...\Run (solo per l'utente, senza permessi di amministratore).</summary>
    internal static class Startup
    {
        private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string Name = "RadioTray";

        private static string Command => "\"" + Application.ExecutablePath + "\"";

        public static bool IsEnabled
        {
            get
            {
                try
                {
                    using (var k = Registry.CurrentUser.OpenSubKey(RunKey)) return k?.GetValue(Name) != null;
                }
                catch (Exception) { return false; }
            }
        }

        /// <summary>Attiva o disattiva; restituisce un errore oppure null.</summary>
        public static string Set(bool on)
        {
            try
            {
                using (var k = Registry.CurrentUser.CreateSubKey(RunKey))
                {
                    if (on) k.SetValue(Name, Command);
                    else k.DeleteValue(Name, false);
                }
                Log.Write(on ? "Avvio con Windows attivato: " + Command : "Avvio con Windows disattivato");
                return null;
            }
            catch (Exception e)
            {
                Log.Write("Avvio con Windows non modificato: " + e.Message);
                return e.Message;
            }
        }

        /// <summary>Se la cartella del programma è stata spostata, aggiorna il percorso.</summary>
        public static void Refresh()
        {
            try
            {
                using (var k = Registry.CurrentUser.OpenSubKey(RunKey, true))
                {
                    if (k?.GetValue(Name) is string current && !string.Equals(current, Command, StringComparison.OrdinalIgnoreCase))
                        k.SetValue(Name, Command);
                }
            }
            catch (Exception) { }
        }
    }
}
