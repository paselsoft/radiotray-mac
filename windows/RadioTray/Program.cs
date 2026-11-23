using System;
using System.Threading;
using System.Windows.Forms;

namespace RadioTray
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            // una sola copia per utente
            using (var mutex = new Mutex(true, @"Local\RadioTray-" + Environment.UserName, out bool first))
            {
                if (!first)
                {
                    MessageBox.Show("RadioTray è già avviato: cerca l'icona nell'area di notifica, in basso a destra " +
                                    "(eventualmente sotto la freccia ^).", "RadioTray", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
                Application.ThreadException += (s, e) => Crash(e.Exception);
                AppDomain.CurrentDomain.UnhandledException += (s, e) => Log.Write("Errore non gestito: " + e.ExceptionObject);
                Log.Write($"--- RadioTray {Application.ProductVersion} su {Environment.OSVersion}, .NET {Environment.Version}");
                using (var app = new TrayApp())
                {
                    Application.Run(app);
                }
            }
        }

        private static void Crash(Exception e)
        {
            Log.Write("Errore non gestito: " + e);
            MessageBox.Show("Si è verificato un errore:\n\n" + e.Message + "\n\nI dettagli sono nel registro (Preferenze → Apri il registro).",
                            "RadioTray", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }
}
